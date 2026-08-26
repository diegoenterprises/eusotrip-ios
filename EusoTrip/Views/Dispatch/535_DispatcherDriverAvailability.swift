//
//  535_DispatcherDriverAvailability.swift
//  EusoTrip — Dispatcher · Driver Availability.
//
//  Verbatim SwiftUI port of:
//    `04 Dispatcher/Dark-SVG/535 Dispatcher Driver Availability.svg`
//
//  THE DRIVER AVAILABILITY SURFACE — before assigning an open load the
//  dispatcher needs a fast read on the fleet: who's free, who's already on a
//  load, who's in a reset. This screen ranks every unit by its live duty
//  state so the dispatcher can pick a driver in seconds. Reached from the
//  Board (401) as the availability surface.
//
//  Honest wiring — 0 stubs, 0 mock data, fully dynamic:
//    • READ  dispatcher.board (dispatcher.ts:32, query, {date?}) →
//            { drivers[] (id, name, status, hazmat, safetyScore, totalLoads),
//              loads[] (driverId, loadNumber, pickup/delivery), asOf }.
//            AVAILABLE / ON LOAD / RESET is derived by joining each driver to
//            their active load in loads[] — real duty state, no invented HOS
//            minute clock.
//    • The primary CTA routes to the real Dispatch Autopilot board (533),
//      which is the ESANG driver↔load auto-suggest surface (dispatchPlanner
//      .autoSuggest, dispatchPlanner.ts:469, feeds it). "Roster" opens the
//      registered Driver Board (Dpch701). No dead taps.
//
//  HONEST GAP: the fleet board carries duty status + safety score but not a
//  per-driver HOS-minute remaining window; that lives on the per-driver
//  dispatchPlanner.getDriverAvailability (dispatchPlanner.ts:417) call. Rows
//  show real status + safety score rather than a fabricated "6h 24m" clock.
//
//  Persona: Aurora Freight Lines · Renée Marquette (RM) dispatcher.
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: ─────────────────────────────────────────────────────────
// MARK: Decoders — field-for-field match to dispatcher.board
// MARK: ─────────────────────────────────────────────────────────

private struct FleetDriver: Decodable, Hashable, Identifiable {
    let id: Int
    let userId: Int?
    let name: String?
    let status: String?
    let hazmatEndorsement: Bool?
    let safetyScore: Int?
    let totalLoads: Int?
}

private struct FleetLoadStop: Decodable, Hashable {
    let city: String?
    let state: String?
}

private struct FleetLoad: Decodable, Hashable, Identifiable {
    let id: Int
    let loadNumber: String?
    let status: String?
    let driverId: Int?
    let pickup: FleetLoadStop?
    let delivery: FleetLoadStop?
}

private struct FleetBoardResponse: Decodable {
    let drivers: [FleetDriver]
    let loads: [FleetLoad]
    let asOf: String?
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: Derived roster unit (driver + duty state)
// MARK: ─────────────────────────────────────────────────────────

private struct RosterUnit: Identifiable, Hashable {
    enum Duty { case available, onLoad, reset, held }
    let id: Int
    let name: String
    let initials: String
    let sub: String        // safety score / assigned lane — real
    let duty: Duty
    let rightLabel: String
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: Screen
// MARK: ─────────────────────────────────────────────────────────

struct DispatcherDriverAvailabilityScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { DispatcherDriverAvailabilityBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Board", systemImage: "rectangle.split.3x1.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Comms", systemImage: "bubble.left.and.bubble.right.fill", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",                  isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct DispatcherDriverAvailabilityBody: View {
    @Environment(\.palette) private var palette

    @State private var drivers: [FleetDriver] = []
    @State private var loads: [FleetLoad] = []
    @State private var hosEvidence: [HOSFleetDriver] = []
    @State private var loading: Bool = true
    @State private var actionError: String?
    @State private var hosWarning: String?

    // driverId → their active load (terminal states already excluded by board).
    private var loadByDriver: [Int: FleetLoad] {
        var m: [Int: FleetLoad] = [:]
        for l in loads { if let d = l.driverId, m[d] == nil { m[d] = l } }
        return m
    }

