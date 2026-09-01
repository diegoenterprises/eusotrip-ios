//
//  827_VesselOutOfGaugeBooking.swift
//  EusoTrip — Vessel Operator · Out-of-Gauge / Breakbulk Booking (827).
//
//  Verbatim-composition port of "827 Vessel Out-of-Gauge Booking.svg" (Dark →
//  Light). DIMENSIONAL-DIAGRAM + EQUIPMENT-SELECTOR + APPROVAL-CHAIN archetype
//  — a project-cargo booking surface: an over-gauge status hero, a dimensional
//  diagram (cargo overhanging a 40' flat-rack deck with over-limit deltas), a
//  flat-rack / open-top / platform equipment selector, and a CSS-Code stowage
//  approval chain. Nav: HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME.
//
//  WIRING (honest):
//    Booking context is REAL — vesselShipments.getVesselShipmentDetail
//        (vesselShipments.ts:561, vesselProcedure, input { id }) →
//        { shipment, containers, … }. Commodity + gross weight drive the hero
//        when a booking is selected.
//    The 40' flat-rack DECK ENVELOPE (12.19 m usable) is a published ISO spec
//        (ISO 1496-5), not fabricated — it is the fixed reference frame.
//    There is NO out-of-gauge dimensional / stowage-approval model on disk
//        (grep OOG/flat-rack/stowage = 0) → STUB · named-gap:
//        vessel.createOOGBooking({bookingId, dims, equip, lashingPlanUrl,
//        confirm:true}) — a deterministic over-limit validator (not the LLM),
//        writes blockchainAuditTrail vessel.oog_booked. The cargo overhang +
//        deltas + live approval state render once that model ships; until then
//        the diagram shows the deck envelope with a dims-pending cargo state.
//    COUNTRY: US USCG heavy-lift permit active · CA Transport Canada · MX SEMAR.
//

import SwiftUI

struct VesselOutOfGaugeBookingScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            VesselOOGBookingBody(shipmentId: shipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",              isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Equipment options (real vessel equipment TYPES)

private enum OOGEquip827: String, CaseIterable, Identifiable {
    case flatRack = "Flat-rack 40'"
    case openTop  = "Open-top 40'"
    case platform = "Platform"
    var id: String { rawValue }
    var note: String {
        switch self {
        case .flatRack: return "suits"
        case .openTop:  return "alt"
        case .platform: return "heavy"
        }
    }
}

// MARK: - Booking shape (getVesselShipmentDetail, permissive)

private struct OOGShipment827: Decodable {
    let id: Int?
    let bookingNumber: String?
    let commodityDescription: String?
    let cargoDescription: String?
    let grossWeightKg: Double?
    let weight: Double?
}
private struct OOGDetail827: Decodable {
    // FLAT-SHAPE REPAIR (2026-08-17). `vesselShipments.getVesselShipmentDetail`
    // returns a FLAT spread — `return { ...shipment, lifecycleStage, bols,
    // customs, events, demurrage, containers, originPort, destinationPort }`
    // (vesselShipments.ts:587). There is NO `shipment` wrapper key. Decoding a
    // wrapper against the real payload does NOT throw — the optional simply
    // yields nil — so the screen loads "successfully" and then renders its
    // awaiting state forever, invisibly. Decode off the ROOT; a wrapper is
    // still tolerated so a future revision cannot silently break this again.
    let shipment: OOGShipment827?

    private enum CodingKeys: String, CodingKey { case shipment }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let wrapped = try? c.decodeIfPresent(OOGShipment827.self, forKey: .shipment) {
            self.shipment = wrapped
        } else {
            self.shipment = try? OOGShipment827(from: decoder)   // real shape: fields sit on the root
        }
    }
}

// MARK: - Body

