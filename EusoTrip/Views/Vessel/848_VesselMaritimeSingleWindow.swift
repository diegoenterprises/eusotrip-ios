//
//  848_VesselMaritimeSingleWindow.swift
//  EusoTrip — Vessel Operator · Maritime Single Window (848).
//
//  Live-wired port of "848 Vessel Maritime Single Window.svg" (Light + Dark).
//  TRANSMISSION BOARD archetype — the ENVELOPE, never the contents.
//
//  Since the IMO FAL Convention made the maritime single window mandatory on
//  1 January 2024, a port call is not a stack of forms handed to a stack of
//  officials; it is ONE electronic window that receives the whole declaration
//  set and answers each piece. That is what this screen is: a per-declaration
//  transmission register. Every row is an envelope record — what was sent, at
//  what time, what the authority said back, and how many times it had to be
//  re-sent — closed by a single all-forms-lodged gate for the call. It never
//  shows a field of any form. What is inside FAL 1 is 849's job; whether FAL 1
//  left the ship and what the window replied is this screen's job.
//
//  Sibling separation (the sharpest clone risk in the band, because 849 is
//  literally one of the forms this hub submits):
//    · 849 General Declaration is ONE form's CONTENTS — a numbered document
//      face with a per-box validation gutter. It has no timestamps, no
//      acknowledgements, no resubmission counter and no second party.
//      848 has nothing BUT those, and no field values at all.
//    · 838 AMS 24-Hour Manifest is a single cargo filing on a cutoff clock —
//      one filing, one countdown, a bill roster. 848 is eight filings and no
//      countdown hero.
//    · 672 USCG Port Entry is the arrival-notice compliance check, not a
//      lodgement register.
//    · 663 CBP Entry Detail is one entry's interior. 848 lists entries as
//      envelopes and opens none of them.
//
//  WIRING (read first-hand off the live router this fire, not inherited):
//    REAL · vesselShipments.getVesselShipmentDetail (vesselShipments.ts:561,
//        vesselProcedure, input { id: number }). Returns a FLAT spread —
//        `{ ...shipment, lifecycleStage, bols, customs, events, demurrage,
//        containers, originPort, destinationPort }` (:587). The port call this
//        board covers, its ETA, its booking reference and its DESTINATION PORT
//        are live from here, and so is the `customs` array — the only
//        transmissions to a border authority that genuinely exist on disk.
//    REAL · vesselShipments.getPortDetails (:2313, input { portId: number }) —
//        `{ ...port, berths }` off the `ports` table: name, unlocode, country,
//        customsOffice. The arrival port in the header and on the gate is this
//        row, never a literal.
//    REAL (fixed regulation, not data) · the 24-hour advance notice-of-arrival
//        rule. US 33 CFR 160.212 requires the NOA at least 24 hours before
//        arrival for a voyage of 24 hours or more. The RULE is printed; the
//        deadline is derived ONLY when the booking carries a real ETA, and is
//        labelled as derived from that ETA. No ETA ⇒ no deadline is drawn.
//    REAL MUTATION · vesselShipments.updateCustomsStatus (:1401, input
//        { id: number, newStatus: "draft"|"filed"|"under_review"|"cleared"|
//        "held"|"rejected", holdReasons?: string[] }) — writes
//        customs_declarations.status, stamps filedDate on "filed" and
//        clearedDate on "cleared", and inserts blockchainAuditTrail
//        vessel.customs_status_updated. WIRED HERE FOR EXACTLY ONE TRANSITION:
//        draft → filed, on a real declaration row belonging to this booking.
//        That transition is the filer's own statement about the filer's own
//        act, which is the only status on that enum this device may honestly
//        assert. "cleared", "under_review", "held" and "rejected" are the
//        AUTHORITY's words — a carrier writing "cleared" onto its own entry
//        would manufacture an acknowledgement nobody gave, which is precisely
//        the lie a stale green badge tells. Those transitions are not wired
//        and will not be.
//    NOT WIRED, and why · vesselShipments.createCustomsEntry (:1349) is real
//        but its input shape does not fit this screen. It takes
//        { shipmentId, declarationType: "import"|"export"|"transit"|
//        "temporary_import", htsCode?, countryOfOrigin?, declaredValue?,
//        currency, dutyRate?, brokerId? } and inserts a DUTY ENTRY. A FAL
//        declaration has no declaration-type from that enum, no HTS code, no
//        declared value and no duty rate. Creating a customs entry to stand in
//        for a lodged FAL form would fabricate a commercial entry the master
//        never made. Named, not forced.
//    STUB · named-gap — there is NO single-window model on disk. Grepped
//        repo-wide this fire: `singleWindow|MSW` = 0, `generalDeclaration|FAL|
//        falForm` = 0, `shipStores|crewEffects` = 0. Proposed shapes:
//
//        vessel.getSingleWindowStatus({ callId: string }) -> {
//          callId: string,
//          window: { authority: string, regime: "US"|"CA"|"MX",
//                    connected: boolean, reference: string | null },
//          noticeDueAt: string | null,          // ISO, authority-issued
//          forms: Array<{
//            code: "FAL1"|"FAL2"|"FAL3"|"FAL4"|"FAL5"|"FAL6"|"FAL7"|"MDH",
//            required: boolean,
//            sentAt: string | null,             // ISO
//            state: "not_sent"|"queued"|"transmitted"|"acknowledged"
//                   |"rejected"|"not_required",
//            acknowledgedAt: string | null,     // ISO
//            acknowledgementRef: string | null, // the authority's own ref
//            rejectionReason: string | null,
//            resubmissions: number
//          }>,
//          allLodged: boolean
//        }
//
//        vessel.submitFALForm({ callId: string, form: FALCode,
//                               confirm: true })   [REGULATORY]
//          gated + confirm:true + audit + test + eval; pin .sortedKeys.
//          Writes the msw_submission row + blockchainAuditTrail
//          vessel.fal_submitted, broadcasts WS_CHANNELS.VESSEL_OPS /
//          WS_EVENTS.MSW_UPDATED. RBAC vesselProcedure (ship's agent / master).
//
//        Until those exist every form row reads NOT SENT with an em-dash
//        timestamp, an em-dash acknowledgement and an em-dash resubmission
//        count, the gate reads NOT LODGED, and Submit pending forms is
//        `.disabled(true)` with the missing procedure named on screen.
//
//    HONEST DEFECT FOUND, not inherited: `vessel_shipments` has NO vesselName
//        column (drizzle/schema.ts:11813 — the ship is `vesselId` → `vessels`).
//        Several landed siblings decode `vesselName` off getVesselShipmentDetail
//        and will silently receive nil forever. This screen does not depend on
//        it: the ship line falls back to the booking reference, and the ship's
//        own identity is 849's subject, not this board's.
//
//  COUNTRY (content inside the screen, never a file fork):
//    US NVMC eNOA-D + CBP ACE — FOREGROUNDED. CA CBSA ACI + Transport Canada
//    single-window initiative and MX SEMAR / VUCEM Ventanilla Única sit on the
//    standby band. One regime governs one call.
//
//  OFFLINE POLICY (doctrine W — derived, not stamped):
//    READ  · READ_CACHED(10m) with a VISIBLE staleness line. A lodgement
//            picture is still readable when it is a few minutes old, and this
//            screen is often opened on a bridge with a bad link. But an
//            acknowledgement is the one thing that must never go stale
//            silently — a cached "acknowledged" badge would tell a master the
//            call is cleared when the window may since have rejected a form.
//            So the retained serve is always banner-labelled and every
//            acknowledgement carries the time it was read, not the time it was
//            given.
//            HONEST SCOPE OF THAT TIER: what the code does today is retain the
//            last decoded serve IN MEMORY for the life of the session and
//            banner-flag a failed refresh above it instead of blanking the
//            board. There is NO persistent cache layer behind it —
//            Services/EusoTripAPI.swift:415-416 sets
//            .reloadIgnoringLocalAndRemoteCacheData and urlCache = nil — so
//            nothing survives a cold launch and the 10m TTL is a policy
//            declaration, not an enforced one. OPEN item (owning lane:
//            the-oath): a real on-disk read cache with TTL enforcement.
//    WRITE · ONLINE_ONLY(lodging a declaration to a border authority is a legal
//            filing). Submitting a FAL form, and recording a customs entry as
//            filed, are both statements to a government. Queued and replayed
//            later, a filing timestamp would assert a transmission that had not
//            happened at the moment it claims. Nothing here is ever enqueued.
//
//  CHAIN CLOSURE:
//    Intended emit WS_EVENTS.MSW_UPDATED on WS_CHANNELS.VESSEL_OPS, for the
//    compliance console (652) and the port-call surfaces that must learn a form
//    was lodged or rejected.
//    OPEN counter-party item (owning lane: VESSEL · the-oath): the receiving
//    half does not exist. RealtimeService carries no vessel:* case and
//    Views/Vessel holds zero realtime subscribers, so a lodgement result is
//    visible only on this screen's own refresh today. Named rather than papered
//    over with an emit nobody hears.
//
//  Nav: HOME · SHIPMENTS · [orb] · COMPLIANCE(current) · ME — the eyebrow, the
//  nav and this note agree.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselMaritimeSingleWindowScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            VesselMaritimeSingleWindowBody(shipmentId: shipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Live shapes (getVesselShipmentDetail :561 · getPortDetails :2313)

