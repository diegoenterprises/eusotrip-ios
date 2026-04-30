//
//  382_ContractList.swift
//  EusoTrip — Shipper · Contract list (Arc N).
//

import SwiftUI

struct ContractListScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ContractListBody() } nav: { shipperLifecycleNav() }
    }
}

private struct ContractRow: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let counterparty: String?
    let status: String?
    let startDate: String?
    let endDate: String?
    let volumeCommittedUsd: Double?
    let volumeActualUsd: Double?
}

private struct ContractListBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [ContractRow] = []
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
                Image(systemName: "doc.append.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · CONTRACTS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Active contracts").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading contracts…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if rows.isEmpty { EusoEmptyState(systemImage: "doc.text", title: "No contracts", subtitle: "Volume commitments / lane contracts surface here once they're authored on web.") }
        else {
            ForEach(rows) { c in
                Button {
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "383", "contractId": c.id])
                } label: {
                    LifecycleCard {
                        LifecycleSection(label: dashIfEmpty(c.name?.uppercased()), icon: "doc.text")
                        LifecycleRow(label: "Counterparty", value: dashIfEmpty(c.counterparty))
                        LifecycleRow(label: "Status",        value: dashIfEmpty(c.status?.uppercased()))
                        LifecycleRow(label: "Start",         value: humanISO(c.startDate, format: "MMM d, yyyy"))
                        LifecycleRow(label: "End",           value: humanISO(c.endDate, format: "MMM d, yyyy"))
                        LifecycleRow(label: "Committed",     value: usd(c.volumeCommittedUsd))
                        LifecycleRow(label: "Actual",        value: usd(c.volumeActualUsd))
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            // shipperContracts.getSummary returns { contracts: [...] } — adapt
            struct Envelope: Decodable { let contracts: [ContractRow]? }
            let e: Envelope = try await EusoTripAPI.shared.queryNoInput("shipperContracts.getSummary")
            rows = e.contracts ?? []
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("382 · Contracts · Night") { ContractListScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("382 · Contracts · Afternoon") { ContractListScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
