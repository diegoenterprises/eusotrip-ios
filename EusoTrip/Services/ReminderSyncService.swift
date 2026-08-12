//
//  ReminderSyncService.swift
//  EusoTrip — the device half of `reminders.upcomingDeadlines`.
//
//  ReminderScheduler.swift already had deterministic ids, real
//  UNCalendarNotificationTriggers and real cancellation — but the only two
//  call sites in the app were manual snoozes. Nothing scheduled anything for
//  the obligations the platform already tracks: a CDL expiry, a VGM cutoff, a
//  container's last free day. This service is the missing input path. It asks
//  the server for the caller's PROVABLE deadlines and turns each one into
//  local notifications at the lead times the server's category ladder
//  prescribes.
//
//  ── THE CANCELLATION RULE (read this before touching anything) ────────────
//  A previously scheduled reminder is cancelled IF AND ONLY IF:
//
//        its `source` appears in the response's `cancellableSources`
//        AND its deadline `id` is absent from the response's `deadlines`
//
//  Nothing else cancels. Not a thrown request. Not `ok: false`. Not an empty
//  `deadlines` array. Not sign-out. The server deliberately withholds a source
//  from `cancellableSources` when that source errored, hit its row cap, or is
//  not applicable to the caller's modes — precisely so a bad network day can
//  never delete a driver's compliance reminders. A deadline we cannot see is
//  not a deadline that was met.
//
//  We add exactly one narrowing on top of the server's guarantee: when
//  `responseTruncated` is true we treat `cancellableSources` as empty. The
//  server already empties it in that case; this is belt-and-braces and can
//  only ever cancel LESS, never more.
//
//  ── WHAT THE LEDGER IS ────────────────────────────────────────────────────
//  "Previously scheduled" is read back from UNUserNotificationCenter itself —
//  pending AND delivered — not from a side table in UserDefaults that could
//  drift out of sync with what the system actually holds. Every identifier we
//  mint is deterministic and self-describing, so the notification centre IS
//  the ledger. Delivered ones are included because a delivered reminder for an
//  obligation that no longer exists is exactly as wrong as a pending one.
//
//  ── WHEN IT REFRESHES ─────────────────────────────────────────────────────
//  · sign-in                       — `start()` from EusoTripApp's phase hook
//  · foreground                    — UIApplication.didBecomeActiveNotification
//  · a silent push arriving        — PushService's background handler
//  · a slow periodic tick          — every 30 min while the app is running
//  No background mode is added. Everything above is a hook the app already had.
//
//  ── WHY THERE IS A BUDGET ─────────────────────────────────────────────────
//  iOS keeps at most 64 pending local notifications per app and silently drops
//  the rest. A 500-deadline response with a 4-rung ladder is 2,000 requests.
//  So candidates are ordered by fire time (soonest first, compliance/money
//  breaking ties) and only the first `scheduleBudget` are scheduled; the
//  remainder are REPORTED as deferred rather than pretended into existence.
//
//  Powered by ESANG AI™.
//

import Foundation
import Combine
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

// ───────────────────────────────────────────────────────────────────────────
// MARK: - Wire types (reminders.upcomingDeadlines)
// ───────────────────────────────────────────────────────────────────────────

/// The table.column a deadline was read from. Carried into the notification's
/// userInfo so a tap can show provenance instead of asking the driver to trust
/// a banner.
struct ReminderDeadlineProof: Decodable {
    let table: String?
    let column: String?
    let dbTable: String?
    let dbColumn: String?
    let rowId: String?
    let derived: Bool?
    let derivation: String?
}

/// One provable deadline.
///
/// `source`, `category` and `criticality` are decoded as `String`, NOT as
/// Swift enums. A server that adds a new source must not make the whole
/// response undecodable — that is the HERE decode trap (one unexpected value
/// in optional metadata discarding an entire valid payload) and it has cost
/// this codebase three outages.
struct ReminderDeadlineDTO: Decodable {
    let id: String
    let source: String
    let category: String?
    let criticality: String?
    let title: String
    let detail: String?
    let dueAt: String
    let schedulable: Bool
    let minutesUntilDue: Int?
    let leadMinutes: [Int]?
    let proof: ReminderDeadlineProof?
    let ref: String?
    let observedAt: String?
}

