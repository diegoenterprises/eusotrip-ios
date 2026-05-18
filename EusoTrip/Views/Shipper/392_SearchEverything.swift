//
//  392_SearchEverything.swift
//  EusoTrip — Shipper · Search-everything (Arc B+).
//

import SwiftUI

struct SearchEverythingScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { SearchBody() } nav: { shipperLifecycleNav() }
    }
}

private struct SearchBody: View {
    @Environment(\.palette) private var palette
    @State private var query: String = ""
    @State private var recents: [String] = []
    @State private var suggestions: [String] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                searchBar
                if !query.isEmpty {
                    Button { runSearch() } label: {
                        Text("Search '\(query)'").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(LinearGradient.diagonal)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }.buttonStyle(.plain)
                }
                if !recents.isEmpty {
                    LifecycleCard {
                        LifecycleSection(label: "RECENT", icon: "clock")
                        ForEach(recents, id: \.self) { r in
                            Button { query = r; runSearch() } label: {
                                HStack {
                                    Image(systemName: "magnifyingglass").foregroundStyle(palette.textTertiary)
                                    Text(r).font(EType.body).foregroundStyle(palette.textPrimary)
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.up.left").foregroundStyle(palette.textTertiary)
                                }
                                .padding(.vertical, 4)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                LifecycleCard {
                    LifecycleSection(label: "SUGGESTIONS", icon: "sparkles")
                    ForEach(["Open RFPs", "Active hazmat loads", "Late settlements", "Carriers · A-grade", "eSang status query"], id: \.self) { s in
                        Button { query = s; runSearch() } label: {
                            HStack {
                                Image(systemName: "sparkles").foregroundStyle(LinearGradient.diagonal)
                                Text(s).font(EType.body).foregroundStyle(palette.textPrimary)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 4)
                        }.buttonStyle(.plain)
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .onAppear { recents = UserDefaults.standard.stringArray(forKey: "shipper.search.recents") ?? [] }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · SEARCH").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Search everything").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(palette.textTertiary)
            TextField("Loads, carriers, settlements, docs", text: $query)
                .textFieldStyle(.plain)
                .onSubmit { runSearch() }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(palette.textTertiary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func runSearch() {
        guard !query.isEmpty else { return }
        var rs = recents
        if !rs.contains(query) { rs.insert(query, at: 0); rs = Array(rs.prefix(8)) }
        UserDefaults.standard.set(rs, forKey: "shipper.search.recents")
        recents = rs
        NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "393", "query": query])
    }
}

#Preview("392 · Search · Night") { SearchEverythingScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("392 · Search · Afternoon") { SearchEverythingScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
