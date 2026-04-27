//
//  NavigationSession.swift
//  EusoTrip Pulse Watch App
//
//  F14 — Pulse Keep-Alive Navigation Session.
//
//  A thin turn-by-turn brain on the wrist. The iOS companion owns
//  route planning (truck-legal routing, HOS-aware waypoints, live
//  traffic). The watch owns the LAST MILE of that plan: pop the
//  next maneuver at the right moment, play a distance-banded haptic
//  so the driver doesn't have to glance down, and keep the wrist
//  alive across the full haul so the guidance doesn't drop on a
//  background sweep.
//
//  Session keep-alive strategy:
//    • If DrivingSessionManager already has a workout session open
//      (the normal case on a long haul), we piggyback on that one.
//      There is no benefit to a second HKWorkoutSession — they don't
//      stack, and starting a second would churn the first's
//      background-execution grant.
//    • If the driver starts navigation without a driving session
//      (rare: "walk me to the dock lane"), we ask the DrivingSession
//      to begin so the watch stays live. End-of-route doesn't end
//      the driving session — the driver might still be on duty.
//
//  Route ingest: `nav.route` applicationContext push from the phone.
//  Route shape: an ordered list of maneuvers (lat, lon, instruction,
//  maneuverKind, distanceFromStart). The phone is the routing engine;
//  the watch is just a consumer with local location awareness.
//
//  Haptic cadence:
//    2 miles out → "tentative" single click
//    1 mile out  → "heads-up" double click
//    0.25 mi out → "turn-now" triple click + primary
//    Arrival     → .success, then session collapses to `.arrived`.
//

import Foundation
import Combine
import CoreLocation
import WatchKit

/// What kind of maneuver is up next. Drives the directional icon in
/// the UI and (later) the Siri-style spoken hint. Ordered for server
/// parity — don't reorder raw values, they cross the WCSession wire.
enum ManeuverKind: String, Codable, Equatable {
    case depart
    case turnLeft
    case turnRight
    case slightLeft
    case slightRight
    case sharpLeft
    case sharpRight
    case keepLeft
    case keepRight
    case uTurn
    case merge
    case exit
    case ferry
    case tollPlaza
    case roundabout
    case arrive

    var glyph: String {
        switch self {
        case .depart:      return "location.fill"
        case .turnLeft:    return "arrow.turn.up.left"
        case .turnRight:   return "arrow.turn.up.right"
        case .slightLeft:  return "arrow.up.left"
        case .slightRight: return "arrow.up.right"
        case .sharpLeft:   return "arrow.uturn.up"
        case .sharpRight:  return "arrow.uturn.up"
        case .keepLeft:    return "arrow.up.left"
        case .keepRight:   return "arrow.up.right"
        case .uTurn:       return "arrow.uturn.up"
        case .merge:       return "arrow.merge"
        case .exit:        return "arrow.down.right"
        case .ferry:       return "ferry.fill"
        case .tollPlaza:   return "dollarsign.circle.fill"
        case .roundabout:  return "arrow.triangle.2.circlepath"
        case .arrive:      return "flag.checkered"
        }
    }
}

/// One waypoint the driver needs to act on. `latitude`/`longitude` is
/// where the driver's truck should be ABOUT TO perform the maneuver —
/// it's the arrival point, not the road segment start.
struct Maneuver: Codable, Equatable, Identifiable {
    var id: String { "\(index)-\(kind.rawValue)" }
    let index: Int
    let kind: ManeuverKind
    let instruction: String
    let latitude: Double
    let longitude: Double
    /// Distance from the start of the trip, in meters. Used by the
    /// active-step picker as a monotonic cursor so GPS wobble around
    /// a turn doesn't cause us to oscillate between two maneuvers.
    let cumulativeMeters: Double
    /// Optional road-class or street name, e.g. "I-20 W". Shown as a
    /// subtle line under the instruction.
    let road: String?
}

/// Which "band" of proximity the active maneuver is currently in.
/// Used for the haptic de-dupe — the same band doesn't re-fire its
/// haptic on subsequent location updates.
enum ManeuverBand: Int, Comparable {
    case far      = 0  // > 2 miles
    case tentative = 1  // 2 miles .. 1 mile
    case headsUp   = 2  // 1 mile .. 0.25 mile
    case turnNow   = 3  // < 0.25 mile
    case passed    = 4  // we went past it

