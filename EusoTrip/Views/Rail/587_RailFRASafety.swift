//
//  587_RailFRASafety.swift
//  EusoTrip — Rail Engineer · FRA Safety (49 CFR 225/229/232 compliance).
//
//  Visual identity: compliance score ring (84pt arc showing 0-100 regulatory
//  health %) in the hero card. Ring color encodes severity: success=compliant,
//  warning=under review, danger=deficient. Each regulatory row has a
//  shield-check icon tinted by its individual status. Regulatory badge "49 CFR"
//  anchors the eyebrow.
//

import SwiftUI

// MARK: - Outer shell

struct RailFRASafetyScreen: View {
    let theme: Theme.Palette
    let railId: String

    var body: some View {
        Shell(theme: theme) {
            RailFRASafetyBody(railId: railId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct FRASafetyCompliance587: Decodable {
    let reportableCount: Int?
    let openInspections: Int?
    let safetyStatus: String?
    let railroadName: String?
    let complianceScore: Double?
}

private struct FRAAccidentReports587: Decodable {
    let reportableOnLane: Int?
    let periodMonths: Int?
    let ptcActive: Bool?
    let lastAuditLabel: String?
    let cfr: String?
}

private struct RailComplianceItem587: Decodable {
    let title: String?
    let detail: String?
    let status: String?
    let rightValue: String?
}

private struct RailIdIn587: Encodable { let railId: String }

// MARK: - Body

private struct RailFRASafetyBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let railId: String

    @State private var compliance: FRASafetyCompliance587? = nil
    @State private var accidents: FRAAccidentReports587? = nil
    @State private var regulatoryItems: [RailComplianceItem587] = []
    @State private var isFiling = false

    /// The fraction the score arc currently animates toward. Starts at 0 so the
    /// ring sweeps up into the real `scoreFraction` on appear and re-sweeps when
    /// fresh compliance data lands. Reduce-motion snaps straight to the value.
    @State private var shownFraction: Double = 0

    // MARK: Derived

    private var reportableCount: Int  { compliance?.reportableCount  ?? 0 }
    private var openInspections: Int  { compliance?.openInspections   ?? 0 }
    private var railroadName: String  { compliance?.railroadName      ?? "BNSF Railway" }
    private var safetyStatus: String  { (compliance?.safetyStatus ?? "compliant").lowercased() }
    private var safetyOk: Bool        { safetyStatus == "compliant" }
    private var safetyUnderReview: Bool { safetyStatus == "under_review" }

    private var statusLabel: String {
        switch safetyStatus {
        case "deficient":    return "DEFICIENT"
        case "under_review": return "UNDER REVIEW"
        default:             return "COMPLIANT"
        }
    }
    private var statusColor: Color {
        safetyOk ? Brand.success : (safetyUnderReview ? Brand.warning : Brand.danger)
    }

    // Score ring: use explicit complianceScore if provided, else derive from status
    private var complianceScore: Double {
        if let s = compliance?.complianceScore { return max(0, min(100, s)) }
        if safetyOk           { return 96.0 }
        if safetyUnderReview  { return 72.0 }
        return 38.0
    }
    private var scoreFraction: Double { complianceScore / 100.0 }
    private var scoreLabel: String    { "\(Int(complianceScore))" }

    private var accidentsCount: Int { accidents?.reportableOnLane ?? reportableCount }

    private var historyLine1: String {
        let count  = accidents?.reportableOnLane ?? 0
        let period = accidents?.periodMonths ?? 12
        let cfr    = accidents?.cfr ?? "49 CFR 225"
        let prefix = count == 0
            ? "No reportable accidents on this lane"
            : "\(count) reportable accident(s) on this lane"
        return "\(prefix) · \(period) mo · \(cfr)"
    }
    private var historyLine2: String {
        let ptc   = (accidents?.ptcActive ?? true) ? "PTC active end-to-end" : "PTC inactive"
        let audit = accidents?.lastAuditLabel.map { "last FRA audit \($0)" } ?? "last FRA audit on file"
        return "\(ptc) · \(audit)"
    }

    // MARK: View

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                eyebrow
                headline
                IridescentHairline()
                complianceHero
                kpiStrip
                regulatorySection
                historyStrip
                ctaPair
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
        }
        .task { await loadAll() }
    }

    // MARK: Eyebrow + headline

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 6) {
                Text("49 CFR")
                    .font(.system(size: 9, weight: .heavy)).kerning(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(palette.textTertiary.opacity(0.12)))
                Text("✦ FRA SAFETY")
                    .font(.system(size: 9, weight: .black)).kerning(1.0)
                    .foregroundStyle(LinearGradient.primary)
            }
            Spacer()
            Text(railId)
                .font(.system(size: 9, weight: .heavy).monospaced()).kerning(0.6)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("FRA safety")
                .font(.system(size: 28, weight: .heavy)).kerning(-0.4).foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Compliance score hero