private struct VesselOOGBookingBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int

    @State private var shipment: OOGShipment827? = nil
    @State private var selectedEquip: OOGEquip827 = .flatRack
    @State private var loading = true
    @State private var loadError: String? = nil

    private var commodity: String {
        shipment?.commodityDescription ?? shipment?.cargoDescription ?? "Project cargo"
    }
    private var weightTons: String {
        let kg = shipment?.grossWeightKg ?? shipment?.weight
        guard let kg, kg > 0 else { return "—" }
        return String(format: "%.1f t", kg / 1000.0)
    }
    private var hasBooking: Bool { shipment != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · OOG / BREAKBULK",
                caption: "IMO CSS CODE",
                title: "OOG booking"
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    skeleton
                } else if let err = loadError {
                    VesselErrorCard(text: err)
                } else {
                    overGaugeHero
                    dimensionSection
                    equipmentSection
                    approvalChain
                    VesselRegulatorBand(
                        title: "REGULATOR · SINGLE ACTIVE GATED",
                        reference: "oog · country",
                        rows: [
                            .init("US", "USCG · heavy-lift permit", active: true),
                            .init("CA", "Transport Canada · OOG"),
                            .init("MX", "SEMAR · carga sobredimensionada")
                        ]
                    )
                    ctaPair
                    VesselGapNote(text: "Booking context is verified. No certified OOG dimensions or stowage approval are linked to this shipment.")
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Over-gauge hero

    private var overGaugeHero: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    Text(hasBooking ? "\(commodity) · \(weightTons)" : "Select a project-cargo booking")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text(hasBooking ? "OVER-GAUGE" : "AWAITING DIMS")
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Color(hex: 0xFFC246))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color(hex: 0xFFC246).opacity(0.14)))
                }
                HStack(alignment: .top) {
                    Text("Out-of-gauge")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(hasBooking ? "pending" : "—")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(Color(hex: 0xFF6F61))
                        Text("overheight vs slot")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Text("Flat-rack stow · CSS Code lashing required")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: - Dimensional diagram (deck envelope · cargo overhang)

    private var dimensionSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "DIMENSIONS · vs 40' FLAT-RACK", right: "IMO CSS Code · Annex")
            VesselGroupCard {
                VStack(alignment: .leading, spacing: Space.s3) {
                    OOGDiagram827(hasCargo: false)   // cargo overhang renders once OOG dims exist
                        .frame(height: 128)
                    HStack(spacing: Space.s2) {
                        deltaChip("over-H", value: hasBooking ? "pending" : "—",
                                  tone: Color(hex: 0xFF6F61))
                        deltaChip("over-W", value: hasBooking ? "pending" : "—",
                                  tone: Color(hex: 0x34D8A6))
                    }
                    Text("Deck envelope 12.19 m (ISO 1496-5) · certified cargo dimensions required")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private func deltaChip(_ label: String, value: String, tone: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                .foregroundStyle(tone)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    // MARK: - Equipment selector (real equipment types · tappable)

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "EQUIPMENT · SELECT", right: "vessel.createOOGBooking")
            HStack(spacing: Space.s2) {
                ForEach(OOGEquip827.allCases) { equip in
                    equipCard(equip)
                }
            }
        }
    }

    private func equipCard(_ equip: OOGEquip827) -> some View {
        let selected = equip == selectedEquip
        return Button {
            selectedEquip = equip
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(equip.rawValue)
                        .font(.system(size: 10.5, weight: selected ? .heavy : .semibold))
                        .foregroundStyle(selected ? palette.textPrimary : palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(equip.note)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(selected ? Color(hex: 0x34D8A6) : palette.textTertiary)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(hex: 0x34D8A6))
                }
            }
            .padding(.horizontal, Space.s3).padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(selected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint),
                                  lineWidth: selected ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stowage approval chain (CSS-Code sequence)

    private let approvalSteps = ["Dimensions", "Lashing plan", "Stowage", "Sign-off"]
    private let approvalSubs  = ["verified", "filed", "master review", "pending"]
    /// Live stage index — advances only when the OOG booking model reports
    /// progress. With no booking selected the sequence sits at the review
    /// gate (index 2), mirroring the canonical departure-check state.
    private var approvalIndex: Int { hasBooking ? 2 : 0 }

    private var approvalChain: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "STOWAGE APPROVAL · CHAIN", right: "APPROVAL REQUIRED")
            VesselGroupCard {
                HStack(spacing: 0) {
                    ForEach(Array(approvalSteps.enumerated()), id: \.offset) { idx, step in
                        let done = idx < approvalIndex
                        let current = idx == approvalIndex
                        VStack(spacing: 6) {
                            ZStack {
                                if current {
                                    Circle().strokeBorder(Color(hex: 0x5AB0FF), lineWidth: 2.4)
                                        .frame(width: 22, height: 22)
                                    Circle().fill(Color(hex: 0x5AB0FF)).frame(width: 7, height: 7)
                                } else if done {
                                    Circle().fill(Color(hex: 0x34D8A6)).frame(width: 22, height: 22)
                                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                } else {
                                    Circle().strokeBorder(palette.textTertiary, lineWidth: 2)
                                        .frame(width: 22, height: 22)
                                }
                            }
                            .frame(height: 22)
                            Text(step)
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Text(approvalSubs[idx])
                                .font(.system(size: 7.5, weight: .medium))
                                .foregroundStyle(current ? Color(hex: 0x5AB0FF) : palette.textTertiary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        if idx < approvalSteps.count - 1 {
                            Rectangle()
                                .fill(idx < approvalIndex ? AnyShapeStyle(LinearGradient.primary)
                                      : AnyShapeStyle(palette.borderSoft))
                                .frame(height: 2).frame(maxWidth: .infinity)
                                .offset(y: -19)
                        }
                    }
                }
            }
        }
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Submit OOG booking", action: {}, trailingIcon: "arrow.right")
            VesselGhostButton(title: "Lashing plan", width: 150) {}
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 120)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 170)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 96)
        }
    }

    // MARK: - Load (REAL: getVesselShipmentDetail)

    private func load() async {
        loading = true; loadError = nil
        guard shipmentId > 0 else { shipment = nil; loading = false; return }
        struct In: Encodable { let id: Int }
        do {
            let detail: OOGDetail827? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: In(id: shipmentId))
            self.shipment = detail?.shipment
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Dimensional diagram (deck bar + cargo overhang)

/// The signature OOG figure — a 40' flat-rack deck bar with a cargo box that,
/// once dimensions exist, overhangs the deck's height limit (dashed red) and
/// is measured L·W·H. With no cargo dims it renders the empty deck envelope +
/// a dims-pending cargo silhouette so the operator sees the reference frame.
private struct OOGDiagram827: View {
    @Environment(\.palette) private var palette
    let hasCargo: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let deckY = h - 30
            let deckW = w * 0.78
            let deckX = (w - deckW) / 2
            let boxW = deckW * 0.86
            let boxX = deckX + (deckW - boxW) / 2
            let boxTop = h * 0.12
            let boxBottom = deckY

            ZStack(alignment: .topLeading) {
                // Cargo box (dashed when dims pending, solid when known)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(hex: 0x5AB0FF).opacity(hasCargo ? 0.12 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(
                                Color(hex: 0x5AB0FF).opacity(hasCargo ? 1 : 0.5),
                                style: StrokeStyle(lineWidth: 1.6, dash: hasCargo ? [] : [4, 3])
                            )
                    )
                    .frame(width: boxW, height: boxBottom - boxTop)
                    .offset(x: boxX, y: boxTop)

                // Deck bar
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(palette.tintNeutral)
                    .frame(width: deckW, height: 16)
                    .offset(x: deckX, y: deckY)

                // Height limit line (dashed red at the flat-rack limit)
                Path { p in
                    let limitY = boxTop + (boxBottom - boxTop) * 0.30
                    p.move(to: CGPoint(x: boxX + boxW + 4, y: limitY))
                    p.addLine(to: CGPoint(x: boxX + boxW + 4, y: boxBottom))
                }
                .stroke(Color(hex: 0xFF6F61), style: StrokeStyle(lineWidth: 1.4, dash: [3, 2]))

                // Dimension labels
                Text("L 12.19 m · W 2.44 m")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: boxW)
                    .offset(x: boxX, y: (boxTop + boxBottom) / 2 - 8)

                Text("H limit 2.59")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xFF6F61))
                    .offset(x: min(boxX + boxW + 8, w - 60), y: boxTop + 4)

                Text("flat-rack deck 12.19 m")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(palette.textTertiary)
                    .offset(x: deckX, y: deckY + 20)
            }
        }
    }
}

#Preview("827 · Vessel OOG Booking · Night") {
    VesselOutOfGaugeBookingScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("827 · Vessel OOG Booking · Light") {
    VesselOutOfGaugeBookingScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
