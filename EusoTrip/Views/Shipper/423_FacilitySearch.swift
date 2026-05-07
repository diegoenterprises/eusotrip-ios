//
//  423_FacilitySearch.swift
//  EusoTrip — Shipper · Facility search (1,400+ petroleum facilities).
//

import SwiftUI

struct FacilitySearchScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { FacilitySearchBody() } nav: { shipperLifecycleNav() }
    }
}

private struct FacilityHit: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let city: String?
    let state: String?
    let country: String?
    let kind: String?         // "refinery" / "terminal" / "rack" / "port"
    let products: [String]?
}

private struct FacilitySearchBody: View {
    @Environment(\.palette) private var palette
    @State private var query: String = ""
    @State private var hits: [FacilityHit] = []
    @State private var loading = false
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                searchBar
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass.circle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · FACILITY SEARCH").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Facility intelligence").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("1,400+ petroleum / chemical / port facilities. Search by name, product grade, city, or state.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var searchBar: some View {
        TextField("e.g. 'Houston refinery' or 'gasoline 87'", text: $query)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onSubmit { Task { await search() } }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Searching…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if hits.isEmpty && !query.isEmpty { EusoEmptyState(systemImage: "magnifyingglass", title: "No matches", subtitle: "Try a broader keyword.") }
        else if hits.isEmpty { LifecycleCard { Text("Type a query and submit to search 1,400+ facilities.").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else {
            ForEach(hits) { h in
                LifecycleCard {
                    LifecycleSection(label: h.name.uppercased(), icon: kindIcon(h.kind))
                    LifecycleRow(label: "Type",     value: dashIfEmpty(h.kind?.uppercased()))
                    LifecycleRow(label: "Location", value: [h.city, h.state, h.country].compactMap { $0 }.joined(separator: ", "))
                    LifecycleRow(label: "Products", value: (h.products ?? []).joined(separator: ", ").isEmpty ? "—" : (h.products ?? []).joined(separator: ", "))
                }
            }
        }
    }

    private func kindIcon(_ kind: String?) -> String {
        switch (kind ?? "").lowercased() {
        case "refinery": return "drop.fill"
        case "terminal": return "building.2.fill"
        case "rack":     return "fuelpump.fill"
        case "port":     return "ferry.fill"
        default:         return "building"
        }
    }

    private func search() async {
        loading = true; loadError = nil
        struct In: Encodable { let q: String }
        do {
            let r: [FacilityHit] = try await EusoTripAPI.shared.query("facilities.search", input: In(q: query))
            hits = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("423 · Facility search · Night") { FacilitySearchScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("423 · Facility search · Afternoon") { FacilitySearchScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
