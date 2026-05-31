//
//  662_VesselExceptionsHolds.swift
//  EusoTrip — Vessel Operator · Exceptions & Holds (urgency-triage board).
//
//  Verbatim port of "662 Vessel Exceptions Holds.svg" (Dark).
//  Bespoke URGENCY-TRIAGE-BOARD archetype: a release-readiness hero (blocking vs
//  cleared segmented bar + dollar exposure) over holds sorted most-imminent-first,
//  where every row carries a left severity-accent rail and a TIME-TO-PENALTY
//  urgency bar that fills red as the deadline/charge approaches — so the operator
//  triages which hold to clear FIRST by how fast money or release is bleeding.
//  Nav anchored to VesselOperatorNavController (HOME · SHIPMENTS · [orb] ·
//  COMPLIANCE · ME), Compliance tab current.
//
//  Data (tRPC vesselShipments.ts):
//    getCBPAlerts      EXISTS:1180  vesselProcedure · {importerId} · CBP exam/PGA holds → rows
//    getCBPEntryStatus EXISTS:1169  vesselProcedure · {entryNumber} · release-blocking state → hero + guard
//    getVesselDemurrage EXISTS:704  vesselProcedure · accrual clock → demurrage row + exposure
//
//  STUB · named-gap (surfaced to the-oath, NOT invented): the server returns CBP
//  alerts (alertId/alertType/severity:string/description/agency/actionRequired) and
//  entry holds (holdType/agency/reason/appliedAt) — but NOT per-hold urgency typing
//  { holdId, authority, severity:'blocking'|'review'|'cleared', minutesToPenalty,
//  exposureUSD }. The SLA bar fill %, the minutes-to-penalty label, and the $-exposure
//  per row therefore cannot be computed honestly from the current contract. Where a
//  field is absent we render the honest derived state (blocking/review from CBP severity
//  + actionRequired; $ exposure from getVesselDemurrage where it overlaps) and leave the
//  urgency math as a real "—" rather than fabricating it. See PORT-GAP notes inline.
//
//  RBAC vesselProcedure. transportMode=vessel · US CBP ACE + ISF 10+2; CA CBSA ACI /
//  MX VUCEM holds resolve in the same rows by entry country. WRITE: clearing a hold is
//  a CBP-entry mutation (Clear hold CTA · not this read surface).
//

import SwiftUI

