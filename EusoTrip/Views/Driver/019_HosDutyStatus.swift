//
//  019_HosDutyStatus.swift
//  EusoTrip 2027 UI — Wave 1 (final screen)
//
//  Screen 019 · HOS Duty Status — the mandatory 30-minute break.
//
//  Moment (night):     Michael Eusorone, 14:22 CDT, truck stopped at Flying J #651
//                      Meridian-adjacent, I-20 E MM 132. Switching Driving → Off-Duty
//                      to start 8/2 split. 6h 58m drive bank, 10h 12m on-duty bank,
//                      52h 44m cycle remaining.
//  Moment (afternoon): Michael Eusorone, 20:53 CDT, Pilot #388 Heflin AL,
//                      I-20 E MM 210. Same break, later in the shift.
//                      7h 27m drive bank, 8h 58m on-duty bank, 47h 11m cycle.
//
//  Doctrine refs: §3 (numbers-first copy — every bank shown),
//                 §4.3 (iridescent only on the live status bar),
//                 §6 (dual register), §7 (breathe density — tall 24-hour timeline),
//                 §8 (Driver rhythm: status picker + timeline + 3 metrics + CTA),
//                 §9 (DutyPicker uses the quiet neutral chip, never accent
//                     except when the segment is live),
//                 §11 (no lorem — carrier/lane/FMCSA §395.8 language),
//                 §12 (dual preview).
//
//  This file is the SwiftUI twin of:
//    02_html/dark/019_hos_duty_status.html
//    02_html/light/019_hos_duty_status.html
//

import SwiftUI

// MARK: - Screen

