//
//  702_TerminalYardMap.swift
//  EusoTrip — Terminal · Yard Map (brick 702).
//
//  Third brick on the Terminal Manager role track (700s). Drilled
//  into from 700_TerminalHome's "Yard" trailing nav slot — exposes
//  the full yard occupancy by zone with each slot rendered as a tile
//  (free / occupied) and a per-slot "Release" mutation when a truck
//  departs and the slot is clear. Brings Terminal to three-screen
//  depth (parity with Shipper 200/201/202, Carrier 300/301/302,
//  Broker 400/401/402, Catalyst 500/501/502 once they all reach 3),
//  honoring the user's "every screen each role at a time" cadence.
//
//  Pixel-doctrine compliant per EUSOTRIP2027GOLD §1 (gradient-only
//  accent — no `.fill(Brand.blue)` / `.tint(Brand.blue)`), §2 (no
//  Toggles on this brick), §4 (tokenized spacing / radius / type —
//  Space.s*, Radius.*, EType.*), §5 (palette semantic only — no
//  hard-coded `Color.white` / `Color.black` / `Color.gray` fills
//  outside the CTA inverse-text and shadow opacities), §3
//  (`AnyShapeStyle` wrapping for ternary shape-styles in fill /
//  stroke), §10 (previews compile in isolation — `.task` doesn't
//  run in the preview canvas, so the store stays in `.loading` and
//  never hits the network).
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data, dynamic ready pages with 0 data,
//  plugged into backend"):
//
//    • Yard envelope → `TerminalYardMapStore` (LiveDataStores.swift)
//      → `terminals.getYardMap` (input `{}`). Server returns
//      zones + slots + KPI counts in a single envelope. If the
//      parallel router has not shipped, the store resolves to
//      `.error` and the screen surfaces an honest retry banner.
//      No fixture data ever.
//    • Per-slot "Release" CTA → `terminals.releaseSlot` mutation
//      (input `{ id: string }`). Each slot owns its own in-flight +
//      error state independently of the others, so a failed release
//      on slot A doesn't disturb slot B's idle CTA. On success the
//      tile re-paints from the mutation envelope (no extra round-
//      trip). On failure the CTA flips back to its idle label and
//      the inline error surfaces — local state never lies about the
//      commit landing.
//    • Empty / blank server fields surface as em-dash sentinels
//      ("—"). Empty zones (zero slots) render zone scaffolding so
//      the operator still sees the yard's geometry at idle; only a
//      zero-zones yard folds to `.empty`.
//
//  Wired into `ContentView.ScreenRegistry` as id="702".
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen body

