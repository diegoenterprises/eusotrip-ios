//
//  330B_CatalystVehicleScorecardAxisDetail.swift
//  EusoTrip — Catalyst · Vehicle Scorecard Axis Detail (brick 330B).
//
//  Pixel-faithful port of
//  `03 Catalyst/Dark-SVG/330B Catalyst Vehicle Scorecard Axis Detail.svg`
//  (canvas 440×956). Web parity:
//  /catalyst/fleet/vehicle/[vehicleId]/scorecard/[axisId].
//
//  Single-axis drill-down on the §9.4 vehicle-composite formula for the
//  selected asset. The composite, grade, lane-avg delta, and per-axis
//  contributions are DERIVED server-side at read time from real delivered-
//  load throughput on this vehicle over a 90-day all-lanes window — there is
//  no stored scorecard table. RBAC: CATALYST (carrier/broker) role,
//  companyId-scoped (the proc returns null for vehicles the caller's company
//  does not own).
//
//  Server wiring (real, role-accessible — verified 2026-06-06):
//    • vehicles.getScorecardAxis        — vehicles.ts:532 (companyId-scoped)
//    • analytics.getCompositeBreakdown  — analytics.ts:1751
//    • analytics.getPeerCompositeBenchmark — analytics.ts:1827
//    • vehicles.getFormulaSpec          — vehicles.ts:618 (§9.4 spec prose;
//      NOTE: the verbatim spec lives on the `vehicles.*` router, NOT
//      `scoring.*` — there is no scoring router server-side)
//    • vehicles.refineCompositeGoal     — vehicles.ts:655 (MUTATION)
//    • vehicles.pinScorecardAxis        — vehicles.ts:694 (MUTATION)
//
//  HONESTY: every figure on this screen is hydrated from the real procs in a
//  `.task`. There are NO seeded composite/grade/delta numbers. When the axis
//  proc returns null (vehicle not owned / no data) the screen renders an
//  EusoEmptyState. MPG telemetry is an explicit server-side gap (no per-asset
//  fuel-burn column) — the breakdown proc returns `null` for mpg/mpgValue/
//  mpgTarget, and the screen renders "—" for those, never a fabricated mpg.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//

import SwiftUI

// MARK: - Screen wrapper

struct CatalystVehicleScorecardAxisDetailScreen: View {
    let theme: Theme.Palette
    let vehicleId: String
    let axisId: String

    /// `vehicleId` / `axisId` are routing arguments — the screen resolves all
    /// figures from the server by these IDs (or shows the empty state). The
    /// defaults exist only so the screen catalog can present it without a
    /// concrete vehicle context; they are not fabricated display data.
    init(theme: Theme.Palette = Theme.dark,
         vehicleId: String = "1",
         axisId: String = "COMPOSITE-1") {
        self.theme = theme
        self.vehicleId = vehicleId
        self.axisId = axisId
    }

    var body: some View {
        Shell(theme: theme) {
            CatalystVehicleScorecardAxisDetailBody(vehicleId: vehicleId, axisId: axisId)
        } nav: {
            BottomNav(
                leading: catalystNavLeading_330B(),
                trailing: catalystNavTrailing_330B(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_330B() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: true)]
}

private func catalystNavTrailing_330B() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)]
}

// MARK: - Detail row tier (the §92 RegulatoryRow geometry · TENTH port)

private enum AxisRowTier {
    case gradient
    case success
    case info
}

private struct AxisDetailRow: Identifiable {
    let id = UUID()
    let eyebrow: String
    let title: String
    let trailingValue: String
    let trailingMeta: String
    let tier: AxisRowTier
    var actionRibbon: Bool = false    // row 5 carries the gradient action rim
}

// MARK: - Body

private struct CatalystVehicleScorecardAxisDetailBody: View {
    let vehicleId: String
    let axisId: String

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    @State private var actionError: String? = nil
    @State private var actionInFlight: Bool = false
    @State private var formulaExpanded: Bool = false

    @State private var axis: VehiclesAPI.ScorecardAxis? = nil
    @State private var breakdown: AnalyticsAPI.CompositeBreakdown? = nil
    @State private var benchmark: AnalyticsAPI.PeerCompositeBenchmark? = nil
    @State private var formula: VehiclesAPI.FormulaSpec? = nil

