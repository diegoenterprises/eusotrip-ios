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
//  REAL WIRING (tRPC · server/routers/blankSailing.ts · vesselProcedure):
//    · blankSailing.dashboard            {} → hero summary + voyage rows
//        (blankSailing.ts:17) — SAME proc 688 Sailing Schedule already
//        consumes; returns { summary, cancelledVoyages[], scheduledVoyages[] }.
//    · blankSailing.reportBlankSailing   mutation → "Report new disruption"
//        primary CTA (blankSailing.ts:41 · broadcasts WS voyageBlanked).
//    · blankSailing.rebookingSuggestions {} → "Re-book" secondary CTA
//        (blankSailing.ts:78 · rank-1 next-best voyage → 706).
//
//  RBAC: vesselProcedure (CATALYST · DISPATCHER · VESSEL_OPERATOR).
//  transportMode=vessel · lanes USLGB/USOAK · ocean catalysts CMA-CGM/MSC/ONE.
//  NAV (VesselOperatorNavController): HOME(current) · SHIPMENTS · [orb]
//  · COMPLIANCE · ME.
//
//  ZERO mock data. Every count / row / booking line derives from the live
//  dashboard payload; the mutation + rebooking CTAs hit the real procedures
//  and degrade to honest ack / error states. When the dashboard is empty the
//  board renders an explicit "no blank sailings on watch" state rather than
//  fabricating voyages.
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
/// `scheduledVoyages`. Field names mirror the vesselVoyages table the
/// 688 Sailing Schedule screen also decodes, with the disruption columns
/// (`disruptionType`, `carrier`, `loadingPort`/`portCode`) layered on.
private struct BlankSailingVoyage730: Decodable, Identifiable {
    let id: Int
    let voyageNumber: String?
    let vesselName: String?
    let carrier: String?
    let disruptionType: String?     // blank_sailing · port_omission · schedule_change
    let status: String?             // scheduled · cancelled · omitted · shifted
    let portCode: String?           // lane unlocode, e.g. USLGB / USOAK
    let scheduledDeparture: String?

    private enum CodingKeys: String, CodingKey {
        case id, voyageNumber, voyageNo, voyage
        case vesselName, vessel, name
        case carrier, carrierName, ocean_carrier
        case disruptionType, disruption_type, type, reason
        case status
        case portCode, port_code, unlocode, loadingPort, lane
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
        voyageNumber = (try? c.decode(String.self, forKey: .voyageNumber))
            ?? (try? c.decode(String.self, forKey: .voyageNo))
            ?? (try? c.decode(String.self, forKey: .voyage))
        vesselName = (try? c.decode(String.self, forKey: .vesselName))
            ?? (try? c.decode(String.self, forKey: .vessel))
            ?? (try? c.decode(String.self, forKey: .name))
        carrier = (try? c.decode(String.self, forKey: .carrier))
            ?? (try? c.decode(String.self, forKey: .carrierName))
            ?? (try? c.decode(String.self, forKey: .ocean_carrier))
        disruptionType = (try? c.decode(String.self, forKey: .disruptionType))
            ?? (try? c.decode(String.self, forKey: .disruption_type))
            ?? (try? c.decode(String.self, forKey: .type))
            ?? (try? c.decode(String.self, forKey: .reason))
        status = try? c.decode(String.self, forKey: .status)
        portCode = (try? c.decode(String.self, forKey: .portCode))
            ?? (try? c.decode(String.self, forKey: .port_code))
            ?? (try? c.decode(String.self, forKey: .unlocode))
            ?? (try? c.decode(String.self, forKey: .loadingPort))
            ?? (try? c.decode(String.self, forKey: .lane))
        scheduledDeparture = (try? c.decode(String.self, forKey: .scheduledDeparture))
            ?? (try? c.decode(String.self, forKey: .scheduled_departure))
            ?? (try? c.decode(String.self, forKey: .etd))
    }
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

/// `blankSailing.rebookingSuggestions` → rank-1 next-best voyage (→ 706).
private struct RebookingSuggestion730: Decodable {
    let voyageNumber: String?
    let etd: String?
    let addedDays: Int?

