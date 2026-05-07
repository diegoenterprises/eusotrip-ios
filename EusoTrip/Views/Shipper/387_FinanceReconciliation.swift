//
//  387_FinanceReconciliation.swift
//  EusoTrip — Shipper · Finance reconciliation (Arc N).
//
//  Reconciliation dashboard surfaces unmatched escrow holds and
//  flagged settlements + a CTA to dispatch ops on stuck items.
//

import SwiftUI

struct FinanceReconciliationScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ReconcileBody() } nav: { shipperLifecycleNav() }
    }
}

private struct ReconEnvelope: Decodable, Hashable {
    let unmatched: [Item]
    let flagged: [Item]
    let totals: Totals
    struct Totals: Decodable, Hashable {
        let escrowHeld: Double?
        let inFlight: Double?
        let unmatchedAmount: Double?
        let flaggedAmount: Double?
    }
    struct Item: Decodable, Hashable, Identifiable {
        let id: String
        let label: String
        let amount: Double
        let lastEvent: String?
        let kind: String?
    }
}

private struct ReconcileBody: View {
    @Environment(\.palette) private var palette
    @State private var env: ReconEnvelope? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading { LifecycleCard { Text("Pulling reconciliation snapshot…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let e = env { totalsCard(e); section(title: "UNMATCHED", items: e.unmatched, danger: true); section(title: "FLAGGED", items: e.flagged, warning: true) }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.doc.horizontal").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · FINANCE · RECONCILIATION").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Reconciliation").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Tracks unmatched escrow holds + flagged settlements. Stripe Connect splits live on web.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func totalsCard(_ e: ReconEnvelope) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "TOTALS", icon: "creditcard")
            LifecycleRow(label: "Escrow held",       value: usd(e.totals.escrowHeld))
            LifecycleRow(label: "In flight",         value: usd(e.totals.inFlight))
            LifecycleRow(label: "Unmatched amount",  value: usd(e.totals.unmatchedAmount))
            LifecycleRow(label: "Flagged amount",    value: usd(e.totals.flaggedAmount))
        }
    }

    @ViewBuilder
    private func section(title: String, items: [ReconEnvelope.Item], danger: Bool = false, warning: Bool = false) -> some View {
        if !items.isEmpty {
            LifecycleCard(accentDanger: danger, accentWarning: warning) {
                LifecycleSection(label: title, icon: danger ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
                ForEach(items) { it in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(it.label).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                            Text(dashIfEmpty(it.lastEvent)).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text(usd(it.amount)).font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textPrimary).monospacedDigit()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let e: ReconEnvelope = try await EusoTripAPI.shared.queryNoInput("wallet.getReconciliationSnapshot")
            env = e
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("387 · Reconciliation · Night") { FinanceReconciliationScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("387 · Reconciliation · Afternoon") { FinanceReconciliationScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
