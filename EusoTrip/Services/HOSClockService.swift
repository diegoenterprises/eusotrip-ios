//
//  HOSClockService.swift
//  EusoTrip — Slow-poll HOS observer → TripEvent bridge.
//
//  Wakes up every `pollInterval` (default 5 min) while the driver is
//  signed in and asks the backend for the current `hos.getStatus`
//  payload. The response is published so any UI that wants a live
//  clock can read it, and — more importantly — when the remaining
//  driving or on-duty window dips below `warningThreshold` (30 min by
//  default) or the backend sets `breakRequired = true`, the service
//  fires `.hosBreakRequired` into the shared `DriverTripController`.
//
//  That routes the driver through the existing 019 HOS-break screen
//  (phase `.hosBreak`) without the driver having to notice the clock
//  on their own.
//
//  The service also debounces: once it has fired `.hosBreakRequired`
//  for a given polling window, it won't fire again until the
//  backend-reported `drivingRemaining` climbs back above the threshold
//  (i.e. the driver took a qualifying break and the server reset the
//  14-hour window). This keeps the controller from re-opening 019 on
//  every poll while the driver is actually resting.
//
//  Lifecycle:
//    • `start()` — called from EusoTripApp when session.phase becomes
//      .signedIn. Kicks off one immediate poll + a repeating timer.
//    • `stop()`  — called on sign-out or background suspension. Cancels
//      the task; published `status` is left intact so UI transitions
//      don't thrash.
//
//  This is intentionally lightweight: no separate thread, no socket,
//  no CMMotionManager. The backend is authoritative for HOS; we just
//  glance at it on a timer and surface warnings into the UI layer.
//

import Foundation
import SwiftUI

@MainActor
final class HOSClockService: ObservableObject {

    static let shared = HOSClockService()

    /// Latest `hos.getStatus` payload — nil until the first successful
    /// poll. DriverHome already has its own copy on the view model,
    /// but exposing it here lets any other surface observe live.
    @Published private(set) var status: HOSStatus?

    /// How often to poll while signed-in. Five minutes is a compromise
    /// between liveness and battery — HOS clocks don't tick fast enough
    /// for a tighter window to matter.
    var pollInterval: TimeInterval = 5 * 60

    /// Fire `.hosBreakRequired` when `drivingRemaining` drops below
    /// this many hours (default 30 min). This gives the UI a lead time
    /// so the 019 screen shows *before* the driver is forced into a
    /// violation.
    var warningThresholdHours: Double = 0.5

    /// Weak link back to the trip controller. Set lazily so app-
    /// construction order doesn't matter — first successful poll will
    /// resolve it from the shared environment if available.
    private weak var controller: DriverTripController?

    /// Has the current "approaching limit" warning already fired? Reset
    /// once the backend reports `drivingRemaining` > threshold again.
    private var warnedThisCycle: Bool = false

    private var pollTask: Task<Void, Never>?

    // MARK: Binding

    /// Called by the root view once `DriverTripController` exists. Same
    /// contract as `GeofenceService.bind(to:)` — weak ref, safe to call
    /// repeatedly.
    func bind(to controller: DriverTripController) {
        self.controller = controller
    }

    // MARK: Lifecycle

    /// Begin polling. Idempotent — calling while already running is a
    /// no-op.
    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.runPollLoop()
        }
    }

    /// Cancel the polling loop. Published `status` survives so UI
    /// transitions don't thrash between signed-out/signed-in.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: Poll loop

    private func runPollLoop() async {
        // Immediate fetch + spaced subsequent fetches. Failures are
        // swallowed — a transient network drop shouldn't knock the
        // driver out of the flow; the next tick will try again.
        while !Task.isCancelled {
            await pollOnce()
            let ns = UInt64(pollInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
        }
    }

    private func pollOnce() async {
        do {
            let fresh = try await EusoTripAPI.shared.hos.getStatus()
            self.status = fresh
            evaluate(status: fresh)
            pushToWatch(fresh)
        } catch {
            #if DEBUG
            print("[HOSClock] poll failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Mirror the freshest HOS snapshot onto the wrist. The watch stores
    /// everything in minutes (to match the `eld.getSummary` shape), so
    /// convert the hour-floats here. This is a best-effort broadcast —
    /// if the watch isn't paired or isn't reachable WCSession silently
    /// drops it and the watch will pick up the next applicationContext
    /// on its own.
    private func pushToWatch(_ fresh: HOSStatus) {
        let drv = Int((fresh.drivingRemaining * 60).rounded())
        let win = Int((fresh.onDutyRemaining * 60).rounded())
        let cyc = Int((fresh.cycleRemaining * 60).rounded())
        WatchAuthBridge.shared.pushHOSUpdate(
            status: fresh.status,
            driveRemainingMinutes: drv,
            windowRemainingMinutes: win,
            cycleRemainingMinutes: cyc
        )
    }

    /// Compare the fresh status against our warning threshold and
    /// fire `.hosBreakRequired` if it's time.
    private func evaluate(status: HOSStatus) {
        let approaching = status.drivingRemaining <= warningThresholdHours
                       || status.onDutyRemaining  <= warningThresholdHours
                       || status.breakRequired

        if approaching, !warnedThisCycle {
            warnedThisCycle = true
            controller?.handle(.hosBreakRequired)
            #if DEBUG
            print("[HOSClock] warn · drv=\(status.drivingRemaining)h " +
                  "ond=\(status.onDutyRemaining)h brkReq=\(status.breakRequired)")
            #endif
        } else if !approaching, warnedThisCycle {
            // Driver took a qualifying break — arm the next warning.
            warnedThisCycle = false
            #if DEBUG
            print("[HOSClock] cleared · drv=\(status.drivingRemaining)h")
            #endif
        }
    }
}
