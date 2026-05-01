//
//  085_MeCarrierScorecard.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · carrier scorecard)
//
//  Screen 085 · Me · Carrier Scorecard — a driver-facing read of
//  the carrier's public CSA (Compliance, Safety, Accountability)
//  scorecard. Surfaces the 7 FMCSA Behavior Analysis and Safety
//  Improvement Categories (BASICs), SAFER out-of-service rates, the
//  24-month FMCSA crash + inspection summary, and the overall
//  Safety Fitness Determination in one glanceable pane.
//
//  Why drivers need this:
//    • Every violation the driver racks up rolls into their carrier's
//      BASIC percentile. Drivers who see the scorecard understand
//      the downstream impact of a roadside inspection, and — having
//      just learned from 084 that DataQs lets them contest those
//      events — can connect self-action to the scoreboard they see.
//    • Drivers in a job search use CSA percentiles to evaluate new
//      carriers. Making this data one tap away keeps them on the
//      platform instead of bouncing out to SAFER Web.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • Every number comes from the live `csaScores.getOverview`
//      proc — MCP-verified at `frontend/server/routers/csaScores.ts:23`.
//      Server pulls directly from FMCSA's 9.8M-row bulk dataset
//      when the carrier's USDOT is on file; falls back to
//      platform-internal signals otherwise. The view surfaces the
//      `dataSource` flag so the driver can tell which.
//
//    • SAFER OOS rates compare to the FMCSA national average in
//      the response (typically ~0.21 for driver OOS). Above-average
//      rates render with `Brand.warning` tint.
//
//    • BASIC percentiles use the actual FMCSA thresholds (65 for
//      safety-sensitive, 80 for others). Gradient fill width tracks
//      proportionally against 100 so a 63 percentile vs 68 is
//      visually distinct.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on percentile fills (under
//         threshold) + overall-good hero. Brand.warning reserved
//         for categories where `alert = true` or at/above threshold.
//    §4   Tokenized spacing, radii, type.
//    §5   Palette semantic throughout.
//    §7   Ternary ShapeStyle wrapped in AnyShapeStyle.
//    §10  Previews land in `.error` under the preview runtime. No
//         fixtures.
//

import SwiftUI

// MARK: - Screen root