    private var units: [RosterUnit] {
        drivers
            .filter { ($0.status ?? "").lowercased() != "suspended" }
            .map { d in
                let active = loadByDriver[d.id]
                let evidence = evidence(for: d)
                let duty = Fleet.duty(hasActiveLoad: active != nil, evidence: evidence)
                let name = d.name ?? "Unit \(d.id)"
                return RosterUnit(
                    id: d.id,
                    name: name,
                    initials: Fleet.initials(name),
                    sub: Fleet.sub(driver: d, active: active, evidence: evidence),
                    duty: duty,
                    rightLabel: Fleet.rightLabel(duty: duty, active: active, evidence: evidence)
                )
            }
            .sorted { rank($0.duty) < rank($1.duty) }
    }

    private func rank(_ d: RosterUnit.Duty) -> Int {
        switch d { case .available: return 0; case .onLoad: return 1; case .reset: return 2; case .held: return 3 }
    }

    private var availableCount: Int { units.filter { $0.duty == .available }.count }
    private var onLoadCount:    Int { units.filter { $0.duty == .onLoad }.count }
    private var resetCount:     Int { units.filter { $0.duty == .reset }.count }
    private var heldCount:      Int { units.filter { $0.duty == .held }.count }

    private func evidence(for driver: FleetDriver) -> HOSFleetDriver? {
        if let userId = driver.userId,
           let match = hosEvidence.first(where: { $0.userId == userId }) {
            return match
        }
        return hosEvidence.first { $0.driverId == String(driver.id) }
    }

    private var topRows: [RosterUnit] { Array(units.prefix(3)) }
    private var moreCount: Int { max(0, units.count - topRows.count) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline().padding(.top, Space.s3)

                if loading {
                    FleetSkeleton().padding(.top, Space.s5)
                } else if let err = actionError {
                    errorState(err)
                } else {
                    heroCard
                    if let hosWarning { hosWarningCard(hosWarning) }
                    kpiStrip
                    rosterList
                    autoSuggestCard
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        }
        .task { await load() }
        // RealtimeService → `dispatch:board_update`. Availability is a
        // direct function of who just got assigned; stale availability is
        // how a driver gets double-booked.
        .onReceive(NotificationCenter.default.publisher(for: .eusoDispatchBoardUpdated)) { _ in
            Task { await load() }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                EusoTripEyebrow(verbatim: "DISPATCHER · DRIVER AVAILABILITY")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                Text("\(units.count) UNITS")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Button { back() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
                Text("Driver availability")
                    .font(EType.h1).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: Space.s2)
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                chip("live")
                chip("fleet")
                Spacer(minLength: 0)
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(availableCount)")
                        .font(.system(size: 30, weight: .bold, design: .default).monospacedDigit())
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("drivers available")
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("\(onLoadCount) on a load · \(resetCount) in reset · \(heldCount) HOS held")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: Space.s3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("FLEET")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textSecondary)
                    Text("\(units.count)")
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                    Text("units")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: 20)
            .strokeBorder(LinearGradient.diagonal.opacity(0.85), lineWidth: 1.5))
        .padding(.top, Space.s5)
    }

