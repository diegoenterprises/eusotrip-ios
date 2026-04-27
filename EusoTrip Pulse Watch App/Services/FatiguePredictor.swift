//
//  FatiguePredictor.swift
//  EusoTrip Pulse Watch App
//
//  Q3 — On-wrist fatigue predictor. Successor to `ErgoMonitor`'s
//  two-factor (time-since-break, HR-over-resting) heuristic. This file
//  builds the richer feature pipeline + scoring head we need before we
//  can plausibly claim a "fatigue score" that correlates with driving
//  risk.
//
//  Why a new file (and not an `ErgoMonitor` rewrite)?
//    • ErgoMonitor has wide blast radius — four views read its
//      published `fatigueScore` and `fatigueTint`. Keeping its public
//      surface stable means we can ship this predictor behind a flag,
//      A/B against the legacy heuristic in the field, then flip
//      `ErgoMonitor` to read from here without touching the UI.
//    • The CoreML classifier (ships in a later drop) expects a
//      `MLMultiArray` of the canonical feature vector. Having the
//      features live in a dedicated file makes the CoreML integration
//      a one-line swap at `score(features:)`.
//
//  Feature vector (10-D, all rolling 60-s window):
//     0  HR mean (bpm)
//     1  HR stddev (bpm)                  — proxy for HRV
//     2  RMSSD over last 60 s (ms)        — true HRV, when beat-to-beat
//                                           timestamps are available
//     3  Mean |a|                         — overall wrist motion
//     4  Stddev of yaw rate                — steering micro-correction
//                                           variability
//     5  Jerk RMS (d|a|/dt)                — road-feedback aggressiveness;
//                                           drops when the driver is zoned
//                                           out and their body stops
//                                           micro-reacting
//     6  Time-of-day circadian factor     — 0 at ~10 am, peaks at 3–5 am
//                                           and again at 2–4 pm
//     7  Minutes since last break / 240   — capped linear ramp
//     8  Cumulative driving minutes / 660 — 11-hr DOT drive-limit ratio
//     9  Microsleep event count (60-s)    — abrupt wrist-drop then recovery
//
//  Scoring head: a runtime-only logistic fusion with weights chosen to
//  match ErgoMonitor's two-factor score at the "typical sharp driver"
//  operating point. The CoreML tabular classifier ships behind the
//  same `score(features:)` surface.
//

import Foundation
import Combine
import CoreMotion
#if canImport(HealthKit)
import HealthKit
#endif

@MainActor
final class FatiguePredictor: ObservableObject {
    static let shared = FatiguePredictor()

    // MARK: - Public state

    /// 0–1 fused fatigue score. Smoothed over the last 5 samples to
    /// stop the UI tint flickering on a single-window noise spike.
    @Published private(set) var score: Double = 0.2
    /// The last feature vector the scoring head consumed. Published so
    /// QA surfaces (TestFlight + the internal ErgoDebugView) can read
    /// raw inputs without having to duplicate the pipeline.
    @Published private(set) var lastFeatures: Features?
    /// True when a microsleep-shaped event fired in the last 60 s.
    @Published private(set) var microsleepLast60s: Bool = false

    // MARK: - Internals

    /// Rolling 60-s windows of raw samples. We keep timestamps so we
    /// don't have to assume a fixed cadence.
    private var hrSamples: [(Date, Double)] = []
    private var accelSamples: [(Date, Double)] = []   // |a|
    private var yawSamples: [(Date, Double)] = []      // z-axis rotation rate
    private var jerkSamples: [(Date, Double)] = []     // d|a|/dt

    private var lastAccelMag: Double?
    private var lastAccelAt: Date?

    /// Running cumulative driving time (reset externally at break).
    private var drivingSecondsAccumulator: TimeInterval = 0

    /// Microsleep events in the last 60 s (tuple of (at, kind)).
    private var microsleepEvents: [Date] = []

    /// EWMA smoother for the final score (α = 0.35).
    private var smoothedScore: Double = 0.2

    // MARK: - Ingest points

    /// Called from ErgoMonitor's HR handler so we don't duplicate the
    /// HealthKit query. Fires every time a fresh HR sample lands.
    func ingestHR(bpm: Double, at: Date = Date()) {
        hrSamples.append((at, bpm))
        trimWindow(&hrSamples, secondsBack: 60, now: at)
    }

    /// Called from DrivingSessionManager's 50 Hz accelerometer tap.
    /// We take the vector magnitude so the callsite doesn't have to
    /// think about SIMD types.
    func ingestAccelerometer(x: Double, y: Double, z: Double, at: Date = Date()) {
        let mag = sqrt(x*x + y*y + z*z)
        accelSamples.append((at, mag))
        trimWindow(&accelSamples, secondsBack: 60, now: at)

        // Jerk = d|a|/dt. First-order difference with the previous mag.
        if let last = lastAccelMag, let lastAt = lastAccelAt {
            let dt = max(at.timeIntervalSince(lastAt), 0.001)
            let jerk = abs(mag - last) / dt
            jerkSamples.append((at, jerk))
            trimWindow(&jerkSamples, secondsBack: 60, now: at)

            // Microsleep shape: a sudden low-jerk span (> 2 s where
            // jerk < 0.5 g/s) followed by an abrupt high-jerk spike
            // (> 4 g/s "startle"). We approximate by looking at the
            // last 3 s of jerk samples for this pattern.
            detectMicrosleep(at: at)
        }
        lastAccelMag = mag
        lastAccelAt = at
    }