struct TerminalYardMap: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var yard = TerminalYardMapStore()

    /// Per-slot in-flight state for the "Release" CTA. Indexed by slot
    /// id so a failed release on slot B doesn't disturb slot A.
    @State private var releaseInFlight: Set<String> = []
    /// 2026-05-23 — drag-and-drop state for the yard map.
    /// dropHoverSlotId tracks which empty slot is the active drop
    /// candidate so it can highlight; moveInFlight gates the source
    /// tile during the mutation; moveError surfaces a per-tile error
    /// inline so an in-flight failure on slot A doesn't disturb the
    /// idle UX on slot B.
    @State private var dropHoverSlotId: String? = nil
    @State private var moveInFlight: Set<String> = []
    @State private var moveError: [String: String] = [:]
    /// Per-slot error message (post-mutation). Cleared when the slot's
    /// CTA is tapped again or the yard refresh fires.
    @State private var releaseError: [String: String] = [:]
    /// Local override for `occupied` flag keyed by slot id. Set by a
    /// successful release so the tile re-paints immediately without
    /// waiting for the next refresh round-trip. The override is a
    /// snapshot of the freshly-released YardSlot so the tile drops
    /// its loadNumber / containerNumber / dwell at the same time.
    @State private var localReleased: [String: TerminalAPI.YardSlot] = [:]

    /// Slot currently presenting the release-confirmation sheet. `nil`
    /// while no slot has its CTA tapped.
    @State private var confirmReleaseSlot: TerminalAPI.YardSlot? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                contentBody
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await yard.refresh() }
        .refreshable { await yard.refresh() }
        // Release-confirmation sheet — opened by tapping the per-slot
        // "Release" CTA. Detents `[.medium]` + drag indicator matches
        // the lightweight one-action confirmation doctrine.
        .sheet(item: $confirmReleaseSlot) { slot in
            releaseConfirmationSheet(for: slot)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 10) {
                Image(systemName: "map.fill")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("TERMINAL · YARD MAP")
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    Text(headline)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text(subhead)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 4)

            // KPI strip — only shown once the envelope is loaded so
            // the strip never paints fabricated zeros mid-load.
            if case .loaded(let envelope) = yard.state, let v = envelope {
                kpiStrip(for: v)
            }
        }
    }

    /// Identity-aware headline. Falls back to a neutral title so the
    /// header never reads as a placeholder.
    private var headline: String {
        if let name = session.user?.firstName, !name.isEmpty {
            return "Yard, \(name)"
        }
        return "Yard Map"
    }

    private var subhead: String {
        switch yard.state {
        case .loading:
            return "Loading yard…"
        case .loaded(let envelope):
            guard let v = envelope else { return "Yard not configured" }
            let occ = v.occupiedSlots
            let total = v.totalSlots
            return "\(occ) / \(total) occupied · \(v.zones.count) zones"
        case .empty:
            return "No yard configured for this terminal"
        case .error:
            return "Yard couldn't load"
        }
    }

    @ViewBuilder
    private func kpiStrip(for envelope: TerminalAPI.YardMap) -> some View {
        HStack(spacing: Space.s2) {
            kpiTile(
                label: "OCCUPIED",
                value: "\(envelope.occupiedSlots)",
                sub: "of \(envelope.totalSlots)"
            )
            kpiTile(
                label: "AVG DWELL",
                value: dwell(envelope.avgDwellHours),
                sub: "across occupied"
            )
            kpiTile(
                label: "DWELL BREACH",
                value: "\(envelope.dwellBreachCount)",
                sub: envelope.dwellBreachCount > 0 ? "needs review" : "clear",
                danger: envelope.dwellBreachCount > 0
            )
        }
    }

    private func kpiTile(
        label: String,
        value: String,
        sub: String,
        danger: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(danger
                                 ? AnyShapeStyle(Brand.danger)
                                 : AnyShapeStyle(LinearGradient.diagonal))
                .monospacedDigit()
            Text(sub)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Content body (state machine)

    @ViewBuilder
    private var contentBody: some View {
        switch yard.state {
        case .loading:
            zoneSkeleton
        case .loaded(let envelope):
            if let v = envelope {
                VStack(alignment: .leading, spacing: Space.s4) {
                    ForEach(v.zones) { zone in
                        zoneCard(zone)
                    }
                }
            } else {
                emptyState
            }
        case .empty:
            emptyState
        case .error(let err):
            errorBanner(message: readableError(err))
        }
    }

    // MARK: - Zone card

    private func zoneCard(_ zone: TerminalAPI.YardZone) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 8) {
                Image(systemName: zoneIcon(for: zone.kind))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(zone.label.isEmpty ? "—" : zone.label.uppercased())
                    .font(.system(size: 11, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(zoneCountLabel(for: zone))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }
            if zone.slots.isEmpty {
                Text("No slots configured in this zone")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 152), spacing: Space.s2)],
                    alignment: .leading,
                    spacing: Space.s2
                ) {
                    ForEach(zone.slots) { slot in
                        slotTile(slot, in: zone)
                    }
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func zoneCountLabel(for zone: TerminalAPI.YardZone) -> String {
        let occ = zone.slots.filter { isOccupied($0) }.count
        return "\(occ)/\(zone.slots.count)"
    }

    private func zoneIcon(for kind: String?) -> String {
        switch kind?.uppercased() {
        case "DOCK":      return "tray.full.fill"
        case "RAIL_SPUR": return "tram.fill"
        case "REEFER":    return "snow"
        case "HAZMAT":    return "flame.fill"
        case "STAGING":   return "square.stack.3d.up.fill"
        default:          return "square.grid.3x3.fill"
        }
    }

    // MARK: - Slot tile

    private func slotTile(_ raw: TerminalAPI.YardSlot, in zone: TerminalAPI.YardZone) -> some View {
        // Local-released override carries the post-mutation snapshot so
        // the tile re-paints immediately without waiting for refresh.
        let slot = localReleased[raw.id] ?? raw
        let occupied = isOccupied(slot)
        let inFlight = releaseInFlight.contains(slot.id)
        let errMsg = releaseError[slot.id] ?? moveError[slot.id]
        let moving = moveInFlight.contains(slot.id)
        let isDropHover = dropHoverSlotId == slot.id

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: occupied ? "shippingbox.fill" : "square.dashed")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(occupied
                                     ? AnyShapeStyle(LinearGradient.diagonal)
                                     : AnyShapeStyle(palette.textTertiary))
                Text(slot.label.isEmpty ? "—" : slot.label)
                    .font(.system(size: 13, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                if let hz = slot.hazmatClass, !hz.isEmpty, occupied {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text("HZ \(hz)")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    }
                    .foregroundStyle(Brand.danger)
                }
            }

            if occupied {
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.loadNumber.isEmpty ? "—" : slot.loadNumber)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    if !slot.containerNumber.isEmpty {
                        Text(slot.containerNumber)
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    } else if let appt = slot.appointmentWindow, !appt.isEmpty {
                        Text(appt.uppercased())
                            .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.textTertiary)
                        Text(dwell(slot.dwellHours))
                            .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                            .monospacedDigit()
                    }
                }

                Button {
                    releaseError[slot.id] = nil
                    confirmReleaseSlot = slot
                } label: {
                    HStack(spacing: 6) {
                        if inFlight {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(0.55)
                        } else {
                            Image(systemName: "arrow.up.right.square.fill")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                        Text("Release")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(LinearGradient.diagonal.opacity(inFlight ? 0.55 : 1.0))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(inFlight)
            } else {
                Text("Free")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            if let msg = errMsg, !msg.isEmpty {
                Text(msg)
                    .font(EType.caption)
                    .foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(
                    isDropHover ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint),
                    lineWidth: isDropHover ? 2 : 1
                )
                .animation(.easeOut(duration: 0.12), value: dropHoverSlotId)
        )
        .opacity(moving ? 0.55 : 1.0)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        // Draggable when occupied — drag the trailer to another spot.
        // Drop on empty spots fires yardManagement.moveTrailer.
        .modifier(YardSlotDnDModifier(
            slot: slot,
            zone: zone,
            occupied: occupied,
            onDrop: { sourceSlotId in
                guard let sourceZone = currentZone(slotId: sourceSlotId, in: zone) ?? lookupZone(forSlot: sourceSlotId),
                      let sourceSlot = sourceZone.slots.first(where: { $0.id == sourceSlotId })
                else { return false }
                if sourceSlot.id == slot.id { return false }
                Task { await commitMove(from: sourceSlot, fromZone: sourceZone, to: slot, toZone: zone) }
                return true
            },
            isDropHovered: { dropHoverSlotId == slot.id },
            setDropHovered: { hovering in
                dropHoverSlotId = hovering ? slot.id : (dropHoverSlotId == slot.id ? nil : dropHoverSlotId)
            }
        ))
    }

    /// Find the zone that contains a given slot id — first checks
    /// the passed-in zone, then falls back to scanning the full
    /// envelope (cross-zone moves).
    private func currentZone(slotId: String, in zone: TerminalAPI.YardZone) -> TerminalAPI.YardZone? {
        zone.slots.contains(where: { $0.id == slotId }) ? zone : nil
    }
    private func lookupZone(forSlot slotId: String) -> TerminalAPI.YardZone? {
        guard case .loaded(let env) = yard.state, let v = env else { return nil }
        return v.zones.first(where: { z in z.slots.contains(where: { $0.id == slotId }) })
    }

    /// commitMove — fires yardManagement.moveTrailer for a drag from
    /// `from` (occupied) to `to` (empty). Optimistically marks the
    /// source as moving + surfaces inline error on the destination if
    /// the mutation fails. The store's next refresh re-syncs.
    private func commitMove(
        from src: TerminalAPI.YardSlot,
        fromZone srcZone: TerminalAPI.YardZone,
        to dest: TerminalAPI.YardSlot,
        toZone destZone: TerminalAPI.YardZone
    ) async {
        moveInFlight.insert(src.id)
        moveError[dest.id] = nil
        defer { moveInFlight.remove(src.id) }
        struct In: Encodable {
            let trailerId: String
            let trailerNumber: String?
            let fromSpot: String
            let toSpot: String
            let locationId: String
            let reason: String?
        }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "yardManagement.moveTrailer",
                input: In(
                    trailerId: src.loadNumber.isEmpty ? src.id : src.loadNumber,
                    trailerNumber: src.loadNumber.isEmpty ? nil : src.loadNumber,
                    fromSpot: src.label.isEmpty ? src.id : src.label,
                    toSpot: dest.label.isEmpty ? dest.id : dest.label,
                    locationId: destZone.id,
                    reason: "reposition"
                )
            )
            await yard.refresh()
        } catch {
            await MainActor.run {
                moveError[dest.id] = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Authority check — server is the source of truth for occupancy.
    private func isOccupied(_ slot: TerminalAPI.YardSlot) -> Bool {
        if let local = localReleased[slot.id] {
            return local.occupied
        }
        return slot.occupied
    }

    // MARK: - Release confirmation sheet

    @ViewBuilder
    private func releaseConfirmationSheet(
        for slot: TerminalAPI.YardSlot
    ) -> some View {
        ReleaseSlotSheet(
            slot: slot,
            onConfirm: {
                Task { await commitRelease(slot: slot) }
            },
            onCancel: {
                confirmReleaseSlot = nil
            }
        )
        .environment(\.palette, palette)
    }

    private func commitRelease(slot: TerminalAPI.YardSlot) async {
        guard !releaseInFlight.contains(slot.id) else { return }
        releaseInFlight.insert(slot.id)
        releaseError[slot.id] = nil
        defer {
            releaseInFlight.remove(slot.id)
            confirmReleaseSlot = nil
        }
        do {
            let updated = try await EusoTripAPI.shared.terminal.releaseSlot(id: slot.id)
            // Re-paint the tile immediately from the mutation envelope.
            localReleased[slot.id] = updated
        } catch {
            releaseError[slot.id] = readableError(error)
        }
    }

    // MARK: - Loading + empty + error states

    private var zoneSkeleton: some View {
        VStack(spacing: Space.s4) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 168)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
            }
        }
    }

    private var emptyState: some View {
        EusoEmptyState(
            systemImage: "map",
            title: "Yard not configured",
            subtitle: "Once your terminal admin defines zones and slots, the live map renders here with per-slot occupancy and one-tap release."
        )
    }

    private func errorBanner(message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.danger)
                Text("COULDN'T LOAD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.danger)
            }
            Text(message)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Button(action: { Task { await yard.refresh() } }) {
                Text("Retry")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Helpers

    /// Format dwell hours as a one-decimal "12.4 hr" label. Returns
    /// "—" for zero so empty/free slots never render as "0.0 hr".
    private func dwell(_ v: Double) -> String {
        guard v > 0 else { return "—" }
        return String(format: "%.1f hr", v)
    }

    private func readableError(_ error: Error) -> String {
        if let api = error as? EusoTripAPIError {
            return api.errorDescription ?? "Request failed."
        }
        return error.localizedDescription
    }
}

