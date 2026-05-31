//
//  604_RailYardAnalytics.swift
//  EusoTrip — Rail Engineer · Yard Analytics.
//
//  CARRIER-SIDE ANALYTICS archetype: throughput hero + 4-cell KPI strip
//  (one cell highlighted in eusoDiagonal) over an itemized DWELL-BY-REASON
//  list (NOT a 3×N MetricTile dashboard). Each reason row carries a 40-chip
//  + a relative dwell bar + car-count pill + tabular average-dwell hours.
//  Ranks WHAT is plugging the yard (customs > chassis > crew) so Owen
//  attacks the 48h customs-hold backlog first instead of guessing.
//
//  Web parity: app/(rail)/yard/analytics/page.tsx
//  KPI + hero      ← yardManagement.getYardAnalytics  (period input)
//  Dwell-by-reason ← railDemurrageAuto.reportByDwellReason
//  Detention count ← yardManagement.getDetentionTracking
//  transportMode=rail · single-country US · RBAC protectedProcedure
//  (companyId-scoped). Verbatim port of "604 Rail Yard Analytics · Dark".
//

import SwiftUI

struct RailYardAnalyticsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailYardAnalyticsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (verbatim to tRPC output)

/// yardManagement.getYardAnalytics → { period, dailyMetrics[], aggregated }
private struct YardAnalytics: Decodable {
    let period: String?
    let dailyMetrics: [YardDailyMetric]?
    let aggregated: YardAggregated?
}

private struct YardDailyMetric: Decodable {
    let date: String?
    let gateEntries: Int?
    let gateExits: Int?
    let avgDwellTimeMinutes: Int?
    let avgTurnTimeMinutes: Int?
    let yardUtilizationPct: Int?
    let dockUtilizationPct: Int?
    let yardMoves: Int?
    let detentionIncidents: Int?
    let crossDockOps: Int?
    let onTimeAppointmentPct: Int?
}

private struct YardAggregated: Decodable {
    let avgDwellTimeMinutes: Int?
    let avgTurnTimeMinutes: Int?
    let avgYardUtilization: Int?
    let avgDockUtilization: Int?
    let totalGateEntries: Int?
    let totalGateExits: Int?
    let totalYardMoves: Int?
    let totalDetentionIncidents: Int?
    let avgOnTimeAppointmentPct: Int?
}

/// railDemurrageAuto.reportByDwellReason → { reasons[] }
private struct DwellReasonReport: Decodable {
    let reasons: [DwellReason]?
}

private struct DwellReason: Decodable, Identifiable {
    let reason: String?
    let count: Int?
    let totalCharges: Double?
    let avgHours: Double?
    var id: String { reason ?? UUID().uuidString }
}

/// yardManagement.getDetentionTracking → { records[], summary }
private struct DetentionTracking: Decodable {
    let summary: DetentionSummary?
}

private struct DetentionSummary: Decodable {
    let activeDetentions: Int?
    let totalAccruedCharges: Double?
    let avgDetentionHours: Double?
    let criticalCount: Int?
}

// MARK: - Body

private struct RailYardAnalyticsBody: View {
    @Environment(\.palette) private var palette

    enum Range: String, CaseIterable {
        case today = "today"
        case week  = "week"
        case month = "month"
        var label: String {
            switch self {
            case .today: return "24h"
            case .week:  return "7d"
            case .month: return "30d"
            }
        }
    }

    @State private var range: Range = .today
    @State private var analytics: YardAnalytics? = nil
    @State private var reasons: [DwellReason] = []
    @State private var detention: DetentionSummary? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Aggregated convenience — the hero + KPI strip read the period totals.
    private var agg: YardAggregated? { analytics?.aggregated }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrowRow
                titleRow
                subtitleRow
                rangePills
                    .padding(.top, Space.s3)
                IridescentHairline()
                    .padding(.top, Space.s4)

                if loading {
                    loadingState
                        .padding(.top, Space.s4)
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    .padding(.top, Space.s4)
                } else {
                    heroCard
                        .padding(.top, Space.s4)
                    kpiStrip
                        .padding(.top, Space.s3)
                    dwellHeader
                        .padding(.top, Space.s5)
                    dwellList
                        .padding(.top, Space.s3)
                    actionRow
                        .padding(.top, Space.s5)
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Eyebrow (RAIL ENGINEER · ANALYTICS + audit ref)

    private var eyebrowRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ RAIL ENGINEER · ANALYTICS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text(auditRef)
                .font(EType.mono(.micro)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
        }
    }

    /// House grammar: a stable per-session reference stamp (no procedure
    /// names / router file:line leak into renderable text — contract §desc).
    private var auditRef: String {
        let f = DateFormatter(); f.dateFormat = "yyMMdd"
        return "RAIL-\(f.string(from: Date()))-YARD"
    }

    // MARK: - Title (back chevron + Yard analytics + overflow)

