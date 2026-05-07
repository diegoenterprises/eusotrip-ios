//
//  393_SearchResults.swift
//  EusoTrip — Shipper · Search results (Arc B+).
//

import SwiftUI

struct SearchResultsScreen: View {
    let theme: Theme.Palette
    let query: String
    var body: some View {
        Shell(theme: theme) { ResultsBody(query: query) } nav: { shipperLifecycleNav() }
    }
}

private struct SearchEnvelope: Decodable, Hashable {
    struct Hit: Decodable, Hashable, Identifiable {
        let id: String
        let kind: String      // "load" / "carrier" / "settlement" / "doc"
        let title: String
        let subtitle: String?
        let screenId: String
    }
    let hits: [Hit]
    let total: Int
}

private struct ResultsBody: View {
    @Environment(\.palette) private var palette
    let query: String
    @State private var env: SearchEnvelope? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var filter: String = "all"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                filterStrip
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
                Image(systemName: "magnifyingglass").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · SEARCH RESULTS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("'\(query)'").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            if let total = env?.total { Text("\(total) results").font(EType.caption).foregroundStyle(palette.textSecondary) }
        }
    }

    private var filterStrip: some View {
        let kinds = ["all", "load", "carrier", "settlement", "doc"]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(kinds, id: \.self) { k in
                    Button { filter = k } label: {
                        Text(k.capitalized).font(.system(size: 11, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(filter == k ? .white : palette.textPrimary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(filter == k ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.tintNeutral))
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Searching…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if (env?.hits ?? []).isEmpty { EusoEmptyState(systemImage: "magnifyingglass", title: "No matches", subtitle: "Try a different keyword or remove filters.") }
        else {
            let hits = (env?.hits ?? []).filter { filter == "all" || $0.kind == filter }
            ForEach(hits) { hit in
                Button {
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": hit.screenId, "id": hit.id])
                } label: {
                    LifecycleCard {
                        HStack {
                            Image(systemName: iconFor(hit.kind)).foregroundStyle(LinearGradient.diagonal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hit.title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                                Text(dashIfEmpty(hit.subtitle)).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
                                Text(hit.kind.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private func iconFor(_ kind: String) -> String {
        switch kind {
        case "load":       return "shippingbox"
        case "carrier":    return "person.2"
        case "settlement": return "creditcard"
        case "doc":        return "doc.text"
        default:           return "circle"
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let q: String }
        do {
            let e: SearchEnvelope = try await EusoTripAPI.shared.query("search.global", input: In(q: query))
            env = e
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("393 · Results · Night") { SearchResultsScreen(theme: Theme.dark, query: "UN1203").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("393 · Results · Afternoon") { SearchResultsScreen(theme: Theme.light, query: "UN1203").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
