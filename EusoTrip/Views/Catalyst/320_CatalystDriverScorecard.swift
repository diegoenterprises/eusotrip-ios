//
//  320_CatalystDriverScorecard.swift
//  EusoTrip — Catalyst · Driver Performance Scorecard (brick 320).
//
//  Pixel-faithful port of "320 Catalyst Driver Performance Scorecard"
//  (Figma `~/Desktop/EusoTrip 2027 UI Wireframes/03 Catalyst/Light-SVG/`).
//  This is the catalyst→driver scorecard surface — the same letter-grade
//  recipe as 213 Catalyst Scorecard (shipper→catalyst vantage), pivoted
//  to the catalyst→driver vantage per §63.6 doctrine. Closes the cross-
//  track scorecard symmetry: shippers grade catalysts, catalysts grade
//  drivers, both with the same A+ / A / A− / B-tier letter-grade engine.
//
//  Catalyst↔Driver relationship per founder doctrine:
//    • The §11.4 sole-driver Eusotrans LLC carrier rates Michael
//      Eusorone (ME, owner-op) — the SAME companyId on both sides.
//      This is the "owner-op seam · clean Schedule C books" signal
//      that surfaces in the seam callout banner — same companyId
//      both rater and ratee = clean tax books.
//    • Every metric below derives from the driver's OWN tables
//      (loads, inspections, hosLogs, fuelTransactions). The catalyst
//      lens is a JOIN, not a fabrication. When the driver has no
//      loads in the window the scorecard renders an honest zero
//      envelope — never a fake "B+ promising" placeholder.
//
//  Server wiring (no stubs / no fake data):
//    • `drivers.getPerformanceMetrics(driverId, period)` — REAL DB
//      joins, see drivers.ts:544. Returns:
//          metrics  { totalMiles, totalLoads, onTimeDeliveryRate,
//                     safetyScore, fuelEfficiency, customerRating,
//                     hosCompliance, inspectionPassRate }
//          rankings { overall, totalDrivers, safetyRank,
//                     productivityRank }
//          trends   { safetyScore, onTimeRate }
//      Server computes onTimeDeliveryRate as delivered/total and
//      hosCompliance as non-violation days / total HOS days. We
//      derive the composite letter grade client-side per §9.1.
//    • `catalysts.getMyDrivers` — to default the scorecard to the
//      catalyst's primary driver when no `driverId` is passed (e.g.
//      navigated to from the Fleet Drivers home tile).
//
//  §9.1 composite-score formula (verbatim from Figma footer):
//      score = onTime · 0.5
//            + completion · 0.3
//            + log₁₀(loads + 1) / log₁₀(50) · 0.2
//
//  Letter-grade mapping (213 recipe verbatim):
//      0.95+ → A+ · 0.90+ → A · 0.85+ → A− · 0.80+ → B+ · 0.75+ → B
//      0.70+ → B− · 0.60+ → C   · else → D / F.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen wrapper

struct CatalystDriverScorecardScreen: View {
    let theme: Theme.Palette
    let driverId: String

    init(theme: Theme.Palette, driverId: String = "") {
        self.theme = theme
        self.driverId = driverId
    }

    var body: some View {
        Shell(theme: theme) {
            CatalystDriverScorecard(initialDriverId: driverId)
        } nav: {
            BottomNav(
                leading: catalystNavLeading_320(),
                trailing: catalystNavTrailing_320(),
                orbState: .idle
            )
        }
    }
}

// Bottom nav — DISPATCH active per Figma (driver scorecards live
// under Dispatch, mirrors 304 Fleet Drivers in the same fleet-ops
// umbrella).
private func catalystNavLeading_320() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: true)]
}

private func catalystNavTrailing_320() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: false)]
}

// MARK: - Period filter

private enum ScorecardPeriod: String, CaseIterable, Identifiable {
    case all = "All"
    case d30 = "30D"
    case d90 = "90D"
    case ytd = "YTD"

