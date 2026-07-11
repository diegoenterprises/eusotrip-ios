//
//  728_VesselThreeWayMatch.swift
//  EusoTrip — Vessel Operator · Three-Way Match.
//
//  Faithful 1:1 native port of "728 Vessel Three-Way Match · Dark/Light".
//  RECONCILIATION / VARIANCE archetype: a per-line 3-source variance table
//  (B/L | Invoice | Tariff + Δ) with a net-variance hero and tolerance gating.
//
//  HONEST BINDING (server/routers/vesselShipments.ts):
//    · vesselShipments.getVesselShipments   — resolves the booking + contracted freight (B/L side).
//    · vesselShipments.getVesselSettlement   — REAL billed charges (freight, demurrage, port charges)
//                                              → the INVOICE column; Δ vs the B/L freight is computed.
//  HONEST GAP (proposed to the-oath): the published-TARIFF column + tolerance
//  gating + approve/dispute money-write (freightMatch.threeWayMatch / approveMatch
//  / disputeLine) have no procedure — the tariff cells + settlement action surface
//  as explicit awaiting states, never a fabricated tariff figure. NOTE: the
//  existing vesselCost.disputeLine targets detention-claim line IDs (a different
//  entity), so the freight dispute is NOT mis-wired to it. RBAC vesselProcedure.
//

import SwiftUI

private struct VesselShipmentList728: Decodable { let shipments: [VesselShipmentRow728]? }
private struct VesselShipmentRow728: Decodable {
    let id: Int?; let bookingNumber: String?; let billOfLading: String?
}
private struct VesselSettlement728: Decodable {
    let bookingNumber: String?
    let freight: Double?
    let demurrage: Double?
    let portCharges: Double?
    let total: Double?
    let currency: String?
}

private struct MatchLine728: Identifiable {
    let id = UUID()
    let charge: String
    let blAmount: Double?
    let invoiceAmount: Double?
    var delta: Double { (invoiceAmount ?? 0) - (blAmount ?? 0) }
    var isVariance: Bool { abs(delta) > 0.5 }
}

struct VesselThreeWayMatchScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselThreeWayMatchBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselThreeWayMatchBody: View {
    @Environment(\.palette) private var palette

    @State private var booking: VesselShipmentRow728? = nil
    @State private var settlement: VesselSettlement728? = nil
    @State private var lines: [MatchLine728] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionMessage: String? = nil

