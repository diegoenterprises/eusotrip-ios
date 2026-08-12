//
//  730_VesselBlankSailingWatch.swift
//  EusoTrip — Vessel Operator · Blank Sailing Watch (DETAIL/BOARD grammar).
//
//  Verbatim bespoke port of canonical wireframe 730 "Vessel Blank Sailing
//  Watch" (06 Vessel · Light + Dark). Monitors cancelled / rolled / omitted
//  sailings, surfaces the affected booking + the rank-1 re-booking slot, and
//  turns a quiet schedule notice into a one-glance triage: cancelled count,
//  rolled count, next-review countdown, the disruption board, and a single
//  tap to re-book the next-best voyage.
//
//  Layout (matches the SVG verbatim):
//    · eyebrow  "✦ VESSEL OPERATOR · BLANK SAILING WATCH"  ·  "watch · 7d"
//    · back chevron + headline "Blank Sailings" + ellipsis
//    · iridescent hairline
//    · hero card (gradient rim) — chips "N cancelled" / "M scheduled",
//      big cancelled count + "cancelled this week" + lead voyage/carrier,
//      ROLLED count + "bookings affected"
//    · KPI strip — CANCELLED (gradient tile) · ROLLED · NEXT REVIEW
//    · VOYAGES · dashboard board — one disruption row per voyage
//      (vessel name + voyage, carrier · disruption_type, CANCEL/OMIT/SHIFT
//      badge, lane unlocode), + archive footnote
//    · AFFECTED BOOKING strip — booking id · voy · capacity pulled +
//      rebook rank-1 slot line
//    · CTA row — "Report new disruption" (primary) · "Re-book" (secondary)
//
//  REAL WIRING (tRPC · server/routers/blankSailing.ts · vesselProcedure —
//  re-verified against the live router 2026-06-10):
//    · blankSailing.dashboard            {} → { summary:{cancelledSailings,
//        scheduledSailings}, cancelledVoyages[], scheduledVoyages[] } — raw
//        vessel_voyages rows (id, vesselId, voyageNumber, serviceRoute,
//        scheduledDeparture, status). SAME proc 688 Sailing Schedule consumes.
//    · vesselShipments.getVesselFleet    {limit} → vesselId → vessel name /
//        ownerCompany enrichment for the board rows + the report payload.
//    · blankSailing.reportBlankSailing   mutation {voyageId?, vesselName,
//        voyageNumber, carrier, originalEtd, reason} → "Report new disruption"
//        CTA. The operator picks a LIVE scheduled voyage from an inline picker;
//        every required field is sourced from that real row (vessel name +
//        carrier from the fleet record) — never typed in by the client. Result
//        is the real { affectedShipments, reason } shape.
//    · "Re-book" CTA → pushes the registered Rebooking Suggestions surface
//        (Vesl706) via the role-stack nav swap. (The raw
//        blankSailing.rebookingSuggestions proc REQUIRES a shipmentId this
//        watch board doesn't own — calling it input-less always failed.)
//
//  RBAC: vesselProcedure (CATALYST · DISPATCHER · VESSEL_OPERATOR).
//  NAV (VesselOperatorNavController): HOME(current) · SHIPMENTS · [orb]
//  · COMPLIANCE · ME.
//
//  ZERO mock data. Every count / row / booking line derives from the live
//  dashboard payload, with honest em-dashes for metrics the server does not
//  track (rolled bookings, next review, archive). When the dashboard is empty
//  the board renders an explicit "no blank sailings on watch" state rather
//  than fabricating voyages.
//
//  De-fab salvage 2026-06-10 (from PR #50): fixed the reportBlankSailing
//  payload (was missing 4 required fields + used a wrong key, so it always
//  400'd), fixed the result decode (server returns affectedShipments, not
//  success), retargeted Re-book to Vesl706, removed server-file/line dev-leak
//  strings from display copy, de-fabricated the zero-claiming ROLLED/archive
//  rollups, and removed the decorative back chevron.
//

import SwiftUI

struct VesselBlankSailingWatchScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselBlankSailingWatchBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: true),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror server: blankSailing.ts)

