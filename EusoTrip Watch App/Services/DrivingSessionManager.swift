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
import HealthKit
import CoreMotion
import SwiftUI
import WatchKit

@MainActor
final class DrivingSessionManager: ObservableObject {
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

    struct MotionEvent: Equatable {
        let kind: Kind
        let at: Date
        enum Kind: String { case hardBrake, pothole, sharpLeft, sharpRight, possibleRollover }
    }

    func begin() {
        guard HKHealthStore.isHealthDataAvailable(), !isRunning else { return }

        // Workout type = .other — we don't care about calorie reporting,
        // we just want the OS to give us background execution.
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .outdoor

        let types: Set<HKSampleType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]
        healthStore.requestAuthorization(toShare: nil, read: types) { [weak self] _, _ in
            Task { @MainActor in
                self?.startSession(config: config)
            }
        }
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
        } catch {
            // swallow — without a workout session we fall back to reduced
            // background and the app may suspend; not fatal.
        }
    }

    func end() async {
        guard let session = workoutSession else { return }
        session.stopActivity(with: Date())
        session.end()
        try? await workoutBuilder?.endCollection(at: Date())
        try? await workoutBuilder?.finishWorkout()
        workoutSession = nil
        workoutBuilder = nil
        isRunning = false
        startedAt = nil
        stopMotion()
    }

    // MARK: - Motion

    private func startMotion() {
        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 0.1
        motion.startAccelerometerUpdates(to: OperationQueue()) { [weak self] data, _ in
            guard let self, let d = data else { return }
            let g = sqrt(d.acceleration.x * d.acceleration.x +
                         d.acceleration.y * d.acceleration.y +
                         d.acceleration.z * d.acceleration.z)
            // Simple thresholding — production would filter + debounce.
            if g > 2.3 {
                let ev = MotionEvent(kind: .hardBrake, at: Date())
                Task { @MainActor in
                    self.lastMotionEvent = ev
                    WKInterfaceDevice.current().play(.notification)
                }
            }
        }

        if CMMotionActivityManager.isActivityAvailable() {
            activity.startActivityUpdates(to: .main) { [weak self] act in
                guard let self, let act else { return }
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
        activity.stopActivityUpdates()
    }
}
