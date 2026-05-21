//
//  309_CatalystBidsOutbound.swift
//  EusoTrip — Catalyst · Bids · Outbound (brick 309).
//
//  Pixel-match to `03 Catalyst/Dark-SVG/309 Catalyst Bids Outbound.svg`.
//  Catalyst's outbound bid pipeline on broker auctions (MATRIX-50).
//
//  Wire bindings (all real, no stubs):
//    loadBidding.getMyBids    — outbound bids
//    loadBidding.getStats     — win rate + avg margin
//

import SwiftUI

private struct OutboundBid: Decodable, Hashable, Identifiable {
    let id: String
    let loadNumber: String?
    let amount: String?
    let targetRate: String?
    let status: String?           // live / leading / outbid / won / lost
    let pickupCity: String?
    let pickupState: String?
    let destCity: String?
    let destState: String?
    let distance: Double?
    let cargoType: String?
    let hazmatClass: String?
    let escortRequired: Bool?
    let competitorCount: Int?
    let cutoffAt: String?
    let delta: String?            // "+$40" or "-$120"
}

private struct BidStats: Decodable, Hashable {
    let liveBids: Int?
    let leadingBids: Int?
    let winRate30d: Int?
    let wonCount30d: Int?
    let totalCount30d: Int?
    let avgMargin: Double?
}

struct CatalystBidsOutboundScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { OutboundBidsBody() } nav: {
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

private struct OutboundBidsBody: View {
    @Environment(\.palette) private var palette

    enum Filter: String, CaseIterable {
        case all = "All", live = "Live", leading = "Leading", outbid = "Outbid", won = "Won"
    }

    @State private var bids: [OutboundBid] = []
    @State private var stats: BidStats?
    @State private var filter: Filter = .all
    @State private var loading: Bool = true

    private var filtered: [OutboundBid] {
        guard filter != .all else { return bids }
        return bids.filter { ($0.status ?? "").lowercased() == filter.rawValue.lowercased() }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                kpiStrip
                filterTabs
                if loading && bids.isEmpty {
                    LifecycleCard { Text("Loading bids…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if filtered.isEmpty {
                    EusoEmptyState(systemImage: "tray", title: "No bids in this lens", subtitle: "Submit a bid on a broker tender and it'll show up here.")
                } else {
                    Text("\(bids.count) OUTBOUND BIDS · RANKED BY URGENCY")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    ForEach(filtered) { bidCard($0) }
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
                Text("CATALYST · BIDS · OUTBOUND").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Outbound Bids").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("MATRIX-50 broker auctions").font(EType.caption).foregroundStyle(palette.textSecondary)
            Text("\(bids.count) BIDS · \(stats?.liveBids ?? 0) LIVE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
        }
    }

    private var kpiStrip: some View {
        let live = stats?.liveBids ?? 0
        let leading = stats?.leadingBids ?? 0
        let winRate = stats?.winRate30d ?? 0
        let won = stats?.wonCount30d ?? 0
        let total = stats?.totalCount30d ?? 0
        let margin = stats?.avgMargin ?? 0
        return HStack(spacing: Space.s2) {
            kpi("LIVE BIDS", "\(live)", leading > 0 ? "\(leading) leading · contested" : "—", .blue)
            kpi("WIN RATE 30D", "\(winRate)%", "\(won) of \(total) awarded", .green)
            kpi("AVG MARGIN", (margin >= 0 ? "+" : "") + "$\(Int(margin))", "vs target rate", margin >= 0 ? .green : .red)
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

    private func bidCard(_ b: OutboundBid) -> some View {
        let statusUpper = (b.status ?? "").uppercased()
        let statusColor: Color = {
            switch statusUpper {
            case "LIVE", "LEADING": return .green
            case "OUTBID":           return .orange
            case "WON":              return .blue
            case "LOST":             return .red
            default:                 return palette.textSecondary
            }
        }()
        return LifecycleCard(accentGradient: statusUpper == "LEADING" || statusUpper == "WON") {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(b.loadNumber ?? "LD-\(b.id)")
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
                        if let delta = b.delta {
                            Text("· \(delta)").font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        }
                    }
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(statusColor.opacity(0.18)))
                    .foregroundStyle(statusColor)
                }
                Text("\(b.pickupCity ?? "—") \(b.pickupState ?? "") → \(b.destCity ?? "—") \(b.destState ?? "") · \(Int(b.distance ?? 0)) mi")
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                let parts: [String] = [
                    b.hazmatClass.map { "UN\($0)" },
                    b.escortRequired == true ? "escort required" : nil,
                    b.targetRate.map { "target $\($0)" },
                    b.competitorCount.map { "\($0) competitors" },
                    b.cutoffAt.flatMap { hoursUntil($0) }.map { "\($0)h to cutoff" },
                ].compactMap { $0 }
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let amt = b.amount {
                    Text("Bid $\(amt)").font(.title3.weight(.heavy).monospacedDigit()).foregroundStyle(palette.textPrimary)
                }
            }
        }
    }

    private func hoursUntil(_ iso: String) -> Int? {
        guard let d = ISO8601DateFormatter().date(from: iso) else { return nil }
        return max(0, Int(d.timeIntervalSinceNow / 3600))
    }

    private func load() async {
        loading = true
        async let b: Void = loadBids()
        async let s: Void = loadStats()
        _ = await (b, s)
        loading = false
    }

    private func loadBids() async {
        struct In: Encodable { let limit: Int }
        do { bids = try await EusoTripAPI.shared.query("loadBidding.getMyBids", input: In(limit: 30)) } catch { /* */ }
    }
    private func loadStats() async {
        do { stats = try await EusoTripAPI.shared.queryNoInput("loadBidding.getStats") } catch { /* */ }
    }
}

#Preview("309 Bids · Dark")  { CatalystBidsOutboundScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("309 Bids · Light") { CatalystBidsOutboundScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
