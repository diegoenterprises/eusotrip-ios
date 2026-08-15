//
//  309_CatalystBidsOutbound.swift
//  EusoTrip — Catalyst · Bids · Outbound (brick 309).
//
//  Pixel-match to `03 Catalyst/Dark-SVG/309 Catalyst Bids Outbound.svg`.
//  Catalyst's outbound bid pipeline on broker auctions (MATRIX-50).
//
//  Wire bindings (all real, no stubs):
//    loadBidding.getMyBids — { bids, total } envelope of raw
//                            load_bids rows (loadBidding.ts:88-116)
//    loads.getById         — client-side lane join per distinct loadId
//    loadBidding.getStats  — submitted/pending/accepted/winRate/avgBid
//                            (loadBidding.ts:200-214)
//

import SwiftUI

/// Mirrors `loadBidding.getStats` verbatim (loadBidding.ts:200-214).
/// All-optional so a partial payload nil-decodes instead of erroring;
/// the KPI strip renders an em-dash for anything missing.
private struct BidStats: Decodable, Hashable {
    let submitted: Int?
    let received: Int?
    let pending: Int?
    let accepted: Int?       // includes auto_accepted server-side
    let rejected: Int?
    let countered: Int?
    let expired: Int?
    let winRate: Int?        // 0-100, server-rounded
    let avgBid: Double?      // server Math.round of AVG(bidAmount)
    let totalWonValue: Double?
    let autoAccepted: Int?
}

struct CatalystBidsOutboundScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { OutboundBidsBody() } nav: {
            BottomNav(
                leading: CarrierNavRoute.leading(current: .loads),
                trailing: CarrierNavRoute.trailing(current: .loads),
                orbState: .idle
            )
        }
    }
}

private struct OutboundBidsBody: View {
    @Environment(\.palette) private var palette

    /// Lenses aligned to the server's real `load_bids.status` enum
    /// (pending / accepted / rejected / countered / withdrawn /
    /// expired / auto_accepted) — the old live/leading/outbid lenses
    /// matched no server value, so every filter came back empty.
    enum Filter: String, CaseIterable {
        case all = "All", pending = "Pending", countered = "Countered", won = "Won", lost = "Lost"
    }

    @State private var bids: [LoadBiddingAPI.MyBid] = []
    @State private var total: Int = 0
    @State private var lanes: [Int: LoadsAPI.LoadDetail] = [:]
    @State private var stats: BidStats?
    @State private var filter: Filter = .all
    @State private var loading: Bool = true
    @State private var loadError: String? = nil

