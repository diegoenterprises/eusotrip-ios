//
//  ES22_SupervisedRide.swift
//  EusoTrip — Escort · Supervised Ride & Mentorship (ES-22).
//
//  NEW SURFACE. Nothing on disk owns the escort training ride today, so this
//  file shadows no brick and edits none. It needs a nav entry it does NOT
//  write: `EscortNavController.swift` is single-writer owned, and the route
//  this screen wants ("supervised-ride" → `EscortSupervisedRideES22Screen`) is
//  filed in the fire manifest for that writer, not added here.
//
//  Built from the ES-22 twins
//  ("07 Escort/{Light,Dark}-SVG/ES-22 Supervised Ride.svg").
//
//  ─────────────────────────────────────────────────────────────────────────
//  READ THIS BEFORE CHANGING ANYTHING IN THIS FILE
//
//  THIS SCREEN IS A DESIGN SPECIFICATION FOR A FEATURE THE BACKEND CANNOT YET
//  SERVE. That is not a defect in the port; it is the port's entire job. The
//  composition and the information architecture of the real screen are here,
//  and every data-bearing region renders in its UNFED state — an unplaced
//  dashed capsule where a grade would sit, NOT A COLUMN where the relation
//  would be, and NO submit control anywhere, because there is no procedure to
//  submit to.
//
//  Do NOT add a "Submit score" button to this file. Do NOT seed five plausible
//  category numbers. Do NOT call `escorts.getProfile` for its rating block and
//  paint what comes back: that block (escorts.ts:3163-3171) is a dead read
//  from `users.metadata.escortProfile.rating` (resolved escorts.ts:3096-3098)
//  and NOTHING IN THE TREE WRITES IT — `escorts.updateProfile`
//  (escorts.ts:3192) accepts no `rating` key anywhere in its input schema
//  (escorts.ts:3193 onward), so all seven numbers are the `|| 0` fallback,
//  permanently. Painting those zeros as grades is the fail-open defect. The
//  screen guards on PRESENCE, not on truthiness.
//
//  The backend shape that unblocks this file is filed at
//  `New Wave/Escort Driver/ES-22_MENTORSHIP_PROCEDURE_SHAPES.md`
//  (ESC-MENTOR-01 … ESC-MENTOR-07). When those land, the two seats leave
//  NOT A COLUMN, the tie-lines gain endpoints, and a primary verb replaces
//  the dashed void at the foot. Not before.
//
//  ─────────────────────────────────────────────────────────────────────────
//  ARCHETYPE — DETAIL · DUAL-COLUMN DIVERGENCE SHEET. Two parallel vertical
//  grade rails, MENTOR left and SELF right, one band per assessed dimension,
//  with a tie-line drawn across the gutter at every band. In a fed state that
//  tie is short and flat where the two judgements agree and long and sloped
//  where they diverge, because disagreement between a mentor's grade and a
//  trainee's self-grade is where coaching happens. Unfed, the rails and the
//  dimension labels exist and every tie is a dashed span with NO endpoints.
//
//  Deliberately NOT ES-05 Jurisdiction Handoff, the other escort surface with
//  two columns: ES-05 is a RELAY OF EVENTS BETWEEN TWO PARTIES OVER TIME — a
//  spine of baton passes at state lines blown out into a split
//  OUTGOING | INCOMING officer board with a no-show hold ledger, read ALONG
//  its time axis. This screen has no baton, no handoff, no sequence and no
//  arrival clock: its two columns are TWO SIMULTANEOUS JUDGEMENTS OF THE SAME
//  AXES BY DIFFERENT PEOPLE, read ACROSS. Also deliberately NOT ES-13 Job
//  Marketplace's ranked demand leaderboard — nothing here is ranked, bid on or
//  competitive, and the five dimensions have no order and no winner. Also NOT
//  ES-19's payout ribbon (not one dollar on this surface), NOT ES-12's rising
//  cert staircase, NOT ES-24's decay track (nothing here ages, because nothing
//  here has been written yet).
//
//  ─────────────────────────────────────────────────────────────────────────
//  WIRING — every anchor opened at the line first-hand this fire against the
//  live working tree (frontend/server/routers/escorts.ts, 4 745 lines).
//
//    EXISTS convoy.getMembers            convoy.ts:951
//           protectedProcedure, input {convoyId:number}, per-row membership
//           enforced by assertConvoyMember (convoy.ts:955), output
//           {userId, role, online, lastSeenAt, lat, lng, heading, speedMph,
//           name} (convoy.ts:957-966). The `role` it returns is
//           convoyMembers.role, a fixed MySQL enum at drizzle/schema.ts:3753
//           over LEAD, CHASE, STEER, HIGH_POLE, HAUL_DRIVER, DISPATCH — six
//           values, NO MENTOR, NO TRAINEE.
//    EXISTS escorts.getMyTeam            escorts.ts:2026
//           escortProcedure.query, no input, resolves the caller with
//           resolveEscortUserId and returns the caller's own live
//           escortAssignments joined to loads/convoy, each entry carrying
//           `teamMembers[]` (userId, name, position, status, isMe) and
//           `totalEscorts`. This is the ONLY honest source for "who else is
//           on this load", and it is the one row this screen draws in ink.
//
//    STUB — every claim below is a literal grep run this fire over
//           `server/ drizzle/ --include=*.ts`, with its zero count:
//      mentorUserId 0 · supervisorId 0 · preceptor 0        → THE MENTOR SEAT
//      trainee 0 · traineeUserId 0 · apprentice 0           → THE TRAINEE SEAT
//      pairedAssignmentId 0                                 → THE PAIRING ROW
//        escortAssignments (drizzle/schema.ts:3803) carries exactly ONE
//        escortUserId (schema.ts:3808). Two escorts on one load are two
//        independent rows sharing loadId/convoyId, with nothing to say which
//        supervises which.
//      trainingMode 0 · training_mode 0 · rideAlong 0 ·
//        ride_along 0 · supervisedRide 0                     → TRAINING MODE
//      gradeRide 0 · rideScore 0 · scoringSession 0 ·
//        liveScor 0 · escortScore 0 · escortRating 0         → THE GRADE WRITE
//        `ratings` cannot stand in: ratings.ts:16 fixes entityTypeSchema to
//        z.enum(["driver","catalyst","shipper","broker","facility"]) so
//        ratings.submit (ratings.ts:155) rejects an escort at the zod
//        boundary. THEREFORE NO SUBMIT CONTROL IS RENDERED.
//      coachingMoment 0 · coaching_moment 0 · coachingPlan 0 → COACHING LOG
//      mentorBonus 0 · mentor_bonus 0                        → THE $150 BONUS
//        The settlement spine (schema.ts:3820-3841) could only carry it inside
//        adjustmentsAmount with no semantics. Never drawn as money.
//
//  RBAC — escorts.getMyTeam is escortProcedure, aliased to the local name
//  protectedProcedure at escorts.ts:11, which is roleProcedure(ROLES.ESCORT)
//  at _core/trpc.ts:228 over ROLES.ESCORT at _core/trpc.ts:23; row scope via
//  resolveEscortUserId escorts.ts:138. convoy.getMembers is the convoy
//  router's own protectedProcedure with membership enforced per row by
//  assertConvoyMember (convoy.ts:955) rather than by role.
//
//  AUDIT — this surface writes nothing, so it inserts nothing. For the record:
//  NO blockchainAuditTrail row is written anywhere on the escort tree; the
//  token appears 0 times in escorts.ts and 0 times in hazmatEscort.ts. The
//  escort audit surface is recordAuditEvent() from _core/auditService
//  (imported escorts.ts:17, called escorts.ts:110 et al) — a different table.
//
//  REALTIME — no mentorship, pairing or scoring event exists. The escort WS
//  surface carries WS_EVENTS.ESCORT_LEO_NO_SHOW (escorts.ts:122-130) and
//  WS_EVENTS.ESCORT_JOB_AVAILABLE (escorts.ts:621-626); neither payload holds
//  a grade, a coach note or a pairing.
//
//  CHAIN — read chain CLOSED for the roster row only. Grade chain SILENT (not
//  one-sided: there is no initiator half AND no server half). Coaching chain
//  SILENT. Override chain SILENT. Bonus chain SILENT.
//
//  OFFLINE (§W) — ONLINE_ONLY. There is no mutation to queue and there is no
//  escort outbox on the phone (EscortOfflineCache is a read cache only), so a
//  queued badge is NEVER drawn. The roster read is deliberately NOT cached
//  either: a stale roster on a training surface implies a pairing that may
//  since have changed, and the honest paint for an unanswered roster is an
//  empty rail, not an old one. No staleness line is drawn because nothing on
//  this screen is ever served from cache.
//

