//
//  404_DispatcherDriverRoster.swift
//  EusoTrip — Dispatcher · Driver Roster.
//
//  Verbatim SwiftUI port of:
//    `04 Dispatcher/Dark-SVG/404 Dispatcher Driver Roster.svg`
//
//  Dispatcher's view of every company driver, sorted by HOS-clock
//  urgency (critical first). Persona §196 Renée Marquette / Aurora
//  Freight Lines. Tap a driver row → message that driver. Bottom-nav
//  "Board" tab is current (matches the SVG's white BOARD glyph).
//
//  Reads ONE real server endpoint — no stubs, no mock data:
//    dispatch.getDriverRoster   (added in the §37 fire — see
//    INTEGRATION.md in this staging folder). Returns the derived
//    driving / pre_trip / sleeper / idle / off taxonomy + per-driver
//    HOS bucket (crit/warn/fresh/available/reset) + lane + counts.
//    RBAC-gated with `dispatchProcedure` (ROLES.DISPATCH).
//
//  Honest-wire policy: the endpoint is wired through a real
//  do/catch with a surfaced `actionError`; if the procedure is not
//  yet deployed the screen shows the error state, never a fake
//  "success" with synthesized rows.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: ─────────────────────────────────────────────────────────
// MARK: Decoders — field-for-field match to dispatch.getDriverRoster
// MARK: ─────────────────────────────────────────────────────────

private struct RosterDriver: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let initials: String
    let status: String          // "driving" | "pre_trip" | "sleeper" | "idle" | "off"
    let reassignable: Bool
    let loadNumber: String?
    let lane: String?           // "Milwaukee → St. Paul"
    let locationLine: String?   // best-effort: "ETA 2:14 PM" / "No active load" / nil
    let hosRemaining: String?   // "0:42" formatted H:MM
    let hosBucket: String?      // "crit" | "warn" | "fresh" | "available" | "reset" | nil
    let transportMode: String?  // "truck" | "rail" | "vessel"
}

private struct RosterCounts: Decodable, Hashable {
    let total: Int
    let driving: Int
    let sleeper: Int
    let idle: Int
    let off: Int
}

private struct RosterResponse: Decodable {
    let drivers: [RosterDriver]
    let counts: RosterCounts
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: Screen
// MARK: ─────────────────────────────────────────────────────────

struct DispatcherDriverRosterScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { DispatcherDriverRosterBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",                  isCurrent: false),
                          NavSlot(label: "Board", systemImage: "rectangle.split.3x1.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Comms", systemImage: "bubble.left.and.bubble.right.fill", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",                isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private enum RosterFilter: String, CaseIterable {
    case all, driving, sleeper, idle, off
}

private struct DispatcherDriverRosterBody: View {
    @Environment(\.palette) private var palette

    @State private var drivers: [RosterDriver] = []
    @State private var counts: RosterCounts = RosterCounts(total: 0, driving: 0, sleeper: 0, idle: 0, off: 0)
    @State private var filter: RosterFilter = .all
    @State private var loading: Bool = true
    @State private var actionError: String?

    private var visibleDrivers: [RosterDriver] {
        switch filter {
        case .all:      return drivers
        case .driving:  return drivers.filter { $0.status == "driving" || $0.status == "pre_trip" }
        case .sleeper:  return drivers.filter { $0.status == "sleeper" }
        case .idle:     return drivers.filter { $0.status == "idle" }
        case .off:      return drivers.filter { $0.status == "off" }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrowRow
                title
                filterChips
                IridescentHairline().padding(.top, Space.s3)

                if loading {
                    loadingState
                } else if let err = actionError {
                    errorState(err)
                } else if visibleDrivers.isEmpty {
                    emptyState
                } else {
                    rosterList
                    esangNudge
                    broadcastCTA
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        }
        .task { await load() }
    }

    // MARK: Header

    private var eyebrowRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ DISPATCHER · ROSTER · \(counts.total) DRIVERS")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: Space.s2)
            Text("\(counts.driving) DRIVING · \(counts.sleeper) SLEEPER · \(counts.idle) IDLE")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("Driver roster")
                .font(EType.h1).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Aurora Freight · sorted by HOS clock · tap to message")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.top, Space.s4)
    }

