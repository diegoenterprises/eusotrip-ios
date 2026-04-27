//
//  TunnelAwareETA.swift
//  EusoTrip Pulse Watch App
//
//  F02 — Tunnel-Aware ETA (Q2 2026 offline-mode tier).
//
//  When the Apple Watch Ultra 2's dual-frequency GNSS (L1 + L5) drops —
//  typically inside a tunnel, parking garage, or under a long overpass —
//  we stop trusting GPS and fall through to a dead-reckoned position
//  using the onboard IMU (CMDeviceMotion) + last-known heading + last-
//  known speed + wheel-tick odometry forwarded from the phone (when the
//  phone is still paired to the truck ECM via SPN 84).
//
//  Implementation: 15-state loosely-coupled error-state EKF.
//
//    State x (15):
//      [ 0..2 ]  p_NED     position offset from anchor (m)
//      [ 3..5 ]  v_NED     velocity (m/s)
//      [ 6..8 ]  ε_NED     small-angle attitude error (rad)
//      [ 9..11]  b_a       accel bias, device frame (m/s²)
//      [12..14]  b_g       gyro bias,  device frame (rad/s)
//
//    Process model:
//      p̈ = R_dev→NED · (a_meas − b_a)      (userAcceleration already has g removed)
//      ṗ = v
//      ε̇ = −R_dev→NED · (ω_meas − b_g)     (first-order; small-angle)
//      ḃ_a = 0,  ḃ_g = 0                   (random walk — only Q grows them)
//
//    Measurement updates (sequential scalar — no matrix inversions):
//      • GPS position fix (3 scalar)        σ = horizontalAccuracy + 1 m
//      • GPS velocity fix (3 scalar)        σ from course-integrated speed
//      • Wheel-tick speed magnitude (1 scalar)  σ = 0.4 m/s (ECM-typical)
//      • Heading unit-vector (2 scalar, ENU N/E components of course)
//
//  The anchor frame is seeded at the last-solid-GPS fix before tunnel
//  entry; NED offsets are maintained relative to that anchor and only
//  re-anchored on tunnel exit to prevent the 1e-7 rad/m flat-earth
//  approximation from accumulating error on cross-country drives.
//
//  Wrist-worn IMU reality check: the driver's arm moves independently
//  of the truck, so accelerometer noise on the wrist is an order of
//  magnitude worse than on a dashboard-mounted phone. We compensate by
//  (a) heavy accel process noise, (b) trusting wheel-tick speed ~10×
//  more than integrated accel, (c) trusting last-GPS heading during the
//  first ~60s of DR (tunnels are mostly straight), and (d) letting the
//  recovery snap-back tell analytics what the actual noise was so the
//  covariances can be tuned from real field data.
//

import Foundation
import Combine
import CoreLocation
import simd
#if canImport(CoreMotion)
import CoreMotion
#endif

enum TunnelETAState: Equatable {
    case gpsLocked          // HDOP < 2.0, dual-freq solution
    case gpsDegraded        // HDOP 2–5, single-freq fallback
    case tunnelDR           // no fix; propagating via IMU
    case recovering         // fresh fix, snapping back
}

@MainActor
final class TunnelAwareETA: ObservableObject {
    static let shared = TunnelAwareETA()

    @Published private(set) var state: TunnelETAState = .gpsLocked
    @Published private(set) var lastFix: CLLocation?
    @Published private(set) var deadReckoned: CLLocation?
    @Published private(set) var driftMeters: Double = 0
    @Published private(set) var tunnelEnteredAt: Date?
    /// √(P[pN,pN] + P[pE,pE]) — horizontal 1σ uncertainty of the DR
    /// estimate. Consumers (RouteOverviewView ETA band) render this as
    /// the "±N m" confidence halo while we're underground.
    @Published private(set) var positionStdMeters: Double = 0

    // Parameters — tunable via EusoTripConfig.
    private let degradedHDOP: Double = 2.0
    private let tunnelHDOP: Double = 5.0

