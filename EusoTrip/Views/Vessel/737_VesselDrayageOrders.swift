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
//    "New drayage order" -> multiModal.createDrayageOrder persists a terminal/port-backed load row
//      with drayage metadata in modeRoutePayload, then refreshes this live board.
//    "Filter" -> applies the same backend type/status/port/search contract as the board query.
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
    let id: String
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
    @State private var actionBanner: String? = nil
    @State private var actionError: String? = nil
    @State private var busyAction: String? = nil
    @State private var showNewOrder = false
    @State private var showFilters = false

    @State private var filterType = "all"
    @State private var filterStatus = "all"
    @State private var filterPortCode = ""
    @State private var filterSearch = ""

    @State private var draftType = "import"
    @State private var draftPortCode = ""
    @State private var draftTerminal = ""
    @State private var draftContainerNumber = ""
    @State private var draftContainerSize = "40ft"
    @State private var draftPickupLocation = ""
    @State private var draftDeliveryLocation = ""
    @State private var draftAppointment = Date()
    @State private var draftWeight = ""
    @State private var draftRate = ""
    @State private var draftHazmat = false
    @State private var draftNotes = ""

    // Hero
    @State private var activeCount = 0
    @State private var portCount = 0
    @State private var avgTurnTime: Int? = nil
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
                                   subtitle: emptySubtitle)
                    actionStatus
                    drayActionRow
                } else {
                    hero
                    actionStatus
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
                    drayActionRow
                    ESangRow737(title: esangTitle, subtitle: esangSubtitle)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showNewOrder) { newOrderSheet }
        .sheet(isPresented: $showFilters) { filterSheet }
    }

    // MARK: - Header (back + ✦ eyebrow + mono caption + 28pt title + overflow)

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · DRAYAGE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text(headerPortLabel).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
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
                    Text(avgTurnTime.map { "avg turn-time \($0) min" } ?? "avg turn-time unavailable")
                        .font(.system(size: 11)).foregroundStyle(palette.textTertiary)
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

    private var emptySubtitle: String {
        hasActiveFilters
        ? "No moves match the current type/status/port/search filters."
        : "getDrayageManagement returned no terminal-tagged moves. Create a live drayage order to place work on the board."
    }

    private var headerPortLabel: String {
        let port = trimmed(filterPortCode)
        return port == nil ? "DRAY · ALL PORTS" : "DRAY · \(port!.uppercased())"
    }

    private var hasActiveFilters: Bool {
        filterType != "all" || filterStatus != "all" || trimmed(filterPortCode) != nil || trimmed(filterSearch) != nil
    }

    private var actionStatus: some View {
        Group {
            if let actionError {
                LifecycleCard(accentDanger: true) {
                    Text(actionError).font(EType.caption).foregroundStyle(Brand.danger)
                }
            } else if let actionBanner {
                LifecycleCard {
                    Text(actionBanner).font(EType.caption).foregroundStyle(Brand.success)
                }
            }
        }
    }

    private var drayActionRow: some View {
        HStack(spacing: 8) {
            CTAButton(title: busyAction == "create" ? "Creating..." : "New drayage order",
                      action: {
                          if draftPortCode.isEmpty { draftPortCode = trimmed(filterPortCode) ?? "" }
                          showNewOrder = true
                      },
                      trailingIcon: "plus")
            secondaryButton737(title: hasActiveFilters ? "Filters on" : "Filter") { showFilters = true }
                .frame(width: 132)
        }
    }

    private var newOrderSheet: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                sheetHeader(title: "New drayage order", subtitle: "Create a load-backed drayage move on the live board.")

                Picker("Move type", selection: $draftType) {
                    ForEach(["import", "export", "pier_pass", "shuttle", "repositioning"], id: \.self) { value in
                        Text(typeLabel(value)).tag(value)
                    }
                }
                .pickerStyle(.menu)

                Picker("Container size", selection: $draftContainerSize) {
                    ForEach(["20ft", "40ft", "40ft_hc", "45ft", "53ft"], id: \.self) { value in
                        Text(value.replacingOccurrences(of: "_", with: " ").uppercased()).tag(value)
                    }
                }
                .pickerStyle(.segmented)

                sheetField("Port code", text: $draftPortCode, hint: "USLAX")
                sheetField("Terminal", text: $draftTerminal, hint: "APM Terminal or terminal code")
                sheetField("Container", text: $draftContainerNumber, hint: "MSCU1234567")
                sheetField("Pickup", text: $draftPickupLocation, hint: "Port pickup location")
                sheetField("Delivery", text: $draftDeliveryLocation, hint: "Customer / ramp / warehouse")

                DatePicker("Appointment", selection: $draftAppointment, displayedComponents: [.date, .hourAndMinute])
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)

                HStack(spacing: 10) {
                    sheetField("Weight", text: $draftWeight, hint: "lbs")
                    sheetField("Rate", text: $draftRate, hint: "USD")
                }
                Toggle("Hazmat", isOn: $draftHazmat)
                    .font(.system(size: 13, weight: .semibold))
                sheetField("Notes", text: $draftNotes, hint: "Dispatch instructions")

                HStack(spacing: 8) {
                    secondaryButton737(title: "Cancel") { showNewOrder = false }
                    CTAButton(title: busyAction == "create" ? "Creating..." : "Create order",
                              action: { Task { await submitNewOrder() } },
                              trailingIcon: "checkmark")
                }
            }
            .padding(Space.s5)
        }
        .background(palette.bgPrimary)
        .presentationDetents([.large])
    }

    private var filterSheet: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                sheetHeader(title: "Filter drayage", subtitle: "Filters run through multiModal.getDrayageManagement.")

                Picker("Move type", selection: $filterType) {
                    Text("All types").tag("all")
                    ForEach(["import", "export", "pier_pass", "shuttle", "repositioning"], id: \.self) { value in
                        Text(typeLabel(value)).tag(value)
                    }
                }
                .pickerStyle(.menu)

                Picker("Status", selection: $filterStatus) {
                    Text("All statuses").tag("all")
                    ForEach(["pending", "dispatched", "in_transit", "at_port", "completed"], id: \.self) { value in
                        Text(statusLabel(value)).tag(value)
                    }
                }
                .pickerStyle(.menu)

                sheetField("Port code", text: $filterPortCode, hint: "USLAX")
                sheetField("Search", text: $filterSearch, hint: "Order, container, terminal, city")

                HStack(spacing: 8) {
                    secondaryButton737(title: "Clear") { Task { await clearFilters() } }
                    CTAButton(title: "Apply filters",
                              action: { Task { await applyFilters() } },
                              trailingIcon: "line.3.horizontal.decrease.circle")
                }
            }
            .padding(Space.s5)
        }
        .background(palette.bgPrimary)
        .presentationDetents([.medium, .large])
    }

    private func sheetHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
        }
    }

    private func sheetField(_ title: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            TextField(hint, text: text)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .padding(12)
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
        }
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
                let id: String?
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
                input: DrayInput737(
                    page: 1,
                    limit: 50,
                    type: filterType == "all" ? nil : filterType,
                    status: filterStatus == "all" ? nil : filterStatus,
                    portCode: trimmed(filterPortCode),
                    search: trimmed(filterSearch)))

            guard let orders = r.orders, !orders.isEmpty else {
                moves = []; laneCounts = []; hasOrders = false; loading = false; return
            }

            var mapped: [DrayMove737] = []
            var bookedSum = 0.0
            var ratedCount = 0
            var ports = Set<String>()

            for o in orders {
                let lane = DrayLane737(status: o.status ?? "pending")
                if let rate = o.rate {
                    bookedSum += rate
                    ratedCount += 1
                }
                if let code = o.port?.code { ports.insert(code) }

                let pickup = o.pickupLocation ?? o.port?.name
                let delivery = o.deliveryLocation

                mapped.append(DrayMove737(
                    id: o.id ?? o.orderNumber ?? UUID().uuidString,
                    lane: lane,
                    typeLabel: typeLabel(o.type),
                    typeTint: typeTint(o.type),
                    order: o.orderNumber ?? "—",
                    container: containerLine(o.containerNumber, o.containerSize),
                    route: routeLine(pickup, delivery),
                    appt: shortTime(o.appointmentTime),
                    lfd: lfdLabel(o.lastFreeDay, perDiem: o.perDiemDays),
                    lfdTint: lfdTint(o.lastFreeDay, perDiem: o.perDiemDays),
                    rate: o.rate.map { "$\(Int($0).formatted())" } ?? "—"
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
            avgTurnTime = s?.avgTurnTime
            bookedTotal = ratedCount > 0 ? "$\(Int(bookedSum).formatted())" : "—"
            nDispatched = s?.dispatched ?? counts[.dispatched, default: 0]
            nCompleted = s?.completed ?? counts[.completed, default: 0]

            hasOrders = true
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - CTAs

    private func submitNewOrder() async {
        actionError = nil
        actionBanner = nil

        guard let portCode = trimmed(draftPortCode) else {
            actionError = "Port code is required."
            return
        }
        guard let terminal = trimmed(draftTerminal) else {
            actionError = "Terminal is required."
            return
        }
        guard let container = trimmed(draftContainerNumber) else {
            actionError = "Container number is required."
            return
        }
        guard let delivery = trimmed(draftDeliveryLocation) else {
            actionError = "Delivery location is required."
            return
        }

        busyAction = "create"
        do {
            let formatter = ISO8601DateFormatter()
            let out: DrayCreateOut737 = try await EusoTripAPI.shared.mutation(
                "multiModal.createDrayageOrder",
                input: DrayCreateInput737(
                    type: draftType,
                    portCode: portCode.uppercased(),
                    terminal: terminal,
                    containerNumber: container.uppercased(),
                    containerSize: draftContainerSize,
                    pickupLocation: trimmed(draftPickupLocation),
                    deliveryLocation: delivery,
                    appointmentTime: formatter.string(from: draftAppointment),
                    weight: Double(trimmed(draftWeight) ?? ""),
                    rate: Double(trimmed(draftRate) ?? ""),
                    hazmat: draftHazmat,
                    notes: trimmed(draftNotes)
                )
            )
            actionBanner = "Created \(out.orderNumber ?? out.id ?? "drayage order")."
            showNewOrder = false
            resetDraft()
            await load()
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        busyAction = nil
    }

    private func applyFilters() async {
        showFilters = false
        await load()
    }

    private func clearFilters() async {
        filterType = "all"
        filterStatus = "all"
        filterPortCode = ""
        filterSearch = ""
        showFilters = false
        await load()
    }

    private func resetDraft() {
        draftType = "import"
        draftPortCode = trimmed(filterPortCode) ?? ""
        draftTerminal = ""
        draftContainerNumber = ""
        draftContainerSize = "40ft"
        draftPickupLocation = ""
        draftDeliveryLocation = ""
        draftAppointment = Date()
        draftWeight = ""
        draftRate = ""
        draftHazmat = false
        draftNotes = ""
    }

    // MARK: - Field formatters

    private func trimmed(_ value: String) -> String? {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

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
    private func statusLabel(_ status: String) -> String {
        switch status {
        case "pending":    "Pending"
        case "dispatched": "Dispatched"
        case "in_transit": "In transit"
        case "at_port":    "At port"
        case "completed":  "Completed"
        default:           status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    private func containerLine(_ num: String?, _ size: String?) -> String {
        let n = num ?? "—"
        guard let s = size, !s.isEmpty else { return n }
        return "\(n) · \(s)"
    }
    private func routeLine(_ pickup: String?, _ delivery: String?) -> String {
        switch (pickup, delivery) {
        case let (.some(p), .some(d)): return "\(p) → \(d)"
        case let (.some(p), nil): return p
        case let (nil, .some(d)): return d
        default: return "route pending"
        }
    }
    private func shortTime(_ iso: String?) -> String {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return iso ?? "—" }
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
        guard let d = daysToLFD(iso) else { return "LFD pending" }
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
private struct DrayInput737: Encodable {
    let page: Int
    let limit: Int
    let type: String?
    let status: String?
    let portCode: String?
    let search: String?
}

private struct DrayCreateInput737: Encodable {
    let type: String
    let portCode: String
    let terminal: String
    let containerNumber: String
    let containerSize: String
    let pickupLocation: String?
    let deliveryLocation: String
    let appointmentTime: String
    let weight: Double?
    let rate: Double?
    let hazmat: Bool
    let notes: String?
}

private struct DrayCreateOut737: Decodable {
    let id: String?
    let orderNumber: String?
}

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
