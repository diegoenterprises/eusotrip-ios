//
//  002_VesselBookingDetail.swift
//  EusoTrip — Vessel Shipper · Booking Detail (shipper vantage).
//
//  Web parity: client/src/pages/vessel/VesselBookingDetail.tsx
//  Wireframe:  06 Vessel / 002 Vessel Booking Detail (canvas 440×956).
//  PERSONA:    Diego Usoro · Eusorone Marine (VESSEL_SHIPPER). Booking VS-48217 ·
//              Shanghai CN → Los Angeles CA · 40ft HC · 8 cntr · ONE.
//  transportMode = vessel.
//
//  tRPC (server/routers/vesselShipments.ts) — VERIFIED against the real
//  procedure bodies + drizzle/schema.ts (the-oath §25 contract-drift kill):
//    getVesselShipmentDetail (EXISTS :234, vesselProcedure) — the ONE real
//      endpoint. Returns { ...vesselShipments row, bols[], customs[], events[],
//      demurrage[], containers[], originPort:<ports|null>, destinationPort } .
//      Every hero/voyage/roster/meter value below binds to a real column on
//      that payload or an honest derivation — no fabricated demo defaults.
//    liveTrackOceanShipment (EXISTS :1132) — "Track live" CTA. Requires
//      { referenceNumber: string } (NOT { id }); we pass the booking/BL ref.
//    getBOL (EXISTS :467) — "Documents" CTA. Keyed by { bolNumber } or the
//      bills_of_lading row { id } (NOT the shipment id); we use detail.bols.
//
//  REMOVED (were guaranteed-failing contract drift, §25):
//    • getContainerTracking — returns { container, movements } (object), was
//      decoded as a bare array (hard throw); also keyed by containerNumber/
//      containerId, never by shipment, so it could never load THIS booking's
//      roster. detail.containers (shipping_containers WHERE assignedShipmentId)
//      is the correct, already-present source.
//    • calculateVesselDemurrage — it is a .mutation (inserts vessel_demurrage
//      rows), input { shipmentId } not { id }, output { demurrage, dwellDays..}
//      not { freeDays, accruedDays.. }. Calling it on a read-only detail LOAD
//      via .query is a method-type mismatch (GET on a mutation → tRPC error)
//      AND a write-on-read hazard. detail.demurrage (the persisted rows) is the
//      correct read source.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//

import SwiftUI

struct VesselBookingDetailScreen: View {
    var theme: Theme.Palette = Theme.dark
    /// Shipment row id the detail endpoint keys on. Defaults to the wireframe
    /// hero booking so the View is default-initializable for previews / router
    /// fallbacks.
    var shipmentId: Int = 48217

    var body: some View {
        Shell(theme: theme) { VesselBookingDetailBody(shipmentId: shipmentId) } nav: {
            // PROPOSED greenfield Vessel nav: HOME · BOOKINGS · [orb] · TRACK(active) · ME
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Bookings", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Track",   systemImage: "clock",            isCurrent: true),
                           NavSlot(label: "Me",      systemImage: "person",           isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Decimal-string tolerant scalar
//
// MySQL `decimal` columns serialize over tRPC as JSON strings ("150.00"), not
// numbers. Decoding them as Double throws. File-local (private) so it does not
// collide with the identically-shaped helper in 002_RailShipmentDetail.swift.

private struct VFlexDecimal: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = Double(s) }
        else if let d = try? c.decode(Double.self) { value = d }
        else if let i = try? c.decode(Int.self) { value = Double(i) }
        else { value = nil }
    }
}

// MARK: - Data shapes (decoded from the REAL getVesselShipmentDetail payload)

/// ports row (originPort / destinationPort objects). `coordinates` is JSON
/// {lat,lng} on the server — decoded so we can derive nautical-mile distance.
private struct VesselPortGeo002: Decodable { let lat: Double?; let lng: Double? }

private struct VesselPort002: Decodable {
    let id: Int?
    let name: String?          // "Port of Los Angeles"
    let unlocode: String?      // "USLAX"
    let city: String?          // "Los Angeles"
    let state: String?         // "CA"
    let country: String?       // "US" | "CA" | "MX" | "CN" ...
    let coordinates: VesselPortGeo002?
}

