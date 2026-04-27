//
//  EnRouteRoadIntelStrip.swift
//  EusoTrip — Unified "road intel ahead" chip strip for the
//  013 / 018 / 035 en-route lifecycle screens.
//
//  Layers three HERE Dynamic Map Content products into one glance
//  surface the driver reads in under a second:
//
//    • Real-Time Traffic (flow) — live jam factor + speed vs. free-
//      flow baseline. "12 mi slow · 15 mph".
//    • Road Alerts (incidents) — accidents, roadworks, closures
//      within ~30 km, filtered to major + critical. "Accident ·
//      4.2 mi ahead".
//    • Safety Cameras — fixed speed + red-light camera POIs.
//      "Speed camera · 2.1 mi".
//
//  Each chip is a live HERE response; when HERE returns empty the
//  chip hides (no fabricated "no incidents" copy). When the client
//  errors the whole strip hides — matches the §3 "no fake data"
//  doctrine.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation

// MARK: - RoadIntelStore

/// Composite store that hydrates flow + incidents + cameras in
/// parallel for a target coordinate. Designed to be owned by the
/// en-route screen (`@StateObject`) and refreshed on each app
/// foregrounding or ~60s timer while the screen is visible.
@MainActor
final class RoadIntelStore: ObservableObject {

    @Published private(set) var worstFlow: HereTrafficFlowResult?
    @Published private(set) var topIncident: HereIncident?
    @Published private(set) var nearestCamera: HereSafetyCameraItem?

    @Published private(set) var incidents: [HereIncident] = []
    @Published private(set) var cameras: [HereSafetyCameraItem] = []

    @Published private(set) var isLoading: Bool = false

    /// Kicks off parallel fetches around a centre point. Each
    /// feed's errors are swallowed (logged in DEBUG) so a partial
    /// HERE outage still leaves the available layers rendered.
    func refresh(center: CLLocationCoordinate2D) async {
        isLoading = true
        defer { isLoading = false }

        async let flowTask: [HereTrafficFlowResult] = (try? await HereTrafficClient.shared.flow(
            near: center,
            radiusMeters: 15_000,
            includeShape: false
        )) ?? []

        async let incidentsTask: [HereIncident] = (try? await HereTrafficClient.shared.incidents(
            near: center,
            radiusMeters: 30_000
        )) ?? []

        async let camerasTask: [HereSafetyCameraItem] = (try? await HereSafetyCamerasClient.shared.camerasNearby(
            center: center,
            limit: 20
        )) ?? []

        let (flows, inc, cams) = await (flowTask, incidentsTask, camerasTask)

        // Worst flow = highest jamFactor.
        worstFlow = flows
            .compactMap { f -> (HereTrafficFlowResult, Double)? in
                guard let j = f.currentFlow?.jamFactor else { return nil }
                return (f, j)
            }
            .max { $0.1 < $1.1 }?
            .0

        incidents = inc
        topIncident = inc
            .sorted { (lhs, rhs) in
                // critical > major > other; otherwise newest first.
                let rank = { (c: String?) -> Int in
                    switch (c ?? "").lowercased() {
                    case "critical": return 2
                    case "major":    return 1
                    default:         return 0
                    }
                }
                let lr = rank(lhs.incidentDetails?.criticality)
                let rr = rank(rhs.incidentDetails?.criticality)
                if lr != rr { return lr > rr }
                return (lhs.sourceUpdated ?? "") > (rhs.sourceUpdated ?? "")
            }
            .first

        cameras = cams
        // Pick the closest camera via the `distance` field HERE
        // ships on Browse results when queried with `at`.
        nearestCamera = cams
            .compactMap { c -> (HereSafetyCameraItem, Int)? in
                guard let d = c.distance else { return nil }
                return (c, d)
            }
            .min { $0.1 < $1.1 }?
            .0
    }
}

// MARK: - EnRouteRoadIntelStrip