    static func < (lhs: ManeuverBand, rhs: ManeuverBand) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

@MainActor
final class NavigationSession: ObservableObject {
    static let shared = NavigationSession()

    // MARK: - Published state

    @Published private(set) var isActive: Bool = false
    @Published private(set) var routeId: String?
    @Published private(set) var maneuvers: [Maneuver] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var distanceToNextMeters: Double = .infinity
    @Published private(set) var band: ManeuverBand = .far
    @Published private(set) var remainingMeters: Double = 0
    @Published private(set) var hasArrived: Bool = false

    /// Derived convenience — the current maneuver, if any.
    var nextManeuver: Maneuver? {
        guard isActive, maneuvers.indices.contains(currentIndex) else { return nil }
        return maneuvers[currentIndex]
    }

    // MARK: - Private state

    /// The highest band we've fired a haptic for on the CURRENT
    /// maneuver. Gets reset when `currentIndex` advances so the next
    /// turn gets its own haptic ladder.
    private var lastHapticBand: ManeuverBand = .far

    /// When the driver overshoots a maneuver we need to advance the
    /// cursor. Track the min distance we saw for the active maneuver
    /// so "past" is unambiguous (distance grew after bottoming out).
    private var minDistanceSeenForCurrent: Double = .infinity

    // MARK: - Lifecycle

    /// Ingest a freshly-planned route from the iOS companion. Starts
    /// the keep-alive workout session if the driver isn't already in
    /// one, and resets the cursor to maneuver 0.
    func startRoute(routeId: String, maneuvers: [Maneuver]) {
        guard EusoTripConfig.keepAliveNavigationEnabled else { return }
        guard !maneuvers.isEmpty else { return }
        self.routeId = routeId
        self.maneuvers = maneuvers
        self.currentIndex = 0
        self.distanceToNextMeters = .infinity
        self.band = .far
        self.lastHapticBand = .far
        self.minDistanceSeenForCurrent = .infinity
        self.remainingMeters = totalRemaining(fromIndex: 0, cursorMeters: 0)
        self.hasArrived = false
        self.isActive = true
        ensureKeepAlive()
        WKInterfaceDevice.current().play(.start)
        if EusoTripConfig.blockchainAuditEnabled {
            BlockchainAudit.shared.append(
                kind: .voiceIntent,
                payload: [
                    "route": routeId,
                    "maneuvers": String(maneuvers.count)
                ]
            )
        }
    }

    /// Collapse the nav session. Does NOT end the underlying driving
    /// session — the driver may still be on duty.
    func endRoute() {
        isActive = false
        hasArrived = false
        maneuvers = []
        routeId = nil
        currentIndex = 0
        lastHapticBand = .far
        distanceToNextMeters = .infinity
        band = .far
        remainingMeters = 0
    }

    /// Called by DrivingSessionManager every time a CLLocation arrives.
    /// Must be fast — this is on the main hot path of the location
    /// fan-out and a slow implementation would stall TunnelAwareETA
    /// and the fatigue predictor tick.
    func ingest(_ location: CLLocation) {
        guard isActive, let current = nextManeuver else { return }
        let d = haversineMeters(
            lat1: location.coordinate.latitude,
            lon1: location.coordinate.longitude,
            lat2: current.latitude,
            lon2: current.longitude
        )
        distanceToNextMeters = d
        let newBand = bandFor(meters: d)
        band = newBand

        // Remaining distance = (current maneuver's cumulativeMeters)
        // minus how far along this leg we are + everything after.
        let prevCum = currentIndex > 0
            ? maneuvers[currentIndex - 1].cumulativeMeters
            : 0
        let legLen = max(1, current.cumulativeMeters - prevCum)
        let progressOnLeg = max(0, min(legLen, legLen - d))
        let after = maneuvers.last.map { $0.cumulativeMeters - current.cumulativeMeters } ?? 0
        remainingMeters = max(0, (legLen - progressOnLeg) + after)

        fireHapticIfNeeded(for: newBand)
        advanceIfPassed(distance: d)
    }

    // MARK: - Cursor advancement

