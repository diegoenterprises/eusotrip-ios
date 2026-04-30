//
//  383_ContractDetail.swift
//  EusoTrip — Shipper · Contract detail (Arc N).
//

import SwiftUI

struct ContractDetailScreen: View {
    let theme: Theme.Palette
    let contractId: String
    var body: some View {
        Shell(theme: theme) { ContractDetailBody(contractId: contractId) } nav: { shipperLifecycleNav() }
    }
}

private struct Contract: Decodable, Hashable {
    let id: String
    let name: String?
    let counterparty: String?
    let status: String?
    let startDate: String?
    let endDate: String?
    let volumeCommittedUsd: Double?
    let volumeActualUsd: Double?
    let lanes: [Lane]?
    let notes: String?
    struct Lane: Decodable, Hashable, Identifiable {
        let id: String
        let origin: String?
        let destination: String?
        let rateUsd: Double?
    }
}

private struct ContractDetailBody: View {
    @Environment(\.palette) private var palette
    let contractId: String
    @State private var contract: Contract? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading { LifecycleCard { Text("Loading contract…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let c = contract { summaryCard(c); lanesCard(c); notesCard(c) }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.below.ecg").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · CONTRACT DETAIL").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(contract?.name ?? "—").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func summaryCard(_ c: Contract) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "TERMS", icon: "doc.text")
            LifecycleRow(label: "Counterparty", value: dashIfEmpty(c.counterparty))
            LifecycleRow(label: "Status",        value: dashIfEmpty(c.status?.uppercased()))
            LifecycleRow(label: "Start",         value: humanISO(c.startDate, format: "MMM d, yyyy"))
            LifecycleRow(label: "End",           value: humanISO(c.endDate, format: "MMM d, yyyy"))
            LifecycleRow(label: "Committed",     value: usd(c.volumeCommittedUsd))
            LifecycleRow(label: "Actual",        value: usd(c.volumeActualUsd))
        }
    }

    @ViewBuilder
    private func lanesCard(_ c: Contract) -> some View {
        if let lanes = c.lanes, !lanes.isEmpty {
            LifecycleCard {
                LifecycleSection(label: "LANES", icon: "map")
                ForEach(lanes) { l in
                    LifecycleRow(label: "\(dashIfEmpty(l.origin)) → \(dashIfEmpty(l.destination))", value: usd(l.rateUsd))
                }
            }
        }
    }

    @ViewBuilder
    private func notesCard(_ c: Contract) -> some View {
        if let n = c.notes, !n.isEmpty {
            LifecycleCard {
                LifecycleSection(label: "NOTES", icon: "text.alignleft")
                Text(n).font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let id: String }
        do {
            let c: Contract = try await EusoTripAPI.shared.query("shipperContracts.getById", input: In(id: contractId))
            contract = c
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("383 · Contract detail · Night") { ContractDetailScreen(theme: Theme.dark, contractId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("383 · Contract detail · Afternoon") { ContractDetailScreen(theme: Theme.light, contractId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