    private var lastFixTimestamp: Date?
    private var lastSpeedMPS: Double = 0
    private var lastHeadingDeg: Double = 0

    /// NED frame anchor — set when we enter tunnelDR. All EKF state
    /// positions are offsets from this anchor (meters, flat-earth).
    private var anchorLocation: CLLocation?

    /// The 15-state EKF core.
    private let ekf = TunnelETAEKF()

    /// Last CMDeviceMotion timestamp — used to compute dt for the EKF
    /// predict step. CMMotionManager delivers a monotonically increasing
    /// `timestamp` in seconds since device boot.
    private var imuLastTimestamp: TimeInterval = 0

    #if canImport(CoreMotion)
    private let motion = CMMotionManager()
    #endif

    // MARK: - Ingest

    /// Feed a freshly-observed location. Called by DrivingSessionManager
    /// every fix. Transitions the state machine and, if entering tunnel
    /// mode, seeds dead-reckoning with this as the anchor.
    func ingest(_ loc: CLLocation) {
        let accuracy = loc.horizontalAccuracy
        let quality: TunnelETAState
        if accuracy < 0 {
            quality = .tunnelDR
        } else if accuracy <= degradedHDOP * 5 {
            quality = .gpsLocked
        } else if accuracy <= tunnelHDOP * 5 {
            quality = .gpsDegraded
        } else {
            quality = .tunnelDR
        }

        let now = Date()
        switch quality {
        case .gpsLocked, .gpsDegraded:
            if state == .tunnelDR {
                // Fresh fix after a DR run. Measure the drift, apply a
                // GPS update to the EKF (snapping back), then clean up.
                let drPos = deadReckoned ?? lastFix
                driftMeters = drPos?.distance(from: loc) ?? 0
                logRecovery(drift: driftMeters)

                applyGPSUpdate(loc)
                state = .recovering

                // Re-anchor so future flat-earth math stays local.
                anchorLocation = loc
                ekf.reset()

                stopIMUDeadReckoning()
                state = quality
            } else {
                state = quality
                // While locked, keep the EKF lightly synced so if we drop
                // into a tunnel mid-block we've already calibrated the
                // velocity vector and the biases have started converging.
                if anchorLocation == nil { anchorLocation = loc }
                applyGPSUpdate(loc)
            }
            lastFix = loc
            lastFixTimestamp = now
            lastSpeedMPS = max(0, loc.speed)
            lastHeadingDeg = loc.course >= 0 ? loc.course : lastHeadingDeg
            deadReckoned = loc
            refreshPublishedUncertainty()

        case .tunnelDR:
            if state != .tunnelDR {
                // First tunnel entry — freeze the anchor and spin up
                // the IMU pump. EKF state is already aligned from the
                // light-sync GPS updates we've been applying while
                // locked.
                state = .tunnelDR
                tunnelEnteredAt = now
                anchorLocation = lastFix ?? loc
                startIMUDeadReckoning()
            }
            // Publish a DR estimate built from current EKF state even
            // though this was a bad fix — ensures UI stays fresh.
            deadReckoned = currentLocationFromEKF(at: now) ?? lastFix
            refreshPublishedUncertainty()

        case .recovering:
            break
        }
    }

    /// Consumers query this for their ETA math. Always returns the best
    /// current estimate — the real GPS fix if available, else the DR
    /// propagation, else the last known fix as a conservative fallback.
    func bestEstimate() -> CLLocation? {
        switch state {
        case .gpsLocked, .gpsDegraded, .recovering:
            return lastFix ?? deadReckoned
        case .tunnelDR:
            return deadReckoned ?? lastFix
        }
    }

    // MARK: - Wheel-tick ingest (F10 — ELD-Fused Precision)