    /// When the driver has clearly passed the current maneuver, advance
    /// the cursor. Heuristic: distance hit a local minimum and is now
    /// growing by more than 25m (more robust than "crossed the
    /// waypoint" which fails on wide intersections and tunnel emerge).
    private func advanceIfPassed(distance d: Double) {
        if d < minDistanceSeenForCurrent {
            minDistanceSeenForCurrent = d
        }
        let advanced = d - minDistanceSeenForCurrent > 25 && minDistanceSeenForCurrent < 120
        if advanced {
            advanceCursor()
        }
    }

    private func advanceCursor() {
        // If the maneuver we just finished was `.arrive`, collapse to
        // the arrived state and fire the arrival haptic. Don't call
        // endRoute automatically — dispatch might want to keep the
        // session open to chain a second leg onto it.
        if let current = nextManeuver, current.kind == .arrive {
            hasArrived = true
            isActive = false
            WKInterfaceDevice.current().play(.success)
            if EusoTripConfig.blockchainAuditEnabled {
                BlockchainAudit.shared.append(
                    kind: .loadArrived,
                    payload: ["route": routeId ?? ""]
                )
            }
            return
        }
        currentIndex += 1
        lastHapticBand = .far
        minDistanceSeenForCurrent = .infinity
        if currentIndex >= maneuvers.count {
            hasArrived = true
            isActive = false
        }
    }

    // MARK: - Haptics

    private func fireHapticIfNeeded(for newBand: ManeuverBand) {
        guard newBand.rawValue > lastHapticBand.rawValue else { return }
        let device = WKInterfaceDevice.current()
        switch newBand {
        case .tentative:
            device.play(.click)
        case .headsUp:
            device.play(.directionUp)  // two-tap watchOS haptic
        case .turnNow:
            // Triple beat on a sharp turn to make sure the driver
            // registers it even in a noisy cab.
            device.play(.notification)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                device.play(.click)
                try? await Task.sleep(nanoseconds: 150_000_000)
                device.play(.click)
            }
        default:
            break
        }
        lastHapticBand = newBand
    }

    private func bandFor(meters: Double) -> ManeuverBand {
        let miles = meters / 1609.344
        if miles > 2 { return .far }
        if miles > 1 { return .tentative }
        if miles > 0.25 { return .headsUp }
        return .turnNow
    }

    // MARK: - Keep-alive

    /// Make sure the watch will stay live while navigating. If the
    /// driving session is already running (typical long-haul case),
    /// this is a no-op — HKWorkoutSession grants are already in hand.
    /// Otherwise kick DrivingSessionManager so the OS keeps us alive.
    private func ensureKeepAlive() {
        guard !DrivingSessionManager.shared.isRunning else { return }
        DrivingSessionManager.shared.begin()
    }

    // MARK: - Geodesy

    /// Great-circle distance in meters. Using haversine because for
    /// truck dispatch we routinely plan routes that span lat/lon
    /// boxes where flat-earth error grows past 1% of the leg length.
    private func haversineMeters(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let earthR = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
            * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthR * c
    }

    private func totalRemaining(fromIndex index: Int, cursorMeters: Double) -> Double {
        guard maneuvers.indices.contains(index) else { return 0 }
        let start = index == 0 ? 0 : maneuvers[index - 1].cumulativeMeters
        let total = maneuvers.last?.cumulativeMeters ?? 0
        return max(0, total - start - cursorMeters)
    }
}

// MARK: - WatchConnectivity ingest helpers

extension NavigationSession {
    /// Decode a `nav.route` payload forwarded from the iOS companion.
    /// The phone JSON-encodes the route plan and base64s the bytes so
    /// WCSession's plist shape doesn't flatten the nested maneuver
    /// structure. Keep this separate from `startRoute` so unit tests
    /// can drive `startRoute` directly with test fixtures.
    func ingestRemoteRouteB64(_ b64: String, routeId: String) {
        guard let data = Data(base64Encoded: b64) else { return }
        struct RemoteRoute: Decodable {
            let maneuvers: [Maneuver]
        }
        guard let route = try? JSONDecoder().decode(RemoteRoute.self, from: data) else { return }
        startRoute(routeId: routeId, maneuvers: route.maneuvers)
    }
}
