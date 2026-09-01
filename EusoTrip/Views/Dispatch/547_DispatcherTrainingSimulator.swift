//
//  547_DispatcherTrainingSimulator.swift
//  EusoTrip 2027 · App target · Views/Dispatch · LIVE DATA LAYER
//
//  CATALOG IDENTITY: 547 Dispatcher Training Simulator
//  (04 Dispatcher · DISPATCHER vantage · Aurora · RM)
//
//  MIRRORS (design of record, 1:1):
//    04 Dispatcher/Light-SVG/547 Dispatcher Training Simulator.svg  (+ Dark)
//
//  COMPOSITION (unchanged from the SVG): DETAIL TopBar -> RADIAL CERTIFICATION
//  DIAL hero (the only radial gauge in the Dispatcher band) + pass bar with a
//  threshold tick + a SANDBOX-ISOLATION warning strip -> SCORED-AXIS BULLET
//  LADDER (each axis a track with a target tick and a scored fill,
//  right-anchored score) -> SCENARIO DECK of runnable drills -> CTA pair.
//  Deliberately unlike 539 Carrier Scorecard (bubble quadrants), 541 Margin
//  Bridge (waterfall), 542 Credentials Watchtower (expiry runway) and 545
//  Maintenance Due (depletion roster).
//  PURPOSE: a scored place to practise a hazmat reassignment or an HOS breach
//  before it costs a real load, and the certification record that lets a
//  supervisor release the dispatcher from probation.
//
//  ── DESIGN-SYSTEM PORT 2026-08-26 ────────────────────────────────────────
//  Colors moved from raw/system values to Theme.Palette + Brand + the house
//  LinearGradient extensions; spacing/radii moved to Space.*/Radius.* where a
//  token matches the SVG value. Chrome now routes through the house
//  Shell + BottomNav(DispatchNavRoute) exactly as Dpch730 does — the local
//  hand-rolled nav bar and orb are gone, so the dock can no longer drift from
//  the rest of the Dispatcher band. THE DATA LAYER IS UNTOUCHED: every
//  endpoint string, decoder shape, error branch and disabled-control reason
//  below is byte-for-byte the endpoint-verified wiring from the staged file.
//
//  WIRED READS (line numbers verified on disk 2026-08-17; none stale):
//    trainingLMS.getLMSDashboard    EXISTS trainingLMS.ts:600 · no input
//        -> the radial dial (`averageScore`) and the course counter.
//           TRAP AVOIDED: `totalTimeSpent` is POLYMORPHIC — the success path
//           returns it from `COALESCE(SUM(...))`, which mysql2 hands back as a
//           STRING, while both fallback paths return the number 0. Decoding it
//           as Int would fail in production, so this screen does not read it.
//    trainingLMS.listCourses        EXISTS trainingLMS.ts:96
//        -> the SCENARIO DECK rows. Returns {courses, total}, NOT a bare array.
//           TRAP AVOIDED: `averageRating` and `completionRate` are DECIMAL
//           columns and arrive as STRINGS, not numbers — decoded as String?.
//    trainingLMS.getCourseDetail    EXISTS trainingLMS.ts:157
//        -> the enrolment row (for `enrollment.id`) and the module list.
//           Returns NULL on no-db / not-found / catch — decoded as Optional.
//    trainingLMS.getModuleProgress  EXISTS trainingLMS.ts:524
//        -> the SCORED-AXIS LADDER and the last-run line.
//           TRAP AVOIDED: the row is NOT flattened. Each element is
//           {progress:{…}, moduleTitle, moduleOrder} — `quizScore` lives inside
//           the nested `progress` object, so a flat decoder silently gets
//           nothing. Modelled with the nesting intact.
//    trainingLMS.getMyCertificates  EXISTS trainingLMS.ts:549 · no input
//        -> the "Transcript" action. Each element nests the row under
//           `certificate` (same nesting trap as above).
//    training.getComplianceGap      EXISTS training.ts:419
//        -> the release-bar gap line (`compliancePercent`, `gaps`).
//
//  WIRED WRITE:
//    trainingLMS.enrollInCourse     EXISTS trainingLMS.ts:215 · mutation
//        -> the primary CTA. Real enrolment against the real course id.
//           TRAP NOTED: its `enrollmentId` is polymorphic (an int column on the
//           already-enrolled path, an untyped `insertId` on the new path), so
//           this screen does not decode that field; it re-reads the enrolment
//           from getCourseDetail instead.
//
//  ── HONEST RE-SOURCING (composition preserved, provenance corrected) ──────
//  The four literal "simulator axes" (Decision speed / HOS compliance / Margin
//  protection / Comms clarity) drawn in the SVG had NO server source and never
//  did — the verb that would produce them is the named gap below. They are
//  replaced by the axes the LMS actually scores: one track per module,
//  `quizScore` as the fill, the course's real `passingScore` as the target
//  tick. Same ladder, same geometry, real numbers.
//  Likewise the deck's trailing metric was "best 61" — a per-course best score
//  that `listCourses` does not return. It now prints the course's REAL passing
//  threshold, which the row does return. A figure the server does not produce
//  is not printed at all.
//
//  ── NAMED GAP · NOT FAKED · STATED IN THE SANDBOX STRIP ON SCREEN ─────────
//    STUB · dispatchSim.runScenario DOES NOT EXIST — re-confirmed absent
//      2026-08-17: a repo-wide search of frontend/server for `runScenario` /
//      `dispatchSim` returns NO match. The LMS scores quizzes, not live-board
//      simulations. Proposed shape, filed as a counter-party row:
//        runScenario({ scenarioId: string, seed: number,
//                      actions: Array<{ t: number, verb: string, payload: unknown }> })
//          -> { axisScores: Record<string, number>, transcript: Array<{t, event}> }
//      It MUST write to a sandbox schema and MUST NOT touch loads/dispatch tables.
//      The SANDBOX ISOLATION strip — an element the composition already has —
//      carries this limit in words, on screen, every time the screen renders.
//      The primary CTA is NOT a dead tap: it performs the real enrolment the
//      platform can actually do today, and its label names that.
//
//  ── CITED BUT DELIBERATELY NOT CALLED (each with its reason) ──────────────
//    trainingLMS.getQuiz            EXISTS trainingLMS.ts:384
//    trainingLMS.submitQuiz         EXISTS trainingLMS.ts:423
//      DELIBERATELY NOT WIRED. `submitQuiz` requires
//      {quizId, answers:[{questionId, answer}]} and THIS SURFACE CAPTURES NO
//      ANSWERS — there is no answer-capture UI anywhere on 547. Synthesising
//      answers to make a score appear would be exactly the client-asserted
//      score this screen's own doctrine forbids. Scoring belongs to the course
//      player; this board READS the scores that player produced. (Separately
//      flagged for the counter-party row: getQuiz's `options[].isCorrect` is
//      NOT stripped despite the "Strip correct answers" comment at
//      trainingLMS.ts:406 — the answer key leaks to any client. Filed; not
//      exploited here.)
//    esangCoach.forTraining         EXISTS esangCoach.ts:386
//      NOT WIRED, for two reasons. (1) This composition has no mentor row —
//      there is no ESang element on 547. (2) Its course facts come from
//      TRAINING_FACTS (esangCoach.ts:217-236), a hardcoded 15-key map keyed by
//      codes like "CDL-001"/"HM-001"; no LMS numeric courseId or slug matches
//      any key, so it degrades to "(unknown course)" and echoes the raw id
//      back. The release-bar line is computed from training.getComplianceGap
//      instead, which is real.
//    training.dispatchAssignCourse  EXISTS training.ts:520
//      Supervisor-side verb. Correctly NOT exposed on this screen.
//
//  SANDBOX ISOLATION IS A SAFETY PROPERTY, NOT A LABEL: every verb reachable
//    from this screen is a read against the LMS, or `enrollInCourse`, which
//    writes only to userCourseEnrollments. NO load, driver, wallet or dispatch
//    table is touched by any action on this surface. That statement is
//    verifiable against the seven call sites below rather than asserted.
//  REALTIME: a passing run emits WS_EVENTS.COMPLIANCE_TRAINING_ASSIGNED
//    shared/websocket-events.ts:174 on WS_CHANNELS.DISPATCH(companyId)
//    shared/websocket-events.ts:577. CHAIN: PARTIAL — iOS has no
//    COMPLIANCE_TRAINING_ASSIGNED case (S3 family). Counter-party row filed.
//  RBAC: protectedProcedure (self scope).
//  OFFLINE POLICY: READ_CACHED(300s) for the course catalog and certificates;
//    enrollment is QUEUE(dispatch); no money movement on this surface.
//  transportMode=truck; country US (FMCSA 11h/14h ELD, 49 CFR hazmat) — the
//    ruleset is course content, so CA and MX drills reuse this one screen.
//  NAV (REAL · house chrome): Shell + BottomNav(leading/trailing from
//    DispatchNavRoute, current: .board, orbState: .idle) — Home · Board
//    (current) · [orb] · Comms · Me, routed by the dispatch nav handler.
//  Persona Aurora Freight Lines · Renée Marquette (RM); shipper-of-record
//  Eusorone Technologies (Diego Usoro · DU).
//
//  HONEST STATUS: 6 reads + 1 write live · 1 named gap (dispatchSim.runScenario)
//  stated on screen in the sandbox strip · 3 verified procedures deliberately
//  unwired with reasons · 2 decoder-nesting traps and 2 numeric-as-string traps
//  caught. No literal row arrays remain. No stubs, no placeholder literals.
//  No retired names. No emoji icons. Exactly one ✦ eyebrow, exactly one
//  iridescent hairline.
//  — Mike "Diego" Usoro / Eusorone Technologies, Inc. · 2026-08-26 EDT.
//