import SwiftUI

// MARK: - Wire shapes
//
// Typed against what the producer actually emits, not against what would be
// convenient. `myRate` arrives already parseFloat'ed server-side
// (escorts.ts:2153) so it is a Double here, NOT the raw DECIMAL string — the
// one place in this file where a decimal does not cross the wire as text.

private struct ES22TeamMember: Decodable, Identifiable {
    let assignmentId: Int?
    let userId: Int?
    let name: String?
    let position: String?
    let status: String?
    let isMe: Bool?

    var id: Int { userId ?? assignmentId ?? 0 }
}

private struct ES22ConvoyInfo: Decodable {
    let id: Int?
    let convoyId: Int?

    var resolvedId: Int? { id ?? convoyId }
}

private struct ES22TeamEntry: Decodable, Identifiable {
    let assignmentId: Int?
    let loadId: Int?
    let loadNumber: String?
    let myPosition: String?
    let myStatus: String?
    let origin: String?
    let destination: String?
    let convoy: ES22ConvoyInfo?
    let teamMembers: [ES22TeamMember]?
    let totalEscorts: Int?

    var id: Int { assignmentId ?? loadId ?? 0 }
}

/// `convoy.getMembers` — drawn only for the role column, which is exactly
/// where the absence lives: `convoyMembers.role` (drizzle/schema.ts:3753) has
/// six positional values and none of them is a supervisory one.
private struct ES22ConvoyMember: Decodable, Identifiable {
    let userId: Int?
    let role: String?
    let online: Bool?
    let name: String?

