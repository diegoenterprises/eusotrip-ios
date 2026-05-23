//
//  320_CarrierVehiclesList.swift
//  EusoTrip — Carrier · Vehicles list (trucks + trailers).
//
//  Reshaped 2026-05-23 from a flat scrolling list into a 4-column
//  lifecycle Kanban backed by the real `vehicles.updateStatus`
//  mutation. The server already enums status to
//  available/in_use/maintenance/out_of_service and emits the
//  VEHICLE_STATUS_CHANGED realtime event on the fleet + dispatch
//  channels, so a drag between columns flips the row + fans the
//  state change to every other client signed into the same
//  company.
//
//  Drag transitions (all wired):
//    AVAILABLE       ⇄ MAINTENANCE / OUT OF SERVICE
//    MAINTENANCE     ⇄ AVAILABLE / OUT OF SERVICE
//    OUT OF SERVICE  ⇄ AVAILABLE / MAINTENANCE
//
//  IN USE is system-managed (auto-flipped when a vehicle gets
//  assigned to a load via dispatch.assignDriver). Dragging a
//  vehicle INTO the IN USE column from another lane is a no-op
//  because there's no load-context to commit to. Dragging an
//  IN USE vehicle OUT to any other lane is allowed — that "frees"
//  the vehicle from the current assignment (server's
//  `vehicles.updateStatus` accepts this; the assignment fan-out
//  separately marks the load as unassigned).
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

private struct VehicleKanbanColumn: Identifiable, Hashable {
    let id: String           // matches server status enum
    let label: String
    let icon: String
    let acceptsDrops: Bool   // false for IN USE (system-managed lane)
}

private let vehicleKanbanColumns: [VehicleKanbanColumn] = [
    .init(id: "available",      label: "AVAILABLE",      icon: "checkmark.seal.fill",        acceptsDrops: true),
    .init(id: "in_use",         label: "IN USE",         icon: "truck.box.fill",             acceptsDrops: false),
    .init(id: "maintenance",    label: "MAINTENANCE",    icon: "wrench.and.screwdriver.fill", acceptsDrops: true),
    .init(id: "out_of_service", label: "OUT OF SERVICE", icon: "xmark.octagon.fill",         acceptsDrops: true),
]

private struct VehiclesBody: View {
    @Environment(\.palette) private var palette
    @State private var vehicles: [CarrierVehicle] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var selected: String = "available"
    @State private var dragHoverColumn: String? = nil
    @State private var flipping: String? = nil
    @State private var actionError: String? = nil
    @State private var lastFlip: String? = nil

