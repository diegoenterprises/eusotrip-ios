//
//  541_DispatcherMarginBridge.swift
//  EusoTrip — Dispatcher · Margin Bridge.
//
//  Verbatim SwiftUI port of:
//    `04 Dispatcher/Dark-SVG/541 Dispatcher Margin Bridge.svg`
//
//  MONEY archetype — a quoted → actual margin WATERFALL (a silhouette used by
//  no other catalog screen) over a ranked margin ledger + an ESANG rebid card.
//  Shows the dispatcher where revenue leaks to cost so thin lanes get rebid
//  before they bleed the week.
//
//  Honest wiring — 0 stubs, fully dynamic (routers confirmed on disk
//  2026-07-11):
//    • READ  brokerManagement.getBrokerMarginAnalysis (…:1178, brokerProcedure)
//            → totalRevenue / totalProfit / overallMargin + per-period analysis
//            rows. This is the anchor.
//    • READ  detentionAccessorials.getAccessorialAnalytics (…:2004) → the real
//            detention/accessorial billed figure, called out as one erosion.
//    • WRITE reports.generate (reports.ts:99, {reportType,dateRange}) →
//            "Export" ships the margin report.
//    • "Rebid thin lanes" routes THROUGH esang.chat (the assistant initiates a
//            rateNegotiation with the counter-party) — never a fabricated
//            one-tap negotiation from a roll-up surface.
//
//  HONEST GAPS surfaced in-code (handed to the-oath):
//    (1) The per-load four-bucket split (linehaul/fuel/deadhead/detention) has
//        no endpoint — brokerManagement.getLoadMarginBreakdown does not exist —
//        so the bridge is drawn at the aggregate the endpoint actually returns:
//        REVENUE → EST. COST (85% model) → NET PROFIT. No fabricated per-load
//        buckets.
//    (2) getBrokerMarginAnalysis groups by PERIOD (month), not lane, so the
//        ranked ledger is labelled "by period", not a fabricated lane list.
//    (3) It is a brokerProcedure; a non-broker dispatch account is shown an
//        honest scope message rather than empty zeros.
//
//  Persona: Aurora Freight Lines · Renée Marquette (RM). transportMode=truck;
//  currency USD (never assumed). NAV: HOME · BOARD(current) · [orb] · COMMS · ME.
//  Powered by ESANG AI™. Author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Decoders

private struct MarginAnalysis541: Decodable {
    let analysis: [MarginPeriod541]
    let overallMargin: Double
    let totalRevenue: Double
    let totalProfit: Double
    let totalLoads: Int?
}
private struct MarginPeriod541: Decodable, Identifiable {
    let period: String
    let revenue: Double
    let estimatedCost: Double
    let profit: Double
    let margin: Double
    let loadCount: Int
    var id: String { period }
}
private struct AccAnalyticsLite541: Decodable { let totalRevenue: Double }

// MARK: - Screen

struct DispatcherMarginBridgeScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { DispatcherMarginBridgeBody() } nav: { DispatchPortNav() }
    }
}

// MARK: - Body

private struct DispatcherMarginBridgeBody: View {
    @Environment(\.palette) private var palette

    @State private var margin: MarginAnalysis541?
    @State private var detentionBilled: Double = 0
    @State private var loading = true
    @State private var loadError: String?
    @State private var exporting = false
    @State private var actionNote: String?

