//
//  647_RailMultimodalAnalytics.swift
//  EusoTrip — Rail Engineer · Multimodal Analytics (carrier-side 30-day roll-up).
//
//  Verbatim port of wireframe "647 Rail Multimodal Analytics · Dark".
//  ANALYTICS archetype: a revenue hero (avg-transit / on-time / rail-share-QoQ),
//  a mode-split KPI strip (rail / truck / ocean / on-time, rail highlighted),
//  an itemized TOP LANES-by-volume ledger, and an ESang optimization insight.
//
//  Web parity: app/(rail)/analytics/multimodal/page.tsx
//  tRPC (REAL):
//    • revenue hero + mode-split KPI ← intermodal.getIntermodalDashboard
//          EXISTS · server/routers/intermodal.ts:341
//          → { activeShipments, avgTransitDays, modeSplit{rail,truck,vessel}, totalRevenue }
//    • TOP LANES ledger ← analytics.getLaneAnalytics
//          EXISTS · server/routers/analytics.ts:724
//          → { lanes:[{lane, loads, revenue, avgRate}], summary{...} }
//  RBAC: protectedProcedure (companyId-scoped). transportMode = rail.
//  Audit/WS: read-only analytics — no DB write, no audit row, no WS broadcast.
//
//  PORT-GAPs (real backend does not return these — rendered as live empty
//  states / dashes, NEVER fabricated):
//    • on-time % + rail-share-QoQ delta → not on either endpoint.
//    • per-mode QoQ deltas (+9pts / −6pts …) → modeSplit returns counts only.
//    • per-lane mode-mix string + transit-days + mode chip → getLaneAnalytics
//      returns lane/loads/revenue/avgRate only (no facility, no transit, no mode).
//    • ESang optimization insight copy → derived heuristically from live lanes;
//      empty state shown when no lanes returned.
//

import SwiftUI

struct RailMultimodalAnalyticsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailMultimodalAnalyticsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (decode the REAL tRPC outputs verbatim)

/// intermodal.getIntermodalDashboard → revenue hero + mode-split strip.
private struct IntermodalDashboard647: Decodable {
    let activeShipments: Int?
    let avgTransitDays: Double?
    let modeSplit: [String: Int]?
    let totalRevenue: Double?
}

/// analytics.getLaneAnalytics → top-lanes ledger.
private struct LaneAnalytics647: Decodable {
    struct Lane: Decodable, Identifiable {
        let lane: String        // e.g. "CA -> IL"
        let loads: Int?
        let revenue: Double?
        let avgRate: Double?
        var id: String { lane }
    }
    struct Summary: Decodable {
        let totalLanes: Int?
        let avgRate: Double?
        let highestVolumeLane: String?
        let fastestGrowingLane: String?
    }
    let lanes: [Lane]?
    let summary: Summary?
}

// MARK: - Body

private struct RailMultimodalAnalyticsBody: View {
    @Environment(\.palette) private var palette
    @State private var dash: IntermodalDashboard647? = nil
    @State private var laneData: LaneAnalytics647? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private var lanes: [LaneAnalytics647.Lane] { laneData?.lanes ?? [] }

    // Total volume across all returned lanes — drives the hero progress bar
    // (rail-share fraction) and the "N shipments · M lanes" subline.
    private var totalLaneLoads: Int {
        lanes.reduce(into: 0) { acc, l in acc += (l.loads ?? 0) }
    }

