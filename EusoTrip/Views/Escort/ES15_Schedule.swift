//
//  ES15_Schedule.swift
//  EusoTrip — Escort · ES-15 Schedule & Availability (month-density BOARD calendar).
//
//  Built from the ES-15 design-authority SVG pair
//  ("07 Escort/{Light,Dark}-SVG/ES-15 Schedule Availability.svg").
//  One month as a 6x7 date lattice; every in-month cell carries a per-day
//  move-density comb; multi-day blocking bands run ACROSS contiguous cells and
//  break-and-continue over the week seam; the peak day is blown out into an
//  hour-ruler density panel that shows the real overlaps.
//
//  Wiring truth (code-traced this firing against the live working tree;
//  fingerprint md5 064a1b8459b8 · 4745 lines · mtime 2026-08-10T22:41:39-05:00):
//    REAL  escorts.getUpcomingJobs      escorts.ts:738  — month lattice counts.
//                                        {limit?} default 5, status='accepted'
//                                        ONLY, scheduledDate "YYYY-MM-DD".
//                                        Called here at limit 200 so the month
//                                        is not silently under-drawn.
//    REAL  escorts.getSchedule          escorts.ts:2265 — active-status rows.
//    REAL  escorts.getAvailability      escorts.ts:2298 — 7 day-of-week rows.
//    REAL  escorts.updateAvailability   escorts.ts:2318 — ONE day per call.
//    REAL  escorts.getCertificationStatus escorts.ts:924 — the cert expiry the
//                                        renewal-window band is DERIVED from.
//    REAL  escorts.getJobDetails        escorts.ts:1979 — consumed for ONE
//                                        field, loads.deliveryDate, because
//                                        neither schedule read projects it and
//                                        a multi-day band needs an end day.
//
//  HONEST LIMITS — both real, both stated on the surface, neither worked around
//  with a guess:
//    • getSchedule declares an input {date?} its handler never reads
//      (escorts.ts:2267) and hard-caps at .limit(10) (escorts.ts:2282). A
//      12-move day cannot be returned whole by it.
//    • getUpcomingJobs is accepted-status only. A day whose true count exceeds
//      both projections is UNDER-counted, and this screen says so rather than
//      presenting a short number as complete.
//    • There is NO escort-entered blackout write path anywhere in escorts.ts and
//      no blackout column in the escort schema, so the SECONDARY action "Block
//      dates" ships DISABLED with STUB · NO WRITE PATH on its face. It has no
//      handler, never opens a sheet and never fakes a write. Searched, not
//      assumed: `blackout` returns ZERO hits across server/routers/. The nearest
//      callable anywhere in the tree is availability.blockTime
//      (server/routers/availability.ts:202, with unblockTime :236 and
//      setAvailability :265, mounted routers.ts:1747) and it is deliberately NOT
//      wired here — it is gated by isolatedProcedure (_core/trpc.ts:517: auth +
//      isolation + autoAudit, NO role gate, therefore not escort-scoped) and it
//      writes driver_availability_blocks.driverId, which no escorts.* read ever
//      returns. Wiring it would persist a block this lattice can never draw.
//    • updateAvailability persists to users.metadata and emits NOTHING — no
//      audit row, no WebSocket fan-out. A dispatcher board does not learn that
//      Saturday just went dark. Named as a one-sided chain, not hidden.
//    • STUB — NO CLOCK ON THE PRIMARY READ. getUpcomingJobs returns
//      id/loadNumber/position/origin/destination/scheduledDate/pay/distance
//      (escorts.ts:754-762) and carries NO start time of any kind; only
//      getSchedule projects `startTime` (escorts.ts:2291, formatted off
//      loads.pickupDate) and it reaches at most 10 rows for the whole book.
//      Rows this screen cannot match to a schedule row therefore have no
//      start time, and none is synthesised: they render TIME TBD, ordered
//      after the timed rows, unplaced on the hour ruler, and excluded from
//      the overlap count and the overlap duration. PROPOSED SERVER SHAPE:
//      add `startTime` (and ideally `endTime`) to the getUpcomingJobs
//      projection so the month's headline day is fully timed.
//    • STUB — SPEED CAP AND FALLBACK DURATION ARE CLIENT-SIDE. Bar length is
//      distance ÷ 45 mph, with 90 min when a row has no distance.
//      convoys.maxSpeedMph is a real column (drizzle/schema.ts:3727, int,
//      default 45) but is NOT projected by getUpcomingJobs, getSchedule or
//      getJobDetails, so it is unreachable from this screen's reads. Both
//      constants are printed on the density panel as assumptions.
//    • BOUNDED DETAIL RESOLUTION. Multi-day band end days come from
//      getJobDetails one row at a time. That loop is capped at
//      spanResolveBudget and scoped to the month actually on screen; the
//      remainder is reported as UNRESOLVED in the footer rather than fetched
//      serially while the user waits.
//
//  WEB PARITY ROUTE: /escort/schedule → client/src/pages/EscortSchedule.tsx,
//  lazy-imported client/src/App.tsx:280, mounted client/src/App.tsx:944 behind
//  guard(ESCT). That page reads escorts.getSchedule / getAvailability /
//  getUpcomingJobs / getJobsSummary (EscortSchedule.tsx:23-26) and mutates
//  escorts.updateAvailability (EscortSchedule.tsx:28) — the SAME single write,
//  so the missing second action is a platform gap, not a phone omission.
//
//  WRITE PATH · blockchainAuditTrail · WS BROADCAST: the only write reachable
//  from this screen is escorts.updateAvailability, and it touches exactly ONE
//  row — db.update(users).set({metadata}) at escorts.ts:2334. No second table,
//  no audit row (it does not even call recordAuditEvent, which escorts.ts:17
//  imports), no emit anywhere in escorts.ts:2318-2336.
//  blockchainAuditTrail = STUB·escort-lane-blockchain-audit-absent, verified for
//  THESE procedures: the table is real (drizzle/schema.ts:10018, GAP-444) and is
//  written next door by wallet.ts:1190, detentionAccessorials.ts:909 and
//  dispatch.ts:4079, but escorts.ts references it ZERO times across all 4745
//  lines. No chain anchor is appended when an escort turns a day on or off, and
//  this screen paints no chain badge it cannot source.
//
//  Offline duty (§W): reads = READ_CACHED(30m) through EscortOfflineCache.
//  When a snapshot is painted the staleness line is visible in the section rail
//  and every count carries the cached tone. Past the ttl the lattice refuses to
//  draw counts rather than present stale density as live. The availability
//  toggle is ONLINE_ONLY — the Unified Outbox is Driver-only today, so no queue
//  badge is ever drawn.
//
//  RBAC: a genuine ROLE gate, pinned hop by hop rather than asserted —
//  escorts.ts:11 imports escortProcedure under the local alias
//  `protectedProcedure`; escortProcedure = roleProcedure(ROLES.ESCORT) at
//  server/_core/trpc.ts:228; the roleProcedure factory is at
//  server/_core/trpc.ts:216. The alias is a naming artefact inside escorts.ts
//  only — it is NOT the bare authenticated procedure the name suggests, and it
//  is not described here as if it were. Registered role .escort only; every
//  procedure resolves the caller's own escort rows server-side
//  (resolveEscortUserId escorts.ts:138). No loads.rate, no shipper margin, no
//  other escort's schedule reaches this surface.
//
//  COMPONENT KIT (FD-008): cards rx20 · tiles rx16 · inner rx14 · chips rx10.
//  Radius (Theme/DesignSystem.swift:237) ships 8/12/16/20/28 and has NO 10 and
//  NO 14, so the chip value lives as a named local constant in ES15Chip below
//  rather than as a bare literal at the call site (every other surface here is a
//  card at Radius.xl 20 or a button at Radius.md 12; nothing needs the inner
//  14). This screen is a date LATTICE and an
//  hour ruler: it contains NO ListRows, so the 40x40 rx10 ListRow icon chip is
//  deliberately absent rather than invented to satisfy the clause.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire projections (screen-local, private)