/// vessel_shipment_events row. NOTE: server `location` is a JSON object
/// {lat,lng,description?}, NOT a string — decoded as an object (the old String?
/// decode would throw whenever a row carried a location).
private struct VesselEventGeo002: Decodable { let lat: Double?; let lng: Double?; let description: String? }

private struct VesselEvent002: Decodable, Identifiable {
    let id: Int
    let eventType: String?     // "status_loaded_on_vessel" | "departed" ...
    let description: String?   // human line for the AIS note
    let location: VesselEventGeo002?
    let timestamp: String?     // ISO-8601 (server orders these DESC)
}

/// shipping_containers row. Real columns: containerNumber, sizeType (NOT
/// "containerType"), status. There is no "bay" column — dropped.
private struct OceanContainer002: Decodable, Identifiable {
    let id: Int
    let containerNumber: String?
    let sizeType: String?      // "40ft_hc" ...
    let status: String?        // "loaded" | "in_transit" | "at_port" ...
}

/// vessel_demurrage row (ARRAY on the payload — was decoded as a single object,
/// a hard throw). Real columns below; money via VFlexDecimal.
private struct VesselDemurrage002: Decodable, Identifiable {
    let id: Int
    let chargeType: String?    // "demurrage" | "detention" | "per_diem"
    let freeTimeDays: Int?
    let chargeableDays: Int?
    let ratePerDay: VFlexDecimal?
    let totalCharge: VFlexDecimal?
    let status: String?        // "accruing" | "invoiced" | "paid" | "disputed" | "waived"
}

/// bills_of_lading row (subset). Backs the BL number + Documents CTA + the
/// vessel name (the shipment row itself does not carry vesselName).
private struct VesselBOL002: Decodable, Identifiable {
    let id: Int
    let bolNumber: String?
    let vesselName: String?
    let voyageNumber: String?
    let status: String?
}

/// vesselShipments.getVesselShipmentDetail (EXISTS :234). Fields are the REAL
/// vessel_shipments columns + the nested joins the server spreads in.
private struct VesselShipmentDetail002: Decodable {
    let id: Int
    let bookingNumber: String?
    let billOfLading: String?
    let cargoType: String?       // "container" | "reefer" | ...
    let commodity: String?
    let containerSize: String?   // "40ft_hc" ...
    let numberOfContainers: Int?
    let status: String?          // vessel_shipments.status enum
    let rate: VFlexDecimal?
    let rateType: String?        // "per_teu" | "lump_sum" ...
    let voyageNumber: String?
    let serviceRoute: String?    // lane label
    let etd: String?
    let eta: String?
    let atd: String?             // actual departure
    let ata: String?             // actual arrival
    let originPort: VesselPort002?
    let destinationPort: VesselPort002?
    let events: [VesselEvent002]?
    let containers: [OceanContainer002]?
    let demurrage: [VesselDemurrage002]?
    let bols: [VesselBOL002]?
}

// MARK: - Body

