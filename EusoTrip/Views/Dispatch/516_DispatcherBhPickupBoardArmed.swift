//
//  516_DispatcherBhPickupBoardArmed.swift
//  EusoTrip — Dispatcher · BH lifecycle 516 · Pickup board armed (countdown watch).
//
//  Wireframe slot: 04 Dispatcher / 516 Dispatcher BH Pickup Board Armed (Light+Dark SVG,
//  golden re-port 2026-06-21 — replaces the stamped Dpch800 duodecet body for this id).
//  Composition (SVG-verbatim): pickup-window countdown hero → WINDOW / DVIR / PING KPI
//  triple → 14-segment pre-trip inspection gauge → 4-row board-watch ledger → lane band →
//  CTA pair (Track pickup window / Nudge DVIR).
//
//  Wiring manifest (code-traced against frontend/server/routers):
//    READ  loads.getById                 — load + pickup window + lane + parties.
//    READ  dispatch.getDriverStatuses    — assigned-driver HOS + drivers.id for messaging.
//    WRITE dispatch.updateLoadStatus     — Track pickup window (status → confirmed).
//    WRITE dispatch.sendDriverMessage    — Nudge DVIR (pre-trip reminder to the driver).
//  Honest gaps (no server proc — rendered as data-absence states, never faked):
//    · pre-trip inspection progress on the dispatch board (gauge + DVIR KPI)
//    · pickup-window auto-ping scheduler (PING KPI + hero chip)
//
//  Dispatcher nav HOME·BOARD·[orb]·COMMS·ME, BOARD active. Light+Dark palette tokens
//  only. The countdown derives from the load's own pickup timestamp — nothing invented.
//

import SwiftUI

// MARK: - Screen

struct DispatcherBHPickupArmed516Screen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            BH516Body(loadId: loadId)
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

private struct BH516Body: View {
    let loadId: String

    @Environment(\.palette) private var palette
    @Environment(\.dispatchNavHandler) private var navHandler

