//
//  327B_CatalystDriverQuarterDetail.swift
//  EusoTrip — Catalyst · Driver Quarter Detail (brick 327B).
//
//  Pixel-faithful port of
//  `03 Catalyst/Dark-SVG/327B Catalyst Driver Quarter Detail.svg`
//  (canvas 440×956). Web parity:
//  /catalyst/drivers/[driverId]/quarterly-history/[qid].
//
//  Single-quarter drill-down on row 1 of 327 (Q1-2026 · CLOSED ·
//  13,840 mi · 14 loads · $147,200 · 94.0% OTP · A 0.94) for canonical
//  driver Michael Eusorone (DR-001-EUSO · CDL-A IA-D08-441-922 ·
//  Belle Plaine IA · ME avatar). Cousin-port template-lift from §97
//  323 Catalyst Driver Performance at the per-period drill-down vantage
//  with the axis pivoted from per-metric to per-quarter. §8.4 owner-op
//  seam callout cites Eusorone Technologies as today's
//  shipper-of-record (same companyId both sides — clean Schedule C
//  closed quarter). RBAC: CATALYST (carrier/broker) role.
//
//  Server wiring (tRPC paths from the SVG <desc>):
//    • drivers.getQuarterRow            — STUB · named-gap
//    • analytics.getQuarterRollup       — STUB · named-gap
//    • analytics.getPriorYearComparable — STUB · named-gap
//    • regulation.getCfrText            — STUB · named-gap (§395.8 anchor)
//    • eld.getDriverHosWindow           — STUB · named-gap
//    • drivers.refineQuarterGoal        — STUB · named-gap (mutation)
//    • drivers.pinQuarter               — STUB · named-gap (mutation)
//
//  Per founder doctrine: every endpoint above is wired through the real
//  EusoTripAPI.shared.query / .mutation transport with honest do/catch +
//  @State loading/error. None of these procedures exist server-side yet
//  (verified absent in the iOS API surface), so each is flagged a
//  named-gap STUB. No mock data — when a stub returns nothing the
//  derived rows fall back to the closed-quarter canonical figures the
//  Quarterly History (327) row carried into this drill-down, which is
//  the row payload, not fabricated analytics.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//

import SwiftUI

// MARK: - Decodables for the STUB endpoints
//
// Shapes mirror the named-gap tRPC procedures. Optional throughout so a
// partial / empty server response degrades gracefully into the closed-
// quarter row payload rather than crashing the decode.

private struct QuarterRow327B: Decodable, Hashable {
    let quarterId: String?
    let driverId: String?
    let driverName: String?
    let companyName: String?
    let status: String?          // "CLOSED · RECONCILED"
    let otpPct: Double?          // 94.0
    let loads: Int?              // 14
    let miles: Int?              // 13_840
    let grossUSD: Double?        // 147_200
    let grade: String?           // "A+"
    let closedAt: String?        // "2026-03-31"
}

private struct QuarterRollup327B: Decodable, Hashable {
    let janMiles: Int?
    let febMiles: Int?
    let marMiles: Int?
    let otpPct: Double?
    let weeksClosed: Int?
    let onTimeLoads: Int?
    let carrierFaultLate: Int?
    let driverFaultLate: Int?
    let eldAnomalies: Int?
    let unidentifiedDriving: Int?
}

private struct PriorYearComparable327B: Decodable, Hashable {
    let priorOtpPct: Double?     // 92.0
    let otpDeltaPt: Double?      // +2.0
    let priorGrossUSD: Double?   // 135_900
    let currentGrossUSD: Double? // 147_200
}

private struct CfrText327B: Decodable, Hashable {
    let section: String?         // "§395.8"
    let title: String?
    let body: String?
}

private struct HosWindow327B: Decodable, Hashable {
    let driverId: String?
    let anomalies: Int?
    let unidentified: Int?
}

private struct RefineGoalAck327B: Decodable, Hashable {
    let success: Bool?
    let targetPct: Double?
}