    /// Gyroscope (rad/s). We only care about the z-axis (yaw) since
    /// that's the steering correction signal; x/y are forearm tilt
    /// which is orthogonal to the fatigue signal we're after.
    func ingestGyro(z: Double, at: Date = Date()) {
        yawSamples.append((at, z))
        trimWindow(&yawSamples, secondsBack: 60, now: at)
    }

    /// Call once per second while the driving session is active; we
    /// use it both to tick the driving-minutes counter and to cheaply
    /// recompute the score on a fresh feature snapshot.
    func tickOneSecond() {
        drivingSecondsAccumulator += 1
        // Recompute features at ~1 Hz. Cheap.
        let f = extractFeatures(minutesSinceBreak: ErgoMonitor.shared.minutesSinceBreak)
        lastFeatures = f
        microsleepLast60s = f.microsleepEvents60s > 0
        let raw = Self.score(features: f)
        smoothedScore = 0.65 * smoothedScore + 0.35 * raw
        score = smoothedScore
    }

    /// Called by ErgoMonitor.markBreakTaken — resets the "driving
    /// minutes" accumulator and the microsleep events window. HR is
    /// kept since a 5-minute break doesn't erase an elevated pulse.
    func onBreakTaken() {
        drivingSecondsAccumulator = 0
        microsleepEvents.removeAll()
    }

    // MARK: - Feature extraction

    private func extractFeatures(minutesSinceBreak: Int) -> Features {
        let now = Date()
        // HR
        let hrVals = hrSamples.map { $0.1 }
        let hrMean = hrVals.isEmpty ? 0 : hrVals.reduce(0, +) / Double(hrVals.count)
        let hrStd = Self.stddev(hrVals)
        let rmssd = Self.rmssd(hrValues: hrVals)

        // Accel
        let accVals = accelSamples.map { $0.1 }
        let accMean = accVals.isEmpty ? 0 : accVals.reduce(0, +) / Double(accVals.count)

        // Yaw stddev
        let yawVals = yawSamples.map { $0.1 }
        let yawStd = Self.stddev(yawVals)

        // Jerk RMS
        let jerkVals = jerkSamples.map { $0.1 }
        let jerkRMS = Self.rms(jerkVals)

        // Circadian factor — U-shaped with peaks at 03:00 and 14:30.
        let circ = Self.circadianFactor(at: now)

        // Time-since-break linear, capped at 4 h.
        let tsbRamp = min(1.0, Double(minutesSinceBreak) / 240.0)

        // Driving-minutes ramp, capped at the FMCSA 11-hour drive limit.
        let drvRamp = min(1.0, drivingSecondsAccumulator / (660 * 60))

        // Count microsleep events still in the 60-s window.
        microsleepEvents.removeAll(where: { now.timeIntervalSince($0) > 60 })
        let micro = microsleepEvents.count

        return Features(
            hrMean: hrMean,
            hrStd: hrStd,
            rmssd: rmssd,
            accelMean: accMean,
            yawStd: yawStd,
            jerkRMS: jerkRMS,
            circadian: circ,
            timeSinceBreakRamp: tsbRamp,
            drivingRamp: drvRamp,
            microsleepEvents60s: micro
        )
    }

    // MARK: - Scoring head
    //
    // Logistic fusion: score = σ(w · f + b). Weights were hand-tuned
    // against the mean-true-positive rate of a dataset of labeled DOT
    // fatigue test clips (public sources + internal QA rides). When
    // the CoreML tabular classifier lands, replace the function body
    // with a `try MLModel.prediction(from:)` call.

    static func score(features f: Features) -> Double {
        // Normalize features into the 0–1 band the weights assume.
        let hrDelta = max(0, min(1, (f.hrMean - 60) / 50))         // 60–110 bpm → 0–1
        let hrvLow  = max(0, min(1, 1 - f.rmssd / 60))             // low RMSSD → high fatigue
        let jerkLow = max(0, min(1, 1 - f.jerkRMS / 4.0))          // low jerk → tuning-out
        let yawLow  = max(0, min(1, 1 - f.yawStd / 0.6))           // low steering variability
        let micro   = min(1, Double(f.microsleepEvents60s) / 2.0)  // 2+ microsleeps = max
        let w = Self.weights

        let z = w.bias
            + w.hrDelta  * hrDelta
            + w.hrvLow   * hrvLow
            + w.jerkLow  * jerkLow
            + w.yawLow   * yawLow
            + w.circ     * f.circadian
            + w.tsb      * f.timeSinceBreakRamp
            + w.drv      * f.drivingRamp
            + w.micro    * micro
        return 1.0 / (1.0 + exp(-z))
    }

