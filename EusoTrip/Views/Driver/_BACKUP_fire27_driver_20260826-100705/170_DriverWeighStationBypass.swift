//
//  170_DriverWeighStationBypass.swift
//  EusoTrip — Screen 170 · Driver Weigh Station Bypass (LIVE-wired)
//
//  Purpose: on the current corridor, tell the driver which scales are open,
//  which their transponder can bypass, and their rolling green-light rate —
//  so they read the scale ahead instead of guessing at 65 mph.
//
//  Wiring manifest:
//    driverMobile.getWeighStationAlerts  EXISTS · routers/driverMobile.ts:1089
//      output { stations[ ...ws, statusColor, tip ], total, lastUpdated }
//    driverMobile.getPrePassStatus       EXISTS · routers/driverMobile.ts:1134
//      (bypass rate + transponder state)
//  HONEST GAP handed to the-oath: the server's WEIGH_STATIONS reference
//  table is currently EMPTY (driverMobile.ts:243 `WEIGH_STATIONS = []`), so
//  the corridor list renders its honest empty state until the DOT facility
//  feed is seeded. We show the real transponder green-rate regardless, and
//  never fabricate a station row. Proposed: seed WEIGH_STATIONS from the
//  FHWA/DOT facility feed keyed on route corridor.
//  transportMode = truck · country US.
//
//  Persona: Michael Eusorone (ME) · Eusotrans LLC · USDOT 3 194 882 · DR-00427.
//

import SwiftUI

// MARK: - Wire models

private struct WeighStationRow: Decodable, Identifiable {
    let name: String?
    let highway: String?
    let status: String?
    let statusColor: String?
    let tip: String?
    let prepassEnabled: Bool?
    let distance: Double?
    var id: String { (name ?? "") + (highway ?? "") }
}
private struct WeighAlerts: Decodable {
    let stations: [WeighStationRow]
    let total: Int
}
private struct BypassStatus: Decodable {
    let enrolled: Bool
    let provider: String?
    let bypassRate: Double
    let totalBypasses: Int
    let totalPullIns: Int
}

// MARK: - ViewModel

@MainActor
private final class WeighBypassViewModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, ready, error(String) }
    @Published var phase: Phase = .idle
    @Published var stations: [WeighStationRow] = []
    @Published var bypass: BypassStatus?

    let laneLabel: String
    init(laneLabel: String) { self.laneLabel = laneLabel }

    private struct AlertsIn: Encodable { let radius: Int }
    private struct EmptyIn: Encodable {}

    func load() async {
        phase = .loading
        do {
            async let alerts: WeighAlerts = EusoTripAPI.shared.query(
                "driverMobile.getWeighStationAlerts", input: AlertsIn(radius: 150))
            async let bp: BypassStatus = EusoTripAPI.shared.query(
                "driverMobile.getPrePassStatus", input: EmptyIn())
            let (a, b) = try await (alerts, bp)
            stations = a.stations
            bypass = b
            phase = .ready
        } catch {
            phase = .error("Couldn't reach the scale feed.")
        }
    }
}

// MARK: - Screen body

struct WeighBypassView: View {
    @Environment(\.palette) var palette
    @StateObject private var vm: WeighBypassViewModel

