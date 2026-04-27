//
//  EmergencyController.swift
//  EusoTrip Watch App
//
//  Central coordinator for SOS events. Three triggers:
//    1. Driver-initiated (long-press on wrist)
//    2. CrashDetection hook from CMMotionActivity (spec §8.1)
//    3. Duress-mode voice phrase
//
//  Each trigger does the same three things:
//    - Fires `emergencyProtocols.activate` on the backend
//    - Asks the phone to place an E911 call (watch can't dial alone)
//    - Surfaces an emergency UI sheet with 30-second countdown + Cancel
//
//  Spec §9.2 — duress mode: if the driver enters duress mode (voice
//  phrase "Esang I'm in trouble"), we silently flag the SOS with
//  `silent: true` so the watch UI shows a benign "Location saved"
//  toast but the backend still routes it to the security team.
//

import Foundation
import WatchKit
import CoreLocation

@MainActor
final class EmergencyController: NSObject, ObservableObject {
    static let shared = EmergencyController()

    @Published var isActive: Bool = false
    @Published var countdownSeconds: Int = 30
    @Published var reason: String = ""
    @Published var silent: Bool = false

    private var timer: Timer?
    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    // MARK: - Activate

    func activate(reason: String, auth: AuthStore, connectivity: WatchConnectivityManager, silent: Bool = false) async {
        self.reason = reason
        self.silent = silent
        self.countdownSeconds = silent ? 0 : 30
        self.isActive = true
        WKInterfaceDevice.current().play(silent ? .notification : .failure)

        // Ping phone immediately so E911 dial can start on the bigger radio.
        let coord = locationManager.location?.coordinate
        connectivity.triggerEmergencySOS(
            reason: reason,
            coordinate: coord.map { ($0.latitude, $0.longitude) }
        )

        // Backend escalation
        Task {
            do {
                let client = EsangClient(auth: auth)
                _ = try await client.mutateJSON(
                    "emergencyProtocols.activate",
                    input: [
                        "reason": reason,
                        "silent": silent,
                        "lat": coord?.latitude ?? 0,
                        "lon": coord?.longitude ?? 0,
                        "source": "watch"
                    ]
                )
            } catch {
                OfflineQueue.shared.enqueueSOS(
                    reason: reason,
                    lat: coord?.latitude,
                    lon: coord?.longitude
                )
            }
        }

        // Countdown (non-silent only) — driver can Cancel.
        if !silent {
            startCountdown()
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        isActive = false
        countdownSeconds = 0
        WKInterfaceDevice.current().play(.click)
    }

    private func startCountdown() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            Task { @MainActor in
                self.countdownSeconds -= 1
                if self.countdownSeconds <= 0 {
                    t.invalidate()
                    self.escalate()
                }
            }
        }
    }

    private func escalate() {
        // Countdown elapsed without cancellation — hold the sheet open,
        // keep haptics loud. The phone placed the E911 call already.
        WKInterfaceDevice.current().play(.failure)
    }
}
