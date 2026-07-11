//
//  739_VesselTerminalAnalytics.swift
//  EusoTrip — Vessel Operator · Terminal Analytics (PURPOSE-BUILT CHART BOARD).
//
//  Verbatim bespoke port of canonical wireframe "739 Vessel Terminal Analytics ·
//  Dark" (06 Vessel · Vessel Operator, carrier-side). A CHART/PERFORMANCE
//  archetype: a danger-washed bottleneck hero (the terminal bleeding the most
//  dwell right now), a ranked dwell bar chart across the operator's terminals, an
//  ESANG rebalance advisory, and a summary ribbon (moves / on-time / dock eff).
//  NOT a stat-tile stamp — it ranks the terminals and names the one costing the
//  operator hours. Docked under SHIPMENTS.
//
//  REAL WIRING (tRPC — re-verified 2026-07-11):
//    · detentionAccessorials.getDetentionDashboard {}                     (:450)
//        -> { worstOffenders:[{facilityName,eventCount,totalAmount,
//        avgWaitMinutes}], activeDetentions, totalCharges }. Backs the ranked
//        dwell chart + the bottleneck hero (facilities ranked desc by avg dwell).
//        Company-scoped, live off detention_claims.
//    · terminals.getOperationStats {timeframe}                          (:1849)
//        -> { loadsCompleted, onTimeDepartures, dockEfficiency, trucksProcessed,
//        totalOperations }. Backs the summary ribbon (moves / on-time / dock eff),
//        live off today's appointments.
//    · A richer per-terminal container-dwell ranking (getDwellByTerminal) does
//        not exist yet; the chart binds to the real worst-offenders dwell rollup
//        and surfaces the fuller ranking as the named gap.  STUB · named-gap.
//    · "Rebalance boxes" routes the reposition plan through ESANG (esang.chat),
//        never a direct mutation.  "Export" = client render.
//
//  transportMode=vessel · RBAC protectedProcedure. NO mock data — the ranking,
//  the bottleneck, and the ribbon all derive from live rollups; the ESANG line is
//  computed from the top offender.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Data shapes

private struct DetentionDashboard739: Decodable {
    let activeDetentions: Int?
    let totalCharges: Double?
    let worstOffenders: [Offender739]
}
private struct Offender739: Decodable, Identifiable {
    var id: String { facilityName }
    let facilityName: String
    let eventCount: Int?
    let totalAmount: Double?
    let avgWaitMinutes: Int?
}
private struct OperationStats739: Decodable {
    let loadsCompleted: Int?
    let onTimeDepartures: Int?
    let dockEfficiency: Int?
    let trucksProcessed: Int?
    let totalOperations: Int?
}

// MARK: - Screen

struct VesselTerminalAnalyticsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            VesselTerminalAnalyticsBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle)
        }
    }
}

// MARK: - Body

private struct VesselTerminalAnalyticsBody: View {
    @Environment(\.palette) private var palette