/// Per-source status. Read-only here: the cancellation decision is driven by
/// `cancellableSources`, never by re-deriving it from these reports.
struct ReminderSourceReportDTO: Decodable {
    let source: String
    let status: String
    let reason: String?
    let count: Int?
    let truncated: Bool?
    let readAt: String?
}

struct UpcomingDeadlinesResponse: Decodable {
    let ok: Bool
    let reason: String?
    let asOf: String?
    let horizonDays: Int?
    let overdueLookbackHours: Int?
    let modes: [String]?
    let deadlines: [ReminderDeadlineDTO]
    let sources: [ReminderSourceReportDTO]?
    let cancellableSources: [String]
    let degradedSources: [String]?
    let responseTruncated: Bool
}

extension EusoTripAPI {
    /// `reminders.upcomingDeadlines` — the device's scheduling input.
    ///
    /// A throw here is NOT an empty result: `ReminderSyncService` treats it as
    /// "we learned nothing" and changes no scheduled reminder.
    func upcomingReminderDeadlines(
        horizonDays: Int,
        overdueLookbackHours: Int
    ) async throws -> UpcomingDeadlinesResponse {
        struct In: Encodable {
            let horizonDays: Int
            let overdueLookbackHours: Int
        }
        return try await query(
            "reminders.upcomingDeadlines",
            input: In(horizonDays: horizonDays, overdueLookbackHours: overdueLookbackHours)
        )
    }
}

// ───────────────────────────────────────────────────────────────────────────
// MARK: - Identity codec
// ───────────────────────────────────────────────────────────────────────────

/// One reminder we have already scheduled, recovered from the notification
/// centre's own list.
struct ReminderLedgerEntry: Equatable {
    let source: String
    let deadlineId: String
    let leadMinutes: Int

    var subject: String {
        ReminderDeadlineIdentity.subject(
            source: source, deadlineId: deadlineId, leadMinutes: leadMinutes
        )
    }
}

/// Deterministic identifier codec. `ReminderScheduler.id(kind:subject:)` gives
/// `euso.reminder.<kind>.<subject>`; we own `kind == "deadline"` and encode the
/// rest of the identity into the subject, so a refetch of the same deadline at
/// the same lead produces the same identifier and REPLACES in place instead of
/// stacking a second banner.
enum ReminderDeadlineIdentity {

    /// `ReminderScheduler` reminder class for server-proved deadlines.
    static let kind = "deadline"

    /// Full identifier prefix of everything this service owns.
    static let identifierPrefix = "euso.reminder.deadline."

    /// Field separator. `|` never appears in a source name (server enum) and
    /// has never appeared in a deadline id (`source#rowId#epochSeconds`).
    static let separator = "|"

    static func subject(source: String, deadlineId: String, leadMinutes: Int) -> String {
        "\(source)\(separator)\(deadlineId)\(separator)\(leadMinutes)"
    }

    static func identifier(source: String, deadlineId: String, leadMinutes: Int) -> String {
        identifierPrefix + subject(source: source, deadlineId: deadlineId, leadMinutes: leadMinutes)
    }

    /// Recover the identity from a notification identifier. Returns nil for
    /// anything that is not ours or that we cannot attribute with certainty —
    /// and an unattributable reminder is never cancelled.
    static func parse(identifier: String) -> ReminderLedgerEntry? {
        var raw = identifier
        // PushService mints `snooze:<identifier>` copies; same identity.
        if raw.hasPrefix("snooze:") { raw = String(raw.dropFirst("snooze:".count)) }
        guard raw.hasPrefix(identifierPrefix) else { return nil }
        let body = String(raw.dropFirst(identifierPrefix.count))
        let parts = body.components(separatedBy: separator)
        // first = source, last = lead, everything between = the deadline id
        // (joined back, so an id that ever contains the separator survives).
        guard parts.count >= 3,
              let source = parts.first, !source.isEmpty,
              let lead = Int(parts[parts.count - 1])
        else { return nil }
        let deadlineId = parts[1..<(parts.count - 1)].joined(separator: separator)
        guard !deadlineId.isEmpty else { return nil }
        return ReminderLedgerEntry(source: source, deadlineId: deadlineId, leadMinutes: lead)
    }
}