    /// Em-dash placeholder for honestly-absent values. No fabrication.
    private let dash = "—"

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
                } else if axis == nil {
                    emptyState
                } else {
                    identityStrip
                    heroSummaryCard
                    lifecycleStrip
                    sectionEyebrow
                    ForEach(detailRows) { detailRowView($0) }
                    formulaChip
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

    // MARK: - TopBar (eyebrow + entity-ID kicker) + back-to-Scorecard pill

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · VEHICLE · SCORECARD AXIS")
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
        guard let code = axis?.assetCode else { return "§9.4 · LIVE" }
        return "\(code) · §9.4 · LIVE"
    }

    private var titleRow: some View {
        HStack(alignment: .center) {
            Text("Axis detail")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("Scorecard")
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

    // MARK: - §8.4 owner-op seam callout banner · TWENTY-SIXTH cross-track port

    private var ownerOpSeamBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            VStack(alignment: .leading, spacing: 2) {
                Text("OWNER-OP SEAM · §9.4 VEHICLE BOOKS CLEAN")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Catalyst rates asset · same companyId both sides · clean §9.4 vehicle books")
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

    // MARK: - Empty state (axis proc returned null — not owned / no data)

    private var emptyState: some View {
        EusoEmptyState(
            systemImage: "chart.bar.doc.horizontal",
            title: "No composite for this asset yet",
            subtitle: "This vehicle has no §9.4 composite in the 90-day all-lanes window, or it isn't in your fleet.",
            comingSoon: false
        )
        .padding(.top, 24)
    }

    // MARK: - Vehicle identity strip (compact · ELEVENTH consecutive port)

    private var identityStrip: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal)
                Text(avatarInitials)
                    .font(.system(size: 13, weight: .bold))
                    .tracking(0.3)
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(vehicleName)
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
                Text(gradeHero)
                    .font(.system(size: 11, weight: .heavy))
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

    private var vehicleName: String { axis?.vehicleName ?? dash }

    /// Two-letter avatar from the vehicle make (no canonical "PB" seed).
    private var avatarInitials: String {
        let name = axis?.vehicleName ?? ""
        let letters = name.filter { $0.isLetter }
        guard !letters.isEmpty else { return "—" }
        return String(letters.prefix(2)).uppercased()
    }

    private var identityMetaLine: String {
        let parts = [axis?.companyName, axis?.assetCode,
                     axis?.titledAt.map { "titled \($0)" }]
            .compactMap { $0 }
        return parts.isEmpty ? dash : parts.joined(separator: " · ")
    }

    // MARK: - Composite HERO summary card (gradient-rim)

    private var heroSummaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow row: composite id + status pill
            HStack(alignment: .top) {
                Text(scoreIdLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
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

            // Hero grade + composite recap row
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(gradeHero)
                        .font(.system(size: 30, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(compositeKicker)
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(laneDeltaLine)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("90-day all-lanes window")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                    Text("§8.4 owner-op fleet")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 18)

            Divider().overlay(palette.borderFaint).padding(.top, 14)

            // 4-axis COMPONENT BREAKDOWN strip (bottom edge) — SIX-PORT HeroAxisStrip
            HStack(alignment: .bottom, spacing: 0) {
                componentCell(value: utilStr,   label: "UTIL")
                componentCell(value: mpgStr,    label: "MPG")
                componentCell(value: volumeStr, label: "VOLUME")
                componentCell(value: totalStr,  label: "TOTAL")
                Spacer(minLength: 0)
                // FORMULA chip — right cap
                HStack(spacing: 6) {
                    Image(systemName: "function")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("FORMULA")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(scheme == .dark ? Color(hex: 0x0B0B0F) : palette.bgCardSoft)
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

    private func componentCell(value: String, label: String) -> some View {
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

    private var scoreIdLabel: String { axis?.scoreId ?? dash }
    private var statusLabel: String { (axis?.status ?? dash).uppercased() }
    private var gradeHero: String { axis?.grade ?? dash }

    private var compositeKicker: String {
        guard let c = axis?.composite ?? breakdown?.total else {
            return "COMPOSITE \(dash) · §9.4 EUSOTRIP"
        }
        return "COMPOSITE \(String(format: "%.2f", c)) · §9.4 EUSOTRIP"
    }

    private var laneDeltaLine: String {
        guard let delta = benchmark?.laneAvgDelta ?? axis?.laneAvgDelta else {
            return "\(dash) vs lane avg"
        }
        let sign = delta >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", delta)) vs lane avg"
    }

    // Per-axis contributions — only rendered from the real breakdown proc.
    // mpg is an honest server gap (always null), so it shows "—".
    private var utilStr: String   { breakdown.map { String(format: "%.3f", $0.util) } ?? dash }
    private var mpgStr: String    { breakdown?.mpg.map { String(format: "%.3f", $0) } ?? dash }
    private var volumeStr: String { breakdown.map { String(format: "%.3f", $0.volume) } ?? dash }
    private var totalStr: String {
        if let t = breakdown?.total { return String(format: "%.2f", t) }
        if let c = axis?.composite { return String(format: "%.2f", c) }
        return dash
    }

    // MARK: - 5-stage scoring pipeline lifecycle strip
    // SAMPLED · WEIGHTED · NORMALIZED · COMPOSITED · GRADED.
    // Stages 0–3 success-tinted (composite ran end-to-end),
    // stage 4 GRADED active (gradient) — INVERTED active-stage.

    private var lifecycleStages: [(String, Bool)] {
        [("SAMPLED", false), ("WEIGHTED", false), ("NORMALIZED", false),
         ("COMPOSITED", false), ("GRADED", true)]
    }

    private var lifecycleStrip: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .center) {
                Rectangle()
                    .fill(Brand.success.opacity(0.50))
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

    // MARK: - AXIS DETAIL section eyebrow

    private var sectionEyebrow: some View {
        Text("AXIS DETAIL · 5 OF 5 · TAP TO PIN OR ANNOTATE")
            .font(.system(size: 9, weight: .heavy))
            .tracking(1.0)
            .foregroundStyle(LinearGradient.diagonal)
    }

    // MARK: - 5 axis-detail rows (§92 RegulatoryRow geometry · TENTH port)
    //
    // Every numeric in these rows is sourced from the real breakdown proc.
    // The MPG row honestly reads "—" because the server has no per-asset
    // fuel-burn column (mpg/mpgValue/mpgTarget are null). The volume-row
    // load count comes from the proc's `loads`.

    private var detailRows: [AxisDetailRow] {
        let util = utilStr
        let mpg = mpgStr
        let volume = volumeStr
        let utilPctStr = breakdown.map { String(format: "%.1f", $0.utilPct) } ?? dash
        let loadsStr = breakdown.map { String($0.loads) } ?? dash

        // MPG sub-row title: only show the ratio math when mpgValue + target
        // are present (they are not, server-side, today) — otherwise honest "—".
        let mpgTitle: String = {
            if let v = breakdown?.mpgValue, let t = breakdown?.mpgTarget, t > 0 {
                let ratio = v / t
                return "\(String(format: "%.1f", v)) mpg · \(String(format: "%.1f", v))/\(String(format: "%.1f", t)) = \(String(format: "%.2f", ratio)) × 0.3 = \(mpg)"
            }
            return "MPG not telemetered per-asset · sub-score omitted from composite"
        }()

        return [
            AxisDetailRow(
                eyebrow: "VERBATIM SPEC · EUSOTRIP §9.4",
                title: "Vehicle composite formula · 0.4/0.3/0.3 weights",
                trailingValue: "read",
                trailingMeta: "SPEC · row 1 of 5",
                tier: .gradient
            ),
            AxisDetailRow(
                eyebrow: "UTILIZATION COMPONENT · WEIGHT 0.4",
                title: "\(utilPctStr)% utilization · contribution \(util) · largest driver",
                trailingValue: util,
                trailingMeta: "CONTRIB · row 2 of 5",
                tier: .success
            ),
            AxisDetailRow(
                eyebrow: "MPG COMPONENT · WEIGHT 0.3",
                title: mpgTitle,
                trailingValue: mpg,
                trailingMeta: "CONTRIB · row 3 of 5",
                tier: .info
            ),
            AxisDetailRow(
                eyebrow: "VOLUME COMPONENT · LOG-NORMALIZED",
                title: "\(loadsStr) delivered loads · contribution \(volume)",
                trailingValue: volume,
                trailingMeta: "CONTRIB · row 4 of 5",
                tier: .gradient
            ),
            AxisDetailRow(
                eyebrow: "NEXT ACTION · REFINE 0.95 STRETCH",
                title: "Set a 0.95 composite stretch target for this asset",
                trailingValue: "act",
                trailingMeta: "refine now · row 5 of 5",
                tier: .gradient,
                actionRibbon: true
            ),
        ]
    }

    private func detailRowView(_ r: AxisDetailRow) -> some View {
        Button {
            if r.actionRibbon {
                Task { await refineStretchGoal() }
            } else {
                Task { await pinScorecardAxis() }
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

    private func rimGradient(for tier: AxisRowTier) -> LinearGradient {
        switch tier {
        case .gradient: return LinearGradient.diagonal
        case .success:  return LinearGradient(colors: [Brand.success, Color(hex: 0x00A07B)],
                                              startPoint: .top, endPoint: .bottom)
        case .info:     return LinearGradient(colors: [Brand.blue, Brand.blue],
                                              startPoint: .top, endPoint: .bottom)
        }
    }

    private func tierEyebrowStyle(_ tier: AxisRowTier) -> AnyShapeStyle {
        switch tier {
        case .gradient: return AnyShapeStyle(LinearGradient.diagonal)
        case .success:  return AnyShapeStyle(Brand.success)
        case .info:     return AnyShapeStyle(Brand.blue)
        }
    }

    private func trailingValueStyle(_ tier: AxisRowTier) -> AnyShapeStyle {
        switch tier {
        case .gradient: return AnyShapeStyle(LinearGradient.diagonal)
        case .success:  return AnyShapeStyle(Brand.success)
        case .info:     return AnyShapeStyle(palette.textPrimary)
        }
    }

    // MARK: - Verbatim §9.4 formula spec chip (expand · NEW SCORING THREAD)

    private var formulaChip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { formulaExpanded.toggle() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Read EusoTrip §9.4 verbatim · vehicle-composite scoring spec")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Image(systemName: formulaExpanded ? "chevron.up" : "chevron.down")
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

            if formulaExpanded {
                Text(formulaBody)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
            }
        }
    }

    private var formulaBody: String {
        formula?.body ?? "The §9.4 vehicle-composite scoring spec is unavailable right now."
    }

    // MARK: - Action ribbon (single-row refinement port #16 · Refine·stretch)

    private var actionRibbon: some View {
        Button {
            Task { await refineStretchGoal() }
        } label: {
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                Image(systemName: "target")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                Text(refineLabel)
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

    private var refineLabel: String {
        guard let code = axis?.assetCode else { return "Refine 0.95 stretch · §9.4" }
        return "Refine 0.95 stretch · §9.4 · \(code)"
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

    // MARK: - Network
    //
    // All procedures are REAL and role-accessible (companyId-scoped). The
    // axis proc returns null for vehicles outside the caller's fleet → the
    // screen shows the empty state. The breakdown / benchmark / formula
    // procs degrade independently (try?) so a transient miss on any one
    // doesn't blank the page; the affected cells render "—".

    private func loadAll() async {
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            // vehicles.getScorecardAxis — companyId-scoped headline.
            self.axis = try await EusoTripAPI.shared.vehicles.getScorecardAxis(
                vehicleId: vehicleId, axisId: axisId)

            // analytics.getCompositeBreakdown — per-axis contributions.
            self.breakdown = try? await EusoTripAPI.shared.analytics.getCompositeBreakdown(
                vehicleId: vehicleId, axisId: axisId)

            // analytics.getPeerCompositeBenchmark — real peer RPM delta.
            self.benchmark = try? await EusoTripAPI.shared.analytics.getPeerCompositeBenchmark(
                vehicleId: vehicleId, windowDays: 90)

            // vehicles.getFormulaSpec (§9.4 anchor) — verbatim spec prose.
            self.formula = try? await EusoTripAPI.shared.vehicles.getFormulaSpec(section: "9.4")
        } catch {
            self.loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func refineStretchGoal() async {
        guard !actionInFlight else { return }
        actionInFlight = true
        actionError = nil
        defer { actionInFlight = false }
        do {
            // vehicles.refineCompositeGoal — MUTATION.
            let ack = try await EusoTripAPI.shared.vehicles.refineCompositeGoal(
                vehicleId: vehicleId, axisId: axisId, stretchTarget: 0.95)
            if !ack.success {
                actionError = "Couldn't refine the 0.95 stretch goal - try again."
            }
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func pinScorecardAxis() async {
        guard !actionInFlight else { return }
        actionInFlight = true
        actionError = nil
        defer { actionInFlight = false }
        do {
            // vehicles.pinScorecardAxis — MUTATION.
            let ack = try await EusoTripAPI.shared.vehicles.pinScorecardAxis(
                vehicleId: vehicleId, axisId: axis?.axisId ?? axisId)
            if !ack.success {
                actionError = "Couldn't pin the axis - try again."
            }
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Previews

#Preview("330B · Catalyst · Vehicle Scorecard Axis Detail · Night") {
    CatalystVehicleScorecardAxisDetailScreen(theme: Theme.dark, vehicleId: "1", axisId: "COMPOSITE-1")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("330B · Catalyst · Vehicle Scorecard Axis Detail · Afternoon") {
    CatalystVehicleScorecardAxisDetailScreen(theme: Theme.light, vehicleId: "1", axisId: "COMPOSITE-1")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
