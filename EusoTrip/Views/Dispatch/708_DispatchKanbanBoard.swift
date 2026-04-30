//
//  708_DispatchKanbanBoard.swift
//  EusoTrip — Dispatch · Lifecycle kanban (paged columns, tap-to-advance).
//
//  Innovation over Dispatch.com style:
//   • Full-width snap pages instead of cramped Trello columns — one stage at a
//     time, designed for thumbs.
//   • Bottom scrubber chips with live counts let dispatchers jump 4 stages
//     without dragging.
//   • Tap card → bottom sheet with the next-stage button. Status update fires
//     dispatch.updateLoadStatus which emits LOAD_STATUS_CHANGED on the socket.
//   • Hazmat / multi-stop loads carry the same chrome as dry-van — full
//     vertical/product parity per founder doctrine.
//

import SwiftUI

struct DispatchKanbanBoardScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { KanbanBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .working
            )
        }
    }
}

private struct KanbanLoad: Decodable, Identifiable, Hashable {
    let id: Int
    let loadNumber: String
    let status: String
    let rate: Double?
    let distance: Double?
    let weight: Double?
    let cargoType: String?
    let hazmatClass: String?
    let commodityName: String?
    let pickupDate: String?
    let deliveryDate: String?
    let driverId: Int?
    let driverName: String?
}

private struct UnifiedLoadsResponse: Decodable, Hashable {
    let loads: [KanbanLoad]
    let total: Int
    struct Summary: Decodable, Hashable { let unassigned: Int; let assigned: Int; let inTransit: Int; let delivered: Int }
    let summary: Summary
}

private struct KanbanColumn: Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String
    let statuses: [String]
    let nextStatus: String?
}

private let kanbanColumns: [KanbanColumn] = [
    .init(id: "posted",   label: "POSTED",        icon: "tray",                    statuses: ["posted","pending","draft"], nextStatus: "bidding"),
    .init(id: "bidding",  label: "BIDDING",       icon: "hand.raised",             statuses: ["bidding"],                  nextStatus: "assigned"),
    .init(id: "assigned", label: "ASSIGNED",      icon: "person.fill.checkmark",   statuses: ["assigned"],                 nextStatus: "en_route_pickup"),
    .init(id: "enroute",  label: "EN ROUTE PU",   icon: "arrow.right",             statuses: ["en_route_pickup"],          nextStatus: "at_pickup"),
    .init(id: "atpickup", label: "AT PICKUP",     icon: "mappin.circle",           statuses: ["at_pickup","pickup_checkin"], nextStatus: "loading"),
    .init(id: "loading",  label: "LOADING",       icon: "shippingbox.and.arrow.backward", statuses: ["loading"],            nextStatus: "in_transit"),
    .init(id: "transit",  label: "IN TRANSIT",    icon: "truck.box",               statuses: ["in_transit"],               nextStatus: "at_delivery"),
    .init(id: "atdel",    label: "AT DELIVERY",   icon: "mappin.and.ellipse",      statuses: ["at_delivery","delivery_checkin"], nextStatus: "unloading"),
    .init(id: "unload",   label: "UNLOADING",     icon: "shippingbox",             statuses: ["unloading"],                nextStatus: "delivered"),
    .init(id: "done",     label: "DELIVERED",     icon: "checkmark.seal.fill",     statuses: ["delivered","unloaded"],     nextStatus: nil),
]

