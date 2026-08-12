//
//  verify-reminder-sync-plan.swift
//  EusoTrip — executable regression fence for the reminder cancellation rule.
//
//  Run:
//    swiftc -O -o /tmp/verify-reminder-sync-plan \
//      "EusoTrip/Services/ReminderScheduler.swift" \
//      "EusoTrip/Services/ReminderSyncService.swift" \
//      "scripts/verify-reminder-sync-plan.swift" && /tmp/verify-reminder-sync-plan
//
//  This compiles and calls the REAL ReminderSyncPlan / ReminderDeadlineIdentity
//  out of EusoTrip/Services/ReminderSyncService.swift. The only thing stubbed
//  is EusoTripAPI — the network boundary — because the app's real client is a
//  27k-line file bound to the app module. Nothing about the subject under test
//  is faked: the planner code that runs here is the code that ships.
//
//  What it pins down is the one rule that, if it drifts, silently deletes a
//  driver's compliance reminders on a bad network day:
//
//     cancel IFF source ∈ cancellableSources AND id ∉ deadlines
//

import Foundation

// ── Network boundary stub (NOT the subject under test) ────────────────────
@MainActor
final class EusoTripAPI {
    static let shared = EusoTripAPI()
    func query<Output: Decodable, Input: Encodable>(_ path: String, input: Input) async throws -> Output {
        throw NSError(domain: "verify", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "no network in the harness"])
    }
}

// ── Harness ───────────────────────────────────────────────────────────────
var failures: [String] = []
var checks = 0

func expect(_ condition: Bool, _ what: String) {
    checks += 1
    if !condition { failures.append(what) }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ what: String) {
    checks += 1
    if a != b { failures.append("\(what) — got \(a), expected \(b)") }
}

let iso: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

let now = Date(timeIntervalSince1970: 1_800_000_000)   // fixed clock

func deadline(
    id: String,
    source: String,
    dueIn minutes: Double,
    leads: [Int],
    schedulable: Bool? = nil,
    category: String = "credential",
    criticality: String = "compliance",
    title: String = "CDL expires",
    ref: String? = nil,
    detail: String? = nil
) -> ReminderDeadlineDTO {
    let due = now.addingTimeInterval(minutes * 60)
    let json: [String: Any] = [
        "id": id,
        "source": source,
        "category": category,
        "criticality": criticality,
        "title": title,
        "detail": detail as Any,
        "dueAt": iso.string(from: due),
        "schedulable": schedulable ?? (due > now),
        "minutesUntilDue": Int(minutes),
        "leadMinutes": leads,
        "proof": [
            "table": "drivers", "column": "licenseExpiry",
            "dbTable": "drivers", "dbColumn": "license_expiry",
            "rowId": "9001", "derived": false, "derivation": NSNull(),
        ],
        "ref": ref as Any,
        "observedAt": iso.string(from: now),
    ]
    let data = try! JSONSerialization.data(withJSONObject: json)
    return try! JSONDecoder().decode(ReminderDeadlineDTO.self, from: data)
}

func response(
    ok: Bool = true,
    deadlines: [ReminderDeadlineDTO],
    cancellableSources: [String],
    degraded: [String] = [],
    truncated: Bool = false
) -> UpcomingDeadlinesResponse {
    let json: [String: Any] = [
        "ok": ok,
        "reason": NSNull(),
        "asOf": iso.string(from: now),
        "horizonDays": 30,
        "overdueLookbackHours": 168,
        "modes": ["TRUCK"],
        "deadlines": [],
        "sources": [],
        "cancellableSources": cancellableSources,
        "degradedSources": degraded,
        "responseTruncated": truncated,
    ]
    let data = try! JSONSerialization.data(withJSONObject: json)
    var decoded = try! JSONDecoder().decode(UpcomingDeadlinesResponse.self, from: data)
    // `deadlines` is re-attached through the decoder too, so the DTOs under
    // test are always decoder output, never hand-built structs.
    let withDeadlines: [String: Any] = [
        "ok": ok, "reason": NSNull(), "asOf": iso.string(from: now),
        "horizonDays": 30, "overdueLookbackHours": 168, "modes": ["TRUCK"],
        "deadlines": deadlines.map { d -> [String: Any] in
            var o: [String: Any] = [
                "id": d.id, "source": d.source, "category": d.category as Any,
                "criticality": d.criticality as Any, "title": d.title,
                "dueAt": d.dueAt, "schedulable": d.schedulable,
                "leadMinutes": d.leadMinutes as Any,
            ]
            if let detail = d.detail { o["detail"] = detail }
            if let ref = d.ref { o["ref"] = ref }
            if let p = d.proof {
                o["proof"] = [
                    "table": p.table as Any, "column": p.column as Any,
                    "dbTable": p.dbTable as Any, "dbColumn": p.dbColumn as Any,
                    "rowId": p.rowId as Any, "derived": p.derived as Any,
                ]
            }
            return o
        },
        "sources": [], "cancellableSources": cancellableSources,
        "degradedSources": degraded, "responseTruncated": truncated,
    ]
    let d2 = try! JSONSerialization.data(withJSONObject: withDeadlines)
    decoded = try! JSONDecoder().decode(UpcomingDeadlinesResponse.self, from: d2)
    return decoded
}

