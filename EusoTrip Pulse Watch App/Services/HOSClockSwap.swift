//
//  HOSClockSwap.swift
//  EusoTrip Pulse Watch App
//
//  F05 — HOS clock swap via updateApplicationContext (Q2 2026).
//
//  The iOS companion's HOSClockService polls server state roughly every
//  five minutes and pushes the result to the wrist via
//  `WCSession.updateApplicationContext`. Between pushes the wrist needs
//  to keep ticking — a display that freezes at "7h 43m remaining" for
//  four minutes while the driver stares at it does not inspire trust.
//
//  This service:
//    1. Subscribes to HOSStore published state.
//    2. On every fresh applyRemote(...) it captures `(snapshot, ts)`.
//    3. A 1-second timer extrapolates the clock forward from the last
//       snapshot when status is `.driving` (the only status that burns
//       the drive clock). When a new snapshot arrives, we "swap" — if
//       the delta between our extrapolation and the server snapshot is
//       > swapThreshold, we post a notification so the UI can flash a
//       subtle re-sync animation.
//    4. While swapping, we favor the server's value (it's authoritative
//       for compliance) and quietly correct local drift.
//
//  Net effect: the wrist shows live-ticking HOS clocks that stay within
//  ~1 second of the iOS app, with no duplicate timer logic in views.
//

import Foundation
import Combine

@MainActor
final class HOSClockSwap: ObservableObject {
    static let shared = HOSClockSwap()

    /// Live, 1-second-extrapolated snapshot. UI reads from here.
    @Published private(set) var liveDriveRemaining: Int = 0   // seconds
    @Published private(set) var liveWindowRemaining: Int = 0  // seconds
    @Published private(set) var liveCycleRemaining: Int = 0   // seconds
    @Published private(set) var swappedAt: Date?

    private var lastSnapshotAt: Date?
    private var lastStatus: String = "off"
    private var timer: Timer?
    private var cancellables: [AnyCancellable] = []
    private let swapThresholdSeconds: Int = 120

    func start(hos: HOSStore) {
        stop()
        // Seed from any prior state.
        absorb(from: hos.current)

        // Watch HOSStore for fresh server pushes.
        hos.$current
            .sink { [weak self] snapshot in
                self?.absorb(from: snapshot)
            }
            .store(in: &cancellables)

        // Local 1-second extrapolation.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.tick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cancellables.removeAll()
    }

    /// Called whenever HOSStore gets a fresh server push. Detects whether
    /// our local extrapolation has drifted far enough to count as a
    /// "swap" event (the UI can animate that).
    private func absorb(from snapshot: WatchHOS) {
        let status = snapshot.status.rawValue
        let driveMin = snapshot.driveRemainingMinutes
        let windowMin = snapshot.windowRemainingMinutes
        let cycleMin = snapshot.cycleRemainingMinutes
        let now = Date()
        let driveSec = driveMin * 60
        let windowSec = windowMin * 60
        let cycleSec = cycleMin * 60

        // Drift check against our local extrapolation — only meaningful
        // if we already have a prior snapshot.
        if lastSnapshotAt != nil {
            let drift = abs(liveDriveRemaining - driveSec)
            if drift >= swapThresholdSeconds {
                swappedAt = now
                NotificationCenter.default.post(name: .hosClockSwapped, object: nil, userInfo: [
                    "driftSeconds": drift
                ])
            }
        }

        liveDriveRemaining  = driveSec
        liveWindowRemaining = windowSec
        liveCycleRemaining  = cycleSec
        lastStatus = status
        lastSnapshotAt = now
    }

    /// Local tick — decrement drive clock by 1s when driving, clamp to 0.
    /// Window clock decrements whenever the driver is on-duty or driving.
    /// Cycle clock is the 60/70-hour 7/8-day total; it decrements only on
    /// driving / on_duty minutes as well.
    private func tick() {
        guard lastSnapshotAt != nil else { return }
        switch lastStatus {
        case "driving":
            if liveDriveRemaining > 0 { liveDriveRemaining -= 1 }
            if liveWindowRemaining > 0 { liveWindowRemaining -= 1 }
            if liveCycleRemaining > 0 { liveCycleRemaining -= 1 }
        case "on_duty":
            if liveWindowRemaining > 0 { liveWindowRemaining -= 1 }
            if liveCycleRemaining > 0 { liveCycleRemaining -= 1 }
        case "sleeper", "off", "off_duty":
            break
        default:
            break
        }
    }
}

extension Notification.Name {
    static let hosClockSwapped = Notification.Name("com.eusotrip.hosClockSwapped")
}