/// One disrupted voyage row on the watch board.
/// `blankSailing.dashboard` returns these in `cancelledVoyages` /
/// `scheduledVoyages`.
/// Mirrors the raw `vessel_voyages` row the live dashboard returns:
/// { id, vesselId, voyageNumber, serviceRoute, scheduledDeparture, status }.
/// Vessel name/carrier are NOT on the row — they are enriched client-side from
/// the live fleet (vesselId → vessels.name / vessels.ownerCompany).
private struct BlankSailingVoyage730: Decodable, Identifiable {
    let id: Int
    let vesselId: Int?
    let voyageNumber: String?
    let serviceRoute: String?       // e.g. transpacific service string (REAL column)
    let status: String?             // scheduled · departed · in_transit · arrived · completed · cancelled
    let scheduledDeparture: String?

    private enum CodingKeys: String, CodingKey {
        case id, vesselId
        case voyageNumber, voyageNo, voyage
        case serviceRoute, service_route
        case status
        case scheduledDeparture, scheduled_departure, etd
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int.self, forKey: .id) {
            id = i
        } else if let s = try? c.decode(String.self, forKey: .id), let i = Int(s) {
            id = i
        } else {
            id = 0
        }
        if let i = try? c.decode(Int.self, forKey: .vesselId) { vesselId = i }
        else if let s = try? c.decode(String.self, forKey: .vesselId), let i = Int(s) { vesselId = i }
        else { vesselId = nil }
        voyageNumber = (try? c.decode(String.self, forKey: .voyageNumber))
            ?? (try? c.decode(String.self, forKey: .voyageNo))
            ?? (try? c.decode(String.self, forKey: .voyage))
        serviceRoute = (try? c.decode(String.self, forKey: .serviceRoute))
            ?? (try? c.decode(String.self, forKey: .service_route))
        status = try? c.decode(String.self, forKey: .status)
        scheduledDeparture = (try? c.decode(String.self, forKey: .scheduledDeparture))
            ?? (try? c.decode(String.self, forKey: .scheduled_departure))
            ?? (try? c.decode(String.self, forKey: .etd))
    }
}

/// `vesselShipments.getVesselFleet` → vesselId → name/ownerCompany enrichment.
private struct FleetResponse730: Decodable {
    let vessels: [FleetVessel730]
}

private struct FleetVessel730: Decodable, Identifiable {
    let id: Int
    let name: String?
    let ownerCompany: String?
}

/// `blankSailing.dashboard` summary block.
private struct BlankSailingSummary730: Decodable {
    let cancelledSailings: Int?
    let scheduledSailings: Int?
    let rolledBookings: Int?
    let nextReviewHours: Int?
    let archivedCount: Int?
    let leadVoyageNumber: String?
    let leadCarrier: String?

    private enum CodingKeys: String, CodingKey {
        case cancelledSailings, cancelled, cancelledCount
        case scheduledSailings, scheduled, scheduledCount
        case rolledBookings, rolled, affectedBookings
        case nextReviewHours, nextReview, reviewHours
        case archivedCount, archived
        case leadVoyageNumber, leadVoyage
        case leadCarrier
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cancelledSailings = (try? c.decode(Int.self, forKey: .cancelledSailings))
            ?? (try? c.decode(Int.self, forKey: .cancelled))
            ?? (try? c.decode(Int.self, forKey: .cancelledCount))
        scheduledSailings = (try? c.decode(Int.self, forKey: .scheduledSailings))
            ?? (try? c.decode(Int.self, forKey: .scheduled))
            ?? (try? c.decode(Int.self, forKey: .scheduledCount))
        rolledBookings = (try? c.decode(Int.self, forKey: .rolledBookings))
            ?? (try? c.decode(Int.self, forKey: .rolled))
            ?? (try? c.decode(Int.self, forKey: .affectedBookings))
        nextReviewHours = (try? c.decode(Int.self, forKey: .nextReviewHours))
            ?? (try? c.decode(Int.self, forKey: .nextReview))
            ?? (try? c.decode(Int.self, forKey: .reviewHours))
        archivedCount = (try? c.decode(Int.self, forKey: .archivedCount))
            ?? (try? c.decode(Int.self, forKey: .archived))
        leadVoyageNumber = (try? c.decode(String.self, forKey: .leadVoyageNumber))
            ?? (try? c.decode(String.self, forKey: .leadVoyage))
        leadCarrier = try? c.decode(String.self, forKey: .leadCarrier)
    }
}