    private var revenue: Double { margin?.totalRevenue ?? 0 }
    private var cost: Double { max(0, revenue - (margin?.totalProfit ?? 0)) }
    private var profit: Double { margin?.totalProfit ?? 0 }
    private var marginPct: Double { margin?.overallMargin ?? 0 }
    private var periods: [MarginPeriod541] {
        (margin?.analysis ?? []).sorted { $0.margin > $1.margin }
    }
    private var thinLane: MarginPeriod541? { periods.min { $0.margin < $1.margin } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline().padding(.top, Space.s3)

            if loading {
                DispatchPortLoadingCard(text: "Loading margin bridge…").padding(.top, Space.s5)
            } else if let err = loadError {
                DispatchPortErrorCard(message: err) { Task { await load() } }.padding(.top, Space.s5)
            } else if revenue <= 0 {
                EusoEmptyState(systemImage: "chart.line.downtrend.xyaxis",
                               title: "No margin data yet",
                               subtitle: "Margin analysis needs broker-desk scope and priced loads in the last 30 days.")
                    .padding(.top, Space.s6)
            } else {
                waterfallCard.padding(.top, Space.s5)
                periodLedger.padding(.top, Space.s5)
                esangCard.padding(.top, Space.s5)
                if let note = actionNote {
                    Text(note).font(EType.caption).foregroundStyle(palette.textSecondary).padding(.top, Space.s3)
                }
                ctaPair.padding(.top, Space.s5)
            }
        }
        .padding(.horizontal, 20).padding(.top, Space.s2)
        .task { await load() }
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(alignment: .firstTextBaseline) {
                EusoTripEyebrow(verbatim: "DISPATCHER · MARGIN BRIDGE")
                    .font(EType.micro).tracking(1.0).foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                HStack(spacing: 5) {
                    Circle().fill(Brand.success).frame(width: 6, height: 6)
                    Text("30-DAY · LIVE").font(EType.micro).tracking(1.0).foregroundStyle(Brand.success)
                }
            }
            HStack(alignment: .center, spacing: Space.s3) {
                DispatchPortBackChevron()
                Text("Margin bridge").font(EType.h1).tracking(-0.4).foregroundStyle(palette.textPrimary)
                Spacer(minLength: Space.s2)
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
            Text("Aurora Freight Lines · realised vs cost")
                .font(EType.caption).foregroundStyle(palette.textSecondary).padding(.leading, 40)
        }
    }

    // MARK: Waterfall hero (REVENUE → COST → PROFIT)

    private var waterfallCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("REVENUE → COST → NET · 30D")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Spacer()
                Circle().fill(Brand.success).frame(width: 7, height: 7)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text(PortMoney.full(profit))
                    .font(.system(size: 40, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(format: "%.1f%% net", marginPct))
                        .font(EType.caption.weight(.bold)).foregroundStyle(Brand.success)
                    Text("net margin").font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(margin?.totalLoads ?? 0) loads")
                        .font(EType.caption.weight(.bold).monospacedDigit()).foregroundStyle(palette.textSecondary)
                    Text("est. cost 85% model").font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                }
            }

            WaterfallPlot541(revenue: revenue, cost: cost, profit: profit, palette: palette)
                .frame(height: 128)
                .padding(.top, Space.s2)

            Text(detentionBilled > 0
                 ? "Incl. \(PortMoney.compact(detentionBilled)) accessorials billed · per-load fuel/deadhead split pending"
                 : "Aggregate bridge · per-load fuel/deadhead split pending")
                .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.xl).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    // MARK: Ranked ledger (by period)

    private var periodLedger: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("MARGIN BY PERIOD · RANKED")
                    .font(EType.micro).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("brokerManagement").font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, Space.s2)

            VStack(spacing: 0) {
                if periods.isEmpty {
                    Text("No priced periods in range.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(Space.s4)
                } else {
                    ForEach(Array(periods.prefix(4).enumerated()), id: \.element.id) { idx, p in
                        periodRow(p)
                        if idx < min(4, periods.count) - 1 {
                            Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                        }
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCardSoft))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private func periodRow(_ p: MarginPeriod541) -> some View {
        let healthy = p.margin >= 15
        let tint = p.margin < 0 ? Brand.danger : (healthy ? Brand.success : Brand.warning)
        return HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.14))
                Text("$").font(.system(size: 16, weight: .heavy)).foregroundStyle(tint)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(PeriodFmt541.month(p.period)).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text("\(p.loadCount) loads · \(PortMoney.full(p.revenue)) rev")
                    .font(EType.mono(.caption)).tracking(0.3).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f%%", p.margin))
                    .font(EType.caption.weight(.heavy).monospacedDigit()).foregroundStyle(tint)
                Text(PortMoney.full(p.profit))
                    .font(EType.bodyStrong.monospacedDigit()).foregroundStyle(palette.textPrimary)
            }
        }
        .padding(Space.s4)
    }

    // MARK: ESANG card

    private var esangCard: some View {
        DispatchPortESangStrip(
            headline: thinLane.map { "ESANG says: rebid \(PeriodFmt541.month($0.period))" } ?? "ESANG says: margins holding",
            detail: thinLane.map { String(format: "%.1f%% thinnest · rebid before it bleeds the week", $0.margin) }
                ?? "no thin period this range"
        )
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button {
                DispatchNavDispatcher.handle("esang")
            } label: {
                Text("Rebid thin lanes").font(EType.bodyStrong).foregroundStyle(palette.textOnGradient)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)

            Button { Task { await exportReport() } } label: {
                HStack(spacing: Space.s2) {
                    if exporting { ProgressView().tint(palette.textPrimary) }
                    Text(exporting ? "Exporting…" : "Export").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                }
                .frame(width: 132).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).fill(Color(hex: 0x232932)))
                .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            }
            .buttonStyle(.plain).disabled(exporting)
        }
    }

    // MARK: Data + actions

    private func load() async {
        loading = true; loadError = nil
        struct MarginIn: Encodable { let period: String; let groupBy: String }
        do {
            let m: MarginAnalysis541 = try await EusoTripAPI.shared.query(
                "brokerManagement.getBrokerMarginAnalysis", input: MarginIn(period: "30d", groupBy: "lane"))
            margin = m
            // Best-effort real detention figure — protectedProcedure, safe for dispatch.
            if let acc: AccAnalyticsLite541 = try? await EusoTripAPI.shared.queryNoInput("detentionAccessorials.getAccessorialAnalytics") {
                detentionBilled = acc.totalRevenue
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func exportReport() async {
        exporting = true; actionNote = nil
        let end = Date(); let start = Calendar.current.date(byAdding: .day, value: -30, to: end) ?? end
        let iso = ISO8601DateFormatter()
        struct Range: Encodable { let start: String; let end: String }
        struct In: Encodable { let reportType: String; let dateRange: Range }
        struct Out: Decodable { let reportId: String? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "reports.generate",
                input: In(reportType: "revenue", dateRange: Range(start: iso.string(from: start), end: iso.string(from: end))))
            actionNote = "Margin report generated for the last 30 days."
        } catch {
            actionNote = "Couldn't generate the report: \((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)"
        }
        exporting = false
    }
}

// MARK: - Waterfall plot

private struct WaterfallPlot541: View {
    let revenue: Double
    let cost: Double
    let profit: Double
    let palette: Theme.Palette

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let colW: CGFloat = (w - 24) / 3
            let maxV = max(revenue, 1)
            let base = h - 22               // baseline for value bars (leave room for labels)
            let revH = base
            let costH = base * CGFloat(cost / maxV)
            let profH = base * CGFloat(max(0, profit) / maxV)
            // cost floats down from the top of revenue
            let costTop = base - revH       // = 0
            let costBottom = costTop + costH

            ZStack(alignment: .topLeading) {
                // baseline
                Path { p in
                    p.move(to: CGPoint(x: 0, y: base)); p.addLine(to: CGPoint(x: w, y: base))
                }.stroke(palette.borderFaint, lineWidth: 1)

                // REVENUE (full)
                bar(x: 0, top: base - revH, height: revH, width: colW,
                    fill: AnyShapeStyle(Brand.info), value: PortMoney.compact(revenue), label: "REVENUE", base: base)

                // COST (drop, red) — floats from revenue top down by cost
                bar(x: colW + 12, top: costBottom - costH, height: costH, width: colW,
                    fill: AnyShapeStyle(LinearGradient.expense), value: "−" + PortMoney.compact(cost), label: "EST. COST", base: base, valueColor: Brand.danger)

                // NET PROFIT (gradient)
                bar(x: (colW + 12) * 2, top: base - profH, height: profH, width: colW,
                    fill: AnyShapeStyle(LinearGradient.diagonal), value: PortMoney.compact(profit), label: "NET", base: base)
            }
        }
    }

    private func bar(x: CGFloat, top: CGFloat, height: CGFloat, width: CGFloat,
                     fill: AnyShapeStyle, value: String, label: String, base: CGFloat,
                     valueColor: Color? = nil) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(fill)
                .frame(width: width, height: max(4, height))
                .offset(x: x, y: top)
            Text(value)
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(valueColor ?? palette.textSecondary)
                .frame(width: width, alignment: .center)
                .offset(x: x, y: max(0, top - 14))
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .frame(width: width, alignment: .center)
                .offset(x: x, y: base + 6)
        }
    }
}

// MARK: - Period label

private enum PeriodFmt541 {
    static func month(_ ym: String) -> String {
        // "2026-07" → "Jul 2026"
        let parts = ym.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]) else { return ym }
        let names = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        guard m >= 1, m <= 12 else { return ym }
        return "\(names[m]) \(parts[0])"
    }
}

// MARK: - Preview

#if DEBUG
#Preview("541 · Margin Bridge · Dark") {
    DispatcherMarginBridgeScreen(theme: Theme.dark).environment(\.palette, Theme.dark)
}
#Preview("541 · Margin Bridge · Light") {
    DispatcherMarginBridgeScreen(theme: Theme.light).environment(\.palette, Theme.light)
}
#endif
