// EusoTrip/Services/HereMaps/TurnByTurnNavigator.swift
//
// L13-3 — Turn-by-turn navigation engine.
//
// Consumes HERE-authored `actions` (maneuvers) plus the section's DECODED
// flexible polyline, projects each live GPS fix onto the route to advance the
// maneuver pointer, speaks voice prompts at 300 m / 100 m, and raises
// `onDeviation` when the driver is genuinely off-route (cross-track > 75 m AND
// heading divergence > 45° for 3 consecutive fixes) so the caller can re-request
// a truck route from HERE and `start(…)` the new geometry.
//
// Standalone engine: drive `ingest(fix:)` from any CLLocation feed (the active
// en-route screen's own manager, or the shared DriverGPSPushService delegate).
// Gated in UI behind the remote `tbtEnabled` flag; the facade card is the
// fallback branch when the flag is off.

import Foundation
import CoreLocation
import AVFoundation

/// One resolved maneuver anchored to a coordinate on the decoded polyline.
struct Maneuver: Identifiable, Equatable {
    let id: Int                     // index in the list
    let instruction: String
    let action: String
    let direction: String?
    let coordinate: CLLocationCoordinate2D   // polyline[offset]
    let metersFromRouteStart: Double

    static func == (lhs: Maneuver, rhs: Maneuver) -> Bool {
        lhs.id == rhs.id &&
        lhs.instruction == rhs.instruction &&
        lhs.action == rhs.action &&
        lhs.direction == rhs.direction &&
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.metersFromRouteStart == rhs.metersFromRouteStart
    }

    /// SF Symbol glyph for the maneuver list / card (best-effort mapping).
    var directionGlyph: String {
        switch action.lowercased() {
        case "depart":  return "location.fill"
        case "arrive":  return "flag.checkered"
        case "exit":    return "arrow.turn.up.right"
        default: break
        }
        switch (direction ?? "").lowercased() {
        case "left":        return "arrow.turn.up.left"
        case "slightleft":  return "arrow.up.left"
        case "sharpleft":   return "arrow.uturn.left"
        case "right":       return "arrow.turn.up.right"
        case "slightright": return "arrow.up.right"
        case "sharpright":  return "arrow.uturn.right"
        default:            return "arrow.up"
        }
    }
}

@MainActor
final class TurnByTurnNavigator: NSObject, ObservableObject {
    @Published private(set) var maneuvers: [Maneuver] = []
    @Published private(set) var currentManeuver: Maneuver?
    @Published private(set) var distanceToManeuverM: Double = .infinity
    @Published var voiceEnabled = true
    @Published private(set) var isRerouting = false

    private var polyline: [CLLocationCoordinate2D] = []
    private var cumulative: [Double] = []             // meters from start per vertex
    private var offRouteStreak = 0
    private var spokenIds = Set<String>()             // "maneuverId@300" / "@100"
    private let synth = AVSpeechSynthesizer()
    var onDeviation: ((CLLocation) -> Void)?          // wire to HereRoutingClient re-request

    // MARK: route intake

    /// Convenience: build the navigator directly from a decoded route section.
    /// Decodes the flexible polyline and forwards the section's `actions`.
    func start(section: HereRouteSection) {
        let coords = HereFlexiblePolyline.decode(section.polyline)
        start(polyline: coords, actions: section.actions ?? [])
    }

    func start(polyline coords: [CLLocationCoordinate2D], actions: [HereRouteAction]) {
        polyline = coords
        cumulative = Self.cumulativeDistances(coords)
        maneuvers = actions.enumerated().compactMap { idx, a in
            guard let off = a.offset, off >= 0, off < coords.count,
                  let text = a.instruction else { return nil }
            return Maneuver(id: idx, instruction: text, action: a.action,
                            direction: a.direction, coordinate: coords[off],
                            metersFromRouteStart: cumulative[off])
        }
        currentManeuver = maneuvers.first
        distanceToManeuverM = .infinity
        offRouteStreak = 0
        isRerouting = false                               // new geometry ends any active reroute
        spokenIds.removeAll()
    }

    /// Called by the host when a reroute request fails (or returns no route)
    /// so the driver isn't stranded in the "rerouting…" state indefinitely.
    func clearRerouting() {
        isRerouting = false
        offRouteStreak = 0
    }