struct MeCarrierScorecard: View {
    @Environment(\.palette) var palette
    @StateObject private var store = CarrierScorecardStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                switch store.state {
                case .loading:
                    skeleton
                case .empty:
                    emptyHero
                case .error(let e):
                    errorBanner(e)
                case .loaded(let overview):
                    carrierIdCard(overview)
                    overallStatusHero(overview)
                    basicsSection(overview)
                    if let safer = overview.saferData {
                        saferSection(safer, overview: overview)
                    }
                    if let crashes = overview.fmcsaCrashes {
                        crashesSection(crashes)
                    }
                    if let insp = overview.fmcsaInspections {
                        inspectionsSection(insp)
                    }
                }
                disclosureFooter
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("CSA Scorecard")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("FMCSA BASIC percentiles · SAFER · crashes")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: States

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.45))
                .frame(height: 96)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.35))
                .frame(height: 140)
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.3))
                    .frame(height: 62)
            }
        }
    }

    private var emptyHero: some View {
        EusoEmptyState(
            systemImage: "building.columns",
            title: "Scorecard unavailable",
            subtitle: "We couldn't load your carrier's CSA scorecard. Pull to refresh."
        )
    }

    private func errorBanner(_ err: Error) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Can't load scorecard")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(err.localizedDescription)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                Task { await store.refresh() }
            } label: {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Carrier identity

    private func carrierIdCard(_ o: CsaScoresAPI.CsaOverview) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(o.companyName.isEmpty ? "Your carrier" : o.companyName)
                .font(EType.h2)
                .foregroundStyle(palette.textPrimary)
            HStack(spacing: Space.s3) {
                if !o.dotNumber.isEmpty {
                    idPill(label: "USDOT", value: o.dotNumber)
                }
                if !o.mcNumber.isEmpty {
                    idPill(label: "MC", value: o.mcNumber)
                }
                Spacer()
            }
            if let pretty = shortDate(o.lastUpdated) {
                Text("Last updated \(pretty)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func idPill(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, Space.s2)
        .padding(.vertical, 4)
        .background(
            Capsule().strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    // MARK: Overall status hero

    private func overallStatusHero(_ o: CsaScoresAPI.CsaOverview) -> some View {
        let (icon, headline, tint, detail) = overallStatusCopy(o)
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s3) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text(detail)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            if o.outOfService == true, let reason = o.oosReason, !reason.isEmpty {
                Text("OOS reason: \(reason)")
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    o.overallStatus == "out_of_service" || o.overallStatus == "critical"
                        ? Brand.warning.opacity(0.5) : palette.borderFaint,
                    lineWidth: 1
                )
        )
    }

    private func overallStatusCopy(_ o: CsaScoresAPI.CsaOverview)
        -> (String, String, AnyShapeStyle, String) {
        switch o.overallStatus.lowercased() {
        case "out_of_service":
            return ("exclamationmark.octagon.fill", "Out of service",
                    AnyShapeStyle(Brand.warning),
                    "Carrier is currently under an out-of-service order. Contact your compliance officer before dispatching.")
        case "critical":
            return ("exclamationmark.triangle.fill", "Critical · multiple alerts",
                    AnyShapeStyle(Brand.warning),
                    "3+ BASIC categories are at or above FMCSA intervention threshold. Expect elevated inspection frequency.")
        case "alert":
            return ("exclamationmark.circle.fill", "One or more BASICs flagged",
                    AnyShapeStyle(Brand.warning),
                    "At least one category is at or above FMCSA threshold. The affected BASIC is highlighted below.")
        default:
            return ("checkmark.shield.fill", "Satisfactory",
                    AnyShapeStyle(LinearGradient.diagonal),
                    "All BASICs below FMCSA intervention thresholds.")
        }
    }

    // MARK: BASICs section

    @ViewBuilder
    private func basicsSection(_ o: CsaScoresAPI.CsaOverview) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("BASIC CATEGORIES")
                    .font(EType.micro).tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(o.basics.count)")
                    .font(EType.micro).tracking(1.1)
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: Space.s2) {
                ForEach(o.basics) { basic in
                    basicRow(basic)
                }
            }
        }
    }

    private func basicRow(_ basic: CsaScoresAPI.BasicCategory) -> some View {
        let fraction = max(0.0, min(1.0, basic.percentile / 100.0))
        return HStack(alignment: .center, spacing: Space.s3) {
            Image(systemName: iconFor(category: basic.category))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(basic.alert ? AnyShapeStyle(Brand.warning) : AnyShapeStyle(LinearGradient.diagonal))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(palette.bgCard.opacity(0.8))
                )
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(basic.name)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%.0f", basic.percentile))
                        .font(EType.bodyStrong)
                        .foregroundStyle(basic.alert ? AnyShapeStyle(Brand.warning) : AnyShapeStyle(palette.textPrimary))
                        .monospacedDigit()
                    Text("/\(basic.threshold)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(palette.tintNeutral.opacity(0.4))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(basic.alert ? AnyShapeStyle(Brand.warning) : AnyShapeStyle(LinearGradient.diagonal))
                            .frame(width: geo.size.width * fraction)
                        // Threshold marker
                        let tFrac = Double(basic.threshold) / 100.0
                        Rectangle()
                            .fill(palette.textTertiary.opacity(0.7))
                            .frame(width: 1, height: 8)
                            .offset(x: geo.size.width * tFrac)
                    }
                }
                .frame(height: 4)
                HStack(spacing: Space.s2) {
                    if basic.alert {
                        Text("FLAGGED")
                            .font(EType.micro).tracking(1.1)
                            .foregroundStyle(Brand.warning)
                    }
                    Text("\(basic.inspections) inspection\(basic.inspections == 1 ? "" : "s")")
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                    if basic.violations > 0 {
                        Text("· \(basic.violations) violation\(basic.violations == 1 ? "" : "s")")
                            .font(EType.micro)
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(basic.alert ? Brand.warning.opacity(0.4) : palette.borderFaint, lineWidth: 1)
        )
    }

    private func iconFor(category: String) -> String {
        switch category {
        case "unsafe_driving":        return "car.fill"
        case "hos_compliance":        return "clock"
        case "driver_fitness":        return "cross.case"
        case "controlled_substances": return "testtube.2"
        case "vehicle_maintenance":   return "wrench.and.screwdriver"
        case "hazmat_compliance":     return "exclamationmark.triangle"
        case "crash_indicator":       return "exclamationmark.octagon"
        default:                      return "chart.bar"
        }
    }

    // MARK: SAFER section

    private func saferSection(_ s: CsaScoresAPI.SaferData, overview _: CsaScoresAPI.CsaOverview) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("SAFER · OUT-OF-SERVICE RATES")
                .font(EType.micro).tracking(1.4)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                saferTile(
                    label: "DRIVER OOS",
                    value: percentString(s.driverOOSRate),
                    reference: "National avg \(percentString(s.nationalAverage))",
                    warn: s.driverOOSRate > s.nationalAverage
                )
                saferTile(
                    label: "VEHICLE OOS",
                    value: percentString(s.vehicleOOSRate),
                    reference: "\(s.inspectionCount24Months) insp · 24 mo",
                    warn: s.vehicleOOSRate > 0.20
                )
            }
        }
    }

    private func saferTile(label: String, value: String, reference: String, warn: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label)
                .font(EType.micro).tracking(1.1)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.numeric)
                .monospacedDigit()
                .foregroundStyle(
                    warn
                        ? AnyShapeStyle(Brand.warning)
                        : AnyShapeStyle(LinearGradient.diagonal)
                )
            Text(reference)
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(warn ? Brand.warning.opacity(0.4) : palette.borderFaint.opacity(0.6), lineWidth: 1)
        )
    }

    // MARK: Crashes section

    private func crashesSection(_ c: CsaScoresAPI.FmcsaCrashes) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("FMCSA · CRASHES (24 MO)")
                .font(EType.micro).tracking(1.4)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                scoreRow(label: "Total", value: "\(c.total)", warn: false)
                rowDivider()
                scoreRow(label: "Fatalities", value: "\(c.fatalities)", warn: c.fatalities > 0)
                rowDivider()
                scoreRow(label: "Injuries", value: "\(c.injuries)", warn: false)
                rowDivider()
                scoreRow(label: "Tow-aways", value: "\(c.towAways)", warn: false)
                rowDivider()
                scoreRow(label: "Hazmat releases", value: "\(c.hazmatReleases)", warn: c.hazmatReleases > 0)
                if let recent = c.recent, recent > 0 {
                    rowDivider()
                    scoreRow(label: "Recent (last 90 days)", value: "\(recent)", warn: true)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
        }
    }

    // MARK: Inspections section

    private func inspectionsSection(_ i: CsaScoresAPI.FmcsaInspections) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("FMCSA · INSPECTIONS (24 MO)")
                .font(EType.micro).tracking(1.4)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                scoreRow(label: "Total inspections", value: "\(i.total)", warn: false)
                rowDivider()
                scoreRow(label: "Violations found", value: "\(i.violations)", warn: false)
                rowDivider()
                scoreRow(label: "Driver OOS", value: "\(i.driverOos)", warn: i.driverOos > 0)
                rowDivider()
                scoreRow(label: "Vehicle OOS", value: "\(i.vehicleOos)", warn: i.vehicleOos > 0)
                rowDivider()
                scoreRow(label: "Hazmat OOS", value: "\(i.hazmatOos)", warn: i.hazmatOos > 0)
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
        }
    }

    private func scoreRow(label: String, value: String, warn: Bool) -> some View {
        HStack {
            Text(label)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(warn ? AnyShapeStyle(Brand.warning) : AnyShapeStyle(palette.textPrimary))
                .monospacedDigit()
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
    }

    private func rowDivider() -> some View {
        Divider()
            .overlay(palette.borderFaint.opacity(0.6))
            .padding(.leading, Space.s3)
    }

    // MARK: Footer

    private var disclosureFooter: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("How percentiles work")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text("BASIC percentiles compare your carrier to peers in the same safety-event group. Higher = worse. Safety-sensitive BASICs (Unsafe Driving / HOS / Crash) trigger at 65; general BASICs trigger at 80. Think you're mis-rated? File a DataQs challenge from 084 Me · DataQs Filer.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: Helpers

    private func percentString(_ v: Double) -> String {
        // Backend returns rates as 0-1 floats (e.g. 0.21 for 21%).
        // Formatter stops at one decimal so "5.8%" reads cleaner
        // than "5.80%".
        String(format: "%.1f%%", v * 100.0)
    }

    private func shortDate(_ iso: String) -> String? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let out = DateFormatter()
            out.dateFormat = "MMM d, yyyy"
            return out.string(from: d)
        }
        return nil
    }
}

// MARK: - Screen wrapper

struct MeCarrierScorecardScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeCarrierScorecard()
        } nav: {
            BottomNav(
                leading: driverNavLeading_085(),
                trailing: driverNavTrailing_085(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_085() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house.fill",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_085() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person.fill",      isCurrent: true)]
}

// MARK: - Previews

#Preview("085 · Me Carrier Scorecard · Night") {
    MeCarrierScorecardScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("085 · Me Carrier Scorecard · Afternoon") {
    MeCarrierScorecardScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
