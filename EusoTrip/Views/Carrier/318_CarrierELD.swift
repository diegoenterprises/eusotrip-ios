//
//  318_CarrierELD.swift
//  EusoTrip — Carrier · ELD fleet status (Geotab / Samsara / Motive / Omnitracs / EROAD).
//

import SwiftUI

struct CarrierELDScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ELDBody() } nav: {
            BottomNav(
                leading: CarrierNavRoute.leading(current: .me),
                trailing: CarrierNavRoute.trailing(current: .me),
                orbState: .idle
            )
        }
    }
}

private struct ELDDevice: Decodable, Identifiable, Hashable {
    let id: String
    let truckNumber: String
    let driverName: String?
    let provider: String?        // geotab / samsara / motive / omnitracs / eroad
    let dutyStatus: String?      // OFF / ON / DRIVING / SLEEPER
    let hosRemainingHours: Double?
    let lastPing: String?
    let lastLocation: String?
    let connectivity: String?    // "online" / "offline"
    let trackingState: HOSTrackingState?
    let tracked: Bool?
    let source: String?
    let freshness: String?

    var hasCurrentHOSEvidence: Bool {
        tracked == true
            && trackingState == .tracked
            && source?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && HOSObservationClock.freshness(freshness).isCurrent
            && dutyStatus.flatMap(normalizedDuty) != nil
    }

    var evidenceDisplay: String {
        if hasCurrentHOSEvidence { return "CURRENT · \(source?.uppercased() ?? "SOURCED")" }
        if tracked == false || trackingState == .notTracked { return "NOT TRACKED" }
        return "UNAVAILABLE"
    }

    private func normalizedDuty(_ raw: String) -> HOSDutyCode? {
        switch raw.lowercased() {
        case "off", "off_duty": return .offDuty
        case "on", "on_duty": return .onDuty
        case "driving": return .driving
        case "sleeper", "sleeper_berth": return .sleeperBerth
        default: return nil
        }
    }
}

private struct ELDBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [ELDDevice] = []
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
        // RealtimeService → ELD device + driver-status updates
        // refresh the carrier's fleet ELD board live.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await load() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · ELD FLEET").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("ELD fleet status").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Verified ELD duty evidence and vehicle heartbeat stay separate. Missing provider evidence remains unavailable.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading ELD…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if rows.isEmpty { EusoEmptyState(systemImage: "antenna.radiowaves.left.and.right", title: "No ELD devices", subtitle: "Connect Geotab / Samsara / Motive via the integrations registry to populate this list.") }
        else {
            ForEach(rows) { d in
                let warn = d.hasCurrentHOSEvidence
                    && d.dutyStatus?.uppercased() == "DRIVING"
                    && d.hosRemainingHours.map { $0 < 1 } == true
                LifecycleCard(accentDanger: warn) {
                    LifecycleSection(label: "TRUCK \(d.truckNumber.uppercased())", icon: "truck.box")
                    LifecycleRow(label: "Driver",          value: dashIfEmpty(d.driverName))
                    LifecycleRow(label: "HOS evidence",     value: d.evidenceDisplay)
                    LifecycleRow(label: "Provider",         value: d.hasCurrentHOSEvidence ? dashIfEmpty(d.provider?.uppercased()) : "UNVERIFIED")
                    LifecycleRow(label: "Duty status",      value: d.hasCurrentHOSEvidence ? dashIfEmpty(d.dutyStatus?.uppercased()) : "UNAVAILABLE")
                    LifecycleRow(label: "HOS remaining",    value: d.hasCurrentHOSEvidence ? d.hosRemainingHours.map { String(format: "%.1f hr", $0) } ?? "UNAVAILABLE" : "UNAVAILABLE")
                    LifecycleRow(label: "Vehicle heartbeat", value: dashIfEmpty(d.connectivity?.uppercased()))
                    LifecycleRow(label: "Heartbeat at",     value: humanISO(d.lastPing))
                    LifecycleRow(label: "Last location",    value: dashIfEmpty(d.lastLocation))
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [ELDDevice] = try await EusoTripAPI.shared.queryNoInput("catalysts.getELDFleet")
            rows = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("318 · ELD · Night") { CarrierELDScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("318 · ELD · Afternoon") { CarrierELDScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