    func stop() {
        maneuvers = []; currentManeuver = nil; polyline = []; cumulative = []
        distanceToManeuverM = .infinity
        offRouteStreak = 0
        spokenIds.removeAll()
        synth.stopSpeaking(at: .immediate)
    }

    // MARK: fix intake (call from the driver's live location feed)
    func ingest(fix: CLLocation) {
        guard !polyline.isEmpty else { return }
        let (segIdx, crossTrackM, alongM) = Self.project(fix.coordinate, onto: polyline, cumulative: cumulative)

        // 1. deviation detection: distance-from-polyline + heading divergence
        let segBearing = Self.bearing(polyline[segIdx], polyline[min(segIdx + 1, polyline.count - 1)])
        let headingOff = fix.course >= 0 ? abs(Self.angleDelta(fix.course, segBearing)) : 0
        if crossTrackM > 75, headingOff > 45 || fix.course < 0 {
            offRouteStreak += 1
            if offRouteStreak >= 3, !isRerouting {
                isRerouting = true
                onDeviation?(fix)                     // caller re-routes, then start(…) again
                return
            }
        } else { offRouteStreak = 0; isRerouting = false }

        // 2. advance the maneuver pointer by along-route progress
        currentManeuver = maneuvers.first(where: { $0.metersFromRouteStart > alongM + 5 })
        guard let m = currentManeuver else { distanceToManeuverM = .infinity; return }
        distanceToManeuverM = m.metersFromRouteStart - alongM

        // 3. voice at 300 m / 100 m
        for gate in [300.0, 100.0] where distanceToManeuverM <= gate {
            let key = "\(m.id)@\(Int(gate))"
            if voiceEnabled, !spokenIds.contains(key) {
                spokenIds.insert(key)
                let u = AVSpeechUtterance(string: gate == 300
                    ? "In 300 meters, \(m.instruction)" : m.instruction)
                u.rate = AVSpeechUtteranceDefaultSpeechRate
                synth.speak(u)
            }
        }
    }

    // MARK: geometry helpers
    static func cumulativeDistances(_ c: [CLLocationCoordinate2D]) -> [Double] {
        var out: [Double] = [0]; out.reserveCapacity(c.count)
        guard c.count > 1 else { return out }
        for i in 1..<c.count {
            out.append(out[i - 1] + CLLocation(latitude: c[i - 1].latitude, longitude: c[i - 1].longitude)
                .distance(from: CLLocation(latitude: c[i].latitude, longitude: c[i].longitude)))
        }
        return out
    }

    /// Returns (segmentIndex, crossTrackMeters, alongRouteMeters) for the nearest segment.
    static func project(_ p: CLLocationCoordinate2D, onto line: [CLLocationCoordinate2D],
                        cumulative: [Double]) -> (Int, Double, Double) {
        var best = (idx: 0, cross: Double.greatestFiniteMagnitude, along: 0.0)
        guard line.count > 1 else { return (0, 0, 0) }
        let pt = CLLocation(latitude: p.latitude, longitude: p.longitude)
        for i in 0..<(line.count - 1) {
            let a = CLLocation(latitude: line[i].latitude, longitude: line[i].longitude)
            let b = CLLocation(latitude: line[i + 1].latitude, longitude: line[i + 1].longitude)
            let ab = a.distance(from: b); guard ab > 0.5 else { continue }
            let ap = a.distance(from: pt)
            let t = max(0, min(1, ((pt.coordinate.latitude - a.coordinate.latitude) * (b.coordinate.latitude - a.coordinate.latitude)
                + (pt.coordinate.longitude - a.coordinate.longitude) * (b.coordinate.longitude - a.coordinate.longitude))
                / ((b.coordinate.latitude - a.coordinate.latitude) * (b.coordinate.latitude - a.coordinate.latitude)
                + (b.coordinate.longitude - a.coordinate.longitude) * (b.coordinate.longitude - a.coordinate.longitude) + .ulpOfOne)))
            let proj = CLLocation(latitude: a.coordinate.latitude + t * (b.coordinate.latitude - a.coordinate.latitude),
                                  longitude: a.coordinate.longitude + t * (b.coordinate.longitude - a.coordinate.longitude))
            let cross = pt.distance(from: proj)
            if cross < best.cross { best = (i, cross, cumulative[i] + t * ab); _ = ap }
        }
        return (best.idx, best.cross, best.along)
    }

    static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    static func angleDelta(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }
}
