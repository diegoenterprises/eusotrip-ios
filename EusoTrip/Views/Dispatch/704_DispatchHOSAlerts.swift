//
//  704_DispatchHOSAlerts.swift
//  EusoTrip — Dispatch · HOS alerts (drivers approaching the wall).
//

import SwiftUI

struct DispatchHOSAlertsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { HOSBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .alert
            )
        }
    }
}

private struct HOSDriver: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let status: String
    let load: String?
    let hoursRemaining: Double?
}

private struct HOSBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [HOSDriver] = []
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
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · HOS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("HOS alerts").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Drivers under 2h remaining are flagged. Reassign before they wall.").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading HOS…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else {
            let critical = rows.filter { ($0.hoursRemaining ?? 999) < 2 }
            let warn = rows.filter { let h = $0.hoursRemaining ?? 999; return h >= 2 && h < 4 }
            let healthy = rows.filter { ($0.hoursRemaining ?? 0) >= 4 }
            if critical.isEmpty && warn.isEmpty && healthy.isEmpty {
                EusoEmptyState(systemImage: "clock", title: "No HOS data", subtitle: "Drivers without ELD telemetry won't show here.")
            } else {
                if !critical.isEmpty {
                    LifecycleCard(accentDanger: true) {
                        LifecycleSection(label: "CRITICAL · UNDER 2H", icon: "exclamationmark.octagon")
                        ForEach(critical) { d in driverLine(d, color: Brand.danger) }
                    }
                }
                if !warn.isEmpty {
                    LifecycleCard {
                        LifecycleSection(label: "WARN · UNDER 4H", icon: "exclamationmark.triangle")
                        ForEach(warn) { d in driverLine(d, color: palette.textPrimary) }
                    }
                }
                if !healthy.isEmpty {
                    LifecycleCard(accentGradient: true) {
                        LifecycleSection(label: "HEALTHY · 4H+", icon: "checkmark.seal")
                        ForEach(healthy) { d in driverLine(d, color: palette.textPrimary) }
                    }
                }
            }
        }
    }

    private func driverLine(_ d: HOSDriver, color: Color) -> some View {
        HStack {
            Text(d.name).font(EType.bodyStrong).foregroundStyle(color)
            Spacer(minLength: 0)
            Text(d.hoursRemaining.map { String(format: "%.1fh", $0) } ?? "—").font(EType.body).foregroundStyle(color).monospacedDigit()
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let limit: Int }
        do {
            let r: [HOSDriver] = try await EusoTripAPI.shared.query("dispatch.getDriverStatuses", input: In(limit: 200))
            rows = r.sorted { ($0.hoursRemaining ?? 999) < ($1.hoursRemaining ?? 999) }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("704 · HOS · Night") { DispatchHOSAlertsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("704 · HOS · Afternoon") { DispatchHOSAlertsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
