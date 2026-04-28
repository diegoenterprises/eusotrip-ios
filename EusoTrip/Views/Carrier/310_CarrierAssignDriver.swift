//
//  310_CarrierAssignDriver.swift
//  EusoTrip — Carrier · Assign driver to load.
//
//  Cross-role chain: carrier picks driver → catalysts.assignDriver →
//  emits LOAD_ASSIGNED + DRIVER_LOAD_ASSIGNED → driver's TripLifecycle
//  store hydrates the load → shipper's getLifecycleSnapshot.driver
//  populates → broker (if any) commission queue advances.
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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if assigned { LifecycleCard(accentGradient: true) { Text("Driver assigned. Driver app + shipper notified via realtime.").font(EType.body).foregroundStyle(palette.textPrimary) } }
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                content
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.fill.badge.plus").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · ASSIGN DRIVER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Pick a driver").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading drivers…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if drivers.isEmpty { EusoEmptyState(systemImage: "person.crop.circle", title: "No available drivers", subtitle: "Drivers in OFF_DUTY or ON_DUTY (not driving) state surface here.") }
        else {
            ForEach(drivers) { d in
                Button { selected = d.id } label: {
                    LifecycleCard(accentGradient: selected == d.id) {
                        HStack {
                            Image(systemName: selected == d.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected == d.id ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.name).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                                Text("\(dashIfEmpty(d.cdlClass)) · HOS \(d.hosRemainingHours.map { String(format: "%.1fh", $0) } ?? "—") remaining")
                                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                                if let truck = d.truckNumber, !truck.isEmpty { Text("Truck \(truck) · \(dashIfEmpty(d.lastKnownCity))").font(EType.mono(.micro)).tracking(0.4).foregroundStyle(palette.textTertiary) }
                            }
                            Spacer(minLength: 0)
                            if d.hazmatEndorsement == true {
                                Text("HAZMAT").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2).background(Brand.warning).clipShape(Capsule())
                            }
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private var ctaRow: some View {
        Button { Task { await assign() } } label: {
            HStack(spacing: 6) {
                if assigning { ProgressView().tint(.white) }
                Text(assigning ? "Assigning…" : "Assign driver").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(assigning || selected == nil)
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [AvailableDriver] = try await EusoTripAPI.shared.api.queryNoInput("catalysts.getAvailableDrivers")
            drivers = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func assign() async {
        guard let driverId = selected else { return }
        assigning = true; actionError = nil
        struct In: Encodable { let loadId: String; let driverId: String }
        struct Out: Decodable { let success: Bool }
        do {
            let _ : Out = try await EusoTripAPI.shared.api.mutation("catalysts.assignDriver", input: In(loadId: loadId, driverId: driverId))
            assigned = true
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        assigning = false
    }
}

#Preview("310 · Assign driver · Night") { CarrierAssignDriverScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("310 · Assign driver · Afternoon") { CarrierAssignDriverScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
