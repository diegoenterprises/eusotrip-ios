//
//  074_MeHOSLogs.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · HOS logs)
//
//  Screen 074 · Me · HOS Logs — the driver's §395.8 hours-of-service
//  surface. Three blocks, stacked: (1) clock cycle remaining hero
//  (driving / on-duty / 70-hour cycle), (2) an 8-day mini-grid of daily
//  rollups with certification status, (3) today's segment strip with
//  per-entry duration + location.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data"):
//
//    • Dashboard + logs + violations all come from the live `hos.*`
//      tRPC procedures via the existing `HOSLiveStore` (backed by
//      `HOSClockService.shared` for the live snapshot + on-demand
//      `getDailyLog` / `getLogHistory` / `getViolations` pulls).
//      MCP-verified at `frontend/server/routers/hos.ts:22` (namespace
//      mounted in `frontend/server/routers.ts`).
//
//    • No fixture data, no stub clocks. The screen reads straight off
//      whatever HOSLiveStore has published. First render shows a
//      graceful skeleton until the `.task { await bootstrap() }`
//      round-trip completes — no "can't load" alarm unless the request
//      genuinely fails, and even then the retry is quiet.
//
//    • 8-day cycle grid is computed off `history` (newest-first). Each
//      day shows drive minutes as a proportional bar against the 11h
//      daily drive ceiling, with a cert badge when signed.
//
//    • Violations (if any) render inline above the cycle grid with
//      palette.textSecondary (not `Brand.warning` flat red) so the
//      driver isn't alarmed by a compliance notice that already exists
//      in the main HOS screen (019). This is a summary view — the
//      canonical editor is still 019_HosDutyStatus.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on the 3 clock numerics + cycle bar
//         fills. Brand.warning only for critical-violation inline.
//    §4   Tokenized spacing (Space.sN), radii (Radius.sm/md/lg), type
//         (EType.*). No magic numbers.
//    §5   Palette semantic throughout.
//    §7   Ternary ShapeStyle wrapped in AnyShapeStyle.
//    §10  Previews compile — HOSLiveStore lands in `.isLoading` under
//         the preview's no-baseURL runtime. No fixtures.
//

import SwiftUI

// MARK: - Screen root

