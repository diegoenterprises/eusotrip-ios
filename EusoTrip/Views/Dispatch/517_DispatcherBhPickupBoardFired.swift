//
//  517_DispatcherBhPickupBoardFired.swift
//  EusoTrip — Dispatcher · BH lifecycle 517 · Pickup board fired (live loading).
//
//  Wireframe slot: 04 Dispatcher / 517 Dispatcher BH Pickup Board Fired (Light+Dark SVG,
//  golden re-port 2026-06-21 — replaces the stamped Dpch800 duodecet body for this id).
//  Composition (SVG-verbatim): live-loading hero (elapsed-since-gate readout + chips) →
//  ELAPSED / DVIR / ETA KPI triple → live origin→destination route strip (truck marker) →
//  4-row pickup-gates ledger → money band → CTA pair (Open dock coord / View detail).
//
//  Wiring manifest (code-traced against frontend/server/routers):
//    READ  loads.getById                        — load + stage + rate + windows + parties.
//    READ  location.tracking.getLoadTracking    — live position / route / ETA envelope.
//    READ  documentManagement.getDocuments      — BOL-on-file check (chip binds to it).
//    READ  dispatch.getDriverStatuses           — driver HOS + drivers.id for messaging.
//    WRITE dispatch.sendDriverMessage           — Open dock coord (dock thread to driver).
//  Honest gaps (no server proc — rendered as data-absence states, never faked):
//    · board-side DVIR rollup (DVIR KPI)
//    · seal-application rollup (hero line binds documents + status only)
//    · loading clock (ELAPSED derives from the load's own status-flip timestamp)
//
//  Dispatcher nav HOME·BOARD·[orb]·COMMS·ME, BOARD active. Light+Dark palette tokens only.
//

import SwiftUI

// MARK: - Screen

struct DispatcherBHPickupFired517Screen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            BH517Body(loadId: loadId)
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

private struct BH517Body: View {
    let loadId: String

    @Environment(\.palette) private var palette
    @Environment(\.dispatchNavHandler) private var navHandler

