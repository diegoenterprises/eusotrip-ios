//
//  227_ShipperSettlementDetail.swift
//  EusoTrip 2027 UI — brick 227 (shipper · settlement detail)
//
//  Detail + approve + dispute view for a single settlement. Mirrors
//  the shipper-action surface of the web `SettlementDetails.tsx`.
//  Sister brick to 206 ShipperSettlements (list view) — a tap from
//  the list lands here, an approve/dispute action flips the row in
//  the list on dismiss.
//
//  Wires:
//    • `earnings.getSettlementById` (read)
//    • `earnings.approveSettlement` (mutation)
//    • `earnings.disputeSettlement` (mutation)
//

import SwiftUI

// MARK: - Store

@MainActor
final class ShipperSettlementDetailStore: ObservableObject {
    enum Phase {
        case loading
        case loaded(ShipperSettlementsAPI.SettlementDetail)
        case error(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var working: Bool = false
    @Published var lastAction: String? = nil
    @Published var lastError: String? = nil

    let settlementId: String
    private let api: EusoTripAPI

    init(settlementId: String, api: EusoTripAPI = .shared) {
        self.settlementId = settlementId
        self.api = api
    }

    func load() async {
        phase = .loading
        do {
            let detail = try await api.shipperSettlements.getDetail(settlementId: settlementId)
            phase = .loaded(detail)
        } catch {
            phase = .error("Couldn't load settlement.")
        }
    }

    func approve() async {
        working = true
        defer { working = false }
        do {
            _ = try await api.shipperSettlements.approve(settlementId: settlementId)
            lastAction = "Settlement \(settlementId) approved."
            await load()
        } catch {
            lastError = "Couldn't approve."
        }
    }

    func dispute(reason: String) async {
        working = true
        defer { working = false }
        do {
            _ = try await api.shipperSettlements.dispute(settlementId: settlementId, reason: reason, evidence: nil)
            lastAction = "Dispute filed for \(settlementId)."
            await load()
        } catch {
            lastError = "Couldn't file dispute."
        }
    }
}

// MARK: - Brick

struct ShipperSettlementDetail: View {
    let settlementId: String
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store: ShipperSettlementDetailStore
    @State private var showDispute: Bool = false
    @State private var disputeReason: String = ""
    @State private var showAck: Bool = false

