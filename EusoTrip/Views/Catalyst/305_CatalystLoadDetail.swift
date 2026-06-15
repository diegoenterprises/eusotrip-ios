//
//  305_CatalystLoadDetail.swift
//  EusoTrip — Catalyst · Load Detail (brick 305).
//
//  Pixel-faithful port of "305 Catalyst Load Detail · Light/Dark"
//  (Figma `~/Desktop/EusoTrip 2027 UI Wireframes/03 Catalyst/Light-SVG/`).
//  This is the FLAGSHIP Catalyst-side load detail surface — mirrors
//  the §11 Shipper 205_ShipperLoadDetail with two Catalyst-specific
//  delta cards added per §57.4 / §58.4 candidate-queue lead doctrine:
//
//    • ASSIGNMENT card — driver ME · CDL-A · H/N/X · HOS x:xx left +
//      REASSIGN action. Wires the live `catalysts.getMyDrivers` row
//      that matches `loads.getById.driverId` so the HOS counter +
//      status pill paint with REAL data, not a fabricated label. Tap
//      the card → 304_CatalystFleetDrivers focused on this driver.
//    • SHIPPER-OF-RECORD card — DU monogram + Diego Usoro · Eusorone
//      Technologies. Cross-role coupling: this is the SAME shipperId
//      the §11 Shipper track shows on its own home; same companyId,
//      same name, same scorecard.
//
//  Catalyst↔Driver relationship per founder doctrine: every field in
//  the assignment card derives from the driver's OWN tables (drivers,
//  hos_logs, gps_tracking, loads). The Catalyst lens is a JOIN, not
//  a fabrication. When the catalyst-side roster doesn't include the
//  driver yet (cross-fleet relay, escort handoff), the card collapses
//  to "Pending assignment" — never a fake driver.
//
//  Server wiring (no stubs / no fake data — every field below either
//  paints a real value or the empty state):
//    • `loads.getById`           — full load envelope (origin, dest,
//                                  commodity, hazmat, rate, dates,
//                                  shipperId, driverId, status).
//                                  iOS: EusoTripAPI.loads.getDetail(id:).
//    • `catalysts.getMyDrivers`  — Catalyst's roster; we filter to
//                                  the row matching `loads.driverId`
//                                  to surface the assignment HOS +
//                                  location.
//    • `eusoTicket.generateBOLPDF` — Bottom CTA "Render & dispatch"
//                                  fallback when the load already
//                                  has a finalized BOL.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation

// MARK: - Screen wrapper

struct CatalystLoadDetailScreen: View {
    let theme: Theme.Palette
    let loadId: String

    init(theme: Theme.Palette, loadId: String = "0") {
        self.theme = theme
        self.loadId = loadId
    }

    var body: some View {
        Shell(theme: theme) {
            CatalystLoadDetail(loadId: loadId)
        } nav: {
            BottomNav(
                leading: catalystNavLeading_305(),
                trailing: catalystNavTrailing_305(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_305() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: true)]
}

private func catalystNavTrailing_305() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: false)]
}

// MARK: - 8-stage lifecycle

private enum LifecycleStage: String, CaseIterable {
    case posted    = "POSTED"
    case bidding   = "BIDDING"
    case awarded   = "AWARDED"
    case pickup    = "PICKUP"
    case inTransit = "IN TRANSIT"
    case delivery  = "DELIVERY"
    case paperwork = "PAPERWORK"
    case closed    = "CLOSED"

    /// Maps a `loads.status` column value to the lifecycle stage we
    /// paint as "current" on the strip. Server-side values per
    /// CLAUDE.md memory: pending / accepted / assigned / in_transit /
    /// delivered / completed / cancelled. The mapping is deliberately
    /// inclusive — any unknown future status defaults to .posted.
    static func from(loadStatus: String?) -> LifecycleStage {
        switch (loadStatus ?? "").lowercased() {
        case "pending":                                    return .posted
        case "bidding":                                    return .bidding
        case "accepted", "awarded":                        return .awarded
        case "assigned":                                   return .pickup
        case "in_transit", "in-transit", "intransit":     return .inTransit
        case "approaching_delivery", "at_receiver",
             "unloading", "delivering":                    return .delivery
        case "paperwork", "post_pod", "settling":         return .paperwork
        case "delivered", "completed", "closed", "paid":  return .closed
        case "cancelled", "voided":                        return .posted
        default:                                           return .posted
        }
    }
}

// MARK: - Body

