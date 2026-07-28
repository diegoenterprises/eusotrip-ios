//
//  628_RailYardMap.swift
//  EusoTrip — Rail Engineer · Yard Map (628).
//
//  CARRIER-SIDE MAP archetype — a live rail-yard map hero (each real yard a
//  translucent footprint + pin over the in-house BespokeMapCanvas) above a
//  TRACK OCCUPANCY board (a track-tile grid colored occupied/open, per-track
//  car detail, and an unassigned lane) and a ZONES list of the rail-yard
//  catalog. Owen reads yard saturation at a glance and jumps to the open
//  track instead of walking the lead.
//
//  Verbatim port of "628 Rail Yard Map · Dark". transportMode=rail · US.
//
//  WIRING (railShipments.ts — REAL carload-native, verified):
//    • yards  ← railShipments.getRailYards            (railShipments.ts:1207)
//               → [rail_yards row] (id/name/city/state/coordinates/yardType/
//                 totalTracks/capacity). The map + ZONES key off these.
//    • tracks ← railShipments.getYardTrackOccupancy   (railShipments.ts:977)
//               → { yardId, yardName?, totalTracks, capacity, utilizationPct,
//                 tracks:[{trackNumber, cars:[{id,carNumber,carType,status}],
//                 carCount}], unassigned:[…] }. REAL railcars currently at the
//                 yard, distributed by trackNumber; out-of-range → unassigned.
//
//  ZERO-FABRICATION: utilizationPct is null when capacity is unknown — the
//  header renders "—", never an invented %. Empty tracks/unassigned render an
//  honest empty state; a FAILED occupancy read renders a distinct retryable
//  error, never the empty state. Every occupant chip shows ONLY real slim
//  fields (carNumber · carType · status). No coordinates → the map card hides
//  itself. Yard switches are generation-guarded — a slow earlier response can
//  never paint a stale yard's board over the current selection.
//

import SwiftUI

struct RailYardMapScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailYardMapBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Track status model (only the two real per-track states)

/// A track is either OCCUPIED (carCount > 0) or OPEN. The carload-native read
/// carries no per-track reserved/maintenance status, so the legend shows only
/// the two states that exist — no fabricated buckets.
private enum TrackStatus {
    case occupied, open

    init(carCount: Int) { self = carCount > 0 ? .occupied : .open }

    var tileFill: Color {
        switch self {
        case .occupied: return Brand.blue.opacity(0.9)
        case .open:     return Color.white.opacity(0.18)
        }
    }
    var legendFill: Color {
        switch self {
        case .occupied: return Brand.blue.opacity(0.85)
        case .open:     return Color.white.opacity(0.18)
        }
    }
    var legendLabel: String {
        switch self {
        case .occupied: return "Occupied"
        case .open:     return "Open"
        }
    }
}

// MARK: - Body