    private func chip(_ label: String) -> some View {
        Text(label)
            .font(EType.micro).tracking(0.5)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, Space.s3).frame(height: 24)
            .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s3) {
            kpiCell("AVAILABLE", availableCount, tint: palette.textOnGradient, filled: true)
            kpiCell("ON LOAD",   onLoadCount,    tint: palette.textPrimary,    filled: false)
            kpiCell("HOS HELD",  resetCount + heldCount, tint: Brand.hazmat,   filled: false)
        }
        .padding(.top, Space.s4)
    }

    private func kpiCell(_ label: String, _ value: Int, tint: Color, filled: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(label)
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(filled ? palette.textOnGradient.opacity(0.85) : palette.textSecondary)
            Text("\(value)")
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .frame(height: 72)
        .background {
            if filled {
                RoundedRectangle(cornerRadius: 16).fill(LinearGradient.diagonal)
            } else {
                RoundedRectangle(cornerRadius: 16).fill(palette.bgCardSoft)
                RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint, lineWidth: 1)
            }
        }
    }

    // MARK: Roster list

    private var rosterList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("FLEET DUTY STATE")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text("dispatcher.board")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, Space.s2)

            VStack(spacing: 0) {
                if topRows.isEmpty {
                    emptyRoster
                } else {
                    ForEach(Array(topRows.enumerated()), id: \.element.id) { idx, u in
                        RosterRow(unit: u)
                        if idx < topRows.count - 1 {
                            Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                        }
                    }
                    if moreCount > 0 {
                        Text("+ \(moreCount) more · sorted by duty state")
                            .font(EType.micro)
                            .foregroundStyle(palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Space.s4)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCardSoft))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
        .padding(.top, Space.s5)
    }

    private var emptyRoster: some View {
        VStack(spacing: Space.s2) {
            Text("No drivers on the board")
                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text("Onboarded units appear here with their live duty state.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s6).padding(.horizontal, Space.s4)
    }

    // MARK: Auto-suggest card

    private var autoSuggestCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("AUTO-SUGGEST")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Text("dispatchPlanner.autoSuggest")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text("let ESANG rank the best driver for each open load")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
            Text("respects HOS, home-time and lane history")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint, lineWidth: 1))
        .padding(.top, Space.s4)
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button { autoSuggest() } label: {
                Text("Auto-suggest matches")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textOnGradient)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)

            Button { roster() } label: {
                Text("Roster")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Color(hex: 0x232932)))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Space.s5)
    }

    // MARK: Error state

    private func errorState(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Couldn't load the fleet board").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            Button { Task { await load() } } label: {
                Text("Retry").font(EType.caption.weight(.heavy))
                    .foregroundStyle(palette.textOnGradient)
                    .padding(.horizontal, Space.s4).frame(height: 32)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain).padding(.top, Space.s1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1))
        .padding(.top, Space.s5)
    }

    // MARK: Data + actions

    private func load() async {
        loading = true
        actionError = nil
        hosWarning = nil
        struct In: Encodable {}
        do {
            let r: FleetBoardResponse = try await EusoTripAPI.shared.query("dispatcher.board", input: In())
            drivers = r.drivers
            loads = r.loads
            do {
                hosEvidence = try await EusoTripAPI.shared.queryNoInput("hos.getFleetHOS")
            } catch {
                hosEvidence = []
                hosWarning = "Current company HOS evidence could not refresh. Every unassigned driver is held."
            }
        } catch {
            actionError = "The fleet board couldn't refresh. Retry from this screen or open the dispatch board."
        }
        loading = false
    }

    private func hosWarningCard(_ message: String) -> some View {
        Text(message)
            .font(EType.caption)
            .foregroundStyle(Brand.warning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s3)
            .background(RoundedRectangle(cornerRadius: Radius.md).fill(Brand.warning.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Brand.warning.opacity(0.4), lineWidth: 1))
            .padding(.top, Space.s3)
    }

    private func autoSuggest() {
        // Route to the real Dispatch Autopilot board (533) — the ESANG
        // driver↔load auto-suggest surface.
        NotificationCenter.default.post(name: .eusoDispatchNavSwap, object: nil, userInfo: ["screenId": "533"])
    }

    private func roster() {
        // Open the registered Driver Board (Dpch701).
        NotificationCenter.default.post(name: .eusoDispatchNavSwap, object: nil, userInfo: ["screenId": "Dpch701"])
    }

    private func back() {
        NotificationCenter.default.post(name: .eusoDispatchNavSwap, object: nil, userInfo: ["screenId": "Disp401"])
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: Roster row
// MARK: ─────────────────────────────────────────────────────────

private struct RosterRow: View {
    @Environment(\.palette) private var palette
    let unit: RosterUnit

    private var accent: Color {
        switch unit.duty {
        case .available: return Brand.success
        case .onLoad:    return Brand.hazmat
        case .reset:     return palette.textTertiary
        case .held:      return Brand.warning
        }
    }
    private var dutyLabel: String {
        switch unit.duty {
        case .available: return "AVAILABLE"
        case .onLoad:    return "ON LOAD"
        case .reset:     return "RESET"
        case .held:      return "HOS HELD"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(accent.opacity(0.18))
                Text(unit.initials)
                    .font(EType.micro).tracking(0.4)
                    .foregroundStyle(accent)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(unit.name)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(unit.sub)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)

            VStack(alignment: .trailing, spacing: 6) {
                Text(dutyLabel)
                    .font(EType.micro).tracking(0.5)
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Capsule().fill(accent.opacity(0.18)))
                Text(unit.rightLabel)
                    .font(EType.caption.weight(.heavy))
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(Space.s4)
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: Skeleton
// MARK: ─────────────────────────────────────────────────────────

private struct FleetSkeleton: View {
    @Environment(\.palette) private var palette
    var body: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: 20).fill(palette.bgCardSoft).frame(height: 116)
            HStack(spacing: Space.s3) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16).fill(palette.bgCardSoft).frame(height: 72)
                }
            }
            RoundedRectangle(cornerRadius: 16).fill(palette.bgCardSoft).frame(height: 252)
        }
        .redacted(reason: .placeholder)
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: Derivation helpers (real driver + load → duty state)
// MARK: ─────────────────────────────────────────────────────────

