//
//  364_OfflineBanner.swift
//  EusoTrip — Shipper · Offline banner (Arc M).
//

import SwiftUI
import Network

struct OfflineBannerScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { OfflineBody() } nav: { shipperLifecycleNav() }
    }
}

private struct OfflineBody: View {
    @Environment(\.palette) private var palette
    @State private var connected: Bool = true
    @State private var monitor: NWPathMonitor? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                statusCard
                cachedDataCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .onAppear { startMonitor() }
        .onDisappear { monitor?.cancel() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "wifi.exclamationmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(connected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Brand.warning))
                Text("SHIPPER · CONNECTIVITY").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(connected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Brand.warning))
            }
            Text(connected ? "You're online" : "You're offline").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var statusCard: some View {
        LifecycleCard(accentGradient: connected, accentWarning: !connected) {
            LifecycleSection(label: connected ? "ALL CHANNELS LIVE" : "USING CACHED DATA", icon: connected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            LifecycleRow(label: "Network",          value: connected ? "Connected" : "Offline")
            LifecycleRow(label: "Sync",             value: connected ? "Live" : "Paused")
            LifecycleRow(label: "Pending mutations", value: "0")
        }
    }

    private var cachedDataCard: some View {
        LifecycleCard {
            LifecycleSection(label: "WHAT WORKS OFFLINE", icon: "internaldrive")
            VStack(alignment: .leading, spacing: 6) {
                row(text: "Active loads (last refresh)")
                row(text: "Recent settlements")
                row(text: "Saved lane templates")
                row(text: "Documents cached on this device")
            }
            Text("Mutations queue locally and replay when connectivity returns.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func row(text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "checkmark.circle").foregroundStyle(LinearGradient.diagonal)
            Text(text).font(EType.body).foregroundStyle(palette.textPrimary)
        }
    }

    private func startMonitor() {
        let m = NWPathMonitor()
        m.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                connected = path.status == .satisfied
            }
        }
        let q = DispatchQueue(label: "eusotrip.network.monitor")
        m.start(queue: q)
        monitor = m
    }
}

#Preview("364 · Offline · Night") { OfflineBannerScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("364 · Offline · Afternoon") { OfflineBannerScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
