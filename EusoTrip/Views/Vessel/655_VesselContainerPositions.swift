//
//  655_VesselContainerPositions.swift
//  EusoTrip — Vessel Operator · Container Positions (carrier vantage).
//
//  Fleet-level container view drilled from the SHIPMENTS tab — distinct from
//  the per-booking container roster on 653. Verbatim port of
//  "655 Vessel Container Positions.svg" (Light + Dark). Nav anchored to
//  VesselOperatorNavController.swift; Shipments tab current (filled symbol).
//  Data shape mirrors vesselShipments.getContainerPositions → { containers, total }
//  (server/routers/vesselShipments.ts:1404).
//
//  ── POSITION-FEED SEAM (2026-06-05) ─────────────────────────────────────────
//  The screen wants a container *map*. The proc (`vesselShipments.getContainerPositions`,
//  bare `db.select().from(shippingContainers)`) ships every column of the
//  `shipping_containers` row, which INCLUDES the two real coordinate carriers:
//      • `currentLocation`  JSON {lat,lng}  ← written by the position feed
//      • `currentPortId`    int FK → ports.unlocode → PortDirectory coord
//  The DB schema has both columns, but the populating feed (Vizion / MarineTraffic
//  AIS → writes `currentLocation`) is NOT wired: in prod ALL container rows carry
//  `currentLocation = NULL` and `currentPortId = NULL` (verified 50/50). The
//  iOS-resolvable coord path is the `currentLocation` JSON the proc already
//  returns (PortDirectory needs an UN/LOCODE string, which the bare proc does
//  not join — so the secondary `currentPortUnlocode` path lights up only once the
//  proc surfaces that column; no client id→unlocode guess is made).
//
//  This is therefore an HONEST env-gated SEAM, not a wire and not a skip:
//  the ocean map + the full decode path are in place. Each container is coord-
//  gated (`!(lat==0 && lng==0)`, the Driver 013 / Catalyst 301 pattern); only
//  containers carrying a REAL fix become `.markers` on the `.ocean`
//  `BespokeMapCanvas`. When zero containers carry a fix, the map slot renders an
//  explicit "awaiting position feed" state — NO fabricated coordinates. The
//  moment the feed populates `currentLocation` (or the proc joins the port
//  UN/LOCODE), the pins light up with zero further client work.
//

import SwiftUI

struct VesselContainerPositionsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselContainerPositionsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                  isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
        // Real top back affordance (replaces the old decorative chevron in
        // the body header). Fixed leading slot → never overlaps the title;
        // posts the shared NavBack the VesselOperatorSurface pops on.
        .injectBespokeBackBar(title: nil) {
            NotificationCenter.default.post(name: .eusoRoleNavBack, object: nil)
        }
    }
}

// MARK: - Data shape (mirror shippingContainers row)

/// The `currentLocation` JSON the proc ships verbatim from the
/// `shipping_containers` row. Canonical `{lat,lng}` shape (the same shape
/// vehicles/loads/users use across the codebase). Optional + null-island
/// gated so a legacy row that predates the position feed never frames the
/// map on (0,0).
private struct ContainerLocationGeo: Decodable, Hashable {
    let lat: Double?
    let lng: Double?
}

private struct OceanContainerPos: Decodable, Identifiable {
    let id: Int
    let containerNumber: String?
    let containerType: String?
    let status: String?         // at_port | on_board | on_water | discharged | gate_out
    let location: String?
    let imdgClass: String?
    let isReefer: Bool?
    // ── Real coordinate carriers shipped by the proc's bare row select ──
    // `currentLocation` is the live position feed's {lat,lng} write.
    // `currentPortUnlocode` lights up only if the proc joins ports.unlocode
    // (PortDirectory resolves it to a coord); the client never guesses it
    // from the raw `currentPortId` int.
    let currentLocation: ContainerLocationGeo?
    let currentPortUnlocode: String?