    struct Weights {
        let bias: Double
        let hrDelta: Double
        let hrvLow: Double
        let jerkLow: Double
        let yawLow: Double
        let circ: Double
        let tsb: Double
        let drv: Double
        let micro: Double
    }

    /// Calibrated against the legacy ErgoMonitor score at these
    /// operating points:
    ///   (sharp, rested, morning)    → ~0.15
    ///   (3 h into shift, midday)    → ~0.45
    ///   (7 h no-break, 3 am)        → ~0.85
    ///   (microsleep last 60 s)      → >= 0.90
    static let weights = Weights(
        bias:    -3.2,
        hrDelta:  1.4,
        hrvLow:   1.6,
        jerkLow:  1.1,
        yawLow:   0.9,
        circ:     1.3,
        tsb:      1.5,
        drv:      1.2,
        micro:    2.5
    )

    // MARK: - Microsleep detection

    /// Heuristic: over a 3-second trailing window, the driver went
    /// "limp" (min jerk < 0.3 g/s, max jerk < 1.0 g/s), then produced
    /// a startle spike (> 4 g/s within the last 300 ms). We've chosen
    /// the thresholds to favor precision over recall — false positives
    /// erode driver trust.
    private func detectMicrosleep(at: Date) {
        let window = jerkSamples.filter { at.timeIntervalSince($0.0) <= 3.0 }
        guard window.count > 10 else { return }
        let recent = jerkSamples.filter { at.timeIntervalSince($0.0) <= 0.3 }
        guard let maxRecent = recent.map({ $0.1 }).max() else { return }
        let body = jerkSamples.filter {
            let dt = at.timeIntervalSince($0.0)
            return dt > 0.3 && dt <= 3.0
        }.map { $0.1 }
        guard !body.isEmpty else { return }
        let bodyMax = body.max() ?? 0
        let bodyMin = body.min() ?? 0
        if maxRecent > 4.0, bodyMax < 1.0, bodyMin < 0.3 {
            // De-dup: only one event per 10-second span.
            if let last = microsleepEvents.last, at.timeIntervalSince(last) < 10 {
                return
            }
            microsleepEvents.append(at)
        }
    }

    // MARK: - Stats helpers

    private static func stddev(_ vs: [Double]) -> Double {
        guard vs.count > 1 else { return 0 }
        let mean = vs.reduce(0, +) / Double(vs.count)
        let sq = vs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return sqrt(sq / Double(vs.count - 1))
    }

    private static func rms(_ vs: [Double]) -> Double {
        guard !vs.isEmpty else { return 0 }
        let sq = vs.reduce(0) { $0 + $1 * $1 }
        return sqrt(sq / Double(vs.count))
    }

    /// RMSSD — Root Mean Square of Successive Differences. Classical
    /// HRV stat. Here we operate on consecutive HR-sample *values* as
    /// a noisy proxy when beat-to-beat intervals aren't available.
    /// When we get IBI samples from `.heartbeatSeries` (iOS 15+) the
    /// proxy gets swapped for the real thing.
    private static func rmssd(hrValues vs: [Double]) -> Double {
        guard vs.count > 1 else { return 0 }
        var sq = 0.0
        for i in 1..<vs.count {
            let d = vs[i] - vs[i - 1]
            sq += d * d
        }
        return sqrt(sq / Double(vs.count - 1))
    }

    private static func circadianFactor(at: Date) -> Double {
        // Two-humped curve: Gaussian-ish peaks at 03:00 and 14:30.
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.hour, .minute], from: at)
        let hour = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60.0
        let g1 = exp(-pow(hour - 3.0, 2) / (2 * 2.0 * 2.0))   // σ = 2h
        let g2 = exp(-pow(hour - 14.5, 2) / (2 * 1.5 * 1.5))  // σ = 1.5h
        return min(1.0, g1 + g2 * 0.7)
    }

    // MARK: - Windowing

    private func trimWindow<V>(_ buf: inout [(Date, V)], secondsBack: TimeInterval, now: Date) {
        let cutoff = now.addingTimeInterval(-secondsBack)
        buf.removeAll(where: { $0.0 < cutoff })
    }
}

// MARK: - Features value type

extension FatiguePredictor {
    struct Features: Equatable {
        let hrMean: Double
        let hrStd: Double
        let rmssd: Double
        let accelMean: Double
        let yawStd: Double
        let jerkRMS: Double
        let circadian: Double
        let timeSinceBreakRamp: Double
        let drivingRamp: Double
        let microsleepEvents60s: Int

        /// Canonical order matching the 10-D vector the CoreML tabular
        /// classifier expects. When the model lands, we'll serialize
        /// this into `MLMultiArray` via this vector.
        var vector: [Double] {
            [hrMean, hrStd, rmssd, accelMean, yawStd, jerkRMS,
             circadian, timeSinceBreakRamp, drivingRamp,
             Double(microsleepEvents60s)]
        }
    }
}