import SwiftUI

// MARK: - WCAG text pair for small type on a tinted wash
//
// The Palette exposes the tinted WASH backgrounds (tintSuccess / tintWarning /
// tintDanger / tintInfo / tintNeutral) but no matching TEXT token, and the
// Brand.* saturations fail small-text contrast when they sit on those washes on
// a light surface — so these darker, contrast-tested variants stay. They are the
// exact values the SVG of record paints, declared once here instead of
// per-view. Do not swap them for Brand.*: that drops small-text contrast.
private let dangerText_547  = Color(red: 0.824, green: 0.204, blue: 0.165) // #D2342A
private let warnText_547    = Color(red: 0.698, green: 0.451, blue: 0.0)   // #B27300
private let successText_547 = Color(red: 0.0,   green: 0.588, blue: 0.420) // #00966B
private let infoText_547    = Color(red: 0.082, green: 0.396, blue: 0.753) // #1565C0
/// Fifth member of the same contrast-tested family — the SVG paints the escort
/// difficulty label #7B1FA2, and the Palette has no escort wash or escort text
/// token either. Declared through the house `Color(hex:)` initializer.
private let escortText_547  = Color(hex: 0x7B1FA2)                         // #7B1FA2

// MARK: - Wire decoders (shapes copied from the server's own return statements)

