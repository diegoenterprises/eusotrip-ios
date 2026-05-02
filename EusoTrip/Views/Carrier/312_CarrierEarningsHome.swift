//
//  312_CarrierEarningsHome.swift
//  EusoTrip — Carrier · Earnings home (incoming side of EusoWallet).
//

import SwiftUI

struct CarrierEarningsHomeScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { EarningsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Bids", systemImage: "hand.raised.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

private struct CarrierEarningsSummary: Decodable, Hashable {
    let mtdRevenue: Double?
    let ytdRevenue: Double?
    let pendingSettlements: Double?
    let paidLastWeek: Double?
    let pendingClaims: Int?
    let nextSettlementISO: String?
}

private struct EarningsBody: View {
    @Environment(\.palette) private var palette
    @State private var summary: CarrierEarningsSummary? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading { LifecycleCard { Text("Loading earnings…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                else if let s = summary { hero(s); breakdownCard(s) }
                links
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "creditcard.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · EARNINGS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("EusoWallet · Carrier").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func hero(_ s: CarrierEarningsSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MTD REVENUE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(.white.opacity(0.85))
            Text(usd(s.mtdRevenue) == "—" ? "$0" : usd(s.mtdRevenue)).font(.system(size: 32, weight: .heavy)).foregroundStyle(.white).monospacedDigit()
            HStack(spacing: 8) {
                Text("YTD \(usd(s.ytdRevenue))").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.18)).clipShape(Capsule())
                Text("PAID LAST WK \(usd(s.paidLastWeek))").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.18)).clipShape(Capsule())
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.diagonal)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func breakdownCard(_ s: CarrierEarningsSummary) -> some View {
        LifecycleCard {
            LifecycleSection(label: "BREAKDOWN", icon: "list.bullet")
            LifecycleRow(label: "Pending settlements", value: usd(s.pendingSettlements))
            LifecycleRow(label: "Pending claims",       value: "\(s.pendingClaims ?? 0)")
            LifecycleRow(label: "Next settlement",      value: humanISO(s.nextSettlementISO))
        }
    }

    private var links: some View {
        VStack(spacing: 8) {
            link(icon: "creditcard", title: "Settlements", screen: "313")
            link(icon: "fuelpump", title: "Fuel cards", screen: "314")
            link(icon: "wrench.fill", title: "Maintenance (Zeun)", screen: "315")
        }
    }

    private func link(icon: String, title: String, screen: String) -> some View {
        Button {
            NotificationCenter.default.post(name: .eusoCarrierNavSwap, object: nil, userInfo: ["screenId": screen])
        } label: {
            LifecycleCard {
                HStack {
                    Image(systemName: icon).foregroundStyle(LinearGradient.diagonal)
                    Text(title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
                }
            }
        }.buttonStyle(.plain)
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let s: CarrierEarningsSummary = try await EusoTripAPI.shared.queryNoInput("catalysts.getCarrierEarningsSummary")
            summary = s
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("312 · Earnings · Night") { CarrierEarningsHomeScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("312 · Earnings · Afternoon") { CarrierEarningsHomeScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
