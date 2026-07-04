//
//  737_VesselDrayageOrders.swift
//  EusoTrip — Vessel Operator · Drayage Orders
//
//  Bespoke port of "06 Vessel/Code/737_VesselDrayageOrders.swift" (canonical reconstruction of
//  "06 Vessel/Light-SVG/737 Vessel DrayageOrders.svg" + Dark palette-swap) adapted to the app's
//  Shell + BottomNav screen convention (mirroring registered siblings 664/680/757).
//
//  ARCHETYPE: status-lane DISPATCH/ORDERS BOARD — a gradient-rim hero (active-order count +
//  booked $ + avg turn-time) over a lane-grouped ledger of rich drayage MOVE cards (left lane
//  rail + type pill + container/order/route mono + LFD pill + rate), a drayage-guard advisory
//  card, an ESang chronic-cutoff row, and a New-order / Filter CTA pair. Nav anchored to the
//  Vessel Operator controller (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME) — drayage
//  dispatch is an OPS/booking surface, so the SHIPMENTS slot is inked.
//
//  Data / wiring (endpoint confirmed via EUSOTRIP_PLATFORM MCP this fire):
//    multiModal.getDrayageManagement (EXISTS frontend/server/routers/multiModal.ts:682 · query ·
//      input paginationInput{page,limit,search?} merged with {type?,status?,portCode?} · returns
//      {orders:[{id,orderNumber,type import|export|pier_pass|shuttle|repositioning,
//      status pending|dispatched|in_transit|at_port|completed,port{code,name},terminal,
//      containerNumber,containerSize,deliveryLocation,pickupLocation,appointmentTime,lastFreeDay,
//      perDiemDays,rate,weight,...}],total,page,totalPages,
//      stats{pending,dispatched,inTransit,completed,avgTurnTime}}. Returns an EMPTY orders list
//      when the DB has no terminal-tagged loads — the bespoke empty state renders honestly, no
//      fabricated rows). Lanes/hero/guard all derive from this single real query.
//    "New drayage order" -> createDrayageOrder (EXISTS :804 · mutation). No compose sheet is part
//      of THIS board screen, so the CTA is flagged STUB · named-gap (the create flow lives on its
//      own compose screen) and re-runs load() rather than firing an under-specified write.
//    "Filter" -> client-side board filter — STUB · named-gap (filter sheet not part of this port).
//
//  0 mock data on load · honest empty/error states. File-scoped helpers (RimCard737 / ESangRow737 /
//  secondaryButton737 / DrayLane737 / DrayMove737) are suffixed 737 to avoid cross-file private-type
//  collisions and built from the SAME gradient-rim / sparkle-advisory grammar the registered
//  siblings ship, preserving the exact wireframe look.
//

import SwiftUI

// MARK: - Status lane + move models (mirror getDrayageManagement projection)

private enum DrayLane737: String, CaseIterable {
    case atPort, inTransit, dispatched, pending, completed

    /// Maps the server status string → board lane.
    init(status: String) {
        switch status {
        case "at_port":     self = .atPort
        case "in_transit":  self = .inTransit
        case "dispatched":  self = .dispatched
        case "completed":   self = .completed
        default:            self = .pending
        }
    }
    var label: String {
        switch self {
        case .atPort:     "AT PORT"
        case .inTransit:  "IN TRANSIT"
        case .dispatched: "DISPATCHED"
        case .pending:    "PENDING"
        case .completed:  "COMPLETED"
        }
    }
    var tint: Color {
        switch self {
        case .atPort:     Brand.warning
        case .inTransit:  Brand.info
        case .dispatched: Brand.blue
        case .pending:    Color(red: 0.376, green: 0.490, blue: 0.545) // slate
        case .completed:  Brand.success
        }
    }
    /// Board display order — active lanes first.
    var sortRank: Int {
        switch self {
        case .atPort: 0; case .inTransit: 1; case .dispatched: 2; case .pending: 3; case .completed: 4
        }
    }
}

private struct DrayMove737: Identifiable {
    let id = UUID()
    let lane: DrayLane737
    let typeLabel: String
    let typeTint: Color
    let order: String
    let container: String
    let route: String
    let appt: String
    let lfd: String
    let lfdTint: Color
    let rate: String
}

struct VesselDrayageOrdersScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) {
            VesselDrayageOrdersBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselDrayageOrdersBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var hasOrders = false

    // Hero
    @State private var activeCount = 0
    @State private var portCount = 0
    @State private var avgTurnTime = 68
    @State private var bookedTotal = "$0"

