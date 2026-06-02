//
//  401_DispatcherKanban.swift
//  EusoTrip — Dispatcher · Board · Kanban (iOS-native vertical swim-lane refit).
//
//  Verbatim reconstruction of wireframe "401 Dispatcher Kanban · Dark"
//  (canvas 440×956). Faithful to layout, copy, element order, colors and
//  spacing proportions; only absolute sizes are tuned for responsive fit.
//
//  iOS-NATIVE VERTICAL SWIM-LANE REFIT (mirror Light · per SKILL §401 +
//  RESUME POINT 2026-05-22): the web 5-column horizontal kanban is
//  re-expressed as vertically stacked stage lanes (TENDER · ASSIGNED ·
//  PICKUP · IN TRANSIT · DELIVERED); vertical scroll between stages, each
//  lane a horizontal card shelf. Tap a card to shift its stage; a
//  confirmation Sheet confirms the advance (LD…7C3A · TENDER → ASSIGNED).
//
//  Persona §196 (canonical, mirrors Light): Renée Marquette · Aurora
//  Freight Lines LLC. MATRIX-50 IDs verbatim, Eusorone shipper-of-record.
//
//  RBAC: dispatcherProcedure. transportMode: TRUCK. country: US.
//
//  Wiring (honest):
//    • dispatch.unifiedLoads     — EXISTS (query)    — board data, grouped
//                                                       into the 5 stage lanes
//    • dispatch.updateLoadStatus — EXISTS (mutation) — shift a load's stage
//                                                       from the confirm sheet
//  Both endpoints are the same ones the live lifecycle board (708) ships
//  against. Real do/catch + @State loading / error / empty states; no mock
//  data. The lane chrome (lane → next-stage map, card copy/colors) mirrors
//  the wireframe verbatim while the load payload is server-driven.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//

import SwiftUI