struct HosDutyStatus: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: EusoTripSession
    @StateObject private var store = HOSLiveStore()

    // Preview register still lets design review open the screen against
    // deterministic copy — real usage is purely live-data driven.
    enum Register { case night, afternoon, live }
    let register: Register

    init(register: Register = .live) {
        self.register = register
    }

    /// Vertical dispatcher. HOS rules per vertical converge on a
    /// "rest" concept, but the labels differ — truck driver sees
    /// DRIVE, rail engineer sees RUN, vessel captain sees WATCH.
    /// Resolved from the signed-in role only; this screen does not
    /// need an active load.
    private var ctx: LifecycleProductContext {
        LifecycleProductContext.forRole(session.user?.role)
    }

    // Rolling wall-clock ticker so the "resumes at", break-countdown,
    // and 24-hour timeline redraw every second without the controller
    // having to re-publish. 1s cadence keeps the battery hit negligible.
    @State private var now: Date = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Remark sheet state.
    @State private var showRemark = false
    @State private var remarkDraft = ""

    // Certification confirmation.
    @State private var certifyTarget: HOSDailyLog?

    // FMCSA §395.8 duty categories (maps 1:1 to HOSDutyCode)
    enum Duty: String, CaseIterable {
        case off = "OFF"
        case sb  = "SB"
        case d   = "D"
        case on  = "ON"

        var title: String {
            switch self {
            case .off: return "Off-Duty"
            case .sb:  return "Sleeper"
            case .d:   return "Driving"
            case .on:  return "On-Duty"
            }
        }
        var subtitle: String {
            switch self {
            case .off: return "§395.8 line 1"
            case .sb:  return "§395.8 line 2"
            case .d:   return "§395.8 line 3"
            case .on:  return "§395.8 line 4"
            }
        }

        var hosCode: HOSDutyCode {
            switch self {
            case .off: return .offDuty
            case .sb:  return .sleeperBerth
            case .d:   return .driving
            case .on:  return .onDuty
            }
        }

        static func from(_ code: HOSDutyCode) -> Duty {
            switch code {
            case .offDuty:      return .off
            case .sleeperBerth: return .sb
            case .driving:      return .d
            case .onDuty:       return .on
            }
        }
    }

    // Header right-column label — matches the Figma `019 HOS Duty
    // Status.png` "70-HOUR / 8-DAY compliant" caption. Pairs with the
    // "§395.8 compliant" line just below it so the driver can
    // glance-confirm the shift is inside FMCSA property-carrier limits.
    private let cycleName  = "70-hour / 8-day compliant"

    // MARK: Live-driven state

    private var current: Duty {
        Duty.from(store.currentDuty)
    }

    private var clockTime: String {
        HosDutyStatus.clockFormatter.string(from: now).uppercased()
    }

    private var locationText: String {
        // Prefer the live segment's location; fall back to the most
        // recent non-empty location from today's log.
        if let live = store.today?.entries.last(where: { $0.endDate == nil }),
           let loc = live.locationDescription, !loc.isEmpty {
            return loc
        }
        return store.today?.entries
            .reversed()
            .compactMap { $0.locationDescription }
            .first { !$0.isEmpty }
            ?? "Awaiting GPS fix"
    }

    private var driveBank: (h: Int, m: Int) {
        toHM(store.status?.drivingRemaining ?? 0)
    }
    private var onBank: (h: Int, m: Int) {
        toHM(store.status?.onDutyRemaining ?? 0)
    }
    private var cycleBank: (h: Int, m: Int) {
        toHM(store.status?.cycleRemaining ?? 0)
    }

    /// 30-min break resume clock, projected forward from nextBreakDue if
    /// we're inside the break, otherwise "—".
    private var resumeAt: String {
        guard let status = store.status else { return "—" }
        if status.breakRequired,
           let iso = status.nextBreakDue,
           let date = ISO8601DateFormatter().date(from: iso) {
            return HosDutyStatus.clockFormatter.string(from: date).uppercased()
        }
        // Not currently on a break — project next required break.
        if let iso = status.nextBreakDue,
           let date = ISO8601DateFormatter().date(from: iso) {
            return "at " + HosDutyStatus.clockFormatter.string(from: date).uppercased()
        }
        return "—"
    }

    private var beforeNextBreak: String {
        if let mins = store.minutesUntilBreak {
            if mins <= 0 { return "0h 00m · break due" }
            return "\(mins / 60)h \(String(format: "%02d", mins % 60))m · until next break"
        }
        return "no break scheduled"
    }

    private var breakElapsedMinutes: Int {
        // When break is required, nextBreakDue is in the future — clamp to 0
        // and measure from the start-of-current-segment (best proxy without
        // a dedicated "break start" field on the server payload).
        guard let start = currentSegmentStart() else { return 0 }
        return max(0, Int(now.timeIntervalSince(start) / 60))
    }

    private var breakProgress: CGFloat {
        // 30-minute rule
        min(1.0, CGFloat(breakElapsedMinutes) / 30.0)
    }

    /// Segments for the 24-hour timeline, normalised to the 04:00 – 04:00
    /// log day. Values are decimal hours from the 04:00 baseline (4.0–28.0
    /// internally; renderer maps back).
    private var segments: [Segment] {
        guard let entries = store.today?.entries, !entries.isEmpty else { return [] }
        let cal = Calendar(identifier: .gregorian)
        // Log day starts at 04:00 local
        let logDayStart: Date = {
            var comp = cal.dateComponents([.year, .month, .day], from: now)
            comp.hour = 4
            comp.minute = 0
            let candidate = cal.date(from: comp) ?? now
            // If it's before 04:00 wall-clock, roll back a day
            return now < candidate ? cal.date(byAdding: .day, value: -1, to: candidate)! : candidate
        }()

        return entries.compactMap { entry -> Segment? in
            let startDelta = entry.startDate.timeIntervalSince(logDayStart) / 3600.0
            let endDelta: Double = {
                if let end = entry.endDate {
                    return end.timeIntervalSince(logDayStart) / 3600.0
                }
                return now.timeIntervalSince(logDayStart) / 3600.0
            }()
            guard endDelta > 0 else { return nil }
            let s = max(0.0, min(24.0, startDelta))
            let e = max(0.0, min(24.0, endDelta))
            guard e > s else { return nil }
            return Segment(
                start: 4.0 + s,
                end: 4.0 + e,
                duty: Duty.from(entry.duty),
                note: entry.locationDescription ?? entry.remark ?? "",
                live: entry.endDate == nil
            )
        }
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s5) {
                    liveStatusCard
                    dutyPicker
                    timelineCard
                    metricsRow
                    breakCountdown
                    certifyRow
                    fineprint
                }
                .padding(Space.s5)
            }
        }
        .onReceive(tick) { now = $0 }
        .task { await store.bootstrap() }
        .refreshable { await store.refreshAll() }
        .sheet(isPresented: $showRemark) {
            remarkSheet
                .eusoSheetX()
        }
        .alert(item: $certifyTarget) { day in
            Alert(
                title: Text("Certify \(day.date)?"),
                message: Text("You're certifying this log as true and complete per 49 CFR §395.8(g)."),
                primaryButton: .default(Text("Certify")) {
                    Task { await store.certify(date: day.date, signature: "ios-self-cert") }
                },
                secondaryButton: .cancel()
            )
        }
        .overlay(alignment: .top) {
            if let toast = store.lastToast {
                Text(toast)
                    .font(EType.caption)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s2)
                    .eusoCard(radius: Radius.sm, intensity: .whisper)
                    .padding(.top, Space.s2)
                    .transition(.opacity)
            }
        }
        // Uniform cafe-door entrance.
        .screenTileRoot()
    }

    // MARK: Helpers

    private func toHM(_ hours: Double) -> (h: Int, m: Int) {
        let mins = Int((hours * 60).rounded())
        return (max(0, mins / 60), max(0, mins % 60))
    }

    /// Start of the driver's current (open) segment — used for the
    /// break elapsed countdown.
    private func currentSegmentStart() -> Date? {
        guard let last = store.today?.entries.last, last.endDate == nil else {
            return nil
        }
        return last.startDate
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm zzz"
        return f
    }()

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 2) {
                Text("HOS")
                    .font(EType.display).foregroundStyle(palette.textPrimary)
                Text(clockTime.uppercased())
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(cycleName.uppercased())
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("§395.8 compliant")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s4)
        .padding(.bottom, Space.s3)
    }

    // MARK: Live status card — the only place gradient is allowed (§4.3)

    private var liveStatusCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CURRENT STATUS")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(current.title)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("break · 30 min")
                            .font(.system(size: 13, weight: .medium)).tracking(0.4)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("RESUMES")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(resumeAt)
                        .font(EType.mono(.caption)).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                        .tracking(0.4)
                }
            }

            // Location line
            HStack(spacing: 6) {
                Image(systemName: "location.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
                Text(locationText)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Duty picker — 4-state segmented

    private var dutyPicker: some View {
        HStack(spacing: Space.s2) {
            ForEach(Duty.allCases, id: \.self) { d in
                dutyChip(duty: d, live: d == current)
            }
        }
    }

    @ViewBuilder
    private func dutyChip(duty: Duty, live: Bool) -> some View {
        Button {
            // Optimistic transition — the store rolls back if the server
            // rejects. Disabled while a previous change is in flight to
            // prevent double-taps from stacking log entries.
            guard !store.isChangingStatus, duty.hosCode != store.currentDuty else { return }
            // TODO: 019 doesn't yet observe DriverHomeViewModel, so we
            // pass "" for the §395.8(h) location_description. Wire a
            // shared LocationService (e.g. surface a published string on
            // GeofenceService.shared) and forward it here so the log
            // entry carries a real place instead of the empty fallback.
            Task { await store.changeStatus(to: duty.hosCode, location: "") }
        } label: {
            VStack(spacing: 4) {
                Text(duty.rawValue)
                    .font(EType.mono(.caption)).fontWeight(.semibold)
                    .tracking(0.6)
                    .foregroundStyle(live ? Color.white : palette.textPrimary)
                Text(duty.title)
                    .font(EType.micro).tracking(0.5)
                    .foregroundStyle(live ? Color.white.opacity(0.82) : palette.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .background {
                if live {
                    LinearGradient.diagonal
                } else {
                    palette.bgCard
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(live ? Color.clear : palette.borderSoft)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .opacity(store.isChangingStatus ? 0.6 : 1.0)
        }
        .disabled(store.isChangingStatus)
        .accessibilityLabel("\(duty.title)\(live ? ", currently selected" : "")")
    }

    // MARK: Timeline — 24-hour stacked duty log

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("TODAY · 24-HOUR LOG")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("04:00 – 04:00 CDT")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }

            // Row stack: 4 lanes, one per duty status
            VStack(spacing: 2) {
                ForEach(Duty.allCases, id: \.self) { lane in
                    lineForDuty(lane)
                }
            }
            .background(palette.bgPage.opacity(0.01)) // keep the coordinate space

            // Hour axis
            HStack {
                ForEach([0, 6, 12, 18, 24], id: \.self) { h in
                    Text(hourLabel(h))
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                    if h != 24 { Spacer() }
                }
            }

            // Legend
            HStack(spacing: Space.s3) {
                legendChip(color: palette.textTertiary.opacity(0.35), label: "Off")
                legendChip(color: palette.textSecondary.opacity(0.35), label: "SB")
                legendChip(color: Brand.blue, label: "Drive")
                legendChip(color: palette.textPrimary.opacity(0.50), label: "On")
                Spacer()
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.md)
    }

    private func hourLabel(_ h: Int) -> String {
        // offset by 4h so log shows 04 → 04
        let clock = (h + 4) % 24
        return String(format: "%02d", clock)
    }

    @ViewBuilder
    private func legendChip(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 4)
            Text(label)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
        }
    }

    @ViewBuilder
    private func lineForDuty(_ lane: Duty) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                // Track
                Rectangle()
                    .fill(palette.borderFaint)
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .center)

                // Lane label
                HStack {
                    Text(lane.rawValue)
                        .font(EType.mono(.micro)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                        .frame(width: 26, alignment: .leading)
                    Spacer()
                }

                // Segments in this lane
                ForEach(segments.filter { $0.duty == lane }) { seg in
                    let sx = (seg.start - 4.0) / 24.0
                    let ex = (seg.end - 4.0) / 24.0
                    let x = max(0, CGFloat(sx) * (w - 26)) + 26
                    let width = max(2, CGFloat(ex - sx) * (w - 26))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(laneFill(seg.duty, isLive: isLive(seg)))
                        .frame(width: width, height: 14)
                        .offset(x: x)
                        .overlay(alignment: .leading) {
                            if isLive(seg) {
                                // Iridescent marker for the active segment
                                Circle()
                                    .fill(LinearGradient.diagonal)
                                    .frame(width: 8, height: 8)
                                    .overlay(Circle().strokeBorder(palette.bgPage, lineWidth: 2))
                                    .offset(x: x + width - 4, y: 0)
                            }
                        }
                }
            }
        }
        .frame(height: 22)
    }

    private func isLive(_ seg: Segment) -> Bool {
        // Segment carries its own live flag (endDate == nil from the server).
        seg.live
    }

    private func laneFill(_ duty: Duty, isLive: Bool) -> some ShapeStyle {
        if isLive { return AnyShapeStyle(LinearGradient.diagonal) }
        switch duty {
        case .off: return AnyShapeStyle(palette.textTertiary.opacity(0.40))
        case .sb:  return AnyShapeStyle(palette.textSecondary.opacity(0.40))
        case .d:   return AnyShapeStyle(Brand.blue.opacity(0.82))
        case .on:  return AnyShapeStyle(palette.textPrimary.opacity(0.55))
        }
    }

    // MARK: Metrics — Drive / On-duty / Cycle banks

    private var metricsRow: some View {
        HStack(spacing: Space.s2) {
            metricCell(
                label: ctx.hosDriveWord,
                big: "\(driveBank.h)h \(String(format: "%02d", driveBank.m))m",
                sub: "of 11h"
            )
            metricCell(
                label: "ON-DUTY",
                big: "\(onBank.h)h \(String(format: "%02d", onBank.m))m",
                sub: "of 14h"
            )
            metricCell(
                label: "CYCLE",
                big: "\(cycleBank.h)h \(String(format: "%02d", cycleBank.m))m",
                sub: "70h / 8d"
            )
        }
    }

    @ViewBuilder
    private func metricCell(label: String, big: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(big)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .tracking(0.4)
            Text(sub)
                .font(EType.mono(.micro)).tracking(0.4)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Break countdown

    private var breakCountdown: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("30-MIN BREAK")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("§395.3(a)(3)(ii)")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }

            // Countdown rail — progress fills as the driver logs off-duty time
            VStack(spacing: 6) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(palette.borderSoft)
                            .frame(height: 6)
                        Capsule()
                            .fill(LinearGradient.diagonal)
                            .frame(width: g.size.width * breakProgress, height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    let elapsedH = breakElapsedMinutes / 60
                    let elapsedM = breakElapsedMinutes % 60
                    Text(String(format: "%d:%02d elapsed", elapsedH, elapsedM))
                    Spacer()
                    let remaining = max(0, 30 - breakElapsedMinutes)
                    Text(String(format: "0:%02d to resume", remaining))
                }
                .font(EType.mono(.micro)).tracking(0.4)
                .foregroundStyle(palette.textSecondary)
            }

            Text(beforeNextBreak)
                .font(EType.mono(.micro)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Certify row

    private var certifyRow: some View {
        HStack(spacing: Space.s2) {
            let pending = store.yesterdayUncertified
            Button {
                guard let day = pending else { return }
                certifyTarget = day
            } label: {
                Text(pending == nil ? "All logs certified" : "Certify \(certifyDayLabel(pending?.date))")
                    .font(EType.body).fontWeight(.semibold)
                    .foregroundStyle(pending == nil ? palette.textSecondary : Color.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background {
                        if pending == nil {
                            palette.bgCardSoft
                        } else {
                            LinearGradient.diagonal
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .disabled(pending == nil)
            .accessibilityLabel("Certify yesterday's log as accurate")

            Button {
                remarkDraft = ""
                showRemark = true
            } label: {
                Text("Add remark")
                    .font(EType.body).fontWeight(.medium)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .accessibilityLabel("Add a remark to the log")
        }
    }

    private func certifyDayLabel(_ date: String?) -> String {
        guard let date else { return "pending" }
        // Compare against wall-clock "yesterday" for a natural label.
        let cal = Calendar(identifier: .gregorian)
        let df = DateFormatter()
        df.calendar = cal
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        guard let target = df.date(from: date) else { return date }
        if cal.isDateInYesterday(target) { return "yesterday" }
        df.dateFormat = "MMM d"
        return df.string(from: target)
    }

    // MARK: Remark sheet

    @ViewBuilder
    private var remarkSheet: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack {
                Text("Add remark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Button("Cancel") { showRemark = false }
                    .font(EType.body).fontWeight(.medium)
                    .foregroundStyle(palette.textSecondary)
            }

            Text("Attach a §395.8(j) annotation to your current segment.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)

            TextEditor(text: $remarkDraft)
                .frame(minHeight: 120)
                .padding(Space.s2)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderSoft))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))

            Button {
                let text = remarkDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                showRemark = false
                Task { await store.addRemark(text) }
            } label: {
                Text("Save remark")
                    .font(EType.body).fontWeight(.semibold)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .disabled(remarkDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
        }
        .padding(Space.s5)
        .presentationDetents([.medium])
    }

    // MARK: Fine print — ELD provenance (§11 no-lorem)

    private var fineprint: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Provenance strings come from the driver's ELD + load when
            // available, falling back to generic §395.8 descriptors if
            // we're not attached to a load yet.
            Text(store.status == nil ? "ELD · §395.15 compliant" : "ELD · linked · §395.15 compliant")
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
            if let today = store.today {
                Text("Today \(today.date) · \(today.drivingDisplay) drive · \(today.onDutyDisplay) on-duty")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("Self-certified record — \(store.today?.certified == true ? "certified" : "uncertified")")
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.top, Space.s2)
    }
}

// MARK: - Segment

private struct Segment: Identifiable {
    let id = UUID()
    let start: Double    // decimal hours 4.0 – 28.0 (mapped to 04:00 – 04:00)
    let end:   Double
    let duty:  HosDutyStatus.Duty
    let note:  String
    let live:  Bool      // true for the still-open segment (endDate == nil)
}

// MARK: - Wrapper

struct HosDutyStatusScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            HosDutyStatus(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_019(),
                      trailing: driverNavTrailing_019(),
                      orbState: .idle)
        }
    }
}

// PNG canon at `01 Driver/{Light,Dark}/019 HOS Duty Status.png` +
// [Driver E2E map] doctrine pin HOS / ELD (019, 074, 081) inside
// Ring 1 Me. Restored canonical layout: Home / Trips · Wallet / Me
// with **ME current**. Prior iOS shipped `Loads isCurrent: true`
// which carried two drifts: (a) Loads is not a canonical trailing
// slot (Wallet is), (b) HOS is a Me-ring compliance hub, not a
// Wallet surface. Per [feedback_bottom_nav_frozen]: layout +
// isCurrent flags ship as-is; this restores the canonical pin.
private func driverNavLeading_019() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house.fill", isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",  isCurrent: false)]
}
private func driverNavTrailing_019() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person.fill", isCurrent: true)]
}

// MARK: - Previews

#Preview("019 · HOS Duty Status · Dark") {
    HosDutyStatusScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("019 · HOS Duty Status · Light") {
    HosDutyStatusScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