private struct BlankSailingDashboard730: Decodable {
    let summary: BlankSailingSummary730?
    let cancelledVoyages: [BlankSailingVoyage730]?
    let scheduledVoyages: [BlankSailingVoyage730]?
    let affectedBooking: AffectedBooking730?

    private enum CodingKeys: String, CodingKey {
        case summary
        case cancelledVoyages, cancelled_voyages, voyages
        case scheduledVoyages, scheduled_voyages
        case affectedBooking, affected_booking, affected
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = try? c.decode(BlankSailingSummary730.self, forKey: .summary)
        cancelledVoyages = (try? c.decode([BlankSailingVoyage730].self, forKey: .cancelledVoyages))
            ?? (try? c.decode([BlankSailingVoyage730].self, forKey: .cancelled_voyages))
            ?? (try? c.decode([BlankSailingVoyage730].self, forKey: .voyages))
        scheduledVoyages = (try? c.decode([BlankSailingVoyage730].self, forKey: .scheduledVoyages))
            ?? (try? c.decode([BlankSailingVoyage730].self, forKey: .scheduled_voyages))
        affectedBooking = (try? c.decode(AffectedBooking730.self, forKey: .affectedBooking))
            ?? (try? c.decode(AffectedBooking730.self, forKey: .affected_booking))
            ?? (try? c.decode(AffectedBooking730.self, forKey: .affected))
    }
}

/// AFFECTED BOOKING strip — the booking whose capacity got pulled + the
/// rank-1 re-booking slot (`reportBlankSailing` / `rebookingSuggestions`).
private struct AffectedBooking730: Decodable {
    let bookingNumber: String?
    let voyageNumber: String?
    let reason: String?
    let rebookVoyageNumber: String?
    let rebookEtd: String?
    let rebookAddedDays: Int?

    private enum CodingKeys: String, CodingKey {
        case bookingNumber, booking, bookingNo
        case voyageNumber, voyage
        case reason, note
        case rebookVoyageNumber, rebookVoyage, rebook_voyage
        case rebookEtd, rebook_etd, etd
        case rebookAddedDays, addedDays, added_days
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bookingNumber = (try? c.decode(String.self, forKey: .bookingNumber))
            ?? (try? c.decode(String.self, forKey: .booking))
            ?? (try? c.decode(String.self, forKey: .bookingNo))
        voyageNumber = (try? c.decode(String.self, forKey: .voyageNumber))
            ?? (try? c.decode(String.self, forKey: .voyage))
        reason = (try? c.decode(String.self, forKey: .reason))
            ?? (try? c.decode(String.self, forKey: .note))
        rebookVoyageNumber = (try? c.decode(String.self, forKey: .rebookVoyageNumber))
            ?? (try? c.decode(String.self, forKey: .rebookVoyage))
            ?? (try? c.decode(String.self, forKey: .rebook_voyage))
        rebookEtd = (try? c.decode(String.self, forKey: .rebookEtd))
            ?? (try? c.decode(String.self, forKey: .rebook_etd))
            ?? (try? c.decode(String.self, forKey: .etd))
        rebookAddedDays = (try? c.decode(Int.self, forKey: .rebookAddedDays))
            ?? (try? c.decode(Int.self, forKey: .addedDays))
            ?? (try? c.decode(Int.self, forKey: .added_days))
    }
}

/// `blankSailing.reportBlankSailing` REAL result shape:
/// { affectedShipments: number, reason: string }.
private struct ReportBlankSailingResult730: Decodable {
    let affectedShipments: Int?
    let reason: String?
}

// MARK: - Body

private struct VesselBlankSailingWatchBody: View {
    @Environment(\.palette) private var palette

    @State private var dashboard: BlankSailingDashboard730? = nil
    @State private var vesselsById: [Int: FleetVessel730] = [:]
    @State private var loading = true
    @State private var loadError: String? = nil