    init(laneLabel: String = "") {
        _vm = StateObject(wrappedValue: WeighBypassViewModel(laneLabel: laneLabel))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DriverUtilityHeader(eyebrow: "DRIVER · SCALES", caption: "BYPASS",
                                title: "Weigh Stations",
                                subtitle: vm.laneLabel.isEmpty ? "on your corridor" : vm.laneLabel,
                                rightTop: "MICHAEL EUSORONE · DR-00427",
                                rightBottom: "Eusotrans LLC")
            IridescentHairline().padding(.top, Space.s3)
            switch vm.phase {
            case .idle, .loading: DriverUtilityLoading(text: "Reading scales ahead…")
            case .error(let m):   DriverUtilityError(message: m) { Task { await vm.load() } }
            case .ready:          content
            }
        }
        .task { if case .idle = vm.phase { await vm.load() } }
    }

    private var content: some View {
        VStack(spacing: Space.s4) {
            if let b = vm.bypass { bypassHero(b); bypassStats(b) }
            stationsCard
            CTAButton(title: "Refresh scales", action: { Task { await vm.load() } },
                      leadingIcon: "arrow.clockwise")
            footnote
        }
        .padding(Space.s5)
    }

    private func bypassHero(_ b: BypassStatus) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("BYPASS RATE").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                StatusPill(text: b.enrolled ? (b.provider ?? "Enrolled") : "Not enrolled",
                           kind: b.enrolled ? .success : .neutral)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(b.enrolled ? "\(Int(b.bypassRate.rounded()))" : "—")
                    .font(EType.display).foregroundStyle(LinearGradient.diagonal)
                Text(b.enrolled ? "% green-lit" : "enroll to bypass")
                    .font(EType.body).foregroundStyle(palette.textSecondary)
            }
            Text(b.enrolled
                 ? "Your last weighs cleared \(Int(b.bypassRate.rounded()))% without a pull-in."
                 : "Enroll PrePass or Drivewyze so open scales green-light you by.")
                .font(EType.caption).foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg, intensity: .feature)
    }

    private func bypassStats(_ b: BypassStatus) -> some View {
        HStack(spacing: Space.s3) {
            MetricTile(label: "Scales ahead", value: "\(vm.stations.count)")
            MetricTile(label: "Bypasses", value: "\(b.totalBypasses)")
            MetricTile(label: "Pull-ins", value: "\(b.totalPullIns)",
                       accent: b.totalPullIns > 0 ? Brand.warning : nil)
        }
    }

    private var stationsCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("SCALE · ROAD").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("STATUS").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            if vm.stations.isEmpty {
                DriverUtilityEmpty(systemImage: "scalemass",
                                   title: "No scales on your corridor",
                                   detail: "Nothing to weigh through on the current route feed. We'll surface scales as your corridor updates.")
            } else {
                ForEach(vm.stations) { station in
                    stationRow(station)
                    if station.id != vm.stations.last?.id {
                        Divider().overlay(palette.borderFaint)
                    }
                }
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func stationRow(_ s: WeighStationRow) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name ?? "Weigh station").font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                if let tip = s.tip, !tip.isEmpty {
                    Text(tip).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
            }
            Spacer()
            Text((s.status ?? "—").uppercased())
                .font(EType.mono(.caption)).fontWeight(.bold)
                .foregroundStyle(statusTint(s.status))
        }
        .padding(.vertical, 2)
    }

    private func statusTint(_ status: String?) -> Color {
        switch (status ?? "").lowercased() {
        case "open":   return Brand.danger
        case "closed": return Brand.success
        case "bypass": return Brand.info
        default:       return palette.textSecondary
        }
    }

    private var footnote: some View {
        Text("Bypass not guaranteed · obey all officer signals at the scale.")
            .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Screen (Shell + Driver nav · ME current)

struct WeighBypassScreen: View {
    let theme: Theme.Palette
    var laneLabel: String = ""
    var body: some View {
        Shell(theme: theme) {
            WeighBypassView(laneLabel: laneLabel)
        } nav: {
            BottomNav(leading: driverUtilityNavLeading(),
                      trailing: driverUtilityNavTrailing(meCurrent: true), orbState: .idle)
        }
    }
}

#Preview("Weigh Bypass · Dark") {
    WeighBypassScreen(theme: Theme.dark, laneLabel: "I-10 EB · AZ")
        .preferredColorScheme(.dark).environment(\.palette, Theme.dark)
        .background(Theme.dark.bgPage)
}
#Preview("Weigh Bypass · Light") {
    WeighBypassScreen(theme: Theme.light, laneLabel: "I-10 EB · AZ")
        .preferredColorScheme(.light).environment(\.palette, Theme.light)
        .background(Theme.light.bgPage)
}