private struct ES15EmptyInput: Encodable {}
private struct ES15LimitInput: Encodable { let limit: Int }
private struct ES15JobIdInput: Encodable { let jobId: String }
private struct ES15AvailabilityInput: Encodable { let dayOfWeek: Int; let available: Bool }

/// One row off `escorts.getUpcomingJobs` (escorts.ts:738).
private struct ES15UpcomingJob: Identifiable, Codable {
    let id: String
    let loadNumber: String?
    let position: String?
    let origin: String?
    let destination: String?
    let scheduledDate: String?
    let pay: Double?
    let distance: Double?
}

/// One row off `escorts.getSchedule` (escorts.ts:2265). `endTime` comes back as
/// "" from the server projection, so it is treated as absent.
private struct ES15ScheduleRow: Identifiable, Codable {
    let id: String
    let convoyName: String?
    let status: String?
    let position: String?
    let origin: String?
    let destination: String?
    let distance: Double?
    let rate: Double?
    let startTime: String?
}

/// One row off `escorts.getAvailability` (escorts.ts:2298).
private struct ES15AvailabilityDay: Identifiable, Codable {
    let dayOfWeek: Int
    let dayName: String
    let available: Bool
    var id: Int { dayOfWeek }
}

private struct ES15AvailabilityReceipt: Decodable {
    let success: Bool
    let dayOfWeek: Int
    let available: Bool
}

/// Cert wallet off `escorts.getCertificationStatus` (escorts.ts:924) — only the
/// nearest expiration is consumed, to DERIVE the renewal-window band.
private struct ES15Cert: Codable {
    let certType: String?
    let issuingState: String?
    let expirationDate: String?
}
private struct ES15CertStatus: Codable {
    let certifications: [ES15Cert]?
}

/// `escorts.getJobDetails` (escorts.ts:1979) — one field is wanted here.
private struct ES15JobSpan: Codable {
    let id: String
    let loadNumber: String?
    let pickupDate: String?
    let deliveryDate: String?
}

/// The whole month snapshot, exactly as it goes to disk for READ_CACHED(30m).
private struct ES15MonthSnapshot: Codable {
    let upcoming: [ES15UpcomingJob]
    let schedule: [ES15ScheduleRow]
    let availability: [ES15AvailabilityDay]
    let certs: [ES15Cert]
    let spans: [ES15JobSpan]
    /// Multi-day candidates in the visible month whose end day was NOT
    /// resolved because the per-row detail budget ran out. Optional so
    /// snapshots written before this field decode as zero rather than fail.
    let unresolvedSpans: Int?
}

// MARK: - Screen-local derived types

private enum ES15Position: String, CaseIterable {
    case lead, chase, steer, highPole

    init(wire: String?) {
        switch (wire ?? "").lowercased() {
        case "chase", "rear": self = .chase
        case "steer": self = .steer
        case "high_pole", "highpole", "pole": self = .highPole
        default: self = .lead
        }
    }
    var label: String {
        switch self {
        case .lead: return "LEAD"
        case .chase: return "CHASE"
        case .steer: return "STEER"
        case .highPole: return "HIGH-POLE"
        }
    }
    /// Design-directive canon: LEAD blue · CHASE purple · STEER amber ·
    /// HIGH-POLE orange.
    var ink: Color {
        switch self {
        case .lead: return Brand.blue
        case .chase: return Brand.escort
        case .steer: return Brand.warning
        case .highPole: return Brand.hazmat
        }
    }
}

private struct ES15Band: Identifiable, Equatable {
    enum Kind: Equatable {
        case assignment(tail: String)
        case certRenewal(label: String)

        var tint: Color {
            switch self {
            case .assignment: return Brand.escort
            case .certRenewal: return Brand.warning
            }
        }
        /// Printed on the band. The reader must always know whether they are
        /// looking at a stored fact or a client-side inference.
        var provenance: String {
            switch self {
            case .assignment: return "ASSIGNMENT"
            case .certRenewal: return "DERIVED"
            }
        }
    }
    let id: String
    let firstDay: Int
    let lastDay: Int
    let title: String
    let kind: Kind
    func covers(_ day: Int) -> Bool { day >= firstDay && day <= lastDay }
}

private struct ES15DayMove: Identifiable, Equatable {
    let id: String
    let index: Int
    /// nil when NO server-supplied start time exists for this row. The screen
    /// never fills this in — getUpcomingJobs carries no clock at all
    /// (escorts.ts:754-762) and getSchedule reaches at most 10 rows.
    let startMinutes: Int?
    /// Client-side estimate only — see ES15Assumption.
    let durationMinutes: Int
    let position: ES15Position