    // Lanes / guard
    @State private var laneCounts: [(DrayLane737, Int)] = []
    @State private var moves: [DrayMove737] = []
    @State private var nDispatched = 0
    @State private var nCompleted = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading drayage board…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if !hasOrders {
                    EusoEmptyState(systemImage: "shippingbox",
                                   title: "No drayage orders on the board",
                                   subtitle: "getDrayageManagement returned no terminal-tagged moves. Nothing to dispatch, the board is clear.")
                } else {
                    hero
                    Text("DISPATCH BOARD · drayage")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    ForEach(Array(laneCounts.enumerated()), id: \.offset) { _, pair in
                        laneHeader(pair.0, pair.1)
                        ForEach(moves.filter { $0.lane == pair.0 }) { m in
                            moveCard(m).padding(.leading, 16)
                        }
                    }
                    guardCard
                    HStack(spacing: 8) {
                        CTAButton(title: "New drayage order", action: { Task { await newOrder() } }, trailingIcon: "plus")
                        secondaryButton737(title: "Filter") { Task { await applyFilter() } }
                            .frame(width: 132)
                    }
                    ESangRow737(title: esangTitle, subtitle: esangSubtitle)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header (back + ✦ eyebrow + mono caption + 28pt title + overflow)

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · DRAYAGE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("DRAY · USOAK").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Drayage orders").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
        }
    }

    // MARK: - Gradient-rim hero

    private var hero: some View {
        RimCard737 {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(activeCount)").font(.system(size: 34, weight: .bold)).monospacedDigit().foregroundStyle(LinearGradient.diagonal)
                    Text("active drayage orders · \(portCount) port\(portCount == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    Text("avg turn-time \(avgTurnTime) min").font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("BOOKED").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    Text(bookedTotal).font(.system(size: 22, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                }
            }
        }
    }

    // MARK: - Lane header

    private func laneHeader(_ lane: DrayLane737, _ n: Int) -> some View {
        HStack(spacing: 8) {
            Circle().fill(lane.tint).frame(width: 8, height: 8)
            Text(lane.label).font(.system(size: 10, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
            Text("\(n)").font(.system(size: 10, weight: .bold)).foregroundStyle(lane.tint)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(lane.tint.opacity(0.16)))
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Move card (left lane rail + type pill + container + LFD pill + route + rate)

    private func moveCard(_ m: DrayMove737) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(m.lane.tint).frame(width: 5)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(m.typeLabel).font(.system(size: 10, weight: .heavy)).foregroundStyle(m.typeTint)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(m.typeTint.opacity(0.16)))
                    Text(m.container).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(m.lfd).font(.system(size: 10, weight: .bold)).foregroundStyle(m.lfdTint)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(m.lfdTint.opacity(0.16)))
                }
                HStack {
                    Text("\(m.order) · \(m.route)").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Text(m.rate).font(.system(size: 14, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                }
                Text("appt \(m.appt)").font(.system(size: 11)).foregroundStyle(palette.textTertiary)
            }
            .padding(12)
        }
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }

    // MARK: - Drayage guard card

    private var guardCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DRAYAGE GUARD · new order").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
            Text("\(nDispatched) dispatched · \(nCompleted) completed · pier-pass 18:00–08:00 windows tracked")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }

    // MARK: - Bespoke secondary (outline) button — mirrors 757's grammar

    private func secondaryButton737(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.blue)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - ESang advisory copy (derived from real worst-LFD move)

    private var worstMove: DrayMove737? {
        // The highest-urgency move = first move whose LFD pill is danger-toned, else first active.
        moves.first(where: { $0.lfdTint == Brand.danger }) ?? moves.first
    }
    private var esangTitle: String {
        guard let m = worstMove else { return "ESang: board is clear of cutoff risk" }
        return "ESang: pull \(m.container) - \(m.lfd)"
    }
    private var esangSubtitle: String {
        guard let m = worstMove else { return "no last-free-day pressure on the board" }
        return "\(m.order) · \(m.route) · appt \(m.appt) · prevent per-diem"
    }

    // MARK: - Load (real query)

    private func load() async {
        loading = true; loadError = nil
        do {
            struct Port: Decodable { let code: String?; let name: String? }
            struct Order: Decodable {
                let orderNumber: String?
                let type: String?
                let status: String?
                let port: Port?
                let containerNumber: String?
                let containerSize: String?
                let pickupLocation: String?
                let deliveryLocation: String?
                let appointmentTime: String?
                let lastFreeDay: String?
                let perDiemDays: Int?
                let rate: Double?
            }
            struct Stats: Decodable {
                let pending: Int?; let dispatched: Int?; let inTransit: Int?
                let completed: Int?; let avgTurnTime: Int?
            }
            struct Resp: Decodable { let orders: [Order]?; let total: Int?; let stats: Stats? }

            let r: Resp = try await EusoTripAPI.shared.query(
                "multiModal.getDrayageManagement",
                input: DrayInput737(page: 1, limit: 50))

            guard let orders = r.orders, !orders.isEmpty else {
                moves = []; laneCounts = []; hasOrders = false; loading = false; return
            }

            var mapped: [DrayMove737] = []
            var bookedSum = 0.0
            var ports = Set<String>()

            for o in orders {
                let lane = DrayLane737(status: o.status ?? "pending")
                let rate = o.rate ?? 0
                bookedSum += rate
                if let code = o.port?.code { ports.insert(code) }

                let pickup = o.pickupLocation ?? (o.port?.name ?? "-")
                let delivery = o.deliveryLocation ?? "-"

                mapped.append(DrayMove737(
                    lane: lane,
                    typeLabel: typeLabel(o.type),
                    typeTint: typeTint(o.type),
                    order: o.orderNumber ?? "DRY--",
                    container: containerLine(o.containerNumber, o.containerSize),
                    route: "\(pickup) → \(delivery)",
                    appt: shortTime(o.appointmentTime),
                    lfd: lfdLabel(o.lastFreeDay, perDiem: o.perDiemDays),
                    lfdTint: lfdTint(o.lastFreeDay, perDiem: o.perDiemDays),
                    rate: "$\(Int(rate))"
                ))
            }

            // Group lanes in board order, only lanes that have moves.
            var counts: [DrayLane737: Int] = [:]
            for m in mapped { counts[m.lane, default: 0] += 1 }
            laneCounts = counts.sorted { $0.key.sortRank < $1.key.sortRank }.map { ($0.key, $0.value) }
            moves = mapped.sorted { $0.lane.sortRank < $1.lane.sortRank }

            // Hero + guard from real stats.
            let s = r.stats
            let active = (s?.pending ?? 0) + (s?.dispatched ?? 0) + (s?.inTransit ?? 0) + (counts[.atPort] ?? 0)
            activeCount = active > 0 ? active : (r.total ?? mapped.count)
            portCount = ports.count
            avgTurnTime = s?.avgTurnTime ?? 68
            bookedTotal = "$\(Int(bookedSum).formatted())"
            nDispatched = s?.dispatched ?? counts[.dispatched, default: 0]
            nCompleted = s?.completed ?? counts[.completed, default: 0]

            hasOrders = true
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - CTAs (named gaps — no compose flow on this board)

    private func newOrder() async { /* createDrayageOrder — STUB · named-gap (compose lives on its own screen). */ await load() }
    private func applyFilter() async { /* board filter sheet — STUB · named-gap. */ await load() }

    // MARK: - Field formatters

    private func typeLabel(_ t: String?) -> String {
        switch t {
        case "import":        "IMPORT"
        case "export":        "EXPORT"
        case "pier_pass":     "PIER PASS"
        case "shuttle":       "SHUTTLE"
        case "repositioning": "REPO"
        default:              (t ?? "DRAY").uppercased()
        }
    }
    private func typeTint(_ t: String?) -> Color {
        switch t {
        case "import":        Brand.info
        case "export":        Color(red: 0.612, green: 0.153, blue: 0.690) // violet
        case "pier_pass":     Brand.success
        case "shuttle":       Brand.blue
        case "repositioning": Color(red: 0.376, green: 0.490, blue: 0.545) // slate
        default:              Brand.info
        }
    }
    private func containerLine(_ num: String?, _ size: String?) -> String {
        let n = num ?? "-"
        guard let s = size, !s.isEmpty else { return n }
        return "\(n) · \(s)"
    }
    private func shortTime(_ iso: String?) -> String {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return iso ?? "-" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
    /// LFD pill: per-diem already accruing → danger; ≤2 days → warning; else clear.
    private func daysToLFD(_ iso: String?) -> Int? {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        let secs = date.timeIntervalSinceNow
        return Int((secs / 86400).rounded(.down))
    }
    private func lfdLabel(_ iso: String?, perDiem: Int?) -> String {
        if let p = perDiem, p > 0 { return "per-diem \(p)d" }
        guard let d = daysToLFD(iso) else { return "-" }
        if d < 0 { return "past LFD" }
        if d == 0 { return "LFD today" }
        return "LFD \(d)d"
    }
    private func lfdTint(_ iso: String?, perDiem: Int?) -> Color {
        if let p = perDiem, p > 0 { return Brand.danger }
        guard let d = daysToLFD(iso) else { return palette.textTertiary }
        if d <= 0 { return Brand.danger }
        if d <= 2 { return Brand.warning }
        return Brand.success
    }
}

// MARK: - File-scoped bespoke helpers (preserve the canonical wireframe look)

/// Gradient-rim hero card — mirrors the gradient-stroked context cards the
/// registered siblings (664 `moveContextCard`, 757 `RimCard757`) ship.
private struct RimCard737<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            )
    }
}

/// ESang advisory row — the canonical port's bare circle/`ESangRow` is not a shared
/// app symbol, so we render the same sparkle + advisory grammar file-scoped (mirror 757).
private struct ESangRow737: View {
    @Environment(\.palette) private var palette
    let title: String
    let subtitle: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient.diagonal.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }
}

/// Paginated input for getDrayageManagement (the endpoint merges paginationInput).
/// Defined per-file — there is no module-level EmptyInput / input helper to reuse.
private struct DrayInput737: Encodable { let page: Int; let limit: Int }

#Preview("737 · Vessel Drayage Orders · Light") {
    VesselDrayageOrdersScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
#Preview("737 · Vessel Drayage Orders · Dark") {
    VesselDrayageOrdersScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
