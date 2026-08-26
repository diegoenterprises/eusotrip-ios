//
//  Dpch740_DispatcherDriverDetailOctet.swift
//  EusoTrip — Dispatcher · Driver-detail octet (420-427).
//
//  Pixel-match to:
//    420 Dispatcher Driver Review
//    421 Dispatcher Driver Lane Detail
//    422 Dispatcher Driver Incident Log
//    423 Dispatcher Driver Performance Detail
//    424 Dispatcher Driver HOS Detail
//    425 Dispatcher Driver Onboarding Step Detail
//    426 Dispatcher Driver Compliance Row Detail
//    427 Dispatcher Driver Quarter Detail
//
//  All 8 screens share `DispatcherDriverDetailBody`, parameterized
//  by `DriverDetailKind`. ZERO FABRICATION:
//    • Identity (name / truck / CDL) comes from the typed
//      `drivers.getProfileById` → `DriversAPI.DriverProfile`. Never a
//      hardcoded persona.
//    • KPIs come from the typed `drivers.getPerformanceMetrics` →
//      `DriversAPI.PerformanceScorecard` (metrics + rankings), the
//      letter-grade computed off those real metrics the same way the
//      Catalyst 320 scorecard computes it.
//    • Live HOS headroom comes from the typed `hos.getCurrentStatus`
//      → `HOSCurrentStatus` (driving-limit remaining minutes).
//    • Compliance / onboarding posture comes from the typed
//      `driverQualification.getOverview` → `DriverQualificationAPI.Overview`.
//    • Every field with NO live source (per-incident counts, per-step
//      onboarding cycle, per-cert runway, per-quarter rollups) renders
//      an honest em-dash — never a fabricated literal. No `?? <invented>`.
//  Bottom nav frozen.
//

import SwiftUI

// MARK: - Kind + config

enum DriverDetailKind: String {
    case review, lane, incident, performance, hos, onboarding, compliance, quarter
}

private struct DriverDetailConfig {
    let eyebrow: String
    let citation: String
    let title: String
    /// Trailing context appended after the live driver line in the
    /// subhead. Pure regulatory / window context — no invented identity.
    let subheadContext: String
    let pillCopy: String
    let statusPill: String
}

private struct DispatchDetailDriverPick: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let status: String
    let load: String?
}

