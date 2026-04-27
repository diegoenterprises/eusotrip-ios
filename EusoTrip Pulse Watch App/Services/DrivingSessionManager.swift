//
//  DrivingSessionManager.swift
//  EusoTrip Watch App
//
//  Runs a lightweight HKWorkoutSession in the background so watchOS
//  keeps the app alive across long hauls. Without a workout session
//  the OS will suspend us after ~30 seconds — unacceptable for an HOS
//  compliance surface that needs to capture the next "driving → on
//  duty not driving" transition at a red light.
//
//  Spec §8.3 — CoreMotion integration is layered on top so we can
//  detect seatbelt / pothole / rollover events and bubble them up to
//  the backend for incident-protocol scoring.
//

import Foundation
import Combine
@preconcurrency import HealthKit
import CoreMotion
import CoreLocation
import SwiftUI
import WatchKit

@MainActor
final class DrivingSessionManager: NSObject, ObservableObject {
    static let shared = DrivingSessionManager()

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var startedAt: Date?
    @Published private(set) var currentSpeedMps: Double = 0
    @Published private(set) var lastMotionEvent: MotionEvent?

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private let motion = CMMotionManager()
    private let pedometer = CMPedometer()
    private let activity = CMMotionActivityManager()
    // F02 — live location pump that feeds TunnelAwareETA.ingest() so
    // the dead-reckoning state machine actually gets GPS samples to
    // classify. Without this, `tunnelAwareETAEnabled` was a no-op.
    private let locationManager = CLLocationManager()

    struct MotionEvent: Equatable {
        let kind: Kind
        let at: Date
        enum Kind: String { case hardBrake, pothole, sharpLeft, sharpRight, possibleRollover }
    }

    override init() {
        super.init()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5 // meters; tunnels don't care about micro-movements
    }