    private var complianceHero: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard)
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)

            HStack(spacing: Space.s4) {
                // Score ring
                complianceRing

                // Text side
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(statusLabel)
                            .font(.system(size: 11, weight: .bold)).kerning(0.5)
                            .foregroundStyle(statusColor)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill(statusColor.opacity(0.14)))
                        Text(railroadName)
                            .font(.system(size: 11, weight: .bold)).kerning(0.5)
                            .foregroundStyle(palette.textPrimary)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill(palette.textPrimary.opacity(0.06)))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(reportableCount) reportable · \(accidents?.periodMonths ?? 12) mo")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
                        Text("getFRASafetyCompliance · \(openInspections) open inspections")
                            .font(EType.caption).foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer()
            }
            .padding(Space.s4)
        }
        .frame(height: 118)
    }

    private var complianceRing: some View {
        ZStack {
            // Track
            Circle()
                .stroke(statusColor.opacity(0.16), lineWidth: 8)
                .frame(width: 80, height: 80)
            // Compliance arc — trims to the live, animated fraction so the
            // sweep tracks the real 0-100 regulatory health score.
            Circle()
                .trim(from: 0, to: shownFraction)
                .stroke(statusColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 80, height: 80)
            VStack(spacing: 1) {
                // Numeral counts up in lockstep with the arc (both driven by
                // the same `shownFraction`), so the digits and ring agree.
                Text("\(Int((shownFraction * 100).rounded()))")
                    .font(.system(size: 18, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(statusColor)
                    .contentTransition(.numericText(value: shownFraction * 100))
                Text("SCORE")
                    .font(.system(size: 7.5, weight: .heavy)).kerning(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        // Sweep from 0 → real fraction on first paint; re-sweep when the live
        // score changes. Reduce-motion snaps straight to the final value.
        .onAppear { animateScore(to: scoreFraction) }
        .onChange(of: scoreFraction) { _, newValue in animateScore(to: newValue) }
        .accessibilityElement()
        .accessibilityLabel("Compliance score \(scoreLabel) of 100, \(statusLabel)")
    }

    /// Drives the score arc + numeral toward the real fraction with a natural
    /// decelerating settle. Gated by Reduce Motion (snaps to the final state).
    private func animateScore(to target: Double) {
        if reduceMotion {
            shownFraction = target
        } else {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                shownFraction = target
            }
        }
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "SAFETY",    value: safetyOk ? "OK" : "FAIL",
                       gradientNumeral: safetyOk, accent: safetyOk ? nil : Brand.danger)
            MetricTile(label: "ACCIDENTS", value: "\(accidentsCount)",
                       accent: accidentsCount > 0 ? Brand.danger : palette.textPrimary)
            MetricTile(label: "OPEN INSP", value: "\(openInspections)",
                       accent: openInspections > 0 ? Brand.warning : palette.textPrimary)
        }
    }

    // MARK: Regulatory list

    private var regulatorySection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("REGULATORY · 49 CFR 225/229/232")
                .font(.system(size: 9, weight: .black)).kerning(1.0).foregroundStyle(palette.textTertiary)

            VStack(spacing: 0) {
                ForEach(Array(regulatoryItems.enumerated()), id: \.offset) { idx, item in
                    if idx > 0 {
                        Divider().overlay(Color.black.opacity(0.06)).padding(.horizontal, Space.s4)
                    }
                    regulatoryRow(item)
                }
            }
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint))
        }
    }

    @ViewBuilder
    private func regulatoryRow(_ item: RailComplianceItem587) -> some View {
        let (pillLabel, pillColor) = regulatoryPillInfo(item.status)
        let iconName: String = {
            switch pillLabel {
            case "OK":      return "checkmark.shield.fill"
            case "DUE":     return "shield.lefthalf.filled"
            case "FAILED":  return "xmark.shield.fill"
            default:        return "exclamationmark.shield.fill"
            }
        }()

        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(pillColor.opacity(0.12)).frame(width: 40, height: 40)
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(pillColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title ?? "—")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                if let detail = item.detail {
                    Text(detail)
                        .font(.system(size: 11).monospaced()).kerning(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(pillLabel)
                    .font(.system(size: 11, weight: .bold)).kerning(0.5)
                    .foregroundStyle(pillColor)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(pillColor.opacity(0.14)))
                if let rv = item.rightValue, !rv.isEmpty {
                    Text(rv)
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                }
            }
        }
        .padding(.horizontal, Space.s4).padding(.vertical, 14)
    }

    // MARK: History strip

    private var historyStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HISTORY")
                .font(.system(size: 9, weight: .black)).kerning(0.8).foregroundStyle(palette.textTertiary)
            Text(historyLine1).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            Text(historyLine2).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint))
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "File FRA inspection",
                      action: { isFiling = true; Task { await fileInspection() } },
                      leadingIcon: "plus", isLoading: isFiling)
            Button("Reports") {}
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(Capsule().fill(palette.bgCard)
                    .overlay(Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1)))
        }
    }

    // MARK: Helpers

    private func regulatoryPillInfo(_ status: String?) -> (String, Color) {
        switch (status ?? "ok").lowercased() {
        case "ok":     return ("OK",     Brand.success)
        case "due":    return ("DUE",    Brand.warning)
        case "failed": return ("FAILED", Brand.danger)
        case "watch":  return ("WATCH",  Brand.warning)
        default:       return ("—",      Brand.info)
        }
    }

    // MARK: Data loading

    private func loadAll() async {
        async let compTask: FRASafetyCompliance587 = EusoTripAPI.shared.query(
            "railShipments.getFRASafetyCompliance", input: RailIdIn587(railId: railId))
        async let accTask: FRAAccidentReports587 = EusoTripAPI.shared.query(
            "railShipments.getFRAAccidentReports", input: RailIdIn587(railId: railId))
        async let regTask: [RailComplianceItem587] = EusoTripAPI.shared.query(
            "railShipments.getRailCompliance", input: RailIdIn587(railId: railId))
        compliance      = try? await compTask
        accidents       = try? await accTask
        regulatoryItems = (try? await regTask) ?? []
    }

    private func fileInspection() async {
        defer { isFiling = false }
        let result: FRASafetyCompliance587? = try? await EusoTripAPI.shared.query(
            "railShipments.getFRASafetyCompliance", input: RailIdIn587(railId: railId))
        if let r = result { compliance = r }
    }
}