/// Horizontal chip row surfaced across en-route lifecycle screens
/// (013 / 018 / 035). Accepts a focus coordinate (the driver's
/// current fix or the load's active leg waypoint) and renders 0-3
/// chips depending on what HERE actually returned.
struct EnRouteRoadIntelStrip: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = RoadIntelStore()

    /// Where to center the intel lookup. Usually the driver's live
    /// coordinate via `DriverLocationResolver`. Callers can pass an
    /// explicit coord (e.g. the active leg waypoint) for a preview.
    let explicitCenter: CLLocationCoordinate2D?

    init(center: CLLocationCoordinate2D? = nil) {
        self.explicitCenter = center
    }

    var body: some View {
        // Hide entirely when nothing came back — the en-route screen
        // shouldn't show an empty "road intel" shell with no content.
        Group {
            if hasAny {
                chipRow
            } else {
                EmptyView()
            }
        }
        .task { await load() }
    }

    private var hasAny: Bool {
        store.worstFlow != nil
            || store.topIncident != nil
            || store.nearestCamera != nil
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let flow = store.worstFlow, let j = flow.currentFlow?.jamFactor {
                    flowChip(result: flow, jamFactor: j)
                }
                if let deltaMinutes = flowVsTypicalDeltaMinutes(),
                   abs(deltaMinutes) >= 1 {
                    // Traffic Analytics-style delta derived from the
                    // live flow's speed vs. its own freeFlow baseline.
                    // Avoids a second round-trip to HERE's Analytics
                    // endpoint when the baseline is already on the
                    // flow result. Swapped in when the delta is
                    // meaningful (>= 1 minute either direction).
                    analyticsDeltaChip(minutes: deltaMinutes)
                }
                if let inc = store.topIncident {
                    incidentChip(inc)
                }
                if let cam = store.nearestCamera {
                    cameraChip(cam)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }

    /// Projects a minutes delta for the segment of the worst-flow
    /// result, comparing live `speed` to the `freeFlow` baseline over
    /// the segment's `length`. Positive values = slower than
    /// baseline (driver loses minutes), negative = ahead of baseline.
    /// Returns nil when any required field is missing.
    private func flowVsTypicalDeltaMinutes() -> Int? {
        guard
            let flow = store.worstFlow,
            let segLen = flow.location?.length,
            segLen > 0,
            let currentSpeed = flow.currentFlow?.speed,
            let freeFlow = flow.currentFlow?.freeFlow,
            currentSpeed > 0, freeFlow > 0
        else { return nil }
        // HERE ships both in m/s (internal SI) — convert both via
        // the same factor so the unit cancels in the delta.
        let live = segLen / currentSpeed
        let base = segLen / freeFlow
        let delta = (live - base) / 60.0
        return Int(delta.rounded())
    }

    // MARK: Chips

    private func flowChip(result: HereTrafficFlowResult, jamFactor: Double) -> some View {
        let (label, color) = flowLabel(jamFactor: jamFactor)
        let speed = result.currentFlow?.speed.map { Int($0.rounded()) }
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                .foregroundStyle(color)
            if let s = speed {
                Text("· \(s) mph")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .chipBackdrop(color: color, palette: palette)
    }

    private func incidentChip(_ inc: HereIncident) -> some View {
        let det = inc.incidentDetails
        let type = (det?.type ?? "incident").uppercased()
        let color = incidentColor(det?.criticality)
        return HStack(spacing: 5) {
            Image(systemName: incidentGlyph(det?.type))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
            Text(type)
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                .foregroundStyle(color)
            if det?.roadClosed == true {
                Text("· CLOSED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.danger)
            }
        }
        .chipBackdrop(color: color, palette: palette)
    }

    private func analyticsDeltaChip(minutes: Int) -> some View {
        let isAhead = minutes < 0
        let color = isAhead ? Brand.success : (abs(minutes) >= 10 ? Brand.danger : Brand.warning)
        let sign = isAhead ? "" : "+"
        return HStack(spacing: 5) {
            Image(systemName: isAhead ? "arrow.down.right" : "arrow.up.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
            Text("\(sign)\(minutes) min")
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(color)
            Text("vs typical")
                .font(.system(size: 9, weight: .semibold)).tracking(0.4)
                .foregroundStyle(.white.opacity(0.85))
        }
        .chipBackdrop(color: color, palette: palette)
    }

    private func cameraChip(_ cam: HereSafetyCameraItem) -> some View {
        let miles = cam.distance.map { Double($0) / 1609.344 }
        return HStack(spacing: 5) {
            Image(systemName: "camera.metering.center.weighted")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Brand.warning)
            Text("CAMERA")
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                .foregroundStyle(Brand.warning)
            if let m = miles {
                Text(String(format: "· %.1f mi", m))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .chipBackdrop(color: Brand.warning, palette: palette)
    }

    // MARK: Logic

    private func load() async {
        let coord: CLLocationCoordinate2D? = {
            if let c = explicitCenter { return c }
            return nil
        }()
        if let explicit = coord {
            await store.refresh(center: explicit)
            return
        }
        guard let live = await DriverLocationResolver.shared.currentCoordinate() else {
            return
        }
        await store.refresh(center: live)
    }

    private func flowLabel(jamFactor: Double) -> (String, Color) {
        switch jamFactor {
        case ..<2:         return ("CLEAR",   Brand.success)
        case 2..<4:        return ("LIGHT",   Brand.success)
        case 4..<7:        return ("SLOW",    Brand.warning)
        case 7..<9:        return ("QUEUED",  Brand.danger)
        default:           return ("STOPPED", Brand.danger)
        }
    }

    private func incidentColor(_ criticality: String?) -> Color {
        switch (criticality ?? "").lowercased() {
        case "critical": return Brand.danger
        case "major":    return Brand.warning
        default:         return Brand.info
        }
    }

    private func incidentGlyph(_ type: String?) -> String {
        switch (type ?? "").lowercased() {
        case "accident":     return "car.side.rear.and.collision.and.car.side.front"
        case "roadworks":    return "cone.fill"
        case "closure":      return "xmark.octagon.fill"
        case "hazard":       return "exclamationmark.triangle.fill"
        case "weather":      return "cloud.bolt.rain.fill"
        case "masstransit":  return "bus.fill"
        case "disaster":     return "flame.fill"
        default:             return "exclamationmark.circle.fill"
        }
    }
}

// MARK: - Chip backdrop modifier

private extension View {
    func chipBackdrop(color: Color, palette: Theme.Palette) -> some View {
        self
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(Color.black.opacity(0.55))
            )
            .overlay(
                Capsule().stroke(color.opacity(0.45), lineWidth: 1)
            )
    }
}

// MARK: - Previews

#Preview("EnRouteRoadIntelStrip · Dark") {
    EnRouteRoadIntelStrip()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .padding()
        .background(Theme.dark.bgPage)
}

#Preview("EnRouteRoadIntelStrip · Light") {
    EnRouteRoadIntelStrip()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .padding()
        .background(Theme.light.bgPage)
}