// MARK: - Release-slot confirmation sheet (split into its own struct
//         for the same reason 701's AssignDockInputSheet is split —
//         keeps `@FocusState` / `@State` from being trapped inside
//         the parent's `@ViewBuilder` closure)

/// Conditional drag/drop modifier for yard slot tiles. Adds
/// `.draggable(slot.id)` when the tile is occupied; adds
/// `.dropDestination(for: String.self)` when the tile is empty. Keeps
/// the tile's tap interactions intact (the existing Release button
/// still works inside the draggable wrapper).
private struct YardSlotDnDModifier: ViewModifier {
    let slot: TerminalAPI.YardSlot
    let zone: TerminalAPI.YardZone
    let occupied: Bool
    let onDrop: (String) -> Bool
    let isDropHovered: () -> Bool
    let setDropHovered: (Bool) -> Void

    func body(content: Content) -> some View {
        if occupied {
            content
                .draggable(slot.id) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(slot.label).font(.system(size: 11, weight: .heavy)).tracking(0.4)
                        Text(slot.loadNumber.isEmpty ? "—" : slot.loadNumber)
                            .font(.system(size: 13, weight: .heavy))
                    }
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                }
        } else {
            content
                .dropDestination(for: String.self) { droppedIds, _ in
                    guard let sourceId = droppedIds.first else { return false }
                    return onDrop(sourceId)
                } isTargeted: { hovering in
                    setDropHovered(hovering)
                }
        }
    }
}

