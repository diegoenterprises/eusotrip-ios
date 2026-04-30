//
//  210_ShipperAnalyticsDeepDive.swift
//  EusoTrip — Shipper · Analytics Deep Dive (brick 210).
//
//  Parity-reconciled to `02 Shipper/Code/210_ShipperAnalyticsDeepDive.swift`
//  per _PARITY_PROMPT_FOR_CODING_TEAM_2026-04-29.md. Wireframe canon
//  applied: TopBar (eyebrow + window/cohort counter), title block,
//  IridescentHairline, 5-chip time-window strip (7d/30d/90d/YTD/vs prior
//  90d), gradient-rim SPEND TREND hero card with dual-polyline chart,
//  BY LANE top-5 horizontal-bar card with tail row, 2-up cohort row
//  (BY EQUIPMENT donut + BY CATALYST stacked-bar with scorecard link).
//
//  Real data preserved: ShipperSpendingAnalyticsStore +
//  ShipperCatalystPerformanceStore + period propagation logic. Spend-
//  trend hero hydrates the headline numeral + sub-line from live data;
//  the dual-polyline chart uses canonical §11 fractional coordinates
//  until the backend ships a byMonth time series (logged EUSO-2064).
//
//  Persona canon (§11): Diego Usoro · Eusorone Technologies (companyId 1).
//  §11.4 anchor lanes (Houston→Dallas / LA→Phoenix / KC→Omaha /
//  Newark→Boston / Atlanta→Miami) drive the BY LANE rows. §13 carrier
//  mix (Eusotrans / Test Carrier / Plainview Petroleum) drives the
//  BY CATALYST rows.
//
//  Web peer: Analytics.tsx (`/shipper/analytics`).
//  Notification names: eusoShipperAnalyticsWindow,
//                      eusoShipperAnalyticsLane,
//                      eusoShipperAnalyticsScorecard.
//
//  BottomNav: Me current — out of scope per parity mandate §1.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Models (file-scoped)

private struct TimeWindow: Identifiable {
    let id: String
    let label: String
    let isWide: Bool
    let period: ShipperAPI.SpendingPeriod
}

private struct LaneRow: Identifiable {
    let id: String
    let lane: String
    let amount: String
    let fraction: CGFloat
}

private struct DonutSegment: Identifiable {
    let id: String
    let label: String
    let percent: Int
    let paint: SegmentPaint

    enum SegmentPaint { case gradient, warning, success }
}

// MARK: - Screen body

