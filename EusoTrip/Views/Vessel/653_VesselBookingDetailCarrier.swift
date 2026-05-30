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
    }
}

// MARK: - Data shapes (mirror getVesselShipmentDetail return)

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
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
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
        struct StatusIn: Encodable { let id: Int; let status: String }
        struct Empty653: Decodable {}
        do {
            let _: Empty653 = try await EusoTripAPI.shared.mutation(
                "vesselShipments.updateVesselShipmentStatus",
                input: StatusIn(id: shipmentId, status: "arrived"))
            await load()
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        updating = false
    }
}

#Preview("653 · Vessel Booking Detail · Night") { VesselBookingDetailCarrierScreen(theme: Theme.dark, shipmentId: 77410).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("653 · Vessel Booking Detail · Light") { VesselBookingDetailCarrierScreen(theme: Theme.light, shipmentId: 77410).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
