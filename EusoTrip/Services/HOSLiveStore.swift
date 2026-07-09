//
//  HOSLiveStore.swift
//  EusoTrip — Live backing store for the ELD overview (MeEldView) and
//  the HOS duty-status screen (019_HosDutyStatus).
//
//  Why this exists:
//  -----------------
//  The detail screens used to render hardcoded strings. `HOSClockService`
//  already polls `hos.getStatus` every 5 min and publishes the dashboard
//  snapshot, but the ELD / 019 screens additionally need:
//    • today's segment list (the 24-hour timeline strip and log table)
//    • last 8 days of rollups (the cycle bar chart)
//    • unresolved violations
//    • the ability to flip OFF / SB / D / ON from the UI
//    • driver certification + remark entry
//
//  HOSLiveStore gathers all of that behind a single @StateObject that
//  the screens can bind to. It piggy-backs on `HOSClockService.shared`
//  for the dashboard snapshot (so we don't double-poll) and owns its
//  own fetch path for the richer log data.
//
//  Single source of truth: the backend. Optimistic updates are allowed
//  for duty transitions (so the 4-button picker feels instant), but
//  every write is round-tripped and reconciled against the response.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class HOSLiveStore: ObservableObject {

    // MARK: Published state

    /// Dashboard snapshot — mirror of HOSClockService so we only poll once.
    @Published private(set) var status: HOSStatus?

    /// Today's §395.8 daily log (segments + totals).
    @Published private(set) var today: HOSDailyLog?

    /// Last 8 days of daily logs, newest-first. Feeds the cycle bar
    /// chart on the ELD overview.
    @Published private(set) var history: [HOSDailyLog] = []

    /// Unresolved violations the driver should be shown on 019.
    @Published private(set) var violations: [HOSViolation] = []

    /// Loading flag for the first-run fetch and pull-to-refresh.
    @Published private(set) var isLoading: Bool = false

    /// True while a duty-status transition is in flight — disables the
    /// picker so the driver can't double-tap during the round-trip.
    @Published private(set) var isChangingStatus: Bool = false

    /// Non-fatal error from the most recent fetch. Cleared when a
    /// fresh fetch succeeds.
    @Published var lastError: String?

    /// Toast string shown after the most recent mutation (certify,
    /// remark, change). Cleared after 3s.
    @Published var lastToast: String?

    // MARK: Dependencies

    private let api: EusoTripAPI
    private var cancellables = Set<AnyCancellable>()
    private var toastTask: Task<Void, Never>?

    init(api: EusoTripAPI = .shared) {
        self.api = api

        // Mirror HOSClockService — it already polls every 5 min. If the
        // clock service is running, its @Published `status` is the
        // authoritative dashboard snapshot.
        HOSClockService.shared.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] fresh in
                self?.status = fresh
            }
            .store(in: &cancellables)

        // Fast-follow on realtime wake-ups so the log strip updates as
        // soon as the backend emits LOAD_STATE_CHANGED / HOS_WARNING etc.
        NotificationCenter.default.publisher(for: .esangRefreshSurface)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in await self?.refreshLogs() }
            }
            .store(in: &cancellables)
    }

    // MARK: Lifecycle

    /// Called from `.task {}` on the screen. Idempotent — safe to call
    /// on every view appearance.
    func bootstrap() async {
        if today == nil || history.isEmpty {
            await refreshAll()
        } else {
            // Cheap refresh — just the log strip.
            await refreshLogs()
        }
    }

    /// Full fetch: dashboard snapshot, today's log, last 8 days, violations.
    func refreshAll() async {
        isLoading = true
        defer { isLoading = false }

        // Kick the dashboard snapshot (redundant with HOSClockService's
        // polling but gets us fresh data immediately on first open).
        async let snap = captureFetch("HOS dashboard") { try await self.api.hos.getStatus() }
        async let td = captureFetch("daily log") { try await self.api.hos.getDailyLog() }
        async let hist = captureFetch("8-day history") { try await self.api.hos.getLogHistory(days: 8) }
        async let viol = captureFetch("violations") { try await self.api.hos.getViolations() }

        let (snapResult, dayResult, historyResult, violationResult) = await (snap, td, hist, viol)
        var failures: [HOSFetchFailure] = []
        var landed = false

        switch snapResult {
        case .value(let fresh):
            self.status = fresh
            landed = true
        case .failure(let failure):
            failures.append(failure)
        }

        switch dayResult {
        case .value(let day):
            self.today = day
            landed = true
        case .failure(let failure):
            failures.append(failure)
        }

        switch historyResult {
        case .value(let rollups):
            self.history = rollups
            landed = true
        case .failure(let failure):
            failures.append(failure)
        }

        switch violationResult {
        case .value(let v):
            self.violations = v
            landed = true
        case .failure(let failure):
            failures.append(failure)
        }

        applyFetchFailures(failures, partialDataLanded: landed)
    }

    /// Log-only refresh (no dashboard poll — HOSClockService handles that).
    func refreshLogs() async {
        async let td = captureFetch("daily log") { try await self.api.hos.getDailyLog() }
        async let hist = captureFetch("8-day history") { try await self.api.hos.getLogHistory(days: 8) }
        async let viol = captureFetch("violations") { try await self.api.hos.getViolations() }
        let (dayResult, historyResult, violationResult) = await (td, hist, viol)

        var failures: [HOSFetchFailure] = []
        var landed = false

        switch dayResult {
        case .value(let day):
            self.today = day
            landed = true
        case .failure(let failure):
            failures.append(failure)
        }

        switch historyResult {
        case .value(let rollups):
            self.history = rollups
            landed = true
        case .failure(let failure):
            failures.append(failure)
        }

        switch violationResult {
        case .value(let v):
            self.violations = v
            landed = true
        case .failure(let failure):
            failures.append(failure)
        }

        applyFetchFailures(failures, partialDataLanded: landed)
    }

    // MARK: Duty-status transitions

    /// Flip duty status from the iOS UI. Optimistically updates the
    /// local snapshot so the picker feels instant, then reconciles
    /// against the server response.
    ///
    /// Round-trip: `hos.changeStatus` → dashboard snapshot → today's log.
    ///
    /// `location` is the human-readable place string the backend writes
    /// into `hos_logs.location_description` per §395.8(h). Callers should
    /// pass `DriverHomeViewModel.lastKnownLocation` (or a reverse-geocoded
    /// city/state) when available. Empty string is accepted by the
    /// server but logs a compliance soft-warning — TODO: wire a shared
    /// LocationService so every change-status site has a real fix.
    @discardableResult
    func changeStatus(
        to new: HOSDutyCode,
        location: String = "",
        remark: String? = nil,
        loadId: String? = nil
    ) async -> Bool {
        guard !isChangingStatus else { return false }
        isChangingStatus = true
        defer { isChangingStatus = false }

        // Optimistic — rewrite the dashboard snapshot so the 4-button
        // picker highlights the new selection immediately. We do NOT
        // promote `canDrive` to true on a Drive request: the FMCSA
        // gates (11h drive bank, 14h on-duty window, 30-min break
        // due, 70/8 cycle) are server-evaluated. If the driver hits
        // the picker out of compliance, the backend rejects the
        // transition AND the rollback below re-polls the truth. Old
        // behavior (`canDrive: new == .driving ? true : s.canDrive`)
        // briefly painted the orb green even when the server was
        // about to reject — a real compliance footgun. We carry the
        // server-side `canDrive` forward unchanged; the picker
        // highlight is enough optimistic UX without faking the gate.
        if var s = status {
            s = HOSStatus(
                drivingRemaining: s.drivingRemaining,
                onDutyRemaining:  s.onDutyRemaining,
                cycleRemaining:   s.cycleRemaining,
                breakRequired:    s.breakRequired,
                nextBreakDue:     s.nextBreakDue,
                status:           new.rawValue,
                canDrive:         s.canDrive,
                canAcceptLoad:    s.canAcceptLoad
            )
            self.status = s
        }

        do {
            let result = try await api.hos.changeStatus(
                status: new,
                source: "ios",
                location: location,
                remark: remark,
                loadId: loadId
            )
            if let snap = result.snapshot { self.status = snap }
            await refreshLogs()
            flashToast(result.message ?? "Status set to \(new.shortLabel)")
            return result.ok
        } catch EusoTripAPIError.queuedForOfflineReplay {
            // Offline — the duty-status change was persisted to the Unified
            // Outbox and will replay on reconnect. Keep the optimistic
            // picker highlight (we do NOT re-poll, which would clobber it
            // with the stale server snapshot) and tell the driver honestly.
            flashToast("Duty status queued — will sync when you reconnect")
            return true
        } catch {
            // Roll back by re-polling
            do {
                let fresh = try await api.hos.getStatus()
                self.status = fresh
            } catch {
                self.lastError = Self.fetchFailureCopy(
                    HOSFetchFailure(area: "HOS dashboard", error: error),
                    partialDataLanded: status != nil
                )
            }
            // NEVER surface `error.localizedDescription` verbatim —
            // tRPC errors from the server arrive as multi-line Zod
            // dumps ("Could not change status — [{"code":"invalid_value",
            // "values":["off_duty"…]}]") which look like a crash to a
            // driver reading at 65 mph. The canonical causes are
            // always one of:
            //   • transient network / 500 → retry fixes it
            //   • server rejected the enum (usually a client-version
            //     mismatch — fixed in the changeStatus Input struct)
            //   • 403 / compliance gate (rare, logged server-side)
            // A one-line neutral "try again" message works for all
            // three; full diagnostic payloads stay in the logs.
            #if DEBUG
            print("[HOSLiveStore] changeStatus error: \(error)")
            #endif
            flashToast(Self.mutationFailureCopy(error, action: "change duty status"))
            return false
        }
    }

    // MARK: Certification / remarks

    /// §395.8(g) certify today's (or an explicit) daily log.
    @discardableResult
    func certify(date: String? = nil, signature: String) async -> Bool {
        let target = date ?? today?.date ?? Self.isoDayFormatter.string(from: Date())
        do {
            let result = try await api.hos.certifyLog(date: target, signature: signature)
            // The server acks `{success, date, certifiedAt}` without
            // echoing the day (hos.ts:208-212) — stamp the local copy so
            // the certify button reflects the acknowledged signature.
            if result.ok {
                let certDate = result.date ?? target
                if let t = today, t.date == certDate {
                    today = t.certifiedCopy(at: result.certifiedAt)
                }
                if let idx = history.firstIndex(where: { $0.date == certDate }) {
                    history[idx] = history[idx].certifiedCopy(at: result.certifiedAt)
                }
            }
            flashToast(result.message ?? "Log certified")
            return result.ok
        } catch EusoTripAPIError.queuedForOfflineReplay {
            // Defensive: certification isn't an enqueue-eligible mutation
            // today (a §395.8(g) signature is a legal event we don't replay
            // silently), so this branch normally won't fire — but if the
            // eligibility table ever grows to include it, surface the same
            // honest queued message instead of a hard error.
            flashToast("Duty status queued — will sync when you reconnect")
            return true
        } catch {
            flashToast(Self.mutationFailureCopy(error, action: "certify log"))
            return false
        }
    }

    /// Attach a §395.8(j) remark. `at` pins the remark to a specific
    /// segment's wall-clock (the 081 per-entry composer passes the
    /// segment start); nil means "now" — both resolve to the
    /// `{date, time, remark}` triple the server schema requires.
    @discardableResult
    func addRemark(_ text: String, entryId: String? = nil, at moment: Date? = nil) async -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        do {
            let result = try await api.hos.addRemark(
                text: text,
                entryId: entryId,
                date: moment.map(HOSAPI.dayString),
                time: moment.map(HOSAPI.timeString)
            )
            await refreshLogs()
            flashToast(result.message ?? "Remark added")
            return result.ok
        } catch EusoTripAPIError.queuedForOfflineReplay {
            // Defensive: §395.8(j) remarks aren't enqueue-eligible today,
            // so this normally won't fire — but if the outbox ever covers
            // them, show the honest queued message rather than a hard fail.
            flashToast("Duty status queued — will sync when you reconnect")
            return true
        } catch {
            flashToast(Self.mutationFailureCopy(error, action: "save remark"))
            return false
        }
    }

    // MARK: Derived convenience

    /// The currently-selected duty code, driven by the server snapshot.
    /// Defaults to off-duty until the first fetch lands.
    var currentDuty: HOSDutyCode {
        HOSDutyCode(rawValue: status?.status ?? "off_duty") ?? .offDuty
    }

    /// Minutes until the §395.3(a)(3)(ii) 30-min break is required.
    /// nil when no break is approaching.
    var minutesUntilBreak: Int? {
        guard let status else { return nil }
        if status.breakRequired { return 0 }
        guard let iso = status.nextBreakDue,
              let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        let delta = Int(date.timeIntervalSinceNow / 60)
        return delta > 0 ? delta : 0
    }

    /// Most-recent uncertified day (so the 019 "Certify yesterday"
    /// button knows which day to operate on).
    var yesterdayUncertified: HOSDailyLog? {
        history.first { !$0.certified && $0.date != today?.date }
    }

    // MARK: Toast helper

    private func flashToast(_ text: String) {
        toastTask?.cancel()
        lastToast = text
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
            self?.lastToast = nil
        }
    }

    private enum HOSFetchResult<Value> {
        case value(Value)
        case failure(HOSFetchFailure)
    }

    private struct HOSFetchFailure {
        let area: String
        let error: Error
    }

    private func captureFetch<Value>(
        _ area: String,
        _ operation: @escaping () async throws -> Value
    ) async -> HOSFetchResult<Value> {
        do {
            return .value(try await operation())
        } catch {
            return .failure(HOSFetchFailure(area: area, error: error))
        }
    }

    private func applyFetchFailures(_ failures: [HOSFetchFailure], partialDataLanded: Bool) {
        guard let first = failures.first else {
            lastError = nil
            return
        }
        lastError = Self.fetchFailureCopy(first, partialDataLanded: partialDataLanded)
        if failures.contains(where: { failure in
            if case EusoTripAPIError.unauthenticated = failure.error { return true }
            return false
        }) {
            NotificationCenter.default.post(name: Notification.Name("eusoLogoutRequested"), object: nil)
        }
    }

    private static func fetchFailureCopy(
        _ failure: HOSFetchFailure,
        partialDataLanded: Bool
    ) -> String {
        let prefix = partialDataLanded ? "Some HOS data could not refresh" : "HOS and ELD data could not load"
        switch failure.error {
        case EusoTripAPIError.unauthenticated:
            return "Session check needed. Sign in again to reload HOS and ELD records."
        case EusoTripAPIError.forbidden(let message):
            return "Compliance role mismatch. \(cleanServerMessage(message))"
        case EusoTripAPIError.decodingFailed:
            return "\(prefix). The server response changed; update the app or pull to retry."
        case EusoTripAPIError.notConfigured:
            return "Compliance service is not configured for this build."
        case EusoTripAPIError.httpStatus(let code, _):
            return "\(prefix). Server returned HTTP \(code). Pull to retry."
        case EusoTripAPIError.trpcError(let message):
            return "\(prefix): \(cleanServerMessage(message))"
        default:
            return "\(prefix). Pull to retry."
        }
    }

    private static func mutationFailureCopy(_ error: Error, action: String) -> String {
        switch error {
        case EusoTripAPIError.unauthenticated:
            NotificationCenter.default.post(name: Notification.Name("eusoLogoutRequested"), object: nil)
            return "Session check needed. Sign in again to \(action)."
        case EusoTripAPIError.forbidden(let message):
            return "Permission mismatch: \(cleanServerMessage(message))"
        case EusoTripAPIError.decodingFailed:
            return "Could not \(action). The server response changed; update the app or retry."
        case EusoTripAPIError.trpcError(let message):
            return "Could not \(action): \(cleanServerMessage(message))"
        case EusoTripAPIError.httpStatus(let code, _):
            return "Could not \(action). Server returned HTTP \(code)."
        default:
            return "Could not \(action). Try again in a moment."
        }
    }

    private static func cleanServerMessage(_ message: String) -> String {
        let cleaned = message
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Request failed." : cleaned
    }

    private static let isoDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

struct HOSConnectionBanner: View {
    @Environment(\.palette) private var palette

    let message: String
    let isLoading: Bool
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Brand.warning)
                .frame(width: 22, height: 22)

            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Space.s2)

            Button(action: retry) {
                HStack(spacing: 5) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text("Retry")
                        .font(EType.micro)
                        .tracking(0.8)
                }
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, Space.s2)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(palette.bgCard.opacity(0.9))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Brand.warning.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.warning.opacity(0.35), lineWidth: 1)
        )
    }
}