private struct ReleaseSlotSheet: View {
    @Environment(\.palette) private var palette

    let slot: TerminalAPI.YardSlot
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("RELEASE SLOT")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text(slot.label.isEmpty ? "—" : slot.label)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                if !slot.loadNumber.isEmpty {
                    Text(slot.loadNumber)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                if !slot.containerNumber.isEmpty {
                    Text(slot.containerNumber)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }

            Text("Confirm the truck has departed and the slot is physically clear. The release fires immediately and removes the load from the yard map.")
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.s3) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(palette.bgCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderFaint, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onConfirm) {
                    Text("Release slot")
                        .font(.system(size: 13, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgPage)
    }
}

// MARK: - Screen wrapper (Shell + BottomNav)

struct TerminalYardMapScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            TerminalYardMap()
        } nav: {
            BottomNav(
                leading: terminalNavLeading_702(),
                trailing: terminalNavTrailing_702(),
                orbState: .idle
            )
        }
    }
}

private func terminalNavLeading_702() -> [NavSlot] {
    [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
     NavSlot(label: "Movements", systemImage: "shippingbox.fill", isCurrent: false)]
}

private func terminalNavTrailing_702() -> [NavSlot] {
    [NavSlot(label: "Yard", systemImage: "map",    isCurrent: true),
     NavSlot(label: "Me",   systemImage: "person", isCurrent: false)]
}

// MARK: - Previews
//
// Previews don't run `.task`, so the store stays in `.loading` —
// both registers render the loading skeleton without hitting the
// network. Per doctrine §10: previews must compile in isolation.

#Preview("702 · Terminal · Yard Map · Night") {
    TerminalYardMapScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("702 · Terminal · Yard Map · Afternoon") {
    TerminalYardMapScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
