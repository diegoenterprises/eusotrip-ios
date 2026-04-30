//
//  319_CarrierDriversList.swift
//  EusoTrip — Carrier · Drivers list.
//

import SwiftUI

struct CarrierDriversListScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { DriversListBody() } nav: {
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

private struct CarrierDriver: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let cdlClass: String?
    let cdlState: String?
    let cdlExpires: String?
    let medicalExpires: String?
    let hazmatEndorsement: Bool?
    let safetyScore: Double?
    let isActive: Bool
}

private struct DriversListBody: View {
    @Environment(\.palette) private var palette
    @State private var drivers: [CarrierDriver] = []
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
                Image(systemName: "person.3.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · DRIVERS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("My drivers").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading drivers…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if drivers.isEmpty { EusoEmptyState(systemImage: "person.3", title: "No drivers", subtitle: "Hire drivers via /authority or invite via /referrals.") }
        else {
            ForEach(drivers) { d in
                LifecycleCard(accentGradient: d.isActive) {
                    LifecycleSection(label: d.name.uppercased(), icon: "person")
                    LifecycleRow(label: "CDL",         value: "\(dashIfEmpty(d.cdlClass)) · \(dashIfEmpty(d.cdlState))")
                    LifecycleRow(label: "CDL expires", value: humanISO(d.cdlExpires, format: "MMM d, yyyy"))
                    LifecycleRow(label: "Medical",     value: humanISO(d.medicalExpires, format: "MMM d, yyyy"))
                    LifecycleRow(label: "Hazmat",      value: d.hazmatEndorsement == true ? "Endorsed" : "—")
                    LifecycleRow(label: "Safety score", value: d.safetyScore.map { String(format: "%.2f", $0) } ?? "—")
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [CarrierDriver] = try await EusoTripAPI.shared.queryNoInput("catalysts.getMyDrivers")
            drivers = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("319 · Drivers · Night") { CarrierDriversListScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("319 · Drivers · Afternoon") { CarrierDriversListScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
