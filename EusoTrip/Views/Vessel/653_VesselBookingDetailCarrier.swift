//
//  653_VesselBookingDetailCarrier.swift
//  EusoTrip — Vessel Operator · Booking Detail (carrier vantage).
//
//  Drill-down from 651_VesselShipments. Verbatim port of
//  "653 Vessel Booking Detail Carrier.svg" (Light + Dark). Nav anchored to
//  VesselOperatorNavController.swift (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME),
//  Shipments tab current. Data shape mirrors
//  vesselShipments.getVesselShipmentDetail → { ...shipment, bols, customs,
//  events, demurrage, containers, originPort, destinationPort }
//  (server/routers/vesselShipments.ts:162).
//

import SwiftUI

struct VesselBookingDetailCarrierScreen: View {
    let theme: Theme.Palette
    let shipmentId: Int
    var body: some View {
        Shell(theme: theme) { VesselBookingDetailCarrierBody(shipmentId: shipmentId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",         isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill",  isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",                isCurrent: false)],
                orbState: .idle
            )
        }
        // Real top back affordance (replaces the old decorative chevron in
        // the body header). Fixed leading slot → never overlaps the title;
        // posts the shared NavBack the VesselOperatorSurface pops on.
        .injectBespokeBackBar(title: nil) {
            NotificationCenter.default.post(name: .eusoRoleNavBack, object: nil)
        }
    }
}

// MARK: - Data shapes (mirror getVesselShipmentDetail return)

/// Tolerant value box for heterogeneous server fields (e.g. nested port objects
/// the API returns as `{ name, code, ... }`). File-private per the codebase pattern.
private struct AnyCodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = NSNull() }
        else if let b = try? c.decode(Bool.self) { value = b }
        else if let i = try? c.decode(Int.self) { value = i }
        else if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = s }
        else if let a = try? c.decode([AnyCodable].self) { value = a.map { $0.value } }
        else if let o = try? c.decode([String: AnyCodable].self) { value = o.mapValues { $0.value } }
        else { value = NSNull() }
    }

    var stringValue: String? { value as? String }
    var intValue: Int?       { value as? Int }
    var doubleValue: Double? { value as? Double }
    var boolValue: Bool?     { value as? Bool }
}

private struct VesselEvent653: Decodable, Identifiable {
    let id: Int
    let eventType: String?
    let location: String?
    let timestamp: String?
}

private struct OceanContainer653: Decodable, Identifiable {
    let id: Int
    let containerNumber: String?
    let containerType: String?
    let status: String?
    let imdgClass: String?
    let reeferSetpoint: Double?
}

private struct VesselDemurrageRow653: Decodable {
    let freeTimeDays: Int?
    let accruedDays: Int?
    let chargeUsd: Double?
}

private struct VesselShipmentDetail653: Decodable {
    let id: Int
    let bookingNumber: String?
    let origin: String?
    let destination: String?
    let status: String?
    let vesselName: String?
    let voyageNumber: String?
    let teuCount: Int?
    let estimatedArrival: String?
    let events: [VesselEvent653]?
    let containers: [OceanContainer653]?
    let demurrage: [VesselDemurrageRow653]?
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.bookingNumber = try c.decodeIfPresent(String.self, forKey: .bookingNumber)
        self.status = try c.decodeIfPresent(String.self, forKey: .status)
        self.voyageNumber = try c.decodeIfPresent(String.self, forKey: .voyageNumber)
        self.events = try c.decodeIfPresent([VesselEvent653].self, forKey: .events)
        self.containers = try c.decodeIfPresent([OceanContainer653].self, forKey: .containers)
        self.demurrage = try c.decodeIfPresent([VesselDemurrageRow653].self, forKey: .demurrage)
        
        // Extract port names from port objects
        if let originPortObj = try c.decodeIfPresent([String: AnyCodable].self, forKey: .originPort) {
            self.origin = originPortObj["name"]?.stringValue
        } else {
            self.origin = try c.decodeIfPresent(String.self, forKey: .origin)
        }
        
        if let destPortObj = try c.decodeIfPresent([String: AnyCodable].self, forKey: .destinationPort) {
            self.destination = destPortObj["name"]?.stringValue
        } else {
            self.destination = try c.decodeIfPresent(String.self, forKey: .destination)
        }
        
        // Map vesselId to vessel name (server only sends ID, extract from vesselId field as fallback)
        self.vesselName = try c.decodeIfPresent(String.self, forKey: .vesselName)
        
        // Map numberOfContainers to teuCount
        if let numContainers = try c.decodeIfPresent(Int.self, forKey: .numberOfContainers) {
            self.teuCount = numContainers
        } else {
            self.teuCount = try c.decodeIfPresent(Int.self, forKey: .teuCount)
        }
        
        // Map eta to estimatedArrival
        if let eta = try c.decodeIfPresent(String.self, forKey: .eta) {
            self.estimatedArrival = eta
        } else {
            self.estimatedArrival = try c.decodeIfPresent(String.self, forKey: .estimatedArrival)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, bookingNumber, status, voyageNumber, events, containers, demurrage
        case origin, destination, vesselName, teuCount, estimatedArrival
        case originPort, destinationPort, numberOfContainers, eta
    }
}

// MARK: - Body

private struct VesselBookingDetailCarrierBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    @State private var detail: VesselShipmentDetail653? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var updating = false

    private let milestones = ["BOOKED", "GATE IN", "LOADED", "ON WATER", "ARRIVED", "DISCH.", "GATE OUT"]

    private var currentMilestoneIndex: Int {
        switch (detail?.status ?? "").lowercased() {
        case "booked":                 return 0
        case "gate_in":                return 1
        case "loaded":                 return 2
        case "departed", "on_water", "in_transit": return 3
        case "arrived":                return 4
        case "discharged":             return 5
        case "gate_out", "settled":    return 6
        default:                       return 3
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading booking…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let d = detail {
                    voyageCard(d)
                    milestoneTrack
                    containerRoster(d)
                    demurrageMeter(d)
                    actions
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "ferry.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · BOOKING DETAIL")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            HStack {
                Text(detail?.bookingNumber ?? "VB-…").font(.system(size: 26, weight: .heavy)).monospaced().foregroundStyle(palette.textPrimary)
                Spacer()
                StatusPill(text: (detail?.status ?? "—").replacingOccurrences(of: "_", with: " ").uppercased(), kind: .info)
            }
            if let d = detail {
                Text("\(d.origin ?? "—") → \(d.destination ?? "—") · \(d.vesselName ?? "—") voy \(d.voyageNumber ?? "—") · \(d.teuCount ?? 0) FEU")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func voyageCard(_ d: VesselShipmentDetail653) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text("VOYAGE · TRANS-PACIFIC EASTBOUND").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Text(d.origin ?? "—").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text("\(d.destination ?? "—") · ETA \(d.estimatedArrival ?? "—")").font(EType.body).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var milestoneTrack: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("STATUS · LIVE EVENT TRACK").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                HStack(spacing: 0) {
                    ForEach(Array(milestones.enumerated()), id: \.offset) { idx, label in
                        VStack(spacing: 6) {
                            Circle()
                                .fill(idx <= currentMilestoneIndex ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCardSoft))
                                .frame(width: idx == currentMilestoneIndex ? 13 : 10, height: idx == currentMilestoneIndex ? 13 : 10)
                            Text(label).font(.system(size: 7.5, weight: idx == currentMilestoneIndex ? .heavy : .semibold))
                                .foregroundStyle(idx <= currentMilestoneIndex ? palette.textPrimary : palette.textTertiary)
                        }
                        if idx < milestones.count - 1 { Spacer(minLength: 0) }
                    }
                }
            }
        }
    }

    private func containerRoster(_ d: VesselShipmentDetail653) -> some View {
        let containers = d.containers ?? []
        return VStack(alignment: .leading, spacing: Space.s2) {
            Text("CONTAINERS · \(d.teuCount ?? containers.count) FEU ON VOY \(d.voyageNumber ?? "—")")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(spacing: Space.s2) {
                    ForEach(containers) { c in
                        HStack {
                            Text("\(c.containerNumber ?? "—")\(c.containerType.map { " · \($0)" } ?? "")")
                                .font(.system(size: 12, weight: .medium)).monospaced().foregroundStyle(palette.textPrimary)
                            Spacer()
                            if c.imdgClass != nil {
                                Text("hazmat").font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.warning)
                            } else if let sp = c.reeferSetpoint {
                                Text(String(format: "%.0f°C OK", sp)).font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.info)
                            } else {
                                Text(c.status ?? "on board").font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.info)
                            }
                        }
                    }
                }
            }
        }
    }

    private func demurrageMeter(_ d: VesselShipmentDetail653) -> some View {
        let row = d.demurrage?.first
        let free = row?.freeTimeDays ?? 4
        let accrued = row?.accruedDays ?? 0
        let charge = row?.chargeUsd ?? 0
        return VStack(alignment: .leading, spacing: Space.s2) {
            Text("DEMURRAGE · FREE TIME METER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(free)d free time · \(accrued)d accrued").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text("$\(Int(charge))").font(EType.bodyStrong).monospacedDigit()
                            .foregroundStyle(charge > 0 ? Brand.warning : Brand.success)
                    }
                    ProgressView(value: Double(accrued), total: Double(max(free, 1))).tint(LinearGradient.primary)
                    Text("On water — meter starts on discharge + gate-out at destination port")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: updating ? "Updating…" : "Update status",
                      action: { Task { await updateStatus() } },
                      leadingIcon: "arrow.triangle.2.circlepath")
            CTAButton(title: "B/L", leadingIcon: "doc.text")
        }
    }

    // MARK: - Load + mutate

    private func load() async {
        loading = true; loadError = nil
        struct DetailIn: Encodable { let id: Int }
        do {
            let d: VesselShipmentDetail653 = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipmentDetail", input: DetailIn(id: shipmentId))
            self.detail = d
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func updateStatus() async {
        updating = true
        struct StatusIn: Encodable { let id: Int; let newStatus: String }
        struct Empty653: Decodable {}
        do {
            let _: Empty653 = try await EusoTripAPI.shared.mutation(
                "vesselShipments.updateVesselShipmentStatus",
                input: StatusIn(id: shipmentId, newStatus: "arrived"))
            await load()
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        updating = false
    }
}

#Preview("653 · Vessel Booking Detail · Night") { VesselBookingDetailCarrierScreen(theme: Theme.dark, shipmentId: 77410).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("653 · Vessel Booking Detail · Light") { VesselBookingDetailCarrierScreen(theme: Theme.light, shipmentId: 77410).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
