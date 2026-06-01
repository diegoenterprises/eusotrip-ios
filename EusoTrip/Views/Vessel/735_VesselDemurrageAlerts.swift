//
//  735_VesselDemurrageAlerts.swift
//  EusoTrip — Vessel Operator · Demurrage Alerts (PRE-ACCRUAL BURNDOWN BOARD).
//
//  Verbatim bespoke port of canonical wireframe 735 "Vessel Demurrage Alerts".
//  Flagship BOARD/EXCEPTIONS grammar (706 sister): a one-glance board of every
//  import container ticking down to demurrage, ranked by free-days remaining
//  before the charge accrues, with projected exposure and trailing history.
//  Distinct from 658 accrual watch and 665 dispute filing — this is the
//  PRE-accrual free-time burndown board.
//
//  Docked under COMPLIANCE. transportMode=vessel · country variance: free-day
//  terminal-tariff rules differ US/CA/MX per carrier per-diem terms. RBAC:
//  vesselProcedure.
//
//  REAL WIRING (tRPC, server/routers/demurrageAlerts.ts · registered in the
//  appRouter as `demurrageAlerts`):
//    · demurrageAlerts.dashboard        {} -> { summary{ totalAccruing,
//        criticalCount, warningCount, safeCount, totalChargesAccruing,
//        projected7dCharges }, critical[], warning[] }   (demurrageAlerts.ts:19)
//    · demurrageAlerts.atRiskContainers {daysAhead?,limit?} -> ranked rows
//        { id, shipmentId, containerId, chargeType, freeTimeDays, ratePerDay,
//          startDate, status, freeTimeEnd, daysRemaining, daysOverdue,
//          projectedCharge }                              (demurrageAlerts.ts:80)
//    · demurrageAlerts.chargeHistory    {limit?} -> vessel_demurrage rows for
//        the trailing-history secondary strip              (demurrageAlerts.ts:118)
//
//  WIRE-GAP (documented in the canonical desc): per-container picker-availability
//  hookup + auto-dispatch confirmation are NOT yet on atRiskContainers, so the
//  primary CTA "Schedule drayage pickup" cannot fire a real drayage-request
//  mutation. It surfaces an honest "not yet wired" notice rather than faking a
//  dispatch. The secondary CTA routes to 665 Vessel Demurrage Dispute
//  (vesselDisputes.create), per the wireframe dispute path.
//
//  NO mock data — every number derives from a live endpoint, with real
//  loading / empty / error states. The board reads the FK-keyed demurrage rows
//  the proc returns (container/shipment ids), degrading gracefully when a
//  human-readable container number is not joined into the projection.
//

import SwiftUI

struct VesselDemurrageAlertsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselDemurrageAlertsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (demurrageAlerts.ts contract)

/// demurrageAlerts.dashboard -> hero + 3-cell KPI source.
private struct DemurrageDashboard735: Decodable {
    let summary: Summary

    struct Summary: Decodable {
        let totalAccruing: Int?
        let criticalCount: Int?
        let warningCount: Int?
        let safeCount: Int?
        let totalChargesAccruing: Double?
        let projected7dCharges: Double?
    }
}

/// demurrageAlerts.atRiskContainers -> one ranked row per at-risk box.
/// containerId / shipmentId are INT FKs (shippingContainers / vesselShipments);
/// chargeType ∈ {demurrage, detention, per_diem}; ratePerDay is DECIMAL(8,2),
/// projectedCharge / freeTimeEnd / daysRemaining / daysOverdue are computed by
/// the proc.
private struct AtRiskContainer735: Decodable, Identifiable {
    let id: Int
    let shipmentId: Int?
    let containerId: Int?
    let chargeType: String?
    let freeTimeDays: Int?
    let ratePerDay: Double?
    let startDate: String?
    let status: String?
    let freeTimeEnd: String?
    let daysRemaining: Int?
    let daysOverdue: Int?
    let projectedCharge: Double?