struct DispatcherKanbanScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette = Theme.dark) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) { DispatcherKanbanBody() } nav: {
            // Nav: HOME · BOARD(active) · [orb] · COMMS · ME.
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",                      isCurrent: false),
                          NavSlot(label: "Board", systemImage: "rectangle.split.3x1.fill",   isCurrent: true)],
                trailing: [NavSlot(label: "Comms", systemImage: "bubble.left.and.bubble.right.fill", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",                    isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Wire model

/// Shared with 708's lifecycle board — `dispatch.unifiedLoads` payload.
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
    let originCity: String?
    let destinationCity: String?
    let driverName: String?
    let temperatureF: Double?
    let etaMinutes: Int?
}

private struct UnifiedLoadsResponse: Decodable, Hashable {
    let loads: [KanbanLoad]
    let total: Int
    struct Summary: Decodable, Hashable { let unassigned: Int; let assigned: Int; let inTransit: Int; let delivered: Int }
    let summary: Summary
}

// MARK: - Lane model (verbatim from wireframe — TENDER · ASSIGNED · PICKUP · IN TRANSIT · DELIVERED)

private enum LaneAccent {
    case hazmat, info, brand, success

    func color(_ p: Theme.Palette) -> AnyShapeStyle {
        switch self {
        case .hazmat:  return AnyShapeStyle(Brand.hazmat)        // #FFB100
        case .info:    return AnyShapeStyle(Color(hex: 0x54A8E8))
        case .brand:   return AnyShapeStyle(LinearGradient.primary)
        case .success: return AnyShapeStyle(Brand.success)       // #00C48C
        }
    }
    /// Flat representative color for the card edge-rail + chip tint.
    func flat(_ p: Theme.Palette) -> Color {
        switch self {
        case .hazmat:  return Brand.hazmat
        case .info:    return Color(hex: 0x54A8E8)
        case .brand:   return Brand.blue
        case .success: return Brand.success
        }
    }
}

private struct KanbanLane: Identifiable, Hashable {
    let id: String
    let label: String          // "TENDER"
    let accent: LaneAccent
    let statuses: [String]     // server status values that map into this lane
    let nextStatus: String?    // the stage a tap shifts toward
    let nextLabel: String?     // "ASSIGNED"

    static func == (l: KanbanLane, r: KanbanLane) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// The 5 lanes, in wireframe order. The status→lane mapping mirrors the
/// canonical lifecycle FSM the 708 board groups against.
private let kanbanLanes: [KanbanLane] = [
    .init(id: "tender",   label: "TENDER",     accent: .hazmat,  statuses: ["posted", "pending", "draft", "bidding"], nextStatus: "assigned",   nextLabel: "ASSIGNED"),
    .init(id: "assigned", label: "ASSIGNED",   accent: .info,    statuses: ["assigned"],                              nextStatus: "en_route_pickup", nextLabel: "PICKUP"),
    .init(id: "pickup",   label: "PICKUP",     accent: .brand,   statuses: ["en_route_pickup", "at_pickup", "pickup_checkin", "loading"], nextStatus: "in_transit", nextLabel: "IN TRANSIT"),
    .init(id: "transit",  label: "IN TRANSIT", accent: .info,    statuses: ["in_transit", "at_delivery", "delivery_checkin", "unloading"], nextStatus: "delivered", nextLabel: "DELIVERED"),
    .init(id: "delivered",label: "DELIVERED",  accent: .success, statuses: ["delivered", "unloaded"],                nextStatus: nil,          nextLabel: nil),
]

// MARK: - Body

private struct DispatcherKanbanBody: View {
    @Environment(\.palette) private var palette

    @State private var byLane: [String: [KanbanLoad]] = [:]
    @State private var totalAll: Int = 0

    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var sheetLoad: KanbanLoad? = nil      // tap-and-shift confirm
    @State private var shifting: Int? = nil
    @State private var actionError: String? = nil

    // Filter chips — verbatim from wireframe (All · Hazmat · Reefer · Dry).
    @State private var filter: BoardFilter = .all

    private enum BoardFilter: String { case all, hazmat, reefer, dry }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow
                    .padding(.horizontal, 20).padding(.top, 12)
                title
                    .padding(.horizontal, 20).padding(.top, 18)
                filterChips
                    .padding(.horizontal, 20).padding(.top, 14)
                IridescentHairline()
                    .padding(.top, 14)

                if loading {
                    LifecycleCard {
                        Text("Loading board…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    .padding(.horizontal, 20).padding(.top, 14)
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    .padding(.horizontal, 20).padding(.top, 14)
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(kanbanLanes) { lane in
                            laneView(lane)
                        }
                    }
                    .padding(.top, 14)
                }

                if let e = actionError {
                    LifecycleCard(accentDanger: true) {
                        Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    .padding(.horizontal, 20).padding(.top, 10)
                }

                Color.clear.frame(height: 8)
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $sheetLoad) { l in confirmSheet(l) }
    }

    // MARK: TopBar eyebrow  ("✦ DISPATCHER · BOARD · KANBAN"  ·  "22 LOADS · 5 STAGES")

    private var eyebrow: some View {
        HStack {
            Text("✦ DISPATCHER · BOARD · KANBAN")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 0)
            Text("\(totalAll) LOADS · 5 STAGES")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Board")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Aurora Freight · tap a load to shift its stage")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Filter chips  (All · 22 / Hazmat · 5 / Reefer · 6 / Dry · 8)

    private var filterChips: some View {
        HStack(spacing: 8) {
            chip(.all,    "All · \(totalAll)",                 color: nil)
            chip(.hazmat, "Hazmat · \(hazmatCount)",           color: Brand.hazmat)
            chip(.reefer, "Reefer · \(reeferCount)",           color: Color(hex: 0x54A8E8))
            chip(.dry,    "Dry · \(dryCount)",                 color: palette.textSecondary)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func chip(_ f: BoardFilter, _ label: String, color: Color?) -> some View {
        let active = (filter == f)
        Button {
            withAnimation(.easeOut(duration: 0.15)) { filter = (filter == f && f != .all) ? .all : f }
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(active ? .white : (color ?? palette.textSecondary))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .frame(minHeight: 26)
                .background(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCard))
                .clipShape(Capsule())
                .overlay(active ? nil : Capsule().strokeBorder(palette.borderFaint))
        }
        .buttonStyle(.plain)
    }

    private var hazmatCount: Int { allLoads.filter { ($0.hazmatClass ?? "").isEmpty == false }.count }
    private var reeferCount: Int { allLoads.filter { ($0.cargoType ?? "").lowercased().contains("reefer") || ($0.cargoType ?? "").lowercased().contains("refrig") }.count }
    private var dryCount: Int    { allLoads.filter { ($0.cargoType ?? "").lowercased().contains("dry") }.count }
    private var allLoads: [KanbanLoad] { byLane.values.flatMap { $0 } }

    // MARK: Stage lane (header row + horizontal card shelf)

    private func laneView(_ lane: KanbanLane) -> some View {
        let cards = filtered(byLane[lane.id] ?? [])
        return VStack(alignment: .leading, spacing: 10) {
            // Lane header: "TENDER · 8"  ………………  "see all ›"
            HStack {
                Text("\(lane.label) · \(cards.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(lane.accent.color(palette))
                Spacer(minLength: 0)
                Text("see all ›")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            Rectangle().fill(palette.borderFaint).frame(height: 1)

            // Horizontal card shelf.
            if cards.isEmpty {
                EusoEmptyState(systemImage: "tray",
                               title: "No loads",
                               subtitle: "Nothing in \(lane.label.capitalized) right now.")
                    .padding(.vertical, 4)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(cards) { l in
                            Button { sheetLoad = l } label: { cardView(l, lane: lane) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 20)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func filtered(_ cards: [KanbanLoad]) -> [KanbanLoad] {
        switch filter {
        case .all:    return cards
        case .hazmat: return cards.filter { ($0.hazmatClass ?? "").isEmpty == false }
        case .reefer: return cards.filter { ($0.cargoType ?? "").lowercased().contains("reefer") || ($0.cargoType ?? "").lowercased().contains("refrig") }
        case .dry:    return cards.filter { ($0.cargoType ?? "").lowercased().contains("dry") }
        }
    }

    // MARK: Card  (168×70 in wireframe — colored edge rail, ID, status chip, lane, meta, rate, driver disc)

    private func cardView(_ l: KanbanLoad, lane: KanbanLane) -> some View {
        let selected = (sheetLoad?.id == l.id)
        return ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                // Left colored edge rail (3pt in wireframe).
                Capsule()
                    .fill(lane.accent.color(palette))
                    .frame(width: 3)
                    .padding(.vertical, 10)
                    .padding(.leading, 10)

                VStack(alignment: .leading, spacing: 0) {
                    // Row 1 — load id + status chip.
                    HStack(alignment: .top) {
                        Text(shortId(l.loadNumber))
                            .font(EType.mono(.micro)).tracking(0.3)
                            .foregroundStyle(palette.textTertiary)
                        Spacer(minLength: 0)
                        statusChip(l, lane: lane)
                    }
                    Spacer(minLength: 0)
                    // Row 2 — lane (origin → destination).
                    Text(laneText(l))
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    // Row 3 — equipment / commodity meta.
                    Text(metaText(l))
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    // Row 4 — rate + driver disc.
                    HStack(alignment: .bottom) {
                        Text(usd(l.rate))
                            .font(.system(size: 13, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                        Spacer(minLength: 0)
                        driverDisc(l.driverName)
                    }
                }
                .padding(.vertical, 10)
                .padding(.leading, 9)
                .padding(.trailing, 10)
            }
            .frame(width: 168, height: 70, alignment: .topLeading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        selected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint),
                        lineWidth: selected ? 1.5 : 1
                    )
            )
        }
    }

    private func statusChip(_ l: KanbanLoad, lane: KanbanLane) -> some View {
        let accent = lane.accent.flat(palette)
        return Text(chipText(l, lane: lane))
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(accent)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(Capsule().fill(accent.opacity(0.20)))
    }

    /// Status-chip copy mirrors the wireframe's per-lane idiom: TENDER shows
    /// a countdown, ASSIGNED a pickup-window, PICKUP "at dock", IN TRANSIT
    /// an ETA, DELIVERED "POD ✓".
    private func chipText(_ l: KanbanLoad, lane: KanbanLane) -> String {
        switch lane.id {
        case "tender":
            if let m = l.etaMinutes { return expiry(m) }
            return "open"
        case "assigned":
            return "PU soon"
        case "pickup":
            return "at dock"
        case "transit":
            if let m = l.etaMinutes { return "ETA \(clock(m))" }
            return "rolling"
        case "delivered":
            return "POD ✓"
        default:
            return l.status.uppercased()
        }
    }

    private func driverDisc(_ name: String?) -> some View {
        ZStack {
            Circle().fill(LinearGradient.diagonal)
            Text(initials(name))
                .font(.system(size: 7, weight: .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: 18, height: 18)
    }

    // MARK: Confirm Sheet  (SHIFT STAGE · CONFIRM)

    private func confirmSheet(_ l: KanbanLoad) -> some View {
        let lane = currentLane(for: l.status) ?? kanbanLanes[0]
        return VStack(alignment: .leading, spacing: 0) {
            // Grabber.
            Capsule().fill(palette.borderSoft)
                .frame(width: 28, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10).padding(.bottom, 16)

            Text("SHIFT STAGE · CONFIRM")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)

            Text("\(shortId(l.loadNumber)) · \(laneText(l))")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 10)

            // Stage transition row:  [TENDER] → [ASSIGNED]  · assign D. Karch
            HStack(spacing: 8) {
                stagePill(lane.label, color: lane.accent.flat(palette))
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                if let nextLabel = lane.nextLabel,
                   let nextLane = kanbanLanes.first(where: { $0.label == nextLabel }) {
                    stagePill(nextLabel, color: nextLane.accent.flat(palette))
                }
                if let d = l.driverName {
                    Text("· assign \(d)")
                        .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 14)

            // Action row:  [Confirm shift →]   [Cancel]
            HStack(spacing: 12) {
                Button {
                    if let next = lane.nextStatus { Task { await shift(l, to: next) } }
                } label: {
                    HStack(spacing: 6) {
                        if shifting == l.id { ProgressView().tint(.white).controlSize(.small) }
                        Text(lane.nextStatus == nil ? "Delivered" : "Confirm shift →")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(shifting != nil || lane.nextStatus == nil)
                .opacity(lane.nextStatus == nil ? 0.6 : 1)

                Button { sheetLoad = nil } label: {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
                        .frame(width: 110, height: 36)
                        .background(palette.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 18)

            if let e = actionError {
                Text(e).font(EType.caption).foregroundStyle(Brand.danger).padding(.top, 10)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .presentationDetents([.height(220)])
        .presentationDragIndicator(.hidden)
    }

    private func stagePill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.20)))
    }

    // MARK: - Load + shift pipeline

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let mode: String; let limit: Int; let offset: Int }
        do {
            let r: UnifiedLoadsResponse = try await EusoTripAPI.shared.query(
                "dispatch.unifiedLoads", input: In(mode: "company", limit: 500, offset: 0))
            var grouped: [String: [KanbanLoad]] = [:]
            for l in r.loads {
                let key = laneId(for: l.status) ?? "tender"
                grouped[key, default: []].append(l)
            }
            byLane = grouped
            totalAll = r.total
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func shift(_ l: KanbanLoad, to next: String) async {
        shifting = l.id; actionError = nil
        struct In: Encodable { let loadId: String; let status: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "dispatch.updateLoadStatus", input: In(loadId: String(l.id), status: next))
            sheetLoad = nil
            await load()
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        shifting = nil
    }

    // MARK: - Mapping + formatting helpers

    private func laneId(for status: String) -> String? {
        kanbanLanes.first { $0.statuses.contains(status) }?.id
    }
    private func currentLane(for status: String) -> KanbanLane? {
        kanbanLanes.first { $0.statuses.contains(status) }
    }

    private func laneText(_ l: KanbanLoad) -> String {
        let o = (l.originCity ?? "—")
        let d = (l.destinationCity ?? "—")
        return "\(o) → \(d)"
    }

    /// Equipment / commodity line: "Reefer 38°F · 28k", "NH₃ · escort",
    /// "53' Dry · 38k", "Gasoline UN1203".
    private func metaText(_ l: KanbanLoad) -> String {
        var parts: [String] = []
        let cargo = (l.cargoType ?? "").lowercased()
        if cargo.contains("reefer") || cargo.contains("refrig") {
            if let t = l.temperatureF { parts.append("Reefer \(Int(t))°F") } else { parts.append("Reefer") }
        } else if let ct = l.cargoType, !ct.isEmpty {
            parts.append(ct)
        } else if let cm = l.commodityName, !cm.isEmpty {
            parts.append(cm)
        }
        if let un = l.hazmatClass, !un.isEmpty { parts.append(un) }
        if let w = l.weight, w > 0 { parts.append("\(Int(w / 1000))k") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func shortId(_ ln: String) -> String { "LD…\(String(ln.uppercased().suffix(4)))" }

    private func usd(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "$\(Int(v).formatted())"
    }

    private func initials(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "—" }
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }

    private func expiry(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// Clock from "minutes from now" for the IN TRANSIT ETA chip.
    private func clock(_ minutesFromNow: Int) -> String {
        let target = Date().addingTimeInterval(TimeInterval(minutesFromNow * 60))
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: target)
    }

}

#Preview("401 · Dispatcher kanban · Night") {
    DispatcherKanbanScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("401 · Dispatcher kanban · Afternoon") {
    DispatcherKanbanScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
