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
import Combine
import WatchKit
import CoreLocation

@MainActor
final class EmergencyController: NSObject, ObservableObject {
    static let shared = EmergencyController()

    @Published var isActive: Bool = false
    @Published var countdownSeconds: Int = 30
    @Published var reason: String = ""
    @Published var silent: Bool = false

    private var countdownTask: Task<Void, Never>?
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

        // Q4 — chain the SOS into the tamper-evident audit log so the
        // activation time + coordinate can't be retroactively edited by
        // a hostile actor who gains filesystem access. The receipt is
        // the `AuditBlock` returned by append(); its hash becomes the
        // anchor for any subsequent chain-of-custody events.
        if EusoTripConfig.blockchainAuditEnabled {
            BlockchainAudit.shared.append(
                kind: .emergency,
                payload: [
                    "reason": reason,
                    "silent": silent ? "1" : "0",
                    "lat": String(format: "%.6f", coord?.latitude ?? 0),
                    "lon": String(format: "%.6f", coord?.longitude ?? 0),
                    "source": "watch"
                ]
            )
        }

        // F13 — fan out to the convoy so the trailing trucks learn
        // something's wrong even if our own cellular radio is dead.
        // ConvoyCoordinator gates on its own flag and no-ops cleanly
        // when the convoy feature is off.
        ConvoyCoordinator.shared.broadcastLocalSOS(
            reason: reason,
            coordinate: coord
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
        countdownTask?.cancel()
        countdownTask = nil
        isActive = false
        countdownSeconds = 0
        WKInterfaceDevice.current().play(.click)
    }

    private func startCountdown() {
        // Use a structured Task instead of Timer — Timer is not Sendable
        // and can't be captured inside an @Sendable closure without a
        // strict-concurrency warning. Task + Task.sleep is the modern
        // replacement and keeps us on MainActor throughout.
        countdownTask?.cancel()
        countdownTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.countdownSeconds -= 1
                if self.countdownSeconds <= 0 {
                    self.escalate()
                    return
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
