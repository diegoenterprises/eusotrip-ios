//
//  617_RailDrayageOrders.swift
//  EusoTrip — Rail Engineer · Drayage Orders.
//
//  CARRIER-SIDE ORDER-BOARD archetype: the drayage (truck-leg) order queue at
//  the ramp. A filter-chip row (All / Dispatched / At-ramp / Pending), an
//  orders-today summary hero, an itemized order list where each drayage leg
//  carries an 8-stage child-truck-mode lifecycle dot strip + a status pill
//  (DISPATCH / AT RAMP / PENDING) clear of the right cutoff/dwell value, and a
//  capacity-guard tile shelf.
//
//  WHY: each rail container's first/last mile is a child truck lifecycle; this
//  board lets Owen dispatch the right dray carrier to the right move before the
//  gate cutoff so containers do not sit and accrue detention.
//
//  Web parity: app/(rail)/drayage/orders/page.tsx
//  tRPC: multiModal.getDrayageManagement EXISTS · server/routers/multiModal.ts:682
//        ({type,status,portCode,page,limit,search} → {orders,total,stats}).
//  PORT-GAP: multiModal.dispatchDrayage — no such mutation exists. The desc
//            proposes multiModal.dispatchDrayage({drayageOrderId,carrierId,
//            appointmentTime}); until it lands the "Dispatch dray" CTA surfaces
//            a real "not wired" error instead of fabricating a success.
//  RBAC: protectedProcedure (companyId-scoped). transportMode=rail (drayage
//        child legs are truck-mode). Single-country US (Corwith · BNSF · IL).
//

import SwiftUI

struct RailDrayageOrdersScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailDrayageOrdersBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror multiModal.getDrayageManagement output)

private struct DrayPort: Decodable {
    let code: String?
    let name: String?
}

private struct DrayDriver: Decodable {
    let id: String?
    let name: String?
}

private struct DrayTruck: Decodable {
    let id: String?
    let number: String?
}

private struct DrayageOrder: Decodable, Identifiable {
    let id: String
    let orderNumber: String?
    let type: String?           // import | export | pier_pass | shuttle | repositioning
    let status: String?         // pending | dispatched | in_transit | at_port | completed
    let port: DrayPort?
    let terminal: String?
    let containerNumber: String?
    let containerSize: String?
    let chassisNumber: String?
    let driver: DrayDriver?
    let truck: DrayTruck?
    let pickupLocation: String?
    let deliveryLocation: String?
    let appointmentTime: String?
    let lastFreeDay: String?
    let perDiemDays: Int?
    let rate: Double?
    let weight: Double?
    let seal: String?
    let createdAt: String?
}

private struct DrayageStats: Decodable {
    let pending: Int?
    let dispatched: Int?
    let inTransit: Int?
    let completed: Int?
    let avgTurnTime: Int?
}

private struct DrayageManagement: Decodable {
    let orders: [DrayageOrder]?
    let total: Int?
    let page: Int?
    let totalPages: Int?
    let stats: DrayageStats?
}

// MARK: - Body

private struct RailDrayageOrdersBody: View {
    @Environment(\.palette) private var palette

    @State private var orders: [DrayageOrder] = []
    @State private var stats: DrayageStats? = nil
    @State private var total: Int = 0
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var dispatchNotice: String? = nil

    // Filter chips. `nil` status = All. Maps directly onto the server enum so
    // the chip selection drives the real query input.
    enum Filter: Equatable {
        case all
        case dispatched
        case atRamp
        case pending

        var apiStatus: String? {
            switch self {
            case .all:        return nil
            case .dispatched: return "dispatched"
            case .atRamp:     return "at_port"   // "at-ramp" maps to the at_port server state
            case .pending:    return "pending"
            }
        }
    }
    @State private var filter: Filter = .all

    // Derived counts off the live stats payload (no fabricated numbers).
    private var dispatchedCount: Int { stats?.dispatched ?? 0 }
    private var atRampCount: Int { (stats?.inTransit ?? 0) + (stats?.completed ?? 0) == 0
        ? 0 : (stats?.inTransit ?? 0) }   // at-ramp ≈ in_transit/at_port bucket
    private var pendingCount: Int { stats?.pending ?? 0 }
    private var allCount: Int { total }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow
                titleBlock
                filterChips
                IridescentHairline()
                    .padding(.top, Space.s3)
                    .padding(.horizontal, Space.s5)