    private enum CodingKeys: String, CodingKey {
        case voyageNumber, voyage, rebookVoyage
        case etd, scheduledDeparture
        case addedDays, added_days
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        voyageNumber = (try? c.decode(String.self, forKey: .voyageNumber))
            ?? (try? c.decode(String.self, forKey: .voyage))
            ?? (try? c.decode(String.self, forKey: .rebookVoyage))
        etd = (try? c.decode(String.self, forKey: .etd))
            ?? (try? c.decode(String.self, forKey: .scheduledDeparture))
        addedDays = (try? c.decode(Int.self, forKey: .addedDays))
            ?? (try? c.decode(Int.self, forKey: .added_days))
    }
}

private struct ReportBlankSailingResult730: Decodable {
    let success: Bool?
    let disruptionId: String?
}

// MARK: - Body

private struct VesselBlankSailingWatchBody: View {
    @Environment(\.palette) private var palette

    @State private var dashboard: BlankSailingDashboard730? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Report-new-disruption mutation (primary CTA).
    @State private var reporting = false
    @State private var reportAck: String? = nil
    @State private var reportError: String? = nil

    // Re-book / rebookingSuggestions (secondary CTA).
    @State private var rebooking = false
    @State private var rebookAck: String? = nil
    @State private var rebookError: String? = nil

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

    /// Disruption rows = cancelled voyages first (the watch's priority), then
    /// any scheduled voyages flagged with a disruption_type (omit/shift).
    private var disruptionRows: [BlankSailingVoyage730] {
        var rows = dashboard?.cancelledVoyages ?? []
        let flaggedScheduled = (dashboard?.scheduledVoyages ?? []).filter {
            let t = ($0.disruptionType ?? "").lowercased()
            return !t.isEmpty && t != "none"
        }
        rows.append(contentsOf: flaggedScheduled)
        return rows
    }

    private var cancelledCount: Int {
        summary?.cancelledSailings ?? (dashboard?.cancelledVoyages?.count ?? 0)
    }
    private var scheduledCount: Int {
        summary?.scheduledSailings ?? (dashboard?.scheduledVoyages?.count ?? 0)
    }
    private var rolledCount: Int { summary?.rolledBookings ?? 0 }

    private var nextReviewLabel: String {
        if let h = summary?.nextReviewHours { return "\(h)h" }
        return "—"
    }

    private var leadVoyageLine: String {
        let voy = summary?.leadVoyageNumber
            ?? dashboard?.cancelledVoyages?.first?.voyageNumber
        let carrier = summary?.leadCarrier
            ?? dashboard?.cancelledVoyages?.first?.carrier
        var parts: [String] = []
        if let voy, !voy.isEmpty { parts.append("voy \(voy)") }
        if let carrier, !carrier.isEmpty { parts.append(carrier) }
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
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
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
            // ROLLED column.
            VStack(alignment: .leading, spacing: 4) {
                Text("ROLLED")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("\(rolledCount)")
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

            kpiTile(label: "ROLLED", value: "\(rolledCount)")
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
                Text("blankSailing.ts:17")
                    .font(EType.mono(.caption))
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
                    if let lane = voyage.portCode, !lane.isEmpty {
                        Text(lane.uppercased())
                            .font(.system(size: 13, weight: .bold)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                    }
                }
            }
        }
        .padding(Space.s4)
    }

    private func voyageTitle(_ v: BlankSailingVoyage730) -> String {
        let vessel = (v.vesselName ?? "").trimmingCharacters(in: .whitespaces)
        let voy = (v.voyageNumber ?? "").trimmingCharacters(in: .whitespaces)
        if !vessel.isEmpty && !voy.isEmpty { return "\(vessel) \(voy)" }
        if !vessel.isEmpty { return vessel }
        if !voy.isEmpty { return "voy \(voy)" }
        return "Voyage"
    }

    private func voyageMeta(_ v: BlankSailingVoyage730) -> String {
        var parts: [String] = []
        if let c = v.carrier, !c.isEmpty { parts.append(c) }
        if let t = v.disruptionType, !t.isEmpty { parts.append(t.lowercased()) }
        else if let s = v.status, !s.isEmpty { parts.append(s.lowercased()) }
        return parts.isEmpty ? "ocean disruption" : parts.joined(separator: " · ")
    }

