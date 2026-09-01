//
//  400_DispatcherHome.swift
// OFFLINE: READ_CACHED(5m) KPIs + board + ATTENTION tenders; staleness line "Offline · data as of 09:41" under the KPI strip; reads-only, nothing queues; reconnect FULL.
//  EusoTrip — Dispatcher · Home (live desk).
//
//  Verbatim reconstruction of wireframe "400 Dispatcher Home · Dark"
//  (canvas 440×956). Faithful to layout, copy, element order, colors and
//  spacing proportions; only absolute sizes are tuned for responsive fit.
//
//  Persona §196 (canonical, mirrors Light): Aurora Freight Lines LLC ·
//  Renée Marquette · USDOT 3 482 119 · Cedar Rapids IA · 18 trucks ·
//  14 active hauls.
//
//  RBAC: dispatcherProcedure. transportMode: TRUCK. country: US.
//
//  Wiring (honest):
//    • dispatch.getKPI            — EXISTS  (queryNoInput) — KPI strip
//    • dispatch.getActiveIssues   — EXISTS  (queryNoInput) — attention row count
//    • dispatch.getDriverStatuses — EXISTS  (query)        — live-drivers strip
//    • dispatch.getPendingTenders — EXISTS  (query)        — top-tender queue
//    • dispatch.acceptTender      — EXISTS  (mutation)     — YES action
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//

import SwiftUI

struct DispatcherHomeScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette = Theme.dark) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) { DispatcherHomeBody() } nav: {
            BottomNav(
                leading: DispatchNavRoute.leading(current: .home),
                trailing: DispatchNavRoute.trailing(current: .home),
                orbState: .idle
            )
        }
    }
}

// MARK: - Wire models

private struct DispatcherKPI: Decodable, Hashable {
    let pendingTenders: Int?
    let activeLoads: Int?
    let driversIdle: Int?
    let onTimePct: Double?
    let avgUtilizationPct: Int?
}

private struct DispatcherIssue: Decodable, Identifiable, Hashable {
    let id: String
    let type: String?
    let severity: String?
    let loadNumber: String?
    let createdAt: String?
}

private struct DispatcherDriverStatus: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let status: String?
    let load: String?
}

/// `dispatch.getPendingTenders` row.
private struct PendingTender: Decodable, Identifiable, Hashable {
    let id: String
    let lane: String?
    let equipment: String?
    let loadNumber: String?
    let rate: Double?
    let weightLb: Int?
    let broker: String?
    let expiresInMinutes: Int?
    let suggestedDriver: String?
    let isPeer: Bool?
    let awardedTo: String?
    let hazmatUN: String?
    let miles: Int?
}

// MARK: - Body

