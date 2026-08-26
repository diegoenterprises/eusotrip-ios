//
//  840_VesselISPSSecurity.swift
//  EusoTrip — Vessel Operator · ISPS Security & Declaration of Security (840).
//
//  App-integrated composition of "840 Vessel ISPS Security & DoS.svg"
//  (Light + Dark). SECURITY-LEVEL ESCALATOR + BILATERAL DoS INSTRUMENT
//  archetype. The governing thing on this surface is not a number, it is a
//  LEVEL and an AGREEMENT: a three-rung MARSEC / ISPS escalator (L3 at the top
//  down to L1, each rung a physical step, the in-force pointer explicitly
//  unset), a Declaration of Security drawn as ONE instrument with TWO signatory
//  panes — ship security officer against facility security officer — carrying
//  its own period of validity, then the ship's CONTROLLED BOUNDARY (access
//  points and restricted areas) as the measure register the level drives.
//  Deliberately NOT 834's naval-architecture plots and NOT 838's
//  countdown-plus-roster: there is not one metric on this screen, because a
//  security posture is a declared state, not a measurement.
//  Nav: HOME · SHIPMENTS · [orb] · COMPLIANCE(current) · ME.
//
//  WIRING (honest) — the SVG <desc> names these procedures verbatim:
//    REAL — vesselShipments.getVesselShipmentDetail (vesselShipments.ts:162,
//        vesselProcedure, input { id: Int }) → { shipment: { id, vesselName,
//        bookingNumber, originPort, destinationPort, voyageNumber, … } }. This
//        is the ONLY live read on this surface; it supplies the port-call
//        context (vessel, booking reference, lane) in the header framing.
//    FIXED REFERENCE (real, not fabricated) — the ISPS Code and SOLAS XI-2
//        define security levels 1/2/3 and the circumstances in which a
//        Declaration of Security is completed; 33 CFR 104 (vessels) and 33 CFR
//        105 (facilities) carry them into US law. Those definitions render as
//        the governing standard exactly the way 833 states the CSS Code.
//    STUB · named-gap — there is no ISPS / MARSEC / DoS model on disk. From the
//        wireframe <desc>, verbatim:
//          "Security level + DoS checklist → vessel.getISPSStatus({callId})
//           [STUB · named-gap: no ISPS/MARSEC/DoS model on disk; reads the port
//           call + facility context off
//           vesselShipments.getVesselShipmentDetail:162]"
//          "Sign DoS → vessel.signDeclarationOfSecurity({callId,confirm:true})
//           and Raise level → vessel.setSecurityLevel({callId,level,confirm:true})
//           [STUB · SECURITY: gated + confirm:true + audit + test] write
//           isps_event row + blockchainAuditTrail vessel.isps_dos_signed,
//           broadcast WS_CHANNELS.VESSEL_OPS / WS_EVENTS.ISPS_UPDATED.
//           RBAC vesselProcedure (ship security officer)."
//        Until those ship, the in-force level, the DoS signatures, the officer
//        identities, the period of validity and every access-point /
//        restricted-area control state render as honest awaiting-states: an
//        unset pointer, unsigned panes, em-dash controls. A fabricated MARSEC
//        level or a fabricated signed DoS would be a safety-and-legal-class lie
//        and is never drawn. The SVG's illustrative figures (level 1, gangway
//        watch on, four of five measures DONE) live only in this comment as the
//        shape the model must return.
//    COUNTRY: single-country security regime — US USCG MARSEC · 33 CFR 104/105
//        active · CA Transport Canada MTSR · MX SEMAR-CUMAR (ISPS Code shared).
//
//  OFFLINE POLICY:
//    READ  · READ_CACHED(10m) — the port-call context may be served from the
//            10-minute cache; the last good serve stays on screen labelled as
//            awaiting and is never passed off as a fresh authority read.
//            HONEST SCOPE OF THAT TIER: what the code does today is retain the
//            last decoded serve IN MEMORY for the life of the session and
//            banner-flag a failed refresh above it instead of blanking the
//            screen. There is NO persistent cache layer behind it —
//            Services/EusoTripAPI.swift:415-416 sets
//            .reloadIgnoringLocalAndRemoteCacheData and urlCache = nil — so
//            nothing survives a cold launch and the 10m TTL is a policy
//            declaration, not an enforced one. OPEN item (owning lane:
//            the-oath): a real on-disk read cache with TTL enforcement.
//    WRITE · ONLINE_ONLY(security posture must reflect live authority state) —
//            signing a Declaration of Security or setting a security level is a
//            posture the port state and the facility own jointly. It may never
//            be queued for later replay: a queued security level is a level
//            nobody has actually declared. No connection, no signature, no
//            level change; the CTA refuses with an on-screen reason.
//
//  CHAIN CLOSURE:
//    Emit — WS_EVENTS.ISPS_UPDATED on WS_CHANNELS.VESSEL_OPS, raised by the
//    (stub) signDeclarationOfSecurity / setSecurityLevel writes.
//    Intended counter-party — the FACILITY security side (the PFSO console that
//    must see the ship's declared level and the countersigned DoS before cargo
//    ops begin) plus the compliance ledger that files the instrument.
//    Listener — NONE. RealtimeService carries ~48 event cases and no vessel:*
//    case; Views/Vessel holds ZERO realtime subscribers (its only
//    RealtimeService mentions are header comments like this one), and
//    Views/Dispatch holds a single one — thin for that lane, but the client as a
//    whole is not: Views/Shipper alone references RealtimeService across ~23
//    files, with further use in Driver, Catalyst, Escort, Rail and Carrier. The
//    gap is vessel-specific, not app-wide. Nothing on iOS would hear ISPS_UPDATED
//    today. OPEN counter-party item → the-oath: the vessel lane owns the emit,
//    the facility/compliance console lane owns the missing receiver. Until it
//    lands, a signature here is write-only and no counter-party is notified.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselISPSSecurityScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0
    /// Keys the STUB posture read once vessel.getISPSStatus({callId}) ships.
    var callId: String = ""

    var body: some View {
        Shell(theme: theme) {
            VesselISPSSecurityBody(shipmentId: shipmentId, callId: callId)
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

// MARK: - Shipment shape (getVesselShipmentDetail · the one REAL read)

private struct ISPSShipment840: Decodable {
    let id: Int?
    let vesselName: String?
    let bookingNumber: String?
    let originPort: String?
    let destinationPort: String?
    let voyageNumber: String?
}
private struct ISPSDetail840: Decodable {
    // FLAT-SHAPE REPAIR (2026-08-17). `vesselShipments.getVesselShipmentDetail`
    // returns a FLAT spread — `return { ...shipment, lifecycleStage, bols,
    // customs, events, demurrage, containers, originPort, destinationPort }`
    // (vesselShipments.ts:587). There is NO `shipment` wrapper key. Decoding a
    // wrapper against the real payload does NOT throw — the optional simply
    // yields nil — so the screen loads "successfully" and then renders its
    // awaiting state forever, invisibly. Decode off the ROOT; a wrapper is
    // still tolerated so a future revision cannot silently break this again.
    let shipment: ISPSShipment840?

    private enum CodingKeys: String, CodingKey { case shipment }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let wrapped = try? c.decodeIfPresent(ISPSShipment840.self, forKey: .shipment) {
            self.shipment = wrapped
        } else {
            self.shipment = try? ISPSShipment840(from: decoder)   // real shape: fields sit on the root
        }
    }
}

// MARK: - The escalator rungs (ISPS Code definitions · fixed reference)

/// One rung of the security-level escalator. `title` and `regime` are the ISPS
/// Code's own definitions of levels 1–3 — published standard text, not data.
/// Nothing on a rung says whether that level is the one in force; that is the
/// STUB's job and it is drawn unset until the STUB answers.
private struct MARSECRung840: Identifiable {
    let id = UUID()
    let level: Int
    let title: String
    let regime: String
}

// MARK: - Body

private struct VesselISPSSecurityBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let callId: String

    @State private var shipment: ISPSShipment840? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    /// Set when the officer taps a security action — states plainly why the
    /// write is refused. Never a fake success, never a queued security posture.
    @State private var actionNotice: String? = nil

    private let pendingAmber = Color(hex: 0xFFC246)

    /// The three ISPS security levels, escalating upward: rung 3 sits at the
    /// top of the ladder. The definitions are SOLAS XI-2 / ISPS Code text.
    private let rungs: [MARSECRung840] = [
        MARSECRung840(level: 3,
                      title: "Exceptional",
                      regime: "further specific measures · incident probable or imminent"),
        MARSECRung840(level: 2,
                      title: "Heightened",
                      regime: "additional measures · period of heightened risk"),
        MARSECRung840(level: 1,
                      title: "Normal",
                      regime: "minimum measures maintained at all times")
    ]

    /// Boundary crossings the Ship Security Plan controls. These are physical
    /// features of the ship, not readings — their CONTROL STATE is what the
    /// STUB supplies, and it is shown em-dash throughout.
    private let accessPoints = ["Accommodation ladder / gangway",
                                "Pilot boarding ladder",
                                "Bunker & stores station",
                                "Mooring stations fwd / aft"]

    /// Restricted areas under ISPS Part A/7 and 33 CFR 104.285.
    private let restrictedAreas = ["Navigation bridge",
                                   "Engine control room",
                                   "Steering gear compartment",
                                   "Cargo control room"]

    private var lane: String {
        if let o = shipment?.originPort, !o.isEmpty,
           let d = shipment?.destinationPort, !d.isEmpty { return "\(o) → \(d)" }
        return "POLB"
    }

    private var portCallLine: String {
        let name = shipment?.vesselName ?? "—"   // no booking selected: assert no ship
        let voy = shipment?.voyageNumber.map { " · voy \($0)" } ?? ""
        return "\(name)\(voy) · \(lane) · ISPS Code · SOLAS XI-2"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · ISPS SECURITY & DoS",
                caption: "SOLAS XI-2 · DoS",   // was "MSC · USCG" — named a carrier, and asserted US jurisdiction on a tri-country surface
                title: "Security level",
                idText: shipment?.bookingNumber,
                subtitle: portCallLine
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
                        VesselErrorCard(text: "Refresh failed — \(err) The posture below is the last serve this session returned and is not being updated.")
                    }
                    levelEscalator
                    dosInstrument
                    boundaryRegister
                    VesselSummaryStrip(label: "Level in force · Declaration of Security",
                                       value: "— · NOT SIGNED",
                                       valueColor: pendingAmber)
                    VesselRegulatorBand(
                        title: "MARITIME SECURITY REGIME · SINGLE-COUNTRY",
                        reference: "port-country",
                        rows: [
                            .init("US", "USCG MARSEC · 33 CFR 104/105", active: true),
                            .init("CA", "Transport Canada · MTSR"),
                            .init("MX", "SEMAR-CUMAR · ISPS Code")
                        ]
                    )
                    ctaPair
                    if let notice = actionNotice {
                        VesselGapNote(text: notice)
                    }
                    VesselGapNote(text: "Port-call context is verified live and the ISPS Code governs this surface. No security-posture record is linked to this call, so the level in force, both Declaration of Security signatures and every access-point and restricted-area control are shown awaiting the authority state rather than assumed.")
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Hero · the security-level escalator (a step register, not a dial)

    private var levelEscalator: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    Text("MARSEC posture · set by the Contracting Government")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    pendingChip("LEVEL NOT RETURNED")
                }
                VStack(spacing: 0) {
                    ForEach(rungs) { rung in
                        rungRow(rung)
                        if rung.level > 1 { Divider().overlay(palette.borderFaint) }
                    }
                }
                Divider().overlay(palette.borderFaint)
                inForceLine
            }
        }
    }

    private func rungRow(_ rung: MARSECRung840) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            // The step: its height IS the level. Pure geometry — a taller step
            // for a higher level. It carries no reading of its own.
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(palette.tintNeutral)
                    .frame(width: 20, height: 38)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(rungTint(rung.level).opacity(0.5))
                    .frame(width: 20, height: CGFloat(rung.level) * 11 + 5)
            }
            .frame(width: 20, height: 38)
            Text("L\(rung.level)")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundStyle(rungTint(rung.level))
                .frame(width: 24, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(rung.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(rung.regime)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 6)
            unsetPointer
        }
        .padding(.vertical, Space.s3)
    }

    /// The in-force pointer slot. Every rung carries one and none of them is
    /// lit — the pointer only takes a rung when getISPSStatus returns a level.
    private var unsetPointer: some View {
        Text("—")
            .font(.system(size: 11, weight: .heavy, design: .monospaced))
            .foregroundStyle(palette.textTertiary)
            .frame(width: 44, height: 20)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(palette.borderSoft,
                                  style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            )
    }

    private var inForceLine: some View {
        HStack(spacing: Space.s2) {
            Text("IN FORCE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text("—")
                .font(.system(size: 15, weight: .heavy, design: .monospaced))
                .foregroundStyle(pendingAmber)
            Spacer(minLength: 6)
            Text("declared by the COTP / facility · no record linked")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private func rungTint(_ level: Int) -> Color {
        switch level {
        case 3:  return Brand.danger
        case 2:  return pendingAmber
        default: return Brand.success
        }
    }

    // MARK: - Declaration of Security · one instrument, two signatories

    private var dosInstrument: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "DECLARATION OF SECURITY · SHIP ↔ FACILITY",
                                right: "NOT ON FILE")
            VesselGroupCard {
                VStack(alignment: .leading, spacing: Space.s4) {
                    HStack(alignment: .top) {
                        Text("One instrument · agreed by both parties for a stated period")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.65)
                        Spacer(minLength: 8)
                        pendingChip("UNSIGNED")
                    }
                    HStack(alignment: .top, spacing: Space.s3) {
                        signatoryPane(side: "SHIP", role: "Ship Security Officer")
                        signatoryPane(side: "PORT FACILITY", role: "Facility Security Officer")
                    }
                    Divider().overlay(palette.borderFaint)
                    validityBlock
                    Text("A Declaration of Security is completed when the ship operates at a higher security level than the facility, at level 3, or where a Contracting Government requires it (SOLAS XI-2/10 · ISPS Code A/5).")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func signatoryPane(side: String, role: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(side)
                .font(.system(size: 8.5, weight: .heavy)).tracking(0.6)
                .foregroundStyle(Brand.blue)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(role)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text("—")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
            // Signature rule: dashed because nothing has been executed on it.
            ISPSSignatureRule840()
                .stroke(palette.borderSoft, style: StrokeStyle(lineWidth: 1.3, dash: [4, 3]))
                .frame(height: 10)
            Text("signature · date —")
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private var validityBlock: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            validityRow("VALID FROM", "—")
            validityRow("VALID UNTIL", "—")
            validityRow("ACTIVITIES COVERED", "—")
        }
    }

    private func validityRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: Space.s3) {
            Text(label)
                .font(.system(size: 8.5, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 128, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Controlled boundary · access points + restricted areas

    private var boundaryRegister: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "CONTROLLED BOUNDARY · ACCESS & RESTRICTED",
                                right: "MEASURES NOT RETURNED")
            VesselGroupCard(padded: false) {
                VStack(spacing: 0) {
                    bandLabel("ACCESS POINTS · boundary crossings")
                    ForEach(Array(accessPoints.enumerated()), id: \.offset) { idx, name in
                        if idx > 0 { Divider().overlay(palette.borderFaint).padding(.leading, Space.s4) }
                        boundaryRow(name, restricted: false)
                    }
                    bandLabel("RESTRICTED AREAS · controlled spaces")
                    ForEach(Array(restrictedAreas.enumerated()), id: \.offset) { idx, name in
                        if idx > 0 { Divider().overlay(palette.borderFaint).padding(.leading, Space.s4) }
                        boundaryRow(name, restricted: true)
                    }
                }
            }
            Text("The measure set in force is issued with the security level under the Ship Security Plan (33 CFR 104.265). No level, no measure set — so no access point is shown as manned and no space is shown as sealed.")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bandLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 8.5, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
    }

    private func boundaryRow(_ name: String, restricted: Bool) -> some View {
        HStack(spacing: Space.s3) {
            if restricted { restrictedGlyph } else { gateGlyph }
            Text(name)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.65)
            Spacer(minLength: 6)
            Text("control —")
                .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
            Circle()
                .strokeBorder(palette.textTertiary.opacity(0.6), lineWidth: 1.8)
                .frame(width: 14, height: 14)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    /// A boundary crossing: two posts with the gap between them.
    private var gateGlyph: some View {
        HStack(spacing: 6) {
            Rectangle().fill(Brand.blue.opacity(0.75)).frame(width: 2, height: 13)
            Rectangle().fill(Brand.blue.opacity(0.75)).frame(width: 2, height: 13)
        }
        .frame(width: 18, height: 14)
    }

    /// A controlled space: a closed enclosure with its barred entry.
    private var restrictedGlyph: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .strokeBorder(palette.textTertiary.opacity(0.8), lineWidth: 1.4)
            .frame(width: 15, height: 13)
            .overlay(Rectangle().fill(palette.textTertiary.opacity(0.8)).frame(width: 9, height: 1.4))
            .frame(width: 18, height: 14)
    }

    // MARK: - Chrome

    private func pendingChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
            .foregroundStyle(pendingAmber)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(pendingAmber.opacity(0.13)))
    }

    // MARK: - CTA pair (both writes are ONLINE_ONLY and both are refused here)

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Sign DoS",
                      action: { blockSignature() },
                      trailingIcon: "checkmark.seal")
            VesselGhostButton(title: "Raise level", width: 150) { blockLevelChange() }
        }
    }

    private func blockSignature() {
        actionNotice = "The Declaration of Security is not signed here: no security-posture record is linked to this port call, and a DoS binds two parties — the ship and the facility. It is never queued offline, because a queued declaration is one no facility has actually agreed to."
    }

    private func blockLevelChange() {
        actionNotice = "The security level is not raised here: the level in force is declared by the Contracting Government and the port facility, and none has been read for this call. A level change is never queued offline — the posture on screen must match the live authority state."
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 210)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 190)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 160)
        }
    }

    // MARK: - Load (REAL: getVesselShipmentDetail)

    private func load() async {
        loading = true; loadError = nil
        guard shipmentId > 0 else { shipment = nil; loading = false; return }
        struct In: Encodable { let id: Int }
        do {
            let detail: ISPSDetail840? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: In(id: shipmentId))
            self.shipment = detail?.shipment
        } catch {
            // `shipment` is deliberately NOT cleared. A failed refresh keeps the
            // last decoded serve on screen, banner-labelled as not fresh, rather
            // than blanking a security posture at the gangway.
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Private instrument: an unexecuted signature rule

/// A horizontal rule across the middle of its frame — the line a signatory
/// would sign on. Drawn dashed by its caller while the instrument is unsigned.
private struct ISPSSignatureRule840: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return p
    }
}

#Preview("840 · Vessel ISPS Security & DoS · Night") {
    VesselISPSSecurityScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("840 · Vessel ISPS Security & DoS · Light") {
    VesselISPSSecurityScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