private struct RailYardMapBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var session: EusoTripSession

    @State private var yards: [RailYardRow] = []
    @State private var occupancy: YardTrackOccupancy? = nil
    @State private var selectedYardId: Int? = nil

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var occLoading = false
    /// Occupancy-read failure — renders the retryable error state, distinct
    /// from the true "No tracks configured" empty state.
    @State private var occError: String? = nil
    /// Generation token for the occupancy fetch — bumped on every request so
    /// a slow earlier response can be discarded instead of painting a stale
    /// yard's board over the current selection.
    @State private var occRequestId = 0

    /// Detail-list scope toggle (secondary CTA). Default: only occupied tracks.
    @State private var showAllTracks = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s3)

                VStack(alignment: .leading, spacing: Space.s5) {
                    if loading {
                        loadingState
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else if yards.isEmpty {
                        EusoEmptyState(systemImage: "mappin.and.ellipse",
                                       title: "No rail yards",
                                       subtitle: "Rail yards will appear here once the catalog is configured.")
                    } else {
                        yardMapCard
                        trackOccupancyCard
                        zonesSection
                        zonesCard
                        ctaRow
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s5)
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Selected yard

    private var selectedYard: RailYardRow? {
        yards.first { $0.id == selectedYardId } ?? yards.first
    }

    // MARK: - Top bar (eyebrow + title + menu + subtitle)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦  RAIL ENGINEER · YARD MAP")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: 8)
                Text(yardRef)
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Text("Yard map")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s4)
            Text(subtitle)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, Space.s1)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s4)
    }

    /// Monospace yard reference — the selected rail yard id, else a RAIL prefix.
    private var yardRef: String {
        if let id = selectedYardId { return "RAIL · YARD \(id)" }
        return "RAIL · YARD MAP"
    }

    private var subtitle: String {
        let name = selectedYard?.name ?? occupancy?.yardName ?? "Yard"
        // Track count: prefer the live occupancy geometry; fall back to the
        // selected yard row's totalTracks. No fabricated "24 tracks".
        if let t = occupancy?.totalTracks, t > 0 {
            return "\(name) · \(t) tracks · live"
        }
        if let t = selectedYard?.totalTracks, t > 0 {
            return "\(name) · \(t) tracks · live"
        }
        return "\(name) · live"
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft)
                .frame(height: 248)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 78)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
    }

    // MARK: - Yard map card (in-house BespokeMapCanvas · .adZones footprints)

    /// Yards with REAL coordinates (lat/lng present, not null-island).
    private var mappableYards: [RailYardRow] {
        yards.filter { y in
            guard let la = y.coordinates?.lat, let lo = y.coordinates?.lng else { return false }
            return !(la == 0 && lo == 0)
        }
    }

    @ViewBuilder
    private var yardMapCard: some View {
        let mapped = mappableYards
        if mapped.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("YARD MAP · LIVE")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: 8)
                    Text("\(mapped.count) yard\(mapped.count == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.bottom, Space.s3)

                HereVectorMapView(
                    center: mapCenter,
                    zoom: mapZoom,
                    interactive: true,
                    tilt: 0,
                    layers: [
                        .adZones(mapped.map(yardFootprint(for:))),
                        .markers(mapped.compactMap { y in
                            guard let lat = y.coordinates?.lat,
                                  let lng = y.coordinates?.lng else { return nil }
                            return HereMarker(
                                at: HereLatLng(lat, lng),
                                kind: .pickup,
                                label: y.name,
                                id: String(y.id))
                        })
                    ],
                    onSelectMarker: { markerId in
                        guard let id = Int(markerId) else { return }
                        withAnimation(.easeInOut(duration: 0.18)) { selectedYardId = id }
                        Task { await reloadOccupancy() }
                    }
                )
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        }
    }

    private var mapCenter: HereLatLng {
        let mapped = mappableYards
        guard !mapped.isEmpty else { return HereLatLng(39.5, -98.35) }
        let lat = mapped.reduce(0.0) { $0 + ($1.coordinates?.lat ?? 0) } / Double(mapped.count)
        let lng = mapped.reduce(0.0) { $0 + ($1.coordinates?.lng ?? 0) } / Double(mapped.count)
        return HereLatLng(lat, lng)
    }

    private var mapZoom: Int { mappableYards.count <= 1 ? 14 : 9 }

    /// Small ~250 m square footprint centered on the yard's real coordinate —
    /// the catalog projects a point, not a ring, so we draw an honest footprint
    /// box (selected yard reads brighter).
    private func yardFootprint(for y: RailYardRow) -> HerePolygon {
        let lat = y.coordinates?.lat ?? 0
        let lng = y.coordinates?.lng ?? 0
        let dLat = 0.0022
        let dLng = 0.0022 / max(cos(lat * .pi / 180), 0.2)
        let ring = [
            HereLatLng(lat + dLat, lng - dLng),
            HereLatLng(lat + dLat, lng + dLng),
            HereLatLng(lat - dLat, lng + dLng),
            HereLatLng(lat - dLat, lng - dLng),
        ]
        let isSelected = (selectedYardId ?? yards.first?.id) == y.id
        return HerePolygon(
            ring: ring,
            fillHex: "#1473FF",
            opacity: isSelected ? 0.30 : 0.16,
            label: y.name)
    }

    // MARK: - Track occupancy card (tile grid + totals + per-track detail)

    private var trackOccupancyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: TRACK OCCUPANCY · LIVE   ·   totals.
            HStack(alignment: .firstTextBaseline) {
                Text("TRACK OCCUPANCY · LIVE")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                if occLoading {
                    ProgressView().scaleEffect(0.6).tint(palette.textTertiary)
                }
            }
            // Yard-level totals strip (real: totalTracks / capacity / util%).
            totalsStrip
                .padding(.top, Space.s3)

            let tracks = occupancy?.tracks ?? []
            if let occErr = occError {
                occupancyErrorState(occErr)
                    .padding(.top, Space.s4)
            } else if tracks.isEmpty {
                emptyTrackState
                    .padding(.top, Space.s4)
            } else {
                tileGrid(tracks)
                    .padding(.top, Space.s4)
                legendRow
                    .padding(.top, Space.s4)
                trackDetailList(tracks)
                    .padding(.top, Space.s4)
            }

            // Unassigned lane — cars whose trackNumber is out of range.
            if let unassigned = occupancy?.unassigned, !unassigned.isEmpty {
                unassignedLane(unassigned)
                    .padding(.top, Space.s4)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    /// Real yard totals: N tracks · cap M · util X% ("—" when unknown).
    private var totalsStrip: some View {
        HStack(spacing: Space.s3) {
            totalStat(value: totalTracksLabel, label: "tracks")
            statDivider
            totalStat(value: capacityLabel, label: "car cap")
            statDivider
            totalStat(value: utilizationLabel, label: "utilization")
            Spacer(minLength: 0)
        }
    }

    private var statDivider: some View {
        Rectangle().fill(palette.borderFaint).frame(width: 1, height: 26)
    }

    private func totalStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
            Text(label)
                .font(.system(size: 9, weight: .regular)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var totalTracksLabel: String {
        if let t = occupancy?.totalTracks, t > 0 { return "\(t)" }
        if let t = selectedYard?.totalTracks, t > 0 { return "\(t)" }
        return "—"
    }
    private var capacityLabel: String {
        if let c = occupancy?.capacity, c > 0 { return "\(c)" }
        if let c = selectedYard?.capacity, c > 0 { return "\(c)" }
        return "—"
    }
    /// Honest "—" when capacity is unknown (server emits null utilizationPct).
    private var utilizationLabel: String {
        guard let pct = occupancy?.utilizationPct else { return "—" }
        if pct == pct.rounded() { return "\(Int(pct))%" }
        return String(format: "%.1f%%", pct)
    }

    /// Bespoke tile grid — one tile per track (1..N), colored occupied/open,
    /// 8 per row. The real carload geometry, not a fabricated 8×4 scaffold.
    private func tileGrid(_ tracks: [YardTrack]) -> some View {
        let ordered = tracks.sorted { $0.trackNumber < $1.trackNumber }
        let rows = stride(from: 0, to: ordered.count, by: 8).map { start in
            Array(ordered[start..<min(start + 8, ordered.count)])
        }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, rowTracks in
                HStack(spacing: 8) {
                    ForEach(rowTracks) { track in
                        trackTile(track)
                    }
                    // Pad the final short row so tiles stay left-sized.
                    if rowTracks.count < 8 {
                        ForEach(0..<(8 - rowTracks.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity).frame(height: 30)
                        }
                    }
                }
            }
        }
    }

    private func trackTile(_ track: YardTrack) -> some View {
        let status = TrackStatus(carCount: track.carCount)
        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(status.tileFill)
            Text("\(track.trackNumber)")
                .font(.system(size: 10, weight: .bold)).monospacedDigit()
                .foregroundStyle(status == .occupied ? Color.white : palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 30)
    }

    private var legendRow: some View {
        HStack(spacing: Space.s4) {
            ForEach([TrackStatus.occupied, .open], id: \.legendLabel) { s in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(s.legendFill)
                        .frame(width: 12, height: 12)
                    Text(s.legendLabel)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Per-track detail list

    @ViewBuilder
    private func trackDetailList(_ tracks: [YardTrack]) -> some View {
        let occupied = tracks.filter { $0.carCount > 0 }.sorted { $0.trackNumber < $1.trackNumber }
        let shown = showAllTracks
            ? tracks.sorted { $0.trackNumber < $1.trackNumber }
            : occupied
        if shown.isEmpty {
            Text("No cars spotted on any track.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { idx, track in
                    trackDetailRow(track)
                    if idx < shown.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1)
                            .padding(.vertical, Space.s1)
                    }
                }
            }
        }
    }

    private func trackDetailRow(_ track: YardTrack) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                Text("Track \(track.trackNumber)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
                Text(track.carCount == 0 ? "open" : "\(track.carCount) car\(track.carCount == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .bold)).tracking(0.3)
                    .foregroundStyle(track.carCount == 0 ? palette.textTertiary : Brand.blue)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill((track.carCount == 0 ? palette.textTertiary : Brand.blue).opacity(0.18)))
            }
            if track.cars.isEmpty {
                Text("no cars spotted")
                    .font(EType.mono(.caption)).tracking(0.2)
                    .foregroundStyle(palette.textTertiary)
            } else {
                FlowChips(cars: track.cars)
            }
        }
        .padding(.vertical, Space.s2)
    }

    // MARK: - Unassigned lane

    private func unassignedLane(_ cars: [YardCar]) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("UNASSIGNED · \(cars.count)")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(Brand.warning)
                Spacer(minLength: 8)
                Text("no track number")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(palette.textTertiary)
            }
            Rectangle().fill(palette.borderFaint).frame(height: 1)
            FlowChips(cars: cars)
        }
        .padding(Space.s3)
        .background(Brand.warning.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Brand.warning.opacity(0.30)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Occupancy error state (failed read — distinct from true empty)

    /// A failed occupancy read renders THIS, never the "No tracks configured"
    /// empty state — that claim is only honest when the read succeeded.
    private func occupancyErrorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Brand.danger)
                Text(message)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Button {
                Task { await reloadOccupancy() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                    Text("Retry")
                        .font(.system(size: 11, weight: .bold)).tracking(0.3)
                }
                .foregroundStyle(Brand.danger)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Brand.danger.opacity(0.14)))
                .overlay(Capsule().strokeBorder(Brand.danger.opacity(0.35)))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.s2)
    }

    // MARK: - Empty track state

    private var emptyTrackState: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Image(systemName: "tram")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("No tracks configured for this yard.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Text("Track occupancy appears once the yard's track count is set.")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.s2)
    }

    // MARK: - ZONES section header

    private var zonesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("ZONES · \(yards.count)")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(Color(hex: 0x4DA3FF))
                Spacer(minLength: 8)
                Text("tap to load tracks ›")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            Rectangle()
                .fill(palette.borderFaint)
                .frame(height: 1)
                .padding(.top, Space.s2)
        }
    }

    // MARK: - Zones card (rail-yard rows)

    @ViewBuilder
    private var zonesCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(yards.enumerated()), id: \.element.id) { idx, y in
                zoneRow(y)
                if idx < yards.count - 1 {
                    Rectangle()
                        .fill(palette.borderFaint)
                        .frame(height: 1)
                        .padding(.horizontal, Space.s4)
                }
            }
        }
        .padding(.vertical, Space.s1)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func zoneRow(_ y: RailYardRow) -> some View {
        let cap = max(y.capacity ?? 0, 0)
        let tracks = max(y.totalTracks ?? 0, 0)
        let accent = zoneAccent(y)
        let isSelected = (selectedYardId ?? yards.first?.id) == y.id

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectedYardId = y.id }
            Task { await reloadOccupancy() }
        } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "mappin")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(y.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(zoneSubtitle(y))
                        .font(EType.mono(.caption)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: Space.s1) {
                    Text(tracks > 0 ? "\(tracks) tracks" : "—")
                        .font(.system(size: 13, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text(cap > 0 ? "\(cap) car cap" : "cap —")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? accent.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func zoneAccent(_ y: RailYardRow) -> Color {
        switch (y.yardType ?? "").lowercased() {
        case let t where t.contains("intermodal"): return Brand.blue
        case let t where t.contains("classification"),
             let t where t.contains("flat"):        return Brand.rail
        case let t where t.contains("industry"),
             let t where t.contains("team"):         return Brand.warning
        default:                                     return Brand.blue
        }
    }

    private func zoneSubtitle(_ y: RailYardRow) -> String {
        var parts: [String] = []
        let place = [y.city, y.state].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ", ")
        if !place.isEmpty { parts.append(place) }
        if let t = y.yardType, !t.isEmpty { parts.append(t.replacingOccurrences(of: "_", with: " ")) }
        return parts.isEmpty ? "rail yard" : parts.joined(separator: " · ")
    }

    // MARK: - CTA row (Refresh · All/Occupied detail toggle)

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            CTAButton(
                title: "Refresh occupancy",
                action: { Task { await reloadOccupancy() } },
                leadingIcon: "arrow.clockwise",
                isLoading: occLoading
            )
            .frame(maxWidth: .infinity)

            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showAllTracks.toggle() }
            } label: {
                Text(showAllTracks ? "Occupied" : "All tracks")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 130, height: 52)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loaders

    private func reload() async {
        loading = true; loadError = nil
        do {
            let list = try await EusoTripAPI.shared.railShipments.getRailYards()
            self.yards = list
            if selectedYardId == nil || !list.contains(where: { $0.id == selectedYardId }) {
                selectedYardId = list.first?.id
            }
            await reloadOccupancy()
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// Load the real carload track occupancy for the selected yard.
    ///
    /// RACE GUARD: tapping yards back-to-back fires overlapping requests — a
    /// slow earlier response must never land after a newer one and render the
    /// wrong yard's board. Each request captures a generation token plus the
    /// yardId it was fired for; the response (success OR failure) is discarded
    /// unless both still match the current state when it lands.
    private func reloadOccupancy() async {
        guard let yardId = selectedYardId else {
            occupancy = nil
            occError = nil
            return
        }
        occRequestId += 1
        let requestId = occRequestId
        occLoading = true
        do {
            let board = try await EusoTripAPI.shared.railShipments.getYardTrackOccupancy(yardId: yardId)
            guard requestId == occRequestId, yardId == selectedYardId else { return }
            self.occupancy = board
            self.occError = nil
        } catch {
            guard requestId == occRequestId, yardId == selectedYardId else { return }
            // HONESTY: a failed read must never render as "No tracks
            // configured" — clear the board and surface the retryable error.
            self.occupancy = nil
            self.occError = "Couldn't load track occupancy."
        }
        if requestId == occRequestId { occLoading = false }
    }
}

// MARK: - Flow-wrapped occupant car chips (shared by tracks + unassigned lane)

/// Wrapping row of car chips. Each chip renders ONLY real slim fields:
/// carNumber (mono) · carType · status. Missing carNumber → em-dash.
private struct FlowChips: View {
    @Environment(\.palette) private var palette
    let cars: [YardCar]

    var body: some View {
        // Reuses the module-wide `FlowLayout` (Auth/002_CreateAccount.swift):
        // a wrapping container so variable-width car chips pack tightly.
        FlowLayout(spacing: 6) {
            ForEach(cars) { car in
                chip(car)
            }
        }
    }

    private func chip(_ car: YardCar) -> some View {
        HStack(spacing: 5) {
            Text(car.carNumber?.isEmpty == false ? car.carNumber! : "—")
                .font(EType.mono(.micro)).tracking(0.2)
                .foregroundStyle(palette.textPrimary)
            if let t = car.carType, !t.isEmpty {
                Text(t)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
            }
            if let s = car.status, !s.isEmpty {
                Text(s)
                    .font(.system(size: 8.5, weight: .bold)).tracking(0.3)
                    .foregroundStyle(statusColor(s))
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(Capsule().fill(statusColor(s).opacity(0.18)))
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(palette.bgCardSoft)
        .overlay(Capsule().strokeBorder(palette.borderFaint))
        .clipShape(Capsule())
    }

    private func statusColor(_ s: String) -> Color {
        switch s.lowercased() {
        case "loaded", "in_transit", "assigned": return Brand.blue
        case "available":                          return Brand.success
        case "in_repair", "out_of_service":        return Brand.danger
        case "stored":                             return Brand.warning
        default:                                    return palette.textSecondary
        }
    }
}

#Preview("628 · Rail Yard Map · Night") { RailYardMapScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("628 · Rail Yard Map · Light") { RailYardMapScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
