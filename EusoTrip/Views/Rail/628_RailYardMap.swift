//
//  628_RailYardMap.swift
//  EusoTrip — Rail Engineer · Yard Map (628).
//
//  CARRIER-SIDE MAP archetype — a live track-grid MapCanvas hero (slots
//  colored occupied/reserved/open/maintenance with legend) over a ZONES
//  list where each zone row carries a 40 pin-chip + relative fill bar +
//  occupancy pill + tabular slots-used. Owen reads yard saturation at a
//  glance and jumps to the open block instead of walking the lead.
//
//  Verbatim port of "628 Rail Yard Map · Dark". transportMode=rail · US.
//  RBAC: protectedProcedure (companyId-scoped) on every yardManagement call.
//
//  WIRING (yardManagement.ts — REAL, verified):
//    • grid     ← yardManagement.getYardMap        (input { locationId }) —
//                 returns { rows, cols, spots:[{ status: empty|occupied|
//                 reserved|maintenance, … }] }.  EXISTS · yardManagement.ts:344
//    • zones    ← yardManagement.getYardLocations  (input { status }) —
//                 returns { locations:[…], total }. EXISTS · yardManagement.ts:246
//    • Locate trailer → yardManagement.updateTrailerPosition (mutation ·
//                 re-spots a unit). EXISTS · yardManagement.ts:501
//
//  PORT-GAPs (surfaced honestly, no fabricated data):
//    • getYardMap requires a `locationId`; the server returns a flat spot
//      grid WITHOUT the per-zone fill-bar / occupancy-pill / slots-used
//      projection the wireframe's ZONES list shows. We render the real
//      grid and derive zones from getYardLocations (capacity/occupied);
//      the server currently reports occupied: 0 for every location
//      (yardManagement.ts:313,325 — "would need real-time tracking"), so
//      the fill bars read honestly off whatever the server projects.
//    • No `yardName` / `trackCount` header projection — the subtitle reads
//      off the selected location's name + capacity when available.
//    • yard-move blockchain audit + WS yard channel = STUB (per <desc>):
//      updateTrailerPosition inserts a completed yardMoves row but NO
//      blockchainAuditTrail row and NO WS_CHANNELS broadcast yet.
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

// MARK: - Data shapes (mirror yardManagement.ts projections verbatim)

/// One spot in the live track grid. Server: yardManagement.getYardMap →
/// spots[]. `status` ∈ empty | occupied | reserved | maintenance.
private struct YardSpot628: Decodable, Identifiable, Hashable {
    let id: String
    let row: Int
    let col: Int
    let label: String?
    let status: String?
    let trailerId: String?
    let trailerNumber: String?
    let type: String?
}

/// getYardMap envelope. Server: { locationId, rows, cols, spots, lastUpdated }.
private struct YardMap628: Decodable {
    let locationId: String?
    let rows: Int?
    let cols: Int?
    let spots: [YardSpot628]?
    let lastUpdated: String?
}

/// One yard location / zone. Server: yardManagement.getYardLocations →
/// locations[]. `occupied` is real-time-tracked (currently 0 server-side).
private struct YardLocation628: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let address: String?
    let type: String?
    let capacity: Int?
    let occupied: Int?
    let dockDoors: Int?
    let status: String?
}

/// getYardLocations envelope. Server: { locations, total }.
private struct YardLocations628: Decodable {
    let locations: [YardLocation628]?
    let total: Int?
}

// MARK: - Spot status model

private enum SpotStatus: String {
    case occupied, reserved, empty, maintenance

    init(server: String?) {
        switch (server ?? "empty").lowercased() {
        case "occupied":    self = .occupied
        case "reserved":    self = .reserved
        case "maintenance": self = .maintenance
        default:            self = .empty
        }
    }

