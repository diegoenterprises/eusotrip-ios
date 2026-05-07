//
//  288_CatalystContact.swift
//  EusoTrip — Shipper · Catalyst contact (Arc F).
//

import SwiftUI

struct CatalystContactScreen: View {
    let theme: Theme.Palette
    let catalystId: String
    var body: some View {
        Shell(theme: theme) { CatalystContactBody(catalystId: catalystId) } nav: { shipperLifecycleNav() }
    }
}

private struct CatalystContactBody: View {
    @Environment(\.palette) private var palette
    let catalystId: String
    @State private var fav: ShipperAPI.FavoriteCatalyst? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "phone.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · CATALYST · CONTACT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(fav?.name ?? "—").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            LifecycleCard { Text("Loading carrier contact…").font(EType.caption).foregroundStyle(palette.textSecondary) }
        } else if let err = loadError {
            LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
        } else if let f = fav {
            LifecycleCard(accentGradient: true) {
                LifecycleSection(label: "CARRIER", icon: "person.fill")
                LifecycleRow(label: "Name",  value: f.name)
                LifecycleRow(label: "USDOT", value: dashIfEmpty(f.dotNumber))
                LifecycleRow(label: "Loads", value: "\(f.loadsCompleted) delivered")
                LifecycleRow(label: "Spend", value: "$\(Int(f.totalSpend))")
            }
            // Tel deep-link only when phone is on file. This row hits
            // the future `companies.getById(catalystId)` endpoint when
            // wired — keeping doctrine: never invent a phone.
            LifecycleCard {
                LifecycleSection(label: "DIRECT LINE", icon: "phone")
                Text("Carrier dispatch phone is not yet exposed on the favorite catalyst projection. Tap any active load with this carrier to reach their dispatcher.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            LifecycleCard {
                Text("Carrier not in your favorites yet.").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let rs = try await EusoTripAPI.shared.shipper.getFavoriteCatalysts()
            fav = rs.first(where: { $0.catalystId == catalystId })
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("288 · Contact · Night") {
    CatalystContactScreen(theme: Theme.dark, catalystId: "car_1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("288 · Contact · Afternoon") {
    CatalystContactScreen(theme: Theme.light, catalystId: "car_1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
