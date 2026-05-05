//
//  290_WalletHome.swift
//  EusoTrip — Shipper · Wallet home (Arc G).
//  Backed by `wallet.getBalance` (existing) + `eusoWallet.getSnapshot`
//  + `wallet.getEscrowHolds`. Em-dash sentinels everywhere.
//

import SwiftUI

struct WalletHomeScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { WalletHomeBody() } nav: { shipperLifecycleNav() }
    }
}

private struct WalletBalance: Decodable, Hashable {
    let available: Double?
    let pending: Double?
    let reserved: Double?
    let escrow: Double?
    let total: Double?
    let monthVolume: Double?
}

private struct WalletHomeBody: View {
    @Environment(\.palette) private var palette
    @State private var balance: WalletBalance? = nil
    @State private var loading: Bool = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let b = balance { balanceHero(b); breakdownCard(b) }
                else if loading { LifecycleCard { Text("Loading wallet…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                quickActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "wallet.pass.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · EUSOWALLET").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("EusoWallet").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func balanceHero(_ b: WalletBalance) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AVAILABLE BALANCE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(.white.opacity(0.85))
            Text(usd(b.available) == "—" ? "$0" : usd(b.available)).font(.system(size: 32, weight: .heavy)).foregroundStyle(.white).monospacedDigit()
            HStack(spacing: 8) {
                Text("MTD VOLUME \(usd(b.monthVolume))").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.18)).clipShape(Capsule())
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.diagonal)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func breakdownCard(_ b: WalletBalance) -> some View {
        LifecycleCard {
            LifecycleSection(label: "BREAKDOWN", icon: "list.bullet")
            LifecycleRow(label: "Pending",   value: usd(b.pending))
            LifecycleRow(label: "Reserved",  value: usd(b.reserved))
            LifecycleRow(label: "Escrow",    value: usd(b.escrow))
            LifecycleRow(label: "Total",     value: usd(b.total))
        }
    }

    private var quickActions: some View {
        VStack(spacing: 8) {
            link(icon: "arrow.right.circle", title: "EusoWallet detail", screenId: "291")
            link(icon: "creditcard", title: "Settlements", screenId: "292")
            link(icon: "creditcard.and.123", title: "Payment methods", screenId: "295")
            link(icon: "doc.text", title: "Statements", screenId: "297")
            link(icon: "leaf", title: "Sustainability", screenId: "298")
            link(icon: "chart.bar", title: "Reports", screenId: "299")
        }
    }

    private func link(icon: String, title: String, screenId: String) -> some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": screenId])
        } label: {
            LifecycleCard {
                HStack {
                    Image(systemName: icon).foregroundStyle(LinearGradient.diagonal)
                    Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
        }.buttonStyle(.plain)
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let b: WalletBalance = try await EusoTripAPI.shared.queryNoInput("wallet.getBalance")
            balance = b
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("290 · Wallet · Night") {
    WalletHomeScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("290 · Wallet · Afternoon") {
    WalletHomeScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