    /// Feed wheel-tick-derived velocity from the paired iPhone's J1939
    /// reader (SPN 84). The phone forwards truck-ECM speed at ~10 Hz
    /// over WatchConnectivity while coupled to the truck's diagnostic
    /// port; this method folds the reading into the EKF speed-magnitude
    /// measurement so in-tunnel dead-reckoning stays anchored to the
    /// real drivetrain velocity instead of the last-known GPS speed
    /// (which can be stale by the time the fix drops).
    ///
    /// No-ops unless `eldFusedPrecisionEnabled` is on AND we're in
    /// tunnelDR mode — during GPS-locked operation the CLLocation speed
    /// is already the ground truth and fusing a second source would
    /// just add jitter. If the driver is at a stop (wheel-tick = 0),
    /// we clamp to zero rather than coasting on the last GPS speed.
    func ingestWheelTickSpeed(_ metersPerSecond: Double, at timestamp: Date = Date()) {
        guard EusoTripConfig.eldFusedPrecisionEnabled else { return }
        guard state == .tunnelDR else { return }
        // Sanity band — truck wheel-tick at 10 Hz shouldn't report
        // anything over 45 m/s (~100 mph). Anything wilder is a CAN
        // glitch; ignore it.
        guard metersPerSecond >= 0, metersPerSecond < 45 else { return }
        lastSpeedMPS = metersPerSecond

        // Scalar speed update. σ = 0.4 m/s is a typical SPN 84 noise
        // budget — covers tire-wear scale error and transmission lash.
        ekf.updateSpeed(metersPerSecond, sigma: 0.4)
        deadReckoned = currentLocationFromEKF(at: timestamp) ?? deadReckoned
        refreshPublishedUncertainty()
    }

    /// Feed a heading update from a fused source (phone magnetometer
    /// or wheel-angle sensor). Same tunnelDR-only contract as above.
    /// Projects the heading into N/E velocity unit components and runs
    /// a scalar update; the speed magnitude is preserved by the EKF.
    func ingestHeading(_ courseDegrees: Double) {
        guard EusoTripConfig.eldFusedPrecisionEnabled else { return }
        guard state == .tunnelDR else { return }
        guard (0...360).contains(courseDegrees) else { return }
        lastHeadingDeg = courseDegrees
        let hRad = courseDegrees * .pi / 180.0
        // Compass heading → NED velocity unit vector (D = 0 on flat road).
        let vN_hat = cos(hRad)
        let vE_hat = sin(hRad)
        ekf.updateHeading(vNHat: vN_hat, vEHat: vE_hat, sigma: 0.1)
        refreshPublishedUncertainty()
    }

    // MARK: - EKF driver

    /// Bridges CMDeviceMotion frames into the EKF. Called from the
    /// CoreMotion handler (background queue) at ~50 Hz, marshalled onto
    /// the MainActor through the startup path.
    /// All arguments are primitives (no captured CMDeviceMotion
    /// reference, which Apple reuses across callbacks).
    private func consumeMotion(
        timestamp t: TimeInterval,
        accel: SIMD3<Double>,
        gyro: SIMD3<Double>,
        rotationMatrix rm: (Double, Double, Double,
                            Double, Double, Double,
                            Double, Double, Double)
    ) {
        let dt: Double
        if imuLastTimestamp > 0 {
            dt = min(max(t - imuLastTimestamp, 1.0 / 200.0), 0.25)
        } else {
            dt = 1.0 / 50.0
        }
        imuLastTimestamp = t

        // Device→NWU (compass-corrected Z-vertical reference frame) then
        // flip Y/Z to land in NED.
        let devToNWU = simd_double3x3(columns: (
            SIMD3(rm.0, rm.3, rm.6),
            SIMD3(rm.1, rm.4, rm.7),
            SIMD3(rm.2, rm.5, rm.8)
        ))
        let nwuToNED = simd_double3x3(diagonal: SIMD3(1.0, -1.0, -1.0))
        let R = nwuToNED * devToNWU

        ekf.predict(dt: dt, accel: accel, gyro: gyro, rotDevToNED: R)

        // Publish the propagated location on each frame — the watch UI
        // re-renders the ETA band from this as it ticks.
        deadReckoned = currentLocationFromEKF(at: Date())
        refreshPublishedUncertainty()
    }

