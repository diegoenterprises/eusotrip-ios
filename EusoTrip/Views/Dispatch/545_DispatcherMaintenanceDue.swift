//
//  545_DispatcherMaintenanceDue.swift
//  EusoTrip — Dispatcher · Maintenance Due.
//
//  Verbatim SwiftUI port of:
//    `04 Dispatcher/Dark-SVG/545 Dispatcher Maintenance Due.svg`
//
//  BOARD archetype — a fleet PM status stacked bar over an urgency progress-bar
//  ROSTER: each power unit a row whose bar fills as it approaches its service
//  window (overdue overflows the track). Turns the fleet's preventive-
//  maintenance state into one ranked board so overdue trucks get serviced
//  before they break down on a dispatched lane.
//
//  Honest wiring — 0 stubs, fully dynamic (maintenance confirmed on disk
//  2026-07-11):
//    • READ  maintenance.getScheduled (…:112) → roster rows {vehicleId,
//            serviceType, nextDueDate, isOverdue, priority} + the status bar.
//    • READ  maintenance.getAlerts    (…:151) → "Alerts" surfaces the overdue
//            alert count.
//    • WRITE maintenance.schedule     (…:184, {vehicleId,type,description,
//            scheduledDate}) → "Schedule overdue" books each overdue unit.
//
//  HONEST NOTE: the maintenance schedule is DATE-based (nextDueDate + isOverdue)
//  and carries no odometer in its projection — so the roster bar fills by time-
//  to-due and the trailing metric is the real due date / OVERDUE status, not a
//  fabricated "+2,800 mi". Unit rows lead with the real vehicleId + service
//  type (no VIN/make in the projection).
//
//  Persona: Aurora Freight Lines · Renée Marquette (RM); fleet scope via
//  ctx.user.companyId. transportMode=truck. NAV: HOME · BOARD(current) · [orb]
//  · COMMS · ME. Author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Decoder

private struct MaintRow545: Decodable, Identifiable {
    let id: String
    let vehicleId: String
    let serviceType: String?
    let nextDueDate: String?      // ISO
    let isOverdue: Bool?
    let priority: String?

    var due: Date? {
        guard let s = nextDueDate, !s.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: s) ?? {
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: s)
        }()
    }
    var daysToDue: Int? {
        guard let d = due else { return nil }
        return Int(d.timeIntervalSinceNow / 86400)
    }
}

private enum PMState545 { case overdue, dueSoon, ok }

// MARK: - Screen

struct DispatcherMaintenanceDueScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { DispatcherMaintenanceDueBody() } nav: { DispatchPortNav() }
    }
}

// MARK: - Body

private struct DispatcherMaintenanceDueBody: View {
    @Environment(\.palette) private var palette

    @State private var rows: [MaintRow545] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var working = false
    @State private var actionNote: String?

    private func stateOf(_ r: MaintRow545) -> PMState545 {
        if r.isOverdue == true || (r.daysToDue ?? 99) < 0 { return .overdue }
        if (r.daysToDue ?? 99) <= 14 { return .dueSoon }
        return .ok
    }
    private var overdue: [MaintRow545] { rows.filter { stateOf($0) == .overdue } }
    private var dueSoon: [MaintRow545] { rows.filter { stateOf($0) == .dueSoon } }
    private var okCount: Int { rows.filter { stateOf($0) == .ok }.count }

