//
//  395_QuoteSaved.swift
//  EusoTrip — Shipper · Saved quotes (Arc B+).
//

import SwiftUI

struct QuoteSavedScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { QuoteSavedBody() } nav: { shipperLifecycleNav() }
    }
}

private struct SavedQuote: Decodable, Identifiable, Hashable {
    let id: String
    let origin: String?
    let destination: String?
    let equipmentType: String?
    let midUsd: Double?
    let createdAt: String?
}

private struct QuoteSavedBody: View {
    @Environment(\.palette) private var palette
    @State private var quotes: [SavedQuote] = []
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
                Image(systemName: "bookmark.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · SAVED QUOTES").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Saved quotes").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading saved quotes…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if quotes.isEmpty { EusoEmptyState(systemImage: "bookmark", title: "No saved quotes", subtitle: "Tap the bookmark on a quote result to save it here for re-runs.") }
        else {
            ForEach(quotes) { q in
                Button {
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "394", "quoteId": q.id])
                } label: {
                    LifecycleCard {
                        LifecycleSection(label: "\(dashIfEmpty(q.origin)) → \(dashIfEmpty(q.destination))", icon: "arrow.right")
                        LifecycleRow(label: "Equipment", value: dashIfEmpty(q.equipmentType))
                        LifecycleRow(label: "Mid-rate",  value: usd(q.midUsd))
                        LifecycleRow(label: "Saved",     value: humanISO(q.createdAt))
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [SavedQuote] = try await EusoTripAPI.shared.queryNoInput("predictivePricing.listSavedQuotes")
            quotes = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("395 · Saved quotes · Night") { QuoteSavedScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("395 · Saved quotes · Afternoon") { QuoteSavedScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
