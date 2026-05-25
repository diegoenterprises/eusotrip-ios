//
//  553_RailShipmentDetailCarrier.swift
//  EusoTrip — Rail Engineer · Shipment Detail (carrier vantage).
//

import SwiftUI

struct RailShipmentDetailCarrierScreen: View {
    let theme: Theme.Palette
    let shipmentId: Int
    var body: some View {
        Shell(theme: theme) { RailShipmentDetailCarrierBody(shipmentId: shipmentId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct RailEvent553: Decodable, Identifiable {
    let id: Int
    let eventType: String?
    let location: String?
    let timestamp: String?
}

private struct RailCar553: Decodable, Identifiable {
    let id: Int
    let carNumber: String?
    let carType: String?
    let status: String?
    let hazmatUn: String?
}

private struct RailDemurrageRow553: Decodable {
    let freeTimeHours: Int?
    let accruedHours: Int?
    let chargeUsd: Double?
}

private struct RailShipmentDetail553: Decodable {
    let id: Int
    let loadId: String?
    let origin: String?
    let destination: String?
    let status: String?
    let carsCount: Int?
    let commodity: String?
    let estimatedArrival: String?
    let carrierName: String?
    let consistNumber: String?
    let events: [RailEvent553]?
    let demurrage: [RailDemurrageRow553]?
}

private struct RailShipmentDetailCarrierBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int
    @State private var detail: RailShipmentDetail553? = nil
    @State private var cars: [RailCar553] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var updating = false

    private let milestones = ["ORDERED", "PLACED", "LOADED", "IN TRANSIT", "INTERCH.", "SPOTTED", "SETTLED"]

    private var currentMilestoneIndex: Int {
        switch (detail?.status ?? "").lowercased() {
        case "car_ordered":    return 0
        case "car_placed":     return 1
        case "loaded":         return 2
        case "departed", "in_transit": return 3
        case "at_interchange": return 4
        case "spotted", "in_yard": return 5
        case "settled":        return 6
        default:               return 3
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading shipment…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if let d = detail {
                    routeCard(d)
                    milestoneTrack
                    carRoster
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
                Image(systemName: "tram.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("RAIL ENGINEER · SHIPMENT DETAIL")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            HStack {
                Text(detail?.loadId ?? "RS-…").font(.system(size: 26, weight: .heavy)).monospaced().foregroundStyle(palette.textPrimary)
                Spacer()
                StatusPill(text: (detail?.status ?? "—").replacingOccurrences(of: "_", with: " ").uppercased(), kind: .info)
            }
            if let d = detail {
                Text("\(d.origin ?? "—") → \(d.destination ?? "—") · intermodal · \(d.carsCount ?? cars.count) cars · \(d.carrierName ?? "—")")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func routeCard(_ d: RailShipmentDetail553) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ROUTE · NS CRESCENT CORRIDOR").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
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

    private var carRoster: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CARS · \(cars.count) IN CONSIST \(detail?.consistNumber ?? "—")")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(spacing: Space.s2) {
                    ForEach(cars) { c in
                        HStack {
                            Text("\(c.carNumber ?? "—")\(c.carType.map { " · \($0)" } ?? "")")
                                .font(.system(size: 12, weight: .medium)).monospaced().foregroundStyle(palette.textPrimary)
                            Spacer()
                            if c.hazmatUn != nil {
                                Text("hazmat").font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.warning)
                            } else {
                                Text(c.status ?? "rolling").font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.success)
                            }
                        }
                    }
                }
            }
        }
    }

    private func demurrageMeter(_ d: RailShipmentDetail553) -> some View {
        let row = d.demurrage?.first
        let free = row?.freeTimeHours ?? 48
        let accrued = row?.accruedHours ?? 0
        let charge = row?.chargeUsd ?? 0
        return VStack(alignment: .leading, spacing: Space.s2) {
            Text("DEMURRAGE · FREE TIME METER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            LifecycleCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(free)h free time · \(accrued)h accrued").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text("$\(Int(charge))").font(EType.bodyStrong).monospacedDigit()
                            .foregroundStyle(charge > 0 ? Brand.warning : Brand.success)
                    }
                    ProgressView(value: Double(accrued), total: Double(max(free, 1))).tint(LinearGradient.primary)
                    Text("In transit — meter starts on yard placement at destination")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: updating ? "Updating…" : "Update status", leadingIcon: "arrow.triangle.2.circlepath", action: { Task { await updateStatus() } })
            CTAButton(title: "Waybill", leadingIcon: "doc.text")
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct DetailIn: Encodable { let id: Int }
        struct CarsIn: Encodable { let limit: Int; let offset: Int }
        struct CarsOut: Decodable { let railcars: [RailCar553]; let total: Int }
        do {
            let d: RailShipmentDetail553 = try await EusoTripAPI.shared.query(
                "railShipments.getRailShipmentDetail", input: DetailIn(id: shipmentId))
            self.detail = d
            let carsOut: CarsOut = try await EusoTripAPI.shared.query(
                "railShipments.getRailcars", input: CarsIn(limit: 50, offset: 0))
            self.cars = carsOut.railcars
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func updateStatus() async {
        updating = true
        struct StatusIn: Encodable { let id: Int; let status: String }
        struct Empty553: Decodable {}
        do {
            _ = try await EusoTripAPI.shared.mutation(
                "railShipments.updateRailShipmentStatus",
                input: StatusIn(id: shipmentId, status: "at_interchange")) as Empty553
            await load()
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        updating = false
    }
}

#Preview("553 · Rail Shipment Detail · Night") { RailShipmentDetailCarrierScreen(theme: Theme.dark, shipmentId: 48231).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("553 · Rail Shipment Detail · Light") { RailShipmentDetailCarrierScreen(theme: Theme.light, shipmentId: 48231).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
