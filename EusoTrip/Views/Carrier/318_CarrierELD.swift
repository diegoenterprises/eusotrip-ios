//
//  318_CarrierELD.swift
//  EusoTrip — Carrier · ELD fleet status (Geotab / Samsara / Motive / Omnitracs / EROAD).
//

import SwiftUI

struct CarrierELDScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ELDBody() } nav: {
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

private struct ELDDevice: Decodable, Identifiable, Hashable {
    let id: String
    let truckNumber: String
    let driverName: String?
    let provider: String         // geotab / samsara / motive / omnitracs / eroad
    let dutyStatus: String       // OFF / ON / DRIVING / SLEEPER
    let hosRemainingHours: Double?
    let lastPing: String?
    let lastLocation: String?
    let connectivity: String?    // "online" / "offline"
}

private struct ELDBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [ELDDevice] = []
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
                Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · ELD FLEET").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("ELD fleet status").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Live HOS state across every truck. Drivers in DRIVING with <1h HOS remaining surface in red.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading ELD…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if rows.isEmpty { EusoEmptyState(systemImage: "antenna.radiowaves.left.and.right", title: "No ELD devices", subtitle: "Connect Geotab / Samsara / Motive via the integrations registry to populate this list.") }
        else {
            ForEach(rows) { d in
                let warn = d.dutyStatus == "DRIVING" && (d.hosRemainingHours ?? 0) < 1
                LifecycleCard(accentDanger: warn) {
                    LifecycleSection(label: "TRUCK \(d.truckNumber.uppercased())", icon: "truck.box")
                    LifecycleRow(label: "Driver",          value: dashIfEmpty(d.driverName))
                    LifecycleRow(label: "Provider",        value: d.provider.uppercased())
                    LifecycleRow(label: "Status",          value: d.dutyStatus.uppercased())
                    LifecycleRow(label: "HOS remaining",    value: d.hosRemainingHours.map { String(format: "%.1f hr", $0) } ?? "—")
                    LifecycleRow(label: "Connectivity",     value: dashIfEmpty(d.connectivity?.uppercased()))
                    LifecycleRow(label: "Last ping",        value: humanISO(d.lastPing))
                    LifecycleRow(label: "Last location",    value: dashIfEmpty(d.lastLocation))
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [ELDDevice] = try await EusoTripAPI.shared.api.queryNoInput("catalysts.getELDFleet")
            rows = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("318 · ELD · Night") { CarrierELDScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("318 · ELD · Afternoon") { CarrierELDScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