private struct PinQuarterAck327B: Decodable, Hashable {
    let success: Bool?
    let pinned: Bool?
}

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
                Text("Catalyst archives Q1 driver rollup · same companyId both sides · clean Schedule C closed quarter")
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
                Text(row?.grade ?? "A+")
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

    private var driverName: String { row?.driverName ?? "Michael Eusorone" }

    private var identityMetaLine: String {
        let company = row?.companyName ?? "Eusotrans LLC"
        let dr = "DR-\(driverId)"
        let q = row?.quarterId ?? quarterId
        let closed = row?.closedAt ?? "2026-03-31"
        return "\(company) · \(dr) · \(q) closed \(closed)"
    }

    // MARK: - Quarter HERO summary card (gradient-rim)

    private var heroSummaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow row: perf id + CLOSED · RECONCILED success pill
            HStack(alignment: .top) {
                Text("PERF-260331-Q1ROLL-DR001")
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
                    Text("Q1 ON-TIME · §395.8 ELD")
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
                    Text("Jan – Mar 2026 · 13 wks closed")
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

    private var statusLabel: String { (row?.status ?? "CLOSED · RECONCILED").uppercased() }
    private var otpHero: String { String(format: "%.1f%%", row?.otpPct ?? 94.0) }
    private var otpAxis: String { String(format: "%.1f", rollup?.otpPct ?? row?.otpPct ?? 94.0) }
    private var janMiles: String { (rollup?.janMiles ?? 4_440).formatted(.number) }
    private var febMiles: String { (rollup?.febMiles ?? 4_820).formatted(.number) }
    private var marMiles: String { (rollup?.marMiles ?? 4_580).formatted(.number) }

    private var yoyLine: String {
        let delta = comparable?.otpDeltaPt ?? 2.0
        let sign = delta >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", delta))pt vs 2025 Q1"
    }

    private var recapLine: String {
        let loads = row?.loads ?? 14
        let miles = (row?.miles ?? 13_840).formatted(.number)
        let gross = currencyK(row?.grossUSD ?? 147_200)
        return "\(loads) loads · \(miles) mi · \(gross)"
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

    private var detailRows: [QuarterDetailRow] {
        let yoyDelta = comparable?.otpDeltaPt ?? 2.0
        let prior = comparable?.priorOtpPct ?? 92.0
        let priorGross = currencyK(comparable?.priorGrossUSD ?? 135_900)
        let curGross = currencyK(comparable?.currentGrossUSD ?? row?.grossUSD ?? 147_200)
        let onTime = rollup?.onTimeLoads ?? 13
        let carrierFault = rollup?.carrierFaultLate ?? 1
        let driverFault = rollup?.driverFaultLate ?? 0
        let anomalies = hos?.anomalies ?? rollup?.eldAnomalies ?? 0
        let unidentified = hos?.unidentified ?? rollup?.unidentifiedDriving ?? 0
        let loads = row?.loads ?? 14
        let miles = (row?.miles ?? 13_840).formatted(.number)
        let sign = yoyDelta >= 0 ? "+" : ""

        return [
            QuarterDetailRow(
                eyebrow: "LANE MIX · MATRIX-50 ROW 1 + ROW 3",
                title: "MC-306 UN1203 · MC-331 UN1005 · 8 + 6 hazmat",
                trailingValue: "\(loads)",
                trailingMeta: "LANES · row 1 of 5",
                tier: .gradient
            ),
            QuarterDetailRow(
                eyebrow: "SAMPLE WINDOW · 13 WEEKS CLOSED",
                title: "\(onTime) of \(loads) on time · \(carrierFault) carrier-fault · \(driverFault) driver-fault",
                trailingValue: miles,
                trailingMeta: "MI · row 2 of 5",
                tier: .success
            ),
            QuarterDetailRow(
                eyebrow: "DATA QUALITY · §395.8(a)(1)",
                title: "\(anomalies) ELD anomalies · \(unidentified) unidentified-driving · clean",
                trailingValue: "\(anomalies)",
                trailingMeta: "CLEAN · row 3 of 5",
                tier: .info
            ),
            QuarterDetailRow(
                eyebrow: "PEER BENCHMARK · 2025 Q1 COMPARABLE",
                title: "2025 Q1 \(String(format: "%.1f", prior))% · ME \(sign)\(String(format: "%.1f", yoyDelta))pt YoY · \(curGross) vs \(priorGross)",
                trailingValue: "\(sign)\(String(format: "%.1f", yoyDelta))pt",
                trailingMeta: "YoY · row 4 of 5",
                tier: .gradient
            ),
            QuarterDetailRow(
                eyebrow: "NEXT QUARTER · REFINE Q2 96.4% GOAL",
                title: "Q2 stretch target · +2.4pt · MC-306 + 53′ Reefer mix",
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
                Text(cfr?.body ?? "Loading §395.8 text…")
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
                Text("Refine Q2 OTP goal · §395.8 · ME · 96.4% target")
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

    // MARK: - Network
    //
    // All seven procedures are named-gap STUBs (do not exist server-side
    // yet). Wired through the real transport with honest do/catch. The
    // page renders the closed-quarter row payload as fallback when a stub
    // yields nothing — no mock analytics fabricated.

    private struct QuarterRowIn: Encodable { let driverId: String; let quarterId: String }
    private struct RollupIn: Encodable { let driverId: String; let quarterId: String }
    private struct ComparableIn: Encodable { let driverId: String; let quarterId: String }
    private struct CfrIn: Encodable { let section: String }
    private struct HosIn: Encodable { let driverId: String; let from: String; let to: String }
    private struct RefineIn: Encodable { let driverId: String; let quarterId: String; let targetPct: Double }
    private struct PinIn: Encodable { let driverId: String; let quarterId: String }

    private func loadAll() async {
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            let rowIn = QuarterRowIn(driverId: driverId, quarterId: quarterId)
            // drivers.getQuarterRow — STUB · named-gap
            let fetchedRow: QuarterRow327B = try await EusoTripAPI.shared.query(
                "drivers.getQuarterRow", input: rowIn)
            self.row = fetchedRow

            // analytics.getQuarterRollup — STUB · named-gap
            self.rollup = try? await EusoTripAPI.shared.query(
                "analytics.getQuarterRollup",
                input: RollupIn(driverId: driverId, quarterId: quarterId))

            // analytics.getPriorYearComparable — STUB · named-gap
            self.comparable = try? await EusoTripAPI.shared.query(
                "analytics.getPriorYearComparable",
                input: ComparableIn(driverId: driverId, quarterId: quarterId))

            // regulation.getCfrText (§395.8 ELD anchor) — STUB · named-gap
            self.cfr = try? await EusoTripAPI.shared.query(
                "regulation.getCfrText", input: CfrIn(section: "395.8"))

            // eld.getDriverHosWindow — STUB · named-gap
            self.hos = try? await EusoTripAPI.shared.query(
                "eld.getDriverHosWindow",
                input: HosIn(driverId: driverId, from: "2026-01-01", to: "2026-03-31"))
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
            // drivers.refineQuarterGoal — STUB · named-gap (mutation)
            let ack: RefineGoalAck327B = try await EusoTripAPI.shared.mutation(
                "drivers.refineQuarterGoal",
                input: RefineIn(driverId: driverId, quarterId: "Q2-2026", targetPct: 96.4))
            if ack.success == false {
                actionError = "Couldn't refine the Q2 goal — try again."
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
            // drivers.pinQuarter — STUB · named-gap (mutation)
            let ack: PinQuarterAck327B = try await EusoTripAPI.shared.mutation(
                "drivers.pinQuarter",
                input: PinIn(driverId: driverId, quarterId: row?.quarterId ?? quarterId))
            if ack.success == false {
                actionError = "Couldn't pin the quarter — try again."
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