    // ── Real stow-position carriers (Wave A2 — 655 stow geometry) ──
    // The bay-plan elevation may only place a container in a bay the
    // server actually assigned. Two wire shapes are decoded end-to-end:
    //   • discrete `bayNumber` / `rowNumber` / `tierNumber` columns, or
    //   • an ISO 9711 `stowPosition` "BBBRRTT" string (bay-row-tier).
    // Until the stow-position fields land on `shipping_containers`, all
    // four stay nil and the elevation renders the honest "awaiting stow
    // plan" seam — never the prior synthetic `i % bayCount` spread.
    let bayNumber: Int?
    let rowNumber: Int?
    let tierNumber: Int?
    let stowPosition: String?

    /// ISO 9711 split of `stowPosition` ("0340682" / "340682" →
    /// bay 34, row 06, tier 82). Returns nil unless the string is a
    /// clean 6–7 digit code.
    private var iso9711: (bay: Int, row: Int, tier: Int)? {
        guard let raw = stowPosition?.trimmingCharacters(in: .whitespaces),
              raw.count == 6 || raw.count == 7,
              raw.allSatisfy(\.isNumber) else { return nil }
        let padded = raw.count == 6 ? "0" + raw : raw
        guard let bay = Int(padded.prefix(3)),
              let row = Int(padded.dropFirst(3).prefix(2)),
              let tier = Int(padded.suffix(2)) else { return nil }
        return (bay, row, tier)
    }

    /// The REAL bay this container is stowed in, or nil when the server
    /// hasn't assigned one. Discrete column wins; ISO string second.
    var resolvedBay: Int? { bayNumber ?? iso9711?.bay }
    /// The REAL tier, when assigned. ISO 9711: deck tiers run 72+,
    /// hold tiers below — drives the ON DECK / IN HOLD band split.
    var resolvedTier: Int? { tierNumber ?? iso9711?.tier }

    /// A REAL, non-null-island fix for this container or nil. Primary path:
    /// the `currentLocation` JSON. Secondary path: the at-berth port's
    /// UN/LOCODE resolved through the in-house `PortDirectory` catalog
    /// (cheat-sheet §B1) — never a fabricated point.
    var fix: HereLatLng? {
        if let lat = currentLocation?.lat, let lng = currentLocation?.lng,
           !(lat == 0 && lng == 0) {
            return HereLatLng(lat, lng)
        }
        if let code = currentPortUnlocode, !code.isEmpty,
           let p = PortDirectory.find(unlocode: code),
           !(p.lat == 0 && p.lng == 0) {
            return HereLatLng(p.lat, p.lng)
        }
        return nil
    }

    /// Ocean-register pin kind by lifecycle: a moving container (on the water)
    /// reads as the en-route puck; everything else reads as a hollow port pin.
    var markerKind: HereMarker.Kind {
        switch (status ?? "").lowercased() {
        case "on_board", "on_water", "in_transit": return .truck
        default: return .pickup
        }
    }
}

private struct ContainerPositionsResponse: Decodable {
    let containers: [OceanContainerPos]
    let total: Int
}

// MARK: - Body