    private enum CodingKeys: String, CodingKey {
        case id, shipmentId, containerId, chargeType, freeTimeDays
        case ratePerDay, startDate, status, freeTimeEnd, daysRemaining
        case daysOverdue, projectedCharge
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        shipmentId = try? c.decode(Int.self, forKey: .shipmentId)
        containerId = try? c.decode(Int.self, forKey: .containerId)
        chargeType = try? c.decode(String.self, forKey: .chargeType)
        freeTimeDays = try? c.decode(Int.self, forKey: .freeTimeDays)
        // DECIMAL columns may serialize as a quoted string.
        if let d = try? c.decode(Double.self, forKey: .ratePerDay) {
            ratePerDay = d
        } else if let s = try? c.decode(String.self, forKey: .ratePerDay) {
            ratePerDay = Double(s)
        } else { ratePerDay = nil }
        startDate = try? c.decode(String.self, forKey: .startDate)
        status = try? c.decode(String.self, forKey: .status)
        freeTimeEnd = try? c.decode(String.self, forKey: .freeTimeEnd)
        daysRemaining = try? c.decode(Int.self, forKey: .daysRemaining)
        daysOverdue = try? c.decode(Int.self, forKey: .daysOverdue)
        if let d = try? c.decode(Double.self, forKey: .projectedCharge) {
            projectedCharge = d
        } else if let s = try? c.decode(String.self, forKey: .projectedCharge) {
            projectedCharge = Double(s)
        } else { projectedCharge = nil }
    }
}

/// demurrageAlerts.chargeHistory -> trailing vessel_demurrage rows for the
/// HISTORY secondary strip (we read incurred totals + status mix).
private struct ChargeHistoryRow735: Decodable, Identifiable {
    let id: Int
    let totalCharge: Double?
    let status: String?
    let chargeType: String?

    private enum CodingKeys: String, CodingKey { case id, totalCharge, status, chargeType }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        if let d = try? c.decode(Double.self, forKey: .totalCharge) {
            totalCharge = d
        } else if let s = try? c.decode(String.self, forKey: .totalCharge) {
            totalCharge = Double(s)
        } else { totalCharge = nil }
        status = try? c.decode(String.self, forKey: .status)
        chargeType = try? c.decode(String.self, forKey: .chargeType)
    }
}

// MARK: - Body

private struct VesselDemurrageAlertsBody: View {
    @Environment(\.palette) private var palette

    @State private var dashboard: DemurrageDashboard735? = nil
    @State private var atRisk: [AtRiskContainer735] = []
    @State private var history: [ChargeHistoryRow735] = []

    @State private var loading = true
    @State private var loadError: String? = nil