/// Explicit null-tolerant box. Several LMS procedures return `null` outright
/// (getCourseDetail on three separate paths), and relying on `Optional` as the
/// generic `Output` of a tRPC envelope is fragile — a JSON `null` in that
/// position can surface as `valueNotFound` rather than `.none`. This decodes the
/// null case openly instead of hoping the generic path handles it.
private struct Nullable_547<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        value = c.decodeNil() ? nil : try c.decode(T.self)
    }
}

/// trainingLMS.getLMSDashboard — trainingLMS.ts:600.
/// `totalTimeSpent` deliberately omitted: string on the success path, 0 on the
/// fallback paths (see header).
private struct LMSDashboard_547: Decodable {
    let totalCourses: Int?
    let enrolledCourses: Int?
    let completedCourses: Int?
    let inProgressCourses: Int?
    let totalCertificates: Int?
    let averageScore: Int?
}

/// trainingLMS.listCourses — trainingLMS.ts:96. Envelope, not a bare array.
private struct CourseList_547: Decodable {
    let courses: [Course_547]
    let total: Int?
}

/// One `trainingCourses` row. averageRating/completionRate are DECIMAL columns
/// and therefore arrive as STRINGS.
private struct Course_547: Decodable {
    let id: Int
    let slug: String?
    let title: String?
    let category: String?
    let difficultyLevel: String?      // beginner | intermediate | advanced
    let estimatedDurationMinutes: Int?
    let moduleCount: Int?
    let isMandatory: Bool?
    let hazmatSpecific: Bool?
    let status: String?
    let passingScore: Int?
    let enrollmentCount: Int?
    let averageRating: String?
    let completionRate: String?
}

/// trainingLMS.getCourseDetail — trainingLMS.ts:157. Returns null on three paths.
private struct CourseDetail_547: Decodable {
    let id: Int
    let title: String?
    let passingScore: Int?
    let modules: [CourseModule_547]?
    let enrollment: Enrollment_547?
}

private struct CourseModule_547: Decodable {
    let id: Int
    let title: String?
    let orderIndex: Int?
}

private struct Enrollment_547: Decodable {
    let id: Int
    let status: String?
    let progressPercentage: Int?
}

/// trainingLMS.getModuleProgress — trainingLMS.ts:524.
/// The row is NESTED under `progress` — do not flatten.
private struct ModuleProgress_547: Decodable {
    let progress: ProgressRow_547?
    let moduleTitle: String?
    let moduleOrder: Int?
}

private struct ProgressRow_547: Decodable {
    let status: String?               // not_started | in_progress | completed
    let quizScore: Int?
    let quizAttempts: Int?
    let timeSpentMinutes: Int?
    let completedAt: String?
}

/// training.getComplianceGap — training.ts:419.
private struct ComplianceGap_547: Decodable {
    let gaps: [Gap_547]
    let completedCount: Int?
    let totalRequired: Int?
    let compliancePercent: Int?
}

private struct Gap_547: Decodable {
    let requirementId: String?
    let title: String?
    let regulation: String?
    let severity: String?             // mandatory | conditional | recommended
    let status: String?               // compliant | expired | missing
}

/// trainingLMS.getMyCertificates — trainingLMS.ts:549. Row nested under `certificate`.
private struct CertificateEntry_547: Decodable {
    let certificate: CertRow_547?
    let courseTitle: String?
    let courseCategory: String?
}

private struct CertRow_547: Decodable {
    let certificateNumber: String?
    let issuedAt: String?
    let expiresAt: String?
    let status: String?               // active | expired | revoked
}

/// trainingLMS.enrollInCourse — trainingLMS.ts:215.
/// `enrollmentId` deliberately omitted: polymorphic (see header).
private struct EnrollResult_547: Decodable {
    let success: Bool?
    let alreadyEnrolled: Bool?
}

// MARK: - View models

private enum Tint547 { case danger, warn, success, info, violet, slate }