/// One real customs declaration row off the booking. These are the ONLY
/// transmissions to a border authority that exist on disk today, so the board
/// shows them as themselves — never dressed up as FAL forms.
private struct CustomsEntry848: Decodable, Identifiable {
    let id: Int
    let entryNumber: String?
    let declarationType: String?
    let status: String?
    let filedDate: String?
    let clearedDate: String?
    let countryOfOrigin: String?
}

private struct Port848: Decodable {
    let id: Int?
    let name: String?
    let unlocode: String?
    let country: String?
    let customsOffice: String?
}

private struct Detail848: Decodable {
    let id: Int?
    let bookingNumber: String?
    let billOfLading: String?
    let voyageNumber: String?
    let status: String?
    let eta: String?
    let ata: String?
    let destinationPortId: Int?
    let originPortId: Int?
    let destinationPort: Port848?
    let originPort: Port848?
    let customs: [CustomsEntry848]?

    /// FLAT-SHAPE GUARD. `getVesselShipmentDetail` returns `{ ...shipment, … }`
    /// with no `shipment` wrapper (vesselShipments.ts:587). Decoding a wrapper
    /// against the real payload does not throw — the optional simply yields nil
    /// — so a screen "loads" and then renders its awaiting state forever,
    /// invisibly. These keys are therefore read off the ROOT of the payload,
    /// which is where the server actually puts them.
    private enum CodingKeys: String, CodingKey {
        case id, bookingNumber, billOfLading, voyageNumber, status, eta, ata
        case destinationPortId, originPortId, destinationPort, originPort, customs
    }
}