    @State private var load: LoadsAPI.LoadDetail?
    @State private var loadFailed = false
    @State private var driverRow: BH516DriverRow?
    @State private var trackInFlight = false
    @State private var nudgeInFlight = false
    @State private var actionAck: String?
    @State private var actionError: String?
    @State private var now = Date()

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                eyebrowRow
                titleRow
                Rectangle().fill(palette.iridescentHairline).frame(height: 1)
                heroCard
                kpiTriple
                sectionLabel("PRE-TRIP INSPECTION · DRIVER-POSTED")
                dvirGauge
                sectionLabel("BOARD WATCH")
                watchLedger
                laneBand
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
        .onReceive(clock) { now = $0 }
    }

    // MARK: Header

    private var eyebrowRow: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · PICKUP · ARMED")
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
            Text("Pickup armed").font(.system(size: 26, weight: .bold)).foregroundStyle(palette.textPrimary)
            Spacer()
            Menu {
                Button("Refresh") { Task { await refresh() } }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: Hero — pickup-window countdown

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                Text("UNTIL PICKUP WINDOW")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    BH516Chip(text: watchChipText, tint: Brand.info)
                    BH516Chip(text: "AUTO-PING —", tint: Brand.neutral)
                }
            }
            Text(countdownText)
                .font(.system(size: 40, weight: .heavy).monospacedDigit())
                .foregroundStyle(LinearGradient.diagonal)
            Text(heroSubline)
                .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.tintInfo))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.info.opacity(0.25), lineWidth: 1))
    }

    // MARK: KPI triple — WINDOW / DVIR / PING

    private var kpiTriple: some View {
        HStack(spacing: Space.s2) {
            BH516Kpi(label: "WINDOW",
                     value: windowOpenText,
                     sub: windowOpenText == "—" ? "no pickup appointment on record" : "pickup window opens",
                     tint: nil)
            BH516Kpi(label: "DVIR",
                     value: "—",
                     sub: "pre-trip not shared to this board",
                     tint: Brand.warning)
            BH516Kpi(label: "PING",
                     value: "—",
                     sub: "no auto-ping on record",
                     tint: nil)
        }
    }

    // MARK: DVIR gauge — honest data-absence rendering

    private var dvirGauge: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text("14-point inspection").font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("— / 14").font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                }
                HStack(spacing: 4) {
                    ForEach(0..<14, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(palette.tintNeutral)
                            .frame(height: 10)
                    }
                }
                Text("Inspection progress posts from the driver's cab — none has been received for this load.")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: Board-watch ledger

    private var watchLedger: some View {
        LifecycleCard {
            VStack(spacing: 0) {
                BH516WatchRow(title: "Driver assignment",
                              sub: driverSub,
                              pill: load?.driverId != nil ? "LOCKED" : "OPEN",
                              pillTint: load?.driverId != nil ? Brand.success : Brand.warning)
                Divider().overlay(palette.borderFaint)
                BH516WatchRow(title: "Fitness gate",
                              sub: fitnessSub,
                              pill: driverRow?.hoursRemaining != nil ? "CHECKED" : "—",
                              pillTint: driverRow?.hoursRemaining != nil ? Brand.success : Brand.neutral)
                Divider().overlay(palette.borderFaint)
                BH516WatchRow(title: "Pickup window",
                              sub: pickupWindowSub,
                              pill: pickupIsFuture ? "ARMED" : (load?.pickupDate == nil ? "—" : "OPEN"),
                              pillTint: pickupIsFuture ? Brand.info : Brand.neutral)
                Divider().overlay(palette.borderFaint)
                BH516WatchRow(title: "Board status",
                              sub: "single watch on this load · consolidated on the board",
                              pill: watchActive ? "1 ACTIVE" : "—",
                              pillTint: watchActive ? Brand.success : Brand.neutral)
            }
        }
    }

    private var laneBand: some View {
        LifecycleCard {
            HStack {
                Text(laneBandText)
                    .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                Spacer()
                BH516Chip(text: watchActive ? "ARMED" : "—", tint: watchActive ? Brand.info : Brand.neutral)
            }
        }
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button { Task { await trackPickupWindow() } } label: {
                HStack(spacing: 6) {
                    if trackInFlight { ProgressView().tint(.white).scaleEffect(0.8) }
                    else { Image(systemName: "clock").font(.system(size: 13, weight: .bold)) }
                    Text(trackInFlight ? "Posting…" : "Track pickup window").font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(trackInFlight)

            Button { Task { await nudgeDvir() } } label: {
                HStack(spacing: 6) {
                    if nudgeInFlight { ProgressView().scaleEffect(0.8) }
                    Text(nudgeInFlight ? "Sending…" : "Nudge DVIR").font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(palette.textPrimary)
                .background(Capsule().fill(palette.bgCard))
                .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(nudgeInFlight)
        }
        .padding(.top, Space.s2)
    }

    // MARK: Derived display

    private var pickupDate: Date? { bh516ISODate(load?.pickupDate) }
    private var pickupIsFuture: Bool { (pickupDate ?? .distantPast) > now }
    private var watchActive: Bool {
        ["awarded", "accepted", "assigned", "confirmed"].contains(load?.status ?? "")
    }

    private var countdownText: String {
        guard let p = pickupDate else { return "—" }
        let secs = Int(p.timeIntervalSince(now))
        guard secs > 0 else { return "OPEN" }
        let h = secs / 3600, m = (secs % 3600) / 60
        return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m)m"
    }

    private var heroSubline: String {
        var parts: [String] = []
        if let p = pickupDate {
            let f = DateFormatter(); f.dateFormat = "MMM d · HH:mm"
            parts.append(f.string(from: p))
        } else {
            parts.append("No pickup appointment on this load record")
        }
        if let city = load?.pickupLocation?.city {
            let state = load?.pickupLocation?.state
            parts.append(state.map { "\(city), \($0)" } ?? city)
        }
        return parts.joined(separator: " · ")
    }

    private var watchChipText: String { watchActive ? "WATCH ARMED" : "WATCH —" }

    private var windowOpenText: String {
        guard let p = pickupDate else { return "—" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: p)
    }

    private var driverSub: String {
        if let n = load?.driver?.name {
            if let d = load?.driver?.dotNumber { return "\(n) · USDOT \(d)" }
            return n
        }
        return "no driver locked on this load"
    }

    private var fitnessSub: String {
        if let h = driverRow?.hoursRemaining {
            return String(format: "HOS %.0fh drive available · from the live driver board", h)
        }
        return "driver hours not on the live board for this load"
    }

    private var pickupWindowSub: String {
        guard let p = pickupDate else { return "no pickup appointment on this record" }
        let f = DateFormatter(); f.dateFormat = "MMM d · HH:mm"
        return "\(f.string(from: p)) · counts down live on this board"
    }

    private var laneBandText: String {
        let lane = load?.laneDisplay ?? "—"
        let mi = load?.distanceDisplay ?? "—"
        return "\(lane) · \(mi)"
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
        now = Date()
    }

    private func fetchDriverRow() async {
        struct In: Encodable { let limit: Int }
        do {
            let rows: [BH516DriverRow] = try await EusoTripAPI.shared.query("dispatch.getDriverStatuses", input: In(limit: 50))
            let ln = load?.loadNumber
            let dn = load?.driver?.name
            driverRow = rows.first(where: { $0.load != nil && $0.load == ln })
                ?? rows.first(where: { dn != nil && $0.name == dn })
        } catch { driverRow = nil }
    }

    private func trackPickupWindow() async {
        guard !trackInFlight else { return }
        trackInFlight = true; actionAck = nil; actionError = nil
        defer { trackInFlight = false }
        struct In: Encodable { let loadId: String; let status: String }
        struct Out: Decodable { let success: Bool?; let newStatus: String? }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation("dispatch.updateLoadStatus",
                                                                 input: In(loadId: loadId, status: "confirmed"))
            if out.success == true {
                actionAck = "Pickup watch confirmed — the board tracks this load against its pickup window."
                await refresh()
            } else {
                actionError = "The watch didn't confirm. The board still shows the last saved stage — try again."
            }
        } catch {
            actionError = "The watch didn't post. The board still shows the last saved stage — check the connection and try again."
        }
    }

    private func nudgeDvir() async {
        guard !nudgeInFlight else { return }
        nudgeInFlight = true; actionAck = nil; actionError = nil
        defer { nudgeInFlight = false }
        guard let driverId = driverRow?.id else {
            actionError = "No driver row for this load is on the company board, so the reminder wasn't sent. Lock a driver first."
            return
        }
        struct In: Encodable { let driverId: String; let message: String; let priority: String }
        struct Out: Decodable { let success: Bool? }
        let windowNote = windowOpenText == "—" ? "" : " Pickup window opens \(windowOpenText)."
        do {
            let out: Out = try await EusoTripAPI.shared.mutation(
                "dispatch.sendDriverMessage",
                input: In(driverId: driverId,
                          message: "Pre-trip inspection reminder for \(load?.loadNumber ?? "your assigned load").\(windowNote)",
                          priority: "normal"))
            if out.success == true {
                actionAck = "Reminder sent to \(driverRow?.name ?? "the driver") — it lands in their cab thread."
            } else {
                actionError = "The reminder didn't send. The watch is still armed — try again."
            }
        } catch {
            actionError = "The reminder didn't send. The watch is still armed — check the connection and try again."
        }
    }
}

// MARK: - Small primitives

private struct BH516Chip: View {
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

private struct BH516Kpi: View {
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

private struct BH516WatchRow: View {
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
            BH516Chip(text: pill, tint: pillTint)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - File-local helpers

private struct BH516DriverRow: Decodable {
    let id: String?
    let name: String?
    let status: String?
    let load: String?
    let hoursRemaining: Double?
}

private func bh516ISODate(_ s: String?) -> Date? {
    guard let s else { return nil }
    let f1 = ISO8601DateFormatter()
    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f1.date(from: s) { return d }
    return ISO8601DateFormatter().date(from: s)
}

// MARK: - Previews

#Preview("516 Pickup Armed · Dark") {
    DispatcherBHPickupArmed516Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("516 Pickup Armed · Light") {
    DispatcherBHPickupArmed516Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