private struct ScoredAxis_547: Identifiable {
    let id = UUID()
    let name: String
    let score: String
    let scoreTint: Tint547
    let detail: String
    let fill: Double        // scored fill, 0…1
    /// The target tick, 0…1 — nil when NO server figure named the threshold.
    /// An absent threshold has no position on the track, so the tick is not
    /// drawn at all rather than parked at an invented default.
    let target: Double?
    let barTint: Tint547
}

private struct Scenario_547: Identifiable {
    let id = UUID()
    let courseId: Int
    let icon: String
    let tint: Tint547
    let title: String
    let sub: String
    let difficulty: String
    let difficultyTint: Tint547
    let best: String
}

// `private` at file scope: this view model's published properties are typed with
// the file-private row structs above, so the class must be no more accessible
// than they are. (The inherited declaration was `internal`, which is a hard
// access-control error — further evidence this file had never been compiled.)
@MainActor
private final class TrainingSimVM_547: ObservableObject {

    // NAMED GAP carried explicitly — never silently faked. Re-confirmed absent
    // from frontend/server on 2026-08-17.
    // runScenario({scenarioId, seed, actions:[{t, verb, payload}]})
    //   -> per-axis scores + transcript, replayed against a SHADOW board.
    //   Sandbox schema only; must not reach loads/dispatch tables.
    let STUB_dispatchSim_runScenario = "dispatchSim.runScenario"

    // Load-cycle state (house pattern, per 545).
    @Published var loading = true
    @Published var loadError: String?
    @Published var working = false
    @Published var actionNote: String?

    // TopBar
    @Published var eyebrow = "\u{2726} DISPATCHER · TRAINING SIM"
    @Published var caption = "SANDBOX"
    @Published var title   = "Simulator"

    // Radial certification dial — getLMSDashboard
    @Published var heroLabel   = "DISPATCH CERTIFICATION · TRAINING RECORD"
    @Published var dialValue   = "—"
    @Published var dialOutOf   = "OF 100"
    @Published var dialFrac    = 0.0
    @Published var moduleLine  = "—"
    @Published var lastRunLine = "—"

    // Release-bar gap — training.getComplianceGap
    @Published var gapLine     = "—"
    /// The state that PRODUCED gapLine, so the line's colour is derived from it
    /// rather than hardcoded: "Compliant on all N requirements" must not paint
    /// in the danger colour.
    @Published var gapTint: Tint547 = .slate
    @Published var passFrac    = 0.0
    /// ABSENT until a server figure names the passing score. Optional on
    /// purpose: a threshold nobody published has no position on the pass bar,
    /// so the tick is omitted instead of being drawn at a default.
    @Published var thresholdFrac: Double?

    // Sandbox isolation strip — a safety property, AND the named gap, in words.
    @Published var sandboxLine = "Sandbox — no live load, driver or wallet is touched"

    // Scored-axis bullet ladder — getModuleProgress (real per-module scores)
    @Published var axesLabel  = "SCORED AXES · BY MODULE"
    @Published var axesSource = "trainingLMS.ts:524"
    @Published var axes: [ScoredAxis_547] = []
    @Published var axesEmptyReason: String?

    // Scenario deck — listCourses
    @Published var deckLabel  = "SCENARIO DECK"
    @Published var deckSource = "trainingLMS.ts:96"
    @Published var scenarios: [Scenario_547] = []

    // CTA
    @Published var primaryCTA   = "Start course"
    @Published var secondaryCTA = "Transcript"

    /// The course the primary CTA will enrol in — the first deck row.
    private var primaryCourseId: Int?

    private let api = EusoTripAPI.shared

    // MARK: Load — ONE tick

