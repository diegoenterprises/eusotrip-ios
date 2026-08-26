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
                leading: DispatchNavRoute.leading(current: .board),
                trailing: DispatchNavRoute.trailing(current: .board),
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

    var isLivestockLoad: Bool { loadVertical?.lowercased() == "livestock" }
}

private struct HOSBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [HOSDriver] = []
    @State private var fleetEvidence: [HOSFleetDriver] = []
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
        .eusoRefreshable { await load() }
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
            Text("Current, company-scoped ELD observations under 2h are flagged. Missing or stale evidence stays unavailable.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
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
            let livestockDrivers = rows.filter(\.isLivestockLoad)
            let standardDrivers  = rows.filter { !$0.isLivestockLoad }
            let critical = standardDrivers.filter { standardHours(for: $0).map { $0 < 2 } == true }
            let warn = standardDrivers.filter {
                standardHours(for: $0).map { $0 >= 2 && $0 < 4 } == true
            }
            let healthy = standardDrivers.filter { standardHours(for: $0).map { $0 >= 4 } == true }
            let unavailable = standardDrivers.filter { standardHours(for: $0) == nil }
            if rows.isEmpty {
                EusoEmptyState(
                    systemImage: "clock",
                    title: "No HOS data",
                    subtitle: "No company-scoped driver status rows were returned."
                )
            } else {
                if !livestockDrivers.isEmpty {
                    livestock28hrSection(livestockDrivers)
                }
                if !critical.isEmpty {
                    LifecycleCard(accentDanger: true) {
                        LifecycleSection(label: "CRITICAL · UNDER 2H · 14-HR HoS", icon: "exclamationmark.octagon")
                        ForEach(critical) { d in standardDriverLine(d, color: Brand.danger) }
                    }
                }
                if !warn.isEmpty {
                    LifecycleCard {
                        LifecycleSection(label: "WARN · UNDER 4H · 14-HR HoS", icon: "exclamationmark.triangle")
                        ForEach(warn) { d in standardDriverLine(d, color: palette.textPrimary) }
                    }
                }
                if !healthy.isEmpty {
                    LifecycleCard(accentGradient: true) {
                        LifecycleSection(label: "HEALTHY · 4H+ · 14-HR HoS", icon: "checkmark.seal")
                        ForEach(healthy) { d in standardDriverLine(d, color: palette.textPrimary) }
                    }
                }
                if !unavailable.isEmpty {
                    LifecycleCard {
                        LifecycleSection(label: "HOS EVIDENCE UNAVAILABLE", icon: "questionmark.circle")
                        ForEach(unavailable) { d in unavailableDriverLine(d) }
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
        let critical = drivers.filter { validLivestockHours($0).map { $0 < 4 } == true }
        let warn = drivers.filter { validLivestockHours($0).map { $0 >= 4 && $0 < 8 } == true }
        let reported = drivers.filter { validLivestockHours($0).map { $0 >= 8 } == true }
        let unavailable = drivers.filter { validLivestockHours($0) == nil }
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
            Text("The load-status feed reports this timer without observation freshness. Values remain reported, not current, until that contract carries a timestamp and source.")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !critical.isEmpty {
                LifecycleCard(accentDanger: true) {
                    LifecycleSection(label: "REPORTED UNDER 4H · FRESHNESS UNAVAILABLE", icon: "exclamationmark.octagon")
                    ForEach(critical) { d in livestockDriverLine(d, color: Brand.danger) }
                }
            }
            if !warn.isEmpty {
                LifecycleCard {
                    LifecycleSection(label: "REPORTED UNDER 8H · FRESHNESS UNAVAILABLE", icon: "exclamationmark.triangle")
                    ForEach(warn) { d in livestockDriverLine(d, color: palette.textPrimary) }
                }
            }
            if !reported.isEmpty {
                LifecycleCard {
                    LifecycleSection(label: "REPORTED 8H+ · FRESHNESS UNAVAILABLE", icon: "clock")
                    ForEach(reported) { d in livestockDriverLine(d, color: palette.textPrimary) }
                }
            }
            if !unavailable.isEmpty {
                LifecycleCard {
                    LifecycleSection(label: "28-HR TIMER UNAVAILABLE", icon: "questionmark.circle")
                    ForEach(unavailable) { d in livestockDriverLine(d, color: palette.textSecondary) }
                }
            }
        }
    }

    private func standardDriverLine(_ d: HOSDriver, color: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(d.name).font(EType.bodyStrong).foregroundStyle(color)
                Text(evidenceLine(for: d))
                    .font(EType.micro)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
            Text(standardHours(for: d).map { String(format: "%.1fh", $0) } ?? "—")
                .font(EType.body).foregroundStyle(color).monospacedDigit()
        }
        .padding(.vertical, 4)
    }

    private func unavailableDriverLine(_ d: HOSDriver) -> some View {
        HStack(alignment: .top) {
            Text(d.name).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
            Text(unavailableReason(for: d))
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.trailing)
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
            Text(validLivestockHours(d).map { String(format: "%.1fh / 28h", $0) } ?? "—")
                .font(EType.body).foregroundStyle(color).monospacedDigit()
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        loading = true; loadError = nil
        rows = []
        fleetEvidence = []
        struct In: Encodable { let limit: Int }
        do {
            let driverRows: [HOSDriver] = try await EusoTripAPI.shared.query(
                "dispatch.getDriverStatuses",
                input: In(limit: 200)
            )
            let evidenceRows: [HOSFleetDriver] = try await EusoTripAPI.shared.queryNoInput("hos.getFleetHOS")
            fleetEvidence = evidenceRows
            rows = driverRows
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func evidence(for driver: HOSDriver) -> HOSFleetDriver? {
        fleetEvidence.first {
            $0.driverId == driver.id || $0.userId.map { String($0) } == driver.id
        }
    }

    private func standardHours(for driver: HOSDriver) -> Double? {
        guard let evidence = evidence(for: driver), evidence.hasCurrentObservation(),
              let hours = evidence.hoursAvailable?.drivingRemaining,
              hours.isFinite, hours >= 0 else { return nil }
        return hours
    }

    private func evidenceLine(for driver: HOSDriver) -> String {
        guard let evidence = evidence(for: driver) else { return "HOS SOURCE UNAVAILABLE" }
        let source = evidence.source?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceLabel = source.flatMap { $0.isEmpty ? nil : $0.uppercased() } ?? "SOURCE UNAVAILABLE"
        return "\(sourceLabel) · CURRENT ≤15M"
    }

    private func unavailableReason(for driver: HOSDriver) -> String {
        guard let evidence = evidence(for: driver) else { return "No company-scoped HOS observation" }
        if !evidence.hasCurrentObservation() {
            switch HOSObservationClock.freshness(evidence.freshness) {
            case .stale: return "HOS observation is stale"
            case .unavailable, .invalid: return "HOS freshness unavailable"
            case .current: return evidence.assignmentEligibility().reason ?? "HOS observation incomplete"
            }
        }
        return "Driving-hours counter unavailable"
    }

    private func validLivestockHours(_ driver: HOSDriver) -> Double? {
        guard let hours = driver.livestock28hrRemaining, hours.isFinite, hours >= 0 else { return nil }
        return hours
    }
}

#Preview("704 · HOS · Night") { DispatchHOSAlertsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("704 · HOS · Afternoon") { DispatchHOSAlertsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