// ───────────────────────────────────────────────────────────────────────────
// MARK: - The plan (pure — this is the part that must never be wrong)
// ───────────────────────────────────────────────────────────────────────────

/// What a sync decided to do. Computed from the response + the ledger with no
/// I/O at all, so the cancellation rule can be exercised directly by
/// `scripts/verify-reminder-sync-plan.swift`.
struct ReminderSyncPlan: Equatable {

    struct Scheduled: Equatable {
        let subject: String
        let source: String
        let deadlineId: String
        let leadMinutes: Int
        let fireAt: Date
        let dueAt: Date
        let title: String
        let body: String
        let category: String
        let criticality: String
        let ref: String?
        let proof: String?
        /// UNNotificationCategory identifier, or nil for no actions. See
        /// `pushCategory(for:)`.
        let pushCategory: String?
    }

    /// Ordered soonest-first; already trimmed to the budget.
    var scheduled: [Scheduled] = []
    /// Ledger entries that satisfied the cancellation rule. Nothing else.
    var cancelled: [ReminderLedgerEntry] = []
    /// Candidates that fit the rule but not the budget. Honest degradation:
    /// reported, never silently dropped.
    var deferred: Int = 0
    /// Deadlines the server marked `schedulable: false` (already past).
    var pastDue: Int = 0
    /// (deadline × lead) pairs whose fire time is already behind us.
    var leadsAlreadyPassed: Int = 0
    /// Deadlines whose `dueAt` could not be parsed. Never scheduled, never
    /// cancelled — an unreadable timestamp is not proof of anything.
    var unparseableDueAt: Int = 0

    static func make(
        response: UpcomingDeadlinesResponse,
        ledger: [ReminderLedgerEntry],
        now: Date,
        budget: Int
    ) -> ReminderSyncPlan {
        var plan = ReminderSyncPlan()
        let clock = ReminderWireClock()

        // ── 1. Cancellation. The rule, literally. ──────────────────────────
        //
        // `cancellableSources` is the ONLY authority for which sources may be
        // cancelled within. A truncated response empties it (the server does
        // this too — see the header).
        let cancellable: Set<String> =
            response.responseTruncated ? [] : Set(response.cancellableSources)
        let liveIds = Set(response.deadlines.map(\.id))
        for entry in ledger
        where cancellable.contains(entry.source) && !liveIds.contains(entry.deadlineId) {
            plan.cancelled.append(entry)
        }

        // ── 2. Candidates. One per (deadline × leadMinutes entry). ─────────
        var candidates: [Scheduled] = []
        for deadline in response.deadlines {
            guard let dueAt = clock.date(from: deadline.dueAt) else {
                plan.unparseableDueAt += 1
                continue
            }
            guard deadline.schedulable else {
                // Returned for display (overdue lookback) — its presence still
                // protects it from cancellation above, which is the point.
                plan.pastDue += 1
                continue
            }
            let category = deadline.category ?? "unknown"
            let criticality = deadline.criticality ?? "operational"
            let proof = deadline.proof.map { p -> String in
                let table = p.dbTable ?? p.table ?? "?"
                let column = p.dbColumn ?? p.column ?? "?"
                let row = p.rowId ?? "?"
                return "\(table).\(column)#\(row)"
            }
            for lead in (deadline.leadMinutes ?? []) where lead >= 0 {
                let fireAt = dueAt.addingTimeInterval(-Double(lead) * 60)
                guard fireAt > now else {
                    plan.leadsAlreadyPassed += 1
                    continue
                }
                candidates.append(Scheduled(
                    subject: ReminderDeadlineIdentity.subject(
                        source: deadline.source, deadlineId: deadline.id, leadMinutes: lead
                    ),
                    source: deadline.source,
                    deadlineId: deadline.id,
                    leadMinutes: lead,
                    fireAt: fireAt,
                    dueAt: dueAt,
                    title: deadline.title,
                    body: body(
                        leadMinutes: lead, dueAt: dueAt,
                        ref: deadline.ref, detail: deadline.detail, clock: clock
                    ),
                    category: category,
                    criticality: criticality,
                    ref: deadline.ref,
                    proof: proof,
                    pushCategory: pushCategory(for: category)
                ))
            }
        }

        // ── 3. Budget. Soonest first; compliance/money break a tie. ────────
        candidates.sort { a, b in
            if a.fireAt != b.fireAt { return a.fireAt < b.fireAt }
            let ra = criticalityRank(a.criticality), rb = criticalityRank(b.criticality)
            if ra != rb { return ra < rb }
            return a.subject < b.subject
        }
        if candidates.count > budget {
            plan.deferred = candidates.count - budget
            plan.scheduled = Array(candidates.prefix(budget))
        } else {
            plan.scheduled = candidates
        }
        return plan
    }