private enum Fleet {
    static func duty(hasActiveLoad: Bool, evidence: HOSFleetDriver?) -> RosterUnit.Duty {
        if hasActiveLoad { return .onLoad }
        guard let evidence else { return .held }
        if evidence.assignmentEligibility() == .eligible { return .available }
        if evidence.hasCurrentObservation(),
           (evidence.status == HOSDutyCode.offDuty.rawValue
                || evidence.status == HOSDutyCode.sleeperBerth.rawValue) {
            return .reset
        }
        return .held
    }

    static func sub(driver: FleetDriver, active: FleetLoad?, evidence: HOSFleetDriver?) -> String {
        if let a = active {
            let lane = laneText(a)
            return lane.isEmpty ? (a.loadNumber ?? "on load") : lane
        }
        guard let evidence else { return "HOS evidence unavailable" }
        if let reason = evidence.assignmentEligibility().reason { return reason }
        var parts: [String] = []
        if let source = evidence.source, !source.isEmpty { parts.append(source) }
        if let s = driver.safetyScore { parts.append("safety \(s)") }
        if driver.hazmatEndorsement == true { parts.append("hazmat") }
        if let t = driver.totalLoads { parts.append("\(t) loads") }
        return parts.isEmpty ? "ready" : parts.joined(separator: " · ")
    }

    static func rightLabel(duty: RosterUnit.Duty, active: FleetLoad?, evidence: HOSFleetDriver?) -> String {
        switch duty {
        case .available:
            return evidence?.hoursAvailable?.drivingRemaining.map { HOSStatus.formatHours($0) } ?? "HOS evidence unavailable"
        case .onLoad:    return active?.loadNumber ?? "on load"
        case .reset:     return "off duty"
        case .held:      return "not assignable"
        }
    }

    static func laneText(_ l: FleetLoad) -> String {
        let o = l.pickup?.city
        let d = l.delivery?.city
        switch (o, d) {
        case let (o?, d?): return "\(o) → \(d)"
        case let (o?, nil): return o
        case let (nil, d?): return "→ \(d)"
        default: return ""
        }
    }

    static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.compactMap { $0.first }.map(String.init).joined()
        return s.isEmpty ? "•" : s.uppercased()
    }
}

#if DEBUG
#Preview("535 · Dispatcher Driver Availability · Dark") {
    DispatcherDriverAvailabilityScreen(theme: Theme.dark)
        .environment(\.palette, Theme.dark)
}
#Preview("535 · Dispatcher Driver Availability · Light") {
    DispatcherDriverAvailabilityScreen(theme: Theme.light)
        .environment(\.palette, Theme.light)
}
#endif