    @State private var load: LoadsAPI.LoadDetail?
    @State private var tracking: BH517Tracking?
    @State private var bolOnFile: Bool?
    @State private var loadFailed = false
    @State private var driverRow: BH517DriverRow?
    @State private var dockInFlight = false
    @State private var actionAck: String?
    @State private var actionError: String?
    @State private var showDetailSheet = false
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
                sectionLabel("LIVE ROUTE · \(routeLabel)")
                routeStrip
                sectionLabel("PICKUP GATES")
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
        .onReceive(clock) { now = $0 }
        .sheet(isPresented: $showDetailSheet) { BH517DetailSheet(load: load, tracking: tracking) }
    }

    // MARK: Header

    private var eyebrowRow: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · PICKUP · FIRED")
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
            Text("Pickup fired").font(.system(size: 26, weight: .bold)).foregroundStyle(palette.textPrimary)
            Spacer()
            Menu {
                Button("Refresh") { Task { await refresh() } }
                Button("View detail") { showDetailSheet = true }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: Hero — live loading

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                HStack(spacing: 6) {
                    Circle().fill(Brand.success).frame(width: 6, height: 6)
                    Text(heroStateLabel)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Brand.success)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    BH517Chip(text: "DVIR —", tint: Brand.neutral)
                    BH517Chip(text: bolChipText, tint: bolOnFile == true ? Brand.success : Brand.warning)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text(elapsedText)
                    .font(.system(size: 40, weight: .heavy).monospacedDigit())
                    .foregroundStyle(LinearGradient.diagonal)
                Text(elapsedText == "—" ? "no gate timestamp on record" : "since the stage fired")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            Text(heroSubline)
                .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.tintSuccess))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.success.opacity(0.25), lineWidth: 1))
    }

    // MARK: KPI triple — ELAPSED / DVIR / ETA

    private var kpiTriple: some View {
        HStack(spacing: Space.s2) {
            BH517Kpi(label: "ELAPSED",
                     value: elapsedText,
                     sub: elapsedText == "—" ? "no gate timestamp on record" : "at the pickup gate",
                     tint: nil)
            BH517Kpi(label: "DVIR",
                     value: "—",
                     sub: "pre-trip not shared to this board",
                     tint: Brand.warning)
            BH517Kpi(label: "ETA",
                     value: etaText,
                     sub: etaText == "—" ? "no delivery prediction yet" : "to the receiver",
                     tint: nil)
        }
    }

    // MARK: Route strip

    private var routeLabel: String {
        let o = load?.pickupLocation?.city ?? "ORIGIN"
        let d = load?.deliveryLocation?.city ?? "DESTINATION"
        return "\(o.uppercased()) → \(d.uppercased())"
    }

    private var routeStrip: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text(originLabel).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(destinationLabel).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.borderSoft).frame(height: 3)
                        Capsule().fill(LinearGradient.primary)
                            .frame(width: max(10, geo.size.width * progressFraction), height: 3)
                        Circle().fill(LinearGradient.diagonal).frame(width: 12, height: 12)
                            .offset(x: max(0, geo.size.width * progressFraction - 6))
                        Image(systemName: "truck.box.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Brand.blue)
                            .offset(x: max(0, geo.size.width * progressFraction - 5), y: -12)
                        Circle().strokeBorder(palette.borderStrong, lineWidth: 1.5)
                            .frame(width: 10, height: 10)
                            .offset(x: geo.size.width - 10)
                    }
                }
                .frame(height: 22)
                HStack {
                    Text(routeMidline).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text(etaText == "—" ? "ETA —" : "ETA \(etaText)").font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    // MARK: Gates ledger

    private var gatesLedger: some View {
        LifecycleCard {
            VStack(spacing: 0) {
                BH517GateRow(title: "Driver assignment",
                             sub: driverSub,
                             pill: load?.driverId != nil ? "LOCKED" : "OPEN",
                             pillTint: load?.driverId != nil ? Brand.success : Brand.warning)
                Divider().overlay(palette.borderFaint)
                BH517GateRow(title: "Fitness gate",
                             sub: fitnessSub,
                             pill: driverRow?.hoursRemaining != nil ? "CHECKED" : "—",
                             pillTint: driverRow?.hoursRemaining != nil ? Brand.success : Brand.neutral)
                Divider().overlay(palette.borderFaint)
                BH517GateRow(title: "Pickup dock",
                             sub: dockSub,
                             pill: isOnSiteStage ? "LOADING" : bh517Humanize(load?.status).uppercased(),
                             pillTint: isOnSiteStage ? Brand.info : Brand.neutral)
                Divider().overlay(palette.borderFaint)
                BH517GateRow(title: "Board status",
                             sub: "pickup watch fired · card is live on the board",
                             pill: isOnSiteStage || isPastPickup ? "FIRED" : "—",
                             pillTint: isOnSiteStage || isPastPickup ? Brand.success : Brand.neutral)
            }
        }
    }

    private var moneyBand: some View {
        LifecycleCard {
            HStack {
                Text("Gross \(load?.rateDisplay ?? "—") · margin — · NET-30")
                    .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                Spacer()
                BH517Chip(text: load?.rate != nil ? "LOCKED" : "—",
                          tint: load?.rate != nil ? Brand.success : Brand.neutral)
            }
        }
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button { Task { await openDockCoord() } } label: {
                HStack(spacing: 6) {
                    if dockInFlight { ProgressView().tint(.white).scaleEffect(0.8) }
                    else { Image(systemName: "scope").font(.system(size: 13, weight: .bold)) }
                    Text(dockInFlight ? "Opening…" : "Open dock coord").font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(dockInFlight)

            Button { showDetailSheet = true } label: {
                Text("View detail").font(EType.body.weight(.semibold))
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

    private var isOnSiteStage: Bool {
        ["at_pickup", "pickup_checkin", "loading", "loading_exception", "loaded"].contains(load?.status ?? "")
    }
    private var isPastPickup: Bool {
        bh517ChainIndex(load?.status) > 3
    }

    private var heroStateLabel: String {
        if isOnSiteStage { return "LOADING · ON-SITE" }
        return "STAGE · \(bh517Humanize(load?.status).uppercased())"
    }

    private var elapsedText: String {
        guard isOnSiteStage, let flipped = bh517ISODate(load?.updatedAt) else { return "—" }
        let secs = max(0, Int(now.timeIntervalSince(flipped)))
        let h = secs / 3600, m = (secs % 3600) / 60
        return h > 0 ? String(format: "%d:%02d", h, m) : String(format: "0:%02d", m)
    }

    private var heroSubline: String {
        var parts: [String] = []
        if let n = load?.driver?.name { parts.append("\(n) on-site") }
        parts.append(bolOnFile == true ? "BOL on file" : "BOL not yet posted")
        if let eq = load?.equipmentType { parts.append(bh517Humanize(eq)) }
        return parts.joined(separator: " · ")
    }

    private var bolChipText: String {
        switch bolOnFile {
        case true: return "BOL ON FILE"
        case false: return "BOL PENDING"
        default: return "BOL —"
        }
    }

    private var etaText: String {
        if let iso = tracking?.eta?.predictedEta, let d = bh517ISODate(iso) {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            return f.string(from: d)
        }
        if let d = bh517ISODate(load?.deliveryDate) {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            return f.string(from: d)
        }
        return "—"
    }

    private var progressFraction: CGFloat {
        guard let remaining = tracking?.eta?.remainingMiles,
              let total = tracking?.route?.distanceMiles ?? load?.distance,
              total > 0 else { return 0.02 }
        return CGFloat(min(0.98, max(0.02, 1.0 - remaining / total)))
    }

    private var originLabel: String {
        let c = load?.pickupLocation?.city ?? "—"
        if let s = load?.pickupLocation?.state { return "\(c), \(s)" }
        return c
    }

    private var destinationLabel: String {
        let c = load?.deliveryLocation?.city ?? "—"
        if let s = load?.deliveryLocation?.state { return "\(c), \(s)" }
        return c
    }

    private var routeMidline: String {
        var parts: [String] = []
        parts.append(load?.distanceDisplay ?? "—")
        if tracking?.position == nil { parts.append("no GPS fix yet") }
        return parts.joined(separator: " · ")
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

    private var dockSub: String {
        var parts: [String] = [originLabel]
        parts.append(bolOnFile == true ? "BOL on file" : "BOL not yet posted")
        return parts.joined(separator: " · ")
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
        await fetchTracking()
        await fetchBolPresence()
        await fetchDriverRow()
        now = Date()
    }

    private func fetchTracking() async {
        struct In: Encodable { let loadId: Int }
        guard let numeric = Int((load?.id ?? loadId).replacingOccurrences(of: "load_", with: "")) else { return }
        do {
            tracking = try await EusoTripAPI.shared.query("location.tracking.getLoadTracking", input: In(loadId: numeric))
        } catch { tracking = nil }
    }

    private func fetchBolPresence() async {
        struct In: Encodable { let entityType: String; let entityId: String; let type: String; let page: Int; let pageSize: Int }
        struct Out: Decodable { struct Doc: Decodable { let id: String? }; let documents: [Doc]? }
        let numericId = (load?.id ?? loadId).replacingOccurrences(of: "load_", with: "")
        do {
            let out: Out = try await EusoTripAPI.shared.query(
                "documentManagement.getDocuments",
                input: In(entityType: "load", entityId: numericId, type: "bol", page: 1, pageSize: 5))
            bolOnFile = !(out.documents ?? []).isEmpty
        } catch { bolOnFile = nil }
    }

    private func fetchDriverRow() async {
        struct In: Encodable { let limit: Int }
        do {
            let rows: [BH517DriverRow] = try await EusoTripAPI.shared.query("dispatch.getDriverStatuses", input: In(limit: 50))
            let ln = load?.loadNumber
            let dn = load?.driver?.name
            driverRow = rows.first(where: { $0.load != nil && $0.load == ln })
                ?? rows.first(where: { dn != nil && $0.name == dn })
        } catch { driverRow = nil }
    }

    private func openDockCoord() async {
        guard !dockInFlight else { return }
        dockInFlight = true; actionAck = nil; actionError = nil
        defer { dockInFlight = false }
        guard let driverId = driverRow?.id else {
            actionError = "No driver row for this load is on the company board, so the dock thread didn't open. Lock a driver first."
            return
        }
        struct In: Encodable { let driverId: String; let message: String; let priority: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation(
                "dispatch.sendDriverMessage",
                input: In(driverId: driverId,
                          message: "Dock coordination for \(load?.loadNumber ?? "your assigned load") — confirm your door and loading status when you can.",
                          priority: "urgent"))
            if out.success == true {
                actionAck = "Dock thread opened with \(driverRow?.name ?? "the driver") — replies land in Comms."
            } else {
                actionError = "The dock thread didn't open. The card stays live — try again."
            }
        } catch {
            actionError = "The dock thread didn't open. The card stays live — check the connection and try again."
        }
    }
}

// MARK: - Detail sheet

private struct BH517DetailSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let load: LoadsAPI.LoadDetail?
    let tracking: BH517Tracking?

    var body: some View {
        ZStack {
            palette.bgPrimary.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack {
                        Text("Pickup detail").font(EType.h2).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(palette.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    if let l = load {
                        LifecycleCard {
                            row("Load", l.loadNumber)
                            row("Stage", bh517Humanize(l.status))
                            row("Lane", l.laneDisplay)
                            row("Distance", l.distanceDisplay)
                            row("Rate", l.rateDisplay)
                            row("Driver", l.driver?.name ?? "not locked")
                            row("Carrier", l.catalyst?.companyName ?? l.catalyst?.name ?? "—")
                        }
                    }
                    LifecycleCard {
                        if let p = tracking?.position {
                            row("GPS", String(format: "%.4f, %.4f", p.lat ?? 0, p.lng ?? 0))
                            row("Speed", p.speed.map { String(format: "%.0f mph", $0) } ?? "—")
                            row("Heartbeat", p.updatedAt ?? "—")
                        } else {
                            Text("No GPS fix has posted for this load — the position paints when the truck reports.")
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

// MARK: - Small primitives

private struct BH517Chip: View {
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

private struct BH517Kpi: View {
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

private struct BH517GateRow: View {
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
            BH517Chip(text: pill, tint: pillTint)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - File-local decode + helpers

private struct BH517Tracking: Decodable {
    struct Position: Decodable { let lat: Double?; let lng: Double?; let speed: Double?; let heading: Double?; let updatedAt: String? }
    struct Route: Decodable { let distanceMiles: Double?; let durationSeconds: Int? }
    struct Eta: Decodable { let predictedEta: String?; let remainingMiles: Double?; let remainingMinutes: Int? }
    let loadId: Int?
    let loadNumber: String?
    let status: String?
    let position: Position?
    let route: Route?
    let eta: Eta?
}

private struct BH517DriverRow: Decodable {
    let id: String?
    let name: String?
    let status: String?
    let load: String?
    let hoursRemaining: Double?
}

private func bh517ChainIndex(_ status: String?) -> Int {
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

private func bh517Humanize(_ raw: String?) -> String {
    guard let raw, !raw.isEmpty else { return "—" }
    return raw.replacingOccurrences(of: "_", with: " ").capitalized
}

private func bh517ISODate(_ s: String?) -> Date? {
    guard let s else { return nil }
    let f1 = ISO8601DateFormatter()
    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f1.date(from: s) { return d }
    return ISO8601DateFormatter().date(from: s)
}

// MARK: - Previews

#Preview("517 Pickup Fired · Dark") {
    DispatcherBHPickupFired517Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("517 Pickup Fired · Light") {
    DispatcherBHPickupFired517Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