func ledgerEntry(_ source: String, _ id: String, _ lead: Int) -> ReminderLedgerEntry {
    ReminderLedgerEntry(source: source, deadlineId: id, leadMinutes: lead)
}

@main
struct VerifyReminderSyncPlan {
static func main() {
    // ── 1. Identity codec round-trips, including the '#' in a server id ───────
    do {
        let id = "credential_cdl#9001#1800000000"
        let ident = ReminderDeadlineIdentity.identifier(
            source: "credential_cdl", deadlineId: id, leadMinutes: 1440)
        expectEqual(ident, "euso.reminder.deadline.credential_cdl|credential_cdl#9001#1800000000|1440",
                    "identifier format")
        let parsed = ReminderDeadlineIdentity.parse(identifier: ident)
        expectEqual(parsed, ledgerEntry("credential_cdl", id, 1440), "identifier round-trip")
        // snooze copies carry the same identity
        expectEqual(ReminderDeadlineIdentity.parse(identifier: "snooze:" + ident),
                    ledgerEntry("credential_cdl", id, 1440), "snooze identifier round-trip")
        // foreign identifiers are never ours
        expect(ReminderDeadlineIdentity.parse(identifier: "euso.reminder.pretrip.load-42") == nil,
               "foreign identifier must not parse")
        expect(ReminderDeadlineIdentity.parse(identifier: "totally.unrelated") == nil,
               "unrelated identifier must not parse")
        expect(ReminderDeadlineIdentity.parse(identifier: "euso.reminder.deadline.badly|formed") == nil,
               "malformed identifier must not parse")
    }

    // ── 2. THE RULE ──────────────────────────────────────────────────────────
    do {
        let live = deadline(id: "credential_cdl#1#100", source: "credential_cdl",
                            dueIn: 60 * 24 * 20, leads: [1440])
        let r = response(
            deadlines: [live],
            cancellableSources: ["credential_cdl", "document_expiry"])
        let ledger = [
            ledgerEntry("credential_cdl", "credential_cdl#1#100", 1440), // live → keep
            ledgerEntry("credential_cdl", "credential_cdl#2#200", 1440), // gone, cancellable → CANCEL
            ledgerEntry("document_expiry", "document_expiry#7#300", 10080), // gone, cancellable → CANCEL
            ledgerEntry("vessel_vgm_cutoff", "vessel_vgm_cutoff#5#400", 240), // gone, NOT cancellable → keep
            ledgerEntry("bid_expiry", "bid_expiry#9#500", 30), // gone, NOT cancellable → keep
        ]
        let plan = ReminderSyncPlan.make(response: r, ledger: ledger, now: now, budget: 48)
        expectEqual(Set(plan.cancelled.map(\.deadlineId)),
                    Set(["credential_cdl#2#200", "document_expiry#7#300"]),
                    "cancels exactly the absent ids of cancellable sources")
    }

    // ── 3. A failed/degraded read cancels NOTHING ────────────────────────────
    do {
        // Server-side failure shape: ok:false, no deadlines, nothing cancellable.
        let r = response(ok: false, deadlines: [], cancellableSources: [],
                         degraded: ["credential_cdl", "document_expiry"])
        let ledger = [
            ledgerEntry("credential_cdl", "credential_cdl#1#100", 1440),
            ledgerEntry("document_expiry", "document_expiry#7#300", 10080),
        ]
        let plan = ReminderSyncPlan.make(response: r, ledger: ledger, now: now, budget: 48)
        expectEqual(plan.cancelled.count, 0, "degraded read must cancel nothing")
        expectEqual(plan.scheduled.count, 0, "degraded read schedules nothing")
    }

    // ── 4. A truncated response cancels NOTHING even if sources are listed ───
    do {
        let r = response(deadlines: [], cancellableSources: ["credential_cdl"], truncated: true)
        let ledger = [ledgerEntry("credential_cdl", "credential_cdl#1#100", 1440)]
        let plan = ReminderSyncPlan.make(response: r, ledger: ledger, now: now, budget: 48)
        expectEqual(plan.cancelled.count, 0, "truncated response must cancel nothing")
    }

    // ── 5. Scheduling: one per lead, past leads skipped, past-due not scheduled ──
    do {
        // Due in 10 days. Ladder 30d / 14d / 7d / 1d → the 30d and 14d rungs are
        // already behind us, the 7d and 1d rungs are real.
        let d = deadline(id: "credential_cdl#1#100", source: "credential_cdl",
                         dueIn: 60 * 24 * 10, leads: [43200, 20160, 10080, 1440])
        // An overdue one the server returned for display only.
        let past = deadline(id: "credential_medical_card#2#50", source: "credential_medical_card",
                            dueIn: -60 * 24, leads: [1440], schedulable: false)
        let r = response(deadlines: [d, past],
                         cancellableSources: ["credential_cdl", "credential_medical_card"])
        let plan = ReminderSyncPlan.make(response: r, ledger: [], now: now, budget: 48)
        expectEqual(plan.scheduled.count, 2, "schedules only the leads still ahead")
        expectEqual(plan.leadsAlreadyPassed, 2, "counts the leads already behind us")
        expectEqual(plan.pastDue, 1, "counts the unschedulable deadline")
        expectEqual(Set(plan.scheduled.map(\.leadMinutes)), Set([10080, 1440]), "correct rungs")
        // Fire times are dueAt minus the lead, to the second.
        let due = now.addingTimeInterval(60 * 60 * 24 * 10)
        for item in plan.scheduled {
            expect(abs(item.fireAt.timeIntervalSince(due.addingTimeInterval(-Double(item.leadMinutes) * 60))) < 1,
                   "fire time is dueAt - lead for rung \(item.leadMinutes)")
        }
        // Soonest first.
        expect(plan.scheduled[0].fireAt < plan.scheduled[1].fireAt, "ordered soonest first")
        // A credential expiry is a snoozable future obligation → the category
        // PushService actually registers.
        expectEqual(plan.scheduled[0].pushCategory, "compliance_expiring",
                    "credential reminders use the registered snoozable category")
    }

    // ── 6. Determinism: a refetch replaces, it never stacks ──────────────────
    do {
        let d = deadline(id: "vessel_vgm_cutoff#77#900", source: "vessel_vgm_cutoff",
                         dueIn: 60 * 48, leads: [1440, 240, 60],
                         category: "cutoff", criticality: "compliance",
                         title: "VGM cutoff (SOLAS VI/2)", ref: "BKG-88213")
        let r = response(deadlines: [d], cancellableSources: ["vessel_vgm_cutoff"])
        let a = ReminderSyncPlan.make(response: r, ledger: [], now: now, budget: 48)
        let b = ReminderSyncPlan.make(response: r, ledger: [], now: now, budget: 48)
        expectEqual(a.scheduled.map(\.subject), b.scheduled.map(\.subject), "subjects are deterministic")
        expectEqual(Set(a.scheduled.map(\.subject)).count, a.scheduled.count, "no duplicate subjects")
        // A moved deadline mints a new id → the old one is cancelled, the new
        // one scheduled. That is the replace path the server designed for.
        let moved = deadline(id: "vessel_vgm_cutoff#77#1200", source: "vessel_vgm_cutoff",
                             dueIn: 60 * 72, leads: [1440],
                             category: "cutoff", criticality: "compliance")
        let r2 = response(deadlines: [moved], cancellableSources: ["vessel_vgm_cutoff"])
        let ledger = a.scheduled.map {
            ledgerEntry($0.source, $0.deadlineId, $0.leadMinutes)
        }
        let plan2 = ReminderSyncPlan.make(response: r2, ledger: ledger, now: now, budget: 48)
        expectEqual(plan2.cancelled.count, 3, "a moved deadline cancels all rungs of the old id")
        expectEqual(plan2.scheduled.count, 1, "and schedules the new one")
    }

    // ── 7. Budget: soonest survive, the rest are reported not pretended ──────
    do {
        var many: [ReminderDeadlineDTO] = []
        for i in 0..<40 {
            many.append(deadline(id: "bid_expiry#\(i)#\(i)", source: "bid_expiry",
                                 dueIn: Double(120 + i * 10), leads: [120, 30],
                                 category: "offer", criticality: "money",
                                 title: "Bid expires"))
        }
        let r = response(deadlines: many, cancellableSources: ["bid_expiry"])
        let plan = ReminderSyncPlan.make(response: r, ledger: [], now: now, budget: 10)
        expectEqual(plan.scheduled.count, 10, "budget is respected")
        // 40 deadlines x 2 rungs = 80 candidates, minus the one rung whose
        // fire time lands exactly on `now` (lead 120 for the deadline due in
        // 120 minutes) — a lead that is not strictly in the future is not
        // scheduled. 79 candidates, 10 kept, 69 deferred.
        expectEqual(plan.leadsAlreadyPassed, 1, "a lead landing exactly on now is not scheduled")
        expectEqual(plan.deferred, 69, "overflow is reported")
        let fires = plan.scheduled.map(\.fireAt)
        expectEqual(fires, fires.sorted(), "kept candidates are the soonest, in order")
    }

    // ── 8. Body copy restates the deadline, never invents one ────────────────
    do {
        let d = deadline(id: "container_last_free_day#3#1", source: "container_last_free_day",
                         dueIn: 60 * 24 * 3, leads: [1440],
                         category: "free_time", criticality: "money",
                         title: "Container last free day (demurrage starts)",
                         ref: "MSCU1234567", detail: "Carrier-supplied.")
        let r = response(deadlines: [d], cancellableSources: ["container_last_free_day"])
        let plan = ReminderSyncPlan.make(response: r, ledger: [], now: now, budget: 48)
        expectEqual(plan.scheduled.count, 1, "one rung scheduled")
        let body = plan.scheduled[0].body
        expect(body.hasPrefix("In 1 day · Due "), "body leads with the lead phrase: \(body)")
        expect(body.contains("MSCU1234567"), "body carries the ref: \(body)")
        expect(body.contains("Carrier-supplied."), "body carries the server detail: \(body)")
        expectEqual(plan.scheduled[0].title, "Container last free day (demurrage starts)",
                    "title is the server's, unaltered")
        expectEqual(plan.scheduled[0].proof, "drivers.license_expiry#9001", "proof is carried")
        expect(plan.scheduled[0].pushCategory == nil,
               "a category with no registered UNNotificationCategory gets none")
    }

    // ── 9. Lead phrasing ─────────────────────────────────────────────────────
    do {
        expectEqual(ReminderSyncPlan.leadPhrase(minutes: 43200), "30 days", "30d phrase")
        expectEqual(ReminderSyncPlan.leadPhrase(minutes: 1440), "1 day", "1d phrase")
        expectEqual(ReminderSyncPlan.leadPhrase(minutes: 240), "4 hours", "4h phrase")
        expectEqual(ReminderSyncPlan.leadPhrase(minutes: 60), "1 hour", "1h phrase")
        expectEqual(ReminderSyncPlan.leadPhrase(minutes: 15), "15 minutes", "15m phrase")
    }

    // ── 10. An unknown source or category cannot break the response ──────────
    do {
        let json: [String: Any] = [
            "ok": true, "reason": NSNull(), "asOf": iso.string(from: now),
            "horizonDays": 30, "overdueLookbackHours": 0, "modes": ["TRUCK"],
            "deadlines": [[
                "id": "brand_new_source#1#2", "source": "brand_new_source",
                "category": "a_category_ios_has_never_heard_of",
                "criticality": "a_new_criticality",
                "title": "Something new expires", "detail": NSNull(),
                "dueAt": iso.string(from: now.addingTimeInterval(3600 * 5)),
                "schedulable": true, "minutesUntilDue": 300,
                "leadMinutes": [60], "proof": NSNull(), "ref": NSNull(),
                "observedAt": iso.string(from: now),
            ]],
            "sources": [], "cancellableSources": ["brand_new_source"],
            "degradedSources": [], "responseTruncated": false,
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        let decoded = try? JSONDecoder().decode(UpcomingDeadlinesResponse.self, from: data)
        expect(decoded != nil, "an unknown source/category must still decode")
        if let decoded {
            let plan = ReminderSyncPlan.make(response: decoded, ledger: [], now: now, budget: 48)
            expectEqual(plan.scheduled.count, 1, "and still schedules")
        }
    }

    // ── report ───────────────────────────────────────────────────────────────
    if failures.isEmpty {
        print("PASS — \(checks) checks")
        exit(0)
    } else {
        print("FAIL — \(failures.count) of \(checks) checks failed:")
        for f in failures { print("  · \(f)") }
        exit(1)
    }

}
}