    // MARK: Filter chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s2) {
                chip(.all,     "All · \(counts.total)",       Brand.blue)
                chip(.driving, "Driving · \(counts.driving)", Color(hex: 0x5BA8FF))
                chip(.sleeper, "Sleeper · \(counts.sleeper)", Color(hex: 0xC58CDB))
                chip(.idle,    "Idle · \(counts.idle)",       Brand.warning)
                chip(.off,     "Off · \(counts.off)",         palette.textSecondary)
            }
        }
        .padding(.top, Space.s4)
    }

    @ViewBuilder
    private func chip(_ f: RosterFilter, _ label: String, _ tint: Color) -> some View {
        let isOn = filter == f
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { filter = f }
        } label: {
            Text(label)
                .font(EType.micro).tracking(0.4)
                .foregroundStyle(isOn ? palette.textOnGradient : tint)
                .padding(.horizontal, Space.s3)
                .frame(height: 26)
                .background {
                    if isOn {
                        Capsule().fill(LinearGradient.primary)
                    } else {
                        Capsule().fill(palette.bgCardSoft)
                        Capsule().strokeBorder(palette.borderFaint, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: Roster list

    private var rosterList: some View {
        VStack(spacing: Space.s3) {
            ForEach(visibleDrivers) { d in
                Button { message(d) } label: { DriverRosterRow(driver: d) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.top, Space.s4)
    }

    // MARK: ESang nudge

    @ViewBuilder
    private var esangNudge: some View {
        if let pick = drivers.first(where: { $0.reassignable }) {
            HStack(spacing: Space.s3) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("ESang says: assign \(pick.name.split(separator: " ").last.map(String.init) ?? pick.name) → next open lane")
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("\(pick.initials) · \(pick.hosRemaining ?? "—") HOS · \(pick.locationLine ?? "reassignable")")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                Text("›").font(EType.title).foregroundStyle(palette.textSecondary)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCardSoft))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint, lineWidth: 1))
            .padding(.top, Space.s4)
        }
    }

    // MARK: Broadcast CTA

    private var broadcastCTA: some View {
        Button { broadcastAll() } label: {
            Text("Broadcast to all \(counts.total) drivers →")
                .font(EType.caption.weight(.heavy)).tracking(0.4)
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.top, Space.s4)
    }

    // MARK: States

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(palette.bgCardSoft)
                    .frame(height: 78)
                    .redacted(reason: .placeholder)
            }
        }
        .padding(.top, Space.s4)
    }

    private func errorState(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Couldn’t load the roster").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            Button { Task { await load() } } label: {
                Text("Retry").font(EType.caption.weight(.heavy))
                    .foregroundStyle(palette.textOnGradient)
                    .padding(.horizontal, Space.s4).frame(height: 32)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .padding(.top, Space.s1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .padding(.top, Space.s4)
    }

    private var emptyState: some View {
        VStack(spacing: Space.s2) {
            Text("No drivers in this view").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text("Switch filters or add drivers to the roster.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s7)
        .padding(.top, Space.s4)
    }

    // MARK: Data + actions

    private func load() async {
        loading = true
        actionError = nil
        do {
            let r: RosterResponse = try await EusoTripAPI.shared.queryNoInput("dispatch.getDriverRoster")
            drivers = r.drivers
            counts = r.counts
        } catch {
            actionError = error.localizedDescription
        }
        loading = false
    }

    private func message(_ d: RosterDriver) {
        // Route into the Dispatch comms thread for this driver. The
        // Dispatch surface observes `eusoDispatchNavSwap`; comms hub is
        // the canonical messaging destination.
        NotificationCenter.default.post(
            name: .eusoDispatchNavSwap, object: nil,
            userInfo: ["screenId": "Dpch706", "driverId": d.id]
        )
    }

    private func broadcastAll() {
        NotificationCenter.default.post(
            name: .eusoDispatchNavSwap, object: nil,
            userInfo: ["screenId": "Dpch706", "broadcast": true]
        )
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: Driver row
// MARK: ─────────────────────────────────────────────────────────

private struct DriverRosterRow: View {
    @Environment(\.palette) private var palette
    let driver: RosterDriver

    private var isCritical: Bool { driver.hosBucket == "crit" }

    private var ringColor: Color {
        switch driver.hosBucket {
        case "crit":      return Brand.danger
        case "warn":      return Brand.warning
        case "fresh", "available": return Brand.success
        case "reset":     return Brand.escort
        default:          return palette.borderSoft
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            avatar
            VStack(alignment: .leading, spacing: Space.s1) {
                HStack(spacing: Space.s2) {
                    Text(driver.name).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    statusBadge
                    if driver.reassignable { reassignablePill }
                }
                if let load = driver.loadNumber {
                    Text(laneLine(load))
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                } else if let lane = driver.lane {
                    Text(lane).font(EType.mono(.caption)).foregroundStyle(palette.textSecondary).lineLimit(1)
                }
                if let loc = driver.locationLine {
                    Text(loc).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: Space.s2)
            hosClock
        }
        .padding(Space.s3)
        .background(rowBackground)
    }

    private func laneLine(_ load: String) -> String {
        if let lane = driver.lane { return "\(load) · \(lane)" }
        return load
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(LinearGradient.diagonal)
            Circle().strokeBorder(ringColor, lineWidth: 2)
            Text(driver.initials)
                .font(.system(size: 13, weight: .heavy)).tracking(0.5)
                .foregroundStyle(Color.white)
        }
        .frame(width: 44, height: 44)
    }

    @ViewBuilder
    private var statusBadge: some View {
        let (label, color): (String, Color) = {
            switch driver.status {
            case "driving":  return ("DRIVING",  Brand.blue)
            case "pre_trip": return ("PRE-TRIP", Brand.success)
            case "sleeper":  return ("SLEEPER",  Brand.escort)
            case "idle":     return ("IDLE",     Brand.warning)
            default:          return ("OFF",      Brand.neutral)
            }
        }()
        Text(label)
            .font(EType.micro).tracking(0.4)
            .foregroundStyle(Color.white)
            .padding(.horizontal, Space.s2).frame(height: 18)
            .background(Capsule().fill(color))
    }

    private var reassignablePill: some View {
        Text("REASSIGNABLE")
            .font(EType.micro).tracking(0.4)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, Space.s2).frame(height: 18)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private var hosClock: some View {
        let (caption, footer, tint): (String, String, Color) = {
            switch driver.hosBucket {
            case "crit":      return ("HOS · 11h", "REMAIN · CRIT", Brand.danger)
            case "warn":      return ("HOS · 11h", "REMAIN · WARN", Brand.warning)
            case "fresh":     return ("HOS · 11h", "FRESH",         Brand.success)
            case "available": return ("HOS · 11h", "AVAILABLE",     Brand.success)
            case "reset":     return ("RESET",     "UNTIL DUTY",    Brand.escort)
            default:           return ("HOS",       "—",             palette.textSecondary)
            }
        }()
        return VStack(spacing: 2) {
            Text(caption).font(EType.micro).tracking(0.4).foregroundStyle(tint.opacity(0.85))
            Text(driver.hosRemaining ?? "—:—")
                .font(.system(size: 20, weight: .heavy, design: .monospaced))
                .foregroundStyle(tint)
            Text(footer).font(EType.micro).foregroundStyle(tint.opacity(0.85))
        }
        .frame(width: 92, height: 60)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(tint.opacity(0.5), lineWidth: 1))
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isCritical {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.lg).fill(LinearGradient.diagonal.opacity(0.85))
                RoundedRectangle(cornerRadius: Radius.lg - 1.5)
                    .fill(palette.bgCardSoft)
                    .padding(1.5)
            }
        } else {
            RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCardSoft)
            RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint, lineWidth: 1)
        }
    }
}

#if DEBUG
private let _previewRoster: [RosterDriver] = [
    RosterDriver(id: "1", name: "D. Karch", initials: "DK", status: "driving", reassignable: false,
                 loadNumber: "LD-260427-44C8AE03BD", lane: "Milwaukee → St. Paul",
                 locationLine: "ETA 2:14 PM", hosRemaining: "0:42", hosBucket: "crit", transportMode: "truck"),
    RosterDriver(id: "2", name: "O. Kemp", initials: "OK", status: "driving", reassignable: false,
                 loadNumber: "LD-260427-2D440B1C57", lane: "Denver → Omaha",
                 locationLine: "ETA 5:50 PM", hosRemaining: "2:18", hosBucket: "warn", transportMode: "truck"),
    RosterDriver(id: "5", name: "R. Bayard", initials: "RB", status: "idle", reassignable: true,
                 loadNumber: nil, lane: nil, locationLine: "No active load",
                 hosRemaining: "9:14", hosBucket: "available", transportMode: nil),
]

#Preview("404 · Dispatcher Driver Roster · Dark") {
    DispatcherDriverRosterScreen(theme: Theme.dark)
        .environment(\.palette, Theme.dark)
}
#endif