    var hasTime: Bool { startMinutes != nil }
    var endMinutes: Int? { startMinutes.map { min($0 + durationMinutes, 23 * 60 + 59) } }
    var startLabel: String {
        guard let s = startMinutes else { return "TIME TBD" }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// The two numbers this screen assumes because no read on it carries them.
/// Both are printed on the surface so nothing here looks server-derived.
private enum ES15Assumption {
    /// convoys.maxSpeedMph EXISTS (drizzle/schema.ts:3727, int, default 45)
    /// but is NOT projected by getUpcomingJobs, getSchedule or getJobDetails,
    /// so this screen cannot read the real cap for a given convoy.
    static let escortCapMph = 45
    /// Used only when a row has no distance at all.
    static let fallbackMinutes = 90
}

private struct ES15Overlap: Identifiable, Equatable {
    let id: String
    let firstIndex: Int
    let secondIndex: Int
    let minutes: Int
}

/// 14-kit radii that `Radius` does not carry.
/// Radius (Theme/DesignSystem.swift:237) ships 8 / 12 / 16 / 20 / 28 — there is
/// no 10 and no 14 — so the chip value lives here as a named constant rather
/// than as a bare literal scattered through the body. Nothing on this screen
/// needs the inner-surface 14: every surface here is a card (20) or a chip (10).
/// This screen is a date lattice with no ListRows, so there is no 40x40 icon
/// chip: the side length the ListRow anatomy would use is deliberately absent
/// rather than invented (FD-008).
private enum ES15Chip {
    static let radius: CGFloat = 10   // chip · SVG rx10
}

// MARK: - Screen

struct EscortSchedule: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    @State private var upcoming: [ES15UpcomingJob] = []
    @State private var scheduleRows: [ES15ScheduleRow] = []
    @State private var availability: [ES15AvailabilityDay] = []
    @State private var certs: [ES15Cert] = []
    @State private var spans: [ES15JobSpan] = []

    @State private var loading = true
    @State private var errorMessage: String?
    @State private var writeInFlight: Int?
    /// nil == live read. Non-nil paints the staleness line and tints counts.
    @State private var cacheAge: TimeInterval?
    @State private var focusedDay: Int?
    @State private var anchorMonth = Date()

    /// READ_CACHED ttl for the month snapshot, per the §W declaration in the
    /// ES-15 `<desc>`.
    private let cacheTTL: TimeInterval = 30 * 60
    private let cacheKey = "escort.schedule.month"

    /// Hard ceiling on per-row `getJobDetails` calls in one load. The month
    /// lattice can only draw a handful of multi-day bands legibly, so nothing
    /// beyond this is worth blocking the load for — the remainder is rendered
    /// as an unresolved count, not fetched serially.
    private static let spanResolveBudget = 8

    /// Multi-day candidates in the visible month whose end day was not fetched.
    @State private var unresolvedSpanCount = 0

    private var isDark: Bool { colorScheme == .dark }
    private var calendar: Calendar { Calendar(identifier: .gregorian) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading && upcoming.isEmpty {
                    LifecycleCard { Text("Loading the month…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else {
                    if let errorMessage {
                        Text(errorMessage).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    sectionRail
                    monthLattice
                    bandsReadOnlyNote
                    densityHeader
                    dayDensityPanel
                    availabilityHeader
                    availabilityRail
                    esangRow
                    honestyFooter
                }
                Color.clear.frame(height: 110)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) { saveBar }
        .task { await load() }
        .eusoRefreshable { await load(forceNetwork: true) }
    }

    // MARK: Header

    // HOME type ramp: H1 34/700/-0.6. The month ledger used to sit ABOVE the H1
    // as a right-of-centre caption row; at 34 the headline runs the full width
    // of the safe area and collided with it, so the ledger was RE-ANCHORED onto
    // the lattice pager row (its own month card) rather than the H1 being cut.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ESCORT · SCHEDULE").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text(monthLabel).font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            Text(headlineText).font(.system(size: 34, weight: .bold)).tracking(-0.6)
                .foregroundStyle(LinearGradient.diagonal)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(subheadText).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            IridescentHairline()
        }
    }

    private var monthLabel: String {
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"
        return f.string(from: anchorMonth).uppercased()
    }
    /// Month totals. Sits on the lattice pager row, where the month name is
    /// already centred — so the label itself is not repeated here.
    private var ledgerLine: String {
        "\(bookedTotal) BOOKED · \(blockedDayCount) BLOCKED"
    }
    private var headlineText: String {
        guard let day = focusedDay, let count = countsByDay[day], count > 0 else {
            return "\(bookedTotal) moves this month"
        }
        return "\(count) moves on \(weekdayShort(day)) \(day)"
    }
    private var subheadText: String {
        // A suppressed figure states its reason rather than showing a number
        // computed over rows that never carried a clock.
        if let reason = overlapSuppressionReason { return reason }
        let tbd = focusedUntimedCount > 0 ? " · \(focusedUntimedCount) TIME TBD" : ""
        let overlaps = focusedOverlaps
        guard !overlaps.isEmpty else {
            return "No double-booking across \(focusedTimedMoves.count) timed moves" + tbd
        }
        let total = overlaps.reduce(0) { $0 + $1.minutes }
        return "\(overlaps.count) overlaps · \(total / 60) h \(total % 60) m double-booked "
            + "across \(focusedTimedMoves.count) timed moves" + tbd
    }

    private var sectionRail: some View {
        HStack {
            Text("MONTH DENSITY · \(monthLabel)").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            // The §W honesty line — visible ONLY when painting a snapshot.
            if let cacheAge {
                HStack(spacing: 5) {
                    Circle().fill(Brand.warning).frame(width: 6, height: 6)
                    Text(EscortOfflineCache.stalenessLine(age: cacheAge))
                        .font(.system(size: 8, weight: .bold).monospaced())
                        .foregroundStyle(Brand.warning)
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(palette.bgCard))
                .overlay(Capsule().strokeBorder(palette.borderFaint))
            }
        }
    }

    // MARK: Month lattice

    private var monthLattice: some View {
        VStack(spacing: 0) {
            HStack {
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                }.buttonStyle(.plain)
                // The month ledger re-anchored off the header for the 34-point H1.
                Text(ledgerLine).font(.system(size: 8, weight: .bold).monospaced())
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                Text(monthLabel).font(.system(size: 11, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                }.buttonStyle(.plain)
            }
            .padding(.top, Space.s3)

            HStack(spacing: 0) {
                ForEach(Array(["SUN","MON","TUE","WED","THU","FRI","SAT"].enumerated()), id: \.offset) { idx, name in
                    Text(name).font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(idx == 6 ? Brand.blue : palette.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, Space.s3)

            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.top, 6)

            GeometryReader { geo in
                let pitch = geo.size.width / 7
                VStack(spacing: 4) {
                    ForEach(0..<6, id: \.self) { week in
                        weekRow(week: week, pitch: pitch)
                    }
                }
            }
            .frame(height: 6 * 44)
            .padding(.top, 4)

            densityLegend.padding(.top, Space.s2).padding(.bottom, Space.s3)
        }
        .padding(.horizontal, Space.s3)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
    }

    private func weekRow(week: Int, pitch: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { col in
                    dayCell(ordinal: week * 7 + col).frame(width: pitch, height: 40)
                }
            }
            ForEach(bands(inWeek: week), id: \.band.id) { slice in
                bandCapsule(slice, pitch: pitch)
                    .offset(x: CGFloat(slice.firstCol) * pitch + 3, y: 22)
            }
        }
        .frame(height: 40)
    }

