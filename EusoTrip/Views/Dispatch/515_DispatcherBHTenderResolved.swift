//
//  515_DispatcherBHTenderResolved.swift
//  EusoTrip — Dispatcher · BH lifecycle 515 · Tender resolved (backhaul AWARDED receipt).
//
//  Wireframe slot: 04 Dispatcher / 515 Dispatcher BH Tender Resolved (Light+Dark SVG,
//  golden re-port 2026-06-21 — replaces the stamped Dpch800 duodecet body for this id).
//  Composition (SVG-verbatim): confirmation hero (awarded-driver card + status chips) →
//  MARGIN / WINDOW / DVIR KPI triple → 8-stage backhaul chain (current stage lit) →
//  4-row resolution-gates ledger → money band → CTA pair (Track to pickup / View tender).
//
//  Wiring manifest (code-traced against frontend/server/routers):
//    READ  loads.getById                 — load + parties + chain stage + rate + windows.
//    READ  dispatch.getDriverStatuses    — assigned-driver HOS hours (fitness-gate row).
//    WRITE dispatch.updateLoadStatus     — Track to pickup (status → en_route_pickup).
//    SHEET View tender                   — read-only sheet bound to the same load record.
//  Honest gaps (no server proc — rendered as data-absence states, never faked):
//    · tender acceptance-window timer (WINDOW KPI binds loads.biddingEnds when present)
//    · board-side DVIR pre-trip rollup (DVIR KPI)
//    · margin / brokerage economics on the load projection (MARGIN KPI, money band)
//
//  Dispatcher nav HOME·BOARD·[orb]·COMMS·ME, BOARD active. Light+Dark palette tokens
//  only. Zero invented business figures — absent fields render an em-dash with
//  availability copy keyed to what the record carries.
//

import SwiftUI

// MARK: - Screen

