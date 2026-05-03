//
//  404_BrokerCommissionQueue.swift
//  EusoTrip — Broker · Commission queue.
//
//  Cross-role chain: load delivers → settlement-builder cron splits
//  shipper-broker contract from broker-carrier contract → broker
//  commission row appears here → on payable date the wallet credits
//  fire (financial:commission_paid event).
//

import SwiftUI

struct BrokerCommissionQueueScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { CommissionQueueBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Carriers", systemImage: "person.3.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

private struct Commission: Decodable, Identifiable, Hashable {
    let id: String
    let loadNumber: String?
    let shipperPay: Double?
    let carrierPay: Double?
    let margin: Double?
    let payableDate: String?
    let paidAt: String?
    let status: String       // "pending" / "approved" / "paid"
}

private struct CommissionQueueBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    @State private var rows: [Commission] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var showSignOutConfirm: Bool = false

    private var totalPending: Double {
        rows.filter { $0.status != "paid" }.compactMap { $0.margin }.reduce(0, +)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if !rows.isEmpty {
                    LifecycleCard(accentGradient: true) {
                        LifecycleSection(label: "PENDING COMMISSION", icon: "creditcard.fill")
                        Text(usd(totalPending)).font(.system(size: 32, weight: .heavy)).foregroundStyle(palette.textPrimary).monospacedDigit()
                    }
                }
                content
                meSection
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .alert("Sign out?", isPresented: $showSignOutConfirm) {
            Button("Sign out", role: .destructive) {
                Task { await session.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign back in to see broker tenders + commissions.")
        }
    }

    /// "Me" section — bottom-nav `Me` slot routes here (per
    /// `BrokerNavRoute.map`'s `me → 404` mapping). Until a dedicated
    /// 420_BrokerMe screen ships, this section gives the broker a
    /// real way out: sign out + (in follow-up bricks) profile,
    /// settings, contracts, contacts. Mirrors the shipper 320_MeHome
    /// `SETTINGS` cell-group pattern.
    private var meSection: some View {
        LifecycleCard {
            LifecycleSection(label: "ME · ACCOUNT", icon: "person.crop.circle")
            VStack(spacing: 8) {
                if let name = session.user?.firstName, !name.isEmpty {
                    HStack {
                        Text("Signed in as")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                        Spacer(minLength: 0)
                        Text(name)
                            .font(EType.body.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                    }
                }
                Button { showSignOutConfirm = true } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundStyle(Brand.danger)
                        Text("Sign out")
                            .font(EType.body.weight(.semibold))
                            .foregroundStyle(Brand.danger)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sign out of broker account")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("BROKER · COMMISSION QUEUE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Commission queue").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading commissions…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if rows.isEmpty { EusoEmptyState(systemImage: "tray", title: "No commissions yet", subtitle: "When loads you brokered close, your margin shows up here.") }
        else {
            ForEach(rows) { c in
                LifecycleCard {
                    LifecycleSection(label: dashIfEmpty(c.loadNumber).uppercased(), icon: "doc.text")
                    LifecycleRow(label: "Shipper pay",  value: usd(c.shipperPay))
                    LifecycleRow(label: "Carrier pay",  value: usd(c.carrierPay))
                    LifecycleRow(label: "Margin",        value: usd(c.margin))
                    LifecycleRow(label: "Status",        value: c.status.uppercased())
                    LifecycleRow(label: "Payable",       value: humanISO(c.payableDate))
                    LifecycleRow(label: "Paid",          value: humanISO(c.paidAt))
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [Commission] = try await EusoTripAPI.shared.queryNoInput("brokers.getCommissionQueue")
            rows = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("404 · Commission · Night") { BrokerCommissionQueueScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("404 · Commission · Afternoon") { BrokerCommissionQueueScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