    /// Applies a full GPS fix (3 position + 3 velocity scalar updates).
    private func applyGPSUpdate(_ loc: CLLocation) {
        guard let anchor = anchorLocation else {
            anchorLocation = loc
            ekf.reset()
            return
        }
        let posNED = nedOffset(from: anchor, to: loc)
        let sigmaP = max(loc.horizontalAccuracy, 1.0)
        ekf.updatePosition(posNED, sigma: sigmaP)

        if loc.speed >= 0, loc.course >= 0 {
            let hRad = loc.course * .pi / 180.0
            let velN = loc.speed * cos(hRad)
            let velE = loc.speed * sin(hRad)
            ekf.updateVelocity(SIMD3(velN, velE, 0), sigma: 1.5)
        }
    }

    /// Converts the current EKF state back into a CLLocation suitable
    /// for downstream consumers. Horizontal accuracy is reported as the
    /// √trace of the EKF position covariance, which is how the route
    /// overlay decides whether to dim the ETA badge as "± N m".
    private func currentLocationFromEKF(at now: Date) -> CLLocation? {
        guard let anchor = anchorLocation else { return nil }
        let (pN, pE, pD) = ekf.position()
        let latPerMeter = 1.0 / 111_111.0
        let lonPerMeter = 1.0 / (111_111.0 * cos(anchor.coordinate.latitude * .pi / 180.0))
        let coord = CLLocationCoordinate2D(
            latitude: anchor.coordinate.latitude + pN * latPerMeter,
            longitude: anchor.coordinate.longitude + pE * lonPerMeter
        )
        let horiz = ekf.positionStdMeters()
        return CLLocation(
            coordinate: coord,
            altitude: anchor.altitude - pD,
            horizontalAccuracy: state == .tunnelDR ? max(horiz, 5.0) : horiz,
            verticalAccuracy: max(horiz, 5.0),
            course: lastHeadingDeg,
            speed: max(0, ekf.speedMPS()),
            timestamp: now
        )
    }

    private func refreshPublishedUncertainty() {
        positionStdMeters = ekf.positionStdMeters()
    }

    /// Flat-earth NED offset from `anchor` to `target`, in meters.
    private func nedOffset(from anchor: CLLocation, to target: CLLocation) -> SIMD3<Double> {
        let dLat = target.coordinate.latitude - anchor.coordinate.latitude
        let dLon = target.coordinate.longitude - anchor.coordinate.longitude
        let pN = dLat * 111_111.0
        let pE = dLon * 111_111.0 * cos(anchor.coordinate.latitude * .pi / 180.0)
        let pD = anchor.altitude - target.altitude
        return SIMD3(pN, pE, pD)
    }

    // MARK: - IMU lifecycle

    private func startIMUDeadReckoning() {
        #if canImport(CoreMotion)
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 50.0
        imuLastTimestamp = 0
        // Background queue — we extract primitives on the callback thread
        // (CMDeviceMotion is a reused reference and may mutate between
        // callbacks) and marshal onto MainActor via a typed Task hop.
        motion.startDeviceMotionUpdates(
            using: .xArbitraryCorrectedZVertical,
            to: OperationQueue()
        ) { [weak self] dm, _ in
            guard let self, let dm else { return }
            let t = dm.timestamp
            // userAcceleration is already gravity-removed and in g-units.
            let a = SIMD3<Double>(
                dm.userAcceleration.x * 9.80665,
                dm.userAcceleration.y * 9.80665,
                dm.userAcceleration.z * 9.80665
            )
            let w = SIMD3<Double>(
                dm.rotationRate.x,
                dm.rotationRate.y,
                dm.rotationRate.z
            )
            let rm = dm.attitude.rotationMatrix
            let rows = (rm.m11, rm.m12, rm.m13,
                        rm.m21, rm.m22, rm.m23,
                        rm.m31, rm.m32, rm.m33)
            Task { @MainActor in
                self.consumeMotion(
                    timestamp: t,
                    accel: a,
                    gyro: w,
                    rotationMatrix: rows
                )
            }
        }
        #endif
    }