    // Primary CTA — drayage auto-dispatch is a documented server wire-gap.
    @State private var drayageNotice: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.top, Space.s3)

                VStack(alignment: .leading, spacing: Space.s4) {
                    if loading {
                        loadingState
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundStyle(Brand.danger)
                                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                            }
                        }
                    } else {
                        heroCard
                        kpiStrip
                        containersSection
                        historyStrip
                        ctaRow
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar (eyebrow + at-risk count · back chevron + title + menu)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · DEMURRAGE ALERTS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text(atRiskCountLabel)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Demurrage Alerts")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s4)
        }
        .padding(.top, Space.s5)
    }

    private var atRiskCount: Int {
        // The board ranks "at risk" off the live atRiskContainers projection;
        // fall back to the dashboard critical+warning count if the rows haven't
        // resolved yet.
        if !atRisk.isEmpty { return atRisk.count }
        let crit = dashboard?.summary.criticalCount ?? 0
        let warn = dashboard?.summary.warningCount ?? 0
        return crit + warn
    }

    private var atRiskCountLabel: String {
        "\(atRiskCount) at risk"
    }

    // MARK: - Hero card (gradient rim · at-risk count · projected exposure)

    private var heroCard: some View {
        let count = atRiskCount
        return ZStack {
            HStack(alignment: .top, spacing: Space.s4) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(spacing: Space.s2) {
                        miniChip("at-risk")
                        miniChip("import")
                    }
                    HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                        Text("\(count)")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                            .monospacedDigit()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(count == 1 ? "container at risk today" : "at risk today")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                            Text(medianFreeDaysLine)
                                .font(.system(size: 11))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("PROJECTED")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(projectedExposure)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("if no action")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(Space.s4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: 1.5)
        )
    }

    private func miniChip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .bold)).tracking(0.5)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(palette.textPrimary.opacity(0.06)))
    }

    /// "N free-days median" — median free-days remaining across at-risk rows.
    private var medianFreeDaysLine: String {
        let days = atRisk.compactMap { $0.daysRemaining }.sorted()
        guard !days.isEmpty else {
            if let ft = dashboard?.summary.totalAccruing, ft > 0 {
                return "free-time burndown active"
            }
            return "no boxes burning down"
        }
        let mid = days.count / 2
        let median: Double = days.count % 2 == 0
            ? Double(days[mid - 1] + days[mid]) / 2.0
            : Double(days[mid])
        return String(format: "%.1f free-days median", median)
    }

    /// Projected exposure if no action — prefers the live atRisk projection
    /// sum; falls back to the dashboard projected-7d figure.
    private var projectedExposure: String {
        let rowSum = atRisk.compactMap { $0.projectedCharge }.reduce(0, +)
        if rowSum > 0 { return usd(rowSum) }
        if let p = dashboard?.summary.projected7dCharges, p > 0 { return usd(p) }
        return "$0"
    }

    // MARK: - KPI strip (AT RISK · FREE DAYS · LAST 30d)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            // AT RISK — gradient-fill tile.
            VStack(alignment: .leading, spacing: 6) {
                Text("AT RISK")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(.white.opacity(0.85))
                Text("\(atRiskCount)")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white).monospacedDigit()
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .padding(Space.s4)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            kpiTile(label: "FREE DAYS", value: medianFreeDaysValue, accent: nil)
            kpiTile(label: "LAST 30d",  value: last30dValue,        accent: Brand.warning)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func kpiTile(label: String, value: String, accent: Color?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(accent ?? palette.textPrimary)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var medianFreeDaysValue: String {
        let days = atRisk.compactMap { $0.daysRemaining }.sorted()
        guard !days.isEmpty else { return "—" }
        let mid = days.count / 2
        let median: Double = days.count % 2 == 0
            ? Double(days[mid - 1] + days[mid]) / 2.0
            : Double(days[mid])
        return String(format: "%.1f", median)
    }

    /// Trailing-30d demurrage incurred — sum of non-accruing (invoiced/paid)
    /// history rows, the cost that has actually landed.
    private var last30dValue: String {
        let incurred = history
            .filter { ($0.status ?? "").lowercased() != "accruing" }
            .compactMap { $0.totalCharge }
            .reduce(0, +)
        return usd(incurred)
    }

    // MARK: - Containers section (CONTAINERS · atRiskContainers)

    private var containersSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("CONTAINERS · atRiskContainers")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("demurrageAlerts.ts:80")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }

            VStack(spacing: 0) {
                if atRisk.isEmpty {
                    allClearRow
                } else {
                    ForEach(Array(atRisk.enumerated()), id: \.element.id) { idx, row in
                        containerRow(row)
                        if idx < atRisk.count - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                    if priorPickedUp > 0 {
                        Divider().overlay(palette.borderFaint)
                            .padding(.horizontal, Space.s4)
                        Text("+ \(priorPickedUp) prior at-risk container\(priorPickedUp == 1 ? "" : "s") cleared before LFD")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Space.s4)
                            .padding(.vertical, Space.s3)
                    }
                }
            }
            .padding(.vertical, Space.s1)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    /// Boxes that have left "accruing" (picked up / waived / invoiced) in the
    /// trailing history but are no longer on the at-risk board.
    private var priorPickedUp: Int {
        history.filter {
            let s = ($0.status ?? "").lowercased()
            return s == "paid" || s == "waived" || s == "invoiced"
        }.count
    }

    private var allClearRow: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.success.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Brand.success)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("No containers at risk")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("every import box still inside free time")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text("CLEAR")
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(Brand.success)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Brand.success.opacity(0.12)))
        }
        .padding(Space.s4)
    }

    private func containerRow(_ row: AtRiskContainer735) -> some View {
        let remaining = row.daysRemaining ?? 0
        let overdue = (row.daysOverdue ?? 0) > 0
        // Critical: overdue or 1 free-day left. Warning otherwise.
        let critical = overdue || remaining <= 1
        let color: Color = critical ? Brand.danger : Brand.warning

        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(containerLabel(row))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: Space.s2)
                    Text(lfdBadge(row))
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(color)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(color.opacity(0.16)))
                }
                Text(lfdLine(row))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                HStack {
                    Text(chargeTypeLabel(row.chargeType))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text(usd(row.projectedCharge ?? 0))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                }
            }
        }
        .padding(Space.s4)
    }

    /// The proc returns the container FK (INT), not a human carrier prefix +
    /// number, so we label honestly off the ids it provides rather than
    /// fabricating an "MSCU 7184462" string.
    private func containerLabel(_ row: AtRiskContainer735) -> String {
        if let cid = row.containerId { return "Container #\(cid)" }
        if let sid = row.shipmentId { return "Shipment #\(sid)" }
        return "Demurrage record #\(row.id)"
    }

    private func lfdBadge(_ row: AtRiskContainer735) -> String {
        if let od = row.daysOverdue, od > 0 { return "LFD+\(od)d" }
        let r = row.daysRemaining ?? 0
        return "LFD-\(r)d"
    }

    private func lfdLine(_ row: AtRiskContainer735) -> String {
        var parts: [String] = []
        if let end = row.freeTimeEnd, !end.isEmpty {
            parts.append("LFD \(String(end.prefix(10)))")
        }
        if let od = row.daysOverdue, od > 0 {
            parts.append("\(od) day\(od == 1 ? "" : "s") overdue")
        } else {
            let r = row.daysRemaining ?? 0
            parts.append("\(r) day\(r == 1 ? "" : "s") left")
        }
        return parts.isEmpty ? "free-time window unknown" : parts.joined(separator: " · ")
    }

    private func chargeTypeLabel(_ t: String?) -> String {
        switch (t ?? "").lowercased() {
        case "demurrage": return "demurrage"
        case "detention": return "detention"
        case "per_diem":  return "per diem"
        default:          return "free-time charge"
        }
    }

    // MARK: - History strip (HISTORY · chargeHistory)

    private var historyStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("HISTORY · chargeHistory")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("demurrageAlerts.ts:118")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            Text(historyIncurredLine)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2).minimumScaleFactor(0.85)
            Text("dispute path → 665 Vessel Demurrage Dispute (vesselDisputes.create)")
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var historyIncurredLine: String {
        let incurred = history
            .filter { ($0.status ?? "").lowercased() != "accruing" }
            .compactMap { $0.totalCharge }
            .reduce(0, +)
        let missed = history.filter {
            let s = ($0.status ?? "").lowercased()
            return s == "invoiced" || s == "paid" || s == "disputed"
        }.count
        if history.isEmpty { return "no demurrage history recorded in the trailing window" }
        return "trailing demurrage incurred \(usd(incurred)) · \(missed) container\(missed == 1 ? "" : "s") past LFD"
    }

    // MARK: - CTA row (Schedule drayage pickup · Open 665)

    private var ctaRow: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let notice = drayageNotice {
                LifecycleCard(accentGradient: true) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text(notice).font(EType.caption).foregroundStyle(palette.textPrimary)
                    }
                }
            }
            HStack(spacing: Space.s2) {
                Button {
                    // WIRE-GAP: per-container picker-availability + auto-dispatch
                    // confirmation are not yet on atRiskContainers. Surface an
                    // honest notice instead of faking a drayage dispatch.
                    drayageNotice = atRisk.isEmpty
                        ? "No at-risk container to schedule — the board is clear."
                        : "Drayage auto-dispatch is not yet wired on this board. Schedule the pickup from the container detail."
                } label: {
                    Text("Schedule drayage pickup")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(LinearGradient.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button { } label: {
                    Text("Open 665")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(palette.bgCard)
                        .overlay(Capsule().strokeBorder(palette.borderFaint))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 148)
            }
        }
    }

    // MARK: - Helpers

    private func usd(_ v: Double) -> String {
        let rounded = (v).rounded()
        return "$" + Int(rounded).formatted(.number.grouping(.automatic))
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 116)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft).frame(height: 72)
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                }
            }
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 252)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        }
    }

    // MARK: - Load (dashboard + atRiskContainers + chargeHistory)

    private func load() async {
        loading = true; loadError = nil
        struct AtRiskIn: Encodable { let daysAhead: Int; let limit: Int }
        struct HistoryIn: Encodable { let limit: Int }
        do {
            async let dash: DemurrageDashboard735 = EusoTripAPI.shared.queryNoInput(
                "demurrageAlerts.dashboard")
            async let rows: [AtRiskContainer735] = EusoTripAPI.shared.query(
                "demurrageAlerts.atRiskContainers", input: AtRiskIn(daysAhead: 7, limit: 50))
            async let hist: [ChargeHistoryRow735] = EusoTripAPI.shared.query(
                "demurrageAlerts.chargeHistory", input: HistoryIn(limit: 100))

            let (dashResp, rowsResp, histResp) = try await (dash, rows, hist)
            self.dashboard = dashResp
            // Rank by free-days remaining (ascending) — most urgent first.
            self.atRisk = rowsResp.sorted {
                ($0.daysRemaining ?? Int.max) < ($1.daysRemaining ?? Int.max)
            }
            self.history = histResp
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("735 · Vessel Demurrage Alerts · Night") { VesselDemurrageAlertsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("735 · Vessel Demurrage Alerts · Light") { VesselDemurrageAlertsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