private struct DispatcherHomeBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @State private var kpi: DispatcherKPI? = nil
    @State private var issues: [DispatcherIssue] = []
    @State private var drivers: [DispatcherDriverStatus] = []
    @State private var hosEvidence: [HOSFleetDriver] = []
    @State private var hosEvidenceError: String? = nil
    @State private var tenders: [PendingTender] = []

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var tenderError: String? = nil
    @State private var actionError: String? = nil
    @State private var acceptingId: String? = nil

    private let widgetLayoutKey = "dispatcher.home.widgetOrder"
    private let dispatchCanonicalOrder = [
        "priority", "dispatch_summary", "tender_queue", "dispatch_esang",
        "hosWatch", "exceptions_list"
    ]

    private var dispatcherDisplayName: String {
        let raw = session.user?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "Dispatcher" : raw
    }

    private var dispatcherFirstName: String {
        let first = dispatcherDisplayName.split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? "Dispatcher" : first
    }

    private var dispatchSummaryLine: String {
        if loading { return "Dispatch desk · updating" }
        if loadError != nil { return "Dispatch desk · data unavailable" }
        guard let active = kpi?.activeLoads else {
            let label = drivers.count == 1 ? "driver" : "drivers"
            return "Dispatch desk · \(drivers.count) \(label) · active hauls not reported"
        }
        let label = drivers.count == 1 ? "driver" : "drivers"
        return "Dispatch desk · \(drivers.count) \(label) · \(active) active hauls"
    }

    private func dispatchHomeRender(_ id: String) -> AnyView {
        switch id {
        case "priority":         AnyView(dispatchPriorityWidget)
        case "dispatch_summary": AnyView(dispatchSummaryWidget)
        case "tender_queue":      AnyView(dispatchTenderWidget)
        case "dispatch_esang":    AnyView(dispatchESangWidget)
        case "hosWatch":          AnyView(dispatchHOSWidget)
        case "exceptions_list":   AnyView(dispatchExceptionsWidget)
        default:                   AnyView(EmptyView())
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            // First-load unlock cascade: top-level sections spring in
            // top-to-bottom (scale 0.92 + blur 5pt + 50 ms stagger) once
            // per cold launch; settled on re-visit. Reduce-Motion → fade.
            StaggeredEntranceStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                greeting
                IridescentHairline()

                HomeWidgetGrid(
                    canonicalOrder: dispatchCanonicalOrder,
                    role: "DISPATCH",
                    storageKey: widgetLayoutKey,
                    weather: {
                        AnyView(HomeWeatherWidget(includeLaneImpact: (kpi?.activeLoads ?? 0) > 0))
                    },
                    render: { id in dispatchHomeRender(id) }
                )

                // The shell navigation floats over the scroll surface. Keep
                // expanded weather and the final driver row fully reachable.
                Color.clear.frame(height: 112)
            }
            .padding(.horizontal, 20).padding(.top, 12)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
        // RealtimeService → `dispatch:board_update`. The desk is the
        // dispatcher's landing surface; every board mutation (assign,
        // autopilot, tender flip, exception) must land here without
        // waiting for a pull.
        .onReceive(NotificationCenter.default.publisher(for: .eusoDispatchBoardUpdated)) { _ in
            Task { await load() }
        }
    }

    // MARK: TopBar eyebrow

    private var eyebrow: some View {
        HStack(alignment: .top) {
            EusoTripEyebrow("DISPATCHER · DESK · LIVE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 0)
            Text(tickerLine)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var tickerLine: String {
        if loading { return "UPDATING" }
        let active = kpi?.activeLoads.map(String.init) ?? "—"
        let pending = kpi?.pendingTenders.map(String.init) ?? "—"
        let expiring = tenderError == nil
            ? String(tenders.filter { ($0.expiresInMinutes ?? .max) < 60 && ($0.isPeer != true) }.count)
            : "—"
        return "\(active) ACTIVE · \(pending) PENDING · \(expiring) EXPIRING"
    }

    // MARK: Widget state boundaries

    @ViewBuilder
    private var dispatchPriorityWidget: some View {
        if loading {
            widgetLoading("Loading priority tenders")
        } else if let tenderError {
            widgetError(tenderError) { Task { await loadTenders() } }
        } else {
            attentionRow
        }
    }

    @ViewBuilder
    private var dispatchSummaryWidget: some View {
        if loading {
            widgetLoading("Loading dispatch summary")
        } else if let loadError {
            widgetError(loadError) { Task { await load() } }
        } else {
            kpiStrip
        }
    }

    @ViewBuilder
    private var dispatchTenderWidget: some View {
        if loading { widgetLoading("Loading tender queue") } else { topTenders }
    }

    @ViewBuilder
    private var dispatchESangWidget: some View {
        if loading {
            widgetLoading("Loading dispatch counsel")
        } else if loadError != nil, tenderError != nil {
            widgetError("Dispatch counsel is waiting for current board evidence.") {
                Task { await load() }
            }
        } else {
            esangStrip
        }
    }

    @ViewBuilder
    private var dispatchHOSWidget: some View {
        if loading {
            widgetLoading("Loading driver duty evidence")
        } else if let loadError {
            widgetError(loadError) { Task { await load() } }
        } else {
            liveDrivers
        }
    }

    @ViewBuilder
    private var dispatchExceptionsWidget: some View {
        if loading {
            widgetLoading("Loading dispatch exceptions")
        } else if let loadError {
            widgetError(loadError) { Task { await load() } }
        } else {
            issuesRegister
        }
    }

    private func widgetLoading(_ message: String) -> some View {
        LifecycleCard {
            HStack(spacing: Space.s2) {
                ProgressView().controlSize(.small)
                Text(message)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func widgetError(_ message: String, retry: @escaping () -> Void) -> some View {
        LifecycleCard(accentDanger: true) {
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Brand.danger)
                Text(message)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: Space.s2)
                Button("Retry", action: retry)
                    .font(EType.micro.weight(.bold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Brand.blue)
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
    }

    private var greeting: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hey, \(dispatcherFirstName)")
                    .font(.system(size: 34, weight: .bold)).tracking(-0.6)
                    .foregroundStyle(palette.textPrimary)
                Text(dispatchSummaryLine)
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            EditableProfileAvatar(size: 56)
        }
    }

    // MARK: ATTENTION row (gradient-rimmed feature card)

    private var attentionRow: some View {
        let expiring = tenders.filter { ($0.expiresInMinutes ?? .max) < 60 && ($0.isPeer != true) }
            .sorted { ($0.expiresInMinutes ?? .max) < ($1.expiresInMinutes ?? .max) }
        let count = expiring.count
        let soonest = expiring.first
        return ActiveCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("ATTENTION · \(count) EXP")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(Brand.hazmat)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Brand.hazmat.opacity(0.18)))
                    Spacer(minLength: 0)
                    Text(soonest.map {
                        "\(($0.expiresInMinutes ?? 0)) min · LD ending \(String(($0.loadNumber ?? "-").suffix(4)))"
                    } ?? "no tender expiring")
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
                HStack(alignment: .center, spacing: 16) {
                    Text("\(count)")
                        .font(.system(size: 38, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("tenders expire < 60 min")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text(attentionLaneSummary(expiring))
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                Button {
                    openBoard()
                } label: {
                    Text("Open the Board →")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(LinearGradient.primary).clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func attentionLaneSummary(_ items: [PendingTender]) -> String {
        guard !items.isEmpty else { return "all tenders steady" }
        let lanes = items.prefix(2).map { $0.lane ?? "-" }
        let extra = items.count - lanes.count
        return extra > 0 ? "\(lanes.joined(separator: " · ")) · +\(extra)" : lanes.joined(separator: " · ")
    }

    // MARK: KPI strip · 4-up

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            kpiTile(label: "PENDING TENDERS",
                    value: kpi?.pendingTenders.map(String.init) ?? "—",
                    valueColor: Brand.warning,
                    foot: tenderError == nil
                        ? "\(tenders.filter { ($0.expiresInMinutes ?? .max) < 60 && $0.isPeer != true }.count) expire < 1h"
                        : "tender timing unavailable",
                    footColor: palette.textSecondary)
            kpiTile(label: "ACTIVE HAULS",
                    value: kpi?.activeLoads.map(String.init) ?? "—",
                    valueColor: palette.textPrimary,
                    foot: kpi?.onTimePct.map { "on time · \(Int($0.rounded()))%" } ?? "on-time rate not reported",
                    footColor: Brand.success)
            kpiTile(label: "DRIVERS IDLE",
                    value: kpi?.driversIdle.map(String.init) ?? "—",
                    valueGradient: true,
                    foot: idleHosFoot,
                    footColor: palette.textSecondary)
            kpiTile(label: "OTR · 90D",
                    value: kpi?.onTimePct.map { String(format: "%.1f%%", $0) } ?? "—",
                    valueGradient: true,
                    foot: kpi?.avgUtilizationPct.map { "util \($0)%" } ?? "utilization not reported",
                    footColor: Brand.success)
        }
    }

    private var idleHosFoot: String {
        let idle = drivers.filter { ($0.status ?? "").lowercased().contains("idle") }
        guard !idle.isEmpty else {
            let reported = kpi?.driversIdle ?? 0
            return reported > 0 ? "HOS evidence unavailable" : "none reported idle"
        }
        let currentHours = idle.compactMap { driver -> Double? in
            guard let evidence = evidence(for: driver.id),
                  evidence.hasCurrentObservation(),
                  let hours = evidence.hoursAvailable?.drivingRemaining,
                  hours.isFinite,
                  hours >= 0 else { return nil }
            return hours
        }
        guard currentHours.count == idle.count else {
            return hosEvidenceError ?? "HOS evidence incomplete"
        }
        let avg = currentHours.reduce(0, +) / Double(currentHours.count)
        let h = Int(avg); let m = Int((avg - Double(h)) * 60)
        return "avg HOS \(h)h \(m)m"
    }

    private func kpiTile(label: String, value: String,
                         valueColor: Color = .primary,
                         valueGradient: Bool = false,
                         foot: String, footColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Group {
                if valueGradient {
                    Text(value).foregroundStyle(LinearGradient.diagonal)
                } else {
                    Text(value).foregroundStyle(valueColor)
                }
            }
            .font(.system(size: 24, weight: .semibold)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.5)
            Text(foot)
                .font(.system(size: 11)).foregroundStyle(footColor)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Top Tenders queue

    private var topTenders: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TOP TENDERS · ACT FAST")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Button {
                    openBoard()
                } label: {
                    Text("See all (\(kpi?.pendingTenders ?? tenders.count))")
                        .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 0) {
                if let actionError {
                    Text(actionError)
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }
                if let te = tenderError {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tender queue unavailable")
                            .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        Text(te)
                            .font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                } else if tenders.isEmpty {
                    EusoEmptyState(systemImage: "tray",
                                   title: "No pending tenders",
                                   subtitle: "Nothing waiting for assignment right now.")
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(tenders.prefix(3).enumerated()), id: \.element.id) { idx, t in
                        tenderRow(t)
                        if idx < min(tenders.count, 3) - 1 {
                            Divider().overlay(palette.borderFaint).padding(.leading, 16)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func tenderRow(_ t: PendingTender) -> some View {
        let peer = (t.isPeer == true)
        let hazmat = (t.hazmatUN != nil)
        return HStack(alignment: .top, spacing: 12) {
            // Icon glyph tile.
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill((hazmat ? Brand.hazmat : Brand.info).opacity(hazmat ? 0.20 : 0.18))
                Image(systemName: hazmat ? "diamond" : "thermometer.medium")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(hazmat ? Brand.hazmat : Color(hex: 0x54A8E8))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(t.lane ?? "-")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(tenderMeta(t))
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary).lineLimit(1)
                Text(tenderStatus(t))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(peer ? palette.textSecondary : Brand.warning)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if peer {
                Text("peer · view")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(palette.bgCardSoft))
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
            } else {
                HStack(spacing: 6) {
                    Button {
                        Task { await acceptTender(t) }
                    } label: {
                        Group {
                            if acceptingId == t.id {
                                ProgressView().tint(.white).controlSize(.mini)
                            } else {
                                Text("YES").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                            }
                        }
                        .frame(width: 40, height: 22)
                        .background(LinearGradient.primary).clipShape(Capsule())
                    }
                    .buttonStyle(.plain).disabled(acceptingId != nil)
                    Text("···")
                        .font(.system(size: 10, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        .frame(width: 40, height: 22)
                        .background(Capsule().fill(palette.bgCard))
                        .overlay(Capsule().strokeBorder(palette.borderSoft))
                }
            }
        }
        .padding(16)
    }

    private func tenderMeta(_ t: PendingTender) -> String {
        var parts: [String] = []
        if let ln = t.loadNumber { parts.append(ln) }
        if let r = t.rate { parts.append("$\(Int(r).formatted())") }
        if let un = t.hazmatUN { parts.append(un) }
        else if let w = t.weightLb { parts.append("\(Int(w / 1000))k lb") }
        if let mi = t.miles { parts.append("\(mi) mi") }
        else if let b = t.broker { parts.append(b) }
        return parts.joined(separator: " · ")
    }

    private func tenderStatus(_ t: PendingTender) -> String {
        if t.isPeer == true, let award = t.awardedTo {
            let exp = t.expiresInMinutes.map { expiryLabel($0) } ?? "-"
            return "expires \(exp) · awarded \(award)"
        }
        let exp = t.expiresInMinutes.map { expiryLabel($0) } ?? "-"
        if let d = t.suggestedDriver { return "expires \(exp) · suggest \(d)" }
        return "expires \(exp)"
    }

    private func expiryLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    // MARK: ESang strip

    private var esangStrip: some View {
        let pick = tenders.first { $0.isPeer != true && $0.suggestedDriver != nil }
        return Button {
            NotificationCenter.default.post(
                name: .eusoDispatcheSangTapped,
                object: nil,
                userInfo: [
                    "surface": "dispatcher_home",
                    "activeLoads": kpi?.activeLoads ?? 0,
                    "pendingTenders": kpi?.pendingTenders ?? tenders.count,
                    "driversRolling": rollingDriverCount
                ]
            )
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.75), .white.opacity(0)],
                                             center: .init(x: 0.35, y: 0.30),
                                             startRadius: 0, endRadius: 16))
                        .frame(width: 16, height: 16).offset(x: -5, y: -5)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(esangHeadline(pick))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.textPrimary).lineLimit(1)
                    Text(esangReason(pick))
                        .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textSecondary)
            }
            .padding(12)
            .frame(minHeight: 56)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func esangHeadline(_ tender: PendingTender?) -> String {
        if tenderError != nil { return "ESANG is waiting for the current tender queue" }
        if let tender {
            return "ESANG says: tender \(tender.lane ?? "this lane") to \(tender.suggestedDriver ?? "best driver")"
        }
        return "ESANG says: queue is steady, no urgent tender"
    }

    private func esangReason(_ t: PendingTender?) -> String {
        guard let t, let d = drivers.first(where: { $0.name.contains(t.suggestedDriver ?? "∅") }) else {
            return "driver-board recommendation · HOS evidence unavailable"
        }
        guard let evidence = evidence(for: d.id),
              evidence.hasCurrentObservation(),
              let hours = evidence.hoursAvailable?.drivingRemaining else {
            return "driver-board recommendation · HOS evidence unavailable"
        }
        return "HOS \(HOSStatus.formatHours(hours)) · \(evidence.source ?? "source unavailable") · driver-board recommendation"
    }

    // MARK: Live drivers strip

    private var liveDrivers: some View {
        let rolling = rollingDriverCount
        let idle = drivers.filter {
            let status = ($0.status ?? "").lowercased()
            return status.contains("idle") || status.contains("available")
        }.count
        let off  = drivers.filter { ($0.status ?? "").lowercased().contains("off") }.count
        return Button {
            openDriverRoster()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("LIVE DRIVERS · \(rolling) ROLLING")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: 0)
                    Text("Open roster")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                }
                HStack(spacing: 8) {
                    ForEach(drivers.prefix(7)) { d in driverDisc(d) }
                    if drivers.count > 7 {
                        Text("+\(drivers.count - 7)")
                            .font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(palette.bgCardSoft))
                            .overlay(Circle().strokeBorder(palette.borderFaint))
                    }
                    Spacer(minLength: 0)
                }
                Text("\(rolling) rolling · \(idle) idle · \(off) off-clock")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var issuesRegister: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("ACTIVE EXCEPTIONS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("\(issues.count)")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            if issues.isEmpty {
                EusoEmptyState(
                    systemImage: "checkmark.circle",
                    title: "No active exceptions",
                    subtitle: "The current dispatch scope has no reported exceptions."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(issues.prefix(4).enumerated()), id: \.element.id) { index, issue in
                        issueRow(issue)
                        if index < min(issues.count, 4) - 1 {
                            Divider().overlay(palette.borderFaint)
                        }
                    }
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            }
        }
    }

    private func issueRow(_ issue: DispatcherIssue) -> some View {
        let severe = ["critical", "danger", "high"].contains((issue.severity ?? "").lowercased())
        let tint = severe ? Brand.danger : Brand.warning
        return HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: severe ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text((issue.type ?? "Dispatch exception").replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text([issue.loadNumber, issue.createdAt].compactMap { $0 }.joined(separator: " · "))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
    }

    private var rollingDriverCount: Int {
        drivers.filter { ($0.status ?? "").lowercased().contains("rolling") || ($0.status ?? "").lowercased().contains("driving") }.count
    }

    private func driverDisc(_ d: DispatcherDriverStatus) -> some View {
        let dot: Color = {
            switch (d.status ?? "").lowercased() {
            case let s where s.contains("rolling") || s.contains("driving"): return Brand.success
            case let s where s.contains("idle") || s.contains("available"): return Brand.warning
            default: return palette.textTertiary
            }
        }()
        return ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle().fill(LinearGradient.diagonal)
                Text(initials(d.name))
                    .font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)
            Circle().fill(dot)
                .frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(palette.bgCard, lineWidth: 2))
        }
        .frame(width: 32, height: 32)
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }

    // MARK: - Load pipeline

    private func load() async {
        loading = true; loadError = nil
        struct DriverIn: Encodable { let limit: Int }
        async let hosRefresh: Void = loadHOSEvidence()
        do {
            async let kpiR: DispatcherKPI = EusoTripAPI.shared.queryNoInput("dispatch.getKPI")
            async let issuesR: [DispatcherIssue] = EusoTripAPI.shared.queryNoInput("dispatch.getActiveIssues")
            async let driversR: [DispatcherDriverStatus] = EusoTripAPI.shared.query(
                "dispatch.getDriverStatuses", input: DriverIn(limit: 100))
            let (k, iss, drv) = try await (kpiR, issuesR, driversR)
            kpi = k
            issues = iss
            drivers = drv
        } catch {
            loadError = "Dispatch desk couldn't refresh. Pull down to try again."
        }
        await hosRefresh
        // Tenders load independently so a temporary provider/API issue does
        // not blank the rest of the desk.
        await loadTenders()
        loading = false
    }

    private func loadHOSEvidence() async {
        do {
            hosEvidence = try await EusoTripAPI.shared.queryNoInput("hos.getFleetHOS")
            hosEvidenceError = nil
        } catch {
            hosEvidence = []
            hosEvidenceError = "HOS evidence unavailable"
        }
    }

    private func evidence(for driverId: String) -> HOSFleetDriver? {
        hosEvidence.first { row in
            row.driverId == driverId || row.userId.map { String($0) } == driverId
        }
    }

    private func loadTenders() async {
        tenderError = nil
        struct In: Encodable { let limit: Int }
        do {
            let r: [PendingTender] = try await EusoTripAPI.shared.query(
                "dispatch.getPendingTenders", input: In(limit: 8))
            tenders = r
        } catch {
            tenders = []
            tenderError = "Pending tenders could not refresh. Pull down to retry or open the board."
        }
    }

    private func acceptTender(_ t: PendingTender) async {
        acceptingId = t.id; actionError = nil
        struct In: Encodable { let tenderId: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "dispatch.acceptTender", input: In(tenderId: t.id))
            await loadTenders()
        } catch {
            actionError = "Tender could not be accepted. Refresh and try again."
        }
        acceptingId = nil
    }

    private func openBoard() {
        NotificationCenter.default.post(
            name: .eusoDispatchNavSwap,
            object: nil,
            userInfo: ["screenId": "Disp401"]
        )
    }

    private func openDriverRoster() {
        NotificationCenter.default.post(
            name: .eusoDispatchNavSwap,
            object: nil,
            userInfo: ["screenId": "Dpch701"]
        )
    }
}

#Preview("400 · Dispatcher home · Night") {
    DispatcherHomeScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("400 · Dispatcher home · Afternoon") {
    DispatcherHomeScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