struct MeHOSLogs: View {
    @Environment(\.palette) var palette
    @StateObject private var store = HOSLiveStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                if store.status == nil && store.isLoading {
                    skeleton
                } else {
                    clockHero
                    if !store.violations.isEmpty {
                        violationsStrip
                    }
                    cycleGrid
                    todayStrip
                }
                disclosureFooter
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.bootstrap() }
        .refreshable { await store.refreshAll() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("HOS Logs")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("§395.8 ELD · 8-day cycle · duty status")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Loading skeleton — graceful, not alarming

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.4))
                .frame(height: 140)
            HStack(spacing: Space.s2) {
                ForEach(0..<8, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.3))
                        .frame(height: 60)
                }
            }
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.3))
                .frame(height: 120)
        }
    }

    // MARK: Clock hero — drive / on-duty / cycle

    @ViewBuilder
    private var clockHero: some View {
        let status = store.status
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text(dutyLabel())
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if status?.breakRequired == true {
                    Text("BREAK DUE")
                        .font(EType.micro)
                        .tracking(1.2)
                        .foregroundStyle(Brand.warning)
                        .padding(.horizontal, Space.s2)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().strokeBorder(Brand.warning.opacity(0.6), lineWidth: 1)
                        )
                }
            }

            HStack(spacing: Space.s3) {
                clockTile(
                    label: "DRIVE",
                    hoursRemaining: status?.drivingRemaining,
                    hoursLimit: 11.0
                )
                clockTile(
                    label: "ON-DUTY",
                    hoursRemaining: status?.onDutyRemaining,
                    hoursLimit: 14.0
                )
                clockTile(
                    label: "70-HR CYCLE",
                    hoursRemaining: status?.cycleRemaining,
                    hoursLimit: 70.0
                )
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private func clockTile(label: String, hoursRemaining: Double?, hoursLimit: Double) -> some View {
        let remaining = hoursRemaining ?? 0
        let fraction = min(1.0, max(0.0, hoursLimit > 0 ? remaining / hoursLimit : 0))
        return VStack(alignment: .leading, spacing: Space.s1) {
            Text(label)
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Text(hoursRemaining == nil ? "—" : HOSStatus.formatHours(remaining))
                .font(EType.numeric)
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
            // Proportional fill bar — shows remaining vs. limit
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(palette.tintNeutral.opacity(0.4))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient.diagonal)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.6), lineWidth: 1)
        )
    }

    private func dutyLabel() -> String {
        guard let raw = store.status?.status else { return "Loading…" }
        switch HOSDutyCode(rawValue: raw) ?? .offDuty {
        case .offDuty:      return "Off Duty"
        case .sleeperBerth: return "Sleeper Berth"
        case .driving:      return "Driving"
        case .onDuty:       return "On Duty · Not Driving"
        }
    }

    // MARK: Violations strip

    @ViewBuilder
    private var violationsStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Brand.warning)
                Text("OPEN VIOLATIONS")
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(store.violations.count)")
                    .font(EType.micro)
                    .tracking(1.1)
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: Space.s2) {
                ForEach(Array(store.violations.prefix(3).enumerated()), id: \.offset) { _, v in
                    violationRow(v)
                }
            }
        }
    }

    private func violationRow(_ v: HOSViolation) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(v.message ?? "Compliance violation")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                if let ts = v.timestamp, let pretty = prettyTime(ts) {
                    Text(pretty)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: Space.s2)
            if let sev = v.severity {
                Text(sev.uppercased())
                    .font(EType.micro)
                    .tracking(1.1)
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, Space.s2)
                    .padding(.vertical, 2)
                    .background(Capsule().strokeBorder(Brand.warning.opacity(0.6), lineWidth: 1))
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    // MARK: 8-day cycle grid

    @ViewBuilder
    private var cycleGrid: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("8-DAY CYCLE")
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(store.history.count) logs")
                    .font(EType.micro)
                    .tracking(1.1)
                    .foregroundStyle(palette.textTertiary)
            }
            if store.history.isEmpty {
                HStack(spacing: Space.s3) {
                    Image(systemName: "calendar")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                    Text("No logs on file for the last 8 days.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                }
                .padding(Space.s3)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
                )
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(store.history.prefix(8)) { log in
                        dayRow(log)
                    }
                }
            }
        }
    }

    private func dayRow(_ log: HOSDailyLog) -> some View {
        let driveHours = Double(log.drivingMinutes) / 60.0
        // 11-hour drive ceiling per §395.3(a)(3)(i)
        let fraction = min(1.0, driveHours / 11.0)
        return HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(shortDayLabel(log.date))
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(log.drivingDisplay + " drive · " + log.onDutyDisplay + " on-duty")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: Space.s3)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(palette.tintNeutral.opacity(0.4))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient.diagonal)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(width: 72, height: 4)
            certChip(log.certified)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func certChip(_ certified: Bool) -> some View {
        if certified {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
                .accessibilityLabel("Certified")
        } else {
            Image(systemName: "seal")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(palette.textTertiary)
                .accessibilityLabel("Not certified")
        }
    }

    // MARK: Today's segment strip

    @ViewBuilder
    private var todayStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("TODAY · SEGMENTS")
                    .font(EType.micro)
                    .tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if let log = store.today {
                    Text("\(log.entries.count)")
                        .font(EType.micro)
                        .tracking(1.1)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            if let log = store.today, !log.entries.isEmpty {
                VStack(spacing: Space.s2) {
                    ForEach(log.entries) { entry in
                        segmentRow(entry)
                    }
                }
            } else {
                HStack(spacing: Space.s3) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                    Text("No duty segments recorded yet today.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                }
                .padding(Space.s3)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
                )
            }
        }
    }

    private func segmentRow(_ e: HOSLogEntry) -> some View {
        HStack(spacing: Space.s3) {
            dutyBadge(e.duty)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s2) {
                    Text(timeRange(e))
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    if let m = e.durationMinutes {
                        Text("· \(HOSStatus.formatHours(Double(m) / 60.0))")
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                if let loc = e.locationDescription, !loc.isEmpty {
                    Text(loc)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: Space.s2)
            if e.automaticEntry == true {
                Text("AUTO")
                    .font(EType.micro)
                    .tracking(1.1)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func dutyBadge(_ duty: HOSDutyCode) -> some View {
        Text(duty.shortLabel)
            .font(EType.micro)
            .tracking(1.3)
            .foregroundStyle(duty == .driving ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textSecondary))
            .frame(width: 32, height: 28)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(duty == .driving ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard.opacity(0.8)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(palette.borderFaint.opacity(0.6), lineWidth: 1)
            )
    }

    // MARK: Disclosure footer

    private var disclosureFooter: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Image(systemName: "scroll")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("Certify & edit")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text("This surface is read-only. To change duty status, sign a log, or edit a segment, head to the full HOS duty screen.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: Date helpers

    private func shortDayLabel(_ raw: String) -> String {
        guard let d = Self.ymd.date(from: raw) else { return raw }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        let out = DateFormatter()
        out.dateFormat = "EEE, MMM d"
        return out.string(from: d)
    }

    private func timeRange(_ e: HOSLogEntry) -> String {
        let start = clockTime(e.startDate)
        if let end = e.endDate {
            return "\(start)–\(clockTime(end))"
        }
        return "\(start) · now"
    }

    private func clockTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private func prettyTime(_ iso: String) -> String? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return nil }
        let out = DateFormatter()
        out.dateFormat = "MMM d · HH:mm"
        return out.string(from: d)
    }

    private static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - Screen wrapper

struct MeHOSLogsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeHOSLogs()
        } nav: {
            BottomNav(
                leading: driverNavLeading_074(),
                trailing: driverNavTrailing_074(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_074() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house.fill",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_074() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person.fill",      isCurrent: true)]
}

// MARK: - Previews

#Preview("074 · Me HOS Logs · Night") {
    MeHOSLogsScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("074 · Me HOS Logs · Afternoon") {
    MeHOSLogsScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
