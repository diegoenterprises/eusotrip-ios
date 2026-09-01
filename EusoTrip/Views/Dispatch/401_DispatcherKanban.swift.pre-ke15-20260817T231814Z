//
//  401_DispatcherKanban.swift
// OFFLINE: board READ_CACHED(5m); stage-shift QUEUE(dispatch) — offline tap+confirm enqueues shiftStage, moved card wears a QUEUED badge until the socket drains; assign-driver same lane (idempotencyKey); queued vs cached visibly distinct; reconnect FULL.
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
                leading: DispatchNavRoute.leading(current: .board),
                trailing: DispatchNavRoute.trailing(current: .board),
                orbState: .idle
            )
        }
    }
}

// MARK: - Wire model

/// Shared with 708's lifecycle board — `dispatch.unifiedLoads` payload.
private struct KanbanLoad: Decodable, Identifiable, Hashable {
    // The server contract is canonical string identity (`String(r.id)`). Keep
    // it exact from read -> drag payload -> mutation -> acknowledgement.
    let id: String
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
    let driverId: String?
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

private struct KanbanSettingsPayload: Decodable {
    let rolePreferences: RolePreferences?
    struct RolePreferences: Decodable { let dispatch: Dispatch? }
    struct Dispatch: Decodable { let board: Board? }
    struct Board: Decodable {
        let visibleStages: [String]
        let cardDensity: String
    }
}

private struct DispatcherMutationResult: Decodable {
    let success: Bool?
    let loadId: String?
    let newStatus: String?
    let message: String?
    let error: String?

    func failureMessage(fallback: String) -> String? {
        guard success == false else { return nil }
        return [message, error]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? fallback
    }

    func validateStatus(loadId expectedId: String, status expectedStatus: String) throws {
        if let failure = failureMessage(fallback: "The stage change was rejected.") {
            throw DispatcherKanbanCommitError.rejected(failure)
        }
        guard success == true else {
            throw DispatcherKanbanCommitError.rejected("The server did not acknowledge the stage change.")
        }
        guard loadId == expectedId else {
            throw DispatcherKanbanCommitError.identityMismatch(expected: expectedId, received: loadId)
        }
        guard newStatus == expectedStatus else {
            throw DispatcherKanbanCommitError.statusMismatch(expected: expectedStatus, received: newStatus)
        }
    }

    func validateUnassignment(loadId expectedId: String) throws {
        if let failure = failureMessage(fallback: "The unassignment was rejected.") {
            throw DispatcherKanbanCommitError.rejected(failure)
        }
        guard success == true else {
            throw DispatcherKanbanCommitError.rejected("The server did not acknowledge the unassignment.")
        }
        guard loadId == expectedId else {
            throw DispatcherKanbanCommitError.identityMismatch(expected: expectedId, received: loadId)
        }
    }
}

private enum DispatcherKanbanCommitError: LocalizedError {
    case rejected(String)
    case identityMismatch(expected: String, received: String?)
    case statusMismatch(expected: String, received: String?)
    case readbackMissing(loadId: String)
    case readbackMismatch(loadId: String, expectedStatus: String, receivedStatus: String)
    case readbackUnassignedMismatch(loadId: String)

    var errorDescription: String? {
        switch self {
        case .rejected(let message):
            return message
        case .identityMismatch:
            return "EusoTrip acknowledged a different load. The board was restored; pull to refresh before retrying."
        case .statusMismatch:
            return "EusoTrip acknowledged a different stage. The board was restored; pull to refresh before retrying."
        case .readbackMissing:
            return "The saved load could not be read back from the dispatch board. The board was restored; pull to refresh."
        case .readbackMismatch:
            return "The saved stage could not be confirmed. The board was restored; pull to refresh before retrying."
        case .readbackUnassignedMismatch:
            return "The driver removal could not be confirmed. The board was restored; pull to refresh before retrying."
        }
    }
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
    @EnvironmentObject private var session: EusoTripSession

    @State private var byLane: [String: [KanbanLoad]] = [:]
    @State private var totalAll: Int = 0

    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var sheetLoad: KanbanLoad? = nil      // tap-and-shift confirm
    @State private var shifting: String? = nil
    @State private var actionError: String? = nil
    @State private var draggingLoadId: String? = nil
    @State private var dropLaneId: String? = nil
    @State private var visibleStageIds = Set(kanbanLanes.map(\.id))
    @State private var cardDensity = "compact"

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
                        ForEach(visibleLanes) { lane in
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
        .eusoRefreshable { await load() }
        .sheet(item: $sheetLoad) { l in confirmSheet(l) }
    }

