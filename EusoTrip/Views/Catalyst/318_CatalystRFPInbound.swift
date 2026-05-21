//
//  318_CatalystRFPInbound.swift
//  EusoTrip — Catalyst · RFP · Inbound (brick 318).
//
//  Pixel-match to `03 Catalyst/Dark-SVG/318 RFP Inbound.svg`.
//  Catalyst's inbound RFP queue — contract awards from shippers
//  on MATRIX-50.
//
//  Wire bindings:
//    rfpManager.getRFPs           — inbound RFP list
//    rfpManager.getRFPDetail      — detail (per-card drill is in
//                                    a follow-up commit)
//

import SwiftUI

private struct InboundRFP: Decodable, Hashable, Identifiable {
    let id: String
    let rfpNumber: String?
    let status: String?           // awarded / negotiating / pending / closed
    let pickupCity: String?
    let pickupState: String?
    let destCity: String?
    let destState: String?
    let recurring: Bool?
    let trailerType: String?
    let loadsPerWeek: Int?
    let contractWeeks: Int?
    let value: Double?
    let awardedBy: String?
    let acceptDeadlineHours: Int?
}

private struct RFPsEnvelope: Decodable {
    let rfps: [InboundRFP]?
    let items: [InboundRFP]?
    let activeRFPs: Int?
    let winRate30d: Int?
    let wonCount: Int?
    let totalCount: Int?
    let contractValue: Double?
    var rows: [InboundRFP] { rfps ?? items ?? [] }
}

struct CatalystRFPInboundScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RFPInboundBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",         isCurrent: false),
                          NavSlot(label: "Dispatch", systemImage: "rectangle.split.3x1.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct RFPInboundBody: View {
    @Environment(\.palette) private var palette

    enum Filter: String, CaseIterable {
        case all = "All", awarded = "Awarded", negotiating = "Negotiating", pending = "Pending", closed = "Closed"
    }

    @State private var envelope: RFPsEnvelope?
    @State private var filter: Filter = .all
    @State private var loading: Bool = true

    private var rfps: [InboundRFP] { envelope?.rows ?? [] }
    private var filtered: [InboundRFP] {
        guard filter != .all else { return rfps }
        return rfps.filter { ($0.status ?? "").lowercased() == filter.rawValue.lowercased() }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                kpiStrip
                filterTabs
                if loading && rfps.isEmpty {
                    LifecycleCard { Text("Loading RFPs…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if filtered.isEmpty {
                    EusoEmptyState(systemImage: "tray", title: "No RFPs in this lens", subtitle: "Shipper contract awards land here.")
                } else {
                    Text("\(rfps.count) INBOUND RFPS · RANKED BY URGENCY")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    ForEach(filtered) { rfpCard($0) }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · RFP · INBOUND").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Inbound RFPs").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("MATRIX-50 contract awards").font(EType.caption).foregroundStyle(palette.textSecondary)
            Text("\(rfps.count) RFPS · \(envelope?.activeRFPs ?? 0) ACTIVE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
        }
    }

    private var kpiStrip: some View {
        let active = envelope?.activeRFPs ?? 0
        let win = envelope?.winRate30d ?? 0
        let won = envelope?.wonCount ?? 0
        let total = envelope?.totalCount ?? 0
        let value = envelope?.contractValue ?? 0
        return HStack(spacing: Space.s2) {
            kpi("ACTIVE RFPS", "\(active)", "awarded · negotiating · pending", .blue)
            kpi("WIN RATE 30D", "\(win)%", "\(won) of \(total) awarded", .green)
            kpi("CONTRACT VALUE", "$\(Int(value / 1000))K", "12-week active", .blue)
        }
    }

    private func kpi(_ label: String, _ value: String, _ subtitle: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(color)
            Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(color.opacity(0.3)))
    }

    private var filterTabs: some View {
        HStack(spacing: 6) {
            ForEach(Filter.allCases, id: \.self) { f in
                Button { filter = f } label: {
                    Text(f.rawValue)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .foregroundStyle(filter == f ? .white : palette.textSecondary)
                        .background(filter == f ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                        .clipShape(Capsule())
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func rfpCard(_ r: InboundRFP) -> some View {
        let statusUpper = (r.status ?? "").uppercased()
        let statusColor: Color = {
            switch statusUpper {
            case "AWARDED":     return .green
            case "NEGOTIATING": return .orange
            case "PENDING":     return .blue
            case "CLOSED":      return palette.textTertiary
            default:            return palette.textSecondary
            }
        }()
        return LifecycleCard(accentGradient: statusUpper == "AWARDED") {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(r.rfpNumber ?? "LD-\(r.id)")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("DU")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(palette.bgCardSoft))
                        .foregroundStyle(palette.textTertiary)
                    HStack(spacing: 4) {
                        Text(statusUpper)
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        if let h = r.acceptDeadlineHours, h > 0, statusUpper == "AWARDED" {
                            Text("· \(h)h to accept").font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        }
                    }
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(statusColor.opacity(0.18)))
                    .foregroundStyle(statusColor)
                }
                HStack {
                    Text("\(r.pickupCity ?? "—") \(r.pickupState ?? "") → \(r.destCity ?? "—") \(r.destState ?? "")")
                        .font(EType.body.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    if r.recurring == true {
                        Text("· recurring").font(.caption).foregroundStyle(palette.textSecondary)
                    }
                }
                let parts: [String] = [
                    r.trailerType,
                    r.loadsPerWeek.map { "\($0) loads/wk" },
                    r.contractWeeks.map { "\($0)-wk contract" },
                    r.awardedBy.map { "awarded by \($0)" },
                ].compactMap { $0 }
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let v = r.value, v > 0 {
                    Text("$\(Int(v).formatted(.number))").font(.title3.weight(.heavy).monospacedDigit()).foregroundStyle(palette.textPrimary)
                }
            }
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            envelope = try await EusoTripAPI.shared.queryNoInput("rfpManager.getRFPs")
        } catch { /* */ }
    }
}

#Preview("318 RFP · Dark")  { CatalystRFPInboundScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("318 RFP · Light") { CatalystRFPInboundScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