    func begin() {
        guard HKHealthStore.isHealthDataAvailable(), !isRunning else { return }

        // Request auth on background queue; build the non-Sendable
        // HKWorkoutConfiguration back on the MainActor so we don't
        // capture it across the @Sendable authorization callback.
        let types: Set<HKSampleType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]
        healthStore.requestAuthorization(toShare: nil, read: types) { _, _ in
            Task { @MainActor [weak self] in
                self?.buildAndStartSession()
            }
        }
    }

    private func buildAndStartSession() {
        // Workout type = .other — we don't care about calorie reporting,
        // we just want the OS to give us background execution.
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .outdoor
        startSession(config: config)
    }

    private func startSession(config: HKWorkoutConfiguration) {
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)

            workoutSession = session
            workoutBuilder = builder

            session.startActivity(with: Date())
            builder.beginCollection(withStart: Date()) { _, _ in }

            isRunning = true
            startedAt = Date()
            startMotion()
            startLocationPump()
            // F02b — begin the dead-zone coast propagator. Safe no-op
            // when `deadZoneCoastEnabled` is false.
            DeadZoneCoast.shared.start()
            // Q3 — drive the fatigue predictor's 1-Hz scoring tick.
            startFatigueTicker()
        } catch {
            // swallow — without a workout session we fall back to reduced
            // background and the app may suspend; not fatal.
        }
    }

    // MARK: - Voice route yield
    //
    // L4 — HKWorkoutSession holds the AVAudioSession route once it
    // starts. When EsangSession.startListening tries to activate
    // .playAndRecord on top, watchOS 26.4 silently drops the activation
    // on the floor and installTap lands on a 0-channel input format
    // (an ObjC exception, not a Swift throw). pauseForVoice() pauses
    // the workout session for the duration of a capture so the mic
    // route is ours alone; resumeAfterVoice() reactivates. Both are
    // idempotent — calling pause twice is safe.

    private var pausedForVoice: Bool = false

    /// Pauses the workout session so the AVAudioSession route can be
    /// reassigned to Esang. Safe to call when no session is running.
    func pauseForVoice() {
        guard let session = workoutSession, !pausedForVoice else { return }
        session.pause()
        pausedForVoice = true
        OrbLog.info("driving.pauseForVoice")
    }

    /// Resumes the workout session after a voice capture ends. Safe
    /// to call when pause was never issued.
    func resumeAfterVoice() {
        guard let session = workoutSession, pausedForVoice else { return }
        session.resume()
        pausedForVoice = false
        OrbLog.info("driving.resumeAfterVoice")
    }

    /// Best-effort alias matched to the preflight call site. Prefers
    /// pauseForVoice() because yielding the route without pausing the
    /// workout session leaves the wrist fighting for the same input.
    func yieldAudioRoute() { pauseForVoice() }

    func end() async {
        guard let session = workoutSession else { return }
        session.stopActivity(with: Date())
        session.end()
        _ = try? await workoutBuilder?.endCollection(at: Date())
        _ = try? await workoutBuilder?.finishWorkout()
        workoutSession = nil
        workoutBuilder = nil
        isRunning = false
        startedAt = nil
        stopMotion()
        stopLocationPump()
        DeadZoneCoast.shared.stop()
    }

    // MARK: - Location (feeds TunnelAwareETA)

    /// Kick off a low-frequency CoreLocation pump when the driving
    /// workout session begins, so F02 (Tunnel-Aware ETA) has real GPS
    /// fixes to classify. watchOS grants live updates to foreground apps
    /// and to HKWorkoutSession-backed background apps — which is exactly
    /// the window we're inside here.
    ///
    /// Gated on `EusoTripConfig.tunnelAwareETAEnabled`. If the user
    /// hasn't granted location auth (watchOS piggy-backs on the paired
    /// iPhone's grant), `startUpdatingLocation()` just silently yields
    /// no callbacks — no crash, no drift in HOS or SOS behavior.
    private func startLocationPump() {
        guard EusoTripConfig.tunnelAwareETAEnabled else { return }
        locationManager.delegate = self
        // Request when-in-use only. Background updates during the
        // workout session don't need "Always" on watchOS.
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        locationManager.startUpdatingLocation()
    }

    private func stopLocationPump() {
        locationManager.stopUpdatingLocation()
    }

    // MARK: - Motion

    private func startMotion() {
        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 0.1
        motion.startAccelerometerUpdates(to: OperationQueue()) { data, _ in
            guard let d = data else { return }
            let g = sqrt(d.acceleration.x * d.acceleration.x +
                         d.acceleration.y * d.acceleration.y +
                         d.acceleration.z * d.acceleration.z)
            // Simple thresholding — production would filter + debounce.
            if g > 2.3 {
                let ev = MotionEvent(kind: .hardBrake, at: Date())
                Task { @MainActor in
                    DrivingSessionManager.shared.lastMotionEvent = ev
                    WKInterfaceDevice.current().play(.notification)
                }
            }
            // Q3 — feed the fatigue predictor's accel window at the
            // same 10 Hz cadence. Extract primitives on the callback
            // thread; the predictor hops to MainActor internally.
            let ax = d.acceleration.x, ay = d.acceleration.y, az = d.acceleration.z
            let at = Date()
            Task { @MainActor in
                FatiguePredictor.shared.ingestAccelerometer(x: ax, y: ay, z: az, at: at)
            }
        }

        // Gyro (z-axis only used by the fatigue predictor, so we
        // subscribe at a low cadence to save battery). Available on
        // all Apple Watch Series 3+; the guard keeps us safe on the
        // simulator where the sensor may not be present.
        if motion.isGyroAvailable {
            motion.gyroUpdateInterval = 0.1
            motion.startGyroUpdates(to: OperationQueue()) { data, _ in
                guard let d = data else { return }
                let z = d.rotationRate.z
                let at = Date()
                Task { @MainActor in
                    FatiguePredictor.shared.ingestGyro(z: z, at: at)
                }
            }
        }

        if CMMotionActivityManager.isActivityAvailable() {
            activity.startActivityUpdates(to: .main) { act in
                guard let act else { return }
                // Auto-start HOS "driving" when motion-type transitions to automotive
                if act.automotive, act.confidence != .low {
                    Task { @MainActor in
                        if HOSStore.shared.current.status != .driving {
                            HOSStore.shared.applyRemote(
                                status: HOSStatus.driving.rawValue,
                                driveRemainingMinutes: HOSStore.shared.current.driveRemainingMinutes,
                                windowRemainingMinutes: HOSStore.shared.current.windowRemainingMinutes
                            )
                        }
                    }
                }
            }
        }
    }

    private func stopMotion() {
        motion.stopAccelerometerUpdates()
        if motion.isGyroActive { motion.stopGyroUpdates() }
        activity.stopActivityUpdates()
        fatigueTicker?.invalidate()
        fatigueTicker = nil
    }

    // MARK: - Fatigue predictor 1-Hz tick

    /// FatiguePredictor needs a low-frequency pulse to re-run its
    /// scoring head + decrement its sliding windows. We drive it here
    /// rather than from FatiguePredictor itself so the predictor only
    /// recomputes while the driver is in a workout session — no point
    /// scoring fatigue when the watch is sitting on the nightstand.
    private var fatigueTicker: Timer?
    private func startFatigueTicker() {
        fatigueTicker?.invalidate()
        fatigueTicker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                FatiguePredictor.shared.tickOneSecond()
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate (F02 feed)

extension DrivingSessionManager: CLLocationManagerDelegate {
    // Delegate methods arrive on the main thread by default on
    // watchOS because the CLLocationManager was created on the main
    // actor. We still mark nonisolated + hop explicitly so Swift 6
    // concurrency doesn't complain about the actor boundary.
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            // Publish current speed for any UI that cares (Route overview,
            // instrument panel). TunnelAwareETA owns the fix classification
            // so that service gets the full CLLocation; UI-level consumers
            // just need the scalar.
            DrivingSessionManager.shared.currentSpeedMps = max(0, latest.speed)
            TunnelAwareETA.shared.ingest(latest)
            // F02b — general dead-zone coast propagator. Parallel to
            // TunnelAwareETA: the coast service only kicks in after a
            // longer silence threshold and stays breadcrumb-grade, so
            // it's fine to run both.
            DeadZoneCoast.shared.ingest(latest)
            // F06 — feed the EWMA route learner. Gated internally on
            // `learnedRouteETAEnabled` so flipping the flag off is
            // sufficient to halt all training without touching this site.
            LearnedRouteETA.shared.ingest(latest)
            // F13 — feed the convoy coordinator so it can compute
            // heading/speed deltas against peers. Gated on its own flag;
            // no-op when off.
            ConvoyCoordinator.shared.observeLocalLocation(
                latest,
                activeLoadId: LoadStore.shared.active?.id
            )
            // F14 — advance the keep-alive nav cursor. Internally gated
            // on `isActive` + `keepAliveNavigationEnabled`, so this is a
            // fast no-op when nav isn't running. Has to be on the fan-
            // out (not its own CL pipe) so we're looking at the exact
            // same filtered, accuracy-bounded fixes that TunnelAwareETA
            // and the fatigue predictor see.
            NavigationSession.shared.ingest(latest)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Non-fatal — tunnelDR handles loss of fix internally.
    }
}