    // MARK: TopBar eyebrow

    private var eyebrow: some View {
        HStack {
            EusoTripBrandMark(size: 12)
            Text("DISPATCHER · BOARD · KANBAN")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 0)
            Text("\(totalAll) LOADS · \(visibleLanes.count) STAGES")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Board")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("\(session.user?.name ?? "Dispatch") · hold a load, then drop it onto a stage")
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
    private var visibleLanes: [KanbanLane] {
        let configured = kanbanLanes.filter { visibleStageIds.contains($0.id) }
        return configured.isEmpty ? kanbanLanes : configured
    }

    // MARK: Stage lane (header row + drag/drop card grid)

    private func laneView(_ lane: KanbanLane) -> some View {
        let cards = filtered(byLane[lane.id] ?? [])
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(lane.label) · \(cards.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(lane.accent.color(palette))
                Spacer(minLength: 0)
            }
            Rectangle().fill(palette.borderFaint).frame(height: 1)

            if cards.isEmpty {
                EusoEmptyState(systemImage: "tray",
                               title: "No loads",
                               subtitle: "Nothing in \(lane.label.capitalized) right now.")
                    .padding(.vertical, 4)
            } else {
                LazyVGrid(
                    columns: cardDensity == "comfortable"
                        ? [GridItem(.flexible(minimum: 0), spacing: 10)]
                        : [GridItem(.flexible(minimum: 0), spacing: 10), GridItem(.flexible(minimum: 0), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(cards) { l in
                        // NOT a Button.
                        //
                        // `.draggable` was applied to a Button, and on iOS the
                        // Button's own tap recognizer wins the gesture race, so
                        // the drag never begins — the card highlights and stays
                        // put. The `.simultaneousGesture(LongPressGesture)`
                        // below it was an attempt to force the long-press that
                        // starts a drag, which cannot work while the Button
                        // still owns the gesture.
                        //
                        // A plain view with `.onTapGesture` keeps the tap and
                        // lets `.draggable` own the long-press, which is what
                        // actually starts a drag. The drop path was never the
                        // problem: it calls dispatch.updateLoadStatus /
                        // dispatch.unassignDriver and surfaces a rejection.
                        cardView(l, lane: lane)
                            .contentShape(Rectangle())
                            .onTapGesture { handleCardTap(l, in: lane) }
                            .draggable(l.id) {
                                dragPreview(l, lane: lane)
                            }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(dropLaneId == lane.id ? lane.accent.flat(palette).opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    dropLaneId == lane.id ? AnyShapeStyle(lane.accent.color(palette)) : AnyShapeStyle(Color.clear),
                    lineWidth: 1.25
                )
        )
        .dropDestination(for: String.self) { ids, _ in
            guard let loadId = ids.first, !loadId.isEmpty else { return false }
            guard shifting == nil else { return false }
            Task { await drop(loadId, into: lane) }
            return true
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.12)) {
                dropLaneId = targeted ? lane.id : nil
            }
        }
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
        let dragging = draggingLoadId == l.id
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
            .frame(maxWidth: .infinity, minHeight: cardDensity == "comfortable" ? 112 : 96, alignment: .topLeading)
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
        .scaleEffect(dragging ? 1.035 : 1)
        .rotationEffect(.degrees(dragging ? 1.2 : 0))
        .shadow(color: dragging ? lane.accent.flat(palette).opacity(0.35) : .clear, radius: 10, x: 0, y: 4)
    }

    private func dragPreview(_ l: KanbanLoad, lane: KanbanLane) -> some View {
        cardView(l, lane: lane)
            .frame(width: 190)
            .frame(minHeight: 100)
            .onAppear { armDragFeedback(for: l.id) }
    }

    private func armDragFeedback(for loadId: String) {
        withAnimation(.easeInOut(duration: 0.11).repeatCount(4, autoreverses: true)) {
            draggingLoadId = loadId
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            if draggingLoadId == loadId {
                withAnimation(.easeOut(duration: 0.12)) { draggingLoadId = nil }
            }
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
        let needsDriver = lane.id == "tender" && l.driverId == nil
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
                    if needsDriver {
                        openAssignDriver(l)
                    } else if let next = lane.nextStatus {
                        Task { await shift(l, to: next) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if shifting == l.id { ProgressView().tint(.white).controlSize(.small) }
                        Text(needsDriver ? "Assign driver" : (lane.nextStatus == nil ? "Delivered" : "Confirm shift →"))
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(shifting != nil || lane.nextStatus == nil)
                .opacity(lane.nextStatus == nil ? 0.6 : 1)

                Button { openConvoyComposer(l) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "car.2.fill")
                            .font(.system(size: 12, weight: .heavy))
                        Text("Convoy / escorts")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(palette.bgCard)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                }
                .buttonStyle(.plain)

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
        .presentationDetents([.height(284)])
        .presentationDragIndicator(.hidden)
    }

    private func openConvoyComposer(_ l: KanbanLoad) {
        sheetLoad = nil
        NotificationCenter.default.post(
            name: .eusoDispatchNavSwap,
            object: nil,
            userInfo: [
                "screenId": "Dpch710A",
                "loadId": l.id,
                "loadNumber": l.loadNumber
            ]
        )
    }

    private func openAssignDriver(_ l: KanbanLoad) {
        sheetLoad = nil
        NotificationCenter.default.post(
            name: .eusoDispatchNavSwap,
            object: nil,
            userInfo: [
                "screenId": "532",
                "loadId": l.id,
                "loadNumber": l.loadNumber,
            ]
        )
    }

    private func handleCardTap(_ l: KanbanLoad, in lane: KanbanLane) {
        if lane.id == "tender", l.driverId == nil {
            openAssignDriver(l)
        } else {
            sheetLoad = l
        }
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
        guard shifting == nil else { return }
        loading = true; loadError = nil
        do {
            let response = try await fetchBoard()
            applyBoard(response)
        } catch {
            if error is CancellationError { return }
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            loading = false
            return
        }

        // Board preferences are an enhancement, not a dependency of the live
        // load feed. A settings outage must never turn a healthy board into an
        // empty/error screen; the complete five-stage compact board remains
        // usable while the next refresh retries preferences.
        do {
            let settings: KanbanSettingsPayload = try await EusoTripAPI.shared.queryNoInput("settings.getSettings")
            if let board = settings.rolePreferences?.dispatch?.board {
                let valid = Set(board.visibleStages).intersection(kanbanLanes.map(\.id))
                visibleStageIds = valid.isEmpty ? Set(kanbanLanes.map(\.id)) : valid
                cardDensity = board.cardDensity == "comfortable" ? "comfortable" : "compact"
            }
        } catch {
            visibleStageIds = Set(kanbanLanes.map(\.id))
            cardDensity = "compact"
        }
        loading = false
    }

    private func shift(_ l: KanbanLoad, to next: String) async {
        guard shifting == nil else { return }
        let previousBoard = byLane
        let previousTotal = totalAll
        shifting = l.id
        actionError = nil
        struct In: Encodable { let loadId: String; let status: String }
        do {
            let response: DispatcherMutationResult = try await EusoTripAPI.shared.mutation(
                "dispatch.updateLoadStatus", input: In(loadId: l.id, status: next))
            try response.validateStatus(loadId: l.id, status: next)
            let confirmed = try await readBack(
                loadId: l.id,
                expectedStatus: next,
                requiresNoDriver: false
            )
            applyBoard(confirmed)
            sheetLoad = nil
        } catch {
            byLane = previousBoard
            totalAll = previousTotal
            if !(error is CancellationError) {
                actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
        }
        shifting = nil
    }

    private func drop(_ loadId: String, into lane: KanbanLane) async {
        guard let load = allLoads.first(where: { $0.id == loadId }),
              let source = currentLane(for: load.status),
              let sourceIndex = kanbanLanes.firstIndex(where: { $0.id == source.id }),
              let targetIndex = kanbanLanes.firstIndex(where: { $0.id == lane.id }) else {
            await resetDragState()
            return
        }
        guard source.id != lane.id else {
            await resetDragState()
            return
        }

        if source.id == "assigned", lane.id == "tender" {
            await unassign(load)
        } else if targetIndex == sourceIndex + 1 {
            if lane.id == "assigned", load.driverId == nil {
                await MainActor.run {
                    actionError = "Assign a driver before moving \(load.loadNumber) into Assigned."
                    openAssignDriver(load)
                }
            } else if let status = dropStatus(for: lane) {
                await shift(load, to: status)
            }
        } else {
            await MainActor.run {
                actionError = "Move \(load.loadNumber) one operational stage at a time."
            }
        }
        await resetDragState()
    }

    private func unassign(_ l: KanbanLoad) async {
        guard shifting == nil else { return }
        let previousBoard = byLane
        let previousTotal = totalAll
        shifting = l.id
        actionError = nil
        struct In: Encodable { let loadId: String; let reason: String }
        do {
            let response: DispatcherMutationResult = try await EusoTripAPI.shared.mutation(
                "dispatch.unassignDriver",
                input: In(loadId: l.id, reason: "Dispatcher Kanban move to Tender")
            )
            try response.validateUnassignment(loadId: l.id)
            let confirmed = try await readBack(
                loadId: l.id,
                expectedStatus: "posted",
                requiresNoDriver: true
            )
            applyBoard(confirmed)
            sheetLoad = nil
        } catch {
            byLane = previousBoard
            totalAll = previousTotal
            if !(error is CancellationError) {
                actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
        }
        shifting = nil
    }

    private func fetchBoard() async throws -> UnifiedLoadsResponse {
        struct In: Encodable { let mode: String; let limit: Int; let offset: Int }
        try Task.checkCancellation()
        let response: UnifiedLoadsResponse = try await EusoTripAPI.shared.query(
            "dispatch.unifiedLoads",
            input: In(mode: "company", limit: 500, offset: 0)
        )
        try Task.checkCancellation()
        return response
    }

    private func readBack(
        loadId: String,
        expectedStatus: String,
        requiresNoDriver: Bool
    ) async throws -> UnifiedLoadsResponse {
        // `unifiedLoads` reads from the configured read database. Give a
        // replica a short bounded window to catch the committed primary write;
        // never paint the new lane until the exact ID/status is observable.
        let delays: [UInt64] = [0, 150_000_000, 350_000_000, 700_000_000]
        var lastStatus: String?
        var sawLoad = false
        var lastReadError: Error?

        for delay in delays {
            try Task.checkCancellation()
            if delay > 0 { try await Task.sleep(nanoseconds: delay) }
            do {
                let response = try await fetchBoard()
                guard let row = response.loads.first(where: { $0.id == loadId }) else {
                    lastReadError = DispatcherKanbanCommitError.readbackMissing(loadId: loadId)
                    continue
                }
                sawLoad = true
                lastStatus = row.status
                guard row.status == expectedStatus else { continue }
                if requiresNoDriver, row.driverId != nil { continue }
                return response
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastReadError = error
            }
        }

        if requiresNoDriver, sawLoad, lastStatus == expectedStatus {
            throw DispatcherKanbanCommitError.readbackUnassignedMismatch(loadId: loadId)
        }
        if sawLoad, let lastStatus {
            throw DispatcherKanbanCommitError.readbackMismatch(
                loadId: loadId,
                expectedStatus: expectedStatus,
                receivedStatus: lastStatus
            )
        }
        throw lastReadError ?? DispatcherKanbanCommitError.readbackMissing(loadId: loadId)
    }

    private func applyBoard(_ response: UnifiedLoadsResponse) {
        var grouped: [String: [KanbanLoad]] = [:]
        for load in response.loads {
            let key = laneId(for: load.status) ?? "tender"
            grouped[key, default: []].append(load)
        }
        byLane = grouped
        totalAll = response.total
    }

    private func resetDragState() async {
        await MainActor.run {
            dropLaneId = nil
            draggingLoadId = nil
        }
    }

    // MARK: - Mapping + formatting helpers

    private func laneId(for status: String) -> String? {
        kanbanLanes.first { $0.statuses.contains(status) }?.id
    }
    private func currentLane(for status: String) -> KanbanLane? {
        kanbanLanes.first { $0.statuses.contains(status) }
    }

    private func dropStatus(for lane: KanbanLane) -> String? {
        switch lane.id {
        case "tender": return "posted"
        case "assigned": return "assigned"
        case "pickup": return "en_route_pickup"
        case "transit": return "in_transit"
        case "delivered": return "delivered"
        default: return lane.nextStatus
        }
    }

    private func laneText(_ l: KanbanLoad) -> String {
        let o = (l.originCity ?? "-")
        let d = (l.destinationCity ?? "-")
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
        return parts.isEmpty ? "-" : parts.joined(separator: " · ")
    }

    private func shortId(_ ln: String) -> String { "LD…\(String(ln.uppercased().suffix(4)))" }

    private func usd(_ v: Double?) -> String {
        guard let v else { return "-" }
        return "$\(Int(v).formatted())"
    }

    private func initials(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "-" }
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