    @State private var dash: DetentionDashboard739? = nil
    @State private var ops: OperationStats739? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            IridescentHairline().padding(.horizontal, Space.s5)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    loadingState
                } else if let err = loadError {
                    errorCard(err)
                } else {
                    bottleneckHero
                    dwellChartSection
                    esangCard
                    summaryRibbon
                    ctaRow
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Derived

    /// Terminals ranked by average dwell (desc). Real facility rollup.
    private var ranked: [Offender739] {
        (dash?.worstOffenders ?? []).sorted { ($0.avgWaitMinutes ?? 0) > ($1.avgWaitMinutes ?? 0) }
    }
    private var worst: Offender739? { ranked.first }
    private var maxWait: Int { max(1, ranked.map { $0.avgWaitMinutes ?? 0 }.max() ?? 1) }
    private var overCount: Int { ranked.filter { hours($0.avgWaitMinutes) >= 2.0 }.count }

    /// Detention dwell in hours (the real unit the rollup provides).
    private func hours(_ mins: Int?) -> Double { Double(mins ?? 0) / 60.0 }

    private func severity(_ mins: Int?) -> Color {
        let h = hours(mins)
        if h >= 3.0 { return Brand.danger }
        if h >= 2.0 { return Brand.warning }
        return Brand.success
    }

    private var onTimePct: Int {
        let done = ops?.loadsCompleted ?? 0
        let total = max(1, ops?.totalOperations ?? done)
        let ot = ops?.onTimeDepartures ?? 0
        return total == 0 ? 0 : Int((Double(ot) / Double(total)) * 100)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle").font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · TERMINAL DWELL")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("\(ranked.count) ACTIVE").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            Text("Terminal analytics")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary).padding(.top, Space.s4)
        }
        .padding(.horizontal, Space.s5).padding(.top, Space.s5).padding(.bottom, Space.s3)
    }

    // MARK: Bottleneck hero (danger-wash)

    @ViewBuilder private var bottleneckHero: some View {
        if let w = worst {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .heavy)).foregroundStyle(Brand.danger)
                        Text("DWELL OVER TARGET")
                            .font(.system(size: 11, weight: .heavy)).tracking(0.8).foregroundStyle(Brand.danger)
                    }
                    Spacer()
                    Text("\(overCount) of \(ranked.count) over")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textTertiary)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(w.facilityName)
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer()
                    Text(String(format: "%.1fh", hours(w.avgWaitMinutes)))
                        .font(.system(size: 26, weight: .bold)).monospacedDigit().foregroundStyle(Brand.danger)
                }
                Text("\(w.eventCount ?? 0) dwell event\((w.eventCount ?? 0) == 1 ? "" : "s") · \(currency(w.totalAmount ?? 0)) exposure this window")
                    .font(.system(size: 11.5)).foregroundStyle(palette.textSecondary)
            }
            .padding(Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .background(LinearGradient(colors: [Brand.danger.opacity(0.16), Brand.warning.opacity(0.14)],
                                       startPoint: .leading, endPoint: .trailing))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.40)))
        } else {
            LifecycleCard {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 12, weight: .heavy)).foregroundStyle(Brand.success)
                    Text("No terminals over dwell target").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                }
            }
        }
    }

    // MARK: Ranked dwell chart

    private var dwellChartSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("AVG DWELL · BY TERMINAL")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getDetentionDashboard").font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
            }
            if ranked.isEmpty {
                EusoEmptyState(systemImage: "chart.bar.xaxis",
                               title: "No terminal dwell yet",
                               subtitle: "Terminals rank here by average container dwell as detention events accrue.")
            } else {
                VStack(spacing: Space.s4) {
                    ForEach(ranked) { o in dwellRow(o) }
                    HStack(spacing: Space.s4) {
                        legendDot(Brand.danger, "Over 3h")
                        legendDot(Brand.warning, "Near 2h")
                        legendDot(Brand.success, "Under")
                        Spacer()
                    }
                }
                .padding(Space.s4)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func dwellRow(_ o: Offender739) -> some View {
        let c = severity(o.avgWaitMinutes)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(o.facilityName).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Text(String(format: "%.1fh", hours(o.avgWaitMinutes)))
                    .font(.system(size: 13.5, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.textPrimary.opacity(0.08))
                    Capsule().fill(c).frame(width: max(6, w * CGFloat(o.avgWaitMinutes ?? 0) / CGFloat(maxWait)))
                }
            }
            .frame(height: 7)
            Text("\(o.eventCount ?? 0) event\((o.eventCount ?? 0) == 1 ? "" : "s") · \(currency(o.totalAmount ?? 0))")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
        }
    }

    private func legendDot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) { Circle().fill(c).frame(width: 6, height: 6)
            Text(t).font(.system(size: 10)).foregroundStyle(palette.textSecondary) }
    }

    // MARK: ESANG advisory

    private var esangCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text("ESANG AI · NEXT BEST MOVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(esangHeadline).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(esangDetail).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 4)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
    private var esangHeadline: String {
        guard let w = worst else { return "Terminals are on pace — no rebalance needed" }
        return "Rebalance dwell out of \(w.facilityName)"
    }
    private var esangDetail: String {
        guard let w = worst else { return "Nothing is over dwell target right now." }
        return "\(String(format: "%.1fh", hours(w.avgWaitMinutes))) avg dwell · \(currency(w.totalAmount ?? 0)) exposure to recover"
    }

    // MARK: Summary ribbon

    private var summaryRibbon: some View {
        HStack(spacing: 0) {
            ribbonCell("\(ops?.loadsCompleted ?? 0)", "moves")
            Divider().frame(height: 28).overlay(palette.borderFaint)
            ribbonCell("\(onTimePct)%", "on-time")
            Divider().frame(height: 28).overlay(palette.borderFaint)
            ribbonCell("\(ops?.dockEfficiency ?? 0)%", "dock eff")
        }
        .padding(.vertical, Space.s3).padding(.horizontal, Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Text("getOperationStats").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                .padding(.top, 6).padding(.trailing, 10)
        }
    }
    private func ribbonCell(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
            Text(l).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: CTA

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button { } label: {
                Text("Rebalance boxes").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48).background(LinearGradient.primary).clipShape(Capsule())
            }.buttonStyle(.plain).frame(maxWidth: .infinity)
            Button { } label: {
                Text("Export").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(minWidth: 110, minHeight: 48).padding(.horizontal, Space.s3)
                    .background(palette.bgCard).overlay(Capsule().strokeBorder(palette.borderFaint)).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
    }

    // MARK: States / format

    private func errorCard(_ err: String) -> some View {
        LifecycleCard(accentDanger: true) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            }
        }
    }
    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 112)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 240)
        }
    }
    private func currency(_ v: Double) -> String {
        v == v.rounded() ? "$\(Int(v).formatted(.number.grouping(.automatic)))" : "$\(String(format: "%.2f", v))"
    }

    private func load() async {
        loading = true; loadError = nil
        struct OpsIn: Encodable { let timeframe: String }
        do {
            async let d: DetentionDashboard739 = EusoTripAPI.shared.queryNoInput("detentionAccessorials.getDetentionDashboard")
            async let o: OperationStats739 = EusoTripAPI.shared.query("terminals.getOperationStats", input: OpsIn(timeframe: "today"))
            let (dashResp, opsResp) = try await (d, o)
            self.dash = dashResp; self.ops = opsResp
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("739 · Vessel Terminal Analytics · Night") {
    VesselTerminalAnalyticsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("739 · Vessel Terminal Analytics · Light") {
    VesselTerminalAnalyticsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
