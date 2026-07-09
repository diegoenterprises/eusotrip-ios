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
                    if let err = route.lastError, route.etaText == "—" {
                        // Distinguish "route data unreachable" from "no
                        // route data on this load" — staleness must be
                        // visible, never a permanent silent Pending.
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.esangAmber)
                            Text(err)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.esangAmber)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: R.sm))
                    }
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
        // The one-shot .task used to fire BEFORE the phone pushed the
        // active load, leaving "—/—/Pending" up forever. Re-run the
        // fetch whenever the active load or the auth mirror lands.
        .onChange(of: loads.active?.id) { _, newId in
            Task { await route.refresh(auth: auth, loadId: newId) }
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            guard signedIn else { return }
            Task { await route.refresh(auth: auth, loadId: loads.active?.id) }
        }
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
            // Bespoke per-load weather chip — glyph from WatchWeatherGlyph
            // (ported verbatim from the lane-impact reference), text from
            // the REAL flag/headline the pipeline handed down. No SF
            // Symbol, no emoji. Renders nothing when there is no signal.
            if let severity = route.weatherSeverity {
                WatchWeatherChip(severity: severity, label: route.weatherFlagDisplay)
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
    /// Last transport failure — rendered as a small banner when the
    /// stats are still placeholders so "unreachable" is distinguishable
    /// from "no route data on this load".
    @Published var lastError: String?

    /// The raw, REAL weather signal that reached the wrist. Sourced (in
    /// priority order) from:
    ///   1. `weather.forLoad → laneImpact` — the canonical per-load
    ///      tri-modal severity (riskTier + headline) that the phone's v3
    ///      card renders. This is the strongest signal: it's the same
    ///      WeatherKit-backed lane analysis the founder's weather surface
    ///      uses.
    ///   2. `routeOptimization.getProgress.weatherFlag` — a coarse route-
    ///      level flag string ("severe-thunderstorm" | "wind-advisory" | …).
    ///      Used only when laneImpact is unavailable.
    /// Stays nil when neither source reports weather — we never fabricate.
    @Published var weatherFlag: String?

    /// Human-readable label for the chip. The lane-impact headline when we
    /// have it, otherwise a prettified flag string. Honest "—" never shown
    /// here because the chip itself is hidden when `weatherSeverity == nil`.
    @Published var weatherHeadline: String?

    /// Bespoke glyph bucket derived from the real signal. nil → the view
    /// renders no weather chip at all (honest empty, not a default storm).
    var weatherSeverity: WatchWeatherSeverity? { WatchWeatherSeverity.from(flag: weatherFlag) }

    /// The string the chip prints: the real lane-impact headline if the
    /// server sent one, else the flag prettified ("wind-advisory" → "Wind
    /// advisory"). Both come straight from server fields.
    var weatherFlagDisplay: String {
        if let h = weatherHeadline, !h.isEmpty { return h }
        guard let f = weatherFlag, !f.isEmpty else { return "—" }
        return f.replacingOccurrences(of: "-", with: " ").capitalizedFirst
    }

    func refresh(auth: AuthStore, loadId: String?) async {
        guard auth.isSignedIn, let loadId else { return }
        let client = EsangClient(auth: auth)

        // --- Route progress (ETA / miles / waypoint + coarse weather flag) ---
        do {
            let data = try await client.queryJSON(
                "routeOptimization.getProgress",
                input: ["loadId": loadId]
            )
            struct Envelope: Decodable {
                struct Result: Decodable {
                    struct DataContainer: Decodable { let json: Progress }
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
            // Coarse route flag is the baseline weather signal.
            weatherFlag = p.weatherFlag
            weatherHeadline = nil
            lastError = nil
        } catch {
            // keep last known — honest staleness, no fabrication —
            // but record the failure so the view can badge it.
            lastError = (error as? LocalizedError)?.errorDescription
                ?? "Can't reach route progress"
        }

        // --- Canonical per-load lane impact (preferred weather signal) ---
        // weather.forLoad is the same tRPC the phone's v3 card uses. When
        // it reports an actionable riskTier we override the coarse route
        // flag with the richer severity + headline. When it's unavailable
        // or returns `none`, we keep whatever getProgress gave us.
        do {
            let data = try await client.queryJSON(
                "weather.forLoad",
                input: ["loadId": loadId]
            )
            struct Envelope: Decodable {
                struct Result: Decodable {
                    struct DataContainer: Decodable { let json: ForLoad }
                    let data: DataContainer
                }
                let result: Result
            }
            struct ForLoad: Decodable {
                struct LaneImpact: Decodable {
                    let available: Bool?
                    let riskTier: String?
                    let headline: String?
                }
                let laneImpact: LaneImpact?
            }
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            if let li = env.result.data.json.laneImpact,
               li.available == true,
               let tier = li.riskTier?.lowercased(),
               tier != "none", !tier.isEmpty {
                // Lane impact wins — feed the bespoke severity off the
                // canonical riskTier, label off the canonical headline.
                weatherFlag = tier
                weatherHeadline = li.headline
            }
        } catch {
            // weather.forLoad unreachable → fall back to the route flag
            // already set above. Honest: no fabricated severity.
        }
    }

    private func formatEta(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)m" }
        return String(format: "%dh %02dm", h, m)
    }
}

private extension String {
    /// Capitalises only the first character, leaving the rest as-is — so
    /// "wind advisory" → "Wind advisory" (not "Wind Advisory").
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
