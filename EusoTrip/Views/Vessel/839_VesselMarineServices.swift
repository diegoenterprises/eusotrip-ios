//
//  839_VesselMarineServices.swift
//  EusoTrip — Vessel Operator · Pilotage & Marine Services (839).
//
//  Verbatim-composition port of "839 Vessel Pilotage & Marine Services.svg"
//  (Dark → Light). HOUR-GUTTER APPROACH-TIMELINE archetype — a scheduling
//  instrument, not a list: a pilot-boarding hero with the berth made-fast time,
//  then a 05:00–09:00 HOUR GUTTER against which each marine service (Pilot,
//  Tugs, Linesmen, Berthing) is drawn as a positioned window block, then the
//  pilotage-authority band. The hour gutter is a deliberately rare device —
//  used exactly once elsewhere platform-wide (Shipper 295) — and is built here
//  as a true positioned track, never degraded into rows.
//  Nav: HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME.
//
//  WIRING (honest):
//    Port-call context is REAL — vesselShipments.getVesselShipmentDetail
//        (vesselShipments.ts, vesselProcedure, input { id: Int }) →
//        { shipment: { id, vesselName, bookingNumber, … } }. The vessel and its
//        inbound booking drive the header and the hero framing.
//    The pilotage AUTHORITY is the real fixed reference, not fabricated:
//        US Jacobsen Pilot Svc under USCG COTP / CA Pacific Pilotage Authority
//        under Transport Canada / MX Pilotos del Pacífico under SEMAR. Boarding
//        ground PB-1 is the port's fixed pilot station.
//    There is NO port-services / pilotage model on disk (service windows,
//        assigned tugs, linesmen gang, bollard pull, order status; grep
//        pilotage/tug/linesmen = 0 dedicated surfaces) → STUB · named-gap:
//        vessel.getMarineServices({callId}) +
//        vessel.confirmMarineServices({callId,confirm:true}) [gated +
//        confirm:true + audit + test] → writes the port_service_order row +
//        blockchainAuditTrail vessel.services_confirmed, broadcasts
//        WS_CHANNELS.VESSEL_OPS / WS_EVENTS.SERVICES_CONFIRMED. Boarding time,
//        made-fast time, every service window and every assigned provider come
//        from that model. Until it ships the gutter draws EMPTY tracks with
//        em-dash windows — no tug is named and no time is drawn that no one has
//        actually booked.
//    COUNTRY: US Jacobsen / USCG COTP active · CA PPA / TC · MX Pilotos / SEMAR.
//
//  OFFLINE POLICY:
//    READ  · READ_CACHED(15m) — port-call context may be served from the
//            15-minute cache; the approach window is re-read on pull.
//            HONEST SCOPE OF THAT TIER: what the code does today is retain the
//            last decoded serve IN MEMORY for the life of the session and
//            banner-flag a failed refresh above it instead of blanking the
//            screen. There is NO persistent cache layer behind it —
//            Services/EusoTripAPI.swift:415-416 sets
//            .reloadIgnoringLocalAndRemoteCacheData and urlCache = nil — so
//            nothing survives a cold launch and the 15m TTL is a policy
//            declaration, not an enforced one. OPEN item (owning lane:
//            the-oath): a real on-disk read cache with TTL enforcement.
//    WRITE · ONLINE_ONLY(berth/tug commit binds a third-party provider) —
//            Confirm services orders pilot, tugs, linesmen and the berth from
//            outside parties and incurs their tariffs; it may never be queued
//            for later replay.
//
//  CHAIN CLOSURE:
//    Emit WS_EVENTS.SERVICES_CONFIRMED on WS_CHANNELS.VESSEL_OPS is meant to
//    land on the port-call and berth-window screens, which plan against the
//    same approach slot.
//    OPEN counter-party item (the-oath): that half does NOT exist. No screen in
//    Views/ subscribes to a vessel-ops event — RealtimeService carries no
//    vessel:* case, and Views/Dispatch has a single realtime subscriber in
//    total (the known systemic subscriber fault). Port Calls and Berth Window
//    would not learn of a confirmation until their own next read. Owning lanes:
//    the Vessel port-call lane (receiver) and the Dispatch lane (realtime).
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselMarineServicesScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0
    var callId: String = "POLB-J266"

    var body: some View {
        Shell(theme: theme) {
            VesselMarineServicesBody(shipmentId: shipmentId, callId: callId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Shipment shape (getVesselShipmentDetail)

private struct ServicesShipment839: Decodable {
    let id: Int?
    let vesselName: String?
    let bookingNumber: String?
    let voyageNumber: String?
    let eta: String?
}
private struct ServicesDetail839: Decodable {
    // FLAT-SHAPE REPAIR (2026-08-17). `vesselShipments.getVesselShipmentDetail`
    // returns a FLAT spread — `return { ...shipment, lifecycleStage, bols,
    // customs, events, demurrage, containers, originPort, destinationPort }`
    // (vesselShipments.ts:587). There is NO `shipment` wrapper key. Decoding a
    // wrapper against the real payload does NOT throw — the optional simply
    // yields nil — so the screen loads "successfully" and then renders its
    // awaiting state forever, invisibly. Decode off the ROOT; a wrapper is
    // still tolerated so a future revision cannot silently break this again.
    let shipment: ServicesShipment839?

    private enum CodingKeys: String, CodingKey { case shipment }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let wrapped = try? c.decodeIfPresent(ServicesShipment839.self, forKey: .shipment) {
            self.shipment = wrapped
        } else {
            self.shipment = try? ServicesShipment839(from: decoder)   // real shape: fields sit on the root
        }
    }
}

// MARK: - Approach-lane model

private enum ApproachState839 {
    case confirmed, ordered, pending
}

/// One marine service lane on the approach timeline. The service KIND is the
/// fixed structure of an inbound port call; `startHour` / `endHour` (decimal
/// hours on the gutter axis) and `provider` come from getMarineServices and
/// stay nil until that record exists.
private struct ApproachLane839: Identifiable {
    let id = UUID()
    let name: String
    let note: String
    let provider: String?
    let startHour: Double?
    let endHour: Double?
    let state: ApproachState839
}

// MARK: - The hour gutter (private to 839)

/// A true positioned time gutter: a shared hour axis across the top, vertical
/// hour rules running the full height of the track column, and one lane per
/// service whose window block is POSITIONED against the axis. When a lane has
/// no window the track renders empty and captioned — the instrument stays
/// honest without collapsing into a roster.
private struct ApproachHourGutter839: View {
    @Environment(\.palette) private var palette
    let hours: [Int]
    let lanes: [ApproachLane839]

    private let labelWidth: CGFloat = 104
    private let laneHeight: CGFloat = 40

    private func fraction(_ hour: Double) -> CGFloat {
        guard let first = hours.first, let last = hours.last, last > first else { return 0 }
        let span = CGFloat(last - first)
        return min(max((CGFloat(hour) - CGFloat(first)) / span, 0), 1)
    }

    private func hm(_ hour: Double) -> String {
        let h = Int(hour)
        let m = Int((hour - Double(h)) * 60.0 + 0.5)
        return String(format: "%02d:%02d", h, m)
    }

    private func tone(_ state: ApproachState839) -> Color {
        switch state {
        case .confirmed: return Color(hex: 0x5AB0FF)
        case .ordered:   return Color(hex: 0xFFC246)
        case .pending:   return palette.textTertiary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            axisHeader
            ForEach(Array(lanes.enumerated()), id: \.element.id) { idx, lane in
                if idx > 0 { Divider().overlay(palette.borderFaint) }
                laneRow(lane)
            }
        }
    }

    // Shared hour axis — the gutter's ruler.
    private var axisHeader: some View {
        HStack(alignment: .bottom, spacing: Space.s3) {
            Color.clear.frame(width: labelWidth, height: 1)
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    ForEach(Array(hours.enumerated()), id: \.offset) { _, hour in
                        let x = fraction(Double(hour)) * geo.size.width
                        Text(String(format: "%02d:00", hour))
                            .font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(0.2)
                            .foregroundStyle(palette.textTertiary)
                            .frame(width: 40, alignment: .center)
                            .offset(x: min(max(x - 20, -14), max(geo.size.width - 26, 0)), y: 0)
                    }
                }
            }
            .frame(height: 12)
        }
        .padding(.bottom, 6)
    }

    private func laneRow(_ lane: ApproachLane839) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lane.name)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(lane.provider ?? lane.note)
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(width: labelWidth, alignment: .leading)

            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    // Hour rules — the gutter proper, drawn through every lane.
                    ForEach(Array(hours.enumerated()), id: \.offset) { _, hour in
                        Rectangle()
                            .fill(palette.borderFaint)
                            .frame(width: 1, height: laneHeight)
                            .offset(x: min(fraction(Double(hour)) * w, max(w - 1, 0)), y: 0)
                    }
                    if let start = lane.startHour, let end = lane.endHour, end > start {
                        let x0 = fraction(start) * w
                        let bw = max((fraction(end) - fraction(start)) * w, 10)
                        Text("\(hm(start))–\(hm(end))")
                            .font(.system(size: 7.5, weight: .heavy)).tracking(0.2)
                            .foregroundStyle(palette.textTertiary)
                            .fixedSize()
                            .offset(x: min(max(x0 + bw / 2 - 26, 0), max(w - 52, 0)), y: 2)
                        Capsule()
                            .fill(tone(lane.state).opacity(0.9))
                            .frame(width: bw, height: 16)
                            .offset(x: x0, y: 15)
                    } else {
                        // Empty track — no window has been ordered for this
                        // service. Drawn full-span and captioned so the gap is
                        // legible as a gap.
                        Capsule()
                            .fill(palette.tintNeutral)
                            .frame(width: w, height: 16)
                            .offset(x: 0, y: 15)
                        Text("—:—  –  —:—")
                            .font(.system(size: 7.5, weight: .heavy)).tracking(0.3)
                            .foregroundStyle(palette.textTertiary)
                            .frame(width: w, alignment: .center)
                            .offset(x: 0, y: 18)
                    }
                }
            }
            .frame(height: laneHeight)
        }
        .padding(.vertical, Space.s2)
    }
}

