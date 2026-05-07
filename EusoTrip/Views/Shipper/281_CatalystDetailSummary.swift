//
//  281_CatalystDetailSummary.swift
//  EusoTrip — Shipper · Catalyst detail · summary (Arc F).
//

import SwiftUI

struct CatalystDetailSummaryScreen: View {
    let theme: Theme.Palette
    let catalystId: String
    var body: some View {
        Shell(theme: theme) { CatalystDetailSummaryBody(catalystId: catalystId) } nav: { shipperLifecycleNav() }
    }
}

private struct CatalystDetailSummaryBody: View {
    @Environment(\.palette) private var palette
    let catalystId: String
    @StateObject private var store = ShipperCatalystPerformanceStore()
    @State private var note: String? = nil

    private var row: ShipperAPI.CatalystPerformance? {
        store.state.value?.first(where: { $0.catalystId == catalystId })
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let r = row { heroCard(r); statsGrid(r); subscreenLinks }
                else { emptyCard }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await store.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · CATALYST DETAIL").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(row?.name ?? "—").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func heroCard(_ r: ShipperAPI.CatalystPerformance) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "PERFORMANCE", icon: "chart.bar.fill")
            LifecycleRow(label: "On-time", value: "\(r.onTimeRate)%")
            LifecycleRow(label: "Delivered", value: "\(r.delivered) of \(r.totalLoads)")
            LifecycleRow(label: "Spend (window)", value: "$\(Int(r.totalSpend))")
        }
    }

    private func statsGrid(_ r: ShipperAPI.CatalystPerformance) -> some View {
        HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "TOTAL", value: "\(r.totalLoads)", icon: "shippingbox")
            LifecycleStatTile(label: "DELIVERED", value: "\(r.delivered)", icon: "checkmark.circle")
            LifecycleStatTile(label: "ON-TIME", value: "\(r.onTimeRate)%", icon: "clock")
        }
    }

    private var emptyCard: some View {
        LifecycleCard {
            Text("Carrier not in this window's directory. Pull-to-refresh or pick another period.")
                .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var subscreenLinks: some View {
        VStack(spacing: 8) {
            link(icon: "list.bullet", title: "Loads history", screenId: "282")
            link(icon: "star.bubble", title: "Ratings & reviews", screenId: "283")
            link(icon: "shield.lefthalf.filled", title: "Compliance peek", screenId: "284")
            link(icon: "chart.line.uptrend.xyaxis", title: "Trend (90 days)", screenId: "285")
            link(icon: "phone.fill", title: "Contact carrier", screenId: "288")
        }
    }

    private func link(icon: String, title: String, screenId: String) -> some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": screenId, "catalystId": catalystId])
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
}

#Preview("281 · Detail summary · Night") {
    CatalystDetailSummaryScreen(theme: Theme.dark, catalystId: "car_1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("281 · Detail summary · Afternoon") {
    CatalystDetailSummaryScreen(theme: Theme.light, catalystId: "car_1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
