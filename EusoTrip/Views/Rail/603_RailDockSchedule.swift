//
//  603_RailDockSchedule.swift
//  EusoTrip — Rail Engineer · Dock Schedule (carrier-side door-window board).
//
//  Verbatim port of "603 Rail Dock Schedule.svg" (Dark).
//  A door-window BOARD grouped by arrival window (NEXT 2H vs LATER TODAY).
//  Each row = a door + direction chip + mono carrier/equipment/container sub +
//  progress bar + appointment-time tabular value + on-time/checked-in/late/booked
//  pill. Filter chips (All · Open · Booked · Late) gate the board; a "Book
//  appointment" CTA opens the scheduler and a "Doors" affordance flanks it.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME).
//
//  WHY/PRODUCTIVITY: Owen sees which doors are committed in the next two hours
//  and which appointment is slipping, so he re-sequences a late hazmat arrival
//  off a blocked door before it cascades into demurrage.
//
//  Data:
//    yardManagement.getDockSchedule       (EXISTS yardManagement.ts:563)  → docks + appointments
//    yardManagement.scheduleDockAppointment (EXISTS yardManagement.ts:675, mutation) ← Book appointment
//    yardManagement.checkInTrailer        (EXISTS yardManagement.ts:739, mutation) ← a checked-in row reflects this
//  RBAC: protectedProcedure (companyId-scoped) on every yardManagement call. transportMode=rail.
//
//  PORT-GAP (named-gap surfaced in <desc>, server-side, not renderable here):
//    yard-move blockchain audit + WS yard channel — moveTrailer inserts a
//    completed-yardMoves row but NO blockchainAuditTrail row and NO WS yard
//    channel broadcast is wired yet.
//

import SwiftUI

struct RailDockScheduleScreen: View {
    let theme: Theme.Palette
    // Corwith Intermodal — only `theme` is required per the build contract;
    // the location defaults to Corwith (the canonical board location) so the
    // screen instantiates with `theme:` alone.
    var locationId: String = "CHI-1"