    /// Day-of-month for a lattice ordinal, and whether it is in the anchor month.
    private func dayInfo(ordinal: Int) -> (day: Int, inMonth: Bool) {
        let comps = calendar.dateComponents([.year, .month], from: anchorMonth)
        guard let first = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: anchorMonth) else { return (0, false) }
        let leading = calendar.component(.weekday, from: first) - 1
        let n = ordinal - leading + 1
        if n >= 1 && n <= range.count { return (n, true) }
        if n < 1 {
            let prev = calendar.date(byAdding: .month, value: -1, to: first) ?? first
            let prevCount = calendar.range(of: .day, in: .month, for: prev)?.count ?? 30
            return (prevCount + n, false)
        }
        return (n - range.count, false)
    }

    private func dayCell(ordinal: Int) -> some View {
        let info = dayInfo(ordinal: ordinal)
        let count = info.inMonth ? (countsByDay[info.day] ?? 0) : 0
        let blocked = info.inMonth && bandList.contains { $0.covers(info.day) }
        let isToday = info.inMonth && calendar.isDateInToday(dateFor(day: info.day) ?? .distantPast)
        let isFocused = info.inMonth && info.day == focusedDay

        return Button {
            if info.inMonth { focusedDay = info.day }
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: ES15Chip.radius, style: .continuous)
                    .fill(cellWash(blocked: blocked, isToday: isToday, isFocused: isFocused))
                    .overlay {
                        if isFocused {
                            RoundedRectangle(cornerRadius: ES15Chip.radius, style: .continuous)
                                .strokeBorder(LinearGradient.primary, lineWidth: 1.6)
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 2) {
                        Text("\(info.day)")
                            .font(.system(size: 11, weight: isToday || isFocused ? .heavy : .bold).monospaced())
                            .foregroundStyle(dayInk(info: info, blocked: blocked, isToday: isToday, count: count))
                        Spacer(minLength: 0)
                        if count >= 3 && !blocked {
                            Text("\(count)").font(.system(size: 8, weight: .heavy).monospaced())
                                .foregroundStyle(isFocused ? Brand.escort : (count >= 6 ? Brand.escort : Brand.warning))
                        }
                    }
                    if !blocked && count > 0 { densityComb(count: count) }
                }
                .padding(.horizontal, 6).padding(.top, 4)
            }
            .frame(height: 36)
            .opacity(cacheAge == nil ? 1 : 0.82)
        }
        .buttonStyle(.plain)
        .disabled(!info.inMonth)
    }

    /// One tick per move, capped at 12 — the comb the twins draw.
    private func densityComb(count: Int) -> some View {
        HStack(spacing: 1.1) {
            ForEach(0..<min(count, 12), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 0.9, style: .continuous)
                    .fill(densityInk(count)).frame(width: 1.8, height: 7)
            }
        }
    }
    private func densityInk(_ count: Int) -> Color {
        if count >= 6 { return Brand.escort }
        if count >= 3 { return Brand.warning }
        return Brand.blue
    }
    private func cellWash(blocked: Bool, isToday: Bool, isFocused: Bool) -> Color {
        if blocked { return Brand.warning.opacity(isDark ? 0.16 : 0.10) }
        if isToday { return Brand.blue.opacity(isDark ? 0.16 : 0.07) }
        if isFocused { return Brand.magenta.opacity(isDark ? 0.16 : 0.07) }
        return .clear
    }
    private func dayInk(info: (day: Int, inMonth: Bool), blocked: Bool, isToday: Bool, count: Int) -> Color {
        if !info.inMonth { return palette.textTertiary.opacity(0.5) }
        if blocked { return Brand.warning }
        if isToday { return Brand.blue }
        if count == 0 { return palette.textTertiary }
        return palette.textPrimary
    }

    private func bandCapsule(_ slice: (band: ES15Band, firstCol: Int, lastCol: Int,
                                       continuesLeft: Bool, continuesRight: Bool),
                             pitch: CGFloat) -> some View {
        let width = CGFloat(slice.lastCol - slice.firstCol + 1) * pitch - 6
        return HStack(spacing: 3) {
            Text(slice.continuesLeft ? "… \(slice.band.lastDay)"
                                     : "\(slice.band.title) · \(slice.band.kind.provenance)")
                .font(.system(size: 6.5, weight: .heavy)).tracking(0.3)
                .foregroundStyle(slice.band.kind.tint).lineLimit(1)
            if slice.continuesRight {
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 6, weight: .heavy))
                    .foregroundStyle(slice.band.kind.tint)
            }
        }
        .padding(.horizontal, 6)
        .frame(width: max(width, 30), height: 13, alignment: slice.continuesLeft ? .center : .leading)
        .background(Capsule().fill(slice.band.kind.tint.opacity(isDark ? 0.34 : 0.30)))
        .overlay(Capsule().strokeBorder(slice.band.kind.tint.opacity(0.65),
                                        style: StrokeStyle(lineWidth: 1,
                                                           dash: slice.continuesLeft ? [3, 2] : [])))
    }

    private var densityLegend: some View {
        HStack(spacing: Space.s3) {
            legendSwatch(Brand.blue, "1–2")
            legendSwatch(Brand.warning, "3–5")
            legendSwatch(Brand.escort, "6+")
            Spacer()
            Text("1 TICK = 1 MOVE").font(.system(size: 7, weight: .bold).monospaced())
                .foregroundStyle(palette.textTertiary)
        }
    }
    private func legendSwatch(_ ink: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(ink).frame(width: 7, height: 7)
            Text(label).font(.system(size: 7, weight: .bold).monospaced())
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: The bands-are-read-only note
    //
    // No procedure writes a date range and no blackout column exists. The
    // affordance itself now lives in the action pair at the foot of the screen,
    // disabled and labelled, so the shortfall is stated where a user would
    // otherwise reach for it; this line explains the bands they can already see.

    private var bandsReadOnlyNote: some View {
        HStack {
            Text("BLOCKING BANDS · VIEW ONLY")
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text("SCHEDULING UNAVAILABLE").font(.system(size: 7.5, weight: .bold).monospaced())
                .foregroundStyle(palette.textTertiary)
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Blocked-date scheduling is unavailable. Use weekly availability or contact dispatch to coordinate a specific date.")
    }

    // MARK: Day density panel

    private var densityHeader: some View {
        HStack {
            Text(focusedDay.map { "\(weekdayShort($0).uppercased()) \($0) · DAY DENSITY" } ?? "DAY DENSITY")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(densityHeaderRight).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(focusedOverlaps.isEmpty ? palette.textTertiary : Brand.danger)
        }
    }
    private var densityHeaderRight: String {
        let moves = focusedMoves
        let tbd = focusedUntimedCount > 0 ? " · \(focusedUntimedCount) TBD" : ""
        if overlapSuppressionReason != nil { return "\(moves.count) MOVES · NO OVERLAP MATH" }
        guard !focusedOverlaps.isEmpty else { return "\(moves.count) MOVES" + tbd }
        let total = focusedOverlaps.reduce(0) { $0 + $1.minutes }
        return "\(focusedOverlaps.count) OVERLAPS · \(total / 60)H\(String(format: "%02d", total % 60))M" + tbd
    }

    private var dayDensityPanel: some View {
        // Already ordered by focusedMoves: timed rows in clock order, then
        // every TIME TBD row. No second sort — an optional start has no place
        // in a comparison.
        let moves = focusedMoves
        let dayStart = 5 * 60, dayEnd = 21 * 60
        return VStack(alignment: .leading, spacing: 0) {
            if moves.isEmpty {
                Text("Nothing booked on this day.").font(EType.caption)
                    .foregroundStyle(palette.textSecondary).padding(.vertical, Space.s4)
            } else {
                GeometryReader { geo in
                    let gutter: CGFloat = 74
                    let track = max(geo.size.width - gutter, 100)
                    let span = CGFloat(dayEnd - dayStart)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            Spacer().frame(width: gutter)
                            ForEach([5, 8, 11, 14, 17, 20], id: \.self) { hour in
                                Text(String(format: "%02d", hour))
                                    .font(.system(size: 7, weight: .bold).monospaced())
                                    .foregroundStyle(palette.textTertiary)
                                    .frame(width: track / 6, alignment: .leading)
                            }
                        }
                        ForEach(moves) { move in
                            HStack(spacing: 0) {
                                Text(String(format: "%02d", move.index))
                                    .font(.system(size: 6.5, weight: .bold).monospaced())
                                    .foregroundStyle(palette.textTertiary)
                                    .frame(width: 18, alignment: .leading)
                                Text(move.startLabel)
                                    .font(.system(size: 6.5, weight: .bold).monospaced())
                                    .foregroundStyle(move.hasTime ? move.position.ink : palette.textTertiary)
                                    .frame(width: gutter - 18, alignment: .leading)
                                ZStack(alignment: .leading) {
                                    Color.clear.frame(height: 6)
                                    if let start = move.startMinutes, let end = move.endMinutes {
                                        Capsule().fill(move.position.ink)
                                            .frame(width: max(track * CGFloat(end - start) / span, 6),
                                                   height: 6)
                                            .offset(x: track * CGFloat(start - dayStart) / span)
                                    } else {
                                        // No server clock: an unplaced capsule
                                        // sitting outside the ruler, never a
                                        // bar at an hour the server never sent.
                                        Capsule()
                                            .strokeBorder(palette.textTertiary.opacity(0.65),
                                                          style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                            .frame(width: min(track, 96), height: 8)
                                    }
                                }
                                .frame(width: track, alignment: .leading)
                            }
                            .frame(height: 10.5)
                        }
                    }
                }
                .frame(height: CGFloat(moves.count) * 10.5 + 18)

                Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.top, Space.s2)

                HStack(spacing: 6) {
                    ForEach(positionSplit, id: \.0.rawValue) { pos, count in
                        Text("\(pos.label) \(count)").font(.system(size: 7.5, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(pos.ink)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(pos.ink.opacity(isDark ? 0.24 : 0.16)))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, Space.s2)

                assumptionNote.padding(.top, Space.s2)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
    }

    /// Everything on this panel that is NOT a stored server value, named on
    /// the panel itself so no bar reads as server-derived.
    private var assumptionNote: some View {
        VStack(alignment: .leading, spacing: 2) {
            if focusedUntimedCount > 0 {
                Text("\(focusedUntimedCount) of \(focusedMoves.count) moves have no start time. They remain unplaced and are excluded from overlap totals.")
                    .font(.system(size: 7.5, weight: .semibold).monospaced())
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("ESTIMATED DURATION · Timed bars use distance at \(ES15Assumption.escortCapMph) mph; moves without distance use \(ES15Assumption.fallbackMinutes) minutes. Confirm the schedule before relying on overlaps.")
                .font(.system(size: 7.5, weight: .semibold).monospaced())
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Availability rail (ONLINE_ONLY write)

    private var availabilityHeader: some View {
        HStack {
            Text("AVAILABILITY · DAY OF WEEK").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text("ONLINE-ONLY").font(.system(size: 7, weight: .heavy)).tracking(0.4)
                .foregroundStyle(Brand.danger)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Brand.danger.opacity(isDark ? 0.16 : 0.10)))
        }
    }

    private var availabilityRail: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { dow in availabilityPill(dow) }
            }
            Text("ONE TOGGLE = ONE WRITE · NO BATCH INPUT · NO DISPATCH FAN-OUT YET")
                .font(.system(size: 7.5, weight: .semibold).monospaced())
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
    }

    private func availabilityPill(_ dow: Int) -> some View {
        let names = ["SUN","MON","TUE","WED","THU","FRI","SAT"]
        let on = availability.first { $0.dayOfWeek == dow }?.available ?? false
        let saturday = dow == 6
        let tint: Color = saturday ? Brand.escort : Brand.blue
        let ink: Color = on ? tint : palette.textTertiary

        return Button {
            Task { await toggle(dayOfWeek: dow, to: !on) }
        } label: {
            VStack(spacing: 2) {
                Text(names[dow]).font(.system(size: 9, weight: .heavy)).foregroundStyle(ink)
                Text(on ? "ON" : "OFF").font(.system(size: 7.5, weight: .heavy).monospaced())
                    .foregroundStyle(ink)
            }
            .frame(maxWidth: .infinity).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: ES15Chip.radius, style: .continuous)
                .fill(on ? tint.opacity(isDark ? 0.22 : 0.14) : palette.bgCardSoft))
            .overlay(RoundedRectangle(cornerRadius: ES15Chip.radius, style: .continuous)
                .strokeBorder(on ? tint.opacity(0.45) : palette.borderSoft))
            .opacity(writeInFlight == dow ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(writeInFlight != nil)
    }

    // MARK: ESANG + honesty footer

    private var esangRow: some View {
        HStack(spacing: Space.s3) {
            Circle().fill(LinearGradient.diagonal).frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("ESANG").font(.system(size: 9.5, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(esangHeadline).font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(palette.textPrimary).lineLimit(1)
                }
                Text(esangDetail).font(.system(size: 8)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s3)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(LinearGradient.diagonal).frame(width: 3)
        }
    }
    private var esangHeadline: String {
        guard let worst = focusedOverlaps.max(by: { $0.minutes < $1.minutes }), let day = focusedDay else {
            return "· Month sits inside your usual load"
        }
        return "· \(weekdayShort(day)) \(day) carries a \(worst.minutes)-min overlap"
    }
    private var esangDetail: String {
        guard let worst = focusedOverlaps.max(by: { $0.minutes < $1.minutes }) else {
            return "No lane on the peak day collides with another."
        }
        return "Releasing move \(worst.secondIndex) clears it."
    }

    /// The two server-side caps, stated on the surface rather than hidden.
    private var honestyFooter: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Counts combine your accepted jobs with the schedule read, which returns at most 10 rows.")
                .font(.system(size: 7.5, weight: .semibold).monospaced())
                .foregroundStyle(palette.textTertiary)
            Text("A day busier than that under-counts here — treat a full day as at least what you see.")
                .font(.system(size: 7.5, weight: .semibold).monospaced())
                .foregroundStyle(palette.textTertiary)
            if unresolvedSpanCount > 0 {
                Text("\(unresolvedSpanCount) multi-day move\(unresolvedSpanCount == 1 ? "" : "s") UNRESOLVED — no end day was fetched for \(unresolvedSpanCount == 1 ? "it" : "them"), so no band is drawn. They still count as day ticks.")
                    .font(.system(size: 7.5, weight: .semibold).monospaced())
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Action pair
    //
    // PRIMARY   re-commits the seven day-of-week rows through
    //           escorts.updateAvailability (escorts.ts:2318). That procedure
    //           takes ONE day per call and there is no batch input, so the
    //           button says so on its face rather than implying a single write.
    // SECONDARY is DISABLED and carries its own reason. No escort-scoped
    //           date-range block mutation exists anywhere in the tree; the only
    //           candidate, availability.blockTime (availability.ts:202), is
    //           isolatedProcedure (trpc.ts:517 — no role gate) writing
    //           driver_availability_blocks, which no escorts.* read returns.
    //           Nothing is invented to fill the pair.

    private var saveBar: some View {
        HStack(spacing: 10) {
            Button {
                Task { await saveAllAvailability() }
            } label: {
                VStack(spacing: 1) {
                    Text("Save availability")
                        .font(.system(size: 13, weight: .heavy)).tracking(0.3)
                    Text(availabilitySummary)
                        .font(.system(size: 6.5, weight: .bold).monospaced())
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .disabled(writeInFlight != nil)
            .opacity(writeInFlight == nil ? 1 : 0.6)

            VStack(spacing: 1) {
                Text("Block dates").font(.system(size: 12, weight: .heavy)).tracking(0.3)
                Text("NOT AVAILABLE").font(.system(size: 6.5, weight: .bold).monospaced())
            }
            .foregroundStyle(palette.textTertiary)
            .frame(width: 154, height: 40)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.textTertiary.opacity(0.45),
                              style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .allowsHitTesting(false)
            .accessibilityLabel("Block dates is unavailable. Use weekly availability or contact dispatch to coordinate a specific date.")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private var availabilitySummary: String {
        let on = availability.filter { $0.available }.count
        return "\(on) OF 7 DAYS ON · ONE WRITE PER DAY"
    }

    // MARK: Derived data

    private var countsByDay: [Int: Int] {
        var seen = Set<String>()
        var counts: [Int: Int] = [:]
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        for job in upcoming {
            guard !seen.contains(job.id), let key = job.scheduledDate, let d = f.date(from: key) else { continue }
            seen.insert(job.id)
            guard calendar.isDate(d, equalTo: anchorMonth, toGranularity: .month) else { continue }
            counts[calendar.component(.day, from: d), default: 0] += 1
        }
        return counts
    }
    private var bookedTotal: Int { countsByDay.values.reduce(0, +) }

    /// Bands: multi-day ASSIGNMENT spans (real pickup→delivery) plus a cert
    /// renewal window DERIVED from a real expiry. Nothing else — there is no
    /// blackout store to read.
    private var bandList: [ES15Band] {
        var out: [ES15Band] = []
        let iso = ISO8601DateFormatter()
        let plain = DateFormatter(); plain.dateFormat = "yyyy-MM-dd"

        for span in spans {
            guard let pRaw = span.pickupDate, let dRaw = span.deliveryDate,
                  let p = iso.date(from: pRaw) ?? plain.date(from: String(pRaw.prefix(10))),
                  let d = iso.date(from: dRaw) ?? plain.date(from: String(dRaw.prefix(10))),
                  calendar.isDate(p, equalTo: anchorMonth, toGranularity: .month) else { continue }
            let first = calendar.component(.day, from: p)
            let last = calendar.component(.day, from: d)
            guard last > first else { continue }        // single-day moves are ticks, not bands
            let tail = String((span.loadNumber ?? span.id).suffix(5))
            out.append(ES15Band(id: "move-\(span.id)", firstDay: first, lastDay: last,
                                title: "\(last - first + 1)-DAY MOVE · \(tail)",
                                kind: .assignment(tail: tail)))
        }

        if let cert = certs.compactMap({ c -> (Date, ES15Cert)? in
            guard let raw = c.expirationDate,
                  let d = iso.date(from: raw) ?? plain.date(from: String(raw.prefix(10))) else { return nil }
            return (d, c)
        }).min(by: { $0.0 < $1.0 }),
           calendar.isDate(cert.0, equalTo: anchorMonth, toGranularity: .month) {
            // A DERIVED window, not a stored blackout — labelled as such.
            let expiryDay = calendar.component(.day, from: cert.0)
            let state = cert.1.issuingState ?? "—"
            out.append(ES15Band(id: "cert-window", firstDay: max(1, expiryDay - 4), lastDay: expiryDay,
                                title: "\(state) CERT RENEWAL",
                                kind: .certRenewal(label: cert.1.certType ?? "Pilot/Escort")))
        }
        return out
    }

    private var blockedDayCount: Int {
        var days = Set<Int>()
        for b in bandList where b.lastDay >= b.firstDay {
            for d in b.firstDay...b.lastDay { days.insert(d) }
        }
        return days.count
    }

    private func bands(inWeek week: Int) -> [(band: ES15Band, firstCol: Int, lastCol: Int,
                                              continuesLeft: Bool, continuesRight: Bool)] {
        let comps = calendar.dateComponents([.year, .month], from: anchorMonth)
        guard let first = calendar.date(from: comps) else { return [] }
        let leading = calendar.component(.weekday, from: first) - 1
        let rowFirst = week * 7 - leading + 1
        let rowLast = rowFirst + 6
        return bandList.compactMap { band in
            let lo = max(band.firstDay, rowFirst), hi = min(band.lastDay, rowLast)
            guard lo <= hi else { return nil }
            return (band, lo - rowFirst, hi - rowFirst,
                    band.firstDay < rowFirst, band.lastDay > rowLast)
        }
    }

    /// Lanes for the focused day.
    ///
    /// A clock is drawn ONLY where the server supplied one. getUpcomingJobs —
    /// the read that populates this whole lattice — returns no time field at
    /// all (escorts.ts:754-762: id / loadNumber / position / origin /
    /// destination / scheduledDate / pay / distance), and getSchedule, which
    /// does project `startTime` (escorts.ts:2291, off loads.pickupDate), is
    /// hard-capped at 10 rows for the entire book (escorts.ts:2282). Rows the
    /// schedule read cannot reach therefore have NO start time, and this
    /// screen refuses to invent one: they render as TIME TBD, ordered after
    /// every timed row so the ruler stays readable.
    private var focusedMoves: [ES15DayMove] {
        guard let day = focusedDay else { return [] }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let sameDay = upcoming.filter { job in
            guard let key = job.scheduledDate, let d = f.date(from: key) else { return false }
            return calendar.isDate(d, equalTo: anchorMonth, toGranularity: .month)
                && calendar.component(.day, from: d) == day
        }
        let clock = DateFormatter(); clock.dateFormat = "hh:mm a"

        // Resolve each row's real start (or nothing) and its estimated length.
        let resolved: [(job: ES15UpcomingJob, start: Int?, minutes: Int, pos: ES15Position)] =
            sameDay.map { job in
                let row = scheduleRows.first { $0.id == job.id }
                var start: Int? = nil
                if let raw = row?.startTime, !raw.isEmpty, let t = clock.date(from: raw) {
                    start = calendar.component(.hour, from: t) * 60 + calendar.component(.minute, from: t)
                }
                let miles = job.distance ?? row?.distance ?? 0
                let minutes = miles > 0
                    ? Int((miles / Double(ES15Assumption.escortCapMph) * 60).rounded())
                    : ES15Assumption.fallbackMinutes
                return (job: job, start: start, minutes: minutes,
                        pos: ES15Position(wire: job.position ?? row?.position))
            }

        // Timed rows first, in clock order; untimed rows after them.
        let timed = resolved.filter { $0.start != nil }.sorted { ($0.start ?? 0) < ($1.start ?? 0) }
        let untimed = resolved.filter { $0.start == nil }
        return (timed + untimed).enumerated().map { idx, r in
            ES15DayMove(id: r.job.id, index: idx + 1,
                        startMinutes: r.start,
                        durationMinutes: r.minutes,
                        position: r.pos)
        }
    }

    /// Rows the server actually gave a clock to. Everything derived from time
    /// is computed over THIS set only.
    private var focusedTimedMoves: [ES15DayMove] { focusedMoves.filter { $0.hasTime } }
    private var focusedUntimedCount: Int { focusedMoves.count - focusedTimedMoves.count }

    /// Overlap is arithmetic over real clocks or it is not computed. A row
    /// with no server start time cannot collide with anything here.
    private var focusedOverlaps: [ES15Overlap] {
        let sorted = focusedTimedMoves.sorted { ($0.startMinutes ?? 0) < ($1.startMinutes ?? 0) }
        var out: [ES15Overlap] = []
        for i in 0..<max(0, sorted.count - 1) {
            let a = sorted[i], b = sorted[i + 1]
            guard let aEnd = a.endMinutes, let bStart = b.startMinutes else { continue }
            let m = aEnd - bStart
            if m > 0 { out.append(ES15Overlap(id: "\(a.id)-\(b.id)", firstIndex: a.index, secondIndex: b.index, minutes: m)) }
        }
        return out
    }

    /// Why an overlap figure is absent, when it is. nil == the figure stands.
    private var overlapSuppressionReason: String? {
        guard focusedDay != nil, !focusedMoves.isEmpty else { return nil }
        // Only a suppression when the missing clocks are what makes the
        // figure impossible. A fully-timed day needs no excuse.
        guard focusedUntimedCount > 0, focusedTimedMoves.count < 2 else { return nil }
        return "Overlap unavailable — \(focusedUntimedCount) of \(focusedMoves.count) moves have no start time."
    }

    private var positionSplit: [(ES15Position, Int)] {
        ES15Position.allCases.map { p in (p, focusedMoves.filter { $0.position == p }.count) }
            .filter { $0.1 > 0 }
    }

    private func dateFor(day: Int) -> Date? {
        var comps = calendar.dateComponents([.year, .month], from: anchorMonth)
        comps.day = day
        return calendar.date(from: comps)
    }
    private func weekdayShort(_ day: Int) -> String {
        guard let d = dateFor(day: day) else { return "" }
        let f = DateFormatter(); f.dateFormat = "EEE"
        return f.string(from: d)
    }
    private func shiftMonth(_ delta: Int) {
        if let d = calendar.date(byAdding: .month, value: delta, to: anchorMonth) {
            anchorMonth = d
            focusedDay = nil
        }
    }

    // MARK: Data — READ_CACHED(30m)

    private func load(forceNetwork: Bool = false) async {
        loading = true
        defer { loading = false }

        // Paint the last-good snapshot first so the month is never a skeleton,
        // and keep its age visible for as long as it is what the user is
        // reading. A live read below replaces it and clears the staleness line.
        if !forceNetwork,
           let snap = EscortOfflineCache.load(ES15MonthSnapshot.self, key: cacheKey, ttl: cacheTTL) {
            apply(snap.value)
            cacheAge = snap.age
        }

        do {
            async let up: [ES15UpcomingJob] = EusoTripAPI.shared.query(
                "escorts.getUpcomingJobs", input: ES15LimitInput(limit: 200))
            async let sched: [ES15ScheduleRow] = EusoTripAPI.shared.query(
                "escorts.getSchedule", input: ES15EmptyInput())
            async let avail: [ES15AvailabilityDay] = EusoTripAPI.shared.query(
                "escorts.getAvailability", input: ES15EmptyInput())

            let fetchedUpcoming = try await up
            let fetchedSchedule = try await sched
            let fetchedAvailability = try await avail
            let certStatus: ES15CertStatus? = try? await EusoTripAPI.shared.query(
                "escorts.getCertificationStatus", input: ES15EmptyInput())

            // Multi-day bands need loads.deliveryDate, which neither schedule
            // read projects — one getJobDetails per candidate row. That read
            // is BOUNDED here: only rows that could plausibly span (distance
            // over a single shift) AND that fall inside the month actually
            // being drawn, and never more than `spanResolveBudget` of them.
            // Anything past the budget is not fetched and not guessed — it is
            // reported as unresolved on the surface.
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
            let candidates = fetchedUpcoming.filter { job in
                guard (job.distance ?? 0) > 400 else { return false }
                guard let key = job.scheduledDate, let d = df.date(from: key) else { return false }
                return calendar.isDate(d, equalTo: anchorMonth, toGranularity: .month)
            }
            let budgeted = candidates.prefix(Self.spanResolveBudget)
            var fetchedSpans: [ES15JobSpan] = []
            for job in budgeted {
                if let span: ES15JobSpan = try? await EusoTripAPI.shared.query(
                    "escorts.getJobDetails", input: ES15JobIdInput(jobId: job.id)) {
                    fetchedSpans.append(span)
                }
            }
            let unresolved = max(0, candidates.count - budgeted.count)

            let snapshot = ES15MonthSnapshot(upcoming: fetchedUpcoming,
                                             schedule: fetchedSchedule,
                                             availability: fetchedAvailability,
                                             certs: certStatus?.certifications ?? [],
                                             spans: fetchedSpans,
                                             unresolvedSpans: unresolved)
            apply(snapshot)
            cacheAge = nil                    // live read — the staleness line goes away
            errorMessage = nil
            EscortOfflineCache.store(snapshot, key: cacheKey)

            if focusedDay == nil { focusedDay = peakDay() }
        } catch {
            // Honest failure: keep the snapshot on screen WITH its staleness
            // line, and say the numbers are not live. Never silently re-present
            // cached density as fresh.
            if cacheAge == nil {
                errorMessage = (error as? EusoTripAPIError)?.errorDescription
                    ?? "Couldn't load the month. Pull to retry."
            } else {
                errorMessage = "Showing the last good month — the live read failed."
            }
        }
    }

    private func apply(_ snap: ES15MonthSnapshot) {
        upcoming = snap.upcoming
        scheduleRows = snap.schedule
        availability = snap.availability
        certs = snap.certs
        spans = snap.spans
        unresolvedSpanCount = snap.unresolvedSpans ?? 0
        if focusedDay == nil { focusedDay = peakDay() }
    }

    private func peakDay() -> Int? {
        countsByDay.max(by: { $0.value < $1.value })?.key
    }

    /// ONLINE_ONLY — one day per call, because the procedure takes one day.
    private func toggle(dayOfWeek: Int, to value: Bool) async {
        guard writeInFlight == nil else { return }
        writeInFlight = dayOfWeek
        defer { writeInFlight = nil }
        do {
            let receipt: ES15AvailabilityReceipt = try await EusoTripAPI.shared.mutation(
                "escorts.updateAvailability",
                input: ES15AvailabilityInput(dayOfWeek: dayOfWeek, available: value))
            if let idx = availability.firstIndex(where: { $0.dayOfWeek == receipt.dayOfWeek }) {
                availability[idx] = ES15AvailabilityDay(dayOfWeek: receipt.dayOfWeek,
                                                        dayName: availability[idx].dayName,
                                                        available: receipt.available)
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? EusoTripAPIError)?.errorDescription
                ?? "Availability needs a connection — escort writes are not queued yet."
        }
    }

    /// Re-commits all seven rows. escorts.updateAvailability takes ONE day per
    /// call and declares no batch input (escorts.ts:2318), so this is seven
    /// sequential mutations and the button says as much. ONLINE_ONLY: there is
    /// no escort outbox, so a failure surfaces as an error rather than a queue.
    private func saveAllAvailability() async {
        guard writeInFlight == nil else { return }
        for day in availability {
            await toggle(dayOfWeek: day.dayOfWeek, to: day.available)
            if errorMessage != nil { return }
        }
    }
}

// MARK: - Registered surface wrapper

struct EscortScheduleScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortSchedule()
        } nav: {
            // Canonical escort bar HOME · ASSIGNMENTS · [orb] · CORRIDOR · ME,
            // built from the real enum (EscortNavController.swift: EscortNavTab
            // :32, orbLabels :63, leading/trailing NavSlots :77-85). Schedule is
            // pushed under ME, so ME carries isCurrent. The stale four-tab
            // TRIP · COMMS · PERMIT · ME label set is NOT this bar.
            BottomNav(
                leading: EscortNavRoute.leading(current: .me),
                trailing: EscortNavRoute.trailing(current: .me),
                orbState: .idle
            )
        }
    }
}

#Preview("ES-15 · Schedule · Dark") {
    EscortScheduleScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("ES-15 · Schedule · Light") {
    EscortScheduleScreen(theme: Theme.light).preferredColorScheme(.light)
}