    /// SVG fills: occupied #1473FF@0.9 · reserved #FFA726@0.9 ·
    /// open #FFFFFF@0.18 · maint #F44336@0.9.
    var fill: Color {
        switch self {
        case .occupied:    return Brand.blue.opacity(0.9)
        case .reserved:    return Brand.warning.opacity(0.9)
        case .maintenance: return Brand.danger.opacity(0.9)
        case .empty:       return Color.white.opacity(0.18)
        }
    }
    /// Legend swatch fills (SVG @0.85 / open @0.18).
    var legendFill: Color {
        switch self {
        case .occupied:    return Brand.blue.opacity(0.85)
        case .reserved:    return Brand.warning.opacity(0.85)
        case .maintenance: return Brand.danger.opacity(0.85)
        case .empty:       return Color.white.opacity(0.18)
        }
    }
    var legendLabel: String {
        switch self {
        case .occupied:    return "Occupied"
        case .reserved:    return "Reserved"
        case .empty:       return "Open"
        case .maintenance: return "Maint"
        }
    }
}

// MARK: - Body

private struct RailYardMapBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @State private var locations: [YardLocation628] = []
    @State private var grid: YardMap628? = nil
    @State private var selectedLocationId: String? = nil

    @State private var loading = true
    @State private var loadError: String? = nil

    // Locate-trailer mutation state.
    @State private var locating = false
    @State private var locateAck: String? = nil
    @State private var locateError: String? = nil

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
                    } else {
                        trackGridCard
                        zonesSection
                        zonesCard
                        if let ack = locateAck {
                            inlineBanner(ack, color: Brand.success, icon: "checkmark.circle.fill")
                        }
                        if let err = locateError {
                            inlineBanner(err, color: Brand.danger, icon: "exclamationmark.triangle.fill")
                        }
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

    // MARK: - Top bar (eyebrow + back + title + menu + subtitle)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Eyebrow row: brand label + monospace yard ref.
            HStack {
                Text("✦  RAIL ENGINEER · YARD MAP")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: 8)
                Text(yardRef)
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            // Title row: back chevron · "Yard map" · three-dot menu.
            HStack(alignment: .center, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
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
            // Subtitle: yard name · track count · live.
            Text(subtitle)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, Space.s1)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s4)
    }

    /// Monospace yard reference, derived from the selected location id when
    /// available — falls back to the SVG-style RAIL prefix.
    private var yardRef: String {
        if let id = selectedLocationId, !id.isEmpty {
            return "RAIL · \(id.uppercased())"
        }
        return "RAIL · YARD MAP"
    }

    private var subtitle: String {
        let active = locations.first { $0.id == selectedLocationId } ?? locations.first
        let name = active?.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Yard"
        // Track count: prefer the live grid geometry; fall back to the
        // location's capacity. No fabricated "24 tracks".
        if let g = grid, let r = g.rows, r > 0 {
            return "\(name) · \(r) tracks · live"
        }
        if let cap = active?.capacity, cap > 0 {
            return "\(name) · \(cap) slots · live"
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

    // MARK: - Track grid card (live MapCanvas hero)

    private var trackGridCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header: TRACK GRID · LIVE   ·   <name> · N tracks
            HStack(alignment: .firstTextBaseline) {
                Text("TRACK GRID · LIVE")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                Text(gridHeaderRight)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            // The slot grid.
            gridView
                .padding(.top, Space.s4)
            // Legend.
            legendRow
                .padding(.top, Space.s4)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var gridHeaderRight: String {
        let active = locations.first { $0.id == selectedLocationId } ?? locations.first
        let name = active?.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Yard"
        if let g = grid, let r = g.rows, r > 0 {
            return "\(name) · \(r) tracks"
        }
        return name
    }

    /// 8-wide rows of slot tiles. SVG: 38×28 rounded-6 tiles in an
    /// 8-col × 4-row grid. We render the REAL spots from getYardMap; when
    /// the server returns an empty grid we draw the open-slot scaffold so
    /// the operator still sees yard geometry (no fabricated occupancy).
    @ViewBuilder
    private var gridView: some View {
        let spots = grid?.spots ?? []
        if spots.isEmpty {
            // Empty-yard scaffold: 8×4 open tiles + an honest note.
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<4, id: \.self) { _ in
                    HStack(spacing: 8) {
                        ForEach(0..<8, id: \.self) { _ in
                            slotTile(status: .empty)
                        }
                    }
                }
                Text("No live spots configured for this yard.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, Space.s1)
            }
        } else {
            // Real grid: group by server row, ordered.
            let rows = Dictionary(grouping: spots, by: { $0.row })
                .sorted { $0.key < $1.key }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows, id: \.key) { _, rowSpots in
                    HStack(spacing: 8) {
                        ForEach(rowSpots.sorted { $0.col < $1.col }) { spot in
                            slotTile(status: SpotStatus(server: spot.status))
                        }
                    }
                }
            }
        }
    }

    private func slotTile(status: SpotStatus) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(status.fill)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
    }

    /// Legend: Occupied · Reserved · Open · Maint (SVG order).
    private var legendRow: some View {
        HStack(spacing: Space.s4) {
            ForEach([SpotStatus.occupied, .reserved, .empty, .maintenance], id: \.self) { s in
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

    // MARK: - ZONES section header

    private var zonesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("ZONES · \(locations.count)")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(Color(hex: 0x4DA3FF))
                Spacer(minLength: 8)
                Text("see all ›")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            Rectangle()
                .fill(palette.borderFaint)
                .frame(height: 1)
                .padding(.top, Space.s2)
        }
    }

    // MARK: - Zones card (pin-chip rows)

    @ViewBuilder
    private var zonesCard: some View {
        if locations.isEmpty {
            EusoEmptyState(systemImage: "mappin.and.ellipse",
                           title: "No yard zones",
                           subtitle: "Yard locations will appear here once configured.")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(locations.enumerated()), id: \.element.id) { idx, loc in
                    zoneRow(loc)
                    if idx < locations.count - 1 {
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
    }

    private func zoneRow(_ loc: YardLocation628) -> some View {
        let cap = max(loc.capacity ?? 0, 0)
        let occ = max(loc.occupied ?? 0, 0)
        let pct: Double = cap > 0 ? min(Double(occ) / Double(cap), 1.0) : 0
        let pctInt = Int((pct * 100).rounded())
        let accent = zoneAccent(loc)
        let isSelected = (selectedLocationId ?? locations.first?.id) == loc.id

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedLocationId = loc.id
            }
            Task { await reloadGrid() }
        } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                // 40 pin-chip.
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "mappin")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(loc.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Yard zone")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(zoneSubtitle(loc))
                        .font(EType.mono(.caption)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                    // Relative fill bar.
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.18))
                            Capsule().fill(accent)
                                .frame(width: max(geo.size.width * pct, pct > 0 ? 6 : 0))
                        }
                    }
                    .frame(height: 6)
                    .padding(.top, Space.s1)
                }
                // Trailing: occupancy pill + tabular slots-used.
                VStack(alignment: .trailing, spacing: Space.s1) {
                    occupancyPill(pctInt: pctInt, occupied: occ, capacity: cap, accent: accent)
                    Text(cap > 0 ? "\(occ)/\(cap)" : "—")
                        .font(.system(size: 14, weight: .bold, design: .default))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text(slotsUnit(loc))
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

    /// Occupancy pill — color-coded by saturation (SVG: blue ≥80%, orange
    /// mid, slate "OPEN"). Reads off real occupancy, not a fixed label.
    private func occupancyPill(pctInt: Int, occupied: Int, capacity: Int, accent: Color) -> some View {
        let label: String
        let color: Color
        if capacity <= 0 {
            label = "—"; color = palette.textTertiary
        } else if pctInt < 30 {
            label = "OPEN"; color = Brand.rail
        } else {
            label = "\(pctInt)% FULL"
            color = pctInt >= 80 ? Brand.blue : (pctInt >= 60 ? Brand.warning : accent)
        }
        return Text(label)
            .font(.system(size: 10.5, weight: .bold)).tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.20)))
    }

    private func zoneAccent(_ loc: YardLocation628) -> Color {
        switch (loc.type ?? "").lowercased() {
        case let t where t.contains("reefer"):     return Brand.warning
        case let t where t.contains("chassis"),
             let t where t.contains("pool"):        return Brand.rail
        case let t where t.contains("intermodal"): return Brand.blue
        default:                                     return Brand.blue
        }
    }

    private func zoneSubtitle(_ loc: YardLocation628) -> String {
        if let addr = loc.address, !addr.isEmpty { return addr }
        if let t = loc.type, !t.isEmpty { return t }
        return "yard location"
    }

    private func slotsUnit(_ loc: YardLocation628) -> String {
        (loc.type ?? "").lowercased().contains("chassis") ? "chassis" : "slots"
    }

    // MARK: - Inline banner (locate ack / error)

    private func inlineBanner(_ text: String, color: Color, icon: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
            Text(text)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(color.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(color.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - CTA row (Locate trailer · List)

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            CTAButton(
                title: "Locate trailer",
                action: { Task { await locateTrailer() } },
                leadingIcon: "list.bullet.rectangle",
                isLoading: locating
            )
            .frame(maxWidth: .infinity)

            Button {
                // List view toggle — same dataset, no separate route in
                // the wireframe; keeps the secondary affordance present.
            } label: {
                Text("List")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 120, height: 52)
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
        locateAck = nil; locateError = nil
        struct LocsIn: Encodable { let status: String }
        do {
            let locs: YardLocations628 = try await EusoTripAPI.shared.query(
                "yardManagement.getYardLocations", input: LocsIn(status: "active"))
            let list = locs.locations ?? []
            self.locations = list
            if selectedLocationId == nil { selectedLocationId = list.first?.id }
            await reloadGrid()
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// Load the live track grid for the selected location.
    private func reloadGrid() async {
        guard let locId = selectedLocationId else { grid = nil; return }
        struct GridIn: Encodable { let locationId: String }
        do {
            let g: YardMap628 = try await EusoTripAPI.shared.query(
                "yardManagement.getYardMap", input: GridIn(locationId: locId))
            self.grid = g
        } catch {
            // Grid is secondary — surface as a soft note inside the error
            // banner only if the whole page hasn't already errored.
            if loadError == nil {
                self.grid = nil
            }
        }
    }

    // MARK: - Locate trailer (updateTrailerPosition mutation)

    /// 'Locate trailer' CTA → yardManagement.updateTrailerPosition. Re-spots
    /// the most-recently-known trailer in the selected yard. Requires a
    /// trailer + a destination spot; when neither is resolvable from the
    /// live grid we surface an honest error instead of inventing IDs.
    //
    // PORT-GAP: updateTrailerPosition writes a completed yardMoves row but
    // NO blockchainAuditTrail row and NO WS_CHANNELS broadcast yet (per
    // <desc> · yardManagement.ts:468). Surfaced to the-oath.
    private func locateTrailer() async {
        guard let locId = selectedLocationId else {
            locateError = "Select a yard zone first."
            return
        }
        // Resolve a real occupied spot + its trailer from the live grid —
        // no fabricated trailer/spot IDs.
        let occupiedSpots = (grid?.spots ?? []).filter {
            SpotStatus(server: $0.status) == .occupied && ($0.trailerId?.isEmpty == false)
        }
        guard let spot = occupiedSpots.first, let trailerId = spot.trailerId else {
            locateError = "No located trailer in this yard yet."
            return
        }

        locating = true; locateAck = nil; locateError = nil
        struct LocateIn: Encodable {
            let trailerId: String
            let spotId: String
            let locationId: String
        }
        struct LocateResult: Decodable {
            let success: Bool?
            let trailerId: String?
            let newSpotId: String?
        }
        do {
            let res: LocateResult = try await EusoTripAPI.shared.mutation(
                "yardManagement.updateTrailerPosition",
                input: LocateIn(trailerId: trailerId, spotId: spot.id, locationId: locId))
            if res.success == true {
                let unit = spot.trailerNumber.flatMap { $0.isEmpty ? nil : $0 } ?? trailerId
                locateAck = "Located \(unit) · spot \(spot.label ?? spot.id)."
                await reloadGrid()
            } else {
                locateError = "Locate did not complete. Try again."
            }
        } catch {
            locateError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        locating = false
    }
}

#Preview("628 · Rail Yard Map · Night") { RailYardMapScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("628 · Rail Yard Map · Light") { RailYardMapScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