    func load() async {
        loading = true
        loadError = nil

        struct Empty: Encodable {}
        struct CourseListIn: Encodable { let page: Int; let limit: Int }
        struct CourseDetailIn: Encodable { let courseId: Int }
        struct ProgressIn: Encodable { let enrollmentId: Int }
        struct GapIn: Encodable { let trailerType: String? }

        var failures: [String] = []

        // 1 · the dial
        do {
            let d: LMSDashboard_547 = try await api.queryNoInput("trainingLMS.getLMSDashboard")
            let score = d.averageScore ?? 0
            dialValue = "\(score)"
            dialFrac = min(max(Double(score) / 100.0, 0), 1)
            passFrac = dialFrac
            let done = d.completedCourses ?? 0
            let enrolled = d.enrolledCourses ?? 0
            moduleLine = enrolled == 0
                ? "No courses enrolled yet"
                : "\(done) of \(enrolled) enrolled \(enrolled == 1 ? "course" : "courses") complete"
            heroLabel = "DISPATCH CERTIFICATION · \(d.totalCertificates ?? 0) CERTIFICATE\((d.totalCertificates ?? 0) == 1 ? "" : "S") HELD"
        } catch {
            failures.append("certification record")
        }

        // 2 · the deck
        var courses: [Course_547] = []
        do {
            let list: CourseList_547 = try await api.query(
                "trainingLMS.listCourses", input: CourseListIn(page: 1, limit: 20))
            courses = list.courses
            scenarios = courses.map { c in
                let d = Self.difficulty(c.difficultyLevel)
                return Scenario_547(
                    courseId: c.id,
                    icon: Self.icon(for: c),
                    tint: Self.tint(forCategory: c.category),
                    title: c.title ?? c.slug ?? "Course \(c.id)",
                    sub: Self.subline(for: c),
                    difficulty: d.0,
                    difficultyTint: d.1,
                    // listCourses returns no per-course best score. The real
                    // figure this row carries is the passing threshold.
                    best: c.passingScore.map { "pass \($0)" } ?? "—")
            }
            deckLabel = "SCENARIO DECK · \(list.total ?? courses.count) DRILLS"
            primaryCourseId = courses.first?.id
            if let t = courses.first?.passingScore {
                thresholdFrac = min(max(Double(t) / 100.0, 0), 1)
            }
            if let t = courses.first?.title, !t.isEmpty {
                primaryCTA = "Start \(t)"
            } else {
                primaryCTA = "Start course"
            }
        } catch {
            scenarios = []
            failures.append("course deck")
        }

        // 3 · the scored-axis ladder, via the real enrolment
        var progressRows: [ModuleProgress_547] = []
        var detailPassing: Int?
        if let firstId = courses.first?.id {
            do {
                let box: Nullable_547<CourseDetail_547> = try await api.query(
                    "trainingLMS.getCourseDetail", input: CourseDetailIn(courseId: firstId))
                let detail = box.value
                detailPassing = detail?.passingScore
                if let enrollmentId = detail?.enrollment?.id {
                    progressRows = try await api.query(
                        "trainingLMS.getModuleProgress", input: ProgressIn(enrollmentId: enrollmentId))
                } else {
                    axesEmptyReason = "No enrolment on \(detail?.title ?? "this course") yet — module scores appear once you start it."
                }
            } catch {
                failures.append("module progress")
            }
        }

        // THE ONE resolved pass threshold, in the server's own units.
        // getCourseDetail's figure OVERRIDES the listCourses figure only when the
        // server actually returned one — that procedure returns null on three
        // separate paths, and on those the listCourses figure set above stands.
        // When neither exists the threshold is ABSENT: nil, never a literal.
        let passingScore: Int? = detailPassing ?? courses.first?.passingScore
        thresholdFrac = passingScore.map { min(max(Double($0) / 100.0, 0), 1) }
        let target = thresholdFrac
        axes = progressRows.compactMap { row in
            guard let p = row.progress else { return nil }
            let score = p.quizScore
            let fill = Double(score ?? 0) / 100.0
            return ScoredAxis_547(
                name: row.moduleTitle ?? "Module \(row.moduleOrder ?? 0)",
                score: score.map { "\($0)" } ?? "—",
                scoreTint: Self.tint(forScore: score, target: passingScore),
                detail: Self.detail(for: p, target: passingScore),
                fill: min(max(fill, 0), 1),
                target: target,
                barTint: Self.tint(forScore: score, target: passingScore))
        }
        if axes.isEmpty && axesEmptyReason == nil {
            axesEmptyReason = "No scored modules on this enrolment yet."
        }
        if !axes.isEmpty { axesEmptyReason = nil }

        // last-run line, from the most recently completed module
        if let last = progressRows
            .compactMap({ $0.progress })
            .filter({ $0.completedAt != nil })
            .max(by: { ($0.completedAt ?? "") < ($1.completedAt ?? "") }) {
            let when = Self.shortDate(last.completedAt)
            lastRunLine = "last module \(last.quizScore.map(String.init) ?? "—") · \(last.quizAttempts ?? 0) attempt\((last.quizAttempts ?? 0) == 1 ? "" : "s")\(when.isEmpty ? "" : " · \(when)")"
        } else {
            lastRunLine = "no scored attempt on record"
        }

        // 4 · the release bar
        // Neutral until the read answers, so a stale success/danger tone can
        // never outlive the sentence it was derived from.
        gapTint = .slate
        do {
            let gap: ComplianceGap_547 = try await api.query(
                "training.getComplianceGap", input: GapIn(trailerType: nil))
            let pct = gap.compliancePercent ?? 0
            let missing = gap.gaps.filter { ($0.status ?? "") != "compliant" }
            gapLine = missing.isEmpty
                ? "Compliant on all \(gap.totalRequired ?? 0) requirements"
                : "\(missing.count) requirement\(missing.count == 1 ? "" : "s") open · \(pct)% compliant"
            // The tone is derived from the SAME branch that wrote the sentence.
            gapTint = missing.isEmpty ? .success : .danger
        } catch {
            gapLine = "release bar unavailable"
            failures.append("compliance gap")
        }

        // The sandbox strip carries the named gap in words, every render.
        sandboxLine = "Sandbox — no live load, driver or wallet is touched · live-board replay not on the server yet"

        if !failures.isEmpty && scenarios.isEmpty && axes.isEmpty {
            loadError = "Couldn't reach the training record (\(failures.joined(separator: ", ")))."
        }
        loading = false
    }

    // MARK: Actions