    init(settlementId: String) {
        self.settlementId = settlementId
        _store = StateObject(wrappedValue: ShipperSettlementDetailStore(settlementId: settlementId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await store.load() }
        .refreshable { await store.load() }
        .sheet(isPresented: $showDispute) { disputeSheet }
        .onChange(of: store.lastAction ?? "") { _, v in if !v.isEmpty { showAck = true } }
        .alert("Done", isPresented: $showAck, actions: {
            Button("OK") { store.lastAction = nil }
        }, message: {
            if let a = store.lastAction { Text(a) }
        })
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading:
            HStack {
                ProgressView()
                Text("Loading settlement…").font(EType.caption).foregroundStyle(palette.textSecondary)
                Spacer()
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        case .error(let m):
            errorCard(m)
        case .loaded(let s):
            VStack(alignment: .leading, spacing: Space.s4) {
                hero(s)
                ledgerCard(s)
                breakdownCard(s)
                actions(s)
            }
        }
    }

    private func hero(_ s: ShipperSettlementsAPI.SettlementDetail) -> some View {
        let style = SettlementStatusStyle.from(s.status)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · SETTLEMENT").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text(s.settlementNumber.flatMap { $0.isEmpty ? nil : $0 } ?? "#\(s.id)")
                .font(.system(size: 24, weight: .heavy)).foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(style.label.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(style.color)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(style.color.opacity(0.15)))
                    .overlay(Capsule().strokeBorder(style.color.opacity(0.5)))
                if let p = s.period, !p.isEmpty {
                    Text(p.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.7)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(palette.bgCardSoft))
                        .overlay(Capsule().strokeBorder(palette.borderFaint))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(money(s.netPay ?? s.grossPay ?? 0))
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                Text(s.netPay != nil ? "/ net" : "/ gross")
                    .font(EType.bodyStrong).foregroundStyle(palette.textSecondary)
            }
            if let n = s.driverName, !n.isEmpty {
                Label("Driver: \(n)", systemImage: "person.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func ledgerCard(_ s: ShipperSettlementsAPI.SettlementDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Gross revenue", money(s.grossRevenue ?? s.grossPay ?? 0))
            row("Driver pay",    money(s.driverPay ?? 0))
            row("Deductions",    money(s.deductions ?? s.totalDeductions ?? 0))
            row("Net pay",       money(s.netPay ?? 0), highlight: true)
            if let m = s.paymentMethod, !m.isEmpty { row("Method", m) }
            if let p = s.periodStart { row("Period start", String(p.prefix(10))) }
            if let p = s.periodEnd   { row("Period end",   String(p.prefix(10))) }
            if let p = s.paidDate, !p.isEmpty { row("Paid", String(p.prefix(10))) }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    @ViewBuilder
    private func breakdownCard(_ s: ShipperSettlementsAPI.SettlementDetail) -> some View {
        if let b = s.breakdown,
           ((b.lineHaul ?? 0) + (b.fuelSurcharge ?? 0) + (b.accessorials ?? 0)) > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Text("BREAKDOWN").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                breakdownBar(s, breakdown: b)
                row("Line haul",     money(b.lineHaul ?? 0))
                row("Fuel surcharge",money(b.fuelSurcharge ?? 0))
                row("Accessorials",  money(b.accessorials ?? 0))
            }
            .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func breakdownBar(_ s: ShipperSettlementsAPI.SettlementDetail, breakdown b: ShipperSettlementsAPI.SettlementDetail.Breakdown) -> some View {
        let lh = b.lineHaul ?? 0
        let fs = b.fuelSurcharge ?? 0
        let ac = b.accessorials ?? 0
        let total = max(lh + fs + ac, 0.0001)
        return GeometryReader { geo in
            HStack(spacing: 0) {
                Rectangle().fill(LinearGradient.diagonal).frame(width: geo.size.width * (lh / total))
                Rectangle().fill(Brand.success).frame(width: geo.size.width * (fs / total))
                Rectangle().fill(Brand.warning).frame(width: geo.size.width * (ac / total))
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
    }

    private func actions(_ s: ShipperSettlementsAPI.SettlementDetail) -> some View {
        let canApprove = (s.status ?? "").lowercased() == "pending"
        let canDispute = ["pending", "approved"].contains((s.status ?? "").lowercased())
        return VStack(spacing: 8) {
            if canApprove {
                Button {
                    Task { await store.approve() }
                } label: {
                    HStack(spacing: 8) {
                        if store.working {
                            ProgressView().scaleEffect(0.6).tint(.white)
                        } else {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 13, weight: .heavy))
                        }
                        Text(store.working ? "Working…" : "Approve settlement")
                            .font(.system(size: 14, weight: .heavy))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .foregroundStyle(.white).background(LinearGradient.diagonal).clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(store.working)
            }
            if canDispute {
                Button {
                    showDispute = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.bubble.fill").font(.system(size: 12, weight: .heavy))
                        Text("File dispute").font(.system(size: 12, weight: .heavy))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .foregroundStyle(Brand.danger).background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(Brand.danger.opacity(0.6)))
                    .clipShape(Capsule())
                }.buttonStyle(.plain)
            }
            Button {
                MeAction.fire("shipper.settlement.openOnWeb", userInfo: ["settlementId": s.id])
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 11, weight: .heavy))
                    Text("Open full ledger on web").font(.system(size: 11, weight: .heavy))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .foregroundStyle(palette.textPrimary).background(palette.bgCard)
                .overlay(Capsule().strokeBorder(palette.borderFaint))
                .clipShape(Capsule())
            }.buttonStyle(.plain)
            if let e = store.lastError {
                Text(e).font(EType.caption).foregroundStyle(Brand.danger)
            }
        }
    }

    private var disputeSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                Text("FILE DISPUTE").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Why is this settlement wrong?")
                    .font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
                Text("Your dispute is sent to the Catalyst + Eusorone audit log. Both parties can attach evidence on the web review screen.")
                    .font(EType.body).foregroundStyle(palette.textSecondary)
                ZStack(alignment: .topLeading) {
                    if disputeReason.isEmpty {
                        Text("Detention overage · accessorial missing · weight discrepancy …")
                            .font(EType.body).foregroundStyle(palette.textTertiary)
                            .padding(Space.s3)
                    }
                    TextEditor(text: $disputeReason)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(Space.s2)
                }
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                Button {
                    Task {
                        await store.dispute(reason: disputeReason)
                        showDispute = false
                        disputeReason = ""
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill").font(.system(size: 12, weight: .heavy))
                        Text("Submit dispute").font(.system(size: 14, weight: .heavy))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .foregroundStyle(.white).background(LinearGradient.diagonal).clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(disputeReason.trimmingCharacters(in: .whitespaces).count < 5)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
        }
        .background(palette.bgPage)
    }

    private func row(_ k: String, _ v: String, highlight: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary).frame(width: 130, alignment: .leading)
            Text(v).font(EType.bodyStrong)
                .foregroundStyle(highlight ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textPrimary))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func errorCard(_ m: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Retry") { Task { await store.load() } }
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.info)
        }
        .padding(Space.s3).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func money(_ v: Double) -> String {
        if v >= 1000 { return String(format: "$%.0f", v) }
        return String(format: "$%.2f", v)
    }
}

// MARK: - status

private struct SettlementStatusStyle {
    let label: String
    let color: Color

    static func from(_ raw: String?) -> SettlementStatusStyle {
        switch (raw ?? "").lowercased() {
        case "pending":    return .init(label: "Pending",    color: Brand.warning)
        case "approved":   return .init(label: "Approved",   color: Brand.success)
        case "completed":  return .init(label: "Paid",       color: Brand.success)
        case "paid":       return .init(label: "Paid",       color: Brand.success)
        case "disputed":   return .init(label: "Disputed",   color: Brand.danger)
        case "voided":     return .init(label: "Voided",     color: Brand.danger)
        default:           return .init(label: (raw ?? "Unknown").capitalized, color: .gray)
        }
    }
}

// MARK: - Previews

#Preview("Settlement · Dark") {
    ShipperSettlementDetail(settlementId: "1").preferredColorScheme(.dark)
}

#Preview("Settlement · Light") {
    ShipperSettlementDetail(settlementId: "1").preferredColorScheme(.light)
}