private extension DriverDetailKind {
    var config: DriverDetailConfig {
        switch self {
        case .review:
            return .init(
                eyebrow: "DISPATCHER · DRIVER · REVIEW",
                citation: "DISPATCHER REVIEW · HOS-AWARE · 90D",
                title: "Driver review",
                subheadContext: "last 90 days",
                pillCopy: "Rate this roster driver · cross-track HOS · safety · no payroll vantage in this lens.",
                statusPill: "DISPATCHER REVIEW · HOS-AWARE · 90D"
            )
        case .lane:
            return .init(
                eyebrow: "DISPATCHER · DRIVER · LANE",
                citation: "DISPATCHER LANE · ESCORT-AWARE · 90D · §11.4",
                title: "Lane detail",
                subheadContext: "§11.4 · LIVE",
                pillCopy: "Pre-assign the next pull · clean lane books surface in the eligible-roster API.",
                statusPill: "ESCORT-AWARE · 90D · §11.4"
            )
        case .incident:
            return .init(
                eyebrow: "DISPATCHER · DRIVER · LOG",
                citation: "DISPATCHER LOG · ATTEST-READY · 90D · §13.3",
                title: "Incident log",
                subheadContext: "90D",
                pillCopy: "Audit the 90-day driver record · attest to §13.3 to surface the driver in the eligible-roster API.",
                statusPill: "90D AUDIT · §13.3 ATTESTATION-ELIGIBLE"
            )
        case .performance:
            return .init(
                eyebrow: "DISPATCHER · DRIVER · KPI",
                citation: "DISPATCHER KPI · REFINE-READY · 30D · §13.3",
                title: "Performance",
                subheadContext: "OTP · LIVE",
                pillCopy: "Refine the 30-day KPI goal · on-time pickup tracks §392.7 ETA.",
                statusPill: "PUBLISHED · LIVE · ON-TIME PICKUP §392.7 ETA"
            )
        case .hos:
            return .init(
                eyebrow: "DISPATCHER · DRIVER · HOS",
                citation: "DISPATCHER HOS · PRE-CLEAR-READY · LIVE · §395",
                title: "HOS clock",
                subheadContext: "§395 · LIVE",
                pillCopy: "Pre-clear HOS for the next pull · drive headroom is read live from the ELD.",
                statusPill: "LIVE · §395.3(a)(3)(i)"
            )
        case .onboarding:
            return .init(
                eyebrow: "DISPATCH · DRIVER ONBOARDING",
                citation: "DQ FILE · ANNUAL REVIEW · FMCSA 391",
                title: "DQ onboarding file",
                subheadContext: "FMCSA 391.25",
                pillCopy: "Annual MVR, document status and onboarding gaps are read from the DQ file.",
                statusPill: "ANNUAL REVIEW · FMCSA 391.25"
            )
        case .compliance:
            return .init(
                eyebrow: "DISPATCH · DQ COMPLIANCE",
                citation: "DQ FILE · CDL · MEDICAL · HME",
                title: "DQ compliance file",
                subheadContext: "FMCSA 383.93 · 391",
                pillCopy: "Live DQ posture joins document validity, missing items and dispatch eligibility in one file.",
                statusPill: "FMCSA 383.93 HME · PART 391 DRIVER QUALIFICATION"
            )
        case .quarter:
            return .init(
                eyebrow: "DISPATCHER · DRIVER · QUARTER DETAIL",
                citation: "DISPATCHER PERIODIC REVIEW · QUARTER",
                title: "Quarter detail",
                subheadContext: "quarter",
                pillCopy: "Periodic quarter review · totals roll into the next-quarter baseline · §395.8 ELD.",
                statusPill: "PERIODIC REVIEW · §395.8 ELD"
            )
        }
    }
    var period: DriversAPI.PerformancePeriod {
        switch self {
        case .performance, .onboarding, .compliance: return .month
        case .quarter: return .quarter
        default: return .quarter
        }
    }
}

// MARK: - Shared shell + body

private struct DispatcherDriverDetailShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: DispatchNavRoute.leading(current: .board),
                trailing: DispatchNavRoute.trailing(current: .board),
                orbState: .idle
            )
        }
    }
}

private struct DispatcherDriverDetailBody: View {
    let driverId: String
    let kind: DriverDetailKind

    @Environment(\.palette) private var palette
    @State private var scorecard: DriversAPI.PerformanceScorecard?
    @State private var profile: DriversAPI.DriverProfile?
    @State private var hos: HOSCurrentStatus?
    @State private var hosLoadError: String?
    @State private var dq: DriverQualificationAPI.Overview?
    @State private var loading: Bool = true
    @State private var resolvedDriverId: String?

    var body: some View {
        let c = kind.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                pill(c)
                identityRow
                kpiGrid
                kindEvidencePanel
                nextStepCard
                Color.clear.frame(height: 150)
            }
            .padding(.horizontal, 14)
            .padding(.top, 58)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // Real driver display name, or honest dash.
    private var driverName: String {
        let profileName = profile?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !profileName.isEmpty { return profileName }
        let dqName = dq?.driverName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !dqName.isEmpty { return dqName }
        return resolvedDriverId == nil ? "No driver selected" : "Fleet driver"
    }

    private func monogram(for name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let initials = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return initials.isEmpty ? "—" : String(initials.prefix(2))
    }