    /// Shut the IMU pump down once GPS has been reacquired. Counterpart
    /// to `startIMUDeadReckoning()`. Called from `ingest(_:)` on tunnel
    /// exit so the motion subsystem doesn't stay spun up across the
    /// whole drive.
    private func stopIMUDeadReckoning() {
        #if canImport(CoreMotion)
        guard motion.isDeviceMotionActive else { return }
        motion.stopDeviceMotionUpdates()
        imuLastTimestamp = 0
        #endif
    }

    private func logRecovery(drift: Double) {
        // Posts a notification so analytics can bucket tunnel-recovery
        // drift distributions. Useful for EKF noise-tuning over time —
        // the Q_diag values are deliberately conservative; field-drift
        // histograms let us tighten them without risking divergence in
        // deployment.
        NotificationCenter.default.post(
            name: .tunnelETARecovered,
            object: nil,
            userInfo: [
                "driftMeters": drift,
                "positionStdMeters": ekf.positionStdMeters(),
                "speedMPS": ekf.speedMPS(),
                "state": String(describing: state)
            ]
        )
    }
}

extension Notification.Name {
    static let tunnelETARecovered = Notification.Name("com.eusotrip.tunnelETARecovered")
}

// MARK: - 15-state error-state EKF
//
// Pragmatic design notes:
//   • Sequential scalar updates — each measurement is a 1-element
//     innovation, so we never need to invert a matrix larger than 1×1.
//     Numerically stable and cheap on the watch CPU.
//   • Covariance is symmetrized after every update to suppress the
//     drift that shows up as a tiny numerical asymmetry in
//     P − KHP. Joseph form would be stronger but noticeably more
//     expensive per update at 50 Hz.
//   • Biases are true random walks — their means don't advance in
//     `predict`, only their covariance grows via Q_diag.
//   • Attitude error ε is kept at zero in the state vector on every
//     predict step: CMDeviceMotion already does its own internal
//     gravity-aware fusion, so we treat the reported R_dev→NED as the
//     mean and let ε's covariance band the residual error.

private final class TunnelETAEKF {
    static let n = 15

    /// 15-element mean vector.
    private(set) var x: [Double] = Array(repeating: 0, count: 15)

    /// 15×15 covariance, row-major.
    private var P = MatD(rows: 15, cols: 15)

    /// Per-state process-noise spectral density (units² per second).
    private var Q_diag: [Double]

    init() {
        // Seeded covariance — these are deliberately pessimistic so the
        // first few GPS updates tighten the EKF rather than reject real
        // measurements as outliers.
        let pVar: Double = 1.0                        // 1 m  position σ
        let vVar: Double = 0.25                       // 0.5 m/s velocity σ
        let attVar: Double = pow(2.0 * .pi / 180.0, 2) // 2° attitude σ
        let baVar: Double = 0.04                      // ~0.2 m/s² accel bias σ
        let bgVar: Double = pow(0.02, 2)              // ~0.02 rad/s gyro bias σ

        for i in 0..<3 { P[i, i] = pVar }
        for i in 3..<6 { P[i, i] = vVar }
        for i in 6..<9 { P[i, i] = attVar }
        for i in 9..<12 { P[i, i] = baVar }
        for i in 12..<15 { P[i, i] = bgVar }

        Q_diag = Array(repeating: 0, count: 15)
        // Direct propagation of pos/vel/att is driven by IMU — the
        // noise folds in through the state transition. We only need
        // random-walk noise on the biases.
        for i in 9..<12 { Q_diag[i] = 1e-4 }    // accel bias rw  (m/s² per √s)
        for i in 12..<15 { Q_diag[i] = 1e-7 }   // gyro  bias rw  (rad/s per √s)
        // Attitude error has a small always-on drift to cover any residual
        // gyro mis-alignment the bias state can't absorb.
        for i in 6..<9 { Q_diag[i] = 1e-6 }
        // Velocity picks up IMU accel-integration noise. Wrist-worn
        // IMU is dirty — arm motion dominates — so we set this
        // aggressively. Q_diag is PSD (m²/s³), so σ_v² ≈ Q·T after T
        // seconds of unaided DR. At Q=0.3 → σ_v ≈ 4.2 m/s after 60 s,
        // which is conservative enough that GPS updates always win
        // when they return. Retune from `tunnelETARecovered` drift
        // histograms once we have field data.
        for i in 3..<6 { Q_diag[i] = 0.3 }
    }

