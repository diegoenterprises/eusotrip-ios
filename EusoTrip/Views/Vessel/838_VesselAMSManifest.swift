//
//  838_VesselAMSManifest.swift
//  EusoTrip — Vessel Operator · AMS 24-Hour Manifest (838).
//
//  Verbatim-composition port of "838 Vessel AMS 24-Hour Manifest.svg" (Dark →
//  Light). CUTOFF-COUNTDOWN + BILL-FILING-ROSTER archetype — a regulatory
//  filing gate: a T-MINUS hero counting down to the foreign-load AMS cutoff
//  with a four-stop filing pipeline (Load cutoff → AMS filed → CBP response →
//  DNL clear), a master/house bill roster where every bill carries its own
//  filing state, a do-not-load sentinel, and the tri-country advance-manifest
//  band. Nav: HOME · SHIPMENTS · [orb] · COMPLIANCE(current) · ME.
//
//  WIRING (honest):
//    Voyage / bill context is REAL — vesselShipments.getVesselShipmentDetail
//        (vesselShipments.ts, vesselProcedure, input { id: Int }) →
//        { shipment: { id, vesselName, bookingNumber, … } }. Vessel, voyage and
//        the master bill reference drive the header and the roster's master row
//        when a booking is selected.
//    The filing regime itself is the real fixed reference, not fabricated:
//        US CBP ACE AMS (24h before foreign load) / CA CBSA ACI eManifest /
//        MX SAT-Aduanas manifiesto.
//    CAUTION — do NOT conflate with ISF. The importer-side ISF filing IS real
//        (vesselShipments.fileISF); the CARRIER 24-hour advance cargo
//        declaration is a DISTINCT filing and has no model on disk.
//    There is NO AMS / advance-manifest model on disk (cutoff clock, filed vs
//        total bills, per-bill status, DNL holds; grep AMS/advance-manifest = 0)
//        → STUB · named-gap: vessel.getAMSManifest({voyageId}) +
//        vessel.fileAMSManifest({voyageId,confirm:true}) [REGULATORY: gated +
//        confirm:true + audit + test] → writes the ams_filing row +
//        blockchainAuditTrail vessel.ams_filed, broadcasts
//        WS_CHANNELS.VESSEL_OPS / WS_EVENTS.AMS_FILED. The countdown, the
//        filed/total split, the pipeline progress and every per-bill filing
//        state (ON FILE / AMENDED / DNL HOLD) render from that model once it
//        ships. Until then this screen shows honest awaiting-states — em-dash
//        clocks, PENDING chips, an unadvanced pipeline. A fabricated
//        do-not-load clearance would be a safety-class lie and is never drawn.
//    COUNTRY: US CBP ACE AMS 24h-before-load active · CA CBSA ACI eManifest ·
//        MX SAT-Aduanas manifiesto.
//
//  OFFLINE POLICY:
//    READ  · READ_CACHED(10m) — voyage + bill context may be served from the
//            10-minute cache; the cutoff clock is never served stale-silent.
//            HONEST SCOPE OF THAT TIER: what the code does today is retain the
//            last decoded serve IN MEMORY for the life of the session and
//            banner-flag a failed refresh above it instead of blanking the
//            screen. There is NO persistent cache layer behind it —
//            Services/EusoTripAPI.swift:415-416 sets
//            .reloadIgnoringLocalAndRemoteCacheData and urlCache = nil — so
//            nothing survives a cold launch and the 10m TTL is a policy
//            declaration, not an enforced one. OPEN item (owning lane:
//            the-oath): a real on-disk read cache with TTL enforcement.
//    WRITE · ONLINE_ONLY(regulatory filing must not be queued) — File / amend
//            AMS is a customs transmission; it may never be enqueued for later
//            replay. No connection, no filing.
//
//  CHAIN CLOSURE:
//    Emit WS_EVENTS.AMS_FILED on WS_CHANNELS.VESSEL_OPS is meant to land on the
//    customs / compliance consoles (the party that must see a DNL hold before a
//    box is loaded).
//    OPEN counter-party item (the-oath): that half does NOT exist. There is no
//    vessel-ops subscriber anywhere in Views/ — RealtimeService carries no
//    vessel:* case, and Views/Vessel holds ZERO realtime subscribers (its only
//    RealtimeService mentions are header comments like this one). Views/Dispatch
//    holds a single realtime subscriber, which is thin for that lane — but the
//    client as a whole is NOT that thin: Views/Shipper alone references
//    RealtimeService across ~23 files, with further use in Driver, Catalyst,
//    Escort, Rail and Carrier. The gap is vessel-specific, not app-wide.
//    Nothing on iOS would hear AMS_FILED today. Owning lanes: the
//    Compliance/Customs console lane (receiver) and the Dispatch lane (the
//    known systemic realtime-subscriber fault). Until a listener exists, the
//    filing result is visible only on this screen's own refresh.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselAMSManifestScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0
    var voyageId: String = "514W"

    var body: some View {
        Shell(theme: theme) {
            VesselAMSManifestBody(shipmentId: shipmentId, voyageId: voyageId)
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

// MARK: - Shipment shape (getVesselShipmentDetail)

private struct ManifestShipment838: Decodable {
    let id: Int?
    let vesselName: String?
    let bookingNumber: String?
    let billOfLading: String?
    let voyageNumber: String?
    let numberOfContainers: Int?
}
private struct ManifestDetail838: Decodable {
    // FLAT-SHAPE REPAIR (2026-08-17). `vesselShipments.getVesselShipmentDetail`
    // returns a FLAT spread — `return { ...shipment, lifecycleStage, bols,
    // customs, events, demurrage, containers, originPort, destinationPort }`
    // (vesselShipments.ts:587). There is NO `shipment` wrapper key. Decoding a
    // wrapper against the real payload does NOT throw — the optional simply
    // yields nil — so the screen loads "successfully" and then renders its
    // awaiting state forever, invisibly. Decode off the ROOT; a wrapper is
    // still tolerated so a future revision cannot silently break this again.
    let shipment: ManifestShipment838?

    private enum CodingKeys: String, CodingKey { case shipment }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let wrapped = try? c.decodeIfPresent(ManifestShipment838.self, forKey: .shipment) {
            self.shipment = wrapped
        } else {
            self.shipment = try? ManifestShipment838(from: decoder)   // real shape: fields sit on the root
        }
    }
}

// MARK: - Filing state vocabulary (the AMS bill states, incl. the danger state)

private enum AMSFilingState838 {
    case onFile, amended, dnlHold, pending

    var label: String {
        switch self {
        case .onFile:  return "ON FILE"
        case .amended: return "AMENDED"
        case .dnlHold: return "DO NOT LOAD"
        case .pending: return "PENDING"
        }
    }
}

// MARK: - Four-stop filing pipeline (private to 838)

/// The AMS filing pipeline: Load cutoff → AMS filed → CBP response → DNL clear.
/// `completed` is the index of the last CLEARED stop; it stays at -1 while no
/// filing record exists, so the rail renders wholly unadvanced rather than
/// implying a transmission that never happened.
private struct AMSFilingRail838: View {
    @Environment(\.palette) private var palette
    let stops: [String]
    let completed: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.offset) { idx, label in
                VStack(spacing: 6) {
                    dot(idx)
                    Text(label)
                        .font(.system(size: 8, weight: .heavy)).tracking(0.2)
                        .foregroundStyle(idx <= completed ? palette.textPrimary : palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
                if idx < stops.count - 1 {
                    Rectangle()
                        .fill(idx < completed ? Color(hex: 0x5AB0FF) : palette.tintNeutral)
                        .frame(height: 3)
                        .frame(maxWidth: .infinity)
                        .offset(y: -9)
                }
            }
        }
    }

    @ViewBuilder
    private func dot(_ idx: Int) -> some View {
        ZStack {
            if idx < completed {
                Circle().fill(Color(hex: 0x5AB0FF)).frame(width: 14, height: 14)
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .heavy)).foregroundStyle(.white)
            } else if idx == completed {
                Circle().fill(palette.bgCard).frame(width: 14, height: 14)
                Circle().strokeBorder(Color(hex: 0x5AB0FF), lineWidth: 2.6).frame(width: 14, height: 14)
            } else {
                Circle().fill(palette.bgCard).frame(width: 12, height: 12)
                Circle().strokeBorder(palette.textTertiary.opacity(0.65), lineWidth: 2).frame(width: 12, height: 12)
            }
        }
        .frame(width: 16, height: 16)
    }
}