    private var filtered: [LoadBiddingAPI.MyBid] {
        switch filter {
        case .all:       return bids
        case .pending:   return bids.filter { $0.status == "pending" }
        case .countered: return bids.filter { $0.status == "countered" }
        case .won:       return bids.filter { $0.status == "accepted" || $0.status == "auto_accepted" }
        case .lost:      return bids.filter { ["rejected", "expired", "withdrawn"].contains($0.status) }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                kpiStrip
                filterTabs
                if loading && bids.isEmpty {
                    LifecycleCard { Text("Loading bids…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError, bids.isEmpty {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if filtered.isEmpty {
                    EusoEmptyState(systemImage: "tray", title: "No bids in this lens", subtitle: "Submit a bid on a broker tender and it'll show up here.")
                } else {
                    Text("\(bids.count) OF \(total) OUTBOUND BIDS · NEWEST FIRST")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    ForEach(filtered) { bidCard($0) }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · BIDS · OUTBOUND").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Outbound Bids").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Broker auctions").font(EType.caption).foregroundStyle(palette.textSecondary)
            Text("\(total) BIDS · \(stats?.pending ?? 0) PENDING")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
        }
    }

    private var kpiStrip: some View {
        // Real getStats keys only — the old liveBids/winRate30d/avgMargin
        // names matched nothing the server emits, so every KPI nil-decoded
        // to a fabricated 0 / 0% / +$0.
        let pending = stats?.pending ?? 0
        let countered = stats?.countered ?? 0
        let winRate = stats?.winRate
        let accepted = stats?.accepted ?? 0
        let submitted = stats?.submitted ?? 0
        let avgBid = stats?.avgBid
        let wonValue = stats?.totalWonValue ?? 0
        return HStack(spacing: Space.s2) {
            kpi("PENDING", "\(pending)",
                countered > 0 ? "\(countered) countered · respond" : "open offers", .blue)
            kpi("WIN RATE", winRate.map { "\($0)%" } ?? "—",
                submitted > 0 ? "\(accepted) of \(submitted) awarded" : "no bids yet", .green)
            kpi("AVG BID", avgBid.flatMap { $0 > 0 ? "$\(Int($0))" : nil } ?? "—",
                wonValue > 0 ? "$\(Int(wonValue)) won total" : "no wins yet", .green)
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

    private func bidCard(_ b: LoadBiddingAPI.MyBid) -> some View {
        let detail = lanes[b.loadId]
        let isWon = b.status == "accepted" || b.status == "auto_accepted"
        let statusLabel = b.status == "auto_accepted" ? "AUTO-WON" : b.status.uppercased()
        let statusColor: Color = {
            switch b.status {
            case "pending":                   return .blue
            case "countered":                 return .orange
            case "accepted", "auto_accepted": return .green
            case "rejected":                  return .red
            default:                          return palette.textSecondary
            }
        }()
        let bidValue = b.bidAmount.flatMap { Double($0) }
        return LifecycleCard(accentGradient: isWon) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(detail?.loadNumber ?? "Load #\(b.loadId)")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    if let r = b.bidRound, r > 1 {
                        Text("R\(r)")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(palette.bgCardSoft))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Text(statusLabel)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(statusColor.opacity(0.18)))
                        .foregroundStyle(statusColor)
                }
                // Lane joined client-side from loads.getById — when the
                // lookup hasn't landed (or failed) there is no lane line,
                // never a fabricated one.
                if let d = detail {
                    Text(d.distance != nil && d.distance! > 0
                         ? "\(d.laneDisplay) · \(d.distanceDisplay)"
                         : d.laneDisplay)
                        .font(EType.body.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                let parts: [String] = [
                    detail?.cargoType,
                    detail?.unNumber,
                    b.equipmentType ?? detail?.equipmentType,
                    (detail?.rateDisplay).flatMap { $0 == "—" ? nil : "posted \($0)" },
                    b.expiresAt.flatMap { hoursUntil($0) }.map { "\($0)h to cutoff" },
                ].compactMap { $0 }
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let amt = bidValue {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("Bid $\(Int(amt))")
                            .font(.title3.weight(.heavy).monospacedDigit())
                            .foregroundStyle(palette.textPrimary)
                        // Delta vs the shipper's posted rate — both sides
                        // real; omitted entirely when the lane join missed.
                        if let posted = detail?.rateValue, posted > 0 {
                            let delta = amt - posted
                            Text(delta >= 0 ? "+$\(Int(delta)) vs posted" : "-$\(Int(-delta)) vs posted")
                                .font(.system(size: 10, weight: .heavy).monospacedDigit())
                                .foregroundStyle(delta >= 0 ? Color.green : Color.red)
                        }
                    }
                }
            }
        }
    }

    private func hoursUntil(_ iso: String) -> Int? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return nil }
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
        do {
            // Server ALWAYS envelopes: { bids, total } of raw load_bids
            // rows (loadBidding.ts:88-116) — the old bare-[OutboundBid]
            // decode could never succeed.
            let env = try await EusoTripAPI.shared.loadBidding.getMyBids(limit: 30)
            bids = env.bids
            total = env.total
            loadError = nil
            await joinLanes(Array(Set(env.bids.map(\.loadId))))
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Client-side lane join — getMyBids rows carry no lane columns,
    /// so hydrate each distinct load via loads.getById in parallel.
    /// Tolerant: a failed lookup just renders "Load #id" with no lane
    /// line, never a fabricated city pair.
    private func joinLanes(_ ids: [Int]) async {
        var map: [Int: LoadsAPI.LoadDetail] = [:]
        await withTaskGroup(of: (Int, LoadsAPI.LoadDetail?).self) { group in
            for id in ids {
                group.addTask {
                    let d = (try? await EusoTripAPI.shared.loads.getDetail(id: String(id))) ?? nil
                    return (id, d)
                }
            }
            for await (id, d) in group {
                if let d { map[id] = d }
            }
        }
        lanes = map
    }

    private func loadStats() async {
        do { stats = try await EusoTripAPI.shared.queryNoInput("loadBidding.getStats") } catch { /* KPI strip renders em-dash */ }
    }
}

#Preview("309 Bids · Dark")  { CatalystBidsOutboundScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("309 Bids · Light") { CatalystBidsOutboundScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