    // Rail share of the live mode split (rail count / total mode segments).
    // PORT-GAP-adjacent: modeSplit is a real count map, so this fraction is
    // real; the QoQ delta is NOT returned and is rendered as a dash.
    private var railShareFraction: Double {
        guard let ms = dash?.modeSplit, !ms.isEmpty else { return 0 }
        let total = ms.values.reduce(into: 0) { acc, v in acc += v }
        guard total > 0 else { return 0 }
        return Double(ms["rail"] ?? 0) / Double(total)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.top, Space.s4)
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s3)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Top bar (eyebrow · back · title · subtitle)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ RAIL ENGINEER · ANALYTICS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("RAIL · 30D")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Multimodal analytics")
                        .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text("Aurora Rail Division · all modes · 30-day")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .rotationEffect(.degrees(90))
            }
            .padding(.top, Space.s4)
        }
    }

    // MARK: - Content switch (loading / error / loaded)

    @ViewBuilder
    private var content: some View {
        if loading {
            VStack(spacing: Space.s4) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 96)
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                }
            }
            .padding(.top, Space.s5)
        } else if let err = loadError {
            VStack(alignment: .leading, spacing: Space.s4) {
                EusoEmptyState(systemImage: "chart.bar.xaxis",
                               title: "Analytics unavailable",
                               subtitle: err)
            }
            .padding(.top, Space.s5)
        } else {
            VStack(alignment: .leading, spacing: Space.s4) {
                revenueHero
                modeSplitStrip
                topLanesSection
                esangInsight
            }
            .padding(.top, Space.s4)
        }
    }

    // MARK: - Revenue hero (gradient-rimmed card)

    private var revenueHero: some View {
        let rev = dash?.totalRevenue ?? 0
        let revStr: String = rev >= 1_000_000
            ? String(format: "$%.2fM", rev / 1_000_000)
            : (rev >= 1_000 ? String(format: "$%.0fK", rev / 1_000) : String(format: "$%.0f", rev))
        let shipN = dash?.activeShipments ?? 0
        let laneN = laneData?.summary?.totalLanes ?? lanes.count
        // Real avg-transit from the dashboard (currently 0 server-side until
        // the segment-transit roll-up lands — render the live value, dash if 0).
        let avg = dash?.avgTransitDays ?? 0
        let avgStr = avg > 0 ? String(format: "%.1fd", avg) : "—"

        return ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                .fill(palette.bgCardSoft)
                .padding(1.5)

            HStack(alignment: .top, spacing: Space.s3) {
                // Left column — label · big revenue · subline · progress bar
                VStack(alignment: .leading, spacing: 0) {
                    Text("INTERMODAL REVENUE · 30D")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Text(revStr)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.top, 6)
                    Text("\(shipN) shipments · \(laneN) lanes")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.top, 4)
                    // Rail-share progress bar (rail fraction of the live mode split).
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.18))
                            Capsule().fill(LinearGradient.primary)
                                .frame(width: max(0, geo.size.width * railShareFraction))
                        }
                    }
                    .frame(width: 150, height: 6)
                    .padding(.top, 10)
                }
                Spacer(minLength: 8)
                // Right column — avg transit · on-time · rail QoQ stack
                VStack(alignment: .trailing, spacing: 0) {
                    heroStat(value: avgStr, label: "avg transit")
                    heroStat(value: onTimeStr, label: "on-time").padding(.top, Space.s3)
                    heroStat(value: railQoQStr, label: "rail QoQ").padding(.top, Space.s3)
                }
            }
            .padding(Space.s5)
        }
        .frame(minHeight: 104)
    }

    private func heroStat(value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(palette.textTertiary)
        }
    }

    // PORT-GAP: on-time % is not returned by either endpoint → dash.
    private var onTimeStr: String { "—" }
    // PORT-GAP: rail-share QoQ delta is not returned → dash.
    private var railQoQStr: String { "—" }

    // MARK: - Mode-split KPI strip (rail / truck / ocean / on-time)

    private var modeSplitStrip: some View {
        let ms = dash?.modeSplit ?? [:]
        let total = ms.values.reduce(into: 0) { acc, v in acc += v }
        let pct: (String) -> String = { key in
            guard total > 0 else { return "—" }
            return "\(Int((Double(ms[key] ?? 0) / Double(total) * 100).rounded()))%"
        }
        return HStack(spacing: Space.s2) {
            modeTile(label: "RAIL",    value: pct("rail"),   highlighted: true)
            modeTile(label: "TRUCK",   value: pct("truck"),  highlighted: false)
            modeTile(label: "OCEAN",   value: pct("vessel"), highlighted: false)
            // PORT-GAP: on-time % not on the endpoint → live dash, never faked.
            modeTile(label: "ON-TIME", value: "—",           highlighted: false)
        }
    }

    private func modeTile(label: String, value: String, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(highlighted ? Color.white.opacity(0.85) : palette.textTertiary)
            Text(value)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(highlighted ? Color.white : palette.textPrimary)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5)
                .padding(.top, 8)
            // QoQ delta row — PORT-GAP: per-mode QoQ deltas are not returned by
            // the endpoint (modeSplit gives counts only). Render an em-dash so
            // the row geometry holds without fabricating a trend.
            Text("—")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(highlighted ? Color.white.opacity(0.9) : palette.textTertiary)
                .monospacedDigit()
                .padding(.top, 4)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .background(
            Group {
                if highlighted {
                    LinearGradient.diagonal
                } else {
                    palette.bgCardSoft
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(highlighted ? Color.clear : palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Top lanes ledger

    private var topLanesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TOP LANES · BY VOLUME")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("see all ›")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, Space.s2)
            Rectangle().fill(palette.borderFaint).frame(height: 1)
                .padding(.bottom, Space.s3)

            if lanes.isEmpty {
                EusoEmptyState(systemImage: "chart.bar.doc.horizontal",
                               title: "No lane volume yet",
                               subtitle: "Delivered intermodal lanes ranked by volume will appear here once shipments settle.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(lanes.prefix(4).enumerated()), id: \.element.id) { idx, lane in
                        laneRow(lane, index: idx)
                        if idx < min(lanes.count, 4) - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                }
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func laneRow(_ lane: LaneAnalytics647.Lane, index: Int) -> some View {
        // Per the wireframe the chip color rotates by row (blue / green /
        // amber / blue). These are presentation accents, not data.
        let accents: [Color] = [Brand.blue, Brand.success, Brand.warning, Brand.blue]
        let accent = accents[index % accents.count]
        let revStr: String = {
            let r = lane.revenue ?? 0
            return r >= 1_000_000 ? String(format: "$%.1fM", r / 1_000_000)
                                  : String(format: "$%.0fK", r / 1_000)
        }()
        let (origin, dest) = laneEndpoints(lane.lane)
        return HStack(alignment: .top, spacing: Space.s3) {
            // Lane glyph chip (intermodal icon).
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(origin) → \(dest)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                // PORT-GAP: per-lane mode-mix / facility string is not returned;
                // we surface the REAL load count + avg-rate the endpoint gives.
                Text("\(lane.loads ?? 0) loads · $\(Int(lane.avgRate ?? 0))/load")
                    .font(EType.mono(.caption)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(revStr)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                // PORT-GAP: per-lane transit-days + mode chip ("3.9d · rail")
                // not returned by getLaneAnalytics → dash.
                Text("— · rail")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
    }

    /// Split the server lane string ("CA -> IL") into origin / dest labels.
    private func laneEndpoints(_ raw: String) -> (String, String) {
        let parts = raw.components(separatedBy: " -> ")
        if parts.count == 2 {
            return (parts[0].trimmingCharacters(in: .whitespaces),
                    parts[1].trimmingCharacters(in: .whitespaces))
        }
        return (raw, "")
    }

    // MARK: - ESang optimization insight

    @ViewBuilder
    private var esangInsight: some View {
        if let insight = derivedInsight {
            HStack(spacing: Space.s3) {
                OrbeSang(state: .idle, diameter: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(insight.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2).minimumScaleFactor(0.8)
                    Text(insight.subtitle)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2).minimumScaleFactor(0.85)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    /// ESang insight derived strictly from LIVE returned figures — the
    /// highest-volume lane and the real rail share. No fabricated dollar
    /// savings (the wireframe's "−$18K/mo" is not computable from the
    /// returned data, so we surface the real top lane + real rail share).
    private var derivedInsight: (title: String, subtitle: String)? {
        guard let top = lanes.first else { return nil }
        let (o, d) = laneEndpoints(top.lane)
        let sharePct = Int((railShareFraction * 100).rounded())
        let title = sharePct > 0
            ? "Rail carries \(sharePct)% of intermodal volume"
            : "Top lane by volume: \(o) → \(d)"
        let subtitle = "\(o) → \(d) leads with \(top.loads ?? 0) loads · review for intermodal shift"
        return (title, subtitle)
    }

    // MARK: - Load

    private func reload() async {
        loading = true; loadError = nil
        struct LaneIn: Encodable { let period: String }
        do {
            async let d: IntermodalDashboard647 =
                EusoTripAPI.shared.queryNoInput("intermodal.getIntermodalDashboard")
            async let l: LaneAnalytics647 =
                EusoTripAPI.shared.query("analytics.getLaneAnalytics", input: LaneIn(period: "month"))
            let (dash, lanes) = try await (d, l)
            self.dash = dash
            self.laneData = lanes
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("647 · Rail Multimodal Analytics · Night") {
    RailMultimodalAnalyticsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("647 · Rail Multimodal Analytics · Light") {
    RailMultimodalAnalyticsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