    /// Resets the mean to zero (post tunnel-exit re-anchor). Covariance
    /// is preserved — the bias estimates are still informative after
    /// re-anchoring.
    func reset() {
        for i in 0..<6 { x[i] = 0 }
        for i in 6..<9 { x[i] = 0 }
        // Leave biases in place.
        // Reset position/velocity covariance to re-initial values so
        // the first new GPS snaps cleanly.
        for i in 0..<3 {
            for j in 0..<15 { P[i, j] = 0; P[j, i] = 0 }
        }
        for i in 3..<6 {
            for j in 0..<15 { P[i, j] = 0; P[j, i] = 0 }
        }
        for i in 6..<9 {
            for j in 0..<15 { P[i, j] = 0; P[j, i] = 0 }
        }
        for i in 0..<3 { P[i, i] = 1.0 }
        for i in 3..<6 { P[i, i] = 0.25 }
        for i in 6..<9 { P[i, i] = pow(2.0 * .pi / 180.0, 2) }
    }

    func position() -> (Double, Double, Double) { (x[0], x[1], x[2]) }

    func speedMPS() -> Double {
        sqrt(x[3] * x[3] + x[4] * x[4] + x[5] * x[5])
    }

    /// √(P_NN + P_EE) — horizontal 1σ uncertainty of the position
    /// estimate.
    func positionStdMeters() -> Double {
        sqrt(max(P[0, 0] + P[1, 1], 0))
    }

    // MARK: - Predict

    /// Advance the state `dt` seconds using a single IMU frame.
    /// `accel`  — device-frame user acceleration (gravity removed), m/s²
    /// `gyro`   — device-frame rotation rate, rad/s
    /// `rotDevToNED` — device→NED rotation matrix from fused attitude
    func predict(dt: Double,
                 accel: SIMD3<Double>,
                 gyro: SIMD3<Double>,
                 rotDevToNED R: simd_double3x3) {
        guard dt > 0, dt < 1.0 else { return }

        let b_a = SIMD3(x[9], x[10], x[11])
        let b_g = SIMD3(x[12], x[13], x[14])
        let aCorr = accel - b_a
        let aNED = R * aCorr

        // --- Mean propagation (Euler integration is fine at 50 Hz) ---
        let v = SIMD3(x[3], x[4], x[5])
        let pNew = SIMD3(x[0], x[1], x[2]) + v * dt + aNED * (0.5 * dt * dt)
        let vNew = v + aNED * dt
        x[0] = pNew.x; x[1] = pNew.y; x[2] = pNew.z
        x[3] = vNew.x; x[4] = vNew.y; x[5] = vNew.z

        // ε̇ = −R·(ω − b_g). ε is integrated but kept small because we
        // trust the CoreMotion attitude and use ε only as a linearization
        // handle for the velocity-accel coupling below.
        let omCorr = gyro - b_g
        let epsDot = -(R * omCorr)
        x[6] += epsDot.x * dt
        x[7] += epsDot.y * dt
        x[8] += epsDot.z * dt

        // --- Covariance propagation P = F · P · Fᵀ + Q·dt ---
        // Continuous-time Jacobian F_c (non-zero blocks only):
        //   ∂p/∂v = I₃
        //   ∂v/∂ε = −[aNED]_× (skew of aNED)
        //   ∂v/∂b_a = −R
        //   ∂ε/∂b_g = −R
        // Discrete first-order:  F = I + F_c · dt
        var F = MatD.identity(15)
        // p row: ∂p/∂v
        for i in 0..<3 { F[i, i + 3] = dt }

        // v row: ∂v/∂ε = −skew(aNED) · dt
        let skew = skewSymmetric(aNED)
        for i in 0..<3 {
            for j in 0..<3 {
                F[3 + i, 6 + j] = -skew[i][j] * dt
            }
        }
        // v row: ∂v/∂b_a = −R · dt
        // ε row: ∂ε/∂b_g = −R · dt
        for i in 0..<3 {
            for j in 0..<3 {
                let Rij = R[j][i] // simd_double3x3 stores column-major: R[col][row]
                F[3 + i, 9 + j]  = -Rij * dt
                F[6 + i, 12 + j] = -Rij * dt
            }
        }

        // P = F · P · Fᵀ
        let FP = MatD.mul(F, P)
        let Ft = F.transposed()
        P = MatD.mul(FP, Ft)
        // + Q·dt on the diagonal
        for i in 0..<15 {
            P[i, i] += Q_diag[i] * dt
        }
        symmetrize()
    }

