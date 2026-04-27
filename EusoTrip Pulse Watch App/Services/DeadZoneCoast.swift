//
//  DeadZoneCoast.swift
//  EusoTrip Pulse Watch App
//
//  F02b — "Dead-Zone Coast" offline position tracker.
//
//  TunnelAwareETA.swift (F02) runs a full 15-state error-state EKF,
//  but its contract is narrow: produce an ETA + 1-σ position variance
//  while the watch is inside a geometry we think is a tunnel. The
//  trigger is "GNSS went bad AND we're near a tunnel polygon we've
//  already learned." That misses the common case: canyons, urban
//  midtowns, electronic interference, dead rural stretches, deep
//  warehouses at a dock. In all of those, GNSS is unreliable but
//  the driver isn't in a mapped tunnel.
//
//  Dead-Zone Coast owns the general case:
//
//    - Watches the CLLocation stream for fix freshness.
//    - If the last 3D fix is older than `coastTriggerSeconds` (default
//      60s) we enter COASTING state and freeze the last known (lat, lon,
//      heading, speed) as the "anchor." From there we propagate forward
//      in meters using simple kinematics: pos += speed · heading · dt.
//    - Uncertainty radius grows linearly: r = max(horizontalAccuracy,
//      `uncertaintyRatePerSec` · coastElapsed). After ~5 minutes a
//      typical 15 m/s highway anchor has grown to ~3 km of 1-σ — big
//      enough that dispatch reads it as "driver is lost, escalate."
//    - When coast elapsed > `satelliteEscalationSeconds` (default 5
//      minutes) we flip SatelliteFallback.terrestrialDown so the UI
//      shows the "Use phone satellite" card, and we enqueue a
//      breadcrumb position into OfflineQueue for when the wrist
//      eventually reconnects.
//
//  This intentionally does NOT run another EKF. Reasons:
//    • Battery — CoreMotion at 50 Hz is expensive; TunnelAwareETA only
//      pays that cost when the user is in a known tunnel for a short
//      window. The general offline case may last hours.
//    • Accuracy — without GNSS-corrected bias estimation, a 50 Hz IMU
//      integration drifts into nonsense fast. Pure kinematic coast
//      from last-known speed is no worse, and far cheaper.
//    • Downstream contract — dispatch needs a "last known point +
//      heading + elapsed-seconds" breadcrumb, not a sub-meter position.
//      Our error bars say "somewhere inside this circle" and that's
//      what UI + broker-of-record dashboards render.
//
//  If TunnelAwareETA is also running (geometry match), its output is
//  more authoritative — the UI can prefer its `bestEstimate()` and
//  treat DeadZoneCoast as the fallback. That's a view-layer concern;
//  this service is happy to run in parallel.
//

import Foundation
import Combine
import CoreLocation

@MainActor
final class DeadZoneCoast: ObservableObject {
    static let shared = DeadZoneCoast()

    // MARK: - Published state (SwiftUI observes these)

    /// Live state of the coast machine. `Int` raw so SwiftUI `Equatable`
    /// comparisons don't allocate.
    enum Mode: Int { case live = 0, coasting = 1 }
    @Published private(set) var mode: Mode = .live

    /// Last known good GPS fix (3D, horizontal accuracy < acceptanceMeters).
    /// Nil before the first fix has ever landed.
    @Published private(set) var anchor: Anchor?

    /// Currently-believed position. When `.live`, this is just `anchor`
    /// with a zero coast offset. When `.coasting`, it's the coast-forward
    /// projection with uncertaintyMeters > 0.
    @Published private(set) var estimate: CoastEstimate?

    /// True when `coastElapsed > satelliteEscalationSeconds`. UI reads
    /// this to render the "request satellite help" escalation card
    /// (which in turn talks to `SatelliteFallback`).
    @Published private(set) var satelliteEscalationDue: Bool = false

    // MARK: - Tuning

    /// Seconds of GNSS silence before we declare dead-zone.
    let coastTriggerSeconds: TimeInterval = 60

    /// Seconds of continuous coast before we escalate to satellite.
    let satelliteEscalationSeconds: TimeInterval = 5 * 60