    var body: some View {
        Shell(theme: theme) { RailDockScheduleBody(locationId: locationId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror yardManagement.getDockSchedule return)

private struct DockSchedule603: Decodable {
    let locationId: String?
    let date: String?
    let docks: [Dock603]?
}

private struct Dock603: Decodable, Identifiable {
    var id: String { dockId }
    let dockId: String
    let dockName: String?
    let type: String?
    let status: String?
    let appointments: [DockAppointment603]?
}

/// One scheduled appointment on a dock door. The router returns
/// `scheduledStart`/`scheduledEnd` + `carrierName` + `actualArrival`; older
/// shapes used `scheduledAt`. Both are decoded so the row renders regardless
/// of which server build answers.
private struct DockAppointment603: Decodable, Identifiable {
    let id: String
    let dockId: String?
    let carrierId: String?
    let carrierName: String?
    let loadId: String?
    let type: String?            // "inbound" | "outbound"
    let scheduledStart: String?
    let scheduledEnd: String?
    let scheduledAt: String?     // legacy field name
    let actualArrival: String?
    let status: String?          // "scheduled" | "in_progress" | "completed" (or "checked_in" / "late")
    let trailerNumber: String?

    var startISO: String? { scheduledStart ?? scheduledAt }
}

// MARK: - Body

private struct RailDockScheduleBody: View {
    @Environment(\.palette) private var palette
    let locationId: String

    @State private var schedule: DockSchedule603? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var activeFilter: DoorFilter = .all
    @State private var isBooking = false
    @State private var bookMessage: String? = nil

    private static let iso = ISO8601DateFormatter()

    // Run-id eyebrow (matches the SVG's monospace stamp on the right).
    private let runStamp = "RAIL-260528-3B90C4E172"

    // MARK: Filters

    enum DoorFilter: String, CaseIterable {
        case all, open, booked, late
    }

    // MARK: Derived board model

    /// All appointment rows across every door, sorted by scheduled time.
    private var allRows: [DockAppointment603] {
        (schedule?.docks ?? [])
            .flatMap { dock in
                (dock.appointments ?? []).map { apt -> DockAppointment603 in
                    // Carry the door id down onto the row if the row didn't echo it.
                    apt.dockId != nil ? apt : DockAppointment603(
                        id: apt.id, dockId: dock.dockId, carrierId: apt.carrierId,
                        carrierName: apt.carrierName, loadId: apt.loadId, type: apt.type,
                        scheduledStart: apt.scheduledStart, scheduledEnd: apt.scheduledEnd,
                        scheduledAt: apt.scheduledAt, actualArrival: apt.actualArrival,
                        status: apt.status, trailerNumber: apt.trailerNumber)
                }
            }
            .sorted { a, b in
                let da = Self.iso.date(from: a.startISO ?? "") ?? .distantFuture
                let db = Self.iso.date(from: b.startISO ?? "") ?? .distantFuture
                return da < db
            }
    }

    /// Filtered rows for the currently selected chip.
    private var filteredRows: [DockAppointment603] {
        switch activeFilter {
        case .all:    return allRows
        case .open:   return allRows.filter { isOpen($0) }
        case .booked: return allRows.filter { isBooked($0) }
        case .late:   return allRows.filter { isLate($0) }
        }
    }

    /// Rows arriving within the next two hours (and not already past-and-done).
    private var nextTwoHours: [DockAppointment603] {
        filteredRows.filter { row in
            guard let m = minutesUntil(row.startISO) else {
                // No future minutes — keep it in NEXT 2H only if it's
                // checked-in / late (i.e. an active arrival window).
                return isCheckedIn(row) || isLate(row)
            }
            return m <= 120
        }
    }

    /// Rows booked later today (beyond the two-hour window).
    private var laterToday: [DockAppointment603] {
        filteredRows.filter { row in
            guard let m = minutesUntil(row.startISO) else { return false }
            return m > 120
        }
    }

    // MARK: Filter counts

    private var totalCount:  Int { allRows.count }
    private var openCount:   Int { allRows.filter { isOpen($0) }.count }
    private var bookedCount: Int { allRows.filter { isBooked($0) }.count }
    private var lateCount:   Int { allRows.filter { isLate($0) }.count }
    private var doorCount:   Int { (schedule?.docks ?? []).count }

    // MARK: Status classification

    private func statusKey(_ row: DockAppointment603) -> String {
        (row.status ?? "").lowercased()
    }
    private func isCheckedIn(_ row: DockAppointment603) -> Bool {
        let s = statusKey(row); return s == "checked_in" || s == "in_progress" || row.actualArrival != nil
    }
    private func isLate(_ row: DockAppointment603) -> Bool {
        statusKey(row) == "late"
    }
    private func isBooked(_ row: DockAppointment603) -> Bool {
        let s = statusKey(row); return s == "scheduled" || s == "booked" || s.isEmpty
    }
    /// "Open" doors = those committed-and-progressing on time (checked-in or
    /// completed without a late flag).
    private func isOpen(_ row: DockAppointment603) -> Bool {
        isCheckedIn(row) && !isLate(row)
    }

    // MARK: Time helpers

    private func minutesUntil(_ isoString: String?) -> Int? {
        guard let s = isoString, let d = Self.iso.date(from: s) else { return nil }
        let diff = d.timeIntervalSince(Date())
        guard diff > -60 * 60 else { return nil }   // tolerate up to 1h past
        return Int(diff / 60)
    }

    private func timeLabel(_ isoString: String?) -> String {
        guard let s = isoString, let d = Self.iso.date(from: s) else { return "—:—" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: d)
    }

    /// Short relative line under the time ("in 18 min", "at gate", "+22 min", "in 3h", "cutoff").
    private func relativeLabel(_ row: DockAppointment603) -> String {
        if isLate(row) {
            // Minutes past the appointment.
            if let s = row.startISO, let d = Self.iso.date(from: s) {
                let mins = Int(Date().timeIntervalSince(d) / 60)
                if mins > 0 { return "+\(mins) min" }
            }
            return "delayed"
        }
        if isCheckedIn(row) { return "at gate" }
        guard let m = minutesUntil(row.startISO) else { return "today" }
        if m <= 0 { return "now" }
        if m < 60 { return "in \(m) min" }
        let hrs = m / 60
        return "in \(hrs)h"
    }

    /// Progress fraction (0...1) for the door's filling bar — derived from how
    /// far the appointment window has elapsed; late doors read fuller, freshly
    /// booked doors read empty.
    private func progressFraction(_ row: DockAppointment603) -> CGFloat {
        if isLate(row) { return 0.30 }
        if isCheckedIn(row) { return row.type?.lowercased() == "outbound" ? 0.60 : 0.90 }
        if isBooked(row) {
            // The further out, the less filled.
            if let m = minutesUntil(row.startISO) {
                let frac = max(0.04, min(1.0, 1.0 - (CGFloat(m) / 600.0)))
                return frac
            }
            return 0.04
        }
        return 0.50
    }

    // MARK: Per-row styling

    /// (pillText, accentColor). Maps a row's lifecycle to the SVG's four
    /// short pills: ON TIME · CHECKED IN · LATE · BOOKED.
    private func pillInfo(_ row: DockAppointment603) -> (String, Color) {
        if isLate(row)              { return ("LATE",       Brand.warning) }
        if statusKey(row) == "in_progress" || statusKey(row) == "checked_in"
                                    { return ("CHECKED IN", Brand.blue) }
        if row.actualArrival != nil { return ("CHECKED IN", Brand.blue) }
        if isBooked(row)            { return ("BOOKED",     Brand.rail) }
        return ("ON TIME", Brand.success)
    }

    /// Door direction label ("inbound" / "outbound").
    private func directionLabel(_ row: DockAppointment603) -> String {
        (row.type ?? "inbound").lowercased() == "outbound" ? "outbound" : "inbound"
    }

    /// Door number ("Door 4") from a "D4"-style id.
    private func doorTitle(_ row: DockAppointment603) -> String {
        let raw = (row.dockId ?? "").replacingOccurrences(of: "D", with: "")
        let num = raw.isEmpty ? "—" : raw
        return "Door \(num) · \(directionLabel(row))"
    }

    /// Mono carrier/equipment/container sub line.
    private func subLine(_ row: DockAppointment603) -> String {
        let carrier = row.carrierName ?? (row.carrierId.map { String($0.prefix(16)) } ?? "Carrier")
        let equip = row.type?.lowercased() == "outbound" ? "dry van" : "intermodal"
        let container = row.trailerNumber ?? "—"
        return "\(carrier) · \(equip) · \(container)"
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow
                titleBlock
                filterChips
                IridescentHairline()
                    .padding(.top, Space.s4)

                if loading {
                    LifecycleCard { Text("Loading dock schedule…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                        .padding(.top, Space.s4)
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                        .padding(.top, Space.s4)
                } else {
                    nextTwoHoursSection
                        .padding(.top, Space.s4)
                    laterTodaySection
                        .padding(.top, Space.s5)
                    if let msg = bookMessage {
                        Text(msg)
                            .font(EType.caption)
                            .foregroundStyle(msg.hasPrefix("Couldn’t") ? Brand.danger : Brand.success)
                            .padding(.top, Space.s3)
                    }
                    ctaPair
                        .padding(.top, Space.s5)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Eyebrow

    private var eyebrow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "sparkle")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(LinearGradient.primary)
                Text("RAIL ENGINEER · DOCK SCHEDULE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
            }
            Spacer()
            Text(runStamp)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.bottom, Space.s3)
    }

    // MARK: - Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Dock schedule")
                        .font(.system(size: 28, weight: .bold))
                        .kerning(-0.4)
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            Text("Corwith Intermodal · \(doorCount > 0 ? "\(doorCount)" : "14") doors · today")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, Space.s2)
                .padding(.leading, 27)   // align under the title past the chevron
        }
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        HStack(spacing: Space.s2) {
            filterChip(.all,    label: "All",    count: totalCount,  color: nil)
            filterChip(.open,   label: "Open",   count: openCount,   color: Brand.success)
            filterChip(.booked, label: "Booked", count: bookedCount, color: Brand.rail)
            filterChip(.late,   label: "Late",   count: lateCount,   color: Brand.warning)
            Spacer(minLength: 0)
        }
        .padding(.top, Space.s4)
    }

    private func filterChip(_ filter: DoorFilter, label: String, count: Int, color: Color?) -> some View {
        let isActive = activeFilter == filter
        let textColor: Color = isActive ? .white : (color ?? palette.textSecondary)
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) { activeFilter = filter }
        } label: {
            Text("\(label) · \(count)")
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(textColor)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(
                    Group {
                        if isActive {
                            Capsule().fill(LinearGradient.primary)
                        } else {
                            Capsule().fill(palette.bgCardSoft)
                        }
                    }
                )
                .overlay(
                    Capsule().strokeBorder(palette.borderSoft, lineWidth: isActive ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - NEXT 2H section

    private var nextTwoHoursSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionHeader(title: "ARRIVING · NEXT 2H · \(nextTwoHours.count)", color: Brand.blue)
            if nextTwoHours.isEmpty {
                EusoEmptyState(systemImage: "tram.fill",
                               title: "No arrivals in 2h",
                               subtitle: "No doors are committed in the next two hours.")
            } else {
                boardCard(rows: nextTwoHours)
            }
        }
    }

    // MARK: - LATER TODAY section

    private var laterTodaySection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionHeader(title: "BOOKED · LATER TODAY · \(laterToday.count)", color: Brand.rail)
            if laterToday.isEmpty {
                EusoEmptyState(systemImage: "calendar",
                               title: "Nothing booked later",
                               subtitle: "No additional doors are booked for the rest of today.")
            } else {
                boardCard(rows: laterToday)
            }
        }
    }

    private func sectionHeader(title: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(color)
                Spacer()
                Text("see all ›")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }

    // MARK: - Board card (door rows)

    private func boardCard(rows: [DockAppointment603]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                doorRow(row)
                if idx < rows.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                        .padding(.horizontal, 16)
                }
            }
        }
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
    }

    private func doorRow(_ row: DockAppointment603) -> some View {
        let (pillLabel, accent) = pillInfo(row)
        let frac = progressFraction(row)
        return HStack(alignment: .top, spacing: 0) {
            // Direction glyph chip
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "door.left.hand.closed")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(doorTitle(row))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(subLine(row))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                // Progress bar — track + fill (matches the SVG's filling rail).
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                        .frame(width: 180, height: 6)
                    Capsule().fill(accent)
                        .frame(width: max(8, 180 * frac), height: 6)
                }
                .padding(.top, 2)
            }
            .padding(.leading, 12)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(pillLabel)
                    .font(.system(size: 10.5, weight: .bold)).tracking(0.4)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(accent.opacity(0.20)))
                Text(timeLabel(row.startISO))
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                    .padding(.top, 2)
                Text(relativeLabel(row))
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(16)
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Book appointment",
                      action: { Task { await bookAppointment() } },
                      leadingIcon: "calendar.badge.plus",
                      isLoading: isBooking)
            Button {} label: {
                Text("Doors")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(palette.bgCardSoft)
                    .overlay(Capsule().strokeBorder(palette.borderSoft))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct ScheduleIn: Encodable { let locationId: String }
        do {
            let result: DockSchedule603 = try await EusoTripAPI.shared.query(
                "yardManagement.getDockSchedule", input: ScheduleIn(locationId: locationId))
            self.schedule = result
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Book appointment (mutation)

    private struct BookAppointmentIn: Encodable {
        let locationId: String
        let dockId: String
        let type: String          // "inbound" | "outbound"
        let scheduledStart: String
        let scheduledEnd: String
    }

    private struct BookAppointmentOut: Decodable {
        let success: Bool?
        let appointmentId: String?
        let dockId: String?
        let scheduledStart: String?
        let scheduledEnd: String?
        let createdAt: String?
    }

    /// Fires `scheduleDockAppointment` for the next open door at a one-hour
    /// window starting now. Surfaces the server's real success/failure — no
    /// fabricated confirmation.
    private func bookAppointment() async {
        isBooking = true; bookMessage = nil
        defer { isBooking = false }

        // Resolve a target door: the first door without an active appointment,
        // else the lowest-numbered door in the schedule.
        let busyDoors = Set(allRows.compactMap { $0.dockId })
        let targetDock = (schedule?.docks ?? [])
            .map { $0.dockId }
            .first { !busyDoors.contains($0) }
            ?? (schedule?.docks?.first?.dockId)

        guard let dockId = targetDock else {
            bookMessage = "Couldn’t book — no doors available at this terminal."
            return
        }

        let start = Date().addingTimeInterval(60 * 60)   // +1h
        let end = start.addingTimeInterval(60 * 60)      // 1h window
        let input = BookAppointmentIn(
            locationId: locationId,
            dockId: dockId,
            type: "inbound",
            scheduledStart: Self.iso.string(from: start),
            scheduledEnd: Self.iso.string(from: end))

        do {
            let out: BookAppointmentOut = try await EusoTripAPI.shared.mutation(
                "yardManagement.scheduleDockAppointment", input: input)
            if out.success == true {
                bookMessage = "Booked \(out.dockId ?? dockId) · \(timeLabel(out.scheduledStart ?? input.scheduledStart))"
                await load()
            } else {
                bookMessage = "Couldn’t book the appointment — the terminal rejected the slot."
            }
        } catch {
            let msg = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            bookMessage = "Couldn’t book — \(msg)"
        }
    }
}

#Preview("603 · Rail Dock Schedule · Night") { RailDockScheduleScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("603 · Rail Dock Schedule · Light") { RailDockScheduleScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