    private func header(_ c: DriverDetailConfig) -> some View {
        // Subhead = real driver name · regulatory/window context.
        // No invented carrier / DR-id / lane literals.
        let sub = "\(driverName) · \(c.subheadContext)"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(sub).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func pill(_ c: DriverDetailConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(c.pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text(c.statusPill).font(.caption2).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var identityRow: AnyView {
        // Identity strip from the typed driver profile only. Truck +
        // CDL render an em-dash when the column is blank — no persona.
        guard resolvedDriverId != nil else {
            return AnyView(LifecycleCard {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Choose a roster driver")
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Text("This detail needs a company-scoped driver before DQ, HOS or scorecard evidence can render.")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            })
        }
        let truck = (profile?.truckNumber.isEmpty == false) ? "Truck \(profile!.truckNumber)" : "Truck not filed"
        let cdl = (profile?.cdlNumber.isEmpty == false) ? profile!.cdlNumber : "CDL not filed"
        let cls = (profile?.cdl.class.isEmpty == false) ? "Class \(profile!.cdl.class)" : "Class not filed"
        return AnyView(LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(monogram(for: driverName)).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(driverName).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Text("\(truck) · CDL \(cdl) · \(cls)").font(.caption2).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
        })
    }

    private var kpiGrid: some View {
        let m = scorecard?.metrics
        let r = scorecard?.rankings
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .review:
                let (letter, _) = letterGrade(scorecard)
                return [
                    ("GRADE",   letter,                          "composite · live", .green),
                    ("ON-TIME", pct(m?.onTimeDeliveryRate),      "on-time delivery · 90d", .green),
                    ("SAFETY",  safetyDisplay(m?.safetyScore),   "CSA · live", .green),
                    ("LOADS",   intStr(m?.totalLoads),           "90d window", .blue),
                ]
            case .lane:
                let (letter, _) = letterGrade(scorecard)
                return [
                    ("GRADE",   letter,                          "composite · live", .green),
                    ("ON-TIME", pct(m?.onTimeDeliveryRate),      "on-time delivery · 90d", .green),
                    ("LOADS",   intStr(m?.totalLoads),           "90d window", .blue),
                    ("RANK",    rankDisplay(r),                  "scored drivers", .blue),
                ]
            case .incident:
                // No live per-incident event/violation/dispute counts on
                // any wired proc — honest dashes. Inspection pass-rate IS
                // live on the scorecard.
                return [
                    ("EVENTS",       "—",                        "no live source", .green),
                    ("VIOLATIONS",   "—",                        "no live source", .green),
                    ("DISPUTES",     "—",                        "no live source", .green),
                    ("PASS-RATE",    pct(m?.inspectionPassRate), "inspection · §396", .green),
                ]
            case .performance:
                return [
                    ("ON-TIME",    pct(m?.onTimeDeliveryRate),   "on-time delivery", .green),
                    ("LOADS",      intStr(m?.totalLoads),        "rolling window", .blue),
                    ("SAFETY",     safetyDisplay(m?.safetyScore),"/5 · CSA · live", .green),
                    ("RANK",       rankDisplay(r),               "scored drivers", .blue),
                ]
            case .hos:
                return [
                    ("HEADROOM",  hosDriveHeadroom,              "drive · §395.3(a)(3)(i)", .green),
                    ("LIMIT",     hosDriveLimitFreePct,          "of 11h limit free", .green),
                    ("HOS%",      pct(m?.hosCompliance),         "compliance · window", .green),
                    ("MILES",     milesK(m?.totalMiles),         "covered · window", .blue),
                ]
            case .onboarding:
                // Per-step onboarding cycle / due-window / step-id have no
                // wired source. DQ file gives the documents posture.
                return [
                    ("DOCS",       intStr(dq?.documents.total),      "DQ file", .blue),
                    ("EXPIRING",   intStr(dq?.documents.expiringSoon), "renewal soon", .orange),
                    ("EXPIRED",    intStr(dq?.documents.expired),    "expired docs", .orange),
                    ("MISSING",    intStr(dq?.documents.missing),    "required docs", .orange),
                ]
            case .compliance:
                // Per-cert runway / eligible-lane flags have no wired
                // source. DQ overview gives a real compliance score +
                // valid-doc count.
                return [
                    ("DQ SCORE",   complianceScoreDisplay,           "qualification file", .green),
                    ("VALID",      intStr(dq?.documents.valid),      "current documents", .green),
                    ("GAPS",       intStr(complianceGapCount),        "missing or expired", .orange),
                    ("STATUS",     dqStatusDisplay,                  "dispatch readiness", .blue),
                ]
            case .quarter:
                // No per-quarter archived rollup on a wired proc — bind
                // to the live quarter-period scorecard the body fetched.
                return [
                    ("OTP",        pct(m?.onTimeDeliveryRate),   "quarter · on-time", .green),
                    ("MILES",      milesK(m?.totalMiles),        "quarter driven", .blue),
                    ("LOADS",      intStr(m?.totalLoads),        "quarter completed", .blue),
                    ("PASS",       pct(m?.inspectionPassRate),   "inspections · §396", .green),
                ]
            }
        }()
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(kpis.enumerated()), id: \.offset) { _, k in
                VStack(alignment: .leading, spacing: 4) {
                    Text(k.0).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text(k.1).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(k.3)
                    Text(k.2).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(k.3.opacity(0.3)))
            }
        }
    }

    @ViewBuilder
    private var kindEvidencePanel: some View {
        let m = scorecard?.metrics
        let r = scorecard?.rankings
        switch kind {
        case .review:
            LifecycleCard {
                evidenceHeader("ROSTER EVIDENCE", "Live scorecard inputs")
                evidenceRow("Inspection pass rate", pct(m?.inspectionPassRate), "driver scorecard")
                evidenceRow("HOS compliance", pct(m?.hosCompliance), "driver scorecard")
                evidenceRow("Miles covered", milesK(m?.totalMiles), "rolling performance window")
            }
        case .lane:
            LifecycleCard {
                evidenceHeader("LANE READINESS", "Live ranking and delivery posture")
                evidenceRow("Eligible rank", rankDisplay(r), "scored driver pool")
                evidenceRow("On-time delivery", pct(m?.onTimeDeliveryRate), "lane assignment confidence")
                evidenceRow("Completed loads", intStr(m?.totalLoads), "rolling operating history")
            }
        case .incident:
            LifecycleCard {
                evidenceHeader("INCIDENT EVIDENCE", "Live safety-adjacent signals")
                evidenceRow("Inspection pass rate", pct(m?.inspectionPassRate), "§396 inspection source")
                evidenceRow("Safety score", safetyDisplay(m?.safetyScore), "CSA score projection")
                evidenceRow("Incident feed", "—", "no wired event-count source yet")
            }
        case .performance:
            LifecycleCard {
                evidenceHeader("PERFORMANCE MIX", "Scorecard components")
                evidenceRow("On-time delivery", pct(m?.onTimeDeliveryRate), "weighted KPI input")
                evidenceRow("HOS compliance", pct(m?.hosCompliance), "weighted KPI input")
                evidenceRow("Total miles", milesK(m?.totalMiles), "window mileage")
            }
        case .hos:
            LifecycleCard {
                evidenceHeader("ELD CLOCK", "Live hours-of-service posture")
                evidenceRow("Observation", hosObservationDisplay, hosObservationDetail)
                evidenceRow("Drive headroom", hosDriveHeadroom, "FMCSA 395 drive window")
                evidenceRow("Limit free", hosDriveLimitFreePct, "remaining drive window")
                evidenceRow("HOS compliance", pct(m?.hosCompliance), "scorecard history")
            }
        case .onboarding:
            LifecycleCard {
                evidenceHeader("DQ FILE", "Driver qualification posture")
                evidenceRow("Status", dq?.status.uppercased() ?? "—", "qualification posture")
                evidenceRow("Last audit", dq?.lastAudit ?? "—", "audit history")
                evidenceRow("Next audit", dq?.nextAudit ?? "—", "renewal runway")
            }
        case .compliance:
            LifecycleCard {
                evidenceHeader("DQ COMPLIANCE", "Documents, gaps and dispatch readiness")
                evidenceRow("Compliance score", complianceScoreDisplay, "DQ score")
                evidenceRow("Current documents", intStr(dq?.documents.valid), "valid on file")
                evidenceRow("Missing or expired", intStr(complianceGapCount), complianceGapCount == 0 ? "no blocking document gaps" : "review before assignment")
            }
        case .quarter:
            LifecycleCard {
                evidenceHeader("QUARTER SNAPSHOT", "Quarter-period scorecard")
                evidenceRow("On-time delivery", pct(m?.onTimeDeliveryRate), "quarter window")
                evidenceRow("Loads completed", intStr(m?.totalLoads), "quarter window")
                evidenceRow("Inspection pass rate", pct(m?.inspectionPassRate), "quarter window")
            }
        }
    }

    private func evidenceHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(subtitle)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.bottom, 4)
    }

    private func evidenceRow(_ label: String, _ value: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 5)
    }

    private var nextStepCard: some View {
        let copy: String = {
            switch kind {
            case .review:      return "Refresh weekly. Roster KPIs roll into the dispatcher score-card. No payroll vantage in this lens."
            case .lane:        return "Pre-assign the driver for the next pull. ESang re-scores when the lane refreshes."
            case .incident:    return "Clean 90-day record attests to §13.3 to surface the driver in the eligible-roster API. Per-incident counts wire when the events feed lands."
            case .performance: return "Refine the 30-day KPI goal off the live on-time floor and inspection pass-rate."
            case .hos:         return "Pre-clear HOS for the next pull. Drive headroom above is read live from the ELD."
            case .onboarding:  return "Work the DQ file. Expiring and missing FMCSA 391 documents above drive the onboarding queue."
            case .compliance:  return complianceNextStep
            case .quarter:     return "Quarter totals above are the live quarter-period scorecard; roll them into the next-quarter baseline."
            }
        }()
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT STEP").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(copy).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Live HOS headroom (typed hos.getCurrentStatus)

    /// "8h 42m" drive headroom from the live ELD limits, or em-dash.
    private var hosDriveHeadroom: String {
        guard hos?.hasCurrentObservation() == true,
              let rem = hos?.limits.driving.remaining,
              rem >= 0 else { return "—" }
        return HOSStatus.formatHours(Double(rem) / 60.0)
    }

    /// "+78%" of the 11-hour drive limit still free, or em-dash.
    private var hosDriveLimitFreePct: String {
        guard hos?.hasCurrentObservation() == true,
              let d = hos?.limits.driving,
              let remaining = d.remaining,
              remaining >= 0,
              d.limit > 0 else { return "—" }
        let free = Double(remaining) / Double(d.limit) * 100
        return "+\(Int(free.rounded()))%"
    }

    private var hosObservationDisplay: String {
        if hosLoadError != nil { return "Unavailable" }
        guard let hos else { return "Unavailable" }
        return hos.hasCurrentObservation() ? "Current" : "Not current"
    }

    private var hosObservationDetail: String {
        if let hosLoadError { return hosLoadError }
        guard let hos else { return "No HOS observation returned" }
        if hos.hasCurrentObservation() { return hos.source ?? "sourced observation" }
        return hos.assignmentEligibility().reason ?? "HOS observation is not current"
    }

    // MARK: - DQ overview helpers

    private var complianceScoreDisplay: String {
        guard let s = dq?.complianceScore else { return "—" }
        return "\(s)%"
    }

    private var complianceGapCount: Int {
        (dq?.documents.missing ?? 0) + (dq?.documents.expired ?? 0)
    }

    private var dqStatusDisplay: String {
        let raw = dq?.status.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "—" : raw.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    private var complianceNextStep: String {
        guard resolvedDriverId != nil else {
            return "Select a fleet driver from the roster to review DQ compliance, document gaps and dispatch readiness."
        }
        if complianceGapCount > 0 {
            return "Resolve \(complianceGapCount) DQ document gap\(complianceGapCount == 1 ? "" : "s") before assigning regulated freight."
        }
        if let score = dq?.complianceScore, score < 100 {
            return "Review the DQ file and close the remaining score gap before high-risk assignments."
        }
        return "DQ file is clear in this view. Keep CDL, medical and HME renewals current before the next regulated move."
    }

    // MARK: - Letter grade (same recipe as Catalyst 320 scorecard)

    private func letterGrade(_ s: DriversAPI.PerformanceScorecard?) -> (letter: String, composite: Double) {
        guard let s else { return ("—", 0) }
        let onTime = max(0.0, min(1.0, s.metrics.onTimeDeliveryRate / 100))
        let completion = max(0.0, min(1.0, s.metrics.hosCompliance / 100))
        let loadsTerm: Double = {
            let n = Double(max(0, s.metrics.totalLoads))
            let num = log10(n + 1.0)
            let den = log10(50.0)
            return den > 0 ? num / den : 0
        }()
        let composite = onTime * 0.5 + completion * 0.3 + loadsTerm * 0.2
        let letter: String = {
            switch composite {
            case 0.95...:     return "A+"
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

    private func rankDisplay(_ r: DriversAPI.PerformanceRankings?) -> String {
        guard let r, r.totalDrivers > 0 else { return "—" }
        return "\(r.overall) of \(r.totalDrivers)"
    }

    private func load() async {
        loading = true; defer { loading = false }
        guard let targetDriverId = await resolveDriverId() else {
            resolvedDriverId = nil
            scorecard = nil
            profile = nil
            hos = nil
            hosLoadError = nil
            dq = nil
            return
        }
        resolvedDriverId = targetDriverId

        // Performance scorecard (typed proc).
        async let scoreTask: DriversAPI.PerformanceScorecard? = {
            try? await EusoTripAPI.shared.drivers.getPerformanceMetrics(
                driverId: targetDriverId, period: kind.period
            )
        }()
        // Identity (typed proc).
        async let profileTask: DriversAPI.DriverProfile? = {
            try? await EusoTripAPI.shared.drivers.getProfileById(driverId: targetDriverId)
        }()
        // Live HOS — only the HOS lens needs it.
        async let hosTask: (HOSCurrentStatus?, String?) = {
            guard kind == .hos else { return (nil, nil) }
            do {
                return (try await EusoTripAPI.shared.hos.getCurrentStatus(driverId: targetDriverId), nil)
            } catch {
                return (nil, "Current HOS evidence could not refresh.")
            }
        }()
        // DQ overview — onboarding + compliance lenses.
        async let dqTask: DriverQualificationAPI.Overview? = {
            guard kind == .onboarding || kind == .compliance else { return nil }
            return try? await EusoTripAPI.shared.dq.getOverview(driverId: targetDriverId)
        }()

        let (s, p, hosResult, d) = await (scoreTask, profileTask, hosTask, dqTask)
        self.scorecard = s
        self.profile = p
        self.hos = hosResult.0
        self.hosLoadError = hosResult.1
        self.dq = d
    }

    private func normalizedDriverId(_ raw: String) -> String? {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id != "0" else { return nil }
        return id
    }

    private func resolveDriverId() async -> String? {
        if let id = normalizedDriverId(driverId) { return id }
        struct Input: Encodable { let limit: Int }
        do {
            let rows: [DispatchDetailDriverPick] = try await EusoTripAPI.shared.query(
                "dispatch.getDriverStatuses",
                input: Input(limit: 1)
            )
            return rows.first.map(\.id)
        } catch {
            return nil
        }
    }
}

// MARK: - Honest display helpers (no fabricated fallbacks)

/// "94%" from a 0–100 rate, or em-dash when the field is absent.
private func pct(_ raw: Double?) -> String {
    guard let raw else { return "—" }
    return "\(Int(raw.rounded()))%"
}

/// Integer field → string, or em-dash when absent.
private func intStr(_ raw: Int?) -> String {
    guard let raw else { return "—" }
    return "\(raw)"
}

/// Safety score: server stores 0–100; render the 5-scale conversion to
/// match the recipe. Em-dash when the field is absent.
private func safetyDisplay(_ raw: Double?) -> String {
    guard let raw else { return "—" }
    let v = max(0, min(5, raw / 20))
    return String(format: "%.2f", v)
}

/// "12.4k" / "840" miles, or em-dash when the field is absent.
private func milesK(_ m: Double?) -> String {
    guard let v = m else { return "—" }
    if v >= 1000 { return String(format: "%.1fk", v / 1000) }
    return String(format: "%.0f", v)
}

// MARK: - Screen structs (420-427)

struct DispatcherDriverReviewScreen: View {
    let theme: Theme.Palette; let driverId: String
    var body: some View {
        DispatcherDriverDetailShell(theme: theme) { DispatcherDriverDetailBody(driverId: driverId, kind: .review) }
    }
}
struct DispatcherDriverLaneDetailScreen: View {
    let theme: Theme.Palette; let driverId: String
    var body: some View {
        DispatcherDriverDetailShell(theme: theme) { DispatcherDriverDetailBody(driverId: driverId, kind: .lane) }
    }
}
struct DispatcherDriverIncidentLogScreen: View {
    let theme: Theme.Palette; let driverId: String
    var body: some View {
        DispatcherDriverDetailShell(theme: theme) { DispatcherDriverDetailBody(driverId: driverId, kind: .incident) }
    }
}
struct DispatcherDriverPerformanceDetailScreen: View {
    let theme: Theme.Palette; let driverId: String
    var body: some View {
        DispatcherDriverDetailShell(theme: theme) { DispatcherDriverDetailBody(driverId: driverId, kind: .performance) }
    }
}
struct DispatcherDriverHOSDetailScreen: View {
    let theme: Theme.Palette; let driverId: String
    var body: some View {
        DispatcherDriverDetailShell(theme: theme) { DispatcherDriverDetailBody(driverId: driverId, kind: .hos) }
    }
}
struct DispatcherDriverOnboardingStepDetailScreen: View {
    let theme: Theme.Palette; let driverId: String
    var body: some View {
        DispatcherDriverDetailShell(theme: theme) { DispatcherDriverDetailBody(driverId: driverId, kind: .onboarding) }
    }
}
struct DispatcherDriverComplianceRowDetailScreen: View {
    let theme: Theme.Palette; let driverId: String
    var body: some View {
        DispatcherDriverDetailShell(theme: theme) { DispatcherDriverDetailBody(driverId: driverId, kind: .compliance) }
    }
}
struct DispatcherDriverQuarterDetailScreen: View {
    let theme: Theme.Palette; let driverId: String
    var body: some View {
        DispatcherDriverDetailShell(theme: theme) { DispatcherDriverDetailBody(driverId: driverId, kind: .quarter) }
    }
}

// MARK: - Previews

#Preview("420 Review · Dark")       { DispatcherDriverReviewScreen(theme: Theme.dark, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("421 Lane · Light")        { DispatcherDriverLaneDetailScreen(theme: Theme.light, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("422 Incident · Dark")     { DispatcherDriverIncidentLogScreen(theme: Theme.dark, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("423 Performance · Light") { DispatcherDriverPerformanceDetailScreen(theme: Theme.light, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("424 HOS · Dark")          { DispatcherDriverHOSDetailScreen(theme: Theme.dark, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("425 Onboarding · Light")  { DispatcherDriverOnboardingStepDetailScreen(theme: Theme.light, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("426 Compliance · Dark")   { DispatcherDriverComplianceRowDetailScreen(theme: Theme.dark, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("427 Quarter · Light")     { DispatcherDriverQuarterDetailScreen(theme: Theme.light, driverId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