                VStack(alignment: .leading, spacing: Space.s4) {
                    summaryHero
                    openDrayageSection
                    capacityGuardSection
                    ctaRow
                    if let notice = dispatchNotice {
                        Text(notice)
                            .font(EType.caption)
                            .foregroundStyle(Brand.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
        .onChange(of: filter) { _, _ in Task { await reload() } }
    }

    // MARK: - Eyebrow (RAIL ENGINEER · DRAYAGE  /  CORWITH · BNSF)

    private var eyebrow: some View {
        HStack {
            Text("✦  RAIL ENGINEER · DRAYAGE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("CORWITH · BNSF")
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
    }

    // MARK: - Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Drayage orders")
                        .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                        .foregroundStyle(palette.textPrimary)
                }
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .rotationEffect(.degrees(90))
            }
            Text("Corwith Intermodal · child truck legs")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.leading, 24)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s3)
    }

    // MARK: - Filter chips (All / Dispatched / At-ramp / Pending)

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", count: allCount, filter: .all, tint: nil)
                chip("Dispatched", count: dispatchedCount, filter: .dispatched, tint: Color(hex: 0x4DA3FF))
                chip("At-ramp", count: atRampCount, filter: .atRamp, tint: Color(hex: 0x90A4AE))
                chip("Pending", count: pendingCount, filter: .pending, tint: Brand.warning)
            }
            .padding(.horizontal, Space.s5)
        }
        .padding(.top, Space.s3)
    }

    private func chip(_ label: String, count: Int, filter f: Filter, tint: Color?) -> some View {
        let selected = filter == f
        return Button {
            filter = f
        } label: {
            Text("\(label) · \(count)")
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(selected ? .white : (tint ?? palette.textSecondary))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .frame(height: 26)
                .background(
                    Group {
                        if selected {
                            Capsule().fill(LinearGradient.primary)
                        } else {
                            Capsule().fill(Color(hex: 0x232932))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                        }
                    }
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary hero (DRAYAGE ORDERS · TODAY)

    private var summaryHero: some View {
        let cutoff = nextCutoff
        let carriers = distinctCarrierCount
        let detention = detentionCount
        return ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: Radius.xl - 1.5, style: .continuous)
                .fill(Color(hex: 0x1C2128))
                .padding(1.5)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("DRAYAGE ORDERS · TODAY")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Text("\(allCount)")
                        .font(.system(size: 40, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                        .padding(.top, 6)
                    Text("\(dispatchedCount) dispatched · \(atRampCount) at-ramp · \(pendingCount) pending")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.top, 4)
                    // Progress bar — dispatched share of today's board.
                    GeometryReader { geo in
                        let frac: CGFloat = allCount > 0
                            ? min(1.0, CGFloat(dispatchedCount) / CGFloat(allCount)) : 0
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.18))
                            Capsule().fill(LinearGradient.primary)
                                .frame(width: geo.size.width * frac)
                        }
                    }
                    .frame(width: 150, height: 6)
                    .padding(.top, 8)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    heroStat(value: cutoff, label: "next cutoff")
                    heroStat(value: "\(carriers)", label: "carriers")
                    heroStat(value: "\(detention)", label: "detention")
                }
            }
            .padding(Space.s5)
        }
        .frame(height: 104)
    }

    private func heroStat(value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .bold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Open drayage · live

    private var openDrayageSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("OPEN DRAYAGE · LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Color(hex: 0x4DA3FF))
                Spacer()
                Text("see all ›")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                .padding(.top, 6)

            if loading {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCardSoft).frame(height: 78)
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderFaint))
                            .padding(.vertical, 4)
                    }
                }
                .padding(.top, Space.s2)
            } else if let err = loadError {
                LifecycleCard(accentDanger: true) {
                    Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                }
                .padding(.top, Space.s2)
            } else if orders.isEmpty {
                EusoEmptyState(systemImage: "box.truck",
                               title: "No open drayage",
                               subtitle: "Drayage child legs for Corwith will appear here.")
                    .padding(.top, Space.s2)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(orders.prefix(3).enumerated()), id: \.element.id) { idx, order in
                        orderRow(order)
                        if idx < min(orders.count, 3) - 1 {
                            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .background(Color(hex: 0x1C2128))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08)))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .padding(.top, Space.s2)
            }
        }
    }

    private func orderRow(_ order: DrayageOrder) -> some View {
        let pill = statusPill(for: order.status)
        let stage = lifecycleStage(for: order.status)   // 1...8
        return HStack(alignment: .top, spacing: 12) {
            // Truck glyph chip — tinted to the status color.
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(pill.color.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: "box.truck")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(pill.color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(legTitle(for: order))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(idLine(for: order))
                    .font(EType.mono(.caption)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                // 8-stage child-truck-mode lifecycle dot strip.
                lifecycleDots(stage: stage)
                    .padding(.top, 2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(pill.label)
                    .font(.system(size: 10.5, weight: .bold)).tracking(0.4)
                    .foregroundStyle(pill.color)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(pill.color.opacity(0.20)))
                VStack(alignment: .trailing, spacing: 1) {
                    Text(rightValue(for: order))
                        .font(.system(size: 14, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text(rightLabel(for: order.status))
                        .font(.system(size: 9))
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(16)
    }

    private func lifecycleDots(stage: Int) -> some View {
        // 8 dots: filled (gradient) up to `stage`, the current dot slightly
        // larger, remaining dots faint white.
        HStack(spacing: 5) {
            ForEach(0..<8, id: \.self) { i in
                let filled = i < stage
                let isCurrent = i == stage - 1
                Circle()
                    .fill(filled ? AnyShapeStyle(LinearGradient.primary)
                                 : AnyShapeStyle(Color.white.opacity(0.18)))
                    .frame(width: isCurrent ? 6 : (filled ? 5 : 4),
                           height: isCurrent ? 6 : (filled ? 5 : 4))
            }
        }
    }

    // MARK: - Capacity guard

    private var capacityGuardSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CAPACITY GUARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("today")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                .padding(.top, 6)
            HStack(spacing: 14) {
                guardTile(dot: Brand.success, title: "\(dispatchedCount) dispatched",
                          line1: "on the road", line2: "BNSF · IL")
                guardTile(dot: Brand.blue, title: "\(atRampCount) at-ramp",
                          line1: "awaiting pull", line2: ">1h dwell")
                guardTile(dot: Brand.danger, title: "\(detentionCount) detention",
                          line1: "billing live", line2: ">2h")
            }
            .padding(.top, Space.s3)
        }
    }

    private func guardTile(dot: Color, title: String, line1: String, line2: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(dot).frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(line1)
                .font(.system(size: 9.5))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 10)
            Text(line2)
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(Color(hex: 0x1C2128))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - CTA row (Dispatch dray · Assign)

    private var ctaRow: some View {
        HStack(spacing: 8) {
            Button {
                dispatchDray()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "box.truck")
                        .font(.system(size: 14, weight: .bold))
                    Text("Dispatch dray")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.primary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                dispatchDray()
            } label: {
                Text("Assign")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(Color(hex: 0x232932))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Derived presentation helpers

    private func statusPill(for status: String?) -> (label: String, color: Color) {
        switch (status ?? "").lowercased() {
        case "dispatched":           return ("DISPATCH", Brand.blue)
        case "in_transit", "at_port": return ("AT RAMP", Brand.warning)
        case "pending":              return ("PENDING", Color(hex: 0x90A4AE))
        case "completed":            return ("COMPLETE", Brand.success)
        default:                     return ("PENDING", Color(hex: 0x90A4AE))
        }
    }

    // 8-stage child-truck-mode lifecycle. Map the server status to a stage
    // index (1...8) along the dray leg: dispatch → en-route → at-ramp pull →
    // pulled → in-transit → at-delivery → unloaded → complete.
    private func lifecycleStage(for status: String?) -> Int {
        switch (status ?? "").lowercased() {
        case "pending":     return 2
        case "dispatched":  return 3
        case "in_transit":  return 5
        case "at_port":     return 5
        case "completed":   return 8
        default:            return 2
        }
    }

    private func legTitle(for order: DrayageOrder) -> String {
        // Derived from the dray type + delivery, matching the SVG's
        // "Import pull · Pier J" / "Export drop · Alliance" pattern.
        let kind: String
        switch (order.type ?? "").lowercased() {
        case "import":        kind = "Import pull"
        case "export":        kind = "Export drop"
        case "repositioning": kind = "Repo empty"
        case "pier_pass":     kind = "Pier pass"
        case "shuttle":       kind = "Shuttle"
        default:              kind = "Drayage"
        }
        let where_ = order.terminal ?? order.port?.name ?? order.deliveryLocation ?? "Ramp"
        return "\(kind) · \(where_)"
    }

    private func idLine(for order: DrayageOrder) -> String {
        // "TCNU 769312 · 40HC · LB" — container · size · port code.
        let cnRaw = order.containerNumber ?? order.orderNumber ?? "—"
        let cn: String = {
            if cnRaw.count > 4 {
                let prefix = String(cnRaw.prefix(4))
                let rest = String(cnRaw.dropFirst(4))
                return "\(prefix) \(rest)"
            }
            return cnRaw
        }()
        let size = sizeShort(order.containerSize)
        let port = order.port?.code ?? "—"
        return "\(cn) · \(size) · \(port)"
    }

    private func sizeShort(_ s: String?) -> String {
        switch (s ?? "").lowercased() {
        case "40ft_hc": return "40HC"
        case "40ft":    return "40'"
        case "20ft":    return "20'"
        case "45ft":    return "45'"
        case "53ft":    return "53'"
        default:        return s ?? "—"
        }
    }

    private func rightLabel(for status: String?) -> String {
        switch (status ?? "").lowercased() {
        case "dispatched":            return "cutoff"
        case "in_transit", "at_port": return "dwell"
        case "pending":               return "unassigned"
        default:                      return "unassigned"
        }
    }

    private func rightValue(for order: DrayageOrder) -> String {
        switch (order.status ?? "").lowercased() {
        case "dispatched":
            return shortTime(order.appointmentTime) ?? "—"
        case "in_transit", "at_port":
            return dwell(since: order.appointmentTime) ?? "—"
        default:
            return "—"
        }
    }

    private func shortTime(_ iso: String?) -> String? {
        guard let iso, let date = parseDate(iso) else { return nil }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func dwell(since iso: String?) -> String? {
        guard let iso, let date = parseDate(iso) else { return nil }
        let secs = max(0, -date.timeIntervalSinceNow)
        let h = Int(secs) / 3600
        let m = (Int(secs) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func parseDate(_ iso: String) -> Date? {
        if let d = ISO8601DateFormatter().date(from: iso) { return d }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso)
    }

    // Hero "next cutoff" — earliest dispatched appointment time.
    private var nextCutoff: String {
        let times = orders.compactMap { o -> Date? in
            guard (o.status ?? "").lowercased() == "dispatched" else { return nil }
            return o.appointmentTime.flatMap { parseDate($0) }
        }.sorted()
        guard let first = times.first else { return "—" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: first)
    }

    private var distinctCarrierCount: Int {
        Set(orders.compactMap { $0.driver?.id }).count
    }

    // Detention ≈ orders with per-diem accrued past free time.
    private var detentionCount: Int {
        orders.filter { ($0.perDiemDays ?? 0) > 0 }.count
    }

    // MARK: - Load

    private func reload() async {
        loading = true; loadError = nil
        struct DrayageIn: Encodable {
            let page: Int
            let limit: Int
            let status: String?
        }
        do {
            let res: DrayageManagement = try await EusoTripAPI.shared.query(
                "multiModal.getDrayageManagement",
                input: DrayageIn(page: 1, limit: 25, status: filter.apiStatus))
            self.orders = res.orders ?? []
            self.stats = res.stats
            self.total = res.total ?? (res.orders?.count ?? 0)
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Dispatch dray (PORT-GAP)

    private func dispatchDray() {
        // PORT-GAP: multiModal.dispatchDrayage({drayageOrderId, carrierId,
        // appointmentTime}) — proposed in 617's <desc>, not yet shipped on the
        // server. No mutation to call, so surface the real gap rather than
        // fabricate a success ack. Once the mutation lands (with
        // blockchainAuditTrail insert + WS broadcast), wire it here.
        dispatchNotice = "Dispatch is not yet wired — multiModal.dispatchDrayage has not shipped. (PORT-GAP)"
    }
}

#Preview("617 · Rail Drayage Orders · Night") {
    RailDrayageOrdersScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("617 · Rail Drayage Orders · Light") {
    RailDrayageOrdersScreen(theme: Theme.light).preferredColorScheme(.light)
}