    /// The registered UNNotificationCategory to attach, or nil.
    ///
    /// PushService registers `compliance_expiring` with View / "Remind me in
    /// 15 min" / "Got it", and that identifier is in its `snoozableCategories`
    /// set — which is exactly right for a credential, document or insurance
    /// expiry: a future obligation that can honestly be snoozed. The remaining
    /// categories have no registered identifier, so they get nil (a banner
    /// with no actions) rather than an identifier iOS would silently ignore.
    static func pushCategory(for category: String) -> String? {
        switch category {
        case "credential", "document", "insurance": return "compliance_expiring"
        default: return nil
        }
    }

    /// Lower sorts first. Money and compliance outrank operational when two
    /// reminders want the same instant.
    static func criticalityRank(_ criticality: String) -> Int {
        switch criticality {
        case "compliance": return 0
        case "money":      return 1
        default:           return 2
        }
    }

    /// "In 14 days · Due Aug 25 at 5:00 PM · BKG-88213 · Carrier-supplied cutoff."
    /// Every clause is a restatement of something the server proved. Nothing
    /// here is inferred.
    static func body(
        leadMinutes: Int,
        dueAt: Date,
        ref: String?,
        detail: String?,
        clock: ReminderWireClock
    ) -> String {
        var parts: [String] = []
        parts.append("In \(leadPhrase(minutes: leadMinutes))")
        parts.append("Due \(clock.display(dueAt))")
        if let ref, !ref.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(ref)
        }
        if let detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(detail)
        }
        return parts.joined(separator: " · ")
    }

    static func leadPhrase(minutes: Int) -> String {
        if minutes >= 1440, minutes % 1440 == 0 {
            let days = minutes / 1440
            return days == 1 ? "1 day" : "\(days) days"
        }
        if minutes >= 60, minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}

/// Wire-date parsing + display. Held as an instance so the formatters are
/// built once per sync rather than once per deadline.
struct ReminderWireClock {
    private let fractional: ISO8601DateFormatter
    private let plain: ISO8601DateFormatter
    private let displayFormatter: DateFormatter

    init() {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        fractional = f
        let p = ISO8601DateFormatter()
        p.formatOptions = [.withInternetDateTime]
        plain = p
        let d = DateFormatter()
        d.dateStyle = .medium
        d.timeStyle = .short
        displayFormatter = d
    }

    /// The server emits `Date.toISOString()` — always UTC, always with
    /// milliseconds — but a plain ISO string is accepted too rather than
    /// discarding a deadline over a formatting detail.
    func date(from iso: String) -> Date? {
        fractional.date(from: iso) ?? plain.date(from: iso)
    }