    /// trainingLMS.enrollInCourse:215 — the real enrolment. This is what the
    /// platform can genuinely do today; the live-board replay is the named gap.
    func startDrill() async {
        guard let courseId = primaryCourseId else {
            actionNote = "No course selected."
            return
        }
        working = true
        actionNote = nil
        struct In: Encodable { let courseId: Int }
        do {
            let r: EnrollResult_547 = try await api.mutation("trainingLMS.enrollInCourse", input: In(courseId: courseId))
            actionNote = r.alreadyEnrolled == true
                ? "Already enrolled — open the course player to take the scored modules."
                : "Enrolled. Open the course player to take the scored modules."
            await load()
        } catch {
            actionNote = (error as? EusoTripAPIError)?.errorDescription ?? "Couldn't enrol in that course."
        }
        working = false
    }

    /// trainingLMS.getMyCertificates:549 — the read-only certification record.
    func openTranscript() async {
        working = true
        actionNote = nil
        do {
            let certs: [CertificateEntry_547] = try await api.queryNoInput("trainingLMS.getMyCertificates")
            if certs.isEmpty {
                actionNote = "No certificates issued yet."
            } else {
                let active = certs.filter { ($0.certificate?.status ?? "") == "active" }.count
                let newest = certs
                    .compactMap { $0.certificate?.issuedAt }
                    .max()
                actionNote = "\(certs.count) certificate\(certs.count == 1 ? "" : "s") on record · \(active) active\(Self.shortDate(newest).isEmpty ? "" : " · latest \(Self.shortDate(newest))")"
            }
        } catch {
            actionNote = (error as? EusoTripAPIError)?.errorDescription ?? "Couldn't load the transcript."
        }
        working = false
    }

    // NOTE — trainingLMS.submitQuiz (trainingLMS.ts:423) is verified and
    // deliberately NOT wired here. It requires {quizId, answers:[…]} and this
    // surface captures no answers. A score this client invented would be the
    // exact failure this screen's doctrine forbids. See the header.

    // MARK: Derivations

    private static func difficulty(_ raw: String?) -> (String, Tint547) {
        switch (raw ?? "").lowercased() {
        case "advanced":     return ("HARD", .danger)
        case "intermediate": return ("MED", .warn)
        case "beginner":     return ("BASIC", .info)
        default:             return ("—", .slate)
        }
    }

    private static func tint(forCategory c: String?) -> Tint547 {
        switch (c ?? "").lowercased() {
        case "hazmat":      return .violet
        case "safety":      return .danger
        case "compliance", "regulatory": return .info
        case "equipment":   return .slate
        case "wellness":    return .success
        default:            return .info
        }
    }

    /// A score with NO published threshold cannot be graded, so it reads
    /// neutral (.slate) — it is never assumed to pass or fail against a
    /// threshold the server did not supply.
    private static func tint(forScore score: Int?, target: Int?) -> Tint547 {
        guard let s = score, let target else { return .slate }
        if s >= target { return .success }
        if s >= target - 15 { return .warn }
        return .danger
    }

    private static func icon(for c: Course_547) -> String {
        if c.hazmatSpecific == true { return "link" }
        switch (c.category ?? "").lowercased() {
        case "safety":    return "exclamationmark.triangle"
        case "equipment": return "box.truck"
        case "wellness":  return "heart"
        default:          return "building.2"
        }
    }

    private static func subline(for c: Course_547) -> String {
        var parts: [String] = []
        if let s = c.slug, !s.isEmpty { parts.append(s.uppercased()) }
        if let m = c.moduleCount { parts.append("\(m) module\(m == 1 ? "" : "s")") }
        if let d = c.estimatedDurationMinutes { parts.append("\(d) min") }
        if c.isMandatory == true { parts.append("mandatory") }
        return parts.joined(separator: " · ")
    }

    private static func detail(for p: ProgressRow_547, target: Int?) -> String {
        var parts: [String] = []
        if let s = p.status { parts.append(s.replacingOccurrences(of: "_", with: " ")) }
        // The whole clause is DROPPED when no server figure named the target.
        // No literal is substituted and no dash is planted inside the phrase —
        // a figure the server does not produce is simply not printed.
        if let target { parts.append("target \(target)") }
        if let a = p.quizAttempts { parts.append("\(a) attempt\(a == 1 ? "" : "s")") }
        if let t = p.timeSpentMinutes, t > 0 { parts.append("\(t) min") }
        return parts.joined(separator: " · ")
    }

    private static func shortDate(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "" }
        let f = ISO8601DateFormatter()
        var date = f.date(from: iso)
        if date == nil {
            let g = ISO8601DateFormatter()
            g.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = g.date(from: iso)
        }
        guard let d = date else { return "" }
        let out = DateFormatter()
        out.dateFormat = "d MMM"
        return out.string(from: d)
    }
}

// MARK: - Shell chrome (house idiom · matches Dpch730_DispatcherOpsQuartet)

private struct ShellNav<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: DispatchNavRoute.leading(current: .board),
                trailing: DispatchNavRoute.trailing(current: .board),
                orbState: .idle
            )
        }
    }
}

// MARK: - 547 Dispatcher Training Simulator

