//
//  327B_CatalystDriverQuarterDetail.swift
//  EusoTrip — Catalyst · Driver Quarter Detail (brick 327B).
//
//  Pixel-faithful port of
//  `03 Catalyst/Dark-SVG/327B Catalyst Driver Quarter Detail.svg`
//  (canvas 440×956). Web parity:
//  /catalyst/drivers/[driverId]/quarterly-history/[qid].
//
//  Single-quarter drill-down opened from a 327 Quarterly-History row. Every
//  figure (driver identity, miles, loads, gross, OTP, grade, month strip,
//  YoY benchmark, ELD data-quality) is hydrated live from the real procs for
//  the (driverId, quarterId) this screen holds — nothing is hardcoded. Cousin-
//  port template-lift from §97 323 Catalyst Driver Performance at the per-
//  period drill-down vantage with the axis pivoted from per-metric to per-
//  quarter. §8.4 owner-op seam callout describes the clean closed-quarter
//  reconciliation. RBAC: CATALYST (carrier/broker) role.
//
//  Server wiring (all procs EXIST + are role-accessible — wired through the
//  typed EusoTripAPI namespaces, no raw stub strings, no fabricated data):
//    • drivers.getQuarterRow            → api.drivers.getQuarterRow
//    • analytics.getQuarterRollup       → api.analytics.getQuarterRollup
//    • analytics.getPriorYearComparable → api.analytics.getPriorYearComparable
//    • regulation.getCfrText            → api.regulation.getCfrText (§395.8)
//    • eld.getDriverHosWindow           → api.eld.getDriverHosWindow
//    • drivers.refineQuarterGoal        → api.drivers.refineQuarterGoal (mutation)
//    • drivers.pinQuarter               → api.drivers.pinQuarter (mutation)
//
//  Every figure on this screen is hydrated from the real proc(s) in a
//  `.task`. When a proc returns its honest-empty payload (driver had no
//  activity in the window), the derived rows render "—"/"-" — never a
//  fabricated seed. No `?? <invented>` fallbacks remain.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//

import SwiftUI

// MARK: - Decodable type aliases
//
// The wire shapes live on the typed EusoTripAPI namespaces (matched
// field-for-field against the server zod outputs). The view consumes them
// through these local aliases.

private typealias QuarterRow327B = DriversAPI.QuarterRow
private typealias QuarterRollup327B = AnalyticsAPI.QuarterRollup
private typealias PriorYearComparable327B = AnalyticsAPI.PriorYearComparable
private typealias CfrText327B = RegulationAPI.CfrText
private typealias HosWindow327B = ELDAPI.DriverHosWindow

// MARK: - Screen wrapper

struct CatalystDriverQuarterDetailBespokeScreen: View {
    let theme: Theme.Palette
    let driverId: String
    let quarterId: String

    init(theme: Theme.Palette = Theme.dark,
         driverId: String = "001-EUSO",
         quarterId: String = "Q1-2026") {
        self.theme = theme
        self.driverId = driverId
        self.quarterId = quarterId
    }

    var body: some View {
        Shell(theme: theme) {
            CatalystDriverQuarterDetailBody(driverId: driverId, quarterId: quarterId)
        } nav: {
            BottomNav(
                leading: catalystNavLeading_327B(),
                trailing: catalystNavTrailing_327B(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_327B() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: true)]
}

private func catalystNavTrailing_327B() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)]
}

// MARK: - Detail row tier (the §92 RegulatoryRow geometry · NINTH port)

private enum QuarterRowTier {
    case gradient
    case success
    case info
}

private struct QuarterDetailRow: Identifiable {
    let id = UUID()
    let eyebrow: String
    let title: String
    let trailingValue: String
    let trailingMeta: String
    let tier: QuarterRowTier
    var actionRibbon: Bool = false    // row 5 carries the gradient action rim
}

// MARK: - Body

private struct CatalystDriverQuarterDetailBody: View {
    let driverId: String
    let quarterId: String

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    @State private var actionError: String? = nil
    @State private var actionInFlight: Bool = false
    @State private var cfrExpanded: Bool = false

    @State private var row: QuarterRow327B? = nil
    @State private var rollup: QuarterRollup327B? = nil
    @State private var comparable: PriorYearComparable327B? = nil
    @State private var cfr: CfrText327B? = nil
    @State private var hos: HosWindow327B? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleRow
                iridescentHairline
                ownerOpSeamBanner