// MARK: - Body

private struct VesselAMSManifestBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let voyageId: String

    @State private var shipment: ManifestShipment838? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    /// Set when the operator taps a CTA — states plainly why the write cannot
    /// happen and that it is never queued. Rendered through VesselGapNote, the
    /// neutral honest-gap affordance; never through the success toast.
    @State private var actionNote: String? = nil

    /// The regulatory filing sequence. The SEQUENCE is the real CBP process;
    /// how far it has advanced comes from getAMSManifest (STUB) and is held at
    /// "not started" until that record exists.
    private let pipeline = ["Load cutoff", "AMS filed", "CBP response", "DNL clear"]
    private var pipelineCompleted: Int { -1 }

    private var voyageLine: String {
        if let s = shipment {
            let vessel = s.vesselName ?? "vessel"
            let voy = s.voyageNumber.map { "voy \($0)" } ?? "voy \(voyageId)"
            return "\(vessel) · \(voy) · foreign-load AMS cutoff"
        }
        // 2026-08-25 — was "MSC ANNA · voy … · CNSHA load cutoff", a fabricated
        // ship, voyage and load port. It sat two lines above `masterRef`, whose
        // own comment reads "Never a stand-in ID" — the file contradicted itself.
        return "— · no booking selected · foreign-load AMS cutoff"
    }

    /// The master bill reference — REAL when a booking is loaded, an honest
    /// em-dash otherwise. Never a stand-in ID.
    private var masterRef: String {
        guard let s = shipment else { return "—" }
        if let bol = s.billOfLading, !bol.isEmpty { return bol }
        if let bkg = s.bookingNumber, !bkg.isEmpty { return bkg }
        return "—"
    }

    private var masterDetail: String {
        guard let s = shipment else { return "master bill loads with the booking" }
        if let n = s.numberOfContainers, n > 0 {
            return "carrier master · \(n) container\(n == 1 ? "" : "s") · house bills pending"
        }
        return "carrier master · house bills pending"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · AMS 24-HOUR MANIFEST",
                caption: "24-HOUR RULE · CBP ACE",   // was "MSC · CBP ACE" — ACE is the real filing system; the carrier was invented
                title: "24-hour manifest",
                subtitle: voyageLine
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
                        VesselErrorCard(text: "Refresh failed — \(err) The manifest below is the last serve this session returned and is not being updated.")
                    }
                    cutoffHero
                    billRoster
                    dnlSentinel
                    VesselSummaryStrip(label: "AMS transmission · CBP ACE response",
                                       value: "— of — accepted")
                    VesselRegulatorBand(
                        title: "ADVANCE MANIFEST · SINGLE-COUNTRY",
                        reference: "filing-country",
                        rows: [
                            .init("US", "CBP ACE · AMS 24h before load", active: true),
                            .init("CA", "CBSA ACI · eManifest 24h"),
                            .init("MX", "SAT-Aduanas · manifiesto")
                        ]
                    )
                    if let actionNote { VesselGapNote(text: actionNote) }
                    ctaPair
                    VesselGapNote(text: "Voyage and master-bill context are verified. The cutoff clock, the filed-versus-total split and every per-bill filing state appear only when the advance-manifest filing record responds — no clearance is shown that CBP has not given.")
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - T-MINUS cutoff hero (countdown + filed/total + filing pipeline)

    private var cutoffHero: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(alignment: .top) {
                    Text("CBP AMS · advance cargo declaration")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text("T-MINUS PENDING")
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Color(hex: 0xFFC246))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color(hex: 0xFFC246).opacity(0.13)))
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("—:—")
                        .font(.system(size: 32, weight: .bold, design: .monospaced)).tracking(-0.5)
                        .foregroundStyle(Color(hex: 0xFFC246))
                    Text("h:m to AMS cutoff")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 6)
                    Text("— / — bills filed")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                AMSFilingRail838(stops: pipeline, completed: pipelineCompleted)
            }
        }
    }

    // MARK: - Master / house bill roster (each bill carries its own filing state)

    private var billRoster: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "MANIFEST BILLS · MASTER / HOUSE",
                                right: "AWAITING FILING RECORD")
            VesselGroupCard(padded: false) {
                VStack(spacing: 0) {
                    billRow(indented: false,
                            accent: palette.textTertiary.opacity(0.5),
                            number: masterRef,
                            detail: masterDetail,
                            state: .pending)
                    Divider().overlay(palette.borderFaint).padding(.leading, Space.s4)
                    houseAwaitingRow
                }
            }
            filingStateKey
        }
    }

    private func billRow(indented: Bool,
                         accent: Color,
                         number: String,
                         detail: String,
                         state: AMSFilingState838) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            if indented {
                // House-bill indent guide (the master → house tree elbow).
                Path { p in
                    p.move(to: CGPoint(x: 5, y: 0))
                    p.addLine(to: CGPoint(x: 5, y: 15))
                    p.addLine(to: CGPoint(x: 14, y: 15))
                }
                .stroke(palette.textTertiary.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                .frame(width: 16, height: 30)
            }
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent).frame(width: 4, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(number)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(detail)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 6)
            Text(state.label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                .foregroundStyle(stateColor(state))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(stateColor(state).opacity(0.14)))
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    private var houseAwaitingRow: some View {
        billRow(indented: true,
                accent: palette.textTertiary.opacity(0.5),
                number: "House bills · — of —",
                detail: "each house bill carries its own CBP filing state",
                state: .pending)
    }

    /// Filing-state key. This is a LEGEND of the states the roster can carry —
    /// it is not data. The do-not-load state is drawn in the danger register so
    /// the operator reads it as a load-blocking condition before ever meeting
    /// one on a live bill.
    private var filingStateKey: some View {
        HStack(spacing: Space.s4) {
            keyChip("On file", Brand.success, "checkmark.seal.fill")
            keyChip("Amended", Color(hex: 0xFFC246), "pencil.circle.fill")
            keyChip("DNL hold", Brand.danger, "hand.raised.fill")
            Spacer(minLength: 0)
        }
    }

    private func keyChip(_ label: String, _ color: Color, _ icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func stateColor(_ s: AMSFilingState838) -> Color {
        switch s {
        case .onFile:  return Brand.success
        case .amended: return Color(hex: 0xFFC246)
        case .dnlHold: return Brand.danger
        case .pending: return palette.textTertiary
        }
    }

    // MARK: - Do-not-load sentinel (the danger state of this screen)

    private var dnlSentinel: some View {
        VesselGroupCard {
            HStack(alignment: .top, spacing: Space.s3) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Brand.danger).frame(width: 4, height: 42)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Brand.danger)
                        Text("DO-NOT-LOAD HOLDS")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(Brand.danger)
                        Spacer(minLength: 6)
                        Text("—")
                            .font(.system(size: 14, weight: .heavy, design: .monospaced))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Text("No container may be loaded against a bill CBP has not cleared. Holds surface here the moment the advance-manifest filing record responds.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - CTA pair (filing is ONLINE_ONLY — never queued)

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "File / amend AMS", action: { flagFilingGap() }, trailingIcon: "checkmark.seal")
            VesselGhostButton(title: "Hold review", width: 150) { flagHoldGap() }
        }
    }

    /// A customs transmission is a regulatory act and the procedure that would
    /// carry it does not exist. Say so plainly — an empty closure teaches the
    /// operator nothing and looks like a filing that silently worked.
    private func flagFilingGap() {
        actionNote = "Filing and amendment are unavailable because this voyage has no advance-manifest transmission record. Ask your customs filing administrator to connect the manifest service, then refresh. Regulatory filings require an online confirmation and are never queued."
    }

    private func flagHoldGap() {
        actionNote = "Do-not-load hold details are unavailable because no customs authority response is connected to this voyage. Refresh after the manifest response arrives. A hold cannot be released without an online authority confirmation."
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 176)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 150)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 90)
        }
    }

    // MARK: - Load (REAL: getVesselShipmentDetail)

    private func load() async {
        loading = true; loadError = nil
        guard shipmentId > 0 else { shipment = nil; loading = false; return }
        struct In: Encodable { let id: Int }
        do {
            let detail: ManifestDetail838? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: In(id: shipmentId))
            self.shipment = detail?.shipment
        } catch {
            // `shipment` is deliberately NOT cleared. A failed refresh keeps the
            // last decoded serve on screen, banner-labelled as not fresh, rather
            // than blanking a cutoff the operator is working to.
            loadError = error.eusoUserCopy
        }
        loading = false
    }
}

#Preview("838 · Vessel AMS 24-Hour Manifest · Night") {
    VesselAMSManifestScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("838 · Vessel AMS 24-Hour Manifest · Light") {
    VesselAMSManifestScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
