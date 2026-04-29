//
//  702_DispatchLoadAssignment.swift
//  EusoTrip — Dispatch · Unassigned loads → assign driver mutation.
//

import SwiftUI

struct DispatchLoadAssignmentScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { LoadAssignBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct UnassignedLoad: Decodable, Identifiable, Hashable {
    let id: String
    let loadNumber: String
    let origin: String?
    let destination: String?
    let pickupDate: String?
    let rate: Double?
    let mode: String?
}

private struct DriverPick: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let status: String
    let hoursRemaining: Double?
}

private struct LoadAssignBody: View {
    @Environment(\.palette) private var palette
    @State private var loads: [UnassignedLoad] = []
    @State private var drivers: [DriverPick] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var pickFor: UnassignedLoad? = nil
    @State private var assigning: String? = nil
    @State private var actionError: String? = nil
    @State private var lastAssigned: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let msg = lastAssigned { LifecycleCard(accentGradient: true) { Text(msg).font(EType.caption).foregroundStyle(palette.textPrimary) } }
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
        .sheet(item: $pickFor) { l in driverPickerSheet(for: l) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · ASSIGNMENT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Unassigned loads").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Tap a row to pick a driver — assignment fires the LOAD_ASSIGNED socket event.").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading unassigned loads…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if loads.isEmpty {
            EusoEmptyState(systemImage: "checkmark.seal", title: "Inbox at zero", subtitle: "Every active load has a driver. New tenders will land here.")
        } else {
            ForEach(loads) { l in
                Button { pickFor = l } label: {
                    LifecycleCard {
                        LifecycleSection(label: l.loadNumber.uppercased(), icon: "shippingbox")
                        LifecycleRow(label: "Origin",       value: dashIfEmpty(l.origin))
                        LifecycleRow(label: "Destination",  value: dashIfEmpty(l.destination))
                        LifecycleRow(label: "Pickup",       value: humanISO(l.pickupDate))
                        LifecycleRow(label: "Rate",         value: usd(l.rate))
                        LifecycleRow(label: "Mode",         value: dashIfEmpty(l.mode))
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private func driverPickerSheet(for l: UnassignedLoad) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Pick driver for \(l.loadNumber)").font(EType.h3).foregroundStyle(palette.textPrimary).padding(.bottom, 6)
                if drivers.isEmpty {
                    EusoEmptyState(systemImage: "person.3", title: "No available drivers", subtitle: "All drivers are on a load or off-duty.")
                } else {
                    ForEach(drivers) { d in
                        Button { Task { await assign(loadId: l.id, driverId: d.id) } } label: {
                            LifecycleCard {
                                LifecycleSection(label: d.name.uppercased(), icon: "person")
                                LifecycleRow(label: "Status",   value: d.status.uppercased())
                                LifecycleRow(label: "HOS left", value: d.hoursRemaining.map { String(format: "%.1fh", $0) } ?? "—")
                                if assigning == d.id { ProgressView().padding(.top, 6) }
                            }
                        }.buttonStyle(.plain).disabled(assigning != nil)
                    }
                }
            }
            .padding(14)
        }.background(palette.background)
    }

    private func loadAll() async {
        loading = true; loadError = nil
        do {
            async let l: [UnassignedLoad] = EusoTripAPI.shared.api.queryNoInput("dispatch.getUnassignedLoads")
            async let d: [DriverPick] = EusoTripAPI.shared.api.queryNoInput("dispatch.getDriverStatuses")
            let (loadsRes, driversRes) = try await (l, d)
            loads = loadsRes
            drivers = driversRes.filter { $0.status == "available" }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func assign(loadId: String, driverId: String) async {
        assigning = driverId; actionError = nil
        struct In: Encodable { let loadId: String; let driverId: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.api.mutation("dispatch.assignDriver", input: In(loadId: loadId, driverId: driverId))
            lastAssigned = "Assigned · driver \(driverId) → \(pickFor?.loadNumber ?? loadId)"
            pickFor = nil
            await loadAll()
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        assigning = nil
    }
}

#Preview("702 · Load assign · Night") { DispatchLoadAssignmentScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("702 · Load assign · Afternoon") { DispatchLoadAssignmentScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
