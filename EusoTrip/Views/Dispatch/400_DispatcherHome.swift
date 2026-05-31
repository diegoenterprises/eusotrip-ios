//
//  400_DispatcherHome.swift
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
//    • dispatch.getPendingTenders — STUB · named-gap EUSO-2122 (top-tender queue)
//    • dispatch.acceptTender      — STUB · named-gap EUSO-2122 (YES action)
//  STUB endpoints are wired with real do/catch + loading/error/empty
//  states; until the server lands them the queue surfaces a flagged
//  empty/error state rather than mock data.
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
                leading: [NavSlot(label: "Home",  systemImage: "house",                 isCurrent: true),
                          NavSlot(label: "Board", systemImage: "rectangle.split.3x1.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Comms", systemImage: "bubble.left.and.bubble.right.fill", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",               isCurrent: false)],
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
    let hoursRemaining: Double?
}

/// `dispatch.getPendingTenders` row — STUB · named-gap EUSO-2122.
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

    @State private var kpi: DispatcherKPI? = nil
    @State private var issues: [DispatcherIssue] = []
    @State private var drivers: [DispatcherDriverStatus] = []
    @State private var tenders: [PendingTender] = []

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var tenderError: String? = nil      // STUB surface
    @State private var actionError: String? = nil
    @State private var acceptingId: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                greeting
                IridescentHairline()

                if loading {
                    LifecycleCard {
                        Text("Loading dispatch desk…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else {
                    attentionRow
                    kpiStrip
                    topTenders
                    esangStrip
                    liveDrivers
                }

                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, 20).padding(.top, 12)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: TopBar eyebrow

    private var eyebrow: some View {
        HStack(alignment: .top) {
            Text("✦ DISPATCHER · DESK · LIVE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 0)
            Text(tickerLine)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var tickerLine: String {
        let active = kpi?.activeLoads ?? 0
        let pending = kpi?.pendingTenders ?? 0
        let expiring = tenders.filter { ($0.expiresInMinutes ?? .max) < 60 && ($0.isPeer != true) }.count
        return "\(active) ACTIVE · \(pending) PENDING · \(expiring) EXPIRING"
    }

    private var greeting: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hey, Renée")
                    .font(.system(size: 34, weight: .bold)).tracking(-0.6)
                    .foregroundStyle(palette.textPrimary)
                Text("Aurora Freight Lines · 18 trucks · 14 active hauls")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            avatarDisc("RM")
        }
    }

    private func avatarDisc(_ initials: String) -> some View {
        ZStack {
            Circle().fill(LinearGradient.diagonal)
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.75), .white.opacity(0)],
                                     center: .init(x: 0.35, y: 0.30),
                                     startRadius: 0, endRadius: 30))
                .frame(width: 28, height: 28)
                .offset(x: -6, y: -6)
            Text(initials)
                .font(.system(size: 14, weight: .heavy)).tracking(0.6)
                .foregroundStyle(.white)
        }
        .frame(width: 56, height: 56)
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
                        "\(($0.expiresInMinutes ?? 0)) min · LD ending \(String(($0.loadNumber ?? "—").suffix(4)))"
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
                    NotificationCenter.default.post(name: .eusoDispatchNavSwap,
                                                    object: nil, userInfo: ["screenId": "708"])
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
        let lanes = items.prefix(2).map { $0.lane ?? "—" }
        let extra = items.count - lanes.count
        return extra > 0 ? "\(lanes.joined(separator: " · ")) · +\(extra)" : lanes.joined(separator: " · ")
    }

    // MARK: KPI strip · 4-up

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            kpiTile(label: "PENDING TENDERS",
                    value: "\(kpi?.pendingTenders ?? 0)",
                    valueColor: Brand.warning,
                    foot: "\(tenders.filter { ($0.expiresInMinutes ?? .max) < 60 && $0.isPeer != true }.count) expire < 1h",
                    footColor: palette.textSecondary)
            kpiTile(label: "ACTIVE HAULS",
                    value: "\(kpi?.activeLoads ?? 0)",
                    valueColor: palette.textPrimary,
                    foot: "on time · \(Int((kpi?.onTimePct ?? 0).rounded()))%",
                    footColor: Brand.success)
            kpiTile(label: "DRIVERS IDLE",
                    value: "\(kpi?.driversIdle ?? 0)",
                    valueGradient: true,
                    foot: idleHosFoot,
                    footColor: palette.textSecondary)
            kpiTile(label: "OTR · 90D",
                    value: String(format: "%.1f%%", kpi?.onTimePct ?? 0),
                    valueGradient: true,
                    foot: "util \(kpi?.avgUtilizationPct ?? 0)%",
                    footColor: Brand.success)
        }
    }

    private var idleHosFoot: String {
        let idle = drivers.filter { ($0.status ?? "").lowercased().contains("idle") }
        let avg = idle.compactMap { $0.hoursRemaining }.reduce(0, +) / Double(max(idle.count, 1))
        let h = Int(avg); let m = Int((avg - Double(h)) * 60)
        return idle.isEmpty ? "no idle drivers" : "avg HOS \(h)h \(m)m"
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
                Text("See all (\(kpi?.pendingTenders ?? tenders.count))")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }

            VStack(spacing: 0) {
                if let te = tenderError {
                    // STUB · EUSO-2122 — endpoint not yet landed.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tender queue unavailable")
                            .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        Text("dispatch.getPendingTenders is a named gap (EUSO-2122). \(te)")
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
                Text(t.lane ?? "—")
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
            let exp = t.expiresInMinutes.map { expiryLabel($0) } ?? "—"
            return "expires \(exp) · awarded \(award)"
        }
        let exp = t.expiresInMinutes.map { expiryLabel($0) } ?? "—"
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
            NotificationCenter.default.post(name: .eusoDispatchNavSwap,
                                            object: nil, userInfo: ["screenId": "esang"])
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
                    Text(pick.map { "ESang says: tender \($0.lane ?? "this lane") to \($0.suggestedDriver ?? "best driver")" }
                         ?? "ESang says: queue is steady — no urgent tender")
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

    private func esangReason(_ t: PendingTender?) -> String {
        guard let t, let d = drivers.first(where: { $0.name.contains(t.suggestedDriver ?? "∅") }) else {
            return "live HoS-aware matching from the driver board"
        }
        let hos = d.hoursRemaining.map { String(format: "HOS %.0fh %02.0fm", floor($0), ($0 - floor($0)) * 60) } ?? "HOS —"
        return "\(hos) · home-base near lane · best rate vs avg"
    }

    // MARK: Live drivers strip

    private var liveDrivers: some View {
        let rolling = drivers.filter { ($0.status ?? "").lowercased().contains("rolling") || ($0.status ?? "").lowercased().contains("driving") }.count
        let idle = drivers.filter { ($0.status ?? "").lowercased().contains("idle") }.count
        let off  = drivers.filter { ($0.status ?? "").lowercased().contains("off") }.count
        return VStack(alignment: .leading, spacing: 10) {
            Text("LIVE DRIVERS · \(drivers.count) ROLLING")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
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

    private func driverDisc(_ d: DispatcherDriverStatus) -> some View {
        let dot: Color = {
            switch (d.status ?? "").lowercased() {
            case let s where s.contains("rolling") || s.contains("driving"): return Brand.success
            case let s where s.contains("idle"): return Brand.warning
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
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        // Tenders load independently — STUB · EUSO-2122 — so a missing
        // endpoint surfaces a flagged state without blowing away the desk.
        await loadTenders()
        loading = false
    }

    private func loadTenders() async {
        tenderError = nil
        struct In: Encodable { let limit: Int }
        do {
            // STUB · named-gap EUSO-2122 — server route not yet shipped.
            let r: [PendingTender] = try await EusoTripAPI.shared.query(
                "dispatch.getPendingTenders", input: In(limit: 8))
            tenders = r
        } catch {
            tenders = []
            tenderError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func acceptTender(_ t: PendingTender) async {
        acceptingId = t.id; actionError = nil
        struct In: Encodable { let tenderId: String }
        struct Out: Decodable { let success: Bool? }
        do {
            // STUB · named-gap EUSO-2122 — accept route not yet shipped.
            let _: Out = try await EusoTripAPI.shared.mutation(
                "dispatch.acceptTender", input: In(tenderId: t.id))
            await loadTenders()
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        acceptingId = nil
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