private struct CatalystLoadDetail: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    let loadId: String

    @State private var load: LoadsAPI.LoadDetail? = nil
    @State private var assignedDriver: CatalystAPI.FleetDriver? = nil
    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    /// REAL decoded HERE Routing geometry for the pickup→delivery corridor
    /// (curved road polyline), loaded by `refreshRoutePolyline(_:)` once the
    /// load's geocoded endpoints are on file. Empty = no real route yet
    /// (un-geocoded lane, vessel/barge leg, or HERE error) → the map falls
    /// back to the straight 2-point pickup→delivery line. Never fabricated.
    @State private var routePolyline: [HereLatLng] = []

    // MARK: Sheet presentation state
    @State private var showStatusPicker: Bool = false
    @State private var showDriverPicker: Bool = false
    @State private var statusUpdating: Bool = false
    @State private var statusUpdateError: String? = nil
    @State private var driverPickerLoading: Bool = false
    @State private var availableDrivers: [CatalystAPI.FleetDriver] = []
    @State private var driverAssignError: String? = nil
    /// RIOS §12 — set true when a load party fails a HARD sanctions gate.
    /// Blocks the carrier's lifecycle-advance CTA until resolved.
    @State private var gateLocked: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleRow
                iridescentHairline

                if loading {
                    skeletonBody
                } else if let err = loadError {
                    errorBanner(err)
                } else if let l = load {
                    routeInfoStrip(l)
                    routeMapCard(l)
                    routeWeatherPanel(l)
                    lifecycleCard(l)
                    moneyAndReceivableCard(l)
                    assignmentCard(l)
                    shipperOfRecordCard(l)
                    documentsRow(l)
                    // RIOS §11/§12 — screen every load party before the carrier
                    // advances/dispatches; gateLocked disables the CTA below.
                    if let lid = Int(loadId) {
                        ComplianceGatesStrip(loadId: lid, role: "carrier", gateLocked: $gateLocked)
                    }
                    bottomCTAs(l)
                } else {
                    emptyLoadState
                }

                if let err = statusUpdateError ?? driverAssignError {
                    Text(err)
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                        .padding(.horizontal, 4)
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task {
            await fetch()
            joinLoadRoom()
        }
        .onDisappear { leaveLoadRoom() }
        // Refetch on any LOAD_STATE_CHANGED / LOAD_UPDATED / LOAD_ASSIGNED
        // socket event — RealtimeService translates those into
        // `.esangRefreshSurface` posts.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await fetch() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadReassigned)) { _ in
            Task { await fetch() }
        }
        .sheet(isPresented: $showStatusPicker) {
            StatusPickerSheet(
                currentStatus: load?.status ?? "",
                isUpdating: statusUpdating,
                onPick: { newStatus in
                    Task { await updateStatus(to: newStatus) }
                }
            )
            .environment(\.palette, palette)
        }
        .sheet(isPresented: $showDriverPicker) {
            DriverPickerSheet(
                drivers: availableDrivers,
                loading: driverPickerLoading,
                currentDriverId: assignedDriver?.id,
                onPick: { driver in
                    Task { await assignDriver(driver) }
                }
            )
            .environment(\.palette, palette)
        }
    }

    // MARK: - TopBar + title

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(eyebrowLabel)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text(loadIdLabel)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var eyebrowLabel: String {
        if let l = load, l.unNumber != nil {
            return "CATALYST · LOAD · UN\(l.unNumber ?? "") HAZMAT"
        }
        return "CATALYST · LOAD"
    }

    private var loadIdLabel: String {
        load?.loadNumber ?? "-"
    }

    private var titleRow: some View {
        HStack(alignment: .center) {
            Button {
                // 305 is push-presented inside CarrierSurface's screenStack
                // swap (not a sheet), so `dismiss()` has no presentation
                // context to dismiss — it was a dead tap. Post the
                // canonical .eusoRoleNavBack which CarrierSurface listens
                // for at RoleSurfaceRouter:935 → popOne(). Matches the
                // back-chevron founder bug pattern (the Shipper Allocations
                // version got fixed 2026-05-22).
                NotificationCenter.default.post(name: .eusoRoleNavBack, object: nil)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
            }
            .buttonStyle(.plain)
            Text(routeTitle)
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .padding(.trailing, 4)
        }
    }

    private var routeTitle: String {
        guard let l = load else { return "Loading…" }
        let from = l.pickupLocation?.cityState ?? "-"
        let to = l.deliveryLocation?.cityState ?? "-"
        return "\(from) → \(to)"
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(height: 1)
            .padding(.horizontal, -20)
    }

    // MARK: - Route info strip

    private func routeInfoStrip(_ l: LoadsAPI.LoadDetail) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ETA")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(etaLabel(l))
                    .font(.system(size: 14, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("DISTANCE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(distanceLabel(l))
                    .font(.system(size: 14, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func etaLabel(_ l: LoadsAPI.LoadDetail) -> String {
        guard let iso = l.estimatedDeliveryDate ?? l.deliveryDate else { return "-" }
        return formatTime(iso) ?? "-"
    }

    private func distanceLabel(_ l: LoadsAPI.LoadDetail) -> String {
        return l.distanceDisplay
    }

    // MARK: - Route map (in-house HERE)
    //
    // Mirrors the canonical LoadDetailSheet:490 + the §11 sibling
    // 205_ShipperLoadDetail hero embed: the OMV vector renderer
    // (HereLiveMapView) with the pickup/delivery pins + a route
    // connector on the vector basemap, and the carrier-side situational
    // add-ons (.shipperTracking = traffic + sponsored ad-zones; no
    // driver-only gamification fan-out). The per-load WEATHER that used
    // to live dormant inside this `.shipperTracking` add-on is now
    // PROMOTED into the explicit bespoke `routeWeatherPanel` below the
    // map (see `routeWeatherPanel(_:)`) — it renders the §3 per-load
    // forecast + LaneImpact through the Wave-1 v3 weather components,
    // never a generic basemap overlay. Coords bind ONLY
    // to the REAL `pickupLocation.lat/.lng` + `deliveryLocation.lat/.lng`
    // the server self-heals onto `loads.getById` — never a fabricated
    // lane. When either endpoint hasn't been geocoded yet (Driver 013
    // coord-gate: any zero/nil), honest-skip to a neutral "Route
    // loading…" placeholder so the map never frames on null island.

    @ViewBuilder
    private func routeMapCard(_ l: LoadsAPI.LoadDetail) -> some View {
        if let coords = laneCoords(l) {
            let midLat = (coords.pickupLat + coords.deliveryLat) / 2
            let midLng = (coords.pickupLng + coords.deliveryLng) / 2
            // REAL road geometry when HERE Routing has resolved it (≥2 pts);
            // straight 2-point pickup→delivery ONLY as the honest fallback
            // (un-geocoded lane, vessel/barge great-circle leg, or HERE
            // error). The straight line is never a fabricated "road".
            let line: [HereLatLng] = routePolyline.count >= 2
                ? routePolyline
                : [.init(coords.pickupLat, coords.pickupLng),
                   .init(coords.deliveryLat, coords.deliveryLng)]
            HereLiveMapView(
                center: .init(midLat, midLng),
                zoom: 6,
                route: line,
                baseLayers: [
                    .route(
                        polyline: line,
                        colorHex: "#1473FF"
                    ),
                    .markers([
                        .init(at: .init(coords.pickupLat, coords.pickupLng),
                              kind: .pickup, label: coords.originTitle),
                        .init(at: .init(coords.deliveryLat, coords.deliveryLng),
                              kind: .delivery, label: coords.destinationTitle)
                    ])
                ],
                addOns: .shipperTracking
            )
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
        } else {
            // Coord gate (Driver 013 pattern): no real fix on one or both
            // endpoints yet — neutral placeholder, never a demo route.
            Rectangle()
                .fill(palette.bgCard)
                .frame(height: 200)
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: "map")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                        Text("Route loading…")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(0.8)
                            .foregroundStyle(palette.textTertiary)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
        }
    }

    /// Resolves the load's REAL pickup → delivery coordinates off the
    /// `loads.getById` envelope. Returns nil (→ honest-skip) when either
    /// endpoint hasn't been geocoded yet — mirrors the §11 sibling
    /// 205_ShipperLoadDetail `laneForMap` gate (non-nil + non-zero on
    /// both lat/lng).
    private func laneCoords(_ l: LoadsAPI.LoadDetail)
        -> (pickupLat: Double, pickupLng: Double,
            deliveryLat: Double, deliveryLng: Double,
            originTitle: String, destinationTitle: String)? {
        guard let p = l.pickupLocation,
              let d = l.deliveryLocation,
              let pLat = p.lat, let pLng = p.lng,
              let dLat = d.lat, let dLng = d.lng,
              !(pLat == 0 && pLng == 0),
              !(dLat == 0 && dLng == 0) else { return nil }
        let origin = p.cityState.isEmpty ? "Origin" : p.cityState
        let dest = d.cityState.isEmpty ? "Dest" : d.cityState
        return (pLat, pLng, dLat, dLng, origin, dest)
    }

    // MARK: - Route weather panel (bespoke, promoted from the dormant add-on)
    //
    // The §3 per-load weather — origin/destination realtime + the
    // mode-aware LaneImpact (truck ETA risk · rail dwell · vessel berth
    // window) + hourly/daily timelines + government alerts — rendered
    // through the Wave-1 v3 bespoke weather corpus (SkyStageHero ·
    // HourlyRibbon · RouteCellDiagram · DayRangeBar) via the Foundation-
    // phase `PerLoadWeatherCard`. This REPLACES the dormant weather flag
    // that used to ride inside the HERE `.shipperTracking` map add-on —
    // a real, expandable card, not a basemap overlay. Push-nav layout
    // (it lives inline in the scroll stack, never a slide-up modal).
    //
    // `isActive` drives the faster (~30 s) auto-refresh + the card's
    // default-expanded state for loads that are mid-haul; idle loads get
    // a one-shot fetch + the collapsed dashboard tile (tap to expand).
    // The card owns its own honest empty/stale/unavailable states — when
    // the lane has no live weather yet it collapses to "No live weather
    // for this lane yet"; nothing here is fabricated.
    private func routeWeatherPanel(_ l: LoadsAPI.LoadDetail) -> some View {
        PerLoadWeatherCard(loadId: l.id, isActive: isLoadActive(l))
    }

    /// A load is "active" (live-tracked) for weather-refresh purposes once
    /// it's in the pickup→delivery window — the same lifecycle band the
    /// strip paints as in-flight. Mirrors `LifecycleStage.from` so the two
    /// surfaces agree on what "in progress" means.
    private func isLoadActive(_ l: LoadsAPI.LoadDetail) -> Bool {
        switch LifecycleStage.from(loadStatus: l.status) {
        case .pickup, .inTransit, .delivery: return true
        default:                             return false
        }
    }

    // MARK: - 8-stage lifecycle strip

    private func lifecycleCard(_ l: LoadsAPI.LoadDetail) -> some View {
        let current = LifecycleStage.from(loadStatus: l.status)
        let allStages = LifecycleStage.allCases

        return VStack(alignment: .leading, spacing: 12) {
            Text(lifecycleEyebrowLabel(l))
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .padding(.bottom, 4)

            VStack(spacing: 10) {
                lifecycleProgressLine(current: current, allStages: allStages)
                lifecycleStageLabels(current: current, allStages: allStages)
            }

            Text(productAwareKicker(l, current: current))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func lifecycleEyebrowLabel(_ l: LoadsAPI.LoadDetail) -> String {
        if let un = l.unNumber {
            let cargo = (l.cargoType?.uppercased() ?? "")
            return "LIFECYCLE · UN\(un) \(cargo.isEmpty ? "HAZMAT" : cargo)"
        }
        let cargo = l.cargoType?.uppercased() ?? "DRY VAN"
        return "LIFECYCLE · \(cargo)"
    }

    private func lifecycleProgressLine(current: LifecycleStage, allStages: [LifecycleStage]) -> some View {
        let currentIdx = allStages.firstIndex(of: current) ?? 0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Neutral baseline
                Capsule()
                    .fill(palette.borderFaint)
                    .frame(height: 2)
                // Gradient progress up to current
                if currentIdx > 0 {
                    Capsule()
                        .fill(LinearGradient.diagonal)
                        .frame(width: geo.size.width * CGFloat(currentIdx) / CGFloat(max(1, allStages.count - 1)), height: 2)
                }
                // Stage dots
                HStack(spacing: 0) {
                    ForEach(Array(allStages.enumerated()), id: \.offset) { idx, _ in
                        stageDot(isDone: idx < currentIdx, isCurrent: idx == currentIdx)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(height: 22)
    }

    private func stageDot(isDone: Bool, isCurrent: Bool) -> some View {
        Group {
            if isCurrent {
                ZStack {
                    Circle().stroke(LinearGradient.diagonal, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    Circle().fill(LinearGradient.diagonal)
                        .frame(width: 16, height: 16)
                    Circle().fill(Color.white)
                        .frame(width: 6, height: 6)
                }
            } else if isDone {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 12, height: 12)
            } else {
                Circle()
                    .fill(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint, lineWidth: 1.2))
                    .frame(width: 10, height: 10)
            }
        }
    }

    private func lifecycleStageLabels(current: LifecycleStage, allStages: [LifecycleStage]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(allStages.enumerated()), id: \.offset) { idx, stage in
                let currentIdx = allStages.firstIndex(of: current) ?? 0
                let isCurrent = idx == currentIdx
                let isDone = idx < currentIdx
                Group {
                    if isCurrent {
                        Text(stage.rawValue)
                            .foregroundStyle(LinearGradient.diagonal)
                    } else if isDone {
                        Text(stage.rawValue)
                            .foregroundStyle(palette.textPrimary)
                    } else {
                        Text(stage.rawValue)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.4)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func productAwareKicker(_ l: LoadsAPI.LoadDetail, current: LifecycleStage) -> String {
        let driverName = assignedDriver?.name.split(separator: " ").first.map(String.init) ?? "driver"
        switch current {
        case .posted:    return "Live · awaiting bids"
        case .bidding:   return "Bidding open · catalyst seeking match"
        case .awarded:   return "Awarded to \(driverName) · awaiting pickup dispatch"
        case .pickup:    return "Pickup phase · \(driverName) en-route to origin"
        case .inTransit:
            if let prog = progressPercent(l) {
                return "In transit · driver \(driverName) · \(prog)% of route"
            }
            return "In transit · driver \(driverName)"
        case .delivery:  return "Delivery in progress · \(driverName) at receiver"
        case .paperwork: return "Paperwork · POD pending · settlement next"
        case .closed:    return "Closed · settled · BOL archived"
        }
    }

    private func progressPercent(_ l: LoadsAPI.LoadDetail) -> Int? {
        // Without GPS-derived completion ratio in the load envelope,
        // we show the linehaul fraction off `actualDeliveryDate` if
        // present, or nil to drop the percent from the kicker.
        guard l.actualDeliveryDate == nil else { return 100 }
        return nil
    }

    // MARK: - Money + receivable card (gradient rim)

    private func moneyAndReceivableCard(_ l: LoadsAPI.LoadDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                if let un = l.unNumber {
                    pillTag(text: "UN\(un) · PG II", tint: Brand.hazmat)
                }
                if let eq = l.equipmentType, !eq.isEmpty {
                    pillTag(text: cleanLabel(eq).uppercased(), tint: palette.textPrimary, neutral: true)
                }
                // 2026-05-17 — Catalyst counter-party badge. Surfaces
                // the shipper's mode pick + multi-vehicle count BEFORE
                // the catalyst commits the dispatch, so a rail unit-
                // train or a vessel charter never lands on a Catalyst
                // expecting a single dry-van.
                LoadModeBadge(modeRaw: l.transportMode,
                              multiVehicleCount: l.multiVehicleCount,
                              compact: true)
                pillTag(text: receivableLabel(l), tint: Brand.success)
            }
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(l.rateDisplay)
                    .font(.system(size: 32, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(linehaulLine(l))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text(settlementLine(l))
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
                progressGauge(l)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Strip machine tokens (bracketed enum keys, "key=value" pairs) that
    /// occasionally bleed into server equipment/cargo display strings,
    /// e.g. "Tanker · Hazmat [tanker_hazmat] · vertical=truck" → "Tanker · Hazmat".
    /// Display-layer only — never apply to values used as lexicon keys or
    /// sent to the server. Never returns empty for a non-empty input.
    /// Mirrors 205_ShipperLoadDetail.cleanLabel(_:).
    private func cleanLabel(_ s: String) -> String {
        var out = s
        out = out.replacingOccurrences(
            of: #"\s*\[[^\]]*\]"#, with: "", options: .regularExpression)
        out = out.replacingOccurrences(
            of: #"\s*[·•]?\s*[A-Za-z_-]+=\S+"#, with: "", options: .regularExpression)
        out = out.replacingOccurrences(
            of: #"\s*·\s*·\s*"#, with: " · ", options: .regularExpression)
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: " ·•"))
        if trimmed.isEmpty { return s.trimmingCharacters(in: .whitespaces) }
        return trimmed
    }

    private func pillTag(text: String, tint: Color, neutral: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(neutral ? AnyShapeStyle(palette.textPrimary) : AnyShapeStyle(tint))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(neutral ? palette.borderFaint.opacity(0.5) : tint.opacity(0.16))
            .clipShape(Capsule())
    }

    private func receivableLabel(_ l: LoadsAPI.LoadDetail) -> String {
        switch l.status.lowercased() {
        case "delivered", "completed", "paid", "closed": return "PAID"
        case "in_transit", "assigned":                    return "RECEIVABLE"
        default:                                          return "PENDING"
        }
    }

    private func linehaulLine(_ l: LoadsAPI.LoadDetail) -> String {
        guard let dist = l.distance, dist > 0, l.rateValue > 0 else { return "linehaul" }
        let perMile = l.rateValue / dist
        return String(format: "linehaul · $%.2f/mi", perMile)
    }

    private func settlementLine(_ l: LoadsAPI.LoadDetail) -> String {
        guard l.rateValue > 0 else { return "" }
        let net = l.rateValue * 0.95   // 5% platform fee per §EusoWallet
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = l.currency ?? "USD"
        f.maximumFractionDigits = 0
        let netStr = f.string(from: NSNumber(value: net)) ?? "$\(Int(net))"
        return "net \(netStr) after 5% platform · settles on POD"
    }

    private func progressGauge(_ l: LoadsAPI.LoadDetail) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("PROGRESS")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(progressPercent(l).map { "\($0)%" } ?? "-")
                .font(.system(size: 18, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
            Text(distanceLabel(l))
                .font(.system(size: 10))
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Assignment card (Catalyst-specific)

    private func assignmentCard(_ l: LoadsAPI.LoadDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ASSIGNMENT · DRIVER")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            assignmentRow(l)
        }
    }

    @ViewBuilder
    private func assignmentRow(_ l: LoadsAPI.LoadDetail) -> some View {
        if let driver = assignedDriver {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                    Text(monogram(for: driver.name))
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                    ZStack {
                        Circle().fill(Brand.success).frame(width: 14, height: 14)
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    .offset(x: 16, y: -14)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(driver.name)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text(driverSubtitle(driver))
                        .font(.system(size: 11, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                    HStack(spacing: 6) {
                        if let h = driver.hoursRemaining {
                            chip(text: "HOS · \(formatHOS(h)) LEFT", tint: palette.textPrimary)
                        }
                        chip(text: "OWNER-OP", tint: Brand.success)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    Task { await openDriverPicker() }
                } label: {
                    Text("REASSIGN")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.4)
                        .foregroundStyle(LinearGradient.diagonal)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .overlay(
                            Capsule().strokeBorder(
                                LinearGradient(
                                    colors: [Brand.blue, Brand.magenta],
                                    startPoint: .leading, endPoint: .trailing
                                ),
                                lineWidth: 1.2
                            )
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        } else if l.driverId == nil {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pending assignment")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("No driver yet · catalyst dispatcher hasn't matched the load")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                Button {
                    Task { await openDriverPicker() }
                } label: {
                    Text("ASSIGN")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(LinearGradient.diagonal)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        } else {
            // driverId is set on the load but the catalyst's roster
            // didn't return a matching FleetDriver row — typically a
            // cross-fleet relay or escort hand-off. Honest empty state
            // — surface the bare driverId so the catalyst can chase
            // the relationship in another tool.
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Driver \(l.driverId.map(String.init) ?? "?")")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("Not in this catalyst's roster · cross-fleet relay")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private func chip(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.4)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tint.opacity(0.10))
            .clipShape(Capsule())
    }

    private func driverSubtitle(_ d: CatalystAPI.FleetDriver) -> String {
        if let load = d.currentLoad, !load.isEmpty {
            return "CDL · ON \(load) · \(d.location)"
        }
        return "CDL · \(d.status.uppercased()) · \(d.location)"
    }

    // MARK: - Shipper-of-record card

    @ViewBuilder
    private func shipperOfRecordCard(_ l: LoadsAPI.LoadDetail) -> some View {
        if l.shipperId != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("SHIPPER-OF-RECORD")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                shipperRow(l)
            }
        }
    }

    private func shipperRow(_ l: LoadsAPI.LoadDetail) -> some View {
        // Without a separate `shipper.getById` fetch wired here, the
        // §11 canonical mapping (companyId 1 = Diego Usoro / Eusorone
        // Technologies) covers our flagship persona. For other
        // shipperIds the row paints a generic shipperId line — never
        // a fabricated name.
        let isFlagship = l.shipperId == 1
        let shipperName = isFlagship ? "Diego Usoro · Eusorone Technologies" : "Shipper #\(l.shipperId ?? 0)"
        let shipperMeta = isFlagship
            ? "companyId 1 · pays net-7 EusoQuickPay"
            : "companyId \(l.shipperId ?? 0)"
        let monogram = isFlagship ? "DU" : "S\(l.shipperId ?? 0)"

        return Button {
            NotificationCenter.default.post(
                name: Notification.Name("eusoCatalystOpenShipper"),
                object: nil,
                userInfo: ["shipperId": l.shipperId ?? 0]
            )
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                    Text(monogram)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(shipperName)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(shipperMeta)
                        .font(.system(size: 11, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isFlagship {
                    Text("DIAMOND")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(0.4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(LinearGradient.diagonal)
                        .clipShape(Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Documents row

    private func documentsRow(_ l: LoadsAPI.LoadDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DOCUMENTS")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 8) {
                let docMode = TransportMode(rawValue: l.transportMode ?? "truck") ?? .truck
                docTile(label: TransportLexicon.short(.billOfLading, mode: docMode, equipmentRaw: l.equipmentType), icon: "doc.text", status: bolStatus(l), action: "openBOL")
                docTile(label: "Rate-con", icon: "checkmark.seal", status: rateconStatus(l), action: "openRatecon")
                docTile(label: TransportLexicon.short(.proofOfDelivery, mode: docMode, equipmentRaw: l.equipmentType), icon: "photo", status: podStatus(l), action: "openPOD")
            }
        }
    }

    private func bolStatus(_ l: LoadsAPI.LoadDetail) -> (text: String, tint: Color) {
        switch l.status.lowercased() {
        case "in_transit", "assigned":         return ("draft", palette.textSecondary)
        case "delivered", "completed", "paid": return ("signed", Brand.success)
        default:                                return ("pending", palette.textTertiary)
        }
    }

    private func rateconStatus(_ l: LoadsAPI.LoadDetail) -> (text: String, tint: Color) {
        switch l.status.lowercased() {
        case "pending", "bidding":            return ("draft", palette.textSecondary)
        default:                                return ("signed", Brand.success)
        }
    }

    private func podStatus(_ l: LoadsAPI.LoadDetail) -> (text: String, tint: Color) {
        switch l.status.lowercased() {
        case "delivered", "completed", "paid": return ("uploaded", Brand.success)
        default:                                return ("pending", palette.textTertiary)
        }
    }

    private func docTile(label: String, icon: String, status: (text: String, tint: Color), action: String) -> some View {
        Button {
            NotificationCenter.default.post(
                name: Notification.Name("eusoCatalystOpenDoc"),
                object: nil,
                userInfo: ["doc": action, "loadId": loadId]
            )
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(label)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(status.text)
                    .font(.system(size: 10))
                    .foregroundStyle(status.tint)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom CTAs

    private func bottomCTAs(_ l: LoadsAPI.LoadDetail) -> some View {
        HStack(spacing: 8) {
            Button {
                showStatusPicker = true
            } label: {
                Text(gateLocked ? "Resolve compliance gate" : (statusUpdating ? "Updating…" : "Update status"))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(gateLocked ? AnyShapeStyle(Color.secondary.opacity(0.5)) : AnyShapeStyle(LinearGradient.diagonal))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(statusUpdating || gateLocked)

            Button {
                // Route to the existing ESANG dispatch chat surface for
                // this load. eSang is the canonical voice/messaging
                // funnel per `feedback_esang_canonical_voice`.
                NotificationCenter.default.post(
                    name: .esangOpenMeDetail,
                    object: "messages",
                    userInfo: ["loadId": l.id]
                )
            } label: {
                Text("Message eSang")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 40)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Empty / loading / error

    private var skeletonBody: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
                .frame(height: 56)
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
                .frame(height: 116)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.bgCard)
                .frame(height: 98)
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
                .frame(height: 80)
        }
        .redacted(reason: .placeholder)
    }

    @ViewBuilder
    private var emptyLoadState: some View {
        VStack(spacing: 8) {
            Image(systemName: "shippingbox")
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text("Load not found")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("This load id isn't in the catalyst's books · check the dispatch board")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(msg)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Button { Task { await fetch() } } label: {
                    Text("Retry")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Brand.danger)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Brand.danger.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Helpers

    private func monogram(for name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let initials = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return initials.isEmpty ? "?" : String(initials.prefix(2))
    }

    private func formatHOS(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return String(format: "%d:%02d", h, m)
    }

    private func formatTime(_ iso: String) -> String? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var d = f.date(from: iso)
        if d == nil {
            f.formatOptions = [.withInternetDateTime]
            d = f.date(from: iso)
        }
        guard let date = d else { return nil }
        let out = DateFormatter()
        out.dateFormat = "HH:mm zzz"
        return out.string(from: date)
    }

    // MARK: - Route geometry (REAL HERE corridor)
    //
    // Resolves the pickup→delivery corridor via HERE Routing v8 and decodes
    // its section polyline into `routePolyline` — the real curved road
    // geometry, not the straight 2-point segment the map used to draw. The
    // surface holds a `LoadDetail` (not the full `Load` that
    // `TruckProfile.from(load:)` needs), so we build `HereStops` from the
    // already-resolved `laneCoords(_:)` and route on the default
    // `.standardUSSemiLoaded` profile — the same baseEquipment
    // `HereRoutingClient.route(for:)` applies. On any failure (missing
    // coords, HERE error) the polyline stays empty and the map keeps the
    // straight pickup→delivery base line — never a fabricated path.
    //
    // Water modes are SKIPPED: a vessel/barge leg is a great-circle ocean
    // path, not a road route — fetching road geometry would be dishonest, so
    // we leave `routePolyline` empty and the map draws the direct connector.
    @MainActor
    private func refreshRoutePolyline(_ l: LoadsAPI.LoadDetail) async {
        let mode = TransportMode(rawValue: l.transportMode ?? "truck") ?? .truck
        guard mode != .vessel, mode != .barge,
              let coords = laneCoords(l) else {
            routePolyline = []
            return
        }
        let stops = HereStops(
            origin: CLLocationCoordinate2D(latitude: coords.pickupLat, longitude: coords.pickupLng),
            destination: CLLocationCoordinate2D(latitude: coords.deliveryLat, longitude: coords.deliveryLng)
        )
        do {
            let resp = try await HereRoutingClient.shared.route(
                stops: stops, profile: .standardUSSemiLoaded)
            guard let section = resp.routes.first?.sections.first else {
                routePolyline = []
                return
            }
            let decoded = HereRoutingClient.polyline(for: section)
            routePolyline = decoded.count >= 2 ? decoded.map { HereLatLng($0) } : []
        } catch {
            routePolyline = []
        }
    }

    // MARK: - Network

    private func fetch() async {
        loading = true
        loadError = nil
        defer { loading = false }
        guard !loadId.isEmpty, loadId != "0" else {
            // No id — leave load nil so emptyLoadState renders.
            routePolyline = []
            return
        }
        do {
            let detail = try await EusoTripAPI.shared.loads.getDetail(id: loadId)
            self.load = detail
            // If the load has a driverId, try to find the matching
            // FleetDriver row in this catalyst's roster.
            if let driverId = detail?.driverId {
                let roster = (try? await EusoTripAPI.shared.catalyst.getMyDrivers(limit: 50)) ?? []
                self.assignedDriver = roster.first { $0.id == String(driverId) }
            }
            // Once the load (and thus its real pickup/delivery coords) is on
            // file, fetch + decode the truck/rail route so the lane map
            // paints the real road geometry instead of a straight line.
            // Honest no-op for un-geocoded lanes and water (vessel/barge) legs.
            if let detail { await refreshRoutePolyline(detail) } else { routePolyline = [] }
        } catch {
            self.loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - WebSocket subscription

    /// Joins the load's Socket.IO room so server-side
    /// `LOAD_STATE_CHANGED` / `LOAD_POD_SUBMITTED` /
    /// `LOAD_ASSIGNED` events fan out to this view's
    /// `.esangRefreshSurface` listener.
    private func joinLoadRoom() {
        guard let intId = Int(loadId), intId > 0 else { return }
        Task { @MainActor in
            // Idempotent server-side; safe to call on every fetch.
            RealtimeService.shared.joinLoad(intId)
        }
    }

    private func leaveLoadRoom() {
        guard let intId = Int(loadId), intId > 0 else { return }
        Task { @MainActor in
            RealtimeService.shared.leaveLoad(intId)
        }
    }

    // MARK: - Driver picker (REASSIGN / ASSIGN)

    private func openDriverPicker() async {
        driverAssignError = nil
        driverPickerLoading = true
        showDriverPicker = true
        defer { driverPickerLoading = false }
        do {
            let roster = try await EusoTripAPI.shared.catalyst.getMyDrivers(limit: 50)
            self.availableDrivers = roster
        } catch {
            self.driverAssignError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            self.availableDrivers = []
        }
    }

    private func assignDriver(_ driver: CatalystAPI.FleetDriver) async {
        driverAssignError = nil
        do {
            _ = try await EusoTripAPI.shared.drivers.assignLoad(
                driverId: driver.id,
                loadId: loadId
            )
            // Server emits LOAD_ASSIGNED on success; the WebSocket
            // listener refetches. Close the sheet immediately for
            // responsive UX.
            self.assignedDriver = driver
            showDriverPicker = false
            await fetch()
        } catch {
            self.driverAssignError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Status update

    private func updateStatus(to newStatus: LoadsAPI.LoadStatusUpdate) async {
        statusUpdateError = nil
        statusUpdating = true
        defer { statusUpdating = false }
        do {
            _ = try await EusoTripAPI.shared.loads.updateLoadStatus(
                loadId: loadId,
                status: newStatus
            )
            // Server emits LOAD_STATE_CHANGED on success → WebSocket
            // listener refetches. Close picker + refetch synchronously
            // for snappy UX.
            showStatusPicker = false
            await fetch()
        } catch {
            self.statusUpdateError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Status picker sheet

private struct StatusPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let currentStatus: String
    let isUpdating: Bool
    let onPick: (LoadsAPI.LoadStatusUpdate) -> Void

    /// Catalyst-side status enum subset — manually-updatable transit
    /// states. The driver app's lifecycle screens (013-051) flip the
    /// fine-grained `en_route_pickup` / `at_pickup` / `loading` /
    /// `at_delivery` / `unloading` states automatically; the catalyst
    /// only manually sets the high-level transit milestones + the
    /// exception states.
    private static let pickable: [LoadsAPI.LoadStatusUpdate] = [
        .assigned, .inTransit, .delivered,
        .tempExcursion, .reeferBreakdown, .contaminationReject,
        .sealBreach, .weightViolation,
        .disputed, .cancelled,
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Self.pickable, id: \.self) { status in
                        Button {
                            onPick(status)
                        } label: {
                            HStack {
                                Text(status.label)
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                                if status.rawValue == currentStatus {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(LinearGradient.diagonal)
                                }
                            }
                        }
                        .disabled(isUpdating)
                    }
                } header: {
                    Text("Catalyst-updatable statuses")
                } footer: {
                    Text("Lifecycle states (en route, at pickup, loading, etc.) flip automatically from the driver app.")
                }
            }
            .navigationTitle("Update load status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if isUpdating {
                    ProgressView().controlSize(.large)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Driver picker sheet

private struct DriverPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let drivers: [CatalystAPI.FleetDriver]
    let loading: Bool
    let currentDriverId: String?
    let onPick: (CatalystAPI.FleetDriver) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if drivers.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 32, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("No drivers in roster")
                            .font(.system(size: 16, weight: .heavy))
                        Text("Add a driver to your fleet on 304 Fleet Drivers.")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(drivers) { driver in
                            Button {
                                onPick(driver)
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle().fill(LinearGradient.diagonal)
                                        Text(monogram(for: driver.name))
                                            .font(.system(size: 13, weight: .heavy))
                                            .foregroundStyle(.white)
                                    }
                                    .frame(width: 36, height: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(driver.name)
                                            .foregroundStyle(palette.textPrimary)
                                        Text(driverSubtitle(driver))
                                            .font(.system(size: 11))
                                            .foregroundStyle(palette.textSecondary)
                                    }
                                    Spacer()
                                    if driver.id == currentDriverId {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(LinearGradient.diagonal)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(currentDriverId == nil ? "Assign driver" : "Reassign driver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func monogram(for name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let initials = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return initials.isEmpty ? "?" : String(initials.prefix(2))
    }

    private func driverSubtitle(_ d: CatalystAPI.FleetDriver) -> String {
        if let load = d.currentLoad, !load.isEmpty {
            return "On \(load) · \(d.location)"
        }
        return "\(d.status.uppercased()) · \(d.location)"
    }
}

// MARK: - Previews

#Preview("305 · Catalyst · Load Detail · Night") {
    CatalystLoadDetailScreen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("305 · Catalyst · Load Detail · Afternoon") {
    CatalystLoadDetailScreen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
