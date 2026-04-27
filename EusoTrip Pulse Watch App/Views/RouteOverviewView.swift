//
//  RouteOverviewView.swift
//  EusoTrip Watch App
//
//  Driver persona's 5th tab — a micro route overview for the active
//  load: ETA, miles remaining, next waypoint, weather flag, plus
//  "Find rest stop" and "Navigate on iPhone" handoffs.
//

import SwiftUI
import Combine
import WatchKit

struct RouteOverviewView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @EnvironmentObject var loads: LoadStore
    @StateObject private var route = RouteProgressStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: S.s2) {
                if let load = loads.active {
                    header(load)
                    statRow
                    waypointRow
                    actions
                } else {
                    emptyState
                }
            }
            .padding(.vertical, S.s1)
            .padding(.horizontal, S.s2)
        }
        .navigationTitle("Route")
        .task { await route.refresh(auth: auth, loadId: loads.active?.id) }
        // Mask overscroll bleed of the brand-gradient route header +
        // colored stat cards into the curved bezel corners.
        .clipShape(ContainerRelativeShape())
    }

    @ViewBuilder
    private func header(_ load: WatchLoad) -> some View {
        VStack(spacing: 2) {
            Text(load.displayId)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            Text("\(load.originShort) → \(load.destShort)")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(LinearGradient.esangPrimary, in: RoundedRectangle(cornerRadius: R.md))
    }

    private var statRow: some View {
        HStack(spacing: 6) {
            statCard(value: route.etaText, label: "ETA", tint: .esangBlue)
            statCard(value: route.milesRemainingText, label: "MILES", tint: .esangGreen)
        }
    }

    @ViewBuilder
    private func statCard(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
    }

    private var waypointRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("NEXT WAYPOINT")
                .font(.system(size: 8, weight: .medium))
                .tracking(1)
                .foregroundStyle(.secondary)
            HStack {
                Circle().fill(Color.esangBlue).frame(width: 6, height: 6)
                Text(route.nextWaypoint)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(2)
            }
            if let weather = route.weatherFlag {
                HStack(spacing: 4) {
                    Image(systemName: "cloud.rain.fill")
                        .foregroundStyle(Color.esangAmber)
                    Text(weather)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
    }

    private var actions: some View {
        VStack(spacing: 4) {
            actionButton(
                label: "Find rest stop",
                systemImage: "fork.knife",
                gradient: .esangPrimary
            ) {
                connectivity.requestPhoneActivation(
                    transcript: "find rest stop",
                    reply: "Searching rest stops on your iPhone."
                )
            }
            actionButton(
                label: "Navigate on iPhone",
                systemImage: "map.fill",
                gradient: .esangPrimary
            ) {
                connectivity.requestPhoneActivation(
                    transcript: "navigate to \(loads.active?.destShort ?? "")",
                    reply: "Opening Maps on your iPhone."
                )
            }
        }
    }

    @ViewBuilder
    private func actionButton(label: String, systemImage: String, gradient: LinearGradient, action: @escaping () -> Void) -> some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            action()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(label).font(.system(size: 11, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(gradient, in: RoundedRectangle(cornerRadius: R.sm))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "map")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("No active route")
                .font(.system(size: 12, weight: .semibold))
            Text("Ask Esang for loads.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
    }
}

@MainActor
final class RouteProgressStore: ObservableObject {
    static let shared = RouteProgressStore()

    @Published var etaText: String = "—"
    @Published var milesRemainingText: String = "—"
    @Published var nextWaypoint: String = "Pending"
    @Published var weatherFlag: String?

    func refresh(auth: AuthStore, loadId: String?) async {
        guard auth.isSignedIn, let loadId else { return }
        do {
            let client = EsangClient(auth: auth)
            let data = try await client.queryJSON(
                "routeOptimization.getProgress",
                input: ["loadId": loadId]
            )
            struct Envelope: Decodable {
                struct Result: Decodable {
                    struct DataContainer: Decodable {
                        let json: Progress
                    }
                    let data: DataContainer
                }
                let result: Result
            }
            struct Progress: Decodable {
                let etaMinutes: Int?
                let milesRemaining: Double?
                let nextWaypoint: String?
                let weatherFlag: String?
            }
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            let p = env.result.data.json
            etaText = p.etaMinutes.map { formatEta($0) } ?? etaText
            milesRemainingText = p.milesRemaining.map { String(format: "%.0f", $0) } ?? milesRemainingText
            nextWaypoint = p.nextWaypoint ?? nextWaypoint
            weatherFlag = p.weatherFlag
        } catch {
            // keep last known
        }
    }

    private func formatEta(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)m" }
        return String(format: "%dh %02dm", h, m)
    }
}
