//
//  286_AddFavoriteCatalyst.swift
//  EusoTrip — Shipper · Add favorite catalyst (Arc F).
//

import SwiftUI

struct AddFavoriteCatalystScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { AddFavoriteBody() } nav: { shipperLifecycleNav() }
    }
}

private struct AddFavoriteBody: View {
    @Environment(\.palette) private var palette
    @StateObject private var perf = ShipperCatalystPerformanceStore()
    @State private var processing: String? = nil
    @State private var success: String? = nil
    @State private var actionError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let s = success { successCard(s) }
                if let err = actionError { errorCard(err) }
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await perf.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "star.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · ADD FAVORITE CATALYST").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Pick a carrier to favorite").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        let rows = perf.state.value ?? []
        if rows.isEmpty {
            EusoEmptyState(systemImage: "person.3", title: "No carriers yet", subtitle: "Once you tender to carriers and they deliver, they'll appear here for favoriting.")
        } else {
            ForEach(rows) { row in
                Button { Task { await favorite(row.catalystId) } } label: {
                    LifecycleCard {
                        HStack {
                            Text(row.name).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                            Spacer(minLength: 0)
                            if processing == row.catalystId {
                                ProgressView().tint(palette.textPrimary)
                            } else {
                                Image(systemName: "plus.circle.fill").foregroundStyle(LinearGradient.diagonal)
                            }
                        }
                    }
                }.buttonStyle(.plain).disabled(processing != nil)
            }
        }
    }

    private func successCard(_ s: String) -> some View {
        LifecycleCard(accentGradient: true) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(LinearGradient.diagonal)
                Text(s).font(EType.caption).foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
            }
        }
    }

    private func errorCard(_ err: String) -> some View {
        LifecycleCard(accentDanger: true) {
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
        }
    }

    private func favorite(_ id: String) async {
        processing = id
        success = nil; actionError = nil
        do {
            let r = try await EusoTripAPI.shared.shipper.addFavoriteCatalyst(catalystId: id)
            success = "Favorite recorded — \(r.catalystId)"
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        processing = nil
    }
}

#Preview("286 · Add favorite · Night") {
    AddFavoriteCatalystScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("286 · Add favorite · Afternoon") {
    AddFavoriteCatalystScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
