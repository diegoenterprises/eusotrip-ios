//
//  280_CatalystDirectory.swift
//  EusoTrip — Shipper · Catalyst directory grid (Arc F).
//
//  Pulls `shippers.getCatalystPerformance` (period-aware) + cross-
//  references `shippers.getFavoriteCatalysts` to flag favorited rows.
//  Each row taps into 281 detail.
//

import SwiftUI

struct CatalystDirectoryScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { CatalystDirectoryBody() } nav: { shipperLifecycleNav() }
    }
}

private struct CatalystDirectoryBody: View {
    @Environment(\.palette) private var palette
    @StateObject private var perf = ShipperCatalystPerformanceStore()
    @State private var favorites: Set<String> = []
    @State private var loadingFavs = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task {
            await perf.refresh()
            await loadFavs()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.3.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · CATALYST DIRECTORY").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Carriers you work with").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Ranked by composite score across delivered loads in this window.").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch perf.state {
        case .loading:
            LifecycleCard {
                LifecycleSection(label: "DIRECTORY", icon: "person.3.fill")
                Text("Loading carriers…").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        case .empty:
            EusoEmptyState(systemImage: "person.3", title: "No carriers yet", subtitle: "Once you tender to carriers and they deliver, they'll show up here.")
        case .loaded(let rows):
            ForEach(rows) { row in
                Button {
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "281", "catalystId": row.catalystId])
                } label: { rowView(row) }
                .buttonStyle(.plain)
            }
        case .error(let err):
            LifecycleCard(accentDanger: true) {
                Text((err as? EusoTripAPIError)?.errorDescription ?? err.localizedDescription).font(EType.caption).foregroundStyle(Brand.danger)
            }
        }
    }

    private func rowView(_ row: ShipperAPI.CatalystPerformance) -> some View {
        LifecycleCard(accentGradient: favorites.contains(row.catalystId)) {
            HStack(spacing: 10) {
                Text(initials(row.name))
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(LinearGradient.diagonal).clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(row.name).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                        if favorites.contains(row.catalystId) {
                            Image(systemName: "star.fill").font(.system(size: 10, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                        }
                    }
                    Text("\(row.totalLoads) loads · \(row.delivered) delivered · \(row.onTimeRate)% on-time")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                Text("$\(Int(row.totalSpend))").font(.system(size: 15, weight: .heavy)).foregroundStyle(palette.textPrimary).monospacedDigit()
                Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
            }
        }
    }

    private func initials(_ s: String) -> String {
        s.split(separator: " ").prefix(2).map { String($0.prefix(1)) }.joined().uppercased()
    }

    private func loadFavs() async {
        loadingFavs = true
        do {
            let rs = try await EusoTripAPI.shared.shipper.getFavoriteCatalysts()
            favorites = Set(rs.map(\.catalystId))
        } catch {
            // Tolerate missing favorites — surface the directory as-is.
        }
        loadingFavs = false
    }
}

// ShipperCatalystPerformanceStore moved to LiveDataStores.swift:3798
// (single canonical home). Removed local duplicate to fix ambiguous-
// type-lookup error on 336 GradeDetail.

#Preview("280 · Directory · Night") {
    CatalystDirectoryScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("280 · Directory · Afternoon") {
    CatalystDirectoryScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
