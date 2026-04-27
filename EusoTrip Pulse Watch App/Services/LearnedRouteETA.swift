//
//  LearnedRouteETA.swift
//  EusoTrip Pulse Watch App
//
//  F06 — Offline ETA from Learned Route History (Q3 2026 offline-mode tier).
//
//  The strategy doc defines this as "per-driver Create ML tabular regressor
//  trained on (road_segment_id, hour_of_week, weather_flag, is_loaded) →
//  observed_speed." That full Create ML training loop requires a multi-week
//  data-collection phase. In the meantime, we ship a runtime-only EWMA
//  estimator that:
//
//    1. Buckets live CLLocation fixes into a coarse H3-ish lat/lon grid
//       (~1.2 km cells — granular enough for highway segments, not so
//       granular that we balloon the sparse matrix).
//    2. Maintains an exponentially-weighted moving average of observed
//       speed per (cell, hour-of-week bucket).
//    3. Persists to Application Support as JSON so a new drive inherits
//       what the wrist learned yesterday.
//
//  Lookup: `estimatedSpeedMPS(at coord: hour:)` returns the EWMA estimate
//  or nil if the cell/hour is unknown — callers fall back to the global
//  speed-limit prior. `estimatedSecondsTo(coordinates:)` sums segment
//  times over an ordered coordinate list (the planned route).
//
//  This file is self-contained and ships TODAY as part of the Q2 keystone
//  wave. The Create ML tabular regressor replaces EWMA in a follow-up; the
//  public API is stable so consumers (RouteOverviewView, ETA ribbons) don't
//  change when the backing estimator swaps.
//

import Foundation
import CoreLocation
import Combine

/// Coarse grid cell (~1.2 km at 40°N). Coordinates truncated to 2 decimal
/// places give us roughly that resolution while keeping the key space
/// small enough for a wrist-class store.
struct RouteGridCell: Hashable, Codable {
    let latBucket: Int   // round(lat * 100)
    let lonBucket: Int   // round(lon * 100)

    init(_ coord: CLLocationCoordinate2D) {
        latBucket = Int((coord.latitude  * 100).rounded())
        lonBucket = Int((coord.longitude * 100).rounded())
    }

    init(latBucket: Int, lonBucket: Int) {
        self.latBucket = latBucket
        self.lonBucket = lonBucket
    }

    /// Approximate back to a center-point CLLocation for distance math.
    var centerCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude:  Double(latBucket) / 100.0,
            longitude: Double(lonBucket) / 100.0
        )
    }
}

/// A (cell, hour-of-week) observation bucket. 168 hours per week lets the
/// estimator distinguish Tuesday-afternoon rush from Sunday-morning empty.
struct SegmentBucket: Hashable, Codable {
    let cell: RouteGridCell
    let hourOfWeek: Int   // 0..<168; 0 = Mon 00:00 local

    /// Derive from a CLLocation's timestamp + coordinate.
    init(location: CLLocation) {
        self.cell = RouteGridCell(location.coordinate)
        self.hourOfWeek = Self.hourOfWeek(from: location.timestamp)
    }

    init(cell: RouteGridCell, hourOfWeek: Int) {
        self.cell = cell
        self.hourOfWeek = hourOfWeek
    }

    static func hourOfWeek(from date: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let comps = cal.dateComponents([.weekday, .hour], from: date)
        // Calendar weekday: Sunday=1..Saturday=7; shift so Monday=0.
        let weekdayZeroIndexed = ((comps.weekday ?? 1) + 5) % 7
        let hour = comps.hour ?? 0
        return weekdayZeroIndexed * 24 + hour
    }
}

/// Persisted EWMA sample: mean + accumulated weight so the estimator
/// keeps its "confidence" across app launches.
struct SegmentSample: Codable {
    var meanSpeedMPS: Double
    var weight: Double    // effective sample count
}

@MainActor
final class LearnedRouteETA: ObservableObject {
    static let shared = LearnedRouteETA()

    /// EWMA decay — 0.15 weights the most recent ~7 samples heavily,
    /// long-tail history lightly. Tuned so a construction-zone slowdown
    /// dominates the estimate after a couple of passes but doesn't
    /// immediately overwrite six months of stable history.
    private let alpha: Double = 0.15

    /// Maximum samples retained; evicts the lowest-weight entry when hit.
    private let maxBuckets: Int = 4_000

    /// Minimum speed we'll treat as "moving." Below this the driver is
    /// probably at a scale, a light, or parked — contaminating the
    /// learned rolling speed with those samples makes every cell look
    /// like a traffic jam.
    private let minTrainingSpeedMPS: Double = 3.0   // ~6.7 mph

    /// Global fallback speed prior (26.8 m/s ≈ 60 mph) — used for any
    /// cell we haven't observed. Intentionally conservative so an ETA
    /// isn't wildly optimistic for unknown territory.
    static let defaultSpeedMPS: Double = 26.8

    @Published private(set) var samplesCount: Int = 0
    @Published private(set) var lastTrainedAt: Date?

    private var store: [SegmentBucket: SegmentSample] = [:]