    // Report-new-disruption mutation (primary CTA → inline live-voyage picker).
    @State private var reporting = false
    @State private var showReportPicker = false
    @State private var reportAck: String? = nil
    @State private var reportError: String? = nil

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
                        voyagesSection
                        affectedBookingStrip
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

    // MARK: - Derived

    private var summary: BlankSailingSummary730? { dashboard?.summary }

    /// Disruption rows = the live cancelled voyages. (The vessel_voyages status
    /// enum carries no omit/shift flag, so we never invent flagged-scheduled
    /// rows — only real cancellations sit on the board.)
    private var disruptionRows: [BlankSailingVoyage730] {
        dashboard?.cancelledVoyages ?? []
    }

    /// Live scheduled voyages — the report picker's source of truth.
    private var scheduledRows: [BlankSailingVoyage730] {
        dashboard?.scheduledVoyages ?? []
    }

    private var cancelledCount: Int {
        summary?.cancelledSailings ?? (dashboard?.cancelledVoyages?.count ?? 0)
    }
    private var scheduledCount: Int {
        summary?.scheduledSailings ?? (dashboard?.scheduledVoyages?.count ?? 0)
    }

    /// Rolled bookings are NOT tracked by the live dashboard — render the
    /// summary figure when the server starts folding it in, em-dash until then.
    private var rolledLabel: String {
        if let r = summary?.rolledBookings { return "\(r)" }
        return "—"
    }

    private var nextReviewLabel: String {
        if let h = summary?.nextReviewHours { return "\(h)h" }
        return "—"
    }

    private func vesselName(for voyage: BlankSailingVoyage730) -> String? {
        guard let vid = voyage.vesselId, let v = vesselsById[vid] else { return nil }
        return (v.name?.isEmpty == false) ? v.name : nil
    }

    private func vesselCarrier(for voyage: BlankSailingVoyage730) -> String? {
        guard let vid = voyage.vesselId, let v = vesselsById[vid] else { return nil }
        return (v.ownerCompany?.isEmpty == false) ? v.ownerCompany : nil
    }

    private var leadVoyageLine: String {
        guard let lead = dashboard?.cancelledVoyages?.first else {
            return "no lead voyage on watch"
        }
        var parts: [String] = []
        if let voy = lead.voyageNumber, !voy.isEmpty { parts.append("voy \(voy)") }
        if let carrier = vesselCarrier(for: lead) { parts.append(carrier) }
        else if let vessel = vesselName(for: lead) { parts.append(vessel) }
        return parts.isEmpty ? "no lead voyage on watch" : parts.joined(separator: " · ")
    }