    /// Rendered in the DEVICE's timezone. A cutoff shown in UTC to a driver in
    /// Laredo is a wrong reminder with a correct timestamp.
    func display(_ date: Date) -> String {
        displayFormatter.string(from: date)
    }
}

// ───────────────────────────────────────────────────────────────────────────
// MARK: - The service
// ───────────────────────────────────────────────────────────────────────────

@MainActor
final class ReminderSyncService: ObservableObject {

    static let shared = ReminderSyncService()

    /// What the last sync actually did. Surfaces are free to show this; it is
    /// deliberately specific so "reminders are on" can never be shown over a
    /// sync that failed.
    enum Outcome: Equatable {
        case never
        case notAuthorized
        case signedOut
        case applied(scheduled: Int, cancelled: Int, deferred: Int)
        /// The response arrived but some sources were degraded — those sources
        /// are not cancellable, so their reminders were left untouched.
        case appliedDegraded(scheduled: Int, cancelled: Int, degraded: [String])
        /// Request failed. NOTHING was cancelled.
        case failed(String)
    }

    @Published private(set) var lastOutcome: Outcome = .never
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var lastServerAsOf: Date?
    @Published private(set) var pendingReminderCount: Int = 0
    @Published private(set) var deferredReminderCount: Int = 0

    /// How far ahead to ask. 30 days matches the longest rung of the server's
    /// credential ladder (43,200 minutes), so no rung is asked for that the
    /// horizon cannot contain.
    var horizonDays: Int = 30

    /// Keep recently-passed deadlines in the response for a week. They are not
    /// schedulable, but their presence in `deadlines` is what stops the rule
    /// from pulling an already-delivered "your CDL expires tomorrow" out of
    /// Notification Center the day after it expired.
    var overdueLookbackHours: Int = 168

    /// iOS holds 64 pending local notifications per app and silently discards
    /// the overflow. Leave headroom for snoozes and the rest of the app.
    var scheduleBudget: Int = 48

    /// Slow tick while the app is running. Deadlines move on the scale of
    /// hours, not seconds.
    var pollInterval: TimeInterval = 30 * 60

    /// Floor between two syncs unless `force` is passed.
    var minimumInterval: TimeInterval = 5 * 60

    /// When the last ATTEMPT started — success or not. The throttle keys on
    /// this rather than on `lastSyncAt` so a server that is down cannot be
    /// hammered once per foreground.
    private var lastAttemptAt: Date?

    private var isActive = false
    private var isSyncing = false
    private var pollTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private init() {}

    // MARK: Lifecycle