private struct KanbanBody: View {
    @Environment(\.palette) private var palette
    @State private var byColumn: [String: [KanbanLoad]] = [:]
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var totals: UnifiedLoadsResponse.Summary? = nil
    @State private var totalAll: Int = 0
    @State private var selected: String = "posted"
    @State private var sheetLoad: KanbanLoad? = nil
    @State private var advancing: Int? = nil
    @State private var actionError: String? = nil
    @State private var lastAdvance: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 6)
            scrubber.padding(.bottom, 6)
            if loading { LifecycleCard { Text("Loading lifecycle…").font(EType.caption).foregroundStyle(palette.textSecondary) }.padding(.horizontal, 14) }
            else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }.padding(.horizontal, 14) }
            else { columnPager }
            if let m = lastAdvance {
                LifecycleCard(accentGradient: true) { Text(m).font(EType.caption).foregroundStyle(palette.textPrimary) }.padding(.horizontal, 14).padding(.top, 6)
            }
            if let e = actionError {
                LifecycleCard(accentDanger: true) { Text(e).font(EType.caption).foregroundStyle(Brand.danger) }.padding(.horizontal, 14).padding(.top, 6)
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $sheetLoad) { l in cardSheet(l) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.split.3x1.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · KANBAN").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                if let s = totals {
                    Text("\(totalAll) LOADS").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(palette.surface).clipShape(Capsule())
                    _ = s
                }
            }
            Text("Lifecycle board").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var scrubber: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(kanbanColumns) { col in
                    Button { withAnimation(.easeOut(duration: 0.18)) { selected = col.id } } label: {
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: col.icon).font(.system(size: 9, weight: .heavy))
                                Text(col.label).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            }
                            Text("\(byColumn[col.id]?.count ?? 0)").font(.system(size: 13, weight: .heavy)).monospacedDigit()
                        }
                        .foregroundStyle(selected == col.id ? .white : palette.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(selected == col.id ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.surface))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private var columnPager: some View {
        TabView(selection: $selected) {
            ForEach(kanbanColumns) { col in
                column(col).tag(col.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func column(_ col: KanbanColumn) -> some View {
        let cards = byColumn[col.id] ?? []
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text(col.label).font(.system(size: 13, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textPrimary)
                    Text("\(cards.count)").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                    Spacer(minLength: 0)
                    if let next = col.nextStatus { Text("→ \(next.replacingOccurrences(of: "_", with: " ").uppercased())").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary) }
                }
                if cards.isEmpty {
                    EusoEmptyState(systemImage: col.icon, title: "Column empty", subtitle: "No loads in this stage right now.")
                } else {
                    ForEach(cards) { l in
                        Button { sheetLoad = l } label: { cardView(l, col: col) }.buttonStyle(.plain)
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 6)
        }
    }

    private func cardView(_ l: KanbanLoad, col: KanbanColumn) -> some View {
        LifecycleCard(accentGradient: col.id == "transit", accentDanger: false) {
            HStack {
                LifecycleSection(label: l.loadNumber.uppercased(), icon: hazmatIcon(l))
                Spacer(minLength: 0)
                if let h = l.hazmatClass, !h.isEmpty {
                    Text("HAZ \(h)").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Brand.danger).clipShape(Capsule())
                }
            }
            LifecycleRow(label: "Driver",    value: dashIfEmpty(l.driverName))
            LifecycleRow(label: "Commodity", value: dashIfEmpty(l.commodityName ?? l.cargoType))
            LifecycleRow(label: "Rate",      value: usd(l.rate))
            LifecycleRow(label: "Pickup",    value: humanISO(l.pickupDate))
            LifecycleRow(label: "Deliver",   value: humanISO(l.deliveryDate))
        }
    }

    private func cardSheet(_ l: KanbanLoad) -> some View {
        let col = currentColumn(for: l.status) ?? kanbanColumns[0]
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text(l.loadNumber).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
                LifecycleCard {
                    LifecycleSection(label: "STAGE", icon: col.icon)
                    LifecycleRow(label: "Now",    value: l.status.uppercased())
                    LifecycleRow(label: "Next",   value: (col.nextStatus ?? "—").replacingOccurrences(of: "_", with: " ").uppercased())
                    LifecycleRow(label: "Driver", value: dashIfEmpty(l.driverName))
                    LifecycleRow(label: "Rate",   value: usd(l.rate))
                    LifecycleRow(label: "Distance", value: l.distance.map { String(format: "%.0f mi", $0) } ?? "—")
                    LifecycleRow(label: "Weight", value: l.weight.map { String(format: "%.0f lb", $0) } ?? "—")
                    LifecycleRow(label: "Commodity", value: dashIfEmpty(l.commodityName ?? l.cargoType))
                    if let h = l.hazmatClass, !h.isEmpty { LifecycleRow(label: "Hazmat", value: h) }
                }
                if let next = col.nextStatus {
                    Button { Task { await advance(load: l, to: next) } } label: {
                        HStack(spacing: 6) {
                            if advancing == l.id { ProgressView().tint(.white) }
                            Image(systemName: "arrow.right.circle.fill").foregroundStyle(.white)
                            Text(advancing == l.id ? "Advancing…" : "Advance to \(next.replacingOccurrences(of: "_", with: " ").uppercased())")
                                .font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }.buttonStyle(.plain).disabled(advancing != nil)
                }
                Spacer()
            }
            .padding(14)
        }.background(palette.background)
    }

    private func currentColumn(for status: String) -> KanbanColumn? {
        kanbanColumns.first { $0.statuses.contains(status) }
    }

    private func hazmatIcon(_ l: KanbanLoad) -> String {
        if let h = l.hazmatClass, !h.isEmpty { return "exclamationmark.triangle.fill" }
        let t = (l.cargoType ?? "").lowercased()
        if t.contains("reefer") || t.contains("refrig") { return "thermometer.snowflake" }
        if t.contains("flat") { return "rectangle.compress.vertical" }
        if t.contains("tank") { return "drop.fill" }
        if t.contains("rail") { return "tram.fill" }
        if t.contains("vessel") || t.contains("container") { return "ferry.fill" }
        return "shippingbox.fill"
    }

    private func bucket(for status: String) -> String? {
        currentColumn(for: status)?.id
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let mode: String; let limit: Int; let offset: Int }
        do {
            let r: UnifiedLoadsResponse = try await EusoTripAPI.shared.query("dispatch.unifiedLoads", input: In(mode: "company", limit: 500, offset: 0))
            var grouped: [String: [KanbanLoad]] = [:]
            for l in r.loads {
                let key = bucket(for: l.status) ?? "posted"
                grouped[key, default: []].append(l)
            }
            byColumn = grouped
            totals = r.summary
            totalAll = r.total
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func advance(load: KanbanLoad, to next: String) async {
        advancing = load.id; actionError = nil
        struct In: Encodable { let loadId: String; let status: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation("dispatch.updateLoadStatus", input: In(loadId: String(load.id), status: next))
            lastAdvance = "\(load.loadNumber) → \(next.replacingOccurrences(of: "_", with: " ").uppercased())"
            sheetLoad = nil
            await self.load()
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        advancing = nil
    }
}

#Preview("708 · Kanban · Night") { DispatchKanbanBoardScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("708 · Kanban · Afternoon") { DispatchKanbanBoardScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
