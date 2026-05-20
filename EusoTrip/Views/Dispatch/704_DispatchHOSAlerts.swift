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
                orbState: .idle
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
    /// T-022 · 2026-05-20 — Canonical Vertical rawValue for the
    /// driver's currently-assigned load. When `livestock` the dispatch
    /// board renders the 28-hr law (49 USC 80502 / FMCSA 395.8)
    /// countdown instead of the standard 11/14-hr HoS limits — animals
    /// can't be in continuous transit more than 28 hours without rest.
    /// Optional so legacy payloads decode without it.
    let loadVertical: String?
    /// T-022 · 2026-05-20 — Hours remaining on the livestock 28-hr clock.
    /// Server computes from `LivestockOverlay.timer28hArmed` timestamp.
    /// Nil when the load isn't livestock OR the 28-hr timer isn't armed
    /// (driver hasn't loaded animals yet).
    let livestock28hrRemaining: Double?

    /// True when this driver's currently-assigned load is livestock
    /// AND the 28-hr countdown is active. Drives the bucketing in
    /// `content`.
    var isLivestock28hr: Bool {
        loadVertical?.lowercased() == "livestock" && livestock28hrRemaining != nil
    }
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
        // RealtimeService → driver duty-status changes propagate
        // into this dispatch board live so the alerts strip and
        // proactive coaching CTAs reflect actual fleet state.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await load() }
        }
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
            // T-022 · 2026-05-20 — Split drivers into two regulatory
            // tracks. Livestock drivers gate on the 49 USC 80502 /
            // FMCSA 395.8 28-hr law; everyone else uses the standard
            // 11-hr driving / 14-hr on-duty clock. The two cards
            // render with different thresholds and regulatory pills so
            // the dispatcher can't confuse the rules.
            let livestockDrivers = rows.filter { $0.isLivestock28hr }
            let standardDrivers  = rows.filter { !$0.isLivestock28hr }
            let critical = standardDrivers.filter { ($0.hoursRemaining ?? 999) < 2 }
            let warn = standardDrivers.filter { let h = $0.hoursRemaining ?? 999; return h >= 2 && h < 4 }
            let healthy = standardDrivers.filter { ($0.hoursRemaining ?? 0) >= 4 }
            if rows.isEmpty {
                EusoEmptyState(systemImage: "clock", title: "No HOS data", subtitle: "Drivers without ELD telemetry won't show here.")
            } else {
                if !livestockDrivers.isEmpty {
                    livestock28hrSection(livestockDrivers)
                }
                if !critical.isEmpty {
                    LifecycleCard(accentDanger: true) {
                        LifecycleSection(label: "CRITICAL · UNDER 2H · 14-HR HoS", icon: "exclamationmark.octagon")
                        ForEach(critical) { d in driverLine(d, color: Brand.danger) }
                    }
                }
                if !warn.isEmpty {
                    LifecycleCard {
                        LifecycleSection(label: "WARN · UNDER 4H · 14-HR HoS", icon: "exclamationmark.triangle")
                        ForEach(warn) { d in driverLine(d, color: palette.textPrimary) }
                    }
                }
                if !healthy.isEmpty {
                    LifecycleCard(accentGradient: true) {
                        LifecycleSection(label: "HEALTHY · 4H+ · 14-HR HoS", icon: "checkmark.seal")
                        ForEach(healthy) { d in driverLine(d, color: palette.textPrimary) }
                    }
                }
            }
        }
    }

    /// T-022 · 2026-05-20 — Livestock 28-hr law section. Renders with
    /// its own thresholds (28-hr law has different bands than 11/14-hr
    /// HoS): < 4h critical (must rest soon · pen for food/water),
    /// 4h–8h warn, >= 8h healthy.
    @ViewBuilder
    private func livestock28hrSection(_ drivers: [HOSDriver]) -> some View {
        let critical = drivers.filter { ($0.livestock28hrRemaining ?? 999) < 4 }
        let warn     = drivers.filter { let h = $0.livestock28hrRemaining ?? 999; return h >= 4 && h < 8 }
        let healthy  = drivers.filter { ($0.livestock28hrRemaining ?? 0) >= 8 }
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("LIVESTOCK 28-HR LAW")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Text("49 USC 80502 · FMCSA 395.8")
                    .font(.system(size: 8, weight: .semibold)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("Animals can't be in continuous transit more than 28 hours without food, water, and rest. Drivers below 4 hours need an immediate pen stop.")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !critical.isEmpty {
                LifecycleCard(accentDanger: true) {
                    LifecycleSection(label: "CRITICAL · UNDER 4H · 28-HR LAW", icon: "exclamationmark.octagon")
                    ForEach(critical) { d in livestockDriverLine(d, color: Brand.danger) }
                }
            }
            if !warn.isEmpty {
                LifecycleCard {
                    LifecycleSection(label: "WARN · UNDER 8H · 28-HR LAW", icon: "exclamationmark.triangle")
                    ForEach(warn) { d in livestockDriverLine(d, color: palette.textPrimary) }
                }
            }
            if !healthy.isEmpty {
                LifecycleCard(accentGradient: true) {
                    LifecycleSection(label: "HEALTHY · 8H+ · 28-HR LAW", icon: "checkmark.seal")
                    ForEach(healthy) { d in livestockDriverLine(d, color: palette.textPrimary) }
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

    /// Livestock driver line — shows the 28-hr-clock countdown instead
    /// of the standard HoS clock. Reads `livestock28hrRemaining`.
    private func livestockDriverLine(_ d: HOSDriver, color: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(d.name).font(EType.bodyStrong).foregroundStyle(color)
                if let load = d.load {
                    Text("LIVESTOCK · \(load)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
            Text(d.livestock28hrRemaining.map { String(format: "%.1fh / 28h", $0) } ?? "—")
                .font(EType.body).foregroundStyle(color).monospacedDigit()
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