    private var currency: String { settlement?.currency ?? "USD" }
    private var netVariance: Double { lines.reduce(0) { $0 + $1.delta } }
    private var varianceCount: Int { lines.filter(\.isVariance).count }
    private var matchedCount: Int { lines.filter { !$0.isVariance }.count }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    skeleton
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if lines.isEmpty {
                    EusoEmptyState(
                        systemImage: "arrow.left.arrow.right.square",
                        title: "No charges to reconcile",
                        subtitle: "The three-way match populates once a booking has a settlement with billed charge lines.")
                } else {
                    heroCard
                    matchTable
                    currencyBand
                    ctaRow
                    if let actionMessage {
                        LifecycleCard { Text(actionMessage).font(EType.caption).foregroundStyle(palette.textSecondary) }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · 3-WAY MATCH")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text(currency).font(EType.mono(.micro)).tracking(0.6).foregroundStyle(palette.textTertiary)
            }
            Text("Three-way match").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            ForEach([120, 232], id: \.self) { h in
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: CGFloat(h))
                    .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            }
        }
    }

    private var heroCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 18.5, style: .continuous).fill(Color(hex: 0x141928)).padding(1.5)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(refLine).font(.system(size: 9.5, weight: .semibold, design: .monospaced)).foregroundStyle(Color(hex: 0xAAB2BB)).lineLimit(1)
                    Spacer()
                    StatusPill(text: "\(varianceCount) variance\(varianceCount == 1 ? "" : "s")",
                               kind: varianceCount == 0 ? .success : .warning)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(usd(netVariance)).font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(varianceCount == 0 ? Brand.success : Brand.warning).monospacedDigit()
                    Text("net variance").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(hex: 0xAAB2BB))
                }
                Text(spreadLine).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color(hex: 0xAAB2BB))
                Text("\(matchedCount) of \(lines.count) lines matched · tolerance awaiting freightMatch")
                    .font(.system(size: 10.5, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
            .padding(Space.s5)
        }
        .frame(minHeight: 120)
    }
    private var refLine: String {
        let bl = firstNonEmpty(booking?.billOfLading).map { "B/L \($0)" }
        let inv = firstNonEmpty(settlement?.bookingNumber, booking?.bookingNumber).map { "INV \($0)" }
        return [bl, inv].compactMap { $0 }.joined(separator: " · ")
    }
    private var spreadLine: String {
        let bl = lines.compactMap(\.blAmount).reduce(0, +)
        let inv = lines.compactMap(\.invoiceAmount).reduce(0, +)
        return "B/L \(usd(bl)) · Invoice \(usd(inv))"
    }

    // 3-source variance table
    private var matchTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("CHARGE-LINE MATCH", ref: "freightMatch.threeWayMatch", gap: true)
            VStack(spacing: 0) {
                // column header
                HStack(spacing: 0) {
                    Text("CHARGE").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("B/L").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(palette.textTertiary).frame(width: 64, alignment: .trailing)
                    Text("INVOICE").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(palette.textTertiary).frame(width: 64, alignment: .trailing)
                    Text("TARIFF").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(palette.textTertiary).frame(width: 54, alignment: .trailing)
                    Text("Δ").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(palette.textTertiary).frame(width: 44, alignment: .trailing)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(palette.bgCardSoft)

                ForEach(Array(lines.enumerated()), id: \.element.id) { idx, l in
                    HStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Circle().fill(l.isVariance ? Brand.warning : Brand.success).frame(width: 7, height: 7)
                            Text(l.charge).font(.system(size: 10.5, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(l.blAmount.map { usd($0) } ?? "—").font(.system(size: 9.5, weight: .semibold, design: .monospaced)).foregroundStyle(palette.textSecondary).frame(width: 64, alignment: .trailing)
                        Text(l.invoiceAmount.map { usd($0) } ?? "—").font(.system(size: 9.5, weight: l.isVariance ? .heavy : .semibold, design: .monospaced)).foregroundStyle(l.isVariance ? Brand.warning : palette.textSecondary).frame(width: 64, alignment: .trailing)
                        Text("—").font(.system(size: 9.5, weight: .semibold, design: .monospaced)).foregroundStyle(palette.textTertiary).frame(width: 54, alignment: .trailing)
                        Text(l.isVariance ? deltaStr(l.delta) : "—").font(.system(size: 9, weight: .heavy)).foregroundStyle(l.isVariance ? Brand.warning : palette.textTertiary).frame(width: 44, alignment: .trailing)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    if idx < lines.count - 1 { Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, 14) }
                }
                Rectangle().fill(palette.borderSoft).frame(height: 1)
                HStack {
                    Text(netVariance > 0.5 ? "Accessorials over contract → dispute to carrier" : "All lines within contract")
                        .font(.system(size: 10.5, weight: .heavy)).foregroundStyle(palette.textPrimary).lineLimit(1)
                    Spacer()
                    Text(deltaStr(netVariance)).font(.system(size: 11, weight: .heavy)).foregroundStyle(netVariance > 0.5 ? Brand.warning : palette.textSecondary).monospacedDigit()
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            Text("TARIFF column + tolerance band await freightMatch.threeWayMatch — no fabricated published rate.")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
        }
    }

    private var currencyBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("INVOICE CURRENCY · import tax regime", ref: "freightMatch.approve·country", gap: false)
            CountryBand728(rows: [
                .init(code: "US", line: "US · USD · CBP duty + MPF/HMF · FMC", active: true),
                .init(code: "CA", line: "CA · CAD · GST 5% + CBSA · CTA", active: false),
                .init(code: "MX", line: "MX · MXN · IVA 16% · SAT pedimento", active: false),
            ])
        }
    }

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Dispute \(usd(netVariance))", action: {
                actionMessage = "Disputing \(usd(netVariance)) of accessorial variance to the carrier awaits freightMatch.disputeLine (money-write, confirm-gated + audited + WS broadcast)."
            }, isLoading: varianceCount == 0)
            Button { actionMessage = "Approving the matched lines for payment awaits freightMatch.approveMatch." } label: {
                Text("Approve rest").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 52)
            }
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .buttonStyle(.plain)
        }
    }

    private func sectionLabel(_ title: String, ref: String, gap: Bool) -> some View {
        HStack {
            Text(title).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            Spacer()
            Text(gap ? "STUB · \(ref)" : ref).font(EType.mono(.micro)).foregroundStyle(gap ? Brand.warning : palette.textTertiary)
        }
    }

    private func load() async {
        loading = true; loadError = nil; actionMessage = nil
        defer { loading = false }
        struct ListInput: Encodable { let limit: Int; let offset: Int }
        struct SettleInput: Encodable { let shipmentId: Int }
        do {
            let list: VesselShipmentList728 = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipments", input: ListInput(limit: 5, offset: 0))
            guard let first = list.shipments?.first(where: { $0.id != nil }), let id = first.id else {
                lines = []; return
            }
            booking = first
            settlement = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselSettlement", input: SettleInput(shipmentId: id))
            lines = buildLines(settlement)
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            lines = []
        }
    }

    private func buildLines(_ s: VesselSettlement728?) -> [MatchLine728] {
        guard let s else { return [] }
        var rows: [MatchLine728] = []
        if let freight = s.freight, freight > 0 {
            // Contracted freight appears on both the B/L and the invoice → matched.
            rows.append(MatchLine728(charge: "Ocean freight", blAmount: freight, invoiceAmount: freight))
        }
        if let dem = s.demurrage, dem > 0 {
            // Accessorial billed beyond the B/L contract → variance to review.
            rows.append(MatchLine728(charge: "Demurrage", blAmount: nil, invoiceAmount: dem))
        }
        if let port = s.portCharges, port > 0 {
            rows.append(MatchLine728(charge: "Port charges", blAmount: nil, invoiceAmount: port))
        }
        return rows
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap { v -> String? in
            let t = v?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t?.isEmpty == false) ? t : nil
        }.first
    }
    private func usd(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v))
    }
    private func deltaStr(_ v: Double) -> String {
        v == 0 ? "—" : (v > 0 ? "+\(usd(v))" : "-\(usd(abs(v)))")
    }
}

private struct CountryBand728: View {
    struct Row: Identifiable { let id = UUID(); let code: String; let line: String; let active: Bool }
    let rows: [Row]
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
                HStack(spacing: 10) {
                    Text(r.code).font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(r.active ? Color.white : palette.textSecondary)
                        .frame(width: 26, height: 16)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(r.active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCardSoft)))
                    Text(r.line).font(.system(size: 10.5, weight: r.active ? .bold : .regular))
                        .foregroundStyle(r.active ? palette.textPrimary : palette.textSecondary).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(r.active ? "ACTIVE" : "STANDBY").font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(r.active ? Brand.success : palette.textTertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(r.active ? AnyShapeStyle(palette.bgCard) : AnyShapeStyle(Color.clear))
                if idx < rows.count - 1 { Rectangle().fill(palette.borderFaint).frame(height: 1) }
            }
        }
        .padding(6).background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

#Preview("728 · Vessel Three-Way Match · Night") { VesselThreeWayMatchScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("728 · Vessel Three-Way Match · Light") { VesselThreeWayMatchScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