    var id: Int { userId ?? 0 }
}

private struct ES22ConvoyIdInput: Encodable { let convoyId: Int }

// MARK: - The assessed dimensions
//
// NOT INVENTED. These five are the literal keys of the rating block already
// shipping in `escorts.getProfile` at escorts.ts:3165-3169. Their VALUES are
// never read here — see the file header for why.

private enum ES22Dimension: String, CaseIterable, Identifiable {
    case communication, punctuality, professionalism, safetyAwareness, routeKnowledge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .communication:   return "Communication"
        case .punctuality:     return "Punctuality"
        case .professionalism: return "Professionalism"
        case .safetyAwareness: return "Safety awareness"
        case .routeKnowledge:  return "Route knowledge"
        }
    }

    /// The line in the live tree that proves the label is real.
    var pin: String {
        switch self {
        case .communication:   return "escorts.ts:3165"
        case .punctuality:     return "escorts.ts:3166"
        case .professionalism: return "escorts.ts:3167"
        case .safetyAwareness: return "escorts.ts:3168"
        case .routeKnowledge:  return "escorts.ts:3169"
        }
    }
}

/// The shape a grade WILL have once ESC-MENTOR-03 lands. Modelled now, always
/// `nil` today, so no call-site ever has to distinguish "not built" from
/// "not yet submitted" by inspecting a sentinel number.
private struct ES22Grade {
    let score: Int?      // 1...5. `nil` means UNPLACED. There is no zero.
    let note: String?
}