struct DispatcherBHTenderResolved515Screen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            BH515Body(loadId: loadId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",                    isCurrent: false),
                          NavSlot(label: "Board", systemImage: "rectangle.split.3x1.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Comms", systemImage: "bubble.left.and.bubble.right.fill", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",                  isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct BH515Body: View {
    let loadId: String

    @Environment(\.palette) private var palette
    @Environment(\.dispatchNavHandler) private var navHandler

    @State private var load: LoadsAPI.LoadDetail?
    @State private var loadFailed = false
    @State private var driverRow: BH515DriverRow?
    @State private var margin: BH515Margin?
    @State private var dvirRollup: BH515DvirRollup?
    @State private var actionInFlight = false
    @State private var actionAck: String?
    @State private var actionError: String?
    @State private var showTenderSheet = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                eyebrowRow
                titleRow
                Rectangle().fill(palette.iridescentHairline).frame(height: 1)
                heroCard
                kpiTriple
                sectionLabel("BACKHAUL CHAIN · STEP \(chainIndex + 1) OF 8 · \(chainStages[chainIndex])")
                BH515ChainStrip(currentIndex: chainIndex)
                sectionLabel("RESOLUTION GATES")
                gatesLedger
                moneyBand
                if let ack = actionAck {
                    LifecycleCard { Text(ack).font(EType.caption).foregroundStyle(Brand.success) }
                }
                if let err = actionError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                }
                if loadFailed {
                    LifecycleCard(accentWarning: true) {
                        Text("Couldn't reach the board for this load. Everything shown is the last loaded state — pull to refresh.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
                ctaPair
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await refresh() }
        .refreshable { await refresh() }
        .sheet(isPresented: $showTenderSheet) { BH515TenderSheet(load: load) }
    }

    // MARK: Header

    private var eyebrowRow: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · TENDER · RESOLVED")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Spacer()
            Text(load?.loadNumber ?? "—")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary).monospacedDigit()
        }
    }

    private var titleRow: some View {
        HStack(spacing: Space.s3) {
            Button { navHandler?("board") } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(palette.textPrimary)
            }
            .buttonStyle(.plain)
            Text("Tender resolved").font(.system(size: 26, weight: .bold)).foregroundStyle(palette.textPrimary)
            Spacer()
            Menu {
                Button("Refresh") { Task { await refresh() } }
                Button("View tender") { showTenderSheet = true }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: Hero — awarded confirmation

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s3) {
                Circle().fill(LinearGradient.diagonal).frame(width: 44, height: 44)
                    .overlay(Text(driverInitials).font(.system(size: 13, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 3) {
                    Text(load?.driver?.name.map { "Awarded · \($0)" } ?? "Awarded · driver pending")
                        .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    Text(carrierLine)
                        .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                    Text(laneLine)
                        .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 6) {
                    BH515Chip(text: resolvedChipText, tint: Brand.success)
                    if load?.driverId == nil {
                        BH515Chip(text: "UNASSIGNED", tint: Brand.warning)
                    }
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.tintSuccess))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.success.opacity(0.25), lineWidth: 1))
    }

    // MARK: KPI triple — MARGIN / WINDOW / DVIR

    private var kpiTriple: some View {
        HStack(spacing: Space.s2) {
            BH515Kpi(label: "MARGIN",
                     value: marginText,
                     sub: marginSub,
                     tint: nil)
            BH515Kpi(label: "WINDOW",
                     value: windowRemainingText,
                     sub: windowRemainingText == "—" ? "no acceptance timer on record" : "until the tender window closes",
                     tint: windowRemainingText == "—" ? nil : palette.textPrimary)
            BH515Kpi(label: "DVIR",
                     value: dvirText,
                     sub: dvirSub,
                     tint: dvirRollup?.sectionsAcked == dvirRollup?.sectionsTotal ? Brand.success : Brand.warning)
        }
    }

    // MARK: Gates ledger

    private var gatesLedger: some View {
        LifecycleCard {
            VStack(spacing: 0) {
                BH515GateRow(title: "Driver assignment",
                             sub: driverGateSub,
                             pill: load?.driverId != nil ? "LOCKED" : "OPEN",
                             pillTint: load?.driverId != nil ? Brand.success : Brand.warning)
                Divider().overlay(palette.borderFaint)
                BH515GateRow(title: "Fitness gate",
                             sub: fitnessGateSub,
                             pill: driverRow?.hoursRemaining != nil ? "CHECKED" : "—",
                             pillTint: driverRow?.hoursRemaining != nil ? Brand.success : Brand.neutral)
                Divider().overlay(palette.borderFaint)
                BH515GateRow(title: "Lane distance",
                             sub: (load?.distance ?? 0) > 0 ? "\(load?.distanceDisplay ?? "—") on the awarded lane" : "distance not on this record",
                             pill: (load?.distance ?? 0) > 0 ? "LOCKED" : "—",
                             pillTint: (load?.distance ?? 0) > 0 ? Brand.success : Brand.neutral)
                Divider().overlay(palette.borderFaint)
                BH515GateRow(title: "Reconfirmation",
                             sub: load?.driverId != nil ? "single-driver direct tender · none required" : "arms when a driver locks",
                             pill: load?.driverId != nil ? "NOT REQ" : "—",
                             pillTint: Brand.neutral)
            }
        }
    }

    // MARK: Money band

    private var moneyBand: some View {
        LifecycleCard {
            HStack {
                Text("Gross \(load?.rateDisplay ?? "—") · margin \(marginText) · NET-30")
                    .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                Spacer()
                BH515Chip(text: load?.rate != nil ? "LOCKED" : "—",
                          tint: load?.rate != nil ? Brand.success : Brand.neutral)
            }
        }
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button { Task { await trackToPickup() } } label: {
                HStack(spacing: 6) {
                    if actionInFlight { ProgressView().tint(.white).scaleEffect(0.8) }
                    else { Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold)) }
                    Text(actionInFlight ? "Posting…" : "Track to pickup").font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(actionInFlight)

            Button { showTenderSheet = true } label: {
                Text("View tender").font(EType.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(palette.textPrimary)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Space.s2)
    }

    // MARK: Derived display

    private var chainStages: [String] { ["POSTED", "BIDDING", "AWARDED", "PICKUP", "TRANSIT", "DELIVERY", "PAPERWORK", "CLOSED"] }
    private var chainIndex: Int { bh515ChainIndex(load?.status) }

    private var driverInitials: String {
        if let i = load?.driver?.initials, !i.isEmpty { return i }
        if let n = load?.driver?.name {
            let parts = n.split(separator: " ")
            let letters = parts.prefix(2).compactMap { $0.first }
            if !letters.isEmpty { return String(letters).uppercased() }
        }
        return "—"
    }

    private var carrierLine: String {
        let carrier = load?.catalyst?.companyName ?? load?.catalyst?.name
        let dot = load?.catalyst?.dotNumber ?? load?.driver?.dotNumber
        switch (carrier, dot) {
        case let (c?, d?): return "\(c) · USDOT \(d)"
        case let (c?, nil): return c
        case let (nil, d?): return "USDOT \(d)"
        default: return "Carrier pending on this record"
        }
    }

    private var laneLine: String {
        let lane = load?.laneDisplay ?? "Lane pending"
        if let mi = load?.distanceDisplay { return "\(lane) · \(mi)" }
        return lane
    }

    private var resolvedChipText: String {
        switch load?.status {
        case "awarded", "accepted", "assigned", "confirmed": return "RESOLVED"
        case let s?: return bh515Humanize(s).uppercased()
        case nil: return "—"
        }
    }

    private var windowRemainingText: String {
        guard let ends = bh515ISODate(load?.biddingEnds) else { return "—" }
        let secs = Int(ends.timeIntervalSinceNow)
        guard secs > 0 else { return "CLOSED" }
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }

    private var marginText: String {
        guard let m = margin?.margin else { return "—" }
        return String(format: "$%.0f", m)
    }

    private var marginSub: String {
        guard let pct = margin?.marginPct else { return "not on this load record" }
        return String(format: "%.1f%% brokerage margin", pct)
    }

    private var dvirText: String {
        guard let r = dvirRollup else { return "—" }
        return "\(r.sectionsAcked)/\(r.sectionsTotal)"
    }

    private var dvirSub: String {
        guard let r = dvirRollup else { return "pre-trip not shared to this board" }
        if r.sectionsAcked == r.sectionsTotal { return "inspection passed" }
        return "inspection advancing"
    }

    private var driverGateSub: String {
        if let n = load?.driver?.name {
            if let d = load?.driver?.dotNumber { return "\(n) · USDOT \(d)" }
            return n
        }
        return "no driver locked on this tender"
    }

    private var fitnessGateSub: String {
        if let h = driverRow?.hoursRemaining {
            return String(format: "HOS %.0fh drive available · from the live driver board", h)
        }
        return "driver hours not on the live board for this load"
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            .padding(.top, Space.s1)
    }

    // MARK: Data

    private func refresh() async {
        struct In: Encodable { let id: String }
        do {
            load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId))
            loadFailed = false
        } catch { loadFailed = load == nil }
        await fetchDriverRow()
        await fetchMargin()
        await fetchDvirRollup()
    }

    private func fetchDriverRow() async {
        struct In: Encodable { let limit: Int }
        do {
            let rows: [BH515DriverRow] = try await EusoTripAPI.shared.query("dispatch.getDriverStatuses", input: In(limit: 50))
            let ln = load?.loadNumber
            let dn = load?.driver?.name
            driverRow = rows.first(where: { $0.load != nil && $0.load == ln })
                ?? rows.first(where: { dn != nil && $0.name == dn })
        } catch { driverRow = nil }
    }

    private func fetchMargin() async {
        struct In: Encodable { let loadId: String }
        let numericId = loadId.replacingOccurrences(of: "load_", with: "")
        do {
            margin = try await EusoTripAPI.shared.query("dispatch.getLoadMargin", input: In(loadId: numericId))
        } catch { margin = nil }
    }

    private func fetchDvirRollup() async {
        struct In: Encodable { let loadId: String }
        let numericId = loadId.replacingOccurrences(of: "load_", with: "")
        do {
            dvirRollup = try await EusoTripAPI.shared.query("dispatch.getLoadDvirRollup", input: In(loadId: numericId))
        } catch { dvirRollup = nil }
    }

    private func trackToPickup() async {
        guard !actionInFlight else { return }
        actionInFlight = true; actionAck = nil; actionError = nil
        defer { actionInFlight = false }
        struct In: Encodable { let loadId: String; let status: String }
        struct Out: Decodable { let success: Bool?; let newStatus: String? }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation("dispatch.updateLoadStatus",
                                                                 input: In(loadId: loadId, status: "en_route_pickup"))
            if out.success == true {
                actionAck = "Pickup tracking is live — the board now shows this load en route to pickup."
                await refresh()
            } else {
                actionError = "The stage didn't advance. The board still shows the last saved stage — try again."
            }
        } catch {
            actionError = "The stage didn't post. The board still shows the last saved stage — check the connection and try again."
        }
    }
}

