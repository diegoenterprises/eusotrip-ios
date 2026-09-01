//
//  835_VesselCraneSequence.swift
//  EusoTrip — Vessel Operator · Load & Discharge Sequence (835).
//
//  App-integrated composition of "835 Vessel Load & Discharge Sequence.svg"
//  (Dark → Light). CRANE SWIM-LANE SEQUENCE BOARD archetype — the berth work
//  order: a moves-complete progress hero (rate + ETA finish), then one LANE per
//  gantry (CRN-1 / CRN-2 / CRN-3), each carrying a horizontal, ordered RUN of
//  move slots (LOAD / DISC / RESTOW · move # · bay) chained by sequence
//  connectors, a restow & hatch-conflict callout, the ESANG re-order advisory,
//  and the terminal-labor authority band. Deliberately NOT a row-stack ledger
//  and NOT a KPI quartet — the lanes read left-to-right as time. Sibling 834 is
//  a class-condition worksheet built on two naval instruments and shares nothing
//  below the house header.
//  Nav: HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME.
//
//  WIRING (honest):
//    REAL — vesselShipments.getVesselShipmentDetail (vesselShipments.ts,
//        vesselProcedure, input { id: Int }) → { shipment: { id, vesselName,
//        bookingNumber, originPort, destinationPort, … } }. That is the ONLY
//        live read on this surface; it supplies the vessel and booking ref the
//        berth call is worked against.
//    FIXED REFERENCE (not fabricated) — the LOAD / DISCHARGE / RESTOW move
//        taxonomy, the CRN-1..3 gantry identities on the berth, and the
//        ILWU-PMA / ILWU Canada-BCMEA / maniobristas-API labor map. Physical
//        and published facts, so they render as text.
//    STUB · named-gap — there is no crane-sequence model on disk (grep
//        craneSequence = 0); it would derive from the BAPLIE pre-stow + bay plan:
//          vessel.getCraneSequence({callId}) → { movesDone, movesTotal,
//              ratePerHr, etaFinish, restowsQueued, hatchConflicts,
//              cranes:[{ name, done, total, ratePerHr,
//                        moves:[{ no, kind: load|disc|restow, bay }] }] }
//          vessel.commitCraneSequence({callId, confirm:true}) → writes the
//              crane_sequence row + blockchainAuditTrail vessel.sequence_committed,
//              broadcasts WS_CHANNELS.VESSEL_OPS / WS_EVENTS.SEQUENCE_COMMITTED.
//              RBAC vesselProcedure.
//        Until those ship, every move slot renders as an EMPTY ordered slot, the
//        counters render em-dash, and the progress tracks stay unfilled. No move
//        number, bay, rate or ETA on this screen is invented. The SVG's
//        illustrative figures (418/980 moves, 31/hr, ETA 21:10, moves #418–#420
//        / #392–#394 / #360–#362) exist only in this comment as the shape the
//        model must return.
//    COUNTRY: single-country terminal labor — US ILWU + PMA active · CA ILWU
//        Canada + BCMEA · MX local maniobristas + API terminal.
//
//  OFFLINE POLICY: READ_CACHED(15m) for the sequence read — a crane board is
//    worked on the quay and from the bridge wing where signal drops, so the last
//    good serve of the berth-call context stays on screen and is labelled as
//    awaiting rather than blanked; it is never passed off as a fresh sequence.
//    HONEST SCOPE OF THAT TIER: the retained serve is held IN MEMORY for the
//    life of the session — a failed refresh is banner-flagged above the content
//    it keeps rather than blanking the screen. There is NO persistent cache
//    layer behind it: Services/EusoTripAPI.swift:415-416 sets
//    .reloadIgnoringLocalAndRemoteCacheData and urlCache = nil, so nothing
//    survives a cold launch and the 15m TTL is a policy declaration, not an
//    enforced one. OPEN item (owning lane: the-oath) — a real on-disk read
//    cache with TTL enforcement.
//    commitCraneSequence is ONLINE_ONLY(class-approval and berth commit must not
//    be queued) — committing a sequence dispatches longshore labor and gantry
//    work against a berth window, so a stale queued commit would put cranes on
//    the wrong bays; the CTA refuses with an on-screen reason instead.
//
//  CHAIN closure: WS_EVENTS.SEQUENCE_COMMITTED on WS_CHANNELS.VESSEL_OPS is
//    emitted by the (stub) commitCraneSequence and is meant to be received by
//    the terminal counter-party — the yard/gantry dispatch board that puts the
//    committed run in front of the crane drivers and the planner watching the
//    berth window. That receiving half DOES NOT EXIST: the iOS RealtimeService
//    subscribes no VESSEL_OPS channel and no vessel-ops listener is registered
//    anywhere in the client. OPEN counter-party item → the-oath (vessel lane
//    owns the emit; the terminal/yard lane owns the missing receiver). Until it
//    lands, a commit here is write-only and no crane driver is notified.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselCraneSequenceScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0
    /// Berth call the board is opened against. Keys the STUB sequence read once
    /// vessel.getCraneSequence ships. Empty by default — which berth face a
    /// vessel is working is getCraneSequence data, so no berth is asserted here.
    var berthId: String = ""

    var body: some View {
        Shell(theme: theme) {
            VesselCraneSequenceBody(shipmentId: shipmentId, berthId: berthId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",         isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Shipment shape (getVesselShipmentDetail · the one REAL read)

private struct SequenceShipment835: Decodable {
    let id: Int?
    let vesselName: String?
    let bookingNumber: String?
    let originPort: String?
    let destinationPort: String?
}
private struct SequenceDetail835: Decodable {
    // FLAT-SHAPE REPAIR (2026-08-17). `vesselShipments.getVesselShipmentDetail`
    // returns a FLAT spread — `return { ...shipment, lifecycleStage, bols,
    // customs, events, demurrage, containers, originPort, destinationPort }`
    // (vesselShipments.ts:587). There is NO `shipment` wrapper key. Decoding a
    // wrapper against the real payload does NOT throw — the optional simply
    // yields nil — so the screen loads "successfully" and then renders its
    // awaiting state forever, invisibly. Decode off the ROOT; a wrapper is
    // still tolerated so a future revision cannot silently break this again.
    let shipment: SequenceShipment835?

    private enum CodingKeys: String, CodingKey { case shipment }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let wrapped = try? c.decodeIfPresent(SequenceShipment835.self, forKey: .shipment) {
            self.shipment = wrapped
        } else {
            self.shipment = try? SequenceShipment835(from: decoder)   // real shape: fields sit on the root
        }
    }
}

// MARK: - Body

private struct VesselCraneSequenceBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let berthId: String

    @State private var shipment: SequenceShipment835? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    /// Set when the operator taps Commit — states plainly why the sequence
    /// cannot be written yet. Never a fake success.
    @State private var commitNotice: String? = nil

    private let pendingAmber = Color(hex: 0xFFC246)
    private let loadGreen = Color(hex: 0x34D8A6)
    private let discBlue = Color(hex: 0x5AB0FF)
    private let restowAmber = Color(hex: 0xFFC246)

    /// The board's three gantry POSITIONS — the structure a crane sequence is
    /// planned into, not a roster of cranes anyone has put on this ship. How
    /// many gantries are actually working a berth face is getCraneSequence
    /// (STUB) data, as are the moves each lane carries; both stay unassigned.
    private let gantries = ["CRN-1", "CRN-2", "CRN-3"]
    private let slotsPerLane = 4

    private var vesselLine: String {
        let name = shipment?.vesselName ?? "—"   // no booking selected: assert no ship
        let berth = berthId.isEmpty ? "berth —" : "Berth \(berthId)"
        return "\(name) · \(berth) · \(gantries.count) gantry positions · none assigned yet"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · LOAD SEQUENCE",
                caption: "BAY PLAN · MOVE LIST",   // was "MSC · USLGB" — named a carrier and a port with no booking loaded
                title: "Crane sequence",
                idText: shipment?.bookingNumber,
                subtitle: vesselLine
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    skeleton
                } else if let err = loadError, shipment == nil {
                    // Nothing retained to keep — the failure IS the screen.
                    VesselErrorCard(text: err)
                } else {
                    if let err = loadError {
                        // Non-destructive refresh banner. A failed re-read never
                        // blanks a serve that is already on screen; it is flagged
                        // as no-longer-fresh above the retained content.
                        VesselErrorCard(text: "Refresh failed — \(err) The board below is the last serve this session returned and is not being updated.")
                    }
                    progressHero
                    laneSection
                    restowCallout
                    esangCard
                    VesselRegulatorBand(
                        title: "TERMINAL LABOR · SINGLE-COUNTRY",
                        reference: "labor-country",
                        rows: [
                            .init("US", "ILWU · PMA longshore jurisdiction", active: true),
                            .init("CA", "ILWU Canada · BCMEA"),
                            .init("MX", "Local maniobristas · API terminal")
                        ]
                    )
                    ctaPair
                    if let notice = commitNotice {
                        VesselGapNote(text: notice)
                    }
                    VesselGapNote(text: "Vessel and booking context are verified live. No crane sequence is linked to this berth call, so every lane shows its ordered slots empty and the move counters, rates and finish ETA are shown awaiting the sequence rather than estimated.")
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Progress hero (moves complete against the berth window)

    private var progressHero: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    Text(berthId.isEmpty ? "Berth — · window not returned"
                                         : "Berth \(berthId) · window not returned")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    pendingChip("SEQUENCE PENDING")
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("— / —")
                        .font(.system(size: 28, weight: .bold)).monospacedDigit()
                        .foregroundStyle(pendingAmber)
                    Text("moves complete")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                }
                // Berth-window progress track: empty until a sequence exists.
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(palette.tintNeutral)
                    .frame(height: 10)
                Text("rate — moves/hr · restows — queued · ETA finish —")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    // MARK: - Crane lanes (one swim-lane per gantry)

    private var laneSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "CRANE LANES · WORK ORDER", right: "NO GANTRY OR MOVE ASSIGNED")
            VesselGroupCard(padded: false) {
                VStack(spacing: 0) {
                    ForEach(Array(gantries.enumerated()), id: \.offset) { idx, crane in
                        if idx > 0 { Divider().overlay(palette.borderFaint) }
                        craneLane(crane)
                    }
                }
            }
            moveKeyRow
        }
    }

    private func craneLane(_ crane: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(discBlue)
                    Text(crane)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.bgCardSoft))
                Spacer(minLength: 6)
                Text("— / — · —/hr")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            // Lane progress track — unfilled, no move count is known.
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(palette.tintNeutral)
                .frame(height: 6)
            // The RUN: ordered slots left-to-right, chained by connectors.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    Text("NOW")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                        .rotationEffect(.degrees(-90))
                        .fixedSize()
                        .frame(width: 14, height: 44)
                    ForEach(0..<slotsPerLane, id: \.self) { i in
                        if i > 0 { sequenceConnector }
                        emptyMoveSlot(order: i + 1)
                    }
                }
                .padding(.trailing, Space.s3)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s4)
    }

    private var sequenceConnector: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(palette.textTertiary.opacity(0.7))
            .padding(.horizontal, 5)
    }

    /// One ordered position in a crane's run. The slot's PLACE in the sequence
    /// is real (it is the nth lift this gantry will make); the move that fills
    /// it is what getCraneSequence must return.
    private func emptyMoveSlot(order: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text("MOVE \(order)")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(palette.tintNeutral))
                Spacer(minLength: 0)
            }
            Text("#—")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
            Text("bay —")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(8)
        .frame(width: 112, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(palette.borderFaint,
                          style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
    }

    private var moveKeyRow: some View {
        HStack(spacing: Space.s4) {
            moveKey("Load", loadGreen)
            moveKey("Discharge", discBlue)
            moveKey("Restow", restowAmber)
            Spacer(minLength: 0)
        }
    }

    private func moveKey(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: - Restow & hatch-conflict callout

    private var restowCallout: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "RESTOWS & HATCH CONFLICTS", right: "NOT EVALUATED")
            VesselGroupCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack(alignment: .top, spacing: Space.s3) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(restowAmber.opacity(0.13))
                                .frame(width: 36, height: 36)
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(restowAmber)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No restow set returned")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text("Restows and hatch-lift conflicts are derived from the pre-stow against the bay plan. Neither is linked to this berth call.")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    VesselSummaryStrip(
                        label: "Restows queued · hatch conflicts on the run",
                        value: "— · —",
                        valueColor: pendingAmber
                    )
                }
            }
        }
    }

    // MARK: - ESANG AI advisory

    private var esangCard: some View {
        VesselGroupCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: 8) {
                    OrbeSang(state: .idle, diameter: 22)
                    Text("ESANG AI")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(discBlue)
                    Spacer(minLength: 6)
                    Text("next best move")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.textTertiary)
                }
                Text("Re-order advice loads with the crane sequence")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("Once the ordered moves per gantry are available, ESANG can propose a re-order that clears restow-heavy bays ahead of the next hatch lift and cuts crane idle inside the berth window.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Chrome bits

    private func pendingChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
            .foregroundStyle(pendingAmber)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(pendingAmber.opacity(0.13)))
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Commit sequence",
                      action: { blockCommit() },
                      trailingIcon: "checkmark.seal")
            VesselGhostButton(title: "Move list", width: 150) {
                commitNotice = "The full move list opens once an ordered sequence is returned for this berth call."
            }
        }
    }

    private func blockCommit() {
        commitNotice = "Commit is withheld: no crane sequence is linked to this berth call yet. A commit dispatches longshore labor and gantry work against the berth window, so it is never queued offline and never written against an empty run."
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 150)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 260)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 110)
        }
    }

    // MARK: - Load (REAL: getVesselShipmentDetail)

    private func load() async {
        loading = true; loadError = nil
        guard shipmentId > 0 else { shipment = nil; loading = false; return }
        struct In: Encodable { let id: Int }
        do {
            let detail: SequenceDetail835? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: In(id: shipmentId))
            self.shipment = detail?.shipment
        } catch {
            // `shipment` is deliberately NOT cleared. A failed refresh keeps the
            // last decoded serve on screen, banner-labelled as not fresh, rather
            // than blanking a board being worked from the quay.
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("835 · Vessel Crane Sequence · Night") {
    VesselCraneSequenceScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("835 · Vessel Crane Sequence · Light") {
    VesselCraneSequenceScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