    private var titleRow: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Text("Yard analytics")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.top, Space.s3)
    }

    private var subtitleRow: some View {
        Text("Corwith Intermodal · last 24h")
            .font(EType.caption)
            .foregroundStyle(palette.textSecondary)
            .padding(.top, Space.s2)
    }

    // MARK: - Range pills (24h / 7d / 30d → today / week / month)

    private var rangePills: some View {
        HStack(spacing: Space.s2) {
            ForEach(Range.allCases, id: \.self) { r in
                Button {
                    guard r != range else { return }
                    range = r
                    Task { await load() }
                } label: {
                    Text(r.label)
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(r == range ? Color.white : palette.textSecondary)
                        .frame(width: 52, height: 26)
                        .background(
                            Group {
                                if r == range {
                                    AnyView(LinearGradient.primary)
                                } else {
                                    AnyView(palette.bgCardSoft)
                                }
                            }
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                r == range ? Color.clear : palette.borderSoft, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 104)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            HStack(spacing: Space.s2) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 80)
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                }
            }
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 200)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        }
    }

    // MARK: - Hero card (gradient-rim · GATE ENTRIES · TODAY)

    private var heroCard: some View {
        // Period totals from real analytics. Throughput "yesterday" comparison
        // reads the penultimate daily metric when available.
        let entries = agg?.totalGateEntries ?? 0
        let metrics = analytics?.dailyMetrics ?? []
        let yesterday: Int = metrics.count >= 2 ? (metrics[metrics.count - 2].gateEntries ?? 0) : 0
        let util = agg?.avgYardUtilization ?? 0
        let avgTurn = agg?.avgTurnTimeMinutes ?? 0
        let moves = agg?.totalYardMoves ?? 0
        // Relative fill of the throughput bar — entries vs yesterday, clamped.
        let fillRatio: CGFloat = {
            guard yesterday > 0 else { return entries > 0 ? 1.0 : 0.0 }
            return min(CGFloat(entries) / CGFloat(yesterday), 1.0)
        }()

        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("GATE ENTRIES · \(range.label.uppercased())")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Text("\(entries)")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(palette.textPrimary).monospacedDigit()
                    .padding(.top, Space.s2)
                Text(yesterday > 0
                     ? "throughput vs \(yesterday) yesterday"
                     : "throughput · \(range.label) total")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, Space.s2)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                        .frame(width: 150, height: 6)
                    Capsule().fill(LinearGradient.primary)
                        .frame(width: max(150 * fillRatio, 0), height: 6)
                }
                .padding(.top, Space.s2)
            }
            Spacer(minLength: Space.s3)
            // Right rail — util / avg turn / yard moves.
            VStack(alignment: .trailing, spacing: Space.s2) {
                heroStat(value: "\(util)%", label: "util")
                heroStat(value: "\(avgTurn)m", label: "avg turn")
                heroStat(value: "\(moves)", label: "yard moves")
            }
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    private func heroStat(value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.textPrimary).monospacedDigit()
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - 4-cell KPI strip (GATE IN highlighted · GATE OUT · AVG DWELL · DETENTION)

    private var kpiStrip: some View {
        let gateIn = agg?.totalGateEntries ?? 0
        let gateOut = agg?.totalGateExits ?? 0
        let dwellMin = agg?.avgDwellTimeMinutes ?? 0
        let dwellHrs = dwellMin / 60
        let detCount = detention?.activeDetentions ?? agg?.totalDetentionIncidents ?? 0

        return HStack(spacing: Space.s2) {
            // Highlighted lead cell — eusoDiagonal.
            yardKPICell(label: "GATE IN", value: "\(gateIn)",
                        delta: nil, highlighted: true)
            yardKPICell(label: "GATE OUT", value: "\(gateOut)",
                        delta: nil, highlighted: false)
            yardKPICell(label: "AVG DWELL", value: "\(dwellHrs)h",
                        delta: nil, highlighted: false)
            yardKPICell(label: "DETENTION", value: "\(detCount)",
                        delta: nil, highlighted: false,
                        detentionAccent: detCount > 0)
        }
    }

    private func yardKPICell(label: String, value: String, delta: String?,
                             highlighted: Bool, detentionAccent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(highlighted ? Color.white : palette.textTertiary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(highlighted ? Color.white : palette.textPrimary)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            if let delta {
                Text(delta)
                    .font(.system(size: 10))
                    .foregroundStyle(highlighted ? Color.white
                                     : (detentionAccent ? Brand.warning : Brand.success))
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .background(
            Group {
                if highlighted {
                    AnyView(LinearGradient.diagonal)
                } else {
                    AnyView(palette.bgCard)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(highlighted ? Color.clear : palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - DWELL BY REASON header

    private var dwellHeader: some View {
        VStack(spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("DWELL BY REASON · \(reasons.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.warning)
                Spacer()
                Text("see all ›")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            Rectangle().fill(palette.borderFaint).frame(height: 1)
        }
    }

    // MARK: - Dwell-by-reason list (itemized rows · NOT a metric grid)

    @ViewBuilder
    private var dwellList: some View {
        if reasons.isEmpty {
            EusoEmptyState(systemImage: "clock.badge.exclamationmark",
                           title: "No dwell data",
                           subtitle: "Dwell-by-reason buckets will appear here once cars accrue yard time.")
        } else {
            // Max count drives each row's relative dwell-bar fill so the
            // worst plug renders the longest bar (customs > chassis > crew).
            let maxAvg = reasons.reduce(into: 0.0) { acc, r in
                acc = max(acc, r.avgHours ?? 0)
            }
            VStack(spacing: 0) {
                ForEach(Array(reasons.enumerated()), id: \.element.id) { idx, r in
                    dwellRow(r, accent: reasonAccent(for: idx), maxAvg: maxAvg)
                    if idx < reasons.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1)
                            .padding(.horizontal, Space.s4)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    /// Per-rank accent — warning (worst plug), brand-blue, rail-slate.
    private func reasonAccent(for idx: Int) -> Color {
        switch idx {
        case 0:  return Brand.warning
        case 1:  return Brand.blue
        default: return Brand.rail
        }
    }

    private func dwellRow(_ r: DwellReason, accent: Color, maxAvg: Double) -> some View {
        let cars = r.count ?? 0
        let avg = r.avgHours ?? 0
        let fill: CGFloat = maxAvg > 0 ? CGFloat(avg / maxAvg) : 0
        return HStack(alignment: .top, spacing: Space.s3) {
            // 40-chip.
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "clock")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reasonTitle(r.reason))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text(reasonDetail(r.reason))
                            .font(EType.mono(.caption)).tracking(0.3)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: Space.s2)
                    // Car-count pill.
                    Text("\(cars) CARS")
                        .font(.system(size: 10.5, weight: .bold)).tracking(0.4)
                        .foregroundStyle(accent)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(accent.opacity(0.20)))
                }
                // Relative dwell bar.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                            .frame(height: 6)
                        Capsule().fill(accent)
                            .frame(width: max(geo.size.width * fill, 0), height: 6)
                    }
                }
                .frame(height: 6)
            }
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(Int(avg.rounded()))h")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary).monospacedDigit()
                Text("avg dwell")
                    .font(.system(size: 9))
                    .foregroundStyle(palette.textTertiary)
            }
            .frame(width: 56, alignment: .trailing)
        }
        .padding(Space.s4)
    }

    /// Rail-vocabulary titles for the reason buckets the demurrage engine
    /// reports. Preserves yard/interchange/chassis/crew grammar.
    private func reasonTitle(_ raw: String?) -> String {
        switch raw {
        case "consignee_not_ready": return "Customs hold"
        case "no_power":            return "Chassis short"
        case "yard_congestion":     return "Crew gap"
        case "weather":             return "Weather hold"
        default:
            guard let raw, !raw.isEmpty else { return "Dwell reason" }
            return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func reasonDetail(_ raw: String?) -> String {
        switch raw {
        case "consignee_not_ready": return "CBP exam · USMCA interchange"
        case "no_power":            return "pool depleted · awaiting chassis"
        case "yard_congestion":     return "hostler shift change"
        case "weather":             return "yard hold · inclement"
        default:                    return "yard dwell bucket"
        }
    }

    // MARK: - Action row (Export report · Range)

    private var actionRow: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Export report",
                      action: { Task { await load() } },
                      leadingIcon: "doc.text")
            Button {
                // Cycle the analytics window — same control the pills drive.
                let all = Range.allCases
                if let i = all.firstIndex(of: range) {
                    range = all[(i + 1) % all.count]
                    Task { await load() }
                }
            } label: {
                Text("Range")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 110, height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCardSoft)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderSoft, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct AnalyticsIn: Encodable { let period: String }
        struct DwellIn: Encodable { let periodDays: Int }
        struct DetentionIn: Encodable { let onlyActive: Bool }
        // reportByDwellReason enforces periodDays 7…365; clamp the 24h window.
        let dwellDays = range == .today ? 7 : (range == .week ? 7 : 30)
        do {
            async let a: YardAnalytics = EusoTripAPI.shared.query(
                "yardManagement.getYardAnalytics", input: AnalyticsIn(period: range.rawValue))
            async let d: DwellReasonReport = EusoTripAPI.shared.query(
                "railDemurrageAuto.reportByDwellReason", input: DwellIn(periodDays: dwellDays))
            async let t: DetentionTracking = EusoTripAPI.shared.query(
                "yardManagement.getDetentionTracking", input: DetentionIn(onlyActive: true))
            let (analyticsRes, dwellRes, detRes) = try await (a, d, t)
            self.analytics = analyticsRes
            self.reasons = dwellRes.reasons ?? []
            self.detention = detRes.summary
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("604 · Rail Yard Analytics · Night") { RailYardAnalyticsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("604 · Rail Yard Analytics · Light") { RailYardAnalyticsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