    // MARK: - Top bar (eyebrow + back + headline + ellipsis)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · BLANK SAILING WATCH")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 8)
                Text("watch · 7d")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Text("Blank Sailings")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s4)
        }
        .padding(.top, Space.s5)
    }

    // MARK: - Hero card (gradient rim · chips + cancelled count + rolled)

    private var heroCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: Space.s3) {
                // Chips: "N cancelled" · "M scheduled".
                HStack(spacing: 8) {
                    heroChip("\(cancelledCount) cancelled")
                    heroChip("\(scheduledCount) scheduled")
                }
                // Big cancelled count + caption + lead voyage line.
                HStack(alignment: .top, spacing: Space.s3) {
                    Text("\(cancelledCount)")
                        .font(.system(size: 30, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("cancelled this week")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text(leadVoyageLine)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
            // ROLLED column — honest em-dash until the server tracks rolls.
            VStack(alignment: .leading, spacing: 4) {
                Text("ROLLED")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(rolledLabel)
                    .font(.system(size: 22, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("bookings affected")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.top, 28)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: 1.5)
        )
    }

    private func heroChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold)).tracking(0.5)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(palette.textTertiary.opacity(0.12)))
    }

    // MARK: - KPI strip (CANCELLED gradient · ROLLED · NEXT REVIEW)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            // CANCELLED — gradient-fill tile.
            VStack(alignment: .leading, spacing: 8) {
                Text("CANCELLED")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(.white.opacity(0.85))
                Text("\(cancelledCount)")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white).monospacedDigit()
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .padding(Space.s4)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            kpiTile(label: "ROLLED", value: rolledLabel)
            kpiTile(label: "NEXT REVIEW", value: nextReviewLabel)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func kpiTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textPrimary).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - VOYAGES · dashboard board

    private var voyagesSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("VOYAGES · DASHBOARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("Live")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, Space.s1)

            VStack(spacing: 0) {
                if disruptionRows.isEmpty {
                    cleanWatchRow
                } else {
                    let rows = disruptionRows
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, voyage in
                        voyageRow(voyage)
                        if idx < rows.count - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                    archiveFootnote
                }
            }
            .padding(.vertical, Space.s1)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    /// Honest "clean watch" state — no fabricated voyage rows.
    private var cleanWatchRow: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.success.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Brand.success)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("No blank sailings on watch")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("schedule firm · no cancellations or omissions")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
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

    private func voyageRow(_ voyage: BlankSailingVoyage730) -> some View {
        let kind = disruptionKind(voyage)
        return HStack(alignment: .top, spacing: Space.s3) {
            // Disruption glyph chip — torn-schedule mark.
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(kind.color.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(kind.color)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: Space.s2) {
                    Text(voyageTitle(voyage))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: Space.s2)
                    Text(kind.badge)
                        .font(.system(size: 11, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(kind.color)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(kind.color.opacity(0.16)))
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(voyageMeta(voyage))
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: Space.s2)
                    if let etd = shortETD(voyage) {
                        Text(etd)
                            .font(.system(size: 13, weight: .bold)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                    }
                }
            }
        }
        .padding(Space.s4)
    }

    private func voyageTitle(_ v: BlankSailingVoyage730) -> String {
        let vessel = (vesselName(for: v) ?? "").trimmingCharacters(in: .whitespaces)
        let voy = (v.voyageNumber ?? "").trimmingCharacters(in: .whitespaces)
        if !vessel.isEmpty && !voy.isEmpty { return "\(vessel) \(voy)" }
        if !vessel.isEmpty { return vessel }
        if !voy.isEmpty { return "voy \(voy)" }
        return "Voyage"
    }

    private func voyageMeta(_ v: BlankSailingVoyage730) -> String {
        var parts: [String] = []
        if let c = vesselCarrier(for: v) { parts.append(c) }
        if let r = v.serviceRoute, !r.isEmpty { parts.append(r) }
        if let s = v.status, !s.isEmpty { parts.append(s.lowercased()) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    /// "ETD MM-dd" trailing label from the real scheduled departure.
    private func shortETD(_ v: BlankSailingVoyage730) -> String? {
        guard let etd = v.scheduledDeparture, !etd.isEmpty else { return nil }
        return "ETD \(shortDate(etd))"
    }

    /// CANCEL badge keyed off the REAL status enum (scheduled · departed ·
    /// in_transit · arrived · completed · cancelled). The schema carries no
    /// omit/shift disruption taxonomy, so we never claim one.
    private func disruptionKind(_ v: BlankSailingVoyage730) -> (badge: String, color: Color) {
        let t = (v.status ?? "").lowercased()
        if t.contains("cancel") {
            return ("CANCEL", Brand.danger)
        }
        return ("WATCH", Brand.warning)
    }

    /// Archive footnote — rendered ONLY when the server actually reports an
    /// archive count. No fabricated "no prior cancellations" claim while the
    /// dashboard does not track an archive at all.
    @ViewBuilder
    private var archiveFootnote: some View {
        if let n = summary?.archivedCount {
            HStack {
                Text(n > 0
                     ? "+ \(n) prior cancellation\(n == 1 ? "" : "s") rolled into archive (last 30d)"
                     : "no prior cancellations in archive (last 30d)")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary)
                Spacer()
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s2)
            .padding(.bottom, Space.s1)
        }
    }

    // MARK: - AFFECTED BOOKING strip

    @ViewBuilder
    private var affectedBookingStrip: some View {
        let booking = dashboard?.affectedBooking
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("AFFECTED BOOKING")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Text("Live")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            if let b = booking {
                Text(affectedLine(b))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(rebookLine(b))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            } else {
                Text("No affected booking surfaced")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                Text("open Re-book to match a disrupted booking to its rank-1 slot")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func affectedLine(_ b: AffectedBooking730) -> String {
        var parts: [String] = []
        if let id = b.bookingNumber, !id.isEmpty { parts.append(id) }
        if let voy = b.voyageNumber, !voy.isEmpty { parts.append("voy \(voy)") }
        if let r = b.reason, !r.isEmpty { parts.append(r) } else { parts.append("capacity pulled") }
        return parts.joined(separator: " · ")
    }

    private func rebookLine(_ b: AffectedBooking730) -> String {
        guard let voy = b.rebookVoyageNumber, !voy.isEmpty else {
            return "rebook rank 1 = pending suggestion"
        }
        var line = "rebook rank 1 = voy \(voy)"
        if let etd = b.rebookEtd, !etd.isEmpty { line += " · ETD \(shortDate(etd))" }
        if let d = b.rebookAddedDays { line += " · +\(d)d added" }
        return line
    }

    // MARK: - CTA row (Report new disruption · Re-book)

    private var ctaRow: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if let ack = reportAck {
                ackCard(ack, gradient: true)
            }
            if let err = reportError {
                errCard(err)
            }
            HStack(spacing: Space.s2) {
                // Toggles the inline picker of LIVE scheduled voyages — the
                // operator confirms a real sailing before anything is filed.
                Button {
                    reportAck = nil; reportError = nil
                    withAnimation(.easeOut(duration: 0.18)) { showReportPicker.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        if reporting { ProgressView().tint(.white).scaleEffect(0.8) }
                        Text(reporting ? "Reporting…" : "Report new disruption")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(reporting)

                // Re-book → push the registered Rebooking Suggestions surface
                // (Vesl706) onto the role stack. The raw rebookingSuggestions
                // proc requires a shipmentId this board doesn't own — 706 is
                // the surface that binds one.
                Button {
                    NotificationCenter.default.post(
                        name: .eusoVesselNavSwap, object: nil,
                        userInfo: ["screenId": "Vesl706"])
                } label: {
                    Text("Re-book")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: 148, minHeight: 48)
                        .frame(maxWidth: .infinity)
                        .background(palette.bgCard)
                        .overlay(Capsule().strokeBorder(palette.borderFaint))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            if showReportPicker {
                reportPickerSection
            }
        }
    }

    // MARK: - Report picker (live scheduled voyages only)

    @ViewBuilder
    private var reportPickerSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("REPORT A SCHEDULED SAILING AS BLANK")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if scheduledRows.isEmpty {
                EusoEmptyState(
                    systemImage: "calendar",
                    title: "No scheduled sailings to report",
                    subtitle: "Live scheduled voyages will list here when the schedule has firm sailings.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(scheduledRows.prefix(6).enumerated()), id: \.element.id) { idx, voyage in
                        Button {
                            Task { await reportDisruption(voyage) }
                        } label: {
                            HStack(spacing: Space.s3) {
                                Image(systemName: "calendar.badge.exclamationmark")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Brand.warning)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(voyageTitle(voyage))
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(palette.textPrimary)
                                        .lineLimit(1).minimumScaleFactor(0.7)
                                    Text(voyageMeta(voyage))
                                        .font(EType.mono(.caption))
                                        .foregroundStyle(palette.textSecondary)
                                        .lineLimit(1).minimumScaleFactor(0.7)
                                }
                                Spacer(minLength: Space.s2)
                                if let etd = shortETD(voyage) {
                                    Text(etd)
                                        .font(.system(size: 12, weight: .bold)).monospacedDigit()
                                        .foregroundStyle(palette.textPrimary)
                                }
                            }
                            .padding(Space.s4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(reporting)
                        if idx < min(scheduledRows.count, 6) - 1 {
                            Divider().overlay(palette.borderFaint)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                }
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func ackCard(_ text: String, gradient: Bool) -> some View {
        LifecycleCard(accentGradient: gradient) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(text).font(EType.caption).foregroundStyle(palette.textPrimary)
            }
        }
    }

    private func errCard(_ text: String) -> some View {
        LifecycleCard(accentDanger: true) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.danger)
                Text(text).font(EType.caption).foregroundStyle(Brand.danger)
            }
        }
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
                .fill(palette.bgCardSoft).frame(height: 200)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        }
    }

    // MARK: - Date helper

    private func shortDate(_ s: String?) -> String {
        guard let s else { return "—" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = iso.date(from: s)
        if date == nil { iso.formatOptions = [.withInternetDateTime]; date = iso.date(from: s) }
        if date == nil {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            date = f.date(from: String(s.prefix(10)))
        }
        guard let d = date else { return String(s.prefix(10)) }
        let out = DateFormatter(); out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = "MM-dd"
        return out.string(from: d)
    }

    // MARK: - Load (blankSailing.dashboard)

    private func load() async {
        loading = true; loadError = nil
        struct FleetIn: Encodable { let limit: Int }
        do {
            // SAME canonical proc 688 Sailing Schedule consumes — the watch's
            // hero summary + cancelled/scheduled voyage rows. The fleet call
            // enriches vesselId → vessel name / owner (the voyage row itself
            // carries neither).
            async let dash: BlankSailingDashboard730 = EusoTripAPI.shared
                .queryNoInput("blankSailing.dashboard")
            async let fleet: FleetResponse730 = EusoTripAPI.shared.query(
                "vesselShipments.getVesselFleet", input: FleetIn(limit: 100))
            let (dashResp, fleetResp) = try await (dash, fleet)
            self.dashboard = dashResp
            self.vesselsById = Dictionary(
                fleetResp.vessels.map { ($0.id, $0) },
                uniquingKeysWith: { a, _ in a })
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    // MARK: - Report new disruption (blankSailing.reportBlankSailing)
    //
    // The live mutation REQUIRES vesselName, voyageNumber, carrier and
    // originalEtd. Every field is sourced from the picked live voyage row +
    // its fleet record; when the fleet record is incomplete we surface the
    // real gap instead of inventing a vessel or carrier name.

    private func reportDisruption(_ voyage: BlankSailingVoyage730) async {
        reporting = true; reportAck = nil; reportError = nil
        defer { reporting = false }

        guard let voyageNumber = voyage.voyageNumber, !voyageNumber.isEmpty else {
            reportError = "This voyage row has no voyage number on record; cannot file a disruption against it."
            return
        }
        guard let vessel = vesselName(for: voyage) else {
            reportError = "No vessel record found for voy \(voyageNumber) in the live fleet; cannot file without the vessel name."
            return
        }
        guard let etd = voyage.scheduledDeparture, !etd.isEmpty else {
            reportError = "Voy \(voyageNumber) has no scheduled departure on record; cannot file without the original ETD."
            return
        }
        // Carrier: the vessel's ownerCompany when the fleet tracks one, else
        // the vessel name itself (the operator of record) — never a brand pulled
        // out of thin air.
        let carrier = vesselCarrier(for: voyage) ?? vessel

        struct ReportIn: Encodable {
            let voyageId: Int
            let vesselName: String
            let voyageNumber: String
            let carrier: String
            let originalEtd: String
            let reason: String
        }
        let input = ReportIn(
            voyageId: voyage.id,
            vesselName: vessel,
            voyageNumber: voyageNumber,
            carrier: carrier,
            originalEtd: etd,
            reason: "blank_sailing")
        do {
            let result: ReportBlankSailingResult730 = try await EusoTripAPI.shared
                .mutation("blankSailing.reportBlankSailing", input: input)
            let affected = result.affectedShipments ?? 0
            reportAck = "Voy \(voyageNumber) reported blank · \(affected) booking\(affected == 1 ? "" : "s") affected. Watch board refreshed."
            withAnimation(.easeOut(duration: 0.18)) { showReportPicker = false }
            await load()
        } catch {
            reportError = error.eusoUserCopy
        }
    }
}

#Preview("730 · Vessel Blank Sailing Watch · Night") { VesselBlankSailingWatchScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("730 · Vessel Blank Sailing Watch · Light") { VesselBlankSailingWatchScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