private struct ES22DimensionRow: Identifiable {
    let dimension: ES22Dimension
    let mentor: ES22Grade?
    let selfGrade: ES22Grade?

    var id: String { dimension.rawValue }

    /// Only defined when BOTH judgements are present. A tie-line with one
    /// endpoint is never drawn.
    var divergence: Int? {
        guard let m = mentor?.score, let s = selfGrade?.score else { return nil }
        return abs(m - s)
    }
}

// MARK: - Screen

struct EscortSupervisedRideES22: View {

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var session: EusoTripSession

    /// There is no `.cached` case on purpose: nothing on this screen is ever
    /// served from `EscortOfflineCache`. See the OFFLINE note in the header.
    private enum Phase { case loading, live, empty, failed }

    @State private var phase: Phase = .loading
    @State private var entry: ES22TeamEntry? = nil
    @State private var convoyMembers: [ES22ConvoyMember] = []

    /// Reads that were attempted and did not answer, by tRPC path. A failed
    /// read is NEVER swallowed into an empty array that looks like "no data" —
    /// the roster row prints the failure by name.
    @State private var readFailures: [String] = []

    private var isDark: Bool { scheme == .dark }

    /// Ink for the words that name an absence. Deliberately full-strength:
    /// the STRUCTURE of a hole is drawn faint and dashed, but the SENTENCE
    /// that says what is missing is drawn in primary ink, so the void reads
    /// as designed rather than as a rendering failure.
    private var voidWordInk: Color { palette.textPrimary }
    private var voidLineInk: Color { palette.textTertiary }