    private let fileURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("learned-route-eta.json")
    }()

    private var dirty: Bool = false
    private var lastPersistAt: Date = .distantPast

    // MARK: - Persistence

    /// Load the EWMA store from disk. Idempotent. Safe to call at launch
    /// before any observations have landed.
    func restore() {
        guard EusoTripConfig.learnedRouteETAEnabled else { return }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            // Snapshot is stored as parallel arrays so the JSON stays
            // small and `Codable` doesn't need a keyed dict with custom
            // key types.
            var restored: [SegmentBucket: SegmentSample] = [:]
            for entry in snap.entries {
                restored[entry.bucket] = entry.sample
            }
            self.store = restored
            self.samplesCount = restored.count
            self.lastTrainedAt = snap.lastTrainedAt
        }
    }

    private func persistIfDue() {
        // Rate-limit disk writes. A long drive produces ~1 location/sec;
        // persisting on every observation would spam the journal.
        guard dirty else { return }
        if Date().timeIntervalSince(lastPersistAt) < 30 { return }
        lastPersistAt = Date()
        dirty = false
        let snap = Snapshot(
            entries: store.map { SnapshotEntry(bucket: $0.key, sample: $0.value) },
            lastTrainedAt: lastTrainedAt
        )
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Force a flush to disk — called from scenePhase .background so we
    /// don't lose the last 30 seconds of observations when the user
    /// drops the wrist.
    func flush() {
        guard EusoTripConfig.learnedRouteETAEnabled else { return }
        dirty = true
        lastPersistAt = .distantPast
        persistIfDue()
    }

    // MARK: - Ingest

    /// Feed a freshly-observed CLLocation. Folds the observed speed into
    /// the EWMA for the matching (cell, hour-of-week) bucket. Called by
    /// `DrivingSessionManager` on every fix while tunnelAwareETAEnabled
    /// or learnedRouteETAEnabled is on (they share the location pump).
    func ingest(_ location: CLLocation) {
        guard EusoTripConfig.learnedRouteETAEnabled else { return }
        // Reject stationary / unreliable samples.
        guard location.speed >= minTrainingSpeedMPS else { return }
        // Reject samples where the coord accuracy is negative (invalid
        // fix, e.g. the DR sentinel from TunnelAwareETA).
        guard location.horizontalAccuracy >= 0 else { return }

        let bucket = SegmentBucket(location: location)
        let observed = location.speed

        if var sample = store[bucket] {
            sample.meanSpeedMPS = (1 - alpha) * sample.meanSpeedMPS + alpha * observed
            sample.weight = min(sample.weight + 1, 1_000) // cap so old history can still budge
            store[bucket] = sample
        } else {
            if store.count >= maxBuckets {
                // Evict lowest-weight bucket. Linear scan is fine at
                // 4k entries; wrist CPU handles it in <1ms.
                if let victim = store.min(by: { $0.value.weight < $1.value.weight })?.key {
                    store.removeValue(forKey: victim)
                }
            }
            store[bucket] = SegmentSample(meanSpeedMPS: observed, weight: 1)
        }

        samplesCount = store.count
        lastTrainedAt = location.timestamp
        dirty = true
        persistIfDue()
    }

    // MARK: - Queries

    /// Best-available speed estimate for a coordinate at a given time.
    /// Returns nil when the cell hasn't been observed at any hour — the
    /// caller should then fall back to `defaultSpeedMPS`.
    func estimatedSpeedMPS(at coord: CLLocationCoordinate2D, when date: Date = Date()) -> Double? {
        let cell = RouteGridCell(coord)
        let hour = SegmentBucket.hourOfWeek(from: date)

        // 1) exact cell + hour
        if let s = store[SegmentBucket(cell: cell, hourOfWeek: hour)] {
            return s.meanSpeedMPS
        }

        // 2) same cell, any hour — weight-average
        var totalWeighted: Double = 0
        var totalWeight: Double = 0
        for h in 0..<168 {
            if let s = store[SegmentBucket(cell: cell, hourOfWeek: h)] {
                totalWeighted += s.meanSpeedMPS * s.weight
                totalWeight += s.weight
            }
        }
        if totalWeight > 0 { return totalWeighted / totalWeight }

        return nil
    }

    /// Estimate drive seconds across an ordered list of waypoints by
    /// summing per-segment times. A waypoint without a learned speed
    /// falls back to `defaultSpeedMPS`. `departAt` defaults to now so a
    /// caller can pass a future time to query "if I leave at 4pm …".
    func estimatedSecondsTo(coordinates: [CLLocationCoordinate2D], departAt: Date = Date()) -> TimeInterval {
        guard coordinates.count >= 2 else { return 0 }
        var seconds: TimeInterval = 0
        var clock = departAt
        for i in 1..<coordinates.count {
            let a = coordinates[i - 1]
            let b = coordinates[i]
            let loc1 = CLLocation(latitude: a.latitude, longitude: a.longitude)
            let loc2 = CLLocation(latitude: b.latitude, longitude: b.longitude)
            let meters = loc1.distance(from: loc2)

            // Use midpoint cell for the query (biases the estimate
            // toward the segment being traversed, not just the start).
            let mid = CLLocationCoordinate2D(
                latitude:  (a.latitude  + b.latitude)  / 2,
                longitude: (a.longitude + b.longitude) / 2
            )
            let speed = estimatedSpeedMPS(at: mid, when: clock) ?? Self.defaultSpeedMPS
            let segmentSeconds = meters / max(speed, 5)
            seconds += segmentSeconds
            clock = clock.addingTimeInterval(segmentSeconds)
        }
        return seconds
    }

    /// How many distinct cells have been observed. Surfaced by Debug
    /// View so fleet admins can sanity-check that learning is happening.
    var distinctCellsObserved: Int {
        Set(store.keys.map { $0.cell }).count
    }

    // MARK: - Snapshot serialization

    private struct SnapshotEntry: Codable {
        let bucket: SegmentBucket
        let sample: SegmentSample
    }

    private struct Snapshot: Codable {
        let entries: [SnapshotEntry]
        let lastTrainedAt: Date?
    }
}
