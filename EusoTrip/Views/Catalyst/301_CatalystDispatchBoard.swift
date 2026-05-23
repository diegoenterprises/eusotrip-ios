//
//  301_CatalystDispatchBoard.swift
//  EusoTrip — Catalyst · Dispatch Board (brick 301).
//
//  Pixel-match to `03 Catalyst/Dark-SVG/301 Dispatch Board.svg`.
//  Owner-op single-truck dispatch lens — "1 truck · today" view
//  of pending tenders + assigned + in-transit + delivered.
//
//  Reshaped 2026-05-23 from a chip-filter linear list into a true
//  4-column Kanban with paged columns + drag-to-advance, matching
//  the 708_DispatchKanbanBoard pattern. Drop fires the canonical
//  `dispatch.updateLoadStatus` mutation.
//
//  Wire bindings (all real, no stubs):
//    loads.list(status: "pending")
//    loads.list(status: "assigned")
//    loads.list(status: "in_transit")
//    loads.list(status: "delivered")
//    dispatch.updateLoadStatus (drag-to-advance)
//

import SwiftUI

private struct DispatchLoad: Decodable, Hashable, Identifiable {
    let id: String
    let loadNumber: String?
    let status: String?
    let cargoType: String?
    let hazmatClass: String?
    let pickupCity: String?
    let pickupState: String?
    let destCity: String?
    let destState: String?
    let pickupDate: String?
    let distance: Double?
    let rate: String?
    let ratePerMile: String?
    let trailerType: String?
    let assignedDriverName: String?
    let expiresAt: String?
}

private struct DispatchLoadsEnvelope: Decodable {
    let loads: [DispatchLoad]?
    let items: [DispatchLoad]?
    var rows: [DispatchLoad] { loads ?? items ?? [] }
}

private struct CatalystKanbanColumn: Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String
    let status: String
    let nextStatus: String?
}

private let catalystKanbanColumns: [CatalystKanbanColumn] = [
    .init(id: "pending",   label: "PENDING",    icon: "tray",                  status: "pending",     nextStatus: "assigned"),
    .init(id: "assigned",  label: "ASSIGNED",   icon: "person.fill.checkmark", status: "assigned",    nextStatus: "in_transit"),
    .init(id: "transit",   label: "IN TRANSIT", icon: "truck.box",             status: "in_transit",  nextStatus: "delivered"),
    .init(id: "delivered", label: "DELIVERED",  icon: "checkmark.seal.fill",   status: "delivered",   nextStatus: nil),
]

