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
//      no blackout column in the escort schema, so "+ Block dates" renders inert
//      with its reason on its face. It never opens a sheet and never fakes a
//      write.
//    • updateAvailability persists to users.metadata and emits NOTHING — no
//      audit row, no WebSocket fan-out. A dispatcher board does not learn that
//      Saturday just went dark. Named as a one-sided chain, not hidden.
//
//  Offline duty (§W): reads = READ_CACHED(30m) through EscortOfflineCache.
//  When a snapshot is painted the staleness line is visible in the section rail
//  and every count carries the cached tone. Past the ttl the lattice refuses to
//  draw counts rather than present stale density as live. The availability
//  toggle is ONLINE_ONLY — the Unified Outbox is Driver-only today, so no queue
//  badge is ever drawn.
//
//  RBAC: registered role .escort only; every procedure resolves the caller's own
//  escort rows server-side (resolveEscortUserId escorts.ts:138). No loads.rate,
//  no shipper margin, no other escort's schedule reaches this surface.
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
private struct ES15UpcomingJob: Decodable, Identifiable, Codable {
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
private struct ES15ScheduleRow: Decodable, Identifiable, Codable {
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
private struct ES15AvailabilityDay: Decodable, Identifiable, Codable {
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
private struct ES15Cert: Decodable, Codable {
    let certType: String?
    let issuingState: String?
    let expirationDate: String?
}
private struct ES15CertStatus: Decodable, Codable {
    let certifications: [ES15Cert]?
}

/// `escorts.getJobDetails` (escorts.ts:1979) — one field is wanted here.
private struct ES15JobSpan: Decodable, Codable {
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
    let startMinutes: Int
    let endMinutes: Int
    let position: ES15Position
    var startLabel: String { String(format: "%02d:%02d", startMinutes / 60, startMinutes % 60) }
}

private struct ES15Overlap: Identifiable, Equatable {
    let id: String
    let firstIndex: Int
    let secondIndex: Int
    let minutes: Int
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
                    blockDatesAffordance
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
        .refreshable { await load(forceNetwork: true) }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ESCORT · SCHEDULE").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text(monthLabel).font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            Text(ledgerLine).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
            Text(headlineText).font(.system(size: 27, weight: .bold)).tracking(-0.6)
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
    private var ledgerLine: String {
        "\(monthLabel) · \(bookedTotal) BOOKED · \(blockedDayCount) BLOCKED"
    }
    private var headlineText: String {
        guard let day = focusedDay, let count = countsByDay[day], count > 0 else {
            return "\(bookedTotal) moves this month"
        }
        return "\(count) moves on \(weekdayShort(day)) \(day)"
    }
    private var subheadText: String {
        let overlaps = focusedOverlaps
        guard !overlaps.isEmpty else { return "No double-booking on the peak day" }
        let total = overlaps.reduce(0) { $0 + $1.minutes }
        return "Peak day · \(overlaps.count) overlaps · \(total / 60) h \(total % 60) m double-booked"
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
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(cellWash(blocked: blocked, isToday: isToday, isFocused: isFocused))
                    .overlay {
                        if isFocused {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
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

    // MARK: The inert block-dates affordance
    //
    // No procedure writes a date range and no blackout column exists. Rather
    // than hide the capability or open a sheet that cannot save, the control is
    // drawn dashed, inert, with its reason on its face.

    private var blockDatesAffordance: some View {
        HStack {
            Text("+ BLOCK DATES · NO WRITE PATH YET")
                .font(.system(size: 7.5, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, Space.s3).padding(.vertical, 5)
                .background(Capsule().fill(palette.bgCard.opacity(0.55)))
                .overlay(Capsule().strokeBorder(palette.textTertiary.opacity(0.45),
                                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            Spacer()
            Text("BANDS ARE READ-ONLY").font(.system(size: 7.5, weight: .bold).monospaced())
                .foregroundStyle(palette.textTertiary)
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Block dates is unavailable: no server write path exists yet.")
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
        guard !focusedOverlaps.isEmpty else { return "\(moves.count) MOVES" }
        let total = focusedOverlaps.reduce(0) { $0 + $1.minutes }
        return "\(focusedOverlaps.count) OVERLAPS · \(total / 60)H\(String(format: "%02d", total % 60))M"
    }

    private var dayDensityPanel: some View {
        let moves = focusedMoves.sorted { $0.startMinutes < $1.startMinutes }
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
                                    .foregroundStyle(move.position.ink)
                                    .frame(width: gutter - 18, alignment: .leading)
                                ZStack(alignment: .leading) {
                                    Color.clear.frame(height: 6)
                                    Capsule().fill(move.position.ink)
                                        .frame(width: max(track * CGFloat(move.endMinutes - move.startMinutes) / span, 6),
                                               height: 6)
                                        .offset(x: track * CGFloat(move.startMinutes - dayStart) / span)
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
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
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
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
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
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(on ? tint.opacity(isDark ? 0.22 : 0.14) : palette.bgCardSoft))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
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
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
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
            Text("Counts union getUpcomingJobs (accepted only) with getSchedule (10-row cap).")
                .font(.system(size: 7.5, weight: .semibold).monospaced())
                .foregroundStyle(palette.textTertiary)
            Text("A day past those caps under-counts here. Range-aware read is owed.")
                .font(.system(size: 7.5, weight: .semibold).monospaced())
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var saveBar: some View {
        VStack(spacing: 6) {
            Text("\(availability.filter { $0.available }.count) of 7 days on · availability saves per tap")
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
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

    /// Lanes for the focused day. Start times come from the REAL `startTime`
    /// string the schedule projection returns; a row without one is placed at
    /// the day's open rather than invented at a plausible hour, and the panel
    /// says how many rows lacked a time.
    private var focusedMoves: [ES15DayMove] {
        guard let day = focusedDay else { return [] }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let sameDay = upcoming.filter { job in
            guard let key = job.scheduledDate, let d = f.date(from: key) else { return false }
            return calendar.isDate(d, equalTo: anchorMonth, toGranularity: .month)
                && calendar.component(.day, from: d) == day
        }
        let clock = DateFormatter(); clock.dateFormat = "hh:mm a"
        return sameDay.enumerated().map { idx, job in
            let row = scheduleRows.first { $0.id == job.id }
            var start = 5 * 60 + idx * 45          // deterministic lane order, not a fake clock
            if let raw = row?.startTime, let t = clock.date(from: raw) {
                start = calendar.component(.hour, from: t) * 60 + calendar.component(.minute, from: t)
            }
            // Duration from REAL leg distance at the common 45 mph escort cap.
            let miles = job.distance ?? row?.distance ?? 0
            let minutes = miles > 0 ? Int((miles / 45 * 60).rounded()) : 90
            return ES15DayMove(id: job.id, index: idx + 1,
                               startMinutes: start,
                               endMinutes: min(start + minutes, 23 * 60 + 59),
                               position: ES15Position(wire: job.position ?? row?.position))
        }
    }

    private var focusedOverlaps: [ES15Overlap] {
        let sorted = focusedMoves.sorted { $0.startMinutes < $1.startMinutes }
        var out: [ES15Overlap] = []
        for i in 0..<max(0, sorted.count - 1) {
            let a = sorted[i], b = sorted[i + 1]
            let m = a.endMinutes - b.startMinutes
            if m > 0 { out.append(ES15Overlap(id: "\(a.id)-\(b.id)", firstIndex: a.index, secondIndex: b.index, minutes: m)) }
        }
        return out
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
            // read projects — one getJobDetails per candidate row, and only for
            // rows that could plausibly span (distance over a single shift).
            var fetchedSpans: [ES15JobSpan] = []
            for job in fetchedUpcoming where (job.distance ?? 0) > 400 {
                if let span: ES15JobSpan = try? await EusoTripAPI.shared.query(
                    "escorts.getJobDetails", input: ES15JobIdInput(jobId: job.id)) {
                    fetchedSpans.append(span)
                }
            }

            let snapshot = ES15MonthSnapshot(upcoming: fetchedUpcoming,
                                             schedule: fetchedSchedule,
                                             availability: fetchedAvailability,
                                             certs: certStatus?.certifications ?? [],
                                             spans: fetchedSpans)
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
}

// MARK: - Registered surface wrapper

struct EscortScheduleScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortSchedule()
        } nav: {
            // Escort role enum TRIP·COMMS·PERMIT·ME — schedule is pushed under
            // ME, matching the ES-08 precedent.
            BottomNav(
                leading: [
                    NavSlot(label: "Trip",  systemImage: "house",       isCurrent: false),
                    NavSlot(label: "Comms", systemImage: "bubble.left", isCurrent: false),
                ],
                trailing: [
                    NavSlot(label: "Permit", systemImage: "doc.text", isCurrent: false),
                    NavSlot(label: "Me",     systemImage: "person",   isCurrent: true),
                ],
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