struct DispatcherTrainingSimulatorScreen: View {
    let theme: Theme.Palette
    var body: some View {
        ShellNav(theme: theme) { TrainingSimulatorBody_547() }
    }
}

private struct TrainingSimulatorBody_547: View {
    @Environment(\.palette) private var palette
    @StateObject private var vm = TrainingSimVM_547()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                if vm.loading {
                    loadingCard
                } else if let err = vm.loadError {
                    errorCard(err)
                } else {
                    certificationHero; axisLadder; scenarioDeck; ctaRow
                }
                Color.clear.frame(height: 96)
            }.padding(.horizontal, Space.s5).padding(.top, Space.s2)
        }
        .task { await vm.load() }
        // Same single `load()` tick, three triggers (pull, top-edge, stale
        // foreground). House pattern, identical to 546/548/550 and Dpch730 —
        // it adds no new call, it re-runs the one above.
        .eusoRefreshable { await vm.load() }
    }

    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading the training record…").font(.system(size: 13)).foregroundStyle(palette.textSecondary)
            Spacer()
        }
        .padding(Space.s5)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.bgCard))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message).font(.system(size: 13)).foregroundStyle(palette.textPrimary)
            Button { Task { await vm.load() } } label: {
                Text("Try again").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textOnGradient)
                    .padding(.horizontal, 18).frame(height: 36)
                    .background(Capsule().fill(LinearGradient.primary))
            }.buttonStyle(.plain)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.bgCard))
    }

    /// Saturated status color — the fill/stroke pair the SVG paints.
    private func tint(_ t: Tint547) -> Color {
        switch t {
        case .danger:  return Brand.danger
        case .warn:    return Brand.warning
        case .success: return Brand.success
        case .info:    return Brand.info
        case .violet:  return Brand.escort
        case .slate:   return Brand.rail
        }
    }

    /// Darker sibling for SMALL TEXT only (see the WCAG block at the top of
    /// this file). Never use these as a fill — they are a text pair.
    private func tintText(_ t: Tint547) -> Color {
        switch t {
        case .danger:  return dangerText_547
        case .warn:    return warnText_547
        case .success: return successText_547
        case .info:    return infoText_547
        case .violet:  return escortText_547
        case .slate:   return Brand.rail
        }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(vm.eyebrow).font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(vm.caption).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 10) {
                // Real control, not a decorative glyph — the house pattern every
                // pre-existing Dispatch peer uses (410:194-200). 44-unit target.
                Button { back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .bold)).foregroundStyle(palette.textPrimary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Text(vm.title).font(.system(size: 28, weight: .bold)).kerning(-0.4).foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
            // THE one iridescent hairline on this surface.
            IridescentHairline()
        }
    }

    private func back() {
        NotificationCenter.default.post(name: .eusoDispatchNavSwap, object: nil, userInfo: ["screenId": "Disp401"])
    }

    /// The release-bar line takes its colour from the state that PRODUCED it:
    /// compliant reads success, open requirements read danger, an unavailable
    /// read reads neutral. Compliance must never paint as an alarm.
    private func gapLineColor(_ t: Tint547) -> Color {
        switch t {
        case .success: return successText_547
        case .danger:  return dangerText_547
        default:       return palette.textSecondary
        }
    }

    // MARK: - Radial certification dial + pass bar + sandbox strip
    private var certificationHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(vm.heroLabel).font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
            HStack(alignment: .center, spacing: Space.s5) {
                certificationDial
                VStack(alignment: .leading, spacing: 6) {
                    Text(vm.moduleLine).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text(vm.lastRunLine).font(.system(size: 11, design: .monospaced)).kerning(0.4).foregroundStyle(palette.textSecondary)
                    Text(vm.gapLine).font(.system(size: 11, weight: .bold)).foregroundStyle(gapLineColor(vm.gapTint)).padding(.top, Space.s1)
                    passBar
                }
            }
            sandboxStrip
        }
        .padding(Space.s5)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    private var certificationDial: some View {
        ZStack {
            Circle().stroke(palette.textPrimary.opacity(0.06), lineWidth: 10)
            Circle().trim(from: 0, to: vm.dialFrac)
                .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(vm.dialValue).font(.system(size: 26, weight: .bold)).monospacedDigit().kerning(-0.5).foregroundStyle(palette.textPrimary)
                Text(vm.dialOutOf).font(.system(size: 9, weight: .bold)).kerning(0.6).foregroundStyle(palette.textTertiary)
            }
        }.frame(width: 76, height: 76)
    }

    private var passBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.textPrimary.opacity(0.06)).frame(height: 8)
                Capsule().fill(LinearGradient.primary).frame(width: geo.size.width * vm.passFrac, height: 8)
                // Drawn ONLY when a real server figure named the threshold. An
                // absent threshold draws nothing — never a tick at a default.
                if let threshold = vm.thresholdFrac {
                    RoundedRectangle(cornerRadius: 1.5).fill(palette.textPrimary)
                        .frame(width: 3, height: 16)
                        .offset(x: geo.size.width * threshold)
                }
            }.frame(height: 16)
        }.frame(height: 16)
    }

    /// Sandbox isolation — a safety property, and the named gap, in words.
    private var sandboxStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 12, weight: .semibold)).foregroundStyle(warnText_547)
            Text(vm.sandboxLine).font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(2).minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).frame(minHeight: 24)
        .background(
            // Two-stop danger→warning WASH. The Palette ships the washes but no
            // gradient pairing of them, so the pair is composed here from the
            // tint tokens rather than from raw color literals.
            Capsule().fill(LinearGradient(colors: [palette.tintDanger, palette.tintWarning], startPoint: .leading, endPoint: .trailing))
        )
    }

    // MARK: - Scored-axis bullet ladder
    private var axisLadder: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(vm.axesLabel).font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(vm.axesSource).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }.padding(.bottom, 10)
            VStack(spacing: 0) {
                ForEach(Array(vm.axes.enumerated()), id: \.element.id) { idx, axis in
                    axisRow(axis)
                    if idx < vm.axes.count - 1 { rowRule }
                }
                if let reason = vm.axesEmptyReason {
                    HStack(alignment: .top, spacing: Space.s2) {
                        Image(systemName: "tray").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textTertiary)
                        Text(reason).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                        Spacer(minLength: 0)
                    }.padding(Space.s4)
                }
            }
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    /// Hairline rule between list rows — the SVG's #000000 @ 6% separator,
    /// expressed with the palette's own faint-border token.
    private var rowRule: some View {
        Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, Space.s4)
    }

    private func axisRow(_ axis: ScoredAxis_547) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(axis.name).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Spacer()
                Text(axis.score).font(.system(size: 14, weight: .bold)).monospacedDigit().foregroundStyle(tintText(axis.scoreTint))
            }
            Text(axis.detail).font(.system(size: 11, design: .monospaced)).kerning(0.4).foregroundStyle(palette.textSecondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.textPrimary.opacity(0.06)).frame(height: 7)
                    Capsule().fill(tint(axis.barTint).opacity(0.85))
                        .frame(width: geo.size.width * axis.fill, height: 7)
                    // Same rule as the pass bar: no published threshold, no tick.
                    if let axisTarget = axis.target {
                        RoundedRectangle(cornerRadius: 1.5).fill(palette.textPrimary.opacity(0.55))
                            .frame(width: 3, height: 15)
                            .offset(x: geo.size.width * axisTarget)
                    }
                }.frame(height: 15)
            }.frame(height: 15)
        }.padding(Space.s4)
    }

    // MARK: - Scenario deck
    private var scenarioDeck: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(vm.deckLabel).font(.system(size: 9, weight: .heavy)).kerning(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(vm.deckSource).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }.padding(.bottom, 10)
            VStack(spacing: 0) {
                ForEach(Array(vm.scenarios.enumerated()), id: \.element.id) { idx, s in
                    scenarioRow(s)
                    if idx < vm.scenarios.count - 1 { rowRule }
                }
                if vm.scenarios.isEmpty {
                    HStack(alignment: .top, spacing: Space.s2) {
                        Image(systemName: "tray").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textTertiary)
                        Text("No courses published for this account yet.").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                        Spacer(minLength: 0)
                    }.padding(Space.s4)
                }
            }
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private func scenarioRow(_ s: Scenario_547) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                // Per-category wash. The Palette's tint* tokens cover
                // success/warning/danger/info only — escort and rail have no
                // wash token — so the wash is derived from the row's own
                // Brand color at the SVG's 12%.
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint(s.tint).opacity(0.12)).frame(width: 40, height: 40)
                Image(systemName: s.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint(s.tint))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(s.title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(s.sub).font(.system(size: 11, design: .monospaced)).kerning(0.4).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 5) {
                Text(s.difficulty).font(.system(size: 10, weight: .heavy)).kerning(0.6).foregroundStyle(tintText(s.difficultyTint))
                Text(s.best).font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
            }
        }.padding(Space.s4)
    }

    // MARK: - CTA pair (both LMS-scoped · no load, driver, wallet or dispatch write)
    private var ctaRow: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Button { Task { await vm.startDrill() } } label: {
                    Text(vm.working ? "Working…" : vm.primaryCTA)
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textOnGradient)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity).frame(height: 48).background(Capsule().fill(LinearGradient.primary))
                }
                .disabled(vm.working || vm.scenarios.isEmpty)
                .opacity(vm.scenarios.isEmpty ? 0.45 : 1.0)

                Button { Task { await vm.openTranscript() } } label: {
                    Text(vm.secondaryCTA).font(.system(size: 15, weight: .semibold)).frame(width: 132, height: 48)
                        .background(Capsule().fill(palette.bgCard))
                        .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
                }
                .foregroundStyle(palette.textPrimary)
                .disabled(vm.working)
            }
            if let note = vm.actionNote {
                Text(note).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
        }
    }
}

// MARK: - Previews

#Preview("547 · Training Simulator · Dark")  { DispatcherTrainingSimulatorScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("547 · Training Simulator · Light") { DispatcherTrainingSimulatorScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