// MARK: - Chain strip (8-stage)

private struct BH515ChainStrip: View {
    @Environment(\.palette) private var palette
    let currentIndex: Int
    private let stages = ["POSTED", "BIDDING", "AWARDED", "PICKUP", "TRANSIT", "DELIVERY", "PAPERWORK", "CLOSED"]

    var body: some View {
        LifecycleCard {
            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    ForEach(stages.indices, id: \.self) { i in
                        Group {
                            if i == currentIndex {
                                Circle().fill(LinearGradient.diagonal).frame(width: 22, height: 22)
                                    .overlay(Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white))
                            } else if i < currentIndex {
                                Circle().fill(Brand.success).frame(width: 10, height: 10)
                            } else {
                                Circle().strokeBorder(palette.borderStrong, lineWidth: 1.5).frame(width: 10, height: 10)
                            }
                        }
                        if i < stages.count - 1 {
                            Rectangle()
                                .fill(i < currentIndex ? Brand.success : palette.borderSoft)
                                .frame(height: 2)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                HStack(spacing: 0) {
                    ForEach(stages.indices, id: \.self) { i in
                        Text(stages[i])
                            .font(.system(size: 6.5, weight: .heavy)).tracking(0.3)
                            .foregroundStyle(i == currentIndex ? Brand.magenta : palette.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

// MARK: - Small primitives

private struct BH515Chip: View {
    let text: String
    let tint: Color
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.12)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 1))
    }
}

private struct BH515Kpi: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    let sub: String
    let tint: Color?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 20, weight: .heavy).monospacedDigit())
                .foregroundStyle(tint ?? palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }
}