struct CatalystDispatchBoardScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { DispatchBoardBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",         isCurrent: false),
                          NavSlot(label: "Dispatch", systemImage: "rectangle.split.3x1.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct DispatchBoardBody: View {
    @Environment(\.palette) private var palette

    @State private var byColumn: [String: [DispatchLoad]] = [:]
    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    @State private var selected: String = "pending"
    @State private var dragHoverColumn: String? = nil
    @State private var advancing: String? = nil
    @State private var actionError: String? = nil
    @State private var lastAdvance: String? = nil

    private var totalAll: Int { byColumn.values.reduce(0) { $0 + $1.count } }
    private var expiringSoon: Int {
        (byColumn["pending"] ?? []).filter { expiresWithin($0.expiresAt, hours: 6) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 6)
            scrubber.padding(.bottom, 6)
            if loading && byColumn.isEmpty {
                LifecycleCard {
                    Text("Loading dispatch board…")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }.padding(.horizontal, 14)
                Spacer(minLength: 0)
            } else if let err = loadError {
                LifecycleCard(accentDanger: true) {
                    Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                }.padding(.horizontal, 14)
                Spacer(minLength: 0)
            } else {
                columnPager
            }
            if let m = lastAdvance {
                LifecycleCard(accentGradient: true) {
                    Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
                }.padding(.horizontal, 14).padding(.top, 6)
            }
            if let e = actionError {
                LifecycleCard(accentDanger: true) {
                    Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                }.padding(.horizontal, 14).padding(.top, 6)
            }
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · DISPATCH BOARD · LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
                Text("\(totalAll) LOADS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(palette.bgCard).clipShape(Capsule())
            }
            Text("Dispatch board")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("1 truck · today · drag to advance stage")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
            if expiringSoon > 0 {
                Text("\(expiringSoon) TENDER\(expiringSoon == 1 ? "" : "S") EXPIRING < 6H")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.danger)
            }
        }
    }

    private var scrubber: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(catalystKanbanColumns) { col in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { selected = col.id }
                    } label: {
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: col.icon).font(.system(size: 9, weight: .heavy))
                                Text(col.label).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            }
                            Text("\(byColumn[col.id]?.count ?? 0)")
                                .font(.system(size: 13, weight: .heavy)).monospacedDigit()
                        }
                        .foregroundStyle(selected == col.id ? .white : palette.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(selected == col.id ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private var columnPager: some View {
        TabView(selection: $selected) {
            ForEach(catalystKanbanColumns) { col in
                column(col).tag(col.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func column(_ col: CatalystKanbanColumn) -> some View {
        let cards = byColumn[col.id] ?? []
        let isHover = dragHoverColumn == col.id
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text(col.label)
                        .font(.system(size: 13, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textPrimary)
                    Text("\(cards.count)")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                    Spacer(minLength: 0)
                    if let next = col.nextStatus {
                        Text("→ \(next.replacingOccurrences(of: "_", with: " ").uppercased())")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                if cards.isEmpty {
                    EusoEmptyState(
                        systemImage: col.icon,
                        title: "Column empty",
                        subtitle: "No loads in this stage right now."
                    )
                } else {
                    ForEach(cards) { l in
                        cardView(l, col: col)
                            .draggable(l.id) {
                                cardView(l, col: col)
                                    .frame(maxWidth: 320)
                                    .opacity(0.92)
                                    .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                            }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    isHover ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Color.clear),
                    lineWidth: isHover ? 2 : 0
                )
                .padding(.horizontal, 8)
                .animation(.easeOut(duration: 0.12), value: isHover)
        )
        .dropDestination(for: String.self) { droppedIds, _ in
            guard let droppedId = droppedIds.first else { return false }
            guard let load = byColumn.values.flatMap({ $0 }).first(where: { $0.id == droppedId }) else { return false }
            if (load.status ?? "") == col.status { return false }
            Task { await advance(load: load, to: col.status) }
            return true
        } isTargeted: { hovering in
            dragHoverColumn = hovering ? col.id : (dragHoverColumn == col.id ? nil : dragHoverColumn)
        }
    }

    private func cardView(_ l: DispatchLoad, col: CatalystKanbanColumn) -> some View {
        let isExpiringSoon = col.id == "pending" && expiresWithin(l.expiresAt, hours: 6)
        return LifecycleCard(accentDanger: isExpiringSoon, accentGradient: col.id == "transit") {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(col.label)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(stageTint(col).opacity(0.18)))
                        .foregroundStyle(stageTint(col))
                    if let h = l.hazmatClass, !h.isEmpty {
                        Text("HAZ \(h)")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                            .foregroundStyle(Color.orange)
                    }
                    Spacer()
                    if isExpiringSoon, let exp = l.expiresAt, let hours = hoursUntil(exp) {
                        Text("⏱ \(hours)h LEFT")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.red.opacity(0.18)))
                            .foregroundStyle(Color.red)
                    }
                }
                Text(l.loadNumber ?? "LD-\(l.id)")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("\(l.pickupCity ?? "—"), \(l.pickupState ?? "—") → \(l.destCity ?? "—"), \(l.destState ?? "—")")
                    .font(EType.body.weight(.bold))
                    .foregroundStyle(palette.textPrimary)
                Text("Pickup \(humanDate(l.pickupDate)) · \(Int(l.distance ?? 0)) mi")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                HStack {
                    Text("$\(l.rate ?? "—")")
                        .font(.title3.weight(.heavy).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                    if let rpm = l.ratePerMile {
                        Text("$\(rpm)/mi")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                    if let tt = l.trailerType {
                        Text(tt.uppercased())
                            .font(.caption2.weight(.bold)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                if let d = l.assignedDriverName, !d.isEmpty {
                    HStack(spacing: 6) {
                        Text("DRIVER")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(palette.bgCardSoft))
                            .foregroundStyle(palette.textTertiary)
                        Text(d).font(.caption).foregroundStyle(palette.textSecondary)
                    }
                    .padding(.top, 4)
                }
                if advancing == l.id {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.6)
                        Text("Advancing…")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textSecondary)
                    }.padding(.top, 4)
                }
            }
        }
    }

    private func stageTint(_ col: CatalystKanbanColumn) -> Color {
        switch col.id {
        case "pending":   return .orange
        case "assigned":  return .blue
        case "transit":   return .green
        case "delivered": return .gray
        default:          return .gray
        }
    }

    private func humanDate(_ iso: String?) -> String {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return "—" }
        let f = DateFormatter(); f.dateFormat = "MMM d HH:mm"
        return f.string(from: date)
    }

    private func expiresWithin(_ iso: String?, hours: Int) -> Bool {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return false }
        return date.timeIntervalSinceNow < Double(hours) * 3600 && date.timeIntervalSinceNow > 0
    }

    private func hoursUntil(_ iso: String) -> Int? {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        return max(0, Int(date.timeIntervalSinceNow / 3600))
    }

    private func loadAll() async {
        loading = true; loadError = nil
        async let p:  [DispatchLoad] = fetch(status: "pending")
        async let a:  [DispatchLoad] = fetch(status: "assigned")
        async let t:  [DispatchLoad] = fetch(status: "in_transit")
        async let d:  [DispatchLoad] = fetch(status: "delivered")
        let (pending, assigned, transit, delivered) = await (p, a, t, d)
        byColumn = [
            "pending":   pending,
            "assigned":  assigned,
            "transit":   transit,
            "delivered": delivered,
        ]
        loading = false
    }

    private func fetch(status: String) async -> [DispatchLoad] {
        struct In: Encodable { let status: String; let limit: Int }
        do {
            let r: DispatchLoadsEnvelope = try await EusoTripAPI.shared.query(
                "loads.list", input: In(status: status, limit: 50)
            )
            return r.rows
        } catch {
            await MainActor.run {
                self.loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
            return []
        }
    }

    private func advance(load: DispatchLoad, to next: String) async {
        await MainActor.run { advancing = load.id; actionError = nil }
        struct In: Encodable { let loadId: String; let status: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "dispatch.updateLoadStatus",
                input: In(loadId: load.id, status: next)
            )
            await MainActor.run {
                lastAdvance = "\(load.loadNumber ?? "LD-\(load.id)") → \(next.replacingOccurrences(of: "_", with: " ").uppercased())"
            }
            await loadAll()
        } catch {
            await MainActor.run {
                actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
        }
        await MainActor.run { advancing = nil }
    }
}

#Preview("301 Dispatch · Dark")  { CatalystDispatchBoardScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("301 Dispatch · Light") { CatalystDispatchBoardScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
