//
//  310_CarrierAssignDriver.swift
//  EusoTrip — Carrier · Assign driver to load.
//
//  Cross-role chain: carrier picks driver → catalysts.assignDriver →
//  emits LOAD_ASSIGNED + DRIVER_LOAD_ASSIGNED → driver's TripLifecycle
//  store hydrates the load → shipper's getLifecycleSnapshot.driver
//  populates → broker (if any) commission queue advances.
//
//  Reshaped 2026-05-23 from tap-to-select + bottom CTA into a
//  single-drop-zone-above-list pattern. The "ASSIGN TO LOAD" tile
//  at the top doubles as the per-load context label + the
//  .dropDestination target — drag a driver card up onto it to
//  fire catalysts.assignDriver in one gesture. Tap-to-select +
//  Assign CTA preserved as fallback.
//
//  Companion shape to 702_DispatchLoadAssignment (which is many-loads
//  many-drivers pair-drop). 310 is the one-load many-drivers
//  variant — same DnD primitive, different cardinality.
//

import SwiftUI

struct CarrierAssignDriverScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) { AssignDriverBody(loadId: loadId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Bids", systemImage: "hand.raised.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct AvailableDriver: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let cdlClass: String?
    let hazmatEndorsement: Bool?
    let hosRemainingHours: Double?
    let truckNumber: String?
    let lastKnownCity: String?
}

private struct AssignDriverBody: View {
    @Environment(\.palette) private var palette
    let loadId: String
    @State private var drivers: [AvailableDriver] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var selected: String? = nil
    @State private var assigning = false
    @State private var actionError: String? = nil
    @State private var assigned = false
    @State private var lastAssigned: String? = nil
    /// True while a driver card is hovering over the drop zone.
    @State private var dropHover: Bool = false
    /// The driver currently being dragged (for inline hover label).
    @State private var draggingDriverId: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let m = lastAssigned {
                    LifecycleCard(accentGradient: true) {
                        Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
                    }
                } else if assigned {
                    LifecycleCard(accentGradient: true) {
                        Text("Driver assigned. Driver app + shipper notified via realtime.")
                            .font(EType.body)
                            .foregroundStyle(palette.textPrimary)
                    }
                }
                if let err = actionError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                }
                dropZone
                content
                ctaRow
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
                Image(systemName: "person.fill.badge.plus")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · ASSIGN DRIVER · LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Pick a driver")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Drag a driver card up onto the ASSIGN TO LOAD tile to fire LOAD_ASSIGNED in one gesture. Or tap to select + Assign.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dropZone: some View {
        let hoveringName = draggingDriverId.flatMap { id in drivers.first(where: { $0.id == id })?.name }
        return HStack(spacing: 10) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 44, height: 44)
                .background(palette.bgCardSoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("ASSIGN TO LOAD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("LD-\(loadId)")
                    .font(.system(size: 16, weight: .heavy).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                if dropHover, let n = hoveringName {
                    Text("Release to assign \(n)")
                        .font(EType.caption)
                        .foregroundStyle(LinearGradient.diagonal)
                } else {
                    Text("Drop a driver card here")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
            if assigning {
                ProgressView().scaleEffect(0.8)
            } else {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(dropHover ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    dropHover ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint),
                    lineWidth: dropHover ? 2 : 1
                )
                .animation(.easeOut(duration: 0.12), value: dropHover)
        )
        .dropDestination(for: String.self) { droppedIds, _ in
            guard let driverId = droppedIds.first else { return false }
            guard drivers.contains(where: { $0.id == driverId }) else { return false }
            Task { await assign(driverId: driverId) }
            return true
        } isTargeted: { hovering in
            dropHover = hovering
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            LifecycleCard {
                Text("Loading drivers…")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        } else if let err = loadError {
            LifecycleCard(accentDanger: true) {
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            }
        } else if drivers.isEmpty {
            EusoEmptyState(
                systemImage: "person.crop.circle",
                title: "No available drivers",
                subtitle: "Drivers in OFF_DUTY or ON_DUTY (not driving) state surface here."
            )
        } else {
            ForEach(drivers) { d in
                Button { selected = d.id } label: { driverCard(d) }
                    .buttonStyle(.plain)
                    .draggable(d.id) {
                        driverCard(d)
                            .frame(maxWidth: 320)
                            .opacity(0.92)
                            .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                    }
                    .onDrag {
                        draggingDriverId = d.id
                        return NSItemProvider(object: d.id as NSString)
                    }
            }
        }
    }

    private func driverCard(_ d: AvailableDriver) -> some View {
        LifecycleCard(accentGradient: selected == d.id) {
            HStack {
                Image(systemName: selected == d.id ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected == d.id ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.name).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text("\(dashIfEmpty(d.cdlClass)) · HOS \(d.hosRemainingHours.map { String(format: "%.1fh", $0) } ?? "—") remaining")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                    if let truck = d.truckNumber, !truck.isEmpty {
                        Text("Truck \(truck) · \(dashIfEmpty(d.lastKnownCity))")
                            .font(EType.mono(.micro)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                Spacer(minLength: 0)
                if d.hazmatEndorsement == true {
                    Text("HAZMAT")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Brand.warning).clipShape(Capsule())
                }
            }
        }
    }

    private var ctaRow: some View {
        Button { Task { await assignSelected() } } label: {
            HStack(spacing: 6) {
                if assigning { ProgressView().tint(.white) }
                Text(assigning ? "Assigning…" : "Assign driver")
                    .font(.system(size: 13, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(assigning || selected == nil)
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [AvailableDriver] = try await EusoTripAPI.shared.queryNoInput("catalysts.getAvailableDrivers")
            drivers = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func assignSelected() async {
        guard let driverId = selected else { return }
        await assign(driverId: driverId)
    }

    private func assign(driverId: String) async {
        await MainActor.run { assigning = true; actionError = nil }
        let driverLabel = drivers.first(where: { $0.id == driverId })?.name ?? "driver \(driverId)"
        struct In: Encodable { let loadId: String; let driverId: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "catalysts.assignDriver",
                input: In(loadId: loadId, driverId: driverId)
            )
            await MainActor.run {
                assigned = true
                lastAssigned = "\(driverLabel) → LD-\(loadId)"
                draggingDriverId = nil
                selected = nil
            }
        } catch {
            await MainActor.run {
                actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
        }
        await MainActor.run { assigning = false }
    }
}

#Preview("310 · Assign driver · Night") { CarrierAssignDriverScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("310 · Assign driver · Afternoon") { CarrierAssignDriverScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