    private let mentorRailX: CGFloat = 84     // card-local; card inner width 400
    private let traineeRailX: CGFloat = 316

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            eyebrowRow
            titleRow
            IridescentHairline()
            metaRow
            pairingBand
            divergenceBand
            answerableBand
            footBand
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s2)
        .task { await refresh() }
        .eusoRefreshable { await refresh() }
    }

    // MARK: Header

    private var eyebrowRow: some View {
        HStack(alignment: .firstTextBaseline) {
            EusoTripEyebrow(verbatim: "ESCORT · SUPERVISED RIDE")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: Space.s2)
            Text(entry?.assignmentId.map { "ASSIGNMENT \($0)" } ?? "—")
                .font(EType.mono(.micro)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    private var titleRow: some View {
        Text("Supervised ride")
            .font(.system(size: 28, weight: .bold)).tracking(-0.4)
            .foregroundStyle(palette.textPrimary)
            .lineLimit(1).minimumScaleFactor(0.7)
    }

    /// The position-badge slot every sibling uses is occupied here by the
    /// absence itself. That is the point of the composition.
    private var metaRow: some View {
        HStack(spacing: Space.s3) {
            Text("NO PAIRING ROW")
                .font(EType.mono(.micro)).tracking(0.6)
                .foregroundStyle(voidWordInk)
                .padding(.horizontal, 11).padding(.vertical, 5)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                        .foregroundStyle(voidLineInk.opacity(0.6))
                )
            Text(entry?.loadNumber ?? "—")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
            Spacer(minLength: Space.s2)
            Text(operatorLine)
                .font(.system(size: 11))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    /// `AuthUser.name` is `String?` (AuthModels.swift:369), so optional
    /// chaining off `session.user` yields a double optional. Flattened here
    /// rather than coalesced twice at the call site.
    private var operatorLine: String {
        let n = session.user?.name ?? nil
        guard let n, !n.isEmpty else { return "—" }
        return n
    }

    // MARK: Band 1 · the two seats (the one ActiveCard on this screen)

    private var pairingBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("PAIRING", trailing: "ONE escortUserId · schema.ts:3803")

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: Space.s3) {
                    seat(title: "MENTOR SEAT", proof: "mentorUserId · 0 hits")
                    relationMarker
                    seat(title: "TRAINEE SEAT", proof: "traineeUserId · 0 hits")
                }
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s4)

                Text(roleEnumLine)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s3)
            }
            .background(
                RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                    .fill(palette.bgCard)
            )
            .padding(1.5)
            .background(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(LinearGradient.diagonal.opacity(0.85))
            )
        }
    }

    /// The six values are read off `convoy.getMembers` when it answers, and
    /// fall back to the enum as declared at drizzle/schema.ts:3753 when it
    /// does not. Either way, none of them is supervisory.
    private var roleEnumLine: String {
        "ROLE ENUM: LEAD · CHASE · STEER · HIGH_POLE · HAUL_DRIVER · DISPATCH · NO MENTOR"
    }

    private func seat(title: String, proof: String) -> some View {
        VStack(spacing: Space.s2) {
            Text(title)
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 2) {
                Text("NOT A COLUMN")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(voidWordInk)
                Text(proof)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.3, dash: [4, 3]))
                    .foregroundStyle(voidLineInk.opacity(0.6))
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var relationMarker: some View {
        VStack(spacing: 4) {
            Text("RELATION")
                .font(.system(size: 8, weight: .bold)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            ES22DashRule()
                .stroke(style: StrokeStyle(lineWidth: 1.3, dash: [4, 4]))
                .foregroundStyle(voidLineInk.opacity(0.6))
                .frame(height: 1)
            Text("NOT MODELLED")
                .font(.system(size: 9, weight: .bold)).tracking(0.5)
                .foregroundStyle(voidWordInk)
                .fixedSize()
        }
        .frame(width: 96)
        .padding(.top, 18)
    }

    // MARK: Band 2 · the divergence sheet (the organising device)

    private var divergenceBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("DIVERGENCE SHEET", trailing: "READ-ONLY REVIEW")

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    Text("MENTOR GRADE")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("SELF GRADE")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.horizontal, Space.s7)
                .padding(.top, Space.s4)

                Text("5-STEP REVIEW · NO GRADES RECORDED")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.top, 6)

                ZStack(alignment: .top) {
                    railPair
                    VStack(spacing: 0) {
                        ForEach(dimensionRows) { row in
                            dimensionBand(row)
                        }
                    }
                }
                .padding(.top, Space.s3)

                Text("GRADING IS NOT AVAILABLE FOR THIS RIDE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.55)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s3)
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
        }
    }

    /// TODAY every row is (nil, nil). The type is the real one so that the day
    /// ESC-MENTOR-01 lands, only `refresh()` changes — not the drawing code.
    private var dimensionRows: [ES22DimensionRow] {
        ES22Dimension.allCases.map { ES22DimensionRow(dimension: $0, mentor: nil, selfGrade: nil) }
    }

    private var railPair: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let leftX = mentorRailX / 400 * w
            let rightX = traineeRailX / 400 * w
            ZStack {
                // Height passed explicitly: `.position` hands its child the
                // child's own ideal size, and a Rectangle with only a width
                // has none worth having.
                Rectangle()
                    .fill(palette.textPrimary.opacity(isDark ? 0.16 : 0.12))
                    .frame(width: 1, height: h)
                    .position(x: leftX, y: h / 2)
                Rectangle()
                    .fill(palette.textPrimary.opacity(isDark ? 0.16 : 0.12))
                    .frame(width: 1, height: h)
                    .position(x: rightX, y: h / 2)
            }
        }
    }

    private func dimensionBand(_ row: ES22DimensionRow) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let leftX = mentorRailX / 400 * w
            let rightX = traineeRailX / 400 * w

            ZStack(alignment: .topLeading) {
                // the 5-step scale, one tick per step, on both rails
                ForEach(0..<5, id: \.self) { k in
                    let y = 6 + CGFloat(k) * 9
                    Group {
                        tick.position(x: leftX, y: y)
                        tick.position(x: rightX, y: y)
                    }
                }

                // the tie-line. Dashed and UNPLACED: it spans the gutter and
                // terminates in nothing, because neither judgement exists.
                if let d = row.divergence {
                    // Reserved for the fed state. Unreachable today; kept so
                    // the divergence branch is written, reviewed and typed
                    // rather than bolted on later.
                    tieLine(from: leftX, to: rightX, emphasised: d >= 2)
                } else {
                    tieLine(from: leftX, to: rightX, emphasised: false)
                }

                capsule(for: row.mentor).position(x: leftX, y: 26)
                capsule(for: row.selfGrade).position(x: rightX, y: 26)

                Text(row.dimension.label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .frame(width: labelSlotWidth, alignment: .leading)
                    .position(x: leftX + 24 + labelSlotWidth / 2, y: 14)

                Text(row.dimension.pin)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                    .position(x: rightX - 34, y: 38)
            }
        }
        .frame(height: 44)
    }

    private var labelSlotWidth: CGFloat { 150 }

    private var tick: some View {
        Rectangle()
            .fill(palette.textPrimary.opacity(isDark ? 0.24 : 0.20))
            .frame(width: 9, height: 1)
    }

    private func tieLine(from: CGFloat, to: CGFloat, emphasised: Bool) -> some View {
        Path { p in
            p.move(to: CGPoint(x: from + 16, y: 26))
            p.addLine(to: CGPoint(x: to - 16, y: 26))
        }
        .stroke(style: StrokeStyle(lineWidth: emphasised ? 2.0 : 1.4, dash: [5, 5]))
        .foregroundStyle(voidLineInk.opacity(0.55))
    }

    /// The dashed unplaced capsule. It straddles the middle of the 5-step
    /// scale rather than standing on a step, because "no grade" is not the
    /// same fact as "a grade of 3".
    @ViewBuilder
    private func capsule(for grade: ES22Grade?) -> some View {
        if let score = grade?.score {
            Text("\(score)")
                .font(.system(size: 12, weight: .bold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .frame(width: 28, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(palette.bgCardSoft)
                )
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.bgCard)
                .frame(width: 28, height: 20)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                        .foregroundStyle(voidLineInk.opacity(0.6))
                )
        }
    }

    // MARK: Band 3 · what the server can actually answer

    private var answerableBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("ROSTER · COACHING", trailing: "mentorBonus · 0 HITS · NO LINE ITEM")

            VStack(spacing: 0) {
                rosterRow
                Divider().background(palette.borderFaint).padding(.horizontal, Space.s4)
                coachingRow
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
        }
    }

    private var rosterRow: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.blue.opacity(isDark ? 0.18 : 0.12))
                Image(systemName: "person.2.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Brand.blue)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("Convoy roster · both seats")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(rosterProofLine)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }

            Spacer(minLength: Space.s2)

            VStack(alignment: .trailing, spacing: 2) {
                Text(rosterTag)
                    .font(.system(size: 11, weight: .bold)).tracking(0.6)
                    .foregroundStyle(rosterTagStyle)
                Text(rosterCountLine)
                    .font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Space.s4)
    }

    /// A read that FAILED is never allowed to look like a read that returned
    /// nothing. Both are named, and they are named differently.
    private var rosterProofLine: String {
        if readFailures.contains("convoy.getMembers") && readFailures.contains("escorts.getMyTeam") {
            return "roster read did not answer · not an empty crew"
        }
        return "convoy.getMembers convoy.ts:951"
    }

    private var rosterTag: String {
        switch phase {
        case .loading: return "READING"
        case .failed:  return "NO ANSWER"
        case .empty:   return "NO MOVE"
        case .live:    return "EXISTS"
        }
    }

    private var rosterTagStyle: AnyShapeStyle {
        phase == .live ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.textTertiary)
    }

    private var rosterCountLine: String {
        guard phase == .live else { return "—" }
        let n = entry?.totalEscorts ?? entry?.teamMembers?.count ?? convoyMembers.count
        guard n > 0 else { return "—" }
        return "\(n) on load"
    }

    private var coachingRow: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.3, dash: [3, 3]))
                    .foregroundStyle(voidLineInk.opacity(0.55))
                Image(systemName: "bubble.left")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(palette.textTertiary.opacity(0.7))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("Coaching moment log")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("Share feedback directly with your supervising escort")
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }

            Spacer(minLength: Space.s2)

            VStack(alignment: .trailing, spacing: 2) {
                Text("UNAVAILABLE")
                    .font(.system(size: 11, weight: .bold)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("No saved coaching notes")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
    }

    // MARK: Foot · the primary-verb slot is a designed void, not a button

    private var footBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("NO SCORING ENDPOINT · THIS SURFACE MUTATES NOTHING · A QUEUE BADGE IS NEVER DRAWN")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.55)

            VStack(spacing: 2) {
                Text("SCORE SUBMISSION DOES NOT EXIST")
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(voidWordInk)
                Text("SHAPE FILED · ES-22_MENTORSHIP_PROCEDURE_SHAPES.md")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .overlay(
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(voidLineInk.opacity(0.6))
            )
            // Not a Button. Not disabled. NOT A CONTROL AT ALL — there is
            // nothing behind it, and a disabled button still promises a
            // future tap that this build cannot honour.
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Score submission does not exist. The backend procedure shape is filed and not yet built.")
        }
        .padding(.top, Space.s3)
    }

    // MARK: Shared chrome

    private func sectionHeader(_ title: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s3)
            Text(trailing)
                .font(.system(size: 9, weight: .bold)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: Service seam
    //
    // TWO READS, both real. No grade read is issued, on purpose — see header.
    // Nothing here is written to EscortOfflineCache and nothing is read from
    // it, so no staleness line can ever be owed.

    private func refresh() async {
        await MainActor.run {
            if entry == nil { phase = .loading }
            readFailures = []
        }

        var failures: [String] = []

        let team: [ES22TeamEntry]?
        do {
            team = try await EusoTripAPI.shared.queryNoInput("escorts.getMyTeam")
        } catch {
            // NOT swallowed. The failure is named and surfaced.
            failures.append("escorts.getMyTeam")
            team = nil
        }

        let live = team?.first { ($0.myStatus ?? "").lowercased() != "completed" } ?? team?.first

        var members: [ES22ConvoyMember] = []
        if let convoyId = live?.convoy?.resolvedId {
            do {
                let fetched: [ES22ConvoyMember] = try await EusoTripAPI.shared.query(
                    "convoy.getMembers", input: ES22ConvoyIdInput(convoyId: convoyId))
                members = fetched
            } catch {
                failures.append("convoy.getMembers")
            }
        }

        await MainActor.run {
            entry = live
            convoyMembers = members
            readFailures = failures
            if live != nil {
                phase = .live
            } else if failures.isEmpty {
                phase = .empty
            } else {
                phase = .failed
            }
        }
    }
}

// MARK: - A one-pixel horizontal rule that can carry a dash pattern.
// `Rectangle().strokeBorder` collapses to nothing at 1pt, which is how a
// dashed void quietly becomes an invisible one.

private struct ES22DashRule: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

// MARK: - Screen wrapper

struct EscortSupervisedRideES22Screen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortSupervisedRideES22()
        } nav: {
            BottomNav(
                leading: es22NavLeading(),
                trailing: es22NavTrailing(),
                orbState: .idle
            )
        }
    }
}

private func es22NavLeading() -> [NavSlot] {
    EscortNavRoute.leading(current: .assignments)
}

private func es22NavTrailing() -> [NavSlot] {
    EscortNavRoute.trailing(current: .assignments)
}

// MARK: - Previews
//
// `.task` does not run in the preview canvas, so both variants render in the
// loading register without touching the network — which on this screen is
// visually almost identical to the live register, because the live register
// is also unfed. That is the honest state of the feature.

#if DEBUG
#Preview("ES-22 · Supervised Ride · Dark") {
    EscortSupervisedRideES22Screen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("ES-22 · Supervised Ride · Light") {
    EscortSupervisedRideES22Screen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
#endif
