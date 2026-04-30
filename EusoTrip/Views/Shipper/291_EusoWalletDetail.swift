//
//  291_EusoWalletDetail.swift
//  EusoTrip — Shipper · EusoWallet detail (Arc G).
//  Backed by `eusoWallet.getSnapshot` + `eusoWallet.listTransactions`.
//

import SwiftUI

struct EusoWalletDetailScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { EusoWalletDetailBody() } nav: { shipperLifecycleNav() }
    }
}

private struct WalletSnapshot: Decodable, Hashable {
    let companyId: Int?
    let available: Double?
    let pending: Double?
    let reserved: Double?
    let totalLifetime: Double?
}

private struct ShipperWalletTxn: Decodable, Identifiable, Hashable {
    let id: Int
    let type: String?
    let amount: Double
    let memo: String?
    let createdAt: String?
}

private struct EusoWalletDetailBody: View {
    @Environment(\.palette) private var palette
    @State private var snap: WalletSnapshot? = nil
    @State private var txns: [ShipperWalletTxn] = []
    @State private var loading: Bool = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let s = snap { snapshotCard(s) }
                else if loading { LifecycleCard { Text("Loading wallet snapshot…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                txnsCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "wallet.pass").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · EUSOWALLET DETAIL").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("EusoWallet").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func snapshotCard(_ s: WalletSnapshot) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "SNAPSHOT", icon: "creditcard.fill")
            LifecycleRow(label: "Available", value: usd(s.available))
            LifecycleRow(label: "Pending",   value: usd(s.pending))
            LifecycleRow(label: "Reserved",  value: usd(s.reserved))
            LifecycleRow(label: "Lifetime",  value: usd(s.totalLifetime))
        }
    }

    private var txnsCard: some View {
        LifecycleCard {
            LifecycleSection(label: "TRANSACTIONS", icon: "list.bullet")
            if txns.isEmpty {
                Text("No transactions yet.").font(EType.caption).foregroundStyle(palette.textSecondary)
            } else {
                ForEach(txns.prefix(20)) { t in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dashIfEmpty(t.type?.uppercased())).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                            Text(dashIfEmpty(t.memo)).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                            Text(humanISO(t.createdAt)).font(EType.mono(.micro)).tracking(0.4).foregroundStyle(palette.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Text((t.amount >= 0 ? "+" : "") + usd(t.amount)).font(.system(size: 13, weight: .heavy)).foregroundStyle(t.amount >= 0 ? palette.textPrimary : Brand.danger).monospacedDigit()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            async let s: WalletSnapshot = EusoTripAPI.shared.queryNoInput("eusoWallet.getSnapshot")
            async let ts: [ShipperWalletTxn]    = EusoTripAPI.shared.queryNoInput("eusoWallet.listTransactions")
            snap = try await s
            txns = (try? await ts) ?? []
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("291 · EusoWallet detail · Night") {
    EusoWalletDetailScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("291 · EusoWallet detail · Afternoon") {
    EusoWalletDetailScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