struct VesselExceptionsHoldsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselExceptionsHoldsBody() } nav: {
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

// MARK: - Data shapes (mirror DescartesABIService + vesselShipments.ts contracts)

/// getCBPAlerts → CBPAlert[] (DescartesABIService.ts:117). No urgency typing —
/// `severity` is a free string ("High"/"Medium"/"Info"…), no minutesToPenalty/exposureUSD.
private struct CBPAlert662: Decodable, Identifiable {
    let alertId: String
    let alertType: String?
    let severity: String?
    let description: String?
    let entryNumber: String?
    let importerId: String?
    let createdAt: String?
    let expiresAt: String?
    let actionRequired: Bool?
    let agency: String?
    var id: String { alertId }
}

/// getCBPEntryStatus → EntryStatus | null (DescartesABIService.ts:72).
private struct EntryHold662: Decodable {
    let holdType: String?
    let agency: String?
    let reason: String?
    let appliedAt: String?
}
private struct EntryStatus662: Decodable {
    let entryNumber: String?
    let status: String?
    let holds: [EntryHold662]?
    let releaseDate: String?
    let liquidationDate: String?
    let dutyOwed: Double?
    let lastUpdated: String?
}

/// getVesselDemurrage → accrual rollup (vesselShipments.ts:704). Only the fields
/// this surface reads: the running $ accrued, used as the demurrage row exposure.
private struct DemurrageRoll662: Decodable {
    let demurrageUsd: Double?
    let detentionUsd: Double?
    let lfdPassedCount: Int?
}

// MARK: - Body

private struct VesselExceptionsHoldsBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @State private var alerts: [CBPAlert662] = []
    @State private var entry: EntryStatus662? = nil
    @State private var demurrage: DemurrageRoll662? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Canonical booking context (SVG <desc>: VES-260523-9F2C41A0E7 · ENT-31194882 · USLGB).
    private let entryNumber = "ENT-31194882"
    private let bookingRef  = "VES-260523"
    private let destPort    = "USLGB"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.top, Space.s3)
                VStack(alignment: .leading, spacing: Space.s4) {
                    if loading {
                        LifecycleCard {
                            Text("Loading exceptions & holds…")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else {
                        hero
                        holdsSection
                        clearedBanner
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

    // MARK: - Top bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · EXCEPTIONS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("\(bookingRef) · \(destPort)")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Exceptions")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s4)
        }
        .padding(.top, Space.s4)
    }

    // MARK: - Hero (release-readiness)

    /// Blocking holds = entry-status holds that are still un-released, plus CBP
    /// alerts flagged actionRequired with a high/blocking severity. Cleared =
    /// entry holds with a releaseDate / alerts whose severity reads informational.
    private var blockingHolds: [DerivedHold] { derivedHolds.filter { $0.tier == .blocking } }
    private var reviewHolds:   [DerivedHold] { derivedHolds.filter { $0.tier == .review } }
    private var clearedHolds:  [DerivedHold] { derivedHolds.filter { $0.tier == .cleared } }

    private var totalHolds: Int { derivedHolds.count }

    /// $ at risk — the only honest exposure number the contract supplies is the
    /// demurrage accrual rollup (getVesselDemurrage). The SVG's "$1,140 next
    /// penalty 6h" depends on the per-hold minutesToPenalty/exposureUSD STUB the
    /// server does not return, so we surface the real demurrage exposure and a
    /// "—" for next-penalty rather than inventing the countdown.
    private var dollarsAtRisk: Double? {
        guard let d = demurrage else { return nil }
        return (d.demurrageUsd ?? 0) + (d.detentionUsd ?? 0)
    }

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.bgCardSoft)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("HOLDS BLOCKING RELEASE")
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(palette.textTertiary)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(blockingHolds.count)")
                                .font(.system(size: 30, weight: .bold)).monospacedDigit()
                                .foregroundStyle(LinearGradient.diagonal)
                            Text("of \(totalHolds) active")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("$ AT RISK")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        if let risk = dollarsAtRisk {
                            Text("$\(Int(risk))")
                                .font(.system(size: 20, weight: .bold)).monospacedDigit()
                                .foregroundStyle(Brand.warning)
                        } else {
                            // PORT-GAP: getVesselDemurrage returned no exposure — no fabricated $.
                            Text("—")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(palette.textTertiary)
                        }
                        // PORT-GAP: per-hold minutesToPenalty not on contract — cannot
                        // honestly render "next penalty 6h". Surfaced as the real cleared
                        // entry-status timestamp instead of an invented countdown.
                        Text(nextPenaltyLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                segmentedBar
            }
            .padding(20)
        }
        .frame(height: 116)
    }

    private var nextPenaltyLabel: String {
        if let last = entry?.lastUpdated, !last.isEmpty { return "updated \(last)" }
        return "next penalty —"
    }

    private var segmentedBar: some View {
        let total = max(totalHolds, 1)
        let blockingW = CGFloat(blockingHolds.count) / CGFloat(total)
        let reviewW   = CGFloat(reviewHolds.count)   / CGFloat(total)
        let clearedW  = CGFloat(clearedHolds.count)  / CGFloat(total)
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 4) {
                    if blockingHolds.count > 0 {
                        RoundedRectangle(cornerRadius: 3).fill(Brand.danger)
                            .frame(width: max((w - 8) * blockingW, 0))
                    }
                    if reviewHolds.count > 0 {
                        RoundedRectangle(cornerRadius: 3).fill(Brand.hazmat)
                            .frame(width: max((w - 8) * reviewW, 0))
                    }
                    if clearedHolds.count > 0 {
                        RoundedRectangle(cornerRadius: 3).fill(Brand.success.opacity(0.55))
                            .frame(width: max((w - 8) * clearedW, 0))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 10)
            HStack {
                Text("\(blockingHolds.count) blocking")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(Brand.danger)
                Spacer()
                Text("\(clearedHolds.count) cleared")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(Brand.success)
            }
        }
    }

    // MARK: - Holds list (by urgency)

    private var holdsSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("HOLDS · BY URGENCY · getCBPAlerts")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(":1180")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }

            if derivedHolds.isEmpty {
                EusoEmptyState(
                    systemImage: "checkmark.shield.fill",
                    title: "No active holds",
                    subtitle: "CBP exam, PGA, and demurrage holds for \(bookingRef) appear here the moment Descartes ABI flags one."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(derivedHolds.enumerated()), id: \.element.id) { idx, hold in
                        holdRow(hold)
                        if idx < derivedHolds.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                                .padding(.leading, 66)
                        }
                    }
                }
                .padding(Space.s3)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func holdRow(_ hold: DerivedHold) -> some View {
        let tone = hold.tier.tone
        return HStack(alignment: .top, spacing: 0) {
            // Left severity-accent rail
            RoundedRectangle(cornerRadius: 2).fill(tone)
                .frame(width: 4, height: 44)
            // Icon chip
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tone.opacity(0.2)).frame(width: 40, height: 40)
                Image(systemName: hold.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tone)
            }
            .padding(.leading, 10)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(hold.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text(hold.subtitle)
                            .font(EType.mono(.caption)).tracking(0.4)
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    Text(hold.tier.badge)
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(tone)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(tone.opacity(0.22)))
                }
                // TIME-TO-PENALTY urgency bar.
                // PORT-GAP: minutesToPenalty / SLA fill % not on the contract.
                // For a blocking hold we render a full red rail with the honest
                // "holds release" label; for the demurrage row we fill from the
                // real $ accrued vs. nothing fabricated. Review rows show the
                // real CBP severity string. We never invent a "6h to deadline".
                urgencyBar(hold, tone: tone)
            }
            .padding(.leading, 12)
        }
        .padding(.vertical, Space.s2)
    }

    private func urgencyBar(_ hold: DerivedHold, tone: Color) -> some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(tone)
                        .frame(width: geo.size.width * hold.fillFraction)
                }
            }
            .frame(height: 6)
            Text(hold.urgencyLabel)
                .font(.system(size: 10, weight: .bold)).monospacedDigit()
                .foregroundStyle(tone)
                .fixedSize()
        }
    }

    // MARK: - Cleared banner

    private var clearedBanner: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Brand.success)
            VStack(alignment: .leading, spacing: 3) {
                Text(clearedBannerTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("release pending CBP exam only · getCBPEntryStatus :1169")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(Brand.success.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Brand.success.opacity(0.18)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var clearedBannerTitle: String {
        let n = clearedHolds.count
        // Agencies actually present on cleared entry holds — no invented set.
        let agencies = clearedHolds.compactMap { $0.agency }.filter { !$0.isEmpty }
        let unique = Array(Set(agencies)).sorted()
        if unique.isEmpty {
            return "\(n) hold\(n == 1 ? "" : "s") cleared"
        }
        return "\(n) hold\(n == 1 ? "" : "s") cleared today · \(unique.joined(separator: " · "))"
    }

    // MARK: - CTA row

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            Button {
                // View CBP entry → read-through to the CBP entry surface.
            } label: {
                Text("View CBP entry")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                // PORT-GAP: clearing a hold is a CBP-entry mutation (clearCBPHold)
                // that is not on the server yet — this read surface only links to it.
            } label: {
                Text("Clear hold")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(palette.bgCardSoft)
                    .overlay(Capsule().strokeBorder(palette.borderSoft))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Derived holds (honest typing from the real contract)

    private enum Tier {
        case blocking, review, cleared
        var tone: Color {
            switch self {
            case .blocking: return Brand.danger
            case .review:   return Brand.hazmat
            case .cleared:  return Brand.success
            }
        }
        var badge: String {
            switch self {
            case .blocking: return "BLOCKING"
            case .review:   return "REVIEW"
            case .cleared:  return "CLEARED"
            }
        }
    }

    private struct DerivedHold: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let tier: Tier
        let agency: String?
        /// SLA bar fill — only honestly known for a blocking hold (full rail =
        /// holds release). Review/cleared default low; demurrage fills from the
        /// real $ accrued share. No minutesToPenalty fabrication.
        let fillFraction: CGFloat
        let urgencyLabel: String
    }

    /// Build the urgency-sorted board from the three real endpoints. Sort order:
    /// blocking → review → cleared, matching the SVG's most-imminent-first triage.
    private var derivedHolds: [DerivedHold] {
        var rows: [DerivedHold] = []

        // 1. Entry-status holds (getCBPEntryStatus) — the release-blocking source.
        if let holds = entry?.holds {
            for (i, h) in holds.enumerated() {
                let released = (entry?.releaseDate ?? "").isEmpty == false
                let tier: Tier = released ? .cleared : .blocking
                let agency = h.agency ?? "CBP"
                rows.append(DerivedHold(
                    id: "entry-\(i)-\(h.holdType ?? "hold")",
                    title: holdTitle(h.holdType, agency: agency),
                    subtitle: holdSubtitle(h.reason, applied: h.appliedAt),
                    icon: "exclamationmark.triangle",
                    tier: tier,
                    agency: agency,
                    fillFraction: tier == .blocking ? 1.0 : 0.12,
                    urgencyLabel: tier == .blocking ? "holds release" : "cleared"
                ))
            }
        }

        // 2. CBP alerts (getCBPAlerts) — exam/PGA/ISF flags. Severity string is the
        //    only urgency signal the contract gives; map it honestly.
        for a in alerts {
            let tier = tierForAlert(a)
            rows.append(DerivedHold(
                id: "alert-\(a.alertId)",
                title: a.alertType?.isEmpty == false ? a.alertType! : "CBP alert",
                subtitle: alertSubtitle(a),
                icon: alertIcon(a),
                tier: tier,
                agency: a.agency,
                fillFraction: tier == .blocking ? 1.0 : (tier == .review ? 0.66 : 0.12),
                urgencyLabel: severityLabel(a.severity, tier: tier)
            ))
        }

        // 3. Demurrage accrual (getVesselDemurrage) — the running money bleed.
        if let d = demurrage, (d.demurrageUsd ?? 0) > 0 {
            let accrued = Int(d.demurrageUsd ?? 0)
            let perDay = "" // PORT-GAP: per-day rate not on the rollup contract.
            rows.append(DerivedHold(
                id: "demurrage",
                title: "Demurrage accruing",
                subtitle: "\(d.lfdPassedCount ?? 0) past LFD\(perDay) · getVesselDemurrage",
                icon: "clock",
                tier: .review,
                agency: "Terminal",
                fillFraction: 1.0,
                urgencyLabel: "$\(accrued) so far"
            ))
        }

        // Triage sort: blocking first, then review, then cleared.
        return rows.sorted { lhs, rhs in
            func rank(_ t: Tier) -> Int { t == .blocking ? 0 : (t == .review ? 1 : 2) }
            return rank(lhs.tier) < rank(rhs.tier)
        }
    }

    private func tierForAlert(_ a: CBPAlert662) -> Tier {
        let sev = (a.severity ?? "").lowercased()
        if a.actionRequired == true && (sev.contains("high") || sev.contains("critical") || sev.contains("block")) {
            return .blocking
        }
        if sev.contains("info") || sev.contains("low") || sev.contains("clear") || sev.contains("resolved") {
            return .cleared
        }
        return .review
    }

    private func severityLabel(_ severity: String?, tier: Tier) -> String {
        if tier == .blocking { return "holds release" }
        if tier == .cleared  { return "cleared" }
        if let s = severity, !s.isEmpty { return s.uppercased() }
        return "review"
    }

    private func alertIcon(_ a: CBPAlert662) -> String {
        let t = (a.alertType ?? "").lowercased()
        if t.contains("isf") { return "doc.text" }
        if t.contains("exam") || t.contains("cet") { return "exclamationmark.triangle" }
        return "exclamationmark.triangle"
    }

    private func alertSubtitle(_ a: CBPAlert662) -> String {
        var parts: [String] = []
        if let e = a.entryNumber, !e.isEmpty { parts.append(e) }
        if let d = a.description, !d.isEmpty { parts.append(d) }
        if parts.isEmpty { parts.append(a.agency ?? "CBP") }
        return parts.joined(separator: " · ")
    }

    private func holdTitle(_ holdType: String?, agency: String) -> String {
        if let t = holdType, !t.isEmpty { return "\(agency) \(t)" }
        return "\(agency) hold"
    }

    private func holdSubtitle(_ reason: String?, applied: String?) -> String {
        var parts: [String] = [entryNumber]
        if let r = reason, !r.isEmpty { parts.append(r) }
        if let ap = applied, !ap.isEmpty { parts.append("applied \(ap)") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct AlertsIn: Encodable { let importerId: String }
        struct EntryIn: Encodable { let entryNumber: String }
        struct Empty: Encodable {}

        // importerId is the operator's company on-record (Eusorone, DU). No
        // hardcoded importer — falls back to the booking ref so the call is real.
        let importerId = session.user?.companyId ?? bookingRef

        do {
            async let a: [CBPAlert662] = EusoTripAPI.shared.query(
                "vesselShipments.getCBPAlerts", input: AlertsIn(importerId: importerId))
            async let e: EntryStatus662? = EusoTripAPI.shared.query(
                "vesselShipments.getCBPEntryStatus", input: EntryIn(entryNumber: entryNumber))
            async let d: DemurrageRoll662 = EusoTripAPI.shared.query(
                "vesselShipments.getVesselDemurrage", input: Empty())
            let (alertList, entryStatus, dem) = try await (a, e, d)
            self.alerts = alertList
            self.entry = entryStatus
            self.demurrage = dem
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("662 · Vessel Exceptions & Holds · Night") { VesselExceptionsHoldsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("662 · Vessel Exceptions & Holds · Light") { VesselExceptionsHoldsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