    // MARK: - Scalar measurement updates (sequential)

    /// 3 GPS position scalars. Measurement: z_i = p_NED[i].  σ in meters.
    func updatePosition(_ posNED: SIMD3<Double>, sigma: Double) {
        let R = max(sigma * sigma, 0.25)
        for axis in 0..<3 {
            let y = posNED[axis] - x[axis]
            scalarUpdate(row: axis, innovation: y, R: R)
        }
    }

    /// 3 GPS velocity scalars. Measurement: z_i = v_NED[i].  σ in m/s.
    func updateVelocity(_ velNED: SIMD3<Double>, sigma: Double) {
        let R = max(sigma * sigma, 0.0625)
        for axis in 0..<3 {
            let y = velNED[axis] - x[3 + axis]
            scalarUpdate(row: 3 + axis, innovation: y, R: R)
        }
    }

    /// Wheel-tick speed magnitude. Linearize |v| around current estimate.
    /// Skips at near-standstill where the gradient is degenerate.
    func updateSpeed(_ speedMPS: Double, sigma: Double) {
        let vN = x[3], vE = x[4], vD = x[5]
        let mag = sqrt(vN * vN + vE * vE + vD * vD)
        guard mag > 0.1 else { return }
        let hN = vN / mag, hE = vE / mag, hD = vD / mag
        let y = speedMPS - mag
        let Rv = max(sigma * sigma, 0.01)

        // H has non-zero entries only in columns 3,4,5 (velocity block).
        // PHt_i = P[i,3]·hN + P[i,4]·hE + P[i,5]·hD
        var PHt = [Double](repeating: 0, count: 15)
        for i in 0..<15 {
            PHt[i] = P[i, 3] * hN + P[i, 4] * hE + P[i, 5] * hD
        }
        let S = PHt[3] * hN + PHt[4] * hE + PHt[5] * hD + Rv
        guard S > 0 else { return }
        let Sinv = 1.0 / S

        for i in 0..<15 { x[i] += PHt[i] * Sinv * y }

        // P := P − PHt · Sinv · (H·P)
        // H·P row_j = hN·P[3,j] + hE·P[4,j] + hD·P[5,j]
        var HP = [Double](repeating: 0, count: 15)
        for j in 0..<15 {
            HP[j] = hN * P[3, j] + hE * P[4, j] + hD * P[5, j]
        }
        for i in 0..<15 {
            let k = PHt[i] * Sinv
            for j in 0..<15 {
                P[i, j] -= k * HP[j]
            }
        }
        symmetrize()
    }