struct ShipperAnalyticsDeepDive: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var spendStore = ShipperSpendingAnalyticsStore()
    @StateObject private var catalystStore = ShipperCatalystPerformanceStore()

    @State private var selectedWindow: String = "90d"

    private let timeWindows: [TimeWindow] = [
        TimeWindow(id: "7d",  label: "7d",          isWide: false, period: .month),
        TimeWindow(id: "30d", label: "30d",         isWide: false, period: .month),
        TimeWindow(id: "90d", label: "90d",         isWide: false, period: .quarter),
        TimeWindow(id: "ytd", label: "YTD",         isWide: false, period: .year),
        TimeWindow(id: "vs",  label: "vs prior 90d", isWide: true,  period: .quarter),
    ]

    /// §11.4 anchor lanes — used until the backend ships
    /// `shippers.byLane` (EUSO-2064 / `shippers.ts:489-493`).
    private let canonicalLaneRows: [LaneRow] = [
        LaneRow(id: "houston-dallas", lane: "Houston → Dallas",  amount: "$184k", fraction: 200.0 / 220.0),
        LaneRow(id: "la-phoenix",     lane: "LA → Phoenix",      amount: "$132k", fraction: 146.0 / 220.0),
        LaneRow(id: "kc-omaha",       lane: "KC → Omaha",        amount: "$108k", fraction: 118.0 / 220.0),
        LaneRow(id: "newark-boston",  lane: "Newark → Boston",   amount: "$84k",  fraction:  92.0 / 220.0),
        LaneRow(id: "atlanta-miami",  lane: "Atlanta → Miami",   amount: "$58k",  fraction:  64.0 / 220.0),
    ]
    private let laneTailLabel = "17 more lanes"
    private let laneTailAmount = "$218k"

    /// §11.2 MATRIX-50 fuel + NH₃ mix.
    private let equipmentSegments: [DonutSegment] = [
        DonutSegment(id: "tanker", label: "Tanker", percent: 60, paint: .gradient),
        DonutSegment(id: "reefer", label: "Reefer", percent: 24, paint: .warning),
        DonutSegment(id: "dry",    label: "Dry",    percent: 16, paint: .success),
    ]

    /// 10-point fractional polylines (current + prior) — verbatim §11
    /// canon until backend ships byMonth time series.
    private let currentPoints: [CGPoint] = [
        CGPoint(x: 0.000, y: 0.683),
        CGPoint(x: 0.111, y: 0.488),
        CGPoint(x: 0.222, y: 0.610),
        CGPoint(x: 0.333, y: 0.366),
        CGPoint(x: 0.444, y: 0.463),
        CGPoint(x: 0.556, y: 0.244),
        CGPoint(x: 0.667, y: 0.390),
        CGPoint(x: 0.778, y: 0.171),
        CGPoint(x: 0.889, y: 0.317),
        CGPoint(x: 1.000, y: 0.049),
    ]
    private let priorPoints: [CGPoint] = [
        CGPoint(x: 0.000, y: 0.756),
        CGPoint(x: 0.111, y: 0.683),
        CGPoint(x: 0.222, y: 0.780),
        CGPoint(x: 0.333, y: 0.610),
        CGPoint(x: 0.444, y: 0.634),
        CGPoint(x: 0.556, y: 0.561),
        CGPoint(x: 0.667, y: 0.683),
        CGPoint(x: 0.778, y: 0.610),
        CGPoint(x: 0.889, y: 0.659),
        CGPoint(x: 1.000, y: 0.585),
    ]
    private let gridFractions: [CGFloat] = [0.268, 0.634, 1.000]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            titleBlock
                .padding(.top, Space.s3)
            IridescentHairline()
                .padding(.top, Space.s3)
                .padding(.horizontal, Space.s5)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s5) {
                    timeWindowChips
                    sectionLabel(trendEyebrow)
                    spendTrendCard
                    sectionLabel("BY LANE · TOP 5")
                    laneCard
                    cohortRow
                    insightsSection
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await refreshAll() }
        .refreshable { await refreshAll() }
    }

    private func refreshAll() async {
        async let a: Void = spendStore.refresh()
        async let b: Void = catalystStore.refresh()
        _ = await (a, b)
    }

    private var liveSpend: ShipperAPI.SpendingAnalytics? {
        spendStore.state.value ?? nil
    }

    // MARK: - TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · ANALYTICS · DEEP DIVE")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1).minimumScaleFactor(0.78)
            Spacer()
            Text("\(selectedWindow.uppercased()) · COHORTS LIVE")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Analytics")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Spend · on-time · CO₂ · cohorts byLane · byEquipment · byCatalyst")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(EType.micro).tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Time-window chip strip

    private var timeWindowChips: some View {
        HStack(spacing: 6) {
            ForEach(timeWindows) { chip in
                Button {
                    selectedWindow = chip.id
                    spendStore.setPeriod(chip.period)
                    catalystStore.setPeriod(chip.period)
                    NotificationCenter.default.post(
                        name: .eusoShipperAnalyticsWindow, object: nil,
                        userInfo: [
                            "source": "210_ShipperAnalyticsDeepDive",
                            "shipperCompanyId": session.user?.companyId ?? "1",
                            "window": chip.label,
                        ]
                    )
                    Task { await refreshAll() }
                } label: {
                    let on = (selectedWindow == chip.id)
                    Text(chip.label)
                        .font(.system(size: 12, weight: on ? .bold : .semibold))
                        .foregroundStyle(on ? .white : palette.textPrimary)
                        .frame(width: chip.isWide ? 100 : 56, height: 32)
                        .background(
                            ZStack {
                                if on {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(LinearGradient.primary)
                                } else {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(palette.bgCard)
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(palette.borderFaint, lineWidth: 1)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(chip.label) window\((selectedWindow == chip.id) ? ", currently selected" : "")")
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Spend trend hero card

    private var trendEyebrow: String {
        switch selectedWindow {
        case "7d":  return "SPEND TREND · 7D"
        case "30d": return "SPEND TREND · 30D"
        case "ytd": return "SPEND TREND · YTD"
        case "vs":  return "SPEND TREND · VS PRIOR 90D"
        default:    return "SPEND TREND · 90D"
        }
    }

    private var trendHeadline: String {
        if let s = liveSpend, s.totalSpend > 0 { return currency(s.totalSpend) }
        return "$784,210"
    }

    private var trendSubLine: String {
        if let s = liveSpend, s.loadCount > 0 {
            return "\(s.loadCount) loads · \(currency(s.avgPerLoad)) avg"
        }
        return "53 loads · $14,797 avg · −6.2% vs prior"
    }

    private var spendTrendCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)
            VStack(alignment: .leading, spacing: 0) {
                Text(trendHeadline)
                    .font(.system(size: 32, weight: .bold).monospacedDigit())
                    .foregroundStyle(LinearGradient.diagonal)
                    .padding(.top, Space.s5)
                    .padding(.horizontal, Space.s5)
                Text(trendSubLine)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.78)
                    .padding(.top, 4)
                    .padding(.horizontal, Space.s5)
                spendTrendChart
                    .frame(height: 96)
                    .padding(.top, Space.s4)
                    .padding(.horizontal, Space.s5)
                    .padding(.bottom, Space.s5)
            }
        }
        .frame(height: 200)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Spend trend, \(selectedWindow). \(trendHeadline). \(trendSubLine).")
    }

    private var spendTrendChart: some View {
        GeometryReader { geo in
            let chartHeight = geo.size.height - 18
            ZStack(alignment: .topLeading) {
                ForEach(gridFractions.indices, id: \.self) { i in
                    Path { p in
                        let y = chartHeight * gridFractions[i]
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(palette.borderFaint, lineWidth: 0.8)
                }
                PriorPolyline(points: priorPoints, areaHeight: chartHeight)
                    .stroke(palette.textTertiary,
                            style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                CurrentTrendFill(points: currentPoints, areaHeight: chartHeight)
                    .fill(LinearGradient(
                        stops: [
                            Gradient.Stop(color: Brand.magenta.opacity(0.20), location: 0.0),
                            Gradient.Stop(color: Brand.blue.opacity(0.02),    location: 1.0),
                        ],
                        startPoint: .top, endPoint: .bottom
                    ))
                CurrentTrendLine(points: currentPoints, areaHeight: chartHeight)
                    .stroke(LinearGradient.primary,
                            style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                if let last = currentPoints.last {
                    Circle()
                        .fill(palette.bgCard)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(LinearGradient.primary, lineWidth: 2))
                        .position(x: last.x * geo.size.width, y: last.y * chartHeight)
                }
                HStack {
                    Text("FEB").font(EType.micro).tracking(0.4).foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("MAR").font(EType.micro).tracking(0.4).foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text("APR").font(EType.micro).tracking(0.4).foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(height: 18)
                .offset(y: chartHeight)
            }
        }
    }

    // MARK: - BY LANE card

    private var laneCard: some View {
        VStack(spacing: 0) {
            ForEach(canonicalLaneRows.indices, id: \.self) { idx in
                laneRowView(canonicalLaneRows[idx])
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                if idx < canonicalLaneRows.count - 1 {
                    Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, 20)
                }
            }
            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, 20)
            HStack(alignment: .firstTextBaseline) {
                Text(laneTailLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text(laneTailAmount)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func laneRowView(_ row: LaneRow) -> some View {
        Button {
            NotificationCenter.default.post(
                name: .eusoShipperAnalyticsLane, object: nil,
                userInfo: [
                    "source": "210_ShipperAnalyticsDeepDive",
                    "shipperCompanyId": session.user?.companyId ?? "1",
                    "lane": row.lane,
                    "amount": row.amount,
                ]
            )
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Text(row.lane)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.78)
                    .frame(width: 110, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(palette.borderFaint)
                            .frame(height: 10)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(LinearGradient.primary)
                            .frame(width: max(0, geo.size.width * row.fraction), height: 10)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 14)
                Text(row.amount)
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 56, alignment: .trailing)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.lane), \(row.amount)")
    }

    // MARK: - 2-up cohort row

    private var cohortRow: some View {
        HStack(alignment: .top, spacing: 12) {
            equipmentCard.frame(maxWidth: .infinity)
            catalystCard.frame(maxWidth: .infinity)
        }
    }

    // MARK: - BY EQUIPMENT donut

    private var equipmentCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BY EQUIPMENT")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 14).padding(.horizontal, 14)

            ZStack {
                Circle()
                    .stroke(palette.borderFaint, lineWidth: 10)
                    .frame(width: 80, height: 80)
                ForEach(equipmentSegments.indices, id: \.self) { idx in
                    DonutSegmentShape(
                        startFraction: cumulativeStart(idx),
                        endFraction:   cumulativeEnd(idx)
                    )
                    .stroke(paintForSegment(equipmentSegments[idx]),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 80, height: 80)
                }
                VStack(spacing: 2) {
                    Text("TANKER")
                        .font(EType.micro).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                    Text("60%")
                        .font(.system(size: 14, weight: .bold).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                }
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(equipmentSegments.indices, id: \.self) { idx in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(paintForSegment(equipmentSegments[idx]))
                            .frame(width: 6, height: 6)
                        Text("\(equipmentSegments[idx].label) · \(equipmentSegments[idx].percent)%")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.4)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.top, 12).padding(.horizontal, 14).padding(.bottom, 14)
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("By equipment. Tanker 60 percent. Reefer 24 percent. Dry 16 percent.")
    }

    private func cumulativeStart(_ i: Int) -> CGFloat {
        var sum: CGFloat = 0
        for k in 0..<i {
            sum += CGFloat(equipmentSegments[k].percent) / 100.0
        }
        return sum
    }
    private func cumulativeEnd(_ i: Int) -> CGFloat {
        cumulativeStart(i) + CGFloat(equipmentSegments[i].percent) / 100.0
    }
    private func paintForSegment(_ seg: DonutSegment) -> AnyShapeStyle {
        switch seg.paint {
        case .gradient: return AnyShapeStyle(LinearGradient.primary)
        case .warning:  return AnyShapeStyle(Brand.warning)
        case .success:  return AnyShapeStyle(Brand.success)
        }
    }

    // MARK: - BY CATALYST stacked-bar card

    private var catalystCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BY CATALYST")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 14).padding(.horizontal, 14)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(catalystHeadlineCount)
                    .font(.system(size: 22, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                Text("active catalysts")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, 4).padding(.horizontal, 14)

            VStack(spacing: 14) {
                ForEach(catalystRows.indices, id: \.self) { idx in
                    catalystRowView(catalystRows[idx])
                }
            }
            .padding(.top, 14).padding(.horizontal, 14)

            Spacer(minLength: 6)

            Button {
                NotificationCenter.default.post(
                    name: .eusoShipperAnalyticsScorecard, object: nil,
                    userInfo: [
                        "source": "210_ShipperAnalyticsDeepDive",
                        "shipperCompanyId": session.user?.companyId ?? "1",
                        "destination": "213_ShipperCatalystScorecard",
                    ]
                )
            } label: {
                Text(catalystTailLink)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.bottom, 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open scorecard")
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private struct CatalystRowVM: Identifiable {
        let id: String
        let name: String
        let loads: String
        let fraction: CGFloat
    }

    private var catalystRows: [CatalystRowVM] {
        if case .loaded(let rows) = catalystStore.state, !rows.isEmpty {
            let ranked = rows.sorted { $0.totalLoads > $1.totalLoads }.prefix(3)
            let topLoads = max(ranked.first?.totalLoads ?? 0, 1)
            return ranked.map { r in
                CatalystRowVM(
                    id: r.id,
                    name: r.name.isEmpty ? "—" : r.name,
                    loads: "\(r.totalLoads)",
                    fraction: CGFloat(r.totalLoads) / CGFloat(topLoads)
                )
            }
        }
        return [
            CatalystRowVM(id: "eusotrans",  name: "Eusotrans LLC",         loads: "38", fraction: 1.0),
            CatalystRowVM(id: "test",       name: "Test Carrier Services", loads: "26", fraction: 0.68),
            CatalystRowVM(id: "plainview",  name: "Plainview Petroleum",   loads: "22", fraction: 0.58),
        ]
    }

    private var catalystHeadlineCount: String {
        if case .loaded(let rows) = catalystStore.state { return "\(rows.count)" }
        return "5"
    }

    private var catalystTailLink: String {
        if case .loaded(let rows) = catalystStore.state, rows.count > 3 {
            return "+\(rows.count - 3) more · open scorecard →"
        }
        return "+2 more · open scorecard →"
    }

    private func catalystRowView(_ row: CatalystRowVM) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.78)
                Spacer()
                Text(row.loads)
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(palette.borderFaint)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(LinearGradient.primary)
                        .frame(width: max(0, geo.size.width * row.fraction), height: 6)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 8)
        }
    }

    // MARK: - INSIGHTS section (EXTRA-OK kept)

    @ViewBuilder
    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("INSIGHTS · DERIVED")
            insightsCard
        }
    }

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ForEach(insights, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(LinearGradient.primary)
                    Text(line)
                        .font(EType.caption)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Programmatic insights derived from live data when present.
    private var insights: [String] {
        var out: [String] = []
        if let s = liveSpend, s.totalSpend > 0 {
            out.append("Total spend \(currency(s.totalSpend)) across \(s.loadCount) loads · avg \(currency(s.avgPerLoad))/load")
            if s.avgPerMile > 0 {
                out.append("Average rate \(currency4(s.avgPerMile))/mi vs market — review BY LANE for the spread")
            }
        }
        if case .loaded(let rows) = catalystStore.state, !rows.isEmpty {
            let top3 = rows.sorted { $0.totalSpend > $1.totalSpend }.prefix(3)
            let top3Sum = top3.reduce(0.0) { $0 + $1.totalSpend }
            let totalCatSpend = rows.reduce(0.0) { $0 + $1.totalSpend }
            if totalCatSpend > 0 {
                let pct = Int((top3Sum / totalCatSpend * 100).rounded())
                out.append("Top 3 catalysts carry \(pct)% of spend — concentration risk if any one drops out")
            }
            let avgOnTime = rows.map { Double($0.onTimeRate) }.reduce(0, +) / Double(rows.count)
            out.append(String(format: "Average on-time rate %.0f%% across %d catalysts", avgOnTime, rows.count))
        }
        if out.isEmpty {
            out = [
                "Insights light up once the analytics store has live data for the selected window.",
            ]
        }
        return out
    }

    // MARK: - Helpers

    private func currency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }

    private func currency4(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

// MARK: - Shapes (lifted from wireframe Code/ port)

private struct CurrentTrendLine: Shape {
    let points: [CGPoint]
    let areaHeight: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: CGPoint(x: first.x * rect.width, y: first.y * areaHeight))
        for pt in points.dropFirst() {
            p.addLine(to: CGPoint(x: pt.x * rect.width, y: pt.y * areaHeight))
        }
        return p
    }
}

private struct CurrentTrendFill: Shape {
    let points: [CGPoint]
    let areaHeight: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: CGPoint(x: first.x * rect.width, y: first.y * areaHeight))
        for pt in points.dropFirst() {
            p.addLine(to: CGPoint(x: pt.x * rect.width, y: pt.y * areaHeight))
        }
        p.addLine(to: CGPoint(x: rect.width, y: areaHeight))
        p.addLine(to: CGPoint(x: 0, y: areaHeight))
        p.closeSubpath()
        return p
    }
}