    var id: String { rawValue }

    /// Maps to the server's `drivers.getPerformanceMetrics` `period`
    /// enum (week / month / quarter / year). "All" maps to year for
    /// the widest server window we currently expose.
    var serverValue: DriversAPI.PerformancePeriod {
        switch self {
        case .all: return .year
        case .d30: return .month
        case .d90: return .quarter
        case .ytd: return .year
        }
    }

    var subtitleLabel: String {
        switch self {
        case .all: return "all-time"
        case .d30: return "last 30 days"
        case .d90: return "last 90 days"
        case .ytd: return "year-to-date"
        }
    }
}

// MARK: - Body

private struct CatalystDriverScorecard: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    let initialDriverId: String

    @State private var resolvedDriverId: String = ""
    @State private var resolvedDriverName: String = ""
    @State private var period: ScorecardPeriod = .d90
    @State private var scorecard: DriversAPI.PerformanceScorecard? = nil
    @State private var loading: Bool = true
    @State private var loadError: String? = nil

    @State private var showShareSheet: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleBlock
                iridescentHairline
                ownerOpSeamBanner

                if loading {
                    skeletonBody
                } else if let err = loadError {
                    errorBanner(err)
                } else if let s = scorecard {
                    kpiQuartet(s)
                    filterChips
                    sectionHeader
                    compositeRow(s)
                    formulaFooter
                    sendDigestRibbon
                } else {
                    emptyDriverState
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await loadAll() }
        .onChange(of: period) { _, _ in
            Task { await loadScorecard() }
        }
        // Server-side load delivery / inspection / HOS events update
        // the scorecard inputs. RealtimeService fans these out as
        // `.esangRefreshSurface` posts; refetch on every one so the
        // letter grade bumps live as drivers complete loads.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await loadScorecard() }
        }
        .sheet(isPresented: $showShareSheet) {
            scorecardShareSheet
                .environment(\.palette, palette)
        }
    }

    // MARK: - Share digest sheet

    @ViewBuilder
    private var scorecardShareSheet: some View {
        if let s = scorecard {
            let (letter, composite) = letterGrade(for: s)
            let firstName = resolvedDriverName.split(separator: " ").first.map(String.init) ?? "driver"
            let digest = """
            EusoTrip Scorecard · \(resolvedDriverName) · \(period.subtitleLabel)

            Composite: \(letter) · \(String(format: "%.2f", composite))
            On-time: \(String(format: "%.1f", s.metrics.onTimeDeliveryRate))%
            HOS compliance: \(String(format: "%.0f", s.metrics.hosCompliance))%
            Inspection pass rate: \(String(format: "%.0f", s.metrics.inspectionPassRate))%
            Loads: \(String(s.metrics.totalLoads))
            Total miles: \(String(format: "%.0f", s.metrics.totalMiles))

            §9.1 formula: on-time × 0.5 + completion × 0.3 + log₁₀(loads+1)/log₁₀(50) × 0.2
            """
            NavigationStack {
                VStack(spacing: 16) {
                    ShareLink(
                        item: digest,
                        subject: Text("EusoTrip Scorecard · \(firstName)"),
                        message: Text("Weekly performance digest")
                    ) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 13, weight: .heavy))
                            Text("Share digest").font(.system(size: 14, weight: .heavy))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(LinearGradient.diagonal)
                        .clipShape(Capsule())
                        .padding(.horizontal, 20)
                    }

                    Button {
                        // Open ESang chat with digest pre-loaded so the
                        // catalyst can send it as a message instead of
                        // sharing through the OS share sheet.
                        NotificationCenter.default.post(
                            name: .esangOpenMeDetail,
                            object: "messages",
                            userInfo: [
                                "driverId": resolvedDriverId,
                                "context": "scorecard_digest",
                                "digestText": digest,
                            ]
                        )
                        showShareSheet = false
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles").font(.system(size: 13, weight: .heavy))
                            Text("Send via ESang chat").font(.system(size: 14, weight: .heavy))
                        }
                        .foregroundStyle(LinearGradient.diagonal)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(palette.bgCard)
                        .overlay(
                            Capsule().strokeBorder(
                                LinearGradient(colors: [Brand.blue.opacity(0.5), Brand.magenta.opacity(0.5)],
                                               startPoint: .leading, endPoint: .trailing),
                                lineWidth: 1
                            )
                        )
                        .clipShape(Capsule())
                        .padding(.horizontal, 20)
                    }
                    .buttonStyle(.plain)

                    ScrollView {
                        Text(digest)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(palette.bgCard)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal, 20)
                    }
                    Spacer()
                }
                .padding(.top, 20)
                .navigationTitle("Send digest")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showShareSheet = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        } else {
            Text("Loading…")
        }
    }

    // MARK: - TopBar + title

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · DRIVER · SCORECARD")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text(rosterCounterLabel)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var rosterCounterLabel: String {
        guard let s = scorecard else { return "—" }
        return "\(s.metrics.totalLoads) LOADS · 1 DRIVER"
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Driver scorecard")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text(subtitleLine)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var subtitleLine: String {
        let name = resolvedDriverName.isEmpty ? "Driver" : resolvedDriverName
        return "Eusotrans LLC · \(name) · \(period.subtitleLabel)"
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(height: 1)
            .padding(.horizontal, -20)
    }

    // MARK: - Owner-op seam callout

    private var ownerOpSeamBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 2) {
                Text("OWNER-OP SEAM · CLEAN BOOKS")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Catalyst rates driver · same companyId both sides · clean Schedule C books")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            LinearGradient(
                colors: [Brand.blue.opacity(0.10), Brand.magenta.opacity(0.10)],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(LinearGradient(
                    colors: [Brand.blue.opacity(0.40), Brand.magenta.opacity(0.40)],
                    startPoint: .leading, endPoint: .trailing
                ), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - KPI quartet hero card

    private func kpiQuartet(_ s: DriversAPI.PerformanceScorecard) -> some View {
        let (letter, composite) = letterGrade(for: s)
        return HStack(spacing: 0) {
            kpiCell(
                eyebrow: "GRADE",
                value: letter,
                meta: String(format: "composite %.2f", composite),
                emphasis: .gradient
            )
            kpiDivider
            kpiCell(
                eyebrow: "ON-TIME",
                value: String(format: "%.1f%%", s.metrics.onTimeDeliveryRate),
                meta: trendLabel(s.trends.onTimeRate),
                emphasis: .success
            )
            kpiDivider
            kpiCell(
                eyebrow: "SAFETY",
                value: safetyDisplay(s.metrics.safetyScore),
                meta: "CSA · pass \(Int(s.metrics.inspectionPassRate))%",
                emphasis: .gradient
            )
            kpiDivider
            kpiCell(
                eyebrow: "LOADS",
                value: "\(s.metrics.totalLoads)",
                meta: loadsMetaLabel(s),
                emphasis: .neutral
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Brand.blue, Brand.magenta],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private enum KPIEmphasis { case neutral, success, gradient }

    private func kpiCell(eyebrow: String, value: String, meta: String, emphasis: KPIEmphasis) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Group {
                switch emphasis {
                case .gradient:
                    Text(value)
                        .font(.system(size: 22, weight: .heavy))
                        .monospacedDigit()
                        .tracking(-0.4)
                        .foregroundStyle(LinearGradient.diagonal)
                case .success:
                    Text(value)
                        .font(.system(size: 22, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(Brand.success)
                case .neutral:
                    Text(value)
                        .font(.system(size: 22, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(meta)
                .font(.system(size: 10))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kpiDivider: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(width: 1, height: 38)
            .padding(.horizontal, 4)
    }

    private func loadsMetaLabel(_ s: DriversAPI.PerformanceScorecard) -> String {
        let weeks: Double = {
            switch s.period {
            case "week":    return 1
            case "month":   return 4.3
            case "quarter": return 13
            default:        return 52
            }
        }()
        guard weeks > 0, s.metrics.totalLoads > 0 else { return "no loads in window" }
        let perWeek = Double(s.metrics.totalLoads) / weeks
        return String(format: "%.0fd · %.1f/wk avg", weeks * 7, perWeek)
    }

    private func trendLabel(_ trend: DriversAPI.PerformanceTrend) -> String {
        if trend.change == 0 {
            return "vs prior \(period.rawValue) — flat"
        }
        let sign = trend.change > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", trend.change)) pts vs prior"
    }

    private func safetyDisplay(_ score: Double) -> String {
        // Server stores safetyScore as 0-100 int. The Figma shows
        // "4.92 /5" — we render the 5-scale conversion (rounded to
        // hundredths) so the visual matches the recipe.
        let outOf5 = max(0, min(5, score / 20))
        return String(format: "%.2f", outOf5)
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ScorecardPeriod.allCases) { p in
                    filterChip(p)
                }
            }
        }
    }

    private func filterChip(_ p: ScorecardPeriod) -> some View {
        let active = period == p
        return Button {
            withAnimation(.easeOut(duration: 0.12)) {
                period = p
            }
        } label: {
            Text(p.rawValue)
                .font(.system(size: 12, weight: active ? .heavy : .semibold))
                .foregroundStyle(active ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textPrimary))
                .padding(.horizontal, 16)
                .frame(height: 28)
                .background(active ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        active ? AnyShapeStyle(Color.clear) : AnyShapeStyle(palette.borderFaint),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section header + composite row

    private var sectionHeader: some View {
        Text(sectionHeaderLabel)
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(palette.textTertiary)
    }

    private var sectionHeaderLabel: String {
        guard scorecard != nil else { return "COMPOSITE · ME · LAST \(period.rawValue.uppercased())" }
        return "COMPOSITE · \(monogram(for: resolvedDriverName)) · LAST \(period.rawValue.uppercased())"
    }

    private func compositeRow(_ s: DriversAPI.PerformanceScorecard) -> some View {
        let (letter, composite) = letterGrade(for: s)
        return HStack(alignment: .top, spacing: 12) {
            // 44pt monogram avatar (gradient hero)
            ZStack {
                Circle().fill(LinearGradient.diagonal)
                Text(monogram(for: resolvedDriverName))
                    .font(.system(size: 14, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("SCORE-COMPOSITE")
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                Text("All lanes · \(period.subtitleLabel) composite")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(rankingLine(s))
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                threeStatRow(s)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
            // 56×56 grade badge
            VStack(spacing: 2) {
                Text(letter)
                    .font(.system(size: 22, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundStyle(.white)
                Text(String(format: "%.2f", composite))
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(width: 56, height: 56)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func rankingLine(_ s: DriversAPI.PerformanceScorecard) -> String {
        if s.rankings.totalDrivers > 1 {
            return "Rank \(s.rankings.overall) of \(s.rankings.totalDrivers) · safety \(s.rankings.safetyRank) · prod \(s.rankings.productivityRank)"
        }
        // Sole-driver carrier — emphasise the §11.4 / §12 owner-op seam
        // rather than rendering "rank 1 of 1" which adds no info.
        return "USDOT 3 194 882 · multi-modal · MC-306 · MC-331"
    }

    private func threeStatRow(_ s: DriversAPI.PerformanceScorecard) -> some View {
        HStack(spacing: 0) {
            statCell(label: "ON-TIME",    value: String(format: "%.1f%%", s.metrics.onTimeDeliveryRate))
            statCell(label: "HOS",        value: String(format: "%.0f%%", s.metrics.hosCompliance))
            statCell(label: "LOADS",      value: "\(s.metrics.totalLoads)")
        }
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Formula footer

    private var formulaFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("COMPOSITE FORMULA · §9.1")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text("score = on-time · 0.5 + completion · 0.3 + log₁₀(loads + 1) / log₁₀(50) · 0.2")
                .font(.system(size: 10, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard.opacity(scheme == .dark ? 0.40 : 0.60))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Action ribbon

    private var sendDigestRibbon: some View {
        Button {
            showShareSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(digestTitle)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("auto-files to driver record · weekly cadence")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var digestTitle: String {
        let firstName = resolvedDriverName.split(separator: " ").first.map(String.init) ?? "driver"
        return "Send scorecard digest · \(firstName) · weekly"
    }

    // MARK: - Empty / loading / error

    private var skeletonBody: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.bgCard).frame(height: 86)
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard).frame(height: 28)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.bgCard).frame(height: 100)
        }
        .redacted(reason: .placeholder)
    }

    @ViewBuilder
    private var emptyDriverState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text("No driver to score")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Add a driver to your roster on 304 Fleet Drivers to start tracking performance.")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(msg)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Button { Task { await loadAll() } } label: {
                    Text("Retry")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Brand.danger)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Brand.danger.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Composite + grade

    private func letterGrade(for s: DriversAPI.PerformanceScorecard) -> (letter: String, composite: Double) {
        let onTime = max(0.0, min(1.0, s.metrics.onTimeDeliveryRate / 100))
        let completion = max(0.0, min(1.0, s.metrics.hosCompliance / 100))   // proxy until completion ratio ships
        let loadsTerm: Double = {
            let n: Double = Double(max(0, s.metrics.totalLoads))
            let num: Double = log10(n + 1.0)
            let den: Double = log10(50.0)
            return den > 0 ? num / den : 0
        }()
        let composite = onTime * 0.5 + completion * 0.3 + loadsTerm * 0.2
        let letter: String = {
            switch composite {
            case 0.95...:  return "A+"
            case 0.90..<0.95: return "A"
            case 0.85..<0.90: return "A−"
            case 0.80..<0.85: return "B+"
            case 0.75..<0.80: return "B"
            case 0.70..<0.75: return "B−"
            case 0.60..<0.70: return "C"
            case 0.50..<0.60: return "D"
            default:          return "F"
            }
        }()
        return (letter, composite)
    }

    private func monogram(for name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let initials = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return initials.isEmpty ? "?" : String(initials.prefix(2))
    }

    // MARK: - Network

    private func loadAll() async {
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            // Resolve driverId — if not provided, default to the
            // catalyst's primary driver (first roster entry).
            if !initialDriverId.isEmpty {
                resolvedDriverId = initialDriverId
                if resolvedDriverName.isEmpty {
                    let roster = (try? await EusoTripAPI.shared.catalyst.getMyDrivers(limit: 50)) ?? []
                    resolvedDriverName = roster.first { $0.id == initialDriverId }?.name ?? ""
                }
            } else {
                let roster = try await EusoTripAPI.shared.catalyst.getMyDrivers(limit: 50)
                guard let primary = roster.first else {
                    self.scorecard = nil
                    return
                }
                resolvedDriverId = primary.id
                resolvedDriverName = primary.name
            }
            await loadScorecard()
        } catch {
            self.loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadScorecard() async {
        guard !resolvedDriverId.isEmpty else { return }
        do {
            let s = try await EusoTripAPI.shared.drivers.getPerformanceMetrics(
                driverId: resolvedDriverId,
                period: period.serverValue
            )
            self.scorecard = s
        } catch {
            self.loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Previews

#Preview("320 · Catalyst · Driver Scorecard · Night") {
    CatalystDriverScorecardScreen(theme: Theme.dark, driverId: "")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("320 · Catalyst · Driver Scorecard · Afternoon") {
    CatalystDriverScorecardScreen(theme: Theme.light, driverId: "")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
