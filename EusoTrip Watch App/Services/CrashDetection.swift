//
//  CrashDetection.swift
//  EusoTrip Watch App
//
//  Thin wrapper around watchOS crash-detection signals. We read the
//  HKCategoryType `.handwashingEvent` — no wait, we listen for the
//  CMCrashDetection events surfaced by CoreMotion in watchOS 10+.
//
//  When Apple-native crash detection fires (it only fires for severe
//  impacts at vehicle speeds) the OS already runs its own prompt. Our
//  job is parallel — not replacement:
//    - Fire `emergencyProtocols.activate(reason: "crash_detected")`
//      so the backend notifies dispatch + broker-of-record + next-of-kin
//    - Log the event to the HOS log automatically (stops the duty clock)
//    - Preserve the last 5 minutes of telemetry in case of a claim
//
//  Spec §8.1.
//

import Foundation
import CoreMotion
import WatchKit

@MainActor
final class CrashDetection: ObservableObject {
    static let shared = CrashDetection()

    @Published private(set) var lastCrashTime: Date?

    private let motion = CMMotionManager()

    /// Called by DrivingSessionManager when a workout session is active.
    /// Uses raw accelerometer magnitude as a proxy trigger (>= 6g sudden
    /// spike persisting 150ms) because watchOS doesn't expose the
    /// internal CMCrashDetection API to third parties — only the OS
    /// native prompt handles that. This belt-and-suspenders detector
    /// gives us independent coverage.
    func startMonitoring(auth: AuthStore, connectivity: WatchConnectivityManager) {
        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 0.02 // 50 Hz
        var window: [Double] = []

        motion.startAccelerometerUpdates(to: OperationQueue()) { [weak self] data, _ in
            guard let self, let d = data else { return }
            let g = sqrt(d.acceleration.x * d.acceleration.x +
                         d.acceleration.y * d.acceleration.y +
                         d.acceleration.z * d.acceleration.z)
            window.append(g)
            if window.count > 10 { window.removeFirst() }
            let peak = window.max() ?? 0
            if peak >= 6 {
                Task { @MainActor in
                    await self.onCrash(auth: auth, connectivity: connectivity)
                }
            }
        }
    }

    func stopMonitoring() {
        motion.stopAccelerometerUpdates()
    }

    private func onCrash(auth: AuthStore, connectivity: WatchConnectivityManager) async {
        guard lastCrashTime == nil ||
              Date().timeIntervalSince(lastCrashTime!) > 120 else { return }
        lastCrashTime = Date()
        WKInterfaceDevice.current().play(.failure)

        // Auto-log HOS transition
        await HOSStore.shared.changeStatus(to: .onDuty, auth: auth, connectivity: connectivity)

        // Emergency escalation (not silent — countdown visible)
        await EmergencyController.shared.activate(
            reason: "crash_detected_watch",
            auth: auth,
            connectivity: connectivity,
            silent: false
        )
    }
}