    /// Called when the session reaches `.signedIn`. Idempotent.
    func start() {
        guard !isActive else { return }
        isActive = true
        installForegroundObserver()
        Task { await sync(trigger: "signin", force: true) }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                // The Task inherits this @MainActor context, so reading the
                // interval off `self` here needs no hop.
                let interval = self?.pollInterval ?? 1800
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { return }
                await self?.sync(trigger: "poll")
            }
        }
    }

    /// Called on sign-out.
    ///
    /// This does NOT cancel scheduled reminders. Signing out is not proof that
    /// a CDL stopped expiring, and the cancellation rule has exactly one
    /// trigger — a successful response that omits the deadline from a
    /// cancellable source. Reminders already scheduled stay; the next signed-in
    /// sync reconciles them.
    func stop() {
        isActive = false
        pollTask?.cancel()
        pollTask = nil
        lastOutcome = .signedOut
    }

    private func installForegroundObserver() {
        #if canImport(UIKit)
        guard observers.isEmpty else { return }
        let token = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                await ReminderSyncService.shared.sync(trigger: "foreground")
            }
        }
        observers.append(token)
        #endif
    }

    /// A silent/visible push arrived. The server pushing anything is a decent
    /// hint that something moved, so reconcile — throttled, and a no-op when
    /// signed out.
    func handleRemotePush() {
        guard isActive else { return }
        Task { await sync(trigger: "push") }
    }

    // MARK: Sync

    func sync(trigger: String, force: Bool = false) async {
        guard isActive else { return }
        guard !isSyncing else { return }
        if !force, let last = lastAttemptAt, Date().timeIntervalSince(last) < minimumInterval {
            return
        }

        // Provisional authorization delivers to Notification Center only, and
        // ReminderScheduler refuses to schedule under it. Say so rather than
        // burning a request and reporting success over nothing.
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            lastOutcome = .notAuthorized
            return
        }

        isSyncing = true
        lastAttemptAt = Date()
        defer { isSyncing = false }

        let response: UpcomingDeadlinesResponse
        do {
            response = try await EusoTripAPI.shared.upcomingReminderDeadlines(
                horizonDays: horizonDays,
                overdueLookbackHours: overdueLookbackHours
            )
        } catch {
            // The whole point of the contract: a failed read changes nothing.
            lastOutcome = .failed(error.localizedDescription)
            print("[ReminderSync] \(trigger) fetch failed — nothing cancelled: \(error.localizedDescription)")
            return
        }

        let ledger = await currentLedger()
        let plan = ReminderSyncPlan.make(
            response: response, ledger: ledger, now: Date(), budget: scheduleBudget
        )
        apply(plan)

        lastSyncAt = Date()
        lastServerAsOf = response.asOf.flatMap { ReminderWireClock().date(from: $0) }
        pendingReminderCount = plan.scheduled.count
        deferredReminderCount = plan.deferred

        let degraded = response.degradedSources ?? []
        lastOutcome = degraded.isEmpty
            ? .applied(
                scheduled: plan.scheduled.count,
                cancelled: plan.cancelled.count,
                deferred: plan.deferred)
            : .appliedDegraded(
                scheduled: plan.scheduled.count,
                cancelled: plan.cancelled.count,
                degraded: degraded)

        print("""
        [ReminderSync] \(trigger): scheduled \(plan.scheduled.count), \
        cancelled \(plan.cancelled.count), deferred \(plan.deferred), \
        past-due \(plan.pastDue), leads-passed \(plan.leadsAlreadyPassed), \
        unparseable \(plan.unparseableDueAt), \
        cancellable-sources \(response.cancellableSources.count), \
        truncated \(response.responseTruncated), degraded \(degraded.count)
        """)
    }

    /// Every reminder this service currently owns, read back from the
    /// notification centre — pending AND delivered.
    private func currentLedger() async -> [ReminderLedgerEntry] {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        let delivered = await center.deliveredNotifications().map(\.request.identifier)
        var seen = Set<String>()
        var entries: [ReminderLedgerEntry] = []
        for identifier in pending + delivered {
            guard let entry = ReminderDeadlineIdentity.parse(identifier: identifier) else { continue }
            let key = entry.subject
            if seen.insert(key).inserted { entries.append(entry) }
        }
        return entries
    }

    private func apply(_ plan: ReminderSyncPlan) {
        for entry in plan.cancelled {
            ReminderScheduler.cancel(kind: ReminderDeadlineIdentity.kind, subject: entry.subject)
        }
        for item in plan.scheduled {
            var info: [String: Any] = [
                "euso.reminder.source": item.source,
                "euso.reminder.deadlineId": item.deadlineId,
                "euso.reminder.leadMinutes": item.leadMinutes,
                "euso.reminder.dueAt": ISO8601DateFormatter().string(from: item.dueAt),
                "euso.reminder.category": item.category,
                "euso.reminder.criticality": item.criticality,
            ]
            if let ref = item.ref { info["euso.reminder.ref"] = ref }
            if let proof = item.proof { info["euso.reminder.proof"] = proof }
            ReminderScheduler.schedule(
                kind: ReminderDeadlineIdentity.kind,
                subject: item.subject,
                title: item.title,
                body: item.body,
                at: item.fireAt,
                category: item.pushCategory,
                userInfo: info
            )
        }
    }
}
