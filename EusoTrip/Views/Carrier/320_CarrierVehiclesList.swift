//
//  320_CarrierVehiclesList.swift
//  EusoTrip — Carrier · Vehicles list (trucks + trailers).
//

import SwiftUI

struct CarrierVehiclesListScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VehiclesBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Bids", systemImage: "hand.raised.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

private struct CarrierVehicle: Decodable, Identifiable, Hashable {
    let id: String
    let vehicleNumber: String
    let kind: String          // "tractor" / "trailer"
    let make: String?
    let model: String?
    let year: Int?
    let vin: String?
    let plate: String?
    let status: String        // "available" / "in_use" / "maintenance" / "out_of_service"
    let currentDriver: String?
    let inspectionExpires: String?
}

private struct VehiclesBody: View {
    @Environment(\.palette) private var palette
    @State private var vehicles: [CarrierVehicle] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "truck.box").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · VEHICLES").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Fleet vehicles").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading vehicles…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if vehicles.isEmpty { EusoEmptyState(systemImage: "truck.box", title: "No vehicles", subtitle: "Add tractors / trailers via the carrier admin or bulk-upload.") }
        else {
            ForEach(vehicles) { v in
                LifecycleCard(accentDanger: v.status == "out_of_service", accentWarning: v.status == "maintenance", accentGradient: v.status == "available") {
                    LifecycleSection(label: v.vehicleNumber.uppercased(), icon: v.kind == "trailer" ? "rectangle.split.3x1" : "truck.box")
                    LifecycleRow(label: "Type",     value: v.kind.uppercased())
                    LifecycleRow(label: "Make",     value: [v.make, v.model, v.year.map { "\($0)" }].compactMap { $0 }.joined(separator: " "))
                    LifecycleRow(label: "VIN",      value: dashIfEmpty(v.vin))
                    LifecycleRow(label: "Plate",    value: dashIfEmpty(v.plate))
                    LifecycleRow(label: "Status",   value: v.status.uppercased())
                    LifecycleRow(label: "Driver",   value: dashIfEmpty(v.currentDriver))
                    LifecycleRow(label: "Inspection", value: humanISO(v.inspectionExpires, format: "MMM d, yyyy"))
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [CarrierVehicle] = try await EusoTripAPI.shared.queryNoInput("catalysts.getMyVehicles")
            vehicles = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("320 · Vehicles · Night") { CarrierVehiclesListScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("320 · Vehicles · Afternoon") { CarrierVehiclesListScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
