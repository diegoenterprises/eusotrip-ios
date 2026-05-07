//
//  422_MyTerminals.swift
//  EusoTrip — Shipper · My terminals (rack access + partnerships).
//

import SwiftUI

struct MyTerminalsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { MyTerminalsBody() } nav: { shipperLifecycleNav() }
    }
}

private struct TerminalRow: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let address: String?
    let products: [String]?
    let rackAccessGranted: Bool?
    let partnershipStatus: String?
}

private struct MyTerminalsBody: View {
    @Environment(\.palette) private var palette
    @State private var terminals: [TerminalRow] = []
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
                Image(systemName: "building.2.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · MY TERMINALS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Terminal partnerships").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading terminals…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if terminals.isEmpty { EusoEmptyState(systemImage: "building.2", title: "No terminal partnerships", subtitle: "Search 1,400+ facilities at /facility-search to add a partnership.") }
        else {
            ForEach(terminals) { t in
                LifecycleCard(accentGradient: t.rackAccessGranted == true) {
                    LifecycleSection(label: t.name.uppercased(), icon: "building.2")
                    LifecycleRow(label: "Address",      value: dashIfEmpty(t.address))
                    LifecycleRow(label: "Products",     value: (t.products ?? []).joined(separator: ", ").isEmpty ? "—" : (t.products ?? []).joined(separator: ", "))
                    LifecycleRow(label: "Rack access",  value: t.rackAccessGranted == true ? "Granted" : "Pending")
                    LifecycleRow(label: "Partnership",  value: dashIfEmpty(t.partnershipStatus?.uppercased()))
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [TerminalRow] = try await EusoTripAPI.shared.queryNoInput("shippers.getMyTerminals")
            terminals = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("422 · My terminals · Night") { MyTerminalsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("422 · My terminals · Afternoon") { MyTerminalsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