private struct VesselBookingDetailBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int

    @State private var detail: VesselShipmentDetail002? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    /// Action surface ("Track live" · "Documents") writes here on failure —
    /// never silently swallowed.
    @State private var actionError: String? = nil

    // Milestone track — SVG nodes in order, mapped to the REAL vessel_shipments
    // status enum.
    private let milestones = ["BOOKED", "GATE-IN", "LOADED", "IN TRANSIT", "ARRIVED", "DISCH.", "DELIVERED"]

    /// Maps the real status enum to a milestone node. Unknown / terminal
    /// (cancelled, rolled) stay at BOOKED — the status pill carries the truth;
    /// we never fabricate "IN TRANSIT" for an unmapped value.
    private var currentMilestoneIndex: Int {
        switch (detail?.status ?? "").lowercased() {
        case "booking_requested", "booking_confirmed", "documentation", "container_released":
            return 0
        case "gate_in":                                   return 1
        case "loaded_on_vessel":                          return 2
        case "departed", "in_transit", "transshipment":   return 3
        case "arrived", "customs_hold", "customs_cleared": return 4
        case "discharged":                                return 5
        case "gate_out", "delivered", "invoiced", "settled": return 6
        default:                                          return 0
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.top, Space.s5)

                VStack(alignment: .leading, spacing: Space.s5) {
                    if let actionError {
                        actionErrorBanner(actionError)
                    }

                    if loading {
                        loadingState
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else if detail == nil {
                        EusoEmptyState(systemImage: "shippingbox",
                                       title: "Booking not found",
                                       subtitle: "This booking is no longer available or you don't have access to it.")
                    } else {
                        voyageCard
                        milestoneSection
                        containerRoster
                        demurrageMeter
                        actions
                    }

                    Color.clear.frame(height: 96)
                }
                .padding(.top, Space.s5)
            }
            .padding(.horizontal, Space.s5)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar  (SVG: back chevron · y=72 eyebrow · y=116 booking# + status pill · y=138 subline)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("✦ VESSEL SHIPPER · BOOKING DETAIL")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: 8)
            }
            .padding(.top, Space.s5)

            HStack(alignment: .center) {
                Text(detail?.bookingNumber ?? "—")
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .kerning(-0.5)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                // SVG: gradient-filled status pill, ink text.
                if let s = detail?.status {
                    Text(statusLabel(s))
                        .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(Color(hex: 0x05060A))
                        .padding(.horizontal, Space.s4).padding(.vertical, 6)
                        .background(Capsule().fill(LinearGradient.primary))
                }
            }
            .padding(.top, Space.s4)

            Text(subline)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 6)
                .lineLimit(2).minimumScaleFactor(0.8)
        }
    }

    private func statusLabel(_ s: String) -> String {
        s.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    /// "origin → destination · <size> · <n> cntr" — every segment real or omitted.
    private var subline: String {
        var parts: [String] = []
        let o = portShort(detail?.originPort)
        let d = portShort(detail?.destinationPort)
        if let o, let d { parts.append("\(o) → \(d)") }
        else if let only = o ?? d { parts.append(only) }
        if let size = prettySize(detail?.containerSize) { parts.append(size) }
        if let n = detail?.numberOfContainers, n > 0 { parts.append("\(n) cntr") }
        return parts.isEmpty ? "Booking details" : parts.joined(separator: " · ")
    }

    /// "City CC" / "Name" / UN/LOCODE — first non-empty.
    private func portShort(_ p: VesselPort002?) -> String? {
        guard let p else { return nil }
        if let city = p.city, !city.isEmpty {
            if let cc = p.country, !cc.isEmpty { return "\(city) \(cc)" }
            return city
        }
        if let name = p.name, !name.isEmpty { return name }
        if let loc = p.unlocode, !loc.isEmpty { return loc }
        return nil
    }

    private func prettySize(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        // "40ft_hc" → "40ft HC", "20ft_reefer" → "20ft REEFER"
        let parts = raw.split(separator: "_")
        return parts.map { seg -> String in
            seg.allSatisfy { $0.isNumber || $0 == "f" || $0 == "t" } ? String(seg) : seg.uppercased()
        }.joined(separator: " ")
    }

    // MARK: - Route / ETA card  (SVG y=178, 400×96, gradient-rim card + ETA chip)

    private var voyageCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(voyageEyebrow)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)

            HStack(alignment: .top, spacing: Space.s4) {
                // Departed/arrival timeline column (filled node → hollow node).
                VStack(spacing: 0) {
                    Circle().fill(LinearGradient.primary).frame(width: 10, height: 10)
                    Rectangle().fill(LinearGradient.iridescentHairlineDark).frame(width: 2, height: 20)
                    Circle().strokeBorder(palette.textTertiary, lineWidth: 2).frame(width: 10, height: 10)
                }
                .padding(.top, 6)

                VStack(alignment: .leading, spacing: Space.s5) {
                    Text(departLine)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(arriveLine)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }

                Spacer(minLength: 4)

                // ETA chip (SVG translate(296,16): 64×48, blue@0.12, gradient numeral).
                VStack(spacing: 2) {
                    Text("ETA")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                    Text(etaStr)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(width: 64, height: 48)
                .background(Brand.blue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .padding(.top, Space.s4)
        }
        .padding(Space.s5)
        .eusoCard(radius: Radius.xl, intensity: .feature)
    }

    private var voyageEyebrow: String {
        var parts: [String] = []
        // Vessel name lives on the BOL, not the shipment row.
        let vessel = detail?.bols?.first?.vesselName
        let voy = detail?.voyageNumber ?? detail?.bols?.first?.voyageNumber
        if let vessel, let voy { parts.append("\(vessel) \(voy)") }
        else if let vessel { parts.append(vessel) }
        else if let voy { parts.append("VOY \(voy)") }
        if let nm = distanceNm() { parts.append("\(nm.formatted()) NM") }
        if let lane = detail?.serviceRoute, !lane.isEmpty { parts.append(lane) }
        return parts.isEmpty ? "VOYAGE" : "VOYAGE · " + parts.joined(separator: " · ")
    }

    /// Great-circle distance in nautical miles between the two port coordinates
    /// (haversine), when both are present. No fabricated default.
    private func distanceNm() -> Int? {
        guard let o = detail?.originPort?.coordinates,
              let d = detail?.destinationPort?.coordinates,
              let lat1 = o.lat, let lon1 = o.lng, let lat2 = d.lat, let lon2 = d.lng
        else { return nil }
        let r = 3440.065 // earth radius in nautical miles
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dPhi = (lat2 - lat1) * .pi / 180
        let dLam = (lon2 - lon1) * .pi / 180
        let a = sin(dPhi / 2) * sin(dPhi / 2)
            + cos(p1) * cos(p2) * sin(dLam / 2) * sin(dLam / 2)
        let c = 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
        let nm = Int((r * c).rounded())
        return nm > 0 ? nm : nil
    }

    private var departLine: String {
        let port = portShort(detail?.originPort)
        let when = shortStamp(detail?.atd ?? detail?.etd)
        switch (port, when) {
        case let (p?, w?): return "\(p) · departed \(w)"
        case let (p?, nil): return p
        case let (nil, w?): return "departed \(w)"
        default:           return "Departure pending"
        }
    }

    private var arriveLine: String {
        let port = portShort(detail?.destinationPort)
        let when = shortStamp(detail?.ata ?? detail?.eta)
        let verb = detail?.ata != nil ? "arrived" : "ETA"
        switch (port, when) {
        case let (p?, w?): return "\(p) · \(verb) \(w)"
        case let (p?, nil): return p
        case let (nil, w?): return "\(verb) \(w)"
        default:           return "Arrival pending"
        }
    }

    /// Days from now until eta (or "arrived"/"—"). No fabricated "5.9d".
    private var etaStr: String {
        if detail?.ata != nil { return "in" }
        guard let iso = detail?.eta, let when = parseISO(iso) else { return "—" }
        let days = when.timeIntervalSinceNow / 86_400
        if days <= 0 { return "due" }
        return String(format: "%.1fd", days)
    }

    // MARK: - Status milestone timeline  (SVG y=306 eyebrow · y=318 card · y=338 AIS note)

    private var milestoneSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("STATUS · LIVE MILESTONE TRACK")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            VStack(alignment: .leading, spacing: Space.s4) {
                Text(aisNote)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)

                HStack(spacing: 0) {
                    ForEach(Array(milestones.enumerated()), id: \.offset) { idx, label in
                        VStack(spacing: 8) {
                            ZStack {
                                if idx == currentMilestoneIndex {
                                    Circle().strokeBorder(LinearGradient.primary, lineWidth: 2)
                                        .frame(width: 22, height: 22)
                                }
                                Circle()
                                    .fill(idx <= currentMilestoneIndex
                                          ? AnyShapeStyle(LinearGradient.primary)
                                          : AnyShapeStyle(palette.bgCardSoft))
                                    .overlay(
                                        Circle().strokeBorder(palette.borderStrong,
                                                              lineWidth: idx <= currentMilestoneIndex ? 0 : 1.4)
                                    )
                                    .frame(width: idx == currentMilestoneIndex ? 13 : 10,
                                           height: idx == currentMilestoneIndex ? 13 : 10)
                            }
                            .frame(height: 22)
                            Text(label)
                                .font(.system(size: 7.5, weight: idx == currentMilestoneIndex ? .heavy : .bold))
                                .foregroundStyle(idx == currentMilestoneIndex
                                                 ? AnyShapeStyle(LinearGradient.primary)
                                                 : (idx < currentMilestoneIndex
                                                    ? AnyShapeStyle(palette.textPrimary)
                                                    : AnyShapeStyle(palette.textTertiary)))
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        if idx < milestones.count - 1 { Spacer(minLength: 0) }
                    }
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    /// Most-recent event (server returns events DESC by timestamp). Honest
    /// empty when the shipment has no event yet.
    private var aisNote: String {
        guard let ev = detail?.events?.first else {
            return "No vessel events recorded yet"
        }
        if let note = ev.description, !note.isEmpty {
            if let w = shortStamp(ev.timestamp) { return "\(note) · \(w)" }
            return note
        }
        let type = (ev.eventType ?? "event").replacingOccurrences(of: "_", with: " ")
        if let w = shortStamp(ev.timestamp) { return "\(type) · \(w)" }
        return type
    }

    // MARK: - Container roster  (SVG y=440 eyebrow · y=452 card · detail.containers)

    private var containerRoster: some View {
        let rows = detail?.containers ?? []
        let bol = detail?.billOfLading ?? detail?.bols?.first?.bolNumber
        let count = detail?.numberOfContainers ?? rows.count
        return VStack(alignment: .leading, spacing: Space.s3) {
            Text(rosterEyebrow(count: count, bol: bol))
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)

            VStack(spacing: 0) {
                if rows.isEmpty {
                    EusoEmptyState(systemImage: "shippingbox",
                                   title: "No container tracking yet",
                                   subtitle: bol.map { "Container positions for BL \($0) will appear here." }
                                        ?? "Container positions will appear here once assigned.")
                        .padding(.vertical, Space.s2)
                } else {
                    ForEach(Array(rows.prefix(5).enumerated()), id: \.element.id) { idx, c in
                        if idx > 0 {
                            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                        }
                        containerRow(c, isLast: idx == 4, remaining: rows.count - 5)
                    }
                }
            }
            .padding(Space.s4)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func rosterEyebrow(count: Int, bol: String?) -> String {
        if let bol { return "CONTAINERS · \(count) ON BL \(bol)" }
        return "CONTAINERS · \(count)"
    }

    private func containerRow(_ c: OceanContainer002, isLast: Bool, remaining: Int) -> some View {
        var label = c.containerNumber ?? "—"
        if let size = prettySize(c.sizeType) { label += " · \(size)" }
        // SVG: the 5th visible row trails "+N more" in secondary; others trail
        // their live status in gradient.
        let showRemainder = isLast && remaining > 0
        return HStack {
            Text(label)
                .font(EType.mono(.body))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            if showRemainder {
                Text("+\(remaining) more")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
            } else if let status = c.status {
                Text(status.replacingOccurrences(of: "_", with: " "))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(LinearGradient.primary)
            }
        }
        .padding(.vertical, Space.s3)
    }

    // MARK: - Demurrage meter  (SVG y=636 eyebrow · y=648 card · detail.demurrage)

    private var demurrageMeter: some View {
        // Aggregate the persisted demurrage rows for this shipment.
        let rows = detail?.demurrage ?? []
        let free = rows.compactMap { $0.freeTimeDays }.max() ?? 0
        let accrued = rows.compactMap { $0.chargeableDays }.reduce(0, +)
        let charge = rows.compactMap { $0.totalCharge?.value }.reduce(0, +)
        let started = rows.contains { ($0.status ?? "").lowercased() == "accruing" } || accrued > 0
        let hasData = !rows.isEmpty
        return VStack(alignment: .leading, spacing: Space.s3) {
            Text("DEMURRAGE · FREE TIME METER")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text(hasData ? "\(free) days free · \(accrued) days accrued"
                                 : "No demurrage accruing")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(chargeStr(charge))
                        .font(.system(size: 13, weight: .bold)).monospacedDigit()
                        .foregroundStyle(charge > 0 ? Brand.warning : Brand.success)
                }
                // SVG: track white@0.10, fill gradient ~ fraction of free days used.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                            .frame(height: 8)
                        Capsule().fill(LinearGradient.primary)
                            .frame(width: meterFillWidth(in: geo.size.width, free: free, accrued: accrued, started: started),
                                   height: 8)
                    }
                }
                .frame(height: 8)
                Text(meterNote(started: started, hasData: hasData))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(Space.s4)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func chargeStr(_ charge: Double) -> String {
        guard charge > 0 else { return "$0" }
        return "$\(Int(charge.rounded()))"
    }

    /// Meter reflects the fraction of free days consumed. Empty (no rows) → no
    /// fill (afloat, nothing accruing) — no fabricated 20%.
    private func meterFillWidth(in total: CGFloat, free: Int, accrued: Int, started: Bool) -> CGFloat {
        guard started, free > 0, accrued > 0 else { return 0 }
        let frac = min(1.0, Double(accrued) / Double(free))
        return total * CGFloat(frac)
    }

    private func meterNote(started: Bool, hasData: Bool) -> String {
        let port = portShort(detail?.destinationPort) ?? "the discharge port"
        if !hasData {
            return "Afloat — meter starts on terminal discharge at \(port)"
        }
        return started
            ? "Meter running — free time consuming at \(port)"
            : "Free time intact at \(port)"
    }

    // MARK: - Actions  (SVG y=752: gradient "Track live" · glass "Documents")

    private var actions: some View {
        HStack(spacing: Space.s3) {
            Button {
                Task { await trackLive() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 15, weight: .bold))
                    Text("Track live")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(Color(hex: 0x05060A))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.primary)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                Task { await openDocuments() }
            } label: {
                Text("Documents")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132, height: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading + error chrome

    private var loadingState: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 96)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
    }

    private func actionErrorBanner(_ message: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.danger)
            Text(message)
                .font(EType.caption)
                .foregroundStyle(Brand.danger)
            Spacer()
            Button { actionError = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .background(Brand.danger.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.40)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Timestamp helpers

    private func parseISO(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: iso) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: iso)
    }

    /// "MM-dd HH:mm" honest short stamp; nil when unparseable/absent.
    private func shortStamp(_ iso: String?) -> String? {
        guard let d = parseISO(iso) else { return nil }
        let out = DateFormatter()
        out.dateFormat = "MM-dd HH:mm"
        return out.string(from: d)
    }

    // MARK: - Load (single real endpoint; do/catch — never try?)

    private func load() async {
        loading = true; loadError = nil
        struct DetailIn: Encodable { let id: Int }
        do {
            // getVesselShipmentDetail (EXISTS :234) returns the row + bols +
            // events + demurrage + containers + originPort + destinationPort,
            // or null when the booking is missing / not accessible. One call
            // powers every section — no fabricated fallbacks. Decoded optional
            // so a null routes to the honest "Booking not found" empty state
            // (not a thrown error).
            let d: VesselShipmentDetail002? =
                try await EusoTripAPI.shared.query("vesselShipments.getVesselShipmentDetail",
                                                   input: DetailIn(id: shipmentId))
            self.detail = d
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Actions (do/catch · actionError on failure)

    /// liveTrackOceanShipment (EXISTS :1132) backs "Track live". Server requires
    /// { referenceNumber: string } — we pass the booking number (or BL ref). A
    /// dead feed / missing ref surfaces honestly; navigation to the live-track
    /// surface is wired at the router.
    private func trackLive() async {
        guard let ref = detail?.bookingNumber ?? detail?.billOfLading ?? detail?.bols?.first?.bolNumber else {
            actionError = "No booking reference to track yet."
            return
        }
        struct TrackIn: Encodable { let referenceNumber: String }
        // External tracking payload shape is provider-defined and the server
        // returns null when the feed is unreachable; decode permissively as an
        // optional so a null is "no live fix yet", not a decode throw.
        struct TrackOut: Decodable {}
        do {
            let _: TrackOut? = try await EusoTripAPI.shared.query(
                "vesselShipments.liveTrackOceanShipment", input: TrackIn(referenceNumber: ref))
        } catch {
            actionError = "Tracking unavailable — "
                + ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// getBOL (EXISTS :467) backs "Documents". Keyed by the BL number (or the
    /// bills_of_lading row id) from detail.bols — NOT the shipment id. Document
    /// viewer presentation is wired at the router; here we honestly surface the
    /// fetch result/error.
    private func openDocuments() async {
        guard let bol = detail?.bols?.first else {
            actionError = "No bill of lading issued for this booking yet."
            return
        }
        struct BOLByNumber: Encodable { let bolNumber: String }
        struct BOLById: Encodable { let id: Int }
        struct BOLOut: Decodable { let bolNumber: String?; let status: String? }
        do {
            if let num = bol.bolNumber {
                let _: BOLOut? = try await EusoTripAPI.shared.query(
                    "vesselShipments.getBOL", input: BOLByNumber(bolNumber: num))
            } else {
                let _: BOLOut? = try await EusoTripAPI.shared.query(
                    "vesselShipments.getBOL", input: BOLById(id: bol.id))
            }
        } catch {
            actionError = "Couldn't open documents — "
                + ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

#Preview("002 · Vessel Booking Detail · Night") {
    VesselBookingDetailScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("002 · Vessel Booking Detail · Light") {
    VesselBookingDetailScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