    /// CANCEL / OMIT / SHIFT — colour + label keyed off disruption type/status.
    private func disruptionKind(_ v: BlankSailingVoyage730) -> (badge: String, color: Color) {
        let t = (v.disruptionType ?? v.status ?? "").lowercased()
        if t.contains("blank") || t.contains("cancel") {
            return ("CANCEL", Brand.danger)
        }
        if t.contains("omit") || t.contains("omission") {
            return ("OMIT", Brand.warning)
        }
        if t.contains("shift") || t.contains("schedule_change") || t.contains("schedule") || t.contains("change") {
            return ("SHIFT", Brand.warning)
        }
        return ("WATCH", Brand.warning)
    }

    private var archiveFootnote: some View {
        let n = summary?.archivedCount ?? 0
        return HStack {
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

    // MARK: - AFFECTED BOOKING strip

    @ViewBuilder
    private var affectedBookingStrip: some View {
        let booking = dashboard?.affectedBooking
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("AFFECTED BOOKING · REPORTBLANKSAILING")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Text("blankSailing.ts:41")
                    .font(EType.mono(.caption))
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
                Text("No affected booking on this voyage yet")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                Text("re-booking suggestions populate when a sailing is reported blank")
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
            if let ack = rebookAck {
                ackCard(ack, gradient: true)
            }
            if let err = rebookError {
                errCard(err)
            }
            HStack(spacing: Space.s2) {
                Button {
                    Task { await reportDisruption() }
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

                Button {
                    Task { await rebook() }
                } label: {
                    HStack(spacing: 6) {
                        if rebooking { ProgressView().tint(palette.textPrimary).scaleEffect(0.8) }
                        Text(rebooking ? "…" : "Re-book")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                    }
                    .frame(maxWidth: 148, minHeight: 48)
                    .frame(maxWidth: .infinity)
                    .background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(rebooking)
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
        do {
            // SAME canonical proc 688 Sailing Schedule consumes — the watch's
            // hero summary + cancelled/scheduled voyage rows + affected booking.
            let dash: BlankSailingDashboard730 = try await EusoTripAPI.shared
                .queryNoInput("blankSailing.dashboard")
            self.dashboard = dash
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Report new disruption (blankSailing.reportBlankSailing)

    private func reportDisruption() async {
        reporting = true; reportAck = nil; reportError = nil
        // Report the lead at-risk voyage on the watch as blanked. The real
        // procedure keys on the voyage being reported; we surface the live
        // row so the operator confirms a real disruption, never a fabricated one.
        let lead = dashboard?.cancelledVoyages?.first ?? disruptionRows.first
        struct ReportIn: Encodable {
            let voyageId: Int?
            let voyageNumber: String?
            let disruptionType: String
        }
        let input = ReportIn(
            voyageId: lead.map { $0.id },
            voyageNumber: lead?.voyageNumber,
            disruptionType: "blank_sailing"
        )
        do {
            let result: ReportBlankSailingResult730 = try await EusoTripAPI.shared
                .mutation("blankSailing.reportBlankSailing", input: input)
            if result.success == true {
                reportAck = "Disruption reported. Watch board refreshed."
                await load()
            } else {
                reportError = "Report did not confirm. Try again."
            }
        } catch {
            reportError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        reporting = false
    }

    // MARK: - Re-book (blankSailing.rebookingSuggestions → 706)

    private func rebook() async {
        rebooking = true; rebookAck = nil; rebookError = nil
        do {
            let suggestion: RebookingSuggestion730 = try await EusoTripAPI.shared
                .queryNoInput("blankSailing.rebookingSuggestions")
            if let voy = suggestion.voyageNumber, !voy.isEmpty {
                var line = "Rank-1 re-book = voy \(voy)"
                if let etd = suggestion.etd, !etd.isEmpty { line += " · ETD \(shortDate(etd))" }
                if let d = suggestion.addedDays { line += " · +\(d)d" }
                rebookAck = line
            } else {
                rebookError = "No re-booking slot available right now."
            }
        } catch {
            rebookError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        rebooking = false
    }
}

#Preview("730 · Vessel Blank Sailing Watch · Night") { VesselBlankSailingWatchScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("730 · Vessel Blank Sailing Watch · Light") { VesselBlankSailingWatchScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