    private var byColumn: [String: [CarrierVehicle]] {
        Dictionary(grouping: vehicles) { $0.status.lowercased() }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    header
                    if let m = lastFlip {
                        LifecycleCard(accentGradient: true) {
                            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
                        }
                    }
                    if let e = actionError {
                        LifecycleCard(accentDanger: true) {
                            Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    }
                    scrubber
                    if loading && vehicles.isEmpty {
                        LifecycleCard {
                            Text("Loading vehicles…")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else if vehicles.isEmpty {
                        EusoEmptyState(
                            systemImage: "truck.box",
                            title: "No vehicles",
                            subtitle: "Add tractors / trailers via the carrier admin or bulk-upload."
                        )
                    } else {
                        columnPager
                            .frame(minHeight: 520)
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, 14).padding(.top, 8)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "truck.box")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · FLEET · LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Fleet vehicles")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Drag a card between columns to flip operational status. IN USE is system-managed by load assignment.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scrubber: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(vehicleKanbanColumns) { col in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { selected = col.id }
                    } label: {
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: col.icon).font(.system(size: 9, weight: .heavy))
                                Text(col.label).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            }
                            Text("\(byColumn[col.id]?.count ?? 0)")
                                .font(.system(size: 13, weight: .heavy)).monospacedDigit()
                        }
                        .foregroundStyle(selected == col.id ? .white : palette.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(selected == col.id ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var columnPager: some View {
        TabView(selection: $selected) {
            ForEach(vehicleKanbanColumns) { col in
                column(col).tag(col.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func column(_ col: VehicleKanbanColumn) -> some View {
        let cards = byColumn[col.id] ?? []
        let isHover = dragHoverColumn == col.id && col.acceptsDrops
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text(col.label)
                        .font(.system(size: 13, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textPrimary)
                    Text("\(cards.count)")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                    Spacer(minLength: 0)
                    if col.acceptsDrops {
                        Text("DROP TO FLIP STATUS")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                    } else {
                        Text("SYSTEM-MANAGED")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                if cards.isEmpty {
                    EusoEmptyState(
                        systemImage: col.icon,
                        title: emptyTitle(col),
                        subtitle: emptySubtitle(col)
                    )
                } else {
                    ForEach(cards) { v in
                        vehicleCard(v, col: col)
                            .draggable(v.id) {
                                vehicleCard(v, col: col)
                                    .frame(maxWidth: 320)
                                    .opacity(0.92)
                                    .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                            }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    isHover ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Color.clear),
                    lineWidth: isHover ? 2 : 0
                )
                .padding(.horizontal, 8)
                .animation(.easeOut(duration: 0.12), value: isHover)
        )
        .dropDestination(for: String.self) { droppedIds, _ in
            guard col.acceptsDrops else { return false }
            guard let vehicleId = droppedIds.first else { return false }
            guard let v = vehicles.first(where: { $0.id == vehicleId }) else { return false }
            if v.status.lowercased() == col.id { return false }
            Task { await flip(v: v, to: col.id) }
            return true
        } isTargeted: { hovering in
            guard col.acceptsDrops else { return }
            dragHoverColumn = hovering ? col.id : (dragHoverColumn == col.id ? nil : dragHoverColumn)
        }
    }

    private func vehicleCard(_ v: CarrierVehicle, col: VehicleKanbanColumn) -> some View {
        let isFlipping = flipping == v.id
        return LifecycleCard(
            accentDanger: col.id == "out_of_service",
            accentWarning: col.id == "maintenance",
            accentGradient: col.id == "available"
        ) {
            LifecycleSection(
                label: v.vehicleNumber.uppercased(),
                icon: v.kind == "trailer" ? "rectangle.split.3x1" : "truck.box"
            )
            LifecycleRow(label: "Type",       value: v.kind.uppercased())
            LifecycleRow(label: "Make",       value: [v.make, v.model, v.year.map { "\($0)" }].compactMap { $0 }.joined(separator: " "))
            LifecycleRow(label: "VIN",        value: dashIfEmpty(v.vin))
            LifecycleRow(label: "Plate",      value: dashIfEmpty(v.plate))
            LifecycleRow(label: "Driver",     value: dashIfEmpty(v.currentDriver))
            LifecycleRow(label: "Inspection", value: humanISO(v.inspectionExpires, format: "MMM d, yyyy"))
            if isFlipping {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6)
                    Text("UPDATING STATUS…")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textSecondary)
                }.padding(.top, 4)
            }
        }
    }

    private func emptyTitle(_ col: VehicleKanbanColumn) -> String {
        switch col.id {
        case "available":      return "Nothing available"
        case "in_use":         return "No active assignments"
        case "maintenance":    return "Nothing in the shop"
        case "out_of_service": return "Nothing red-tagged"
        default:               return "Empty"
        }
    }

    private func emptySubtitle(_ col: VehicleKanbanColumn) -> String {
        switch col.id {
        case "available":      return "Vehicles cleared for dispatch land here. Drag a card from another lane to flip."
        case "in_use":         return "Vehicles assigned to active loads. Status flips back to AVAILABLE on delivery."
        case "maintenance":    return "Drag a card here when a truck heads to the shop."
        case "out_of_service": return "Drag a card here to red-tag a vehicle (inspection failure, accident, etc.)."
        default:               return ""
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

    private func flip(v: CarrierVehicle, to newStatus: String) async {
        await MainActor.run { flipping = v.id; actionError = nil }
        struct In: Encodable { let id: String; let status: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "vehicles.updateStatus",
                input: In(id: v.id, status: newStatus)
            )
            await MainActor.run {
                lastFlip = "\(v.vehicleNumber) → \(newStatus.uppercased().replacingOccurrences(of: "_", with: " "))"
            }
            await load()
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.18)) { selected = newStatus }
            }
        } catch {
            await MainActor.run {
                actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
        }
        await MainActor.run { flipping = nil }
    }
}

#Preview("320 · Vehicles · Night") { CarrierVehiclesListScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("320 · Vehicles · Afternoon") { CarrierVehiclesListScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