    /// Seconds between breadcrumb enqueues into OfflineQueue while
    /// coasting. Dispatch sees a ping every 2 min — enough to track
    /// progress, few enough to stay under the outbox quota.
    let breadcrumbIntervalSeconds: TimeInterval = 2 * 60

    /// 1-σ growth rate of position uncertainty per second of coast.
    /// 2 m/s ≈ a tight highway-speed breadcrumb at 1 min → 120 m; at
    /// 5 min → 600 m. Tune on-device from outbox residuals later.
    let uncertaintyRatePerSec: Double = 2.0

    /// Horizontal accuracy threshold for accepting a fix as "good"
    /// (a.k.a. "we're back live"). Consumer-grade iPhones in heavy
    /// urban canyon easily return 30–80 m; we cap at 40 m to avoid
    /// flapping in and out of coast on marginal fixes.
    let acceptanceMeters: CLLocationAccuracy = 40

    // MARK: - Internals

    private var lastGoodFixAt: Date?
    private var coastStartedAt: Date?
    private var lastBreadcrumbAt: Date?
    private var ticker: Timer?

    // MARK: - Lifecycle

    /// Begin ticking the coast propagator. Safe to call multiple times
    /// (no-op after first). Paired with `stop()` in
    /// `DrivingSessionManager.end()`.
    func start() {
        guard EusoTripConfig.deadZoneCoastEnabled else { return }
        if ticker != nil { return }
        // 1 Hz is plenty — we're doing arithmetic, not Kalman math.
        // Swift 6 concurrency: don't capture `self` across the Sendable
        // Timer closure — hop to MainActor and look up the singleton
        // fresh each tick instead.
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in DeadZoneCoast.shared.tick() }
        }
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        mode = .live
        estimate = anchor.map { CoastEstimate(latitude: $0.latitude,
                                              longitude: $0.longitude,
                                              headingDegrees: $0.headingDegrees,
                                              speedMps: $0.speedMps,
                                              uncertaintyMeters: 0,
                                              coastElapsed: 0) }
        satelliteEscalationDue = false
        coastStartedAt = nil
    }

    // MARK: - Ingest (called by DrivingSessionManager on every fix)

    /// Feed the next CLLocation sample. Accepted if horizontalAccuracy
    /// <= `acceptanceMeters`; rejected (but still counts as "a fix
    /// happened") otherwise — we don't want to reset the coast timer
    /// on a 500 m urban-canyon fix that the OS only gave us because
    /// no satellites were visible.
    func ingest(_ loc: CLLocation) {
        guard EusoTripConfig.deadZoneCoastEnabled else { return }
        // Negative accuracy = invalid fix on watchOS; guard that first.
        guard loc.horizontalAccuracy >= 0,
              loc.horizontalAccuracy <= acceptanceMeters else {
            return
        }
        let heading = loc.course >= 0 ? loc.course : (anchor?.headingDegrees ?? 0)
        let speed = max(0, loc.speed)
        let now = loc.timestamp
        anchor = Anchor(
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            headingDegrees: heading,
            speedMps: speed,
            horizontalAccuracy: loc.horizontalAccuracy,
            at: now
        )
        lastGoodFixAt = now
        // Coming out of coast: clear escalation + update live estimate.
        if mode == .coasting {
            mode = .live
            coastStartedAt = nil
            satelliteEscalationDue = false
        }
        estimate = CoastEstimate(
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            headingDegrees: heading,
            speedMps: speed,
            uncertaintyMeters: max(5, loc.horizontalAccuracy),
            coastElapsed: 0
        )
    }

    // MARK: - Per-second tick

    private func tick() {
        guard EusoTripConfig.deadZoneCoastEnabled else { return }
        guard let anchor, let lastGoodFixAt else { return }
        let now = Date()
        let silence = now.timeIntervalSince(lastGoodFixAt)

        if silence < coastTriggerSeconds {
            // Still live (or in the grace window). Refresh estimate so
            // the UI shows a ticking uncertainty but `mode == .live`.
            estimate = CoastEstimate(
                latitude: anchor.latitude,
                longitude: anchor.longitude,
                headingDegrees: anchor.headingDegrees,
                speedMps: anchor.speedMps,
                uncertaintyMeters: max(5, anchor.horizontalAccuracy),
                coastElapsed: silence
            )
            mode = .live
            satelliteEscalationDue = false
            return
        }

        // ---- Dead-zone: coast forward from anchor ----

        if mode != .coasting {
            mode = .coasting
            coastStartedAt = now
            lastBreadcrumbAt = nil
        }

        let coastElapsed = now.timeIntervalSince(coastStartedAt ?? now)
        // Kinematic projection: constant speed + heading from anchor.
        // Convert (speed, heading) into NE displacement, then NE back to
        // lat/lon via flat-earth approximation anchored at `anchor`.
        let theta = anchor.headingDegrees * .pi / 180.0
        let dN = anchor.speedMps * silence * cos(theta)
        let dE = anchor.speedMps * silence * sin(theta)
        let (lat, lon) = offsetLatLon(
            fromLat: anchor.latitude,
            fromLon: anchor.longitude,
            northMeters: dN,
            eastMeters: dE
        )

        // Uncertainty: start with the anchor's own accuracy and grow
        // linearly with coast time. A more principled model would use
        // a Brownian drift (√t) on heading + linear on speed, but the
        // dispatch UI just renders a circle — a conservative linear
        // blow-up is fine and honest.
        let uncertainty = max(anchor.horizontalAccuracy, 0) + uncertaintyRatePerSec * coastElapsed

        estimate = CoastEstimate(
            latitude: lat,
            longitude: lon,
            headingDegrees: anchor.headingDegrees,
            speedMps: anchor.speedMps,
            uncertaintyMeters: uncertainty,
            coastElapsed: coastElapsed
        )

        // Escalation: flip the flag once and stay flipped until a good
        // fix resets us. Don't spam probe() on every tick.
        if coastElapsed >= satelliteEscalationSeconds, !satelliteEscalationDue {
            satelliteEscalationDue = true
            NotificationCenter.default.post(name: .deadZoneSatelliteEscalation, object: nil)
        }

        // Breadcrumb every N seconds while coasting so dispatch sees a
        // fresh "still in a dead zone at time T" ping even before we
        // reach satellite escalation.
        if lastBreadcrumbAt == nil ||
           now.timeIntervalSince(lastBreadcrumbAt ?? .distantPast) >= breadcrumbIntervalSeconds {
            lastBreadcrumbAt = now
            let txt = String(
                format: "EUSO COAST %.5f,%.5f h:%.0f v:%.1f±%.0fm t:%.0fs",
                lat, lon, anchor.headingDegrees, anchor.speedMps, uncertainty, coastElapsed
            )
            OfflineQueue.shared.enqueueMessage(
                loadId: LoadStore.shared.active?.id,
                to: "dispatch:breadcrumb",
                text: txt
            )
        }
    }

    // MARK: - Geometry helper

    /// Flat-earth offset. Good to a few ppm for horizons under a few
    /// dozen kilometres, which is the regime we care about here.
    private func offsetLatLon(
        fromLat lat: Double,
        fromLon lon: Double,
        northMeters dN: Double,
        eastMeters dE: Double
    ) -> (Double, Double) {
        let earthR = 6_378_137.0 // WGS-84 semi-major
        let dLat = dN / earthR
        let dLon = dE / (earthR * cos(lat * .pi / 180.0))
        return (lat + dLat * 180.0 / .pi, lon + dLon * 180.0 / .pi)
    }
}

// MARK: - Value types

extension DeadZoneCoast {
    struct Anchor: Equatable {
        let latitude: Double
        let longitude: Double
        let headingDegrees: Double
        let speedMps: Double
        let horizontalAccuracy: CLLocationAccuracy
        let at: Date
    }

    /// Snapshot of the current believed position + uncertainty. The UI
    /// binds to this; rendered on the map as a dot with an error halo.
    struct CoastEstimate: Equatable {
        let latitude: Double
        let longitude: Double
        let headingDegrees: Double
        let speedMps: Double
        let uncertaintyMeters: Double
        let coastElapsed: TimeInterval
    }
}

// MARK: - Notification names

extension Notification.Name {
    /// Fired once when Dead-Zone Coast crosses the escalation threshold.
    /// Observers (SatelliteFallback, HomeView) can react — e.g. kick off
    /// a `SatelliteFallback.probe(connectivity:)` call.
    static let deadZoneSatelliteEscalation = Notification.Name("eusotrip.deadZoneSatelliteEscalation")
}