// MARK: - The FAL declaration set (the envelope's fixed manifest)

/// The declaration set a maritime single window receives for one port call
/// under the FAL Convention. The SET is the regulation and is fixed; every
/// per-form STATE below arrives with getSingleWindowStatus and is unknown
/// until it does. `notSent` and `notRequired` are deliberately distinct —
/// "we have not sent it" and "this call does not need it" carry different
/// consequences and must never collapse into each other.
private enum FALState848 {
    case unknown          // no window connected — nothing has been reported
    case notSent
    case transmitted
    case acknowledged
    case rejected
    case notRequired
}

private struct FALForm848: Identifiable {
    let id: String        // the form code — stable, so no UUID re-minting
    let name: String
    let subject: String   // what the form declares (one short line)
    var state: FALState848 = .unknown
    var sentAt: String? = nil
    var ackRef: String? = nil
    var resubmissions: Int? = nil
}

// MARK: - Body

private struct VesselMaritimeSingleWindowBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int

    @State private var detail: Detail848? = nil
    @State private var arrivalPort: Port848? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var readAt: Date? = nil

    // The one real write this device may make, and its two-step arm.
    @State private var armedEntryId: Int? = nil
    @State private var filing = false
    @State private var fileAck: String? = nil
    @State private var fileError: String? = nil

    /// The fixed FAL manifest. STATIC on purpose — the content is regulation,
    /// not data, so one evaluation for the process is correct and the ForEach
    /// identity stays stable across re-inits.
    private static let manifest: [FALForm848] = [
        FALForm848(id: "FAL 1", name: "General Declaration",   subject: "ship, voyage and call particulars"),
        FALForm848(id: "FAL 2", name: "Cargo Declaration",     subject: "cargo carried on this call"),
        FALForm848(id: "FAL 3", name: "Ship's Stores",         subject: "stores held aboard"),
        FALForm848(id: "FAL 4", name: "Crew's Effects",        subject: "effects accompanying the crew"),
        FALForm848(id: "FAL 5", name: "Crew List",             subject: "the signed-on complement"),
        FALForm848(id: "FAL 6", name: "Passenger List",        subject: "passengers embarked or landed"),
        FALForm848(id: "FAL 7", name: "Dangerous Goods",       subject: "IMDG consignments aboard"),
        FALForm848(id: "MDH",   name: "Declaration of Health", subject: "health state of those aboard")
    ]

    // MARK: Derived context (all of it live or absent — none of it invented)

    private var arrivalPlace: String? {
        guard let p = arrivalPort ?? detail?.destinationPort else { return nil }
        let name = p.name?.trimmingCharacters(in: .whitespaces)
        let code = p.unlocode?.trimmingCharacters(in: .whitespaces)
        switch (name?.isEmpty == false ? name : nil, code?.isEmpty == false ? code : nil) {
        case let (n?, c?): return "\(n) \(c)"
        case let (n?, nil): return n
        case let (nil, c?): return c
        default: return nil
        }
    }

    private var headerTitle: String { arrivalPlace ?? "Port call" }

    private var callLine: String {
        var parts: [String] = []
        if let b = detail?.bookingNumber, !b.isEmpty { parts.append(b) }
        if let v = detail?.voyageNumber, !v.isEmpty { parts.append("voy \(v)") }
        parts.append("single window")
        return parts.joined(separator: " · ")
    }

    /// The 24-hour notice deadline is DERIVED, and only from a real ETA on the
    /// booking. No ETA ⇒ nothing is drawn, because a deadline invented from a
    /// guessed arrival is worse than no deadline at all.
    private var noticeDueLine: String {
        guard let etaISO = detail?.eta, let eta = Self.parseISO(etaISO) else {
            return "No ETA on this booking — the 24-hour notice deadline cannot be derived"
        }
        let due = eta.addingTimeInterval(-24 * 3600)
        return "ETA \(Self.stamp(eta)) · 24-hour notice due \(Self.stamp(due)) · derived from the booking ETA"
    }

    private var customsEntries: [CustomsEntry848] { detail?.customs ?? [] }

    private var draftEntry: CustomsEntry848? {
        customsEntries.first { ($0.status ?? "").lowercased() == "draft" }
    }

    private var stalenessLine: String {
        guard let readAt else { return "not yet read" }
        let mins = Int(Date().timeIntervalSince(readAt) / 60)
        if mins <= 0 { return "read just now" }
        return "read \(mins)m ago"
    }

    // MARK: Layout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · MARITIME SINGLE WINDOW",
                caption: "IMO FAL · MSW",
                title: headerTitle,
                subtitle: callLine
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading && detail == nil {
                    skeleton
                } else if let err = loadError, detail == nil {
                    // Nothing retained to keep — the failure IS the screen.
                    VesselErrorCard(text: err)
                } else {
                    if let err = loadError {
                        VesselErrorCard(text: "Refresh failed — \(err) The board below is the last serve this session returned and is not being updated.")
                    }
                    lodgementGate
                    transmissionLedger
                    authorityResponseSection
                    customsSection
                    VesselSummaryStrip(
                        label: "Arrival authority · \(arrivalPort?.customsOffice ?? "customs office not on the port record")",
                        value: "\(customsEntries.count) on file",
                        valueColor: customsEntries.isEmpty ? palette.textTertiary : palette.textPrimary
                    )
                    VesselRegulatorBand(
                        title: "SINGLE-WINDOW ROUTING · SINGLE-COUNTRY",
                        reference: "one regime per call",
                        rows: [
                            .init("US", "NVMC eNOA-D · CBP ACE", active: true),
                            .init("CA", "CBSA ACI · Transport Canada SWI"),
                            .init("MX", "SEMAR · VUCEM Ventanilla Única")
                        ]
                    )
                    if let fileAck { VesselToastRow(text: fileAck) }
                    if let fileError { VesselErrorCard(text: fileError) }
                    ctaPair
                    gapNotes
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - The gate (the whole call, one verdict)

    private var lodgementGate: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    Text("Declarations acknowledged by the window")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    dashedChip("WINDOW NOT CONNECTED", tone: palette.textTertiary)
                }
                // The call's single verdict. It stays NEUTRAL and em-dashed —
                // never green — because a lodgement count nobody returned is
                // the exact figure a master would act on at 04:00.
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("— / 8")
                        .font(.system(size: 32, weight: .bold, design: .monospaced)).tracking(-0.5)
                        .foregroundStyle(palette.textTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("declarations lodged")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("no acknowledgement received")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("ALL FORMS LODGED")
                            .font(.system(size: 7.5, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(palette.textTertiary)
                        HStack(spacing: 4) {
                            Image(systemName: "lock")
                                .font(.system(size: 9, weight: .bold))
                            Text("NOT LODGED")
                                .font(.system(size: 10, weight: .heavy)).tracking(0.3)
                        }
                        .foregroundStyle(Brand.warning)
                    }
                }
                envelopeStrip
                Text(noticeDueLine)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The rule is 33 CFR 160.212 — notice of arrival at least 24 hours ahead for a voyage of 24 hours or more. The rule is printed; no submission is plotted against it.")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Eight envelopes, one per declaration. Each is drawn UNSENT — a dashed
    /// outline with no fill — so the strip reads as a set of empty envelopes,
    /// not as a progress bar of a value nobody supplied.
    private var envelopeStrip: some View {
        HStack(spacing: 4) {
            ForEach(Self.manifest) { form in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(palette.tintNeutral)
                        .frame(height: 7)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(palette.textTertiary.opacity(0.5),
                                              style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
                        )
                    Text(form.id.replacingOccurrences(of: "FAL ", with: ""))
                        .font(.system(size: 7, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - The transmission ledger (the screen's organ)

    private var transmissionLedger: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "TRANSMISSION LEDGER · 8 DECLARATIONS",
                                right: "0 SENT · 0 ACKNOWLEDGED")
            VesselGroupCard(padded: false) {
                VStack(spacing: 0) {
                    ledgerColumnHeader
                    Divider().overlay(palette.borderSoft)
                    ForEach(Array(Self.manifest.enumerated()), id: \.element.id) { idx, form in
                        if idx > 0 { Divider().overlay(palette.borderFaint) }
                        ledgerRow(form)
                    }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "paperplane")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("Sent, acknowledged and re-sent counts arrive with the single-window record")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.65)
                Spacer(minLength: 0)
            }
        }
    }

    /// The board's column rule. A ledger with named columns is a board; the
    /// form face next door (849) has no columns at all.
    private var ledgerColumnHeader: some View {
        HStack(spacing: 0) {
            Text("DECLARATION")
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("SENT")
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 56, alignment: .trailing)
            Text("ACK")
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 56, alignment: .trailing)
            Text("RE-SENT")
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s3)
        .padding(.bottom, 6)
    }

    private func ledgerRow(_ form: FALForm848) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: Space.s3) {
                Text(form.id)
                    .font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(0.2)
                    .foregroundStyle(Brand.blue)
                    .frame(width: 42, height: 17)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Brand.blue.opacity(0.13)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(form.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(form.subject)
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 6)
                stateChip(form.state)
            }
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ledgerCell(Self.stampText(form.sentAt), width: 56)
                ledgerCell(form.ackRef ?? "—", width: 56)
                ledgerCell(form.resubmissions.map(String.init) ?? "—", width: 48)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    private func ledgerCell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(palette.textTertiary)
            .frame(width: width, alignment: .trailing)
            .lineLimit(1).minimumScaleFactor(0.7)
    }

    /// A REPORTED state gets a solid chip; an AWAITING state gets a dashed one.
    /// The dash is the carrier of "nobody has told us this yet" across the whole
    /// screen, so an acknowledgement that genuinely arrives must never wear it.
    private func stateChip(_ state: FALState848) -> some View {
        let label: String
        let tone: Color
        let dashed: Bool
        switch state {
        case .unknown:      label = "NOT SENT";     tone = palette.textTertiary; dashed = true
        case .notSent:      label = "NOT SENT";     tone = palette.textTertiary; dashed = true
        case .transmitted:  label = "TRANSMITTED";  tone = Brand.blue;           dashed = false
        case .acknowledged: label = "ACKNOWLEDGED"; tone = Brand.success;        dashed = false
        case .rejected:     label = "REJECTED";     tone = Brand.danger;         dashed = false
        case .notRequired:  label = "NOT REQUIRED"; tone = palette.textTertiary; dashed = false
        }
        return dashedChip(label, tone: tone, dashed: dashed)
    }

    private func dashedChip(_ label: String, tone: Color, dashed: Bool = true) -> some View {
        Text(label)
            .font(.system(size: 8.5, weight: .heavy)).tracking(0.3)
            .foregroundStyle(tone)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule().fill(dashed ? palette.tintNeutral : tone.opacity(0.14)))
            .overlay(
                Capsule().strokeBorder(tone.opacity(dashed ? 0.45 : 0.0),
                                       style: StrokeStyle(lineWidth: 1, dash: dashed ? [2.5, 2.5] : []))
            )
    }

    // MARK: - Authority response (the half of an envelope nobody else shows)

    private var authorityResponseSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "AUTHORITY RESPONSE · REJECTIONS & RE-SUBMISSIONS",
                                right: "NO RESPONSE ON RECORD")
            VesselGroupCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(spacing: Space.s3) {
                        Image(systemName: "tray")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("No acknowledgement or rejection has been received")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(2).minimumScaleFactor(0.8)
                            Text("A rejection shows the authority's reason and the recorded resubmission count for that form.")
                                .font(.system(size: 9.5, weight: .regular))
                                .foregroundStyle(palette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    Divider().overlay(palette.borderFaint)
                    HStack {
                        Text("Window reference")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                        Spacer(minLength: 8)
                        Text("—")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(palette.textTertiary)
                    }
                    HStack {
                        Text("Board read")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                        Spacer(minLength: 8)
                        Text(stalenessLine)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: - Customs entries on file (the REAL transmissions)

    private var customsSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "CUSTOMS ENTRIES ON FILE · THIS BOOKING",
                                right: customsEntries.isEmpty ? "NONE" : "\(customsEntries.count) ON FILE")
            VesselGroupCard(padded: customsEntries.isEmpty) {
                if customsEntries.isEmpty {
                    HStack(alignment: .top, spacing: Space.s3) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                            .frame(width: 20)
                        Text("No customs declaration is attached to this booking. When one exists it appears here with the status the customs router actually holds for it — draft, filed, under review, cleared, held or rejected — and nothing else.")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(customsEntries.enumerated()), id: \.element.id) { idx, entry in
                            if idx > 0 { Divider().overlay(palette.borderFaint) }
                            customsRow(entry)
                        }
                    }
                }
            }
        }
    }

    private func customsRow(_ entry: CustomsEntry848) -> some View {
        let status = (entry.status ?? "unknown").lowercased()
        return HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.entryNumber?.isEmpty == false ? entry.entryNumber! : "entry #\(entry.id)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(customsSubline(entry))
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 6)
            Text(status.replacingOccurrences(of: "_", with: " ").uppercased())
                .font(.system(size: 8.5, weight: .heavy)).tracking(0.3)
                .foregroundStyle(Self.customsTone(status))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(Self.customsTone(status).opacity(0.14)))
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    private func customsSubline(_ entry: CustomsEntry848) -> String {
        var parts: [String] = []
        if let t = entry.declarationType, !t.isEmpty {
            parts.append(t.replacingOccurrences(of: "_", with: " "))
        }
        if let o = entry.countryOfOrigin, !o.isEmpty { parts.append("origin \(o)") }
        if let f = entry.filedDate, let d = Self.parseISO(f) { parts.append("filed \(Self.stamp(d))") }
        if let c = entry.clearedDate, let d = Self.parseISO(c) { parts.append("cleared \(Self.stamp(d))") }
        return parts.isEmpty ? "no filing dates recorded" : parts.joined(separator: " · ")
    }

    private static func customsTone(_ status: String) -> Color {
        switch status {
        case "cleared":      return Brand.success
        case "filed":        return Brand.blue
        case "under_review": return Brand.warning
        case "held", "rejected": return Brand.danger
        default:             return Brand.neutral
        }
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                CTAButton(title: "Submit pending forms", trailingIcon: "paperplane")
                    .disabled(true)
                    .accessibilityHint("Unavailable until a maritime single-window submission record is connected")
                VesselGhostButton(
                    title: armedEntryId == nil ? "Record entry filed" : "Confirm filed",
                    width: 150
                ) { tapRecordFiled() }
                .disabled(draftEntry == nil || filing)
            }
            if draftEntry == nil {
                VesselGapNote(text: "Filing is unavailable because this booking has no customs declaration draft. Create the declaration first, then return here to record filing.")
            } else if armedEntryId != nil {
                VesselGapNote(text: "Confirm filed records the declaration as filed with the current date and an audit entry. It does not mean the authority accepted or cleared it.")
            }
        }
    }

    private func tapRecordFiled() {
        guard let entry = draftEntry, !filing else { return }
        if armedEntryId == entry.id {
            Task { await recordFiled(entry) }
        } else {
            armedEntryId = entry.id
            fileAck = nil
            fileError = nil
        }
    }

    // MARK: - Honest-gap notes

    private var gapNotes: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            VesselGapNote(text: "The port call, arrival port, and ETA are available. No maritime single-window submission record is connected, so filing times, acknowledgement references, and resubmission counts remain unknown. Form submission is disabled until that record is available.")
            VesselGapNote(text: "A cargo-duty entry cannot substitute for a maritime declaration because it records different legal facts.")
            VesselGapNote(text: "Border filings require an active connection and are never queued. Previously loaded status remains visible with its read time until you refresh.")
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 210)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 340)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 130)
        }
    }

    // MARK: - Load (REAL: getVesselShipmentDetail :561 → getPortDetails :2313)

    private func load() async {
        loading = true; loadError = nil
        guard shipmentId > 0 else {
            // No port call threaded in. The board is honestly empty rather than
            // populated with somebody else's call.
            detail = nil; arrivalPort = nil; loading = false
            return
        }
        struct DetailIn: Encodable { let id: Int }
        struct PortIn: Encodable { let portId: Int }
        do {
            let d: Detail848? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: DetailIn(id: shipmentId))
            self.detail = d
            self.readAt = Date()

            // The arrival port is the destination of an inbound call. The spread
            // already carries the joined row; getPortDetails is the authority for
            // the customs office and the UN/LOCODE, so it is read when there is a
            // port id to read it with. A failure here degrades to the joined row,
            // never to a literal.
            if let portId = d?.destinationPortId ?? d?.destinationPort?.id {
                self.arrivalPort = try? await EusoTripAPI.shared.query(
                    "vesselShipments.getPortDetails", input: PortIn(portId: portId))
            } else {
                self.arrivalPort = d?.destinationPort
            }
        } catch {
            // `detail` is deliberately NOT cleared. A failed refresh keeps the
            // last decoded serve on screen, banner-labelled as not fresh, rather
            // than blanking a board an agent may still be reading.
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    // MARK: - The one real write (updateCustomsStatus :1401 · draft → filed)

    private func recordFiled(_ entry: CustomsEntry848) async {
        filing = true; fileError = nil; fileAck = nil
        struct StatusIn: Encodable { let id: Int; let newStatus: String }
        struct StatusOut: Decodable { let success: Bool?; let newStatus: String? }
        do {
            let out: StatusOut = try await EusoTripAPI.shared.mutation(
                "vesselShipments.updateCustomsStatus",
                input: StatusIn(id: entry.id, newStatus: "filed"))
            let landed = out.newStatus ?? "filed"
            fileAck = "Entry \(entry.entryNumber ?? "#\(entry.id)") recorded as \(landed). This records your filing, not an authority acceptance."
            armedEntryId = nil
            await load()
        } catch {
            fileError = error.eusoUserCopy
            armedEntryId = nil
        }
        filing = false
    }

    // MARK: - Date helpers

    private static func parseISO(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = f.date(from: s) { return d }
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    private static func stamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM HH:mm"
        return f.string(from: d)
    }

    private static func stampText(_ s: String?) -> String {
        guard let d = parseISO(s) else { return "—" }
        return stamp(d)
    }
}

#Preview("848 · Vessel Maritime Single Window · Night") {
    VesselMaritimeSingleWindowScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("848 · Vessel Maritime Single Window · Light") {
    VesselMaritimeSingleWindowScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