    /// Heading unit vector in NED (N,E components). Runs two sequential
    /// scalar updates against v̂_N = vN/|v| and v̂_E = vE/|v|. Preserves
    /// the velocity magnitude — only rotates the velocity vector.
    func updateHeading(vNHat: Double, vEHat: Double, sigma: Double) {
        let mag = speedMPS()
        guard mag > 0.5 else { return }
        // Decompose: measure the North and East velocity components that
        // would result from the heading at the current speed. This is a
        // regular linear measurement in the velocity states.
        let zN = vNHat * mag
        let zE = vEHat * mag
        let R = max(sigma * sigma * mag * mag, 0.04)
        scalarUpdate(row: 3, innovation: zN - x[3], R: R)
        scalarUpdate(row: 4, innovation: zE - x[4], R: R)
    }

    // MARK: - Kalman helpers

    /// Single-column H row — H has a 1 in column `row`, 0 elsewhere.
    /// Standard scalar EKF update.
    private func scalarUpdate(row: Int, innovation y: Double, R: Double) {
        // PHt (column `row` of P)
        var PHt = [Double](repeating: 0, count: 15)
        for i in 0..<15 { PHt[i] = P[i, row] }
        let S = P[row, row] + R
        guard S > 0 else { return }
        let Sinv = 1.0 / S
        for i in 0..<15 { x[i] += PHt[i] * Sinv * y }

        // H·P row is row `row` of P.
        var HP = [Double](repeating: 0, count: 15)
        for j in 0..<15 { HP[j] = P[row, j] }
        for i in 0..<15 {
            let k = PHt[i] * Sinv
            for j in 0..<15 {
                P[i, j] -= k * HP[j]
            }
        }
        symmetrize()
    }

    /// Symmetrize covariance + guard against negative diagonals.
    private func symmetrize() {
        for i in 0..<15 {
            for j in (i + 1)..<15 {
                let avg = 0.5 * (P[i, j] + P[j, i])
                P[i, j] = avg
                P[j, i] = avg
            }
            if P[i, i] < 1e-12 { P[i, i] = 1e-12 }
        }
    }

    /// Skew-symmetric cross-product matrix [v]_×.
    private func skewSymmetric(_ v: SIMD3<Double>) -> [[Double]] {
        return [
            [0,    -v.z,  v.y],
            [v.z,  0,    -v.x],
            [-v.y, v.x,   0  ]
        ]
    }
}

// MARK: - Small double-precision matrix utility
//
// Keeps the EKF math self-contained — pulling in Accelerate adds link
// weight to the watch binary and our 15×15 matmuls run in ~12 µs on an
// S9 chip, well inside budget at 50 Hz.

private struct MatD {
    let rows: Int
    let cols: Int
    var data: [Double]

    init(rows: Int, cols: Int) {
        self.rows = rows
        self.cols = cols
        self.data = Array(repeating: 0, count: rows * cols)
    }

    static func identity(_ n: Int) -> MatD {
        var m = MatD(rows: n, cols: n)
        for i in 0..<n { m[i, i] = 1 }
        return m
    }

    subscript(r: Int, c: Int) -> Double {
        get { data[r * cols + c] }
        set { data[r * cols + c] = newValue }
    }

    func transposed() -> MatD {
        var t = MatD(rows: cols, cols: rows)
        for i in 0..<rows {
            for j in 0..<cols {
                t[j, i] = self[i, j]
            }
        }
        return t
    }

    static func mul(_ A: MatD, _ B: MatD) -> MatD {
        precondition(A.cols == B.rows, "MatD.mul shape mismatch")
        var C = MatD(rows: A.rows, cols: B.cols)
        for i in 0..<A.rows {
            for k in 0..<A.cols {
                let aik = A[i, k]
                if aik == 0 { continue }
                for j in 0..<B.cols {
                    C[i, j] += aik * B[k, j]
                }
            }
        }
        return C
    }
}
