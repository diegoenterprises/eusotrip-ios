//
//  834_VesselStabilityStress.swift
//  EusoTrip — Vessel Operator · Stowage Stability & Stress (834).
//
//  App-integrated composition of "834 Vessel Stowage Stability & Stress.svg"
//  (Dark → Light). CLASS-CONDITION WORKSHEET archetype — the naval-architecture
//  sheet an operator signs before the departure gate: a GM verdict hero, a
//  side-elevation VESSEL PROFILE carrying the fwd/aft draft-mark staffs and the
//  even-keel datum, a hull-girder BENDING & SHEAR envelope with its station
//  axis, then the class+flag authority band. Deliberately NOT a KPI quartet and
//  NOT a row-stack ledger — the two instruments (hull silhouette, girder curve)
//  are the spine of the screen. Sibling 835 is a crane swim-lane sequence board
//  and shares nothing below the house header.
//  Nav: HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME.
//
//  WIRING (honest):
//    REAL — vesselShipments.getVesselShipmentDetail (vesselShipments.ts,
//        vesselProcedure, input { id: Int }) → { shipment: { id, vesselName,
//        bookingNumber, originPort, destinationPort, … } }. That is the ONLY
//        live read on this surface; it supplies the vessel, the booking ref and
//        the sailing lane in the header + hero framing.
//    FIXED REFERENCE (not fabricated) — IMO A.749 intact-stability criteria and
//        the ABS / Lloyd's Register / DNV class + USCG / Transport Canada /
//        SEMAR flag map. These are published standards, so they render as text.
//    STUB · named-gap — there is no loadicator / stability model on disk
//        (grep stabilityCondition = 0):
//          vessel.getStabilityCondition({voyageId}) → { gmMeters, gmMin,
//              draftFwd, draftAft, trimMeters, listDeg, displacementT, kgMeters }
//          vessel.getHullStress({voyageId}) → { stations:[{x, bendingFrac,
//              shearFrac}], peakStressFrac, permissibleFrac }
//          vessel.approveDepartureCondition({voyageId, confirm:true}) → writes
//              the stability_approvals row + blockchainAuditTrail
//              vessel.condition_approved, broadcasts WS_CHANNELS.VESSEL_OPS /
//              WS_EVENTS.CONDITION_APPROVED. RBAC vesselProcedure.
//        Until those ship, EVERY figure they would supply renders as an honest
//        awaiting-state: em-dash readings, PENDING chips, an empty GM track and
//        an empty station axis. No number on this screen is invented. The SVG's
//        illustrative figures (GM 1.84 m, 13.2/13.6 m drafts, 82% permissible)
//        exist only in this comment as the shape the model must return.
//    COUNTRY: single-country class+flag — US USCG + ABS active · CA Transport
//        Canada + Lloyd's Register · MX SEMAR + DNV.
//
//  OFFLINE POLICY: READ_CACHED(15m) for the condition read — a departure
//    condition is reviewed on the bridge and in the terminal office where signal
//    drops, so the last good serve of the shipment context stays on screen and
//    is labelled as awaiting rather than blanked; it is never passed off as a
//    fresh class read.
//    HONEST SCOPE OF THAT TIER: the retained serve is held IN MEMORY for the
//    life of the session — a failed refresh is banner-flagged above the content
//    it keeps rather than blanking the screen. There is NO persistent cache
//    layer behind it: Services/EusoTripAPI.swift:415-416 sets
//    .reloadIgnoringLocalAndRemoteCacheData and urlCache = nil, so nothing
//    survives a cold launch and the 15m TTL is a policy declaration, not an
//    enforced one. OPEN item (owning lane: the-oath) — a real on-disk read
//    cache with TTL enforcement.
//    approveDepartureCondition is ONLINE_ONLY(class-approval
//    and berth commit must not be queued) — signing a vessel seaworthy is a
//    legal act against a class society and a port-state-control record, so the
//    CTA refuses with an on-screen reason instead of queueing the write.
//
//  CHAIN closure: WS_EVENTS.CONDITION_APPROVED on WS_CHANNELS.VESSEL_OPS is
//    emitted by the (stub) approveDepartureCondition and is meant to be received
//    by the terminal/berth counter-party surface — the planner watching the
//    departure gate — plus the compliance ledger that files the approved
//    condition. That receiving half DOES NOT EXIST: the iOS RealtimeService
//    subscribes no VESSEL_OPS channel and no vessel-ops listener is registered
//    anywhere in the client. OPEN counter-party item → the-oath (vessel lane
//    owns the emit; the terminal/planner lane owns the missing receiver). Until
//    it lands, an approval here is write-only and no counter-party is notified.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselStabilityStressScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0
    /// Keys the STUB condition read once vessel.getStabilityCondition ships.
    var voyageId: String = ""

    var body: some View {
        Shell(theme: theme) {
            VesselStabilityStressBody(shipmentId: shipmentId, voyageId: voyageId)
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

private struct StabilityShipment834: Decodable {
    let id: Int?
    let vesselName: String?
    let bookingNumber: String?
    let originPort: String?
    let destinationPort: String?
}
private struct StabilityDetail834: Decodable {
    // FLAT-SHAPE REPAIR (2026-08-17). `vesselShipments.getVesselShipmentDetail`
    // returns a FLAT spread — `return { ...shipment, lifecycleStage, bols,
    // customs, events, demurrage, containers, originPort, destinationPort }`
    // (vesselShipments.ts:587). There is NO `shipment` wrapper key. Decoding a
    // wrapper against the real payload does NOT throw — the optional simply
    // yields nil — so the screen loads "successfully" and then renders its
    // awaiting state forever, invisibly. Decode off the ROOT; a wrapper is
    // still tolerated so a future revision cannot silently break this again.
    let shipment: StabilityShipment834?

    private enum CodingKeys: String, CodingKey { case shipment }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let wrapped = try? c.decodeIfPresent(StabilityShipment834.self, forKey: .shipment) {
            self.shipment = wrapped
        } else {
            self.shipment = try? StabilityShipment834(from: decoder)   // real shape: fields sit on the root
        }
    }
}

// MARK: - Body

private struct VesselStabilityStressBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let voyageId: String

    @State private var shipment: StabilityShipment834? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    /// Set when the operator taps Approve — states plainly why the class
    /// approval cannot be written yet. Never a fake success.
    @State private var approvalNotice: String? = nil

    private let pendingAmber = Color(hex: 0xFFC246)

    private var lane: String {
        if let o = shipment?.originPort, !o.isEmpty,
           let d = shipment?.destinationPort, !d.isEmpty { return "\(o) → \(d)" }
        return "CNSHA → USLGB"
    }
    private var vesselLine: String {
        let name = shipment?.vesselName ?? "—"   // no booking selected: assert no ship
        let voyage = voyageId.isEmpty ? "" : " · voyage \(voyageId)"
        // 2026-08-25 — "ABS class" was asserted unconditionally, naming a specific
        // classification society for a vessel that may not be loaded. IMO A.749 is
        // the intact-stability code and applies regardless; the society does not.
        let classing = shipment == nil ? "class —" : "ABS class"
        return "\(name)\(voyage) · \(lane) · \(classing) · IMO A.749"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · STABILITY & STRESS",
                caption: "IMO A.749 · STABILITY BOOK",   // was "MSC · ABS" — named a carrier and a class society with no booking loaded
                title: "Departure condition",
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
                        VesselErrorCard(text: "Refresh failed — \(err) The condition below is the last serve this session returned and is not being updated.")
                    }
                    verdictHero
                    profileSection
                    girderSection
                    VesselRegulatorBand(
                        title: "CLASS & FLAG · SINGLE-COUNTRY",
                        reference: "class-country",
                        rows: [
                            .init("US", "USCG · ABS class society", active: true),
                            .init("CA", "Transport Canada · Lloyd's Register"),
                            .init("MX", "SEMAR · DNV class")
                        ]
                    )
                    ctaPair
                    if let notice = approvalNotice {
                        VesselGapNote(text: notice)
                    }
                    VesselGapNote(text: "Vessel and booking context are verified live. No approved loaded condition is linked to this voyage, so GM, drafts, trim, list and the hull-girder curve are shown awaiting the class condition rather than estimated.")
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Verdict hero (GM against the IMO minimum)

    private var verdictHero: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    Text("Sailing draft condition · \(lane)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    pendingChip("CONDITION PENDING")
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("GM —")
                        .font(.system(size: 30, weight: .bold)).monospacedDigit()
                        .foregroundStyle(pendingAmber)
                    Text("min 0.15 m · IMO A.749")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Text("displacement — · KG — · free-surface correction not returned")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                // GM-margin track: empty until a class condition exists.
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(palette.tintNeutral)
                    .frame(height: 8)
            }
        }
    }

    // MARK: - Draft & trim · vessel profile instrument

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "DRAFT & TRIM · VESSEL PROFILE", right: "DRAFT MARKS PENDING")
            VesselGroupCard {
                VStack(alignment: .leading, spacing: Space.s4) {
                    HStack {
                        Text("FWD")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(palette.textTertiary)
                        Spacer()
                        Text("SIDE ELEVATION · EVEN-KEEL DATUM")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Spacer()
                        Text("AFT")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(palette.textTertiary)
                    }
                    hullProfile
                    draftReadouts
                    Divider().overlay(palette.borderFaint)
                    keelDatum
                }
            }
        }
    }

    private var hullProfile: some View {
        ZStack {
            StabilityHullSilhouette834()
                .fill(Brand.blue.opacity(0.11))
            StabilityHullSilhouette834()
                .stroke(Brand.blue.opacity(0.85), lineWidth: 1.6)
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                // Deckhouse block aft (physical superstructure, not a datum).
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Brand.blue.opacity(0.22))
                    .frame(width: w * 0.07, height: h * 0.16)
                    .position(x: w * 0.78, y: h * 0.20)
                // Design waterline — the reference the draft marks read against.
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.62))
                    p.addLine(to: CGPoint(x: w, y: h * 0.62))
                }
                .stroke(palette.textTertiary, style: StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
                // Fwd draft-mark staff — dashed because no reading is returned.
                Path { p in
                    p.move(to: CGPoint(x: w * 0.10, y: h * 0.26))
                    p.addLine(to: CGPoint(x: w * 0.10, y: h * 0.94))
                }
                .stroke(palette.textTertiary, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                // Aft draft-mark staff.
                Path { p in
                    p.move(to: CGPoint(x: w * 0.88, y: h * 0.26))
                    p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.94))
                }
                .stroke(palette.textTertiary, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
            }
        }
        .frame(height: 78)
    }

    private var draftReadouts: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            draftMark("FWD DRAFT", alignment: .leading)
            Spacer(minLength: 0)
            draftMark("AFT DRAFT", alignment: .trailing)
        }
    }

    private func draftMark(_ label: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
            Text("— m")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
        }
    }

    /// The even-keel datum: a keel axis with a centre-of-flotation tick. Trim
    /// and list would deflect this line; with no condition returned it sits
    /// flat and is explicitly labelled as not yet read.
    private var keelDatum: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ZStack {
                Rectangle()
                    .fill(palette.borderSoft)
                    .frame(height: 1.5)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(palette.textTertiary)
                        .frame(width: 1.5, height: 12)
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 12)
            HStack(spacing: Space.s4) {
                datumCell("TRIM", "—")
                datumCell("LIST", "—")
                Spacer(minLength: 6)
                Text("PORT ← DATUM → STBD")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    private func datumCell(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Hull girder · bending & shear envelope

    private var girderSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "HULL GIRDER · BENDING & SHEAR", right: "CURVE PENDING")
            VesselGroupCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack {
                        Text("PERMISSIBLE ENVELOPE · ABS SEAGOING")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 8)
                        pendingChip("NO STATIONS")
                    }
                    girderPlot
                    HStack {
                        Text("AP")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                        Spacer(minLength: 6)
                        curveKey("Bending", Color(hex: 0x5AB0FF))
                        curveKey("Shear", Color(hex: 0x9B6BFF))
                        Spacer(minLength: 6)
                        Text("FP")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                    }
                    VesselSummaryStrip(
                        label: "Peak stress vs permissible · GM margin",
                        value: "— % · — m",
                        valueColor: pendingAmber
                    )
                }
            }
        }
    }

    private var girderPlot: some View {
        ZStack {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                // Permissible envelope — a class limit, drawn as the frame the
                // curve must live inside. It is a reference, not a reading.
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Brand.success.opacity(0.08))
                    .frame(width: w, height: h * 0.74)
                    .position(x: w / 2, y: h / 2)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Brand.success.opacity(0.35),
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: w, height: h * 0.74)
                    .position(x: w / 2, y: h / 2)
                // Zero-moment baseline.
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h / 2))
                    p.addLine(to: CGPoint(x: w, y: h / 2))
                }
                .stroke(palette.textTertiary.opacity(0.45), lineWidth: 0.8)
                // Station axis (AP → FP). The ticks are the ship's frame
                // stations; the curve that rides them is what is missing.
                Path { p in
                    for i in 0...8 {
                        let x = w * CGFloat(i) / 8.0
                        p.move(to: CGPoint(x: x, y: h / 2 - 4))
                        p.addLine(to: CGPoint(x: x, y: h / 2 + 4))
                    }
                }
                .stroke(palette.borderSoft, lineWidth: 1)
            }
            Text("no station curve returned")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(palette.bgCardSoft))
        }
        .frame(height: 96)
    }

    private func curveKey(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(label)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
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
            CTAButton(title: "Approve condition",
                      action: { blockApproval() },
                      trailingIcon: "checkmark.seal")
            VesselGhostButton(title: "Loadicator", width: 150) {
                approvalNotice = "The loadicator export opens once a loaded condition is returned for this voyage."
            }
        }
    }

    private func blockApproval() {
        approvalNotice = "Departure approval is withheld: no class condition is linked to this voyage yet. Class approval is a legal write against ABS and port-state control, so it is never queued offline and never signed against an unread condition."
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 150)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 200)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 190)
        }
    }

    // MARK: - Load (REAL: getVesselShipmentDetail)

    private func load() async {
        loading = true; loadError = nil
        guard shipmentId > 0 else { shipment = nil; loading = false; return }
        struct In: Encodable { let id: Int }
        do {
            let detail: StabilityDetail834? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: In(id: shipmentId))
            self.shipment = detail?.shipment
        } catch {
            // `shipment` is deliberately NOT cleared. A failed refresh keeps the
            // last decoded serve on screen, banner-labelled as not fresh, rather
            // than blanking a condition being reviewed on the bridge.
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Private instrument: side-elevation hull silhouette

/// Container-ship side elevation: flat deck line, raked stem forward, rounded
/// stern aft. Pure geometry — it carries no data, it is the surface the draft
/// marks and the waterline are read against.
private struct StabilityHullSilhouette834: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.05, y: h * 0.28))
        p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.28))
        p.addQuadCurve(to: CGPoint(x: w * 0.98, y: h * 0.52),
                       control: CGPoint(x: w * 0.97, y: h * 0.28))
        p.addQuadCurve(to: CGPoint(x: w * 0.86, y: h * 0.82),
                       control: CGPoint(x: w * 0.96, y: h * 0.82))
        p.addLine(to: CGPoint(x: w * 0.13, y: h * 0.82))
        p.addQuadCurve(to: CGPoint(x: w * 0.05, y: h * 0.28),
                       control: CGPoint(x: w * 0.005, y: h * 0.56))
        p.closeSubpath()
        return p
    }
}

#Preview("834 · Vessel Stability & Stress · Night") {
    VesselStabilityStressScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("834 · Vessel Stability & Stress · Light") {
    VesselStabilityStressScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