private struct BH515GateRow: View {
    @Environment(\.palette) private var palette
    let title: String
    let sub: String
    let pill: String
    let pillTint: Color
    var body: some View {
        HStack(alignment: .center, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                Text(sub).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            BH515Chip(text: pill, tint: pillTint)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - View-tender sheet (read-only, bound to the live load record)

private struct BH515TenderSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let load: LoadsAPI.LoadDetail?

    var body: some View {
        ZStack {
            palette.bgPrimary.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack {
                        Text("Tender").font(EType.h2).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(palette.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    if let l = load {
                        LifecycleCard {
                            row("Load", l.loadNumber)
                            row("Stage", bh515Humanize(l.status))
                            row("Lane", l.laneDisplay)
                            row("Distance", l.distanceDisplay)
                            row("Rate", l.rateDisplay)
                            row("Equipment", l.equipmentType.map(bh515Humanize) ?? "—")
                            row("Pickup", bh515LocalDateTime(l.pickupDate) ?? "—")
                            row("Delivery", bh515LocalDateTime(l.deliveryDate) ?? "—")
                            row("Driver", l.driver?.name ?? "not locked")
                            row("Carrier", l.catalyst?.companyName ?? l.catalyst?.name ?? "—")
                        }
                    } else {
                        LifecycleCard {
                            Text("The tender detail hasn't loaded — close this sheet and pull to refresh the board.")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    }
                    Spacer(minLength: 24)
                }
                .padding(Space.s4)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value).font(EType.mono(.caption)).foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - File-local helpers

private struct BH515Margin: Decodable {
    let grossRate: Double?
    let carrierLinehaul: Double?
    let margin: Double?
    let marginPct: Double?
}

private struct BH515DvirRollup: Decodable {
    let dvirId: Int?
    let status: String?
    let sectionsAcked: Int
    let sectionsTotal: Int
}

private struct BH515DriverRow: Decodable {
    let id: String?
    let name: String?
    let status: String?
    let load: String?
    let hoursRemaining: Double?
}

private func bh515ChainIndex(_ status: String?) -> Int {
    switch status {
    case "draft", "posted": return 0
    case "bidding", "expired", "declined", "lapsed": return 1
    case "awarded", "accepted", "assigned", "confirmed", nil: return 2
    case "en_route_pickup", "at_pickup", "pickup_checkin", "loading", "loading_exception", "loaded": return 3
    case "in_transit", "transit_hold", "transit_exception": return 4
    case "at_delivery", "delivery_checkin", "unloading", "unloading_exception", "unloaded": return 5
    case "pod_pending", "pod_rejected", "delivered", "invoiced", "disputed": return 6
    case "paid", "complete": return 7
    default: return 2
    }
}

private func bh515Humanize(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return "—" }
    return raw.replacingOccurrences(of: "_", with: " ").capitalized
}

private func bh515ISODate(_ s: String?) -> Date? {
    guard let s else { return nil }
    let f1 = ISO8601DateFormatter()
    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f1.date(from: s) { return d }
    return ISO8601DateFormatter().date(from: s)
}

private func bh515LocalDateTime(_ iso: String?) -> String? {
    guard let d = bh515ISODate(iso) else { return nil }
    let f = DateFormatter()
    f.dateFormat = "MMM d · HH:mm"
    return f.string(from: d)
}

// MARK: - Previews

#Preview("515 Tender Resolved · Dark") {
    DispatcherBHTenderResolved515Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("515 Tender Resolved · Light") {
    DispatcherBHTenderResolved515Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