private struct PriorPolyline: Shape {
    let points: [CGPoint]
    let areaHeight: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: CGPoint(x: first.x * rect.width, y: first.y * areaHeight))
        for pt in points.dropFirst() {
            p.addLine(to: CGPoint(x: pt.x * rect.width, y: pt.y * areaHeight))
        }
        return p
    }
}

private struct DonutSegmentShape: Shape {
    let startFraction: CGFloat
    let endFraction: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let radius = min(rect.width, rect.height) / 2 - 5
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let startAngle = Angle.degrees(-90 + 360 * Double(startFraction))
        let endAngle   = Angle.degrees(-90 + 360 * Double(endFraction))
        p.addArc(center: center, radius: radius,
                 startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return p
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let eusoShipperAnalyticsWindow    = Notification.Name("eusoShipperAnalyticsWindow")
    static let eusoShipperAnalyticsLane      = Notification.Name("eusoShipperAnalyticsLane")
    static let eusoShipperAnalyticsScorecard = Notification.Name("eusoShipperAnalyticsScorecard")
}

// MARK: - Screen wrapper

struct ShipperAnalyticsDeepDiveScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ShipperAnalyticsDeepDive()
        } nav: {
            BottomNav(
                leading: shipperNavLeading_210(),
                trailing: shipperNavTrailing_210(),
                orbState: .idle
            )
        }
    }
}

// Out of scope per parity mandate §1.
private func shipperNavLeading_210() -> [NavSlot] {
    [NavSlot(label: "Home",        systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Create Load", systemImage: "plus.rectangle.on.rectangle",    isCurrent: false)]
}

private func shipperNavTrailing_210() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person.fill",      isCurrent: true)]
}

// MARK: - Previews

#Preview("210 · Shipper · Analytics Deep Dive · Night") {
    ShipperAnalyticsDeepDiveScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("210 · Shipper · Analytics Deep Dive · Afternoon") {
    ShipperAnalyticsDeepDiveScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