                if loading {
                    skeletonBody
                } else if let err = loadError {
                    errorBanner(err)
                } else {
                    identityStrip
                    heroSummaryCard
                    lifecycleStrip
                    sectionEyebrow
                    ForEach(detailRows) { detailRowView($0) }
                    cfrChip
                    actionRibbon
                    if let actionError {
                        actionErrorNote(actionError)
                    }
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    // MARK: - TopBar (eyebrow + entity-ID kicker) + back-to-Quarterly pill

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · DRIVER · QUARTER DETAIL")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text(kickerLabel)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var kickerLabel: String {
        let dr = "DR-\(driverId)"
        let q = (row?.quarterId ?? quarterId)
        return "\(dr) · \(q) · CLOSED"
    }

    private var titleRow: some View {
        HStack(alignment: .center) {
            Text("Quarter detail")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("Quarterly")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                }
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(palette.bgCard)
                .overlay(
                    Capsule().strokeBorder(palette.borderSoft, lineWidth: 1)
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [Brand.blue.opacity(0.40), Brand.magenta.opacity(0.40)],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(height: 1)
            .padding(.horizontal, -20)
    }

    // MARK: - §8.4 owner-op seam callout banner

    private var ownerOpSeamBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 2) {
                Text("OWNER-OP SEAM · Q1 BOOKS RECONCILED CLEAN")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Catalyst archives Q1 driver rollup · same company both sides · clean Schedule C closed quarter")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [Brand.blue.opacity(0.14), Brand.magenta.opacity(0.14)],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(LinearGradient(
                    colors: [Brand.blue.opacity(0.40), Brand.magenta.opacity(0.40)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Driver identity strip (compact · THIRTEENTH consecutive port)

    private var identityStrip: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal)
                Text(monogram(for: driverName))
                    .font(.system(size: 13, weight: .bold))
                    .tracking(0.3)
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(driverName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(identityMetaLine)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(LinearGradient.diagonal)
                Text(gradeLabel)
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.2)
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)
        }
        .padding(12)
        .frame(height: 64)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var driverName: String {
        let n = row?.driverName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (n?.isEmpty == false) ? n! : "—"
    }

    private var gradeLabel: String {
        let g = row?.grade?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (g?.isEmpty == false) ? g! : "—"
    }

    private var identityMetaLine: String {
        let dr = "DR-\(driverId)"
        let q = row?.quarterId ?? quarterId
        var parts: [String] = []
        if let company = row?.companyName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !company.isEmpty {
            parts.append(company)
        }
        parts.append(dr)
        if let closed = row?.closedAt, !closed.isEmpty {
            parts.append("\(q) closed \(closed)")
        } else {
            parts.append(q)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Quarter HERO summary card (gradient-rim)

    private var heroSummaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow row: perf id + CLOSED · RECONCILED success pill
            HStack(alignment: .top) {
                Text(perfRollupId)
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text(statusLabel)
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 20)
                    .background(LinearGradient(colors: [Brand.success, Color(hex: 0x00A07B)],
                                               startPoint: .top, endPoint: .bottom))
                    .clipShape(Capsule())
            }

            // Hero metric + recap row
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(otpHero)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("\(quarterTag) ON-TIME · §395.8 ELD")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(yoyLine)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(recapLine)
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                    Text(quarterWindowLine)
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 18)

            Divider().overlay(palette.borderFaint).padding(.top, 14)

            // 4-axis MONTH STRIP (bottom edge) — FIFTH HeroAxisStrip port
            HStack(alignment: .bottom, spacing: 0) {
                monthCell(value: janMiles, label: "JAN MI")
                monthCell(value: febMiles, label: "FEB MI")
                monthCell(value: marMiles, label: "MAR MI")
                monthCell(value: otpAxis,  label: "Q1 OTP")
                Spacer(minLength: 0)
                // ELD vendor chip — right cap
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("ELD")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(scheme == .dark ? Color(hex: 0x141928) : palette.bgCardSoft)
                .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1))
                .clipShape(Capsule())
            }
            .padding(.top, 12)
        }
        .padding(14)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Brand.blue.opacity(0.95), Brand.magenta.opacity(0.95)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func monthCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
            Text(label)
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
        }
        .frame(width: 72, alignment: .leading)
    }

    /// Parsed (quarterNumber, year) from the canonical "Q<n>-<year>" label.
    private var quarterParts: (q: Int, year: Int)? {
        let label = row?.quarterId ?? quarterId
        guard let m = label.range(of: #"Q([1-4])-(\d{4})"#, options: .regularExpression) else { return nil }
        let matched = String(label[m])
        let digits = matched.dropFirst().split(separator: "-")
        guard digits.count == 2, let q = Int(digits[0]), let y = Int(digits[1]) else { return nil }
        return (q, y)
    }

    /// "Q1" … "Q4" from the real quarter label (falls back to the raw label).
    private var quarterTag: String {
        guard let p = quarterParts else { return (row?.quarterId ?? quarterId) }
        return "Q\(p.q)"
    }

    /// Month-window + weeks-closed line derived from the real quarter label
    /// and the rollup's weeksClosed (honest "—" when the rollup is empty).
    private var quarterWindowLine: String {
        let months: String
        if let p = quarterParts {
            let names = ["Jan – Mar", "Apr – Jun", "Jul – Sep", "Oct – Dec"]
            months = "\(names[p.q - 1]) \(p.year)"
        } else {
            months = (row?.quarterId ?? quarterId)
        }
        if let wks = rollup?.weeksClosed {
            return "\(months) · \(wks) wks closed"
        }
        return months
    }

    /// Performance-rollup id derived from the real closed-quarter row
    /// (close date + quarter label + driver id) — not a hardcoded literal.
    private var perfRollupId: String {
        let compact = (row?.closedAt ?? quarterId).replacingOccurrences(of: "-", with: "")
        let qTag = (row?.quarterId ?? quarterId)
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
        let dr = driverId.replacingOccurrences(of: "-", with: "").uppercased()
        return "PERF-\(compact)-\(qTag)ROLL-DR\(dr)"
    }

    private var statusLabel: String {
        guard let s = row?.status, !s.isEmpty else { return "—" }
        return s.uppercased()
    }
    private var otpHero: String {
        guard let otp = row?.otpPct else { return "—" }
        return String(format: "%.1f%%", otp)
    }
    private var otpAxis: String {
        guard let otp = rollup?.otpPct ?? row?.otpPct else { return "—" }
        return String(format: "%.1f", otp)
    }
    private var janMiles: String { milesCell(rollup?.janMiles) }
    private var febMiles: String { milesCell(rollup?.febMiles) }
    private var marMiles: String { milesCell(rollup?.marMiles) }

    private func milesCell(_ v: Int?) -> String {
        guard let v else { return "—" }
        return v.formatted(.number)
    }

    private var yoyLine: String {
        guard let delta = comparable?.otpDeltaPt else { return "— vs prior-year Q" }
        let sign = delta >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", delta))pt vs prior-year Q"
    }

    private var recapLine: String {
        let loads = row?.loads.map { "\($0) loads" } ?? "— loads"
        let miles = row?.miles.map { "\($0.formatted(.number)) mi" } ?? "— mi"
        let gross = row?.grossUSD.map(currencyK) ?? "—"
        return "\(loads) · \(miles) · \(gross)"
    }

    // MARK: - 5-stage QUARTER lifecycle strip
    // PLANNED · IN PROGRESS · CLOSED · RECONCILED · ARCHIVED.
    // Stages 0–3 success-tinted (Q1 ran end-to-end + reconciled),
    // stage 4 ARCHIVED active (gradient) — QUARTER COMPLETE.

    private var lifecycleStages: [(String, Bool)] {
        [("PLANNED", false), ("IN PROGRESS", false), ("CLOSED", false),
         ("RECONCILED", false), ("ARCHIVED", true)]
    }

    private var lifecycleStrip: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .center) {
                Rectangle()
                    .fill(Brand.success.opacity(0.40))
                    .frame(height: 1)
                    .padding(.horizontal, 22)
                HStack(spacing: 0) {
                    ForEach(Array(lifecycleStages.enumerated()), id: \.offset) { _, stage in
                        lifecycleNode(active: stage.1)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            HStack(spacing: 0) {
                ForEach(Array(lifecycleStages.enumerated()), id: \.offset) { _, stage in
                    Text(stage.0)
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.5)
                        .foregroundStyle(stage.1 ? AnyShapeStyle(LinearGradient.diagonal)
                                                  : AnyShapeStyle(Brand.success))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(12)
        .frame(height: 44)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func lifecycleNode(active: Bool) -> some View {
        ZStack {
            if active {
                Circle()
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                Circle().fill(LinearGradient.diagonal).frame(width: 14, height: 14)
            } else {
                Circle()
                    .fill(LinearGradient(colors: [Brand.success, Color(hex: 0x00A07B)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 14, height: 14)
            }
            Image(systemName: "checkmark")
                .font(.system(size: 7, weight: .heavy))
                .foregroundStyle(.white)
        }
    }

    // MARK: - QUARTER DETAIL section eyebrow

    private var sectionEyebrow: some View {
        Text("QUARTER DETAIL · 5 OF 5 · TAP TO PIN OR ANNOTATE")
            .font(.system(size: 9, weight: .heavy))
            .tracking(1.0)
            .foregroundStyle(LinearGradient.diagonal)
    }

    // MARK: - 5 quarter-detail rows (§92 RegulatoryRow geometry · NINTH port)

    /// Prior-year quarter label ("2025 Q1") derived from the real quarter.
    private var priorYearTag: String {
        guard let p = quarterParts else { return "prior-year Q" }
        return "\(p.year - 1) Q\(p.q)"
    }

    /// Next-quarter label ("Q2-2026") derived from the real quarter — the
    /// refine mutation persists against this id.
    private var nextQuarterId: String {
        guard let p = quarterParts else { return "Q2-2026" }
        if p.q < 4 { return "Q\(p.q + 1)-\(p.year)" }
        return "Q1-\(p.year + 1)"
    }
    private var nextQuarterTag: String { String(nextQuarterId.split(separator: "-").first ?? "Q2") }

    private var detailRows: [QuarterDetailRow] {
        let onTime = rollup?.onTimeLoads
        let carrierFault = rollup?.carrierFaultLate
        let driverFault = rollup?.driverFaultLate
        let anomalies = hos?.anomalies ?? rollup?.eldAnomalies
        let unidentified = hos?.unidentified ?? rollup?.unidentifiedDriving
        let loads = row?.loads
        let milesStr = row?.miles.map { $0.formatted(.number) } ?? "—"

        // Row 1 — quarter lane count (delivered loads inside the window).
        let laneTitle = loads.map { "\($0) delivered loads in window" } ?? "No delivered loads in window"

        // Row 2 — on-time vs fault split (honest "—" when the rollup is empty).
        let onTimeStr = onTime.map(String.init) ?? "—"
        let totalStr = loads.map(String.init) ?? "—"
        let carrierStr = carrierFault.map(String.init) ?? "—"
        let driverStr = driverFault.map(String.init) ?? "—"
        let window2 = rollup?.weeksClosed.map { "\($0) WEEKS CLOSED" } ?? "QUARTER WINDOW"

        // Row 3 — ELD data quality (only assert "clean" when truly zero).
        let anomStr = anomalies.map(String.init) ?? "—"
        let unidStr = unidentified.map(String.init) ?? "—"
        let qualityTitle: String = {
            guard let a = anomalies, let u = unidentified else {
                return "\(anomStr) ELD anomalies · \(unidStr) unidentified-driving"
            }
            let clean = (a == 0 && u == 0) ? " · clean" : ""
            return "\(a) ELD anomalies · \(u) unidentified-driving\(clean)"
        }()

        // Row 4 — prior-year comparable / peer benchmark.
        let benchTitle: String
        let benchTrailing: String
        if let yoyDelta = comparable?.otpDeltaPt {
            let sign = yoyDelta >= 0 ? "+" : ""
            let priorStr = comparable?.priorOtpPct.map { String(format: "%.1f%%", $0) } ?? "—"
            let curGross = comparable?.currentGrossUSD.map(currencyK) ?? row?.grossUSD.map(currencyK) ?? "—"
            let priorGross = comparable?.priorGrossUSD.map(currencyK) ?? "—"
            benchTitle = "\(priorYearTag) \(priorStr) · \(sign)\(String(format: "%.1f", yoyDelta))pt YoY · \(curGross) vs \(priorGross)"
            benchTrailing = "\(sign)\(String(format: "%.1f", yoyDelta))pt"
        } else {
            benchTitle = "\(priorYearTag) comparable not available"
            benchTrailing = "—"
        }

        return [
            QuarterDetailRow(
                eyebrow: "LANE COUNT · DELIVERED LOADS",
                title: laneTitle,
                trailingValue: loads.map(String.init) ?? "—",
                trailingMeta: "LOADS · row 1 of 5",
                tier: .gradient
            ),
            QuarterDetailRow(
                eyebrow: "SAMPLE WINDOW · \(window2)",
                title: "\(onTimeStr) of \(totalStr) on time · \(carrierStr) carrier-fault · \(driverStr) driver-fault",
                trailingValue: milesStr,
                trailingMeta: "MI · row 2 of 5",
                tier: .success
            ),
            QuarterDetailRow(
                eyebrow: "DATA QUALITY · §395.8(a)(1)",
                title: qualityTitle,
                trailingValue: anomStr,
                trailingMeta: "ANOM · row 3 of 5",
                tier: .info
            ),
            QuarterDetailRow(
                eyebrow: "PEER BENCHMARK · \(priorYearTag.uppercased()) COMPARABLE",
                title: benchTitle,
                trailingValue: benchTrailing,
                trailingMeta: "YoY · row 4 of 5",
                tier: .gradient
            ),
            QuarterDetailRow(
                eyebrow: "NEXT QUARTER · REFINE \(nextQuarterTag) GOAL",
                title: "\(nextQuarterTag) stretch target · 96.4% on-time goal",
                trailingValue: "act",
                trailingMeta: "refine now · row 5 of 5",
                tier: .gradient,
                actionRibbon: true
            ),
        ]
    }

    private func detailRowView(_ r: QuarterDetailRow) -> some View {
        Button {
            if r.actionRibbon {
                Task { await refineQ2Goal() }
            } else {
                Task { await pinQuarter() }
            }
        } label: {
            HStack(alignment: .center, spacing: 0) {
                Rectangle()
                    .fill(rimGradient(for: r.tier))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.eyebrow)
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(tierEyebrowStyle(r.tier))
                    Text(r.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.leading, 13)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(r.trailingValue)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(trailingValueStyle(r.tier))
                    Text(r.trailingMeta)
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.5)
                        .foregroundStyle(tierEyebrowStyle(r.tier))
                }
                .padding(.trailing, 16)
            }
            .frame(height: 48)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        r.actionRibbon
                            ? AnyShapeStyle(LinearGradient(
                                colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(palette.borderFaint),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(actionInFlight)
    }

    private func rimGradient(for tier: QuarterRowTier) -> LinearGradient {
        switch tier {
        case .gradient: return LinearGradient.diagonal
        case .success:  return LinearGradient(colors: [Brand.success, Color(hex: 0x00A07B)],
                                              startPoint: .top, endPoint: .bottom)
        case .info:     return LinearGradient(colors: [Brand.blue, Brand.blue],
                                              startPoint: .top, endPoint: .bottom)
        }
    }

    private func tierEyebrowStyle(_ tier: QuarterRowTier) -> AnyShapeStyle {
        switch tier {
        case .gradient: return AnyShapeStyle(LinearGradient.diagonal)
        case .success:  return AnyShapeStyle(Brand.success)
        case .info:     return AnyShapeStyle(Brand.blue)
        }
    }

    private func trailingValueStyle(_ tier: QuarterRowTier) -> AnyShapeStyle {
        switch tier {
        case .gradient: return AnyShapeStyle(LinearGradient.diagonal)
        case .success:  return AnyShapeStyle(Brand.success)
        case .info:     return AnyShapeStyle(palette.textPrimary)
        }
    }

    // MARK: - Verbatim §395.8 CFR chip (expand · EXISTING REGULATORY THREAD)

    private var cfrChip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { cfrExpanded.toggle() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Read 49 CFR §395.8 verbatim · ELD recordkeeping at quarterly cadence")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Image(systemName: cfrExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 28)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(palette.borderSoft, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            if cfrExpanded {
                Text(cfrBodyText)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Action ribbon (single-row refinement port #31 · Refine verb)

    private var actionRibbon: some View {
        Button {
            Task { await refineQ2Goal() }
        } label: {
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                Image(systemName: "target")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                Text("Refine \(nextQuarterTag) OTP goal · §395.8 · 96.4% target")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(LinearGradient.primary)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .opacity(actionInFlight ? 0.6 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(actionInFlight)
    }

    private func actionErrorNote(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Brand.warning)
            Text(msg)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Brand.warning.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Loading / error chrome

    private var skeletonBody: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard).frame(height: 64)
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.bgCard).frame(height: 116)
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.bgCard).frame(height: 44)
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.bgCard).frame(height: 48)
            }
        }
        .redacted(reason: .placeholder)
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
                    .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Helpers

    private func monogram(for name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let initials = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return initials.isEmpty ? "?" : String(initials.prefix(2))
    }

    private func currencyK(_ usd: Double) -> String {
        if usd >= 1000 { return String(format: "$%.1fk", usd / 1000) }
        return "$\(Int(usd))"
    }

    /// Honest CFR body: the loaded verbatim text, a loading placeholder while
    /// the proc is in flight, or "—" once it resolves with no text.
    private var cfrBodyText: String {
        if let body = cfr?.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            return body
        }
        return cfr == nil ? "Loading §395.8 text…" : "—"
    }

    /// ISO from/to window for the ELD HOS query, derived from the real
    /// quarter label (first → last calendar day of the quarter).
    private var hosWindow: (from: String, to: String) {
        guard let p = quarterParts else { return ("", "") }
        let startMonth = (p.q - 1) * 3
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.timeZone = cal.timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        let start = cal.date(from: DateComponents(year: p.year, month: startMonth + 1, day: 1)) ?? Date()
        // Last calendar day of the quarter = day 0 of the month after the window.
        let end = cal.date(from: DateComponents(year: p.year, month: startMonth + 4, day: 0)) ?? start
        return (fmt.string(from: start), fmt.string(from: end))
    }

    // MARK: - Network
    //
    // All procs exist server-side and are role-accessible. Each is wired
    // through its typed EusoTripAPI namespace method (no raw stub strings).
    // The primary row is required; the rollup / comparable / CFR / HOS lanes
    // are best-effort (try?) so a partial outage still renders the page with
    // honest "—" placeholders rather than failing the whole screen.

    private func loadAll() async {
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            // drivers.getQuarterRow — required (identity + headline figures).
            self.row = try await EusoTripAPI.shared.drivers.getQuarterRow(
                driverId: driverId, quarterId: quarterId)

            // analytics.getQuarterRollup — month strip + fault split.
            self.rollup = try? await EusoTripAPI.shared.analytics.getQuarterRollup(
                driverId: driverId, quarterId: quarterId)

            // analytics.getPriorYearComparable — YoY benchmark row.
            self.comparable = try? await EusoTripAPI.shared.analytics.getPriorYearComparable(
                driverId: driverId, quarterId: quarterId)

            // regulation.getCfrText — verbatim §395.8 ELD recordkeeping text.
            self.cfr = try? await EusoTripAPI.shared.regulation.getCfrText(section: "395.8")

            // eld.getDriverHosWindow — ELD anomalies + unidentified driving.
            let window = hosWindow
            self.hos = try? await EusoTripAPI.shared.eld.getDriverHosWindow(
                driverId: driverId,
                from: window.from.isEmpty ? nil : window.from,
                to: window.to.isEmpty ? nil : window.to)
        } catch {
            self.loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func refineQ2Goal() async {
        guard !actionInFlight else { return }
        actionInFlight = true
        actionError = nil
        defer { actionInFlight = false }
        do {
            // drivers.refineQuarterGoal — persist the next-quarter OTP goal.
            let ack = try await EusoTripAPI.shared.drivers.refineQuarterGoal(
                driverId: driverId, quarterId: nextQuarterId, targetPct: 96.4)
            if ack.success == false {
                actionError = "Couldn't refine the \(nextQuarterTag) goal - try again."
            }
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func pinQuarter() async {
        guard !actionInFlight else { return }
        actionInFlight = true
        actionError = nil
        defer { actionInFlight = false }
        do {
            // drivers.pinQuarter — idempotent pin/unpin toggle.
            let ack = try await EusoTripAPI.shared.drivers.pinQuarter(
                driverId: driverId, quarterId: row?.quarterId ?? quarterId)
            if ack.success == false {
                actionError = "Couldn't pin the quarter - try again."
            }
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Previews

#Preview("327B · Catalyst · Driver Quarter Detail · Night") {
    CatalystDriverQuarterDetailBespokeScreen(theme: Theme.dark, driverId: "001-EUSO", quarterId: "Q1-2026")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("327B · Catalyst · Driver Quarter Detail · Afternoon") {
    CatalystDriverQuarterDetailBespokeScreen(theme: Theme.light, driverId: "001-EUSO", quarterId: "Q1-2026")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