private struct VesselContainerPositionsBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @State private var containers: [OceanContainerPos] = []
    @State private var total = 0
    @State private var loading = true
    @State private var loadError: String? = nil

    private var onBoard: Int  { containers.filter { ($0.status ?? "") == "on_board" || ($0.status ?? "") == "on_water" }.count }
    private var atPort: Int   { containers.filter { ($0.status ?? "") == "at_port" }.count }
    private var hazmat: Int   { containers.filter { $0.imdgClass != nil }.count }

    // MARK: Position-feed projection (REAL coords only)
    //
    // Only containers carrying a real `fix` (currentLocation JSON or an
    // at-berth port UN/LOCODE resolved via PortDirectory) become markers. The
    // count gates the whole map slot: zero fixes ⇒ the "awaiting feed" state,
    // never a synthetic point.
    private var positioned: [OceanContainerPos] { containers.filter { $0.fix != nil } }

    private var positionMarkers: [HereMarker] {
        positioned.compactMap { c in
            guard let fix = c.fix else { return nil }
            return HereMarker(
                at: fix,
                kind: c.markerKind,
                label: c.containerNumber ?? "CTR",
                id: String(c.id)
            )
        }
    }

    /// Camera center = the centroid of the real fixes (no fix ⇒ nil ⇒ the
    /// map slot is not drawn at all; we show the seam state instead). Mid-
    /// ocean Atlantic basin is never assumed — the center is derived purely
    /// from the points we actually have.
    private var positionCenter: HereLatLng? {
        let fixes = positioned.compactMap { $0.fix }
        guard !fixes.isEmpty else { return nil }
        let lat = fixes.map(\.lat).reduce(0, +) / Double(fixes.count)
        let lng = fixes.map(\.lng).reduce(0, +) / Double(fixes.count)
        return HereLatLng(lat, lng)
    }

    // MARK: Bay-plan elevation model (REAL stow positions only — Wave A2)
    //
    // 2026-06-10 de-fabrication: the prior `i % bayCount` bucketing painted
    // containers into bays the server never assigned — synthetic stow
    // geometry wearing a real bay plan's clothes. The elevation now renders
    // ONLY containers carrying a real stow position (discrete bay/tier
    // columns or an ISO 9711 `stowPosition` code), grouped by their TRUE
    // bay. When zero containers carry stow data the slot renders an honest
    // "awaiting stow plan" seam card — same pattern as the position-feed
    // seam above. Slot kinds stay real: restow/relocation status → .restow,
    // imdgClass → .hazmat, isReefer → .reefer, else .dry.
    private func slotKind(for c: OceanContainerPos) -> BayPlanSlot.Kind {
        let status = (c.status ?? "").lowercased()
        if status.contains("restow") || status.contains("relocat") { return .restow }
        if c.imdgClass != nil { return .hazmat }
        if c.isReefer == true { return .reefer }
        return .dry
    }

    /// Containers the server has actually stowed (real bay assignment).
    private var stowed: [OceanContainerPos] { containers.filter { $0.resolvedBay != nil } }

    private var bayColumns: [BayColumn] {
        let stowedNow = stowed
        guard !stowedNow.isEmpty else { return [] }

        // Group by the REAL bay, displayed descending fore→aft like a real
        // bay plan header strip.
        let byBay = Dictionary(grouping: stowedNow, by: { $0.resolvedBay! })
        let bays = byBay.keys.sorted(by: >)

        return bays.map { bay in
            let group = byBay[bay] ?? []
            var onDeck: [BayPlanSlot] = []
            var inHold: [BayPlanSlot] = []
            // Stack order: highest tier outermost in each band.
            for c in group.sorted(by: { ($0.resolvedTier ?? 0) > ($1.resolvedTier ?? 0) }) {
                let kind = slotKind(for: c)
                let band: Bool = {
                    // ISO 9711 tier truth wins: deck tiers run 72 and up.
                    if let tier = c.resolvedTier { return tier >= 72 }
                    // No tier on the wire — band by the real load status.
                    let status = (c.status ?? "").lowercased()
                    return status == "on_board" || status == "on_water"
                }()
                if band { onDeck.append(BayPlanSlot(kind)) }
                else    { inHold.append(BayPlanSlot(kind)) }
            }
            // Pad to at least one tier per band with open (.empty) cells so
            // the hull/hatch geometry reads cleanly even for sparse bays.
            if onDeck.isEmpty { onDeck = [BayPlanSlot(.empty)] }
            if inHold.isEmpty { inHold = [BayPlanSlot(.empty)] }
            return BayColumn(bayNumber: bay, onDeck: onDeck, inHold: inHold)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading containers…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if containers.isEmpty {
                    EusoEmptyState(systemImage: "shippingbox", title: "No containers",
                                   subtitle: "Tracked containers will appear here.")
                } else {
                    summaryTiles
                    positionMapSection
                    stowElevationSection
                    Text("CONTAINERS · live positions")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    VStack(spacing: Space.s2) { ForEach(containers) { containerRow($0) } }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · CONTAINERS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Container positions").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("\(total) containers tracked · ISO 6346").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var summaryTiles: some View {
        HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "ON BOARD", value: "\(onBoard)", icon: "ferry.fill")
            LifecycleStatTile(label: "AT PORT",  value: "\(atPort)",  icon: "building.columns")
            LifecycleStatTile(label: "HAZMAT",   value: "\(hazmat)",  icon: "exclamationmark.triangle",
                              danger: hazmat > 0)
        }
    }

    // MARK: Position map (ocean register) — REAL fixes only, else seam state
    //
    // VESSEL mode ⇒ the `.ocean` cartography register (hollow port pins, AIS
    // orb, latitude grid) per the canonical Vessel 003 surface. The map is only
    // mounted when at least one container carries a real fix; otherwise the slot
    // honestly states the position feed has not landed (no synthetic points).
    @ViewBuilder private var positionMapSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("POSITIONS · live feed")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            if let center = positionCenter {
                HereVectorMapView(
                    center: center,
                    zoom: 3,
                    interactive: true,
                    tilt: 0,
                    layers: [.markers(positionMarkers)],
                    styleHint: .ocean
                )
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                Text("\(positioned.count) of \(containers.count) containers reporting a position")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            } else {
                awaitingFeedCard
            }
        }
    }

    // MARK: Stow elevation — REAL bays only, else the honest seam

    @ViewBuilder private var stowElevationSection: some View {
        if !bayColumns.isEmpty {
            BayPlanStowElevation(columns: bayColumns)
            Text("\(stowed.count) of \(containers.count) containers carry a stow position")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        } else {
            awaitingStowPlanCard
        }
    }

    /// Honest "awaiting stow plan" state — the elevation + ISO 9711 decode
    /// path are wired end-to-end, but no container row carries a real bay/
    /// tier assignment yet, so we say exactly that rather than painting
    /// containers into invented bays (the retired `i % bayCount` spread).
    private var awaitingStowPlanCard: some View {
        VStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCard)
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.3x3.middle.filled")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("Awaiting stow plan")
                        .font(.system(size: 14, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    Text("The bay-plan elevation draws itself from real bay/row/tier stow positions (ISO 9711). None of the \(containers.count) tracked containers carry a stow assignment yet - no bay geometry is invented in the meantime.")
                        .font(EType.caption).multilineTextAlignment(.center)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, Space.s4)
                }
                .padding(Space.s4)
            }
            .frame(height: 180)
        }
    }

    /// Honest "awaiting position feed" state — the map + decode path are wired,
    /// but no container row carries a real `currentLocation`/port fix yet, so we
    /// show exactly that rather than inventing coordinates.
    private var awaitingFeedCard: some View {
        VStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCard)
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                VStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.up.forward")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("Awaiting position feed")
                        .font(.system(size: 14, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    Text("Container fixes light up here the moment the AIS / carrier position feed reports a location. None of the \(containers.count) tracked containers carry coordinates yet.")
                        .font(EType.caption).multilineTextAlignment(.center)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, Space.s4)
                }
                .padding(Space.s4)
            }
            .frame(height: 200)
        }
    }

    private func containerRow(_ c: OceanContainerPos) -> some View {
        let (label, tone): (String, Color) = {
            if c.imdgClass != nil { return ("HAZMAT", Brand.warning) }
            if c.isReefer == true { return ("REEFER", Brand.info) }
            switch (c.status ?? "") {
            case "on_board":   return ("ON BOARD", Brand.info)
            case "on_water":   return ("ON WATER", Brand.info)
            case "discharged": return ("DISCH.",   Brand.success)
            case "at_port":    return ("AT PORT",  palette.textTertiary)
            default:           return ((c.status ?? "-").uppercased(), palette.textSecondary)
            }
        }()
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(c.containerNumber ?? "-")\(c.containerType.map { " · \($0)" } ?? "")")
                    .font(.system(size: 13, weight: .semibold)).monospaced().foregroundStyle(palette.textPrimary)
                Text(c.location ?? "-").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            // A discreet "on map" dot when this container is actually pinned, so
            // the roster ties back to the position layer truthfully.
            if c.fix != nil {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.info)
            }
            Text(label).font(.system(size: 8.5, weight: .heavy)).tracking(0.5).foregroundStyle(tone)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(tone.opacity(0.16)).clipShape(Capsule())
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func load() async {
        loading = true; loadError = nil
        struct PosIn: Encodable { let limit: Int }
        do {
            let result: ContainerPositionsResponse = try await EusoTripAPI.shared.query(
                "vesselShipments.getContainerPositions", input: PosIn(limit: 100))
            self.containers = result.containers
            self.total = result.total
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }
}

#Preview("655 · Vessel Container Positions · Night") { VesselContainerPositionsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("655 · Vessel Container Positions · Light") { VesselContainerPositionsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