// MARK: - Body

private struct VesselMarineServicesBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    let callId: String

    @State private var shipment: ServicesShipment839? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    /// Set when the operator taps a CTA — states plainly why the write cannot
    /// happen and that it is never queued. Rendered through VesselGapNote, the
    /// neutral honest-gap affordance; never through the success toast.
    @State private var actionNote: String? = nil

    /// The approach axis for an inbound call at this port — 05:00 to 09:00
    /// local. The axis is the instrument; the windows drawn on it are data.
    private let axisHours = [5, 6, 7, 8, 9]

    /// The four marine services an inbound call orders. The KINDS are fixed;
    /// providers and windows arrive with getMarineServices (STUB).
    /// STATIC deliberately: the elements carry `let id = UUID()`, so rebuilding
    /// the array on every Body re-init re-mints every id and the gutter's
    /// ForEach sees new identities each render, defeating view diffing. The
    /// content is fixed, so one evaluation for the process is correct.
    private static let lanes: [ApproachLane839] = [
        ApproachLane839(name: "Pilot",    note: "boarding ground PB-1",   provider: nil, startHour: nil, endHour: nil, state: .pending),
        ApproachLane839(name: "Tugs",     note: "assist pair · pending",  provider: nil, startHour: nil, endHour: nil, state: .pending),
        ApproachLane839(name: "Linesmen", note: "line gang · pending",    provider: nil, startHour: nil, endHour: nil, state: .pending),
        ApproachLane839(name: "Berthing", note: "made fast · pending",    provider: nil, startHour: nil, endHour: nil, state: .pending)
    ]

    private var callLine: String {
        if let s = shipment {
            let vessel = s.vesselName ?? "vessel"
            let voy = s.voyageNumber.map { "voy \($0)" } ?? "inbound"
            return "\(vessel) · \(voy) · inbound port call · pilotage"
        }
        // 2026-08-25 — was "MSC ANNA · ETA berth POLB J266 · inbound": a fabricated
        // ship, berth and ETA. The service lanes below are all `.pending` with no
        // provider, so the header claimed a port call the body cannot evidence.
        return "— · no port call selected · pilotage & marine services"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · PILOTAGE & MARINE SERVICES",
                caption: "POLB · USCG",
                title: "Marine services",
                subtitle: callLine
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
                        VesselErrorCard(text: "Refresh failed — \(err) The approach board below is the last serve this session returned and is not being updated.")
                    }
                    boardingHero
                    timelineSection
                    VesselSummaryStrip(label: "Pilot boarding ground PB-1 · tug bollard pull",
                                       value: "— t BP")
                    VesselRegulatorBand(
                        title: "PILOTAGE AUTHORITY · SINGLE-COUNTRY",
                        reference: "port-country",
                        rows: [
                            .init("US", "Jacobsen Pilot Svc · USCG COTP", active: true),
                            .init("CA", "Pacific Pilotage Authority · TC"),
                            .init("MX", "Pilotos del Pacífico · SEMAR")
                        ]
                    )
                    if let actionNote { VesselGapNote(text: actionNote) }
                    ctaPair
                    VesselGapNote(text: "Port-call context is verified and the pilotage authority is the governing one for this port. Boarding time, made-fast time, assigned tugs and every service window appear only when the marine-services order responds.")
                }
                Color.clear.frame(height: Space.s7)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: - Pilot-boarding hero (boarding time + made-fast time)

    private var boardingHero: some View {
        VesselHeroCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    Text("Port call · pilot boarding ground PB-1")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text("SERVICES PENDING")
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(Color(hex: 0xFFC246))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color(hex: 0xFFC246).opacity(0.13)))
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("—:—")
                        .font(.system(size: 32, weight: .bold, design: .monospaced)).tracking(-0.5)
                        .foregroundStyle(Color(hex: 0x5AB0FF))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("pilot boarding · LT")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("berth made-fast —:—")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("— services")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text("ordered · — tug pair")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
            }
        }
    }

    // MARK: - Hour-gutter approach timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "APPROACH SERVICES · HOUR WINDOWS",
                                right: "AWAITING SERVICE ORDER")
            VesselGroupCard {
                ApproachHourGutter839(hours: axisHours, lanes: Self.lanes)
            }
            legendRow
        }
    }

    private var legendRow: some View {
        HStack(spacing: Space.s4) {
            legendChip("Confirmed", Color(hex: 0x5AB0FF))
            legendChip("Ordered", Color(hex: 0xFFC246))
            legendChip("No window", palette.textTertiary)
            Spacer(minLength: 0)
        }
    }

    private func legendChip(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 14, height: 7)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: - CTA pair (confirm is ONLINE_ONLY — it binds a third party)

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Confirm services", action: { flagConfirmGap() }, trailingIcon: "checkmark.seal")
            VesselGhostButton(title: "Reschedule", width: 150) { flagRescheduleGap() }
        }
    }

    /// Confirming binds a pilot, tugs, linesmen and a berth from outside
    /// parties. The procedure that would do it does not exist — say so plainly
    /// rather than letting the tap do nothing and explain nothing.
    private func flagConfirmGap() {
        actionNote = "Marine services cannot be confirmed because no booked service order is connected to this port call. Ask the port-services coordinator to connect the pilot, tug, linesmen, and berth order, then refresh. Third-party commitments require an online confirmation and are never queued."
    }

    private func flagRescheduleGap() {
        actionNote = "Rescheduling is unavailable because no booked marine-service window is connected to this port call. Refresh after the service order is available. Provider changes require an online confirmation and are never queued."
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 150)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 240)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 60)
        }
    }

    // MARK: - Load (REAL: getVesselShipmentDetail)

    private func load() async {
        loading = true; loadError = nil
        guard shipmentId > 0 else { shipment = nil; loading = false; return }
        struct In: Encodable { let id: Int }
        do {
            let detail: ServicesDetail839? = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: In(id: shipmentId))
            self.shipment = detail?.shipment
        } catch {
            // `shipment` is deliberately NOT cleared. A failed refresh keeps the
            // last decoded serve on screen, banner-labelled as not fresh, rather
            // than blanking an approach board being worked from the bridge.
            loadError = error.eusoUserCopy
        }
        loading = false
    }
}

#Preview("839 · Vessel Pilotage & Marine Services · Night") {
    VesselMarineServicesScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("839 · Vessel Pilotage & Marine Services · Light") {
    VesselMarineServicesScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