    private var sorted: [MaintRow545] {
        rows.sorted { a, b in
            let sa = stateOf(a), sb = stateOf(b)
            func rank(_ s: PMState545) -> Int { s == .overdue ? 0 : (s == .dueSoon ? 1 : 2) }
            if rank(sa) != rank(sb) { return rank(sa) < rank(sb) }
            return (a.daysToDue ?? 9999) < (b.daysToDue ?? 9999)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline().padding(.top, Space.s3)

            if loading {
                DispatchPortLoadingCard(text: "Loading maintenance…").padding(.top, Space.s5)
            } else if let err = loadError, rows.isEmpty {
                DispatchPortErrorCard(message: err) { Task { await load() } }.padding(.top, Space.s5)
            } else if rows.isEmpty {
                EusoEmptyState(systemImage: "wrench.and.screwdriver.fill",
                               title: "No PM scheduled",
                               subtitle: "Preventive-maintenance intervals for the fleet's power units appear here as they come due.")
                    .padding(.top, Space.s6)
            } else {
                statusCard.padding(.top, Space.s5)
                roster.padding(.top, Space.s5)
                if let note = actionNote {
                    Text(note).font(EType.caption).foregroundStyle(palette.textSecondary).padding(.top, Space.s3)
                }
                ctaPair.padding(.top, Space.s5)
            }
        }
        .padding(.horizontal, 20).padding(.top, Space.s2)
        .task { await load() }
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("✦ DISPATCHER · MAINTENANCE")
                    .font(EType.micro).tracking(1.0).foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                Text("FLEET PM").font(EType.mono(.micro)).tracking(1.0).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                DispatchPortBackChevron()
                Text("Maintenance").font(EType.h1).tracking(-0.4).foregroundStyle(palette.textPrimary)
                Spacer(minLength: Space.s2)
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
        }
    }

    // MARK: Status hero (stacked bar)

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("PREVENTIVE MAINTENANCE · AURORA FLEET")
                .font(EType.micro).tracking(1.0).foregroundStyle(palette.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text("\(overdue.count)")
                    .font(.system(size: 32, weight: .bold).monospacedDigit()).foregroundStyle(Brand.danger)
                Text("overdue · \(dueSoon.count) due soon")
                    .font(EType.caption.weight(.bold)).foregroundStyle(palette.textPrimary)
                Spacer()
                Text("\(rows.count) power units").font(.system(size: 11)).foregroundStyle(palette.textTertiary)
            }

            GeometryReader { geo in
                let w = geo.size.width, total = max(1, rows.count)
                HStack(spacing: 3) {
                    seg(Double(overdue.count) / Double(total), w, Brand.danger.opacity(0.85))
                    seg(Double(dueSoon.count) / Double(total), w, Brand.warning.opacity(0.75))
                    seg(Double(okCount) / Double(total), w, Brand.success.opacity(0.6))
                }
            }
            .frame(height: 10)

            if let first = overdue.first ?? dueSoon.first {
                Text("Unit \(first.vehicleId) · \(ServiceMeta545.label(first.serviceType)) — schedule before next dispatch")
                    .font(EType.caption).foregroundStyle(palette.textPrimary)
            }
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.xl).fill(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    private func seg(_ frac: Double, _ w: CGFloat, _ color: Color) -> some View {
        Capsule().fill(color).frame(width: max(frac > 0 ? 8 : 0, (w - 6) * CGFloat(frac)))
    }

    // MARK: Roster

    private var roster: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("UNITS · TIME TO SERVICE")
                    .font(EType.micro).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("maintenance").font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, Space.s2)

            VStack(spacing: 0) {
                ForEach(Array(sorted.prefix(6).enumerated()), id: \.element.id) { idx, r in
                    unitRow(r)
                    if idx < min(6, sorted.count) - 1 {
                        Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                    }
                }
                if sorted.count > 6 {
                    Text("+ \(sorted.count - 6) more units · fleet scope · DU / Eusorone")
                        .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(Space.s4)
                }
            }
            .background(RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCardSoft))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint, lineWidth: 1))
        }
    }

    private func unitRow(_ r: MaintRow545) -> some View {
        let st = stateOf(r)
        let color: Color = st == .overdue ? Brand.danger : (st == .dueSoon ? Brand.warning : Brand.success)
        let label = st == .overdue ? "OVERDUE" : (st == .dueSoon ? "DUE SOON" : "OK")
        // urgency fill: overdue = full; else fills toward the 60-day window.
        let fill: CGFloat = {
            if st == .overdue { return 1.0 }
            let d = CGFloat(r.daysToDue ?? 60)
            return min(max(1 - d / 60, 0.06), 1)
        }()
        return HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Brand.rail.opacity(0.18))
                Image(systemName: "truck.box.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.rail)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text("Unit \(r.vehicleId)").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(ServiceMeta545.label(r.serviceType))
                    .font(EType.mono(.caption)).tracking(0.3).foregroundStyle(palette.textSecondary).lineLimit(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08)).frame(height: 6)
                        Capsule().fill(color).frame(width: geo.size.width * fill, height: 6)
                    }
                }
                .frame(height: 6)
            }
            Spacer(minLength: Space.s2)

            VStack(alignment: .trailing, spacing: 2) {
                Text(label).font(.system(size: 10, weight: .heavy)).tracking(0.4).foregroundStyle(color)
                Text(dueLabel(r)).font(EType.caption.weight(.bold).monospacedDigit()).foregroundStyle(palette.textPrimary)
            }
        }
        .padding(Space.s4)
    }

    private func dueLabel(_ r: MaintRow545) -> String {
        guard let d = r.daysToDue else { return "—" }
        if d < 0 { return "\(-d)d past" }
        if d == 0 { return "today" }
        return "in \(d)d"
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            Button { Task { await scheduleOverdue() } } label: {
                HStack(spacing: Space.s2) {
                    if working { ProgressView().tint(palette.textOnGradient) }
                    Text(working ? "Scheduling…" : "Schedule \(overdue.count) overdue")
                        .font(EType.bodyStrong).foregroundStyle(palette.textOnGradient).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            .disabled(working || overdue.isEmpty)
            .opacity(overdue.isEmpty ? 0.5 : 1)

            Button { Task { await fetchAlerts() } } label: {
                Text("Alerts").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    .frame(width: 110).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).fill(Color(hex: 0x232932)))
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            }
            .buttonStyle(.plain).disabled(working)
        }
    }

    // MARK: Data + actions

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable {}
        do {
            rows = try await EusoTripAPI.shared.query("maintenance.getScheduled", input: In())
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func scheduleOverdue() async {
        let targets = overdue
        guard !targets.isEmpty else { return }
        working = true; actionNote = nil
        let when = ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date())
        struct In: Encodable { let vehicleId: String; let type: String; let description: String; let scheduledDate: String }
        struct Out: Decodable { let success: Bool? }
        var booked = 0
        for r in targets {
            do {
                let _: Out = try await EusoTripAPI.shared.mutation(
                    "maintenance.schedule",
                    input: In(vehicleId: r.vehicleId, type: r.serviceType ?? "pm_service",
                              description: "Booked from dispatch maintenance board", scheduledDate: when))
                booked += 1
            } catch { /* tally honestly */ }
        }
        actionNote = booked == targets.count
            ? "Booked \(booked) overdue \(booked == 1 ? "unit" : "units") for service."
            : "Booked \(booked) of \(targets.count) — retry the rest."
        await load()
        working = false
    }

    private func fetchAlerts() async {
        working = true; actionNote = nil
        struct Row: Decodable {}
        do {
            let alerts: [Row] = try await EusoTripAPI.shared.queryNoInput("maintenance.getAlerts")
            actionNote = alerts.isEmpty ? "No open maintenance alerts." : "\(alerts.count) overdue \(alerts.count == 1 ? "alert" : "alerts") open."
        } catch {
            actionNote = "Couldn't load maintenance alerts."
        }
        working = false
    }
}

// MARK: - Service type metadata

private enum ServiceMeta545 {
    static func label(_ t: String?) -> String {
        guard let t, !t.isEmpty else { return "PM service" }
        return t.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Preview

#if DEBUG
#Preview("545 · Maintenance Due · Dark") {
    DispatcherMaintenanceDueScreen(theme: Theme.dark).environment(\.palette, Theme.dark)
}
#Preview("545 · Maintenance Due · Light") {
    DispatcherMaintenanceDueScreen(theme: Theme.light).environment(\.palette, Theme.light)
}
#endif
