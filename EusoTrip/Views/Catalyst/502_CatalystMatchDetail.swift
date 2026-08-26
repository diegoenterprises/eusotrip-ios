//
//  502_CatalystMatchDetail.swift
//  EusoTrip — Catalyst · Match Detail (brick 502).
//
//  Third brick on the Catalyst role track (500s). The natural follow-on
//  to 501_CatalystMatches — when a catalyst taps a row on the
//  active-matches board, this is the deep match-detail surface that
//  opens. Until 502 shipped, 501's row tap surfaced an interim
//  `EusoEmptyState` sheet. Now that 502 is live, that interim state
//  is replaced with this real surface and Catalyst depth
//  matches the structural depth of Carrier (300/301/302) and Broker
//  (400/401/402): three production screens per role.
//
//  Pixel-doctrine compliant per EUSOTRIP2027GOLD §2 (gradient-only
//  accent — no flat Brand.info / Brand.blue fills, no .tint(.blue)),
//  §4 (tokenized spacing / radius / type — Space.s*, Radius.*,
//  EType.*), §5 (palette semantic only — no hard-coded Color.white /
//  Color.black / Color.gray fills outside CTA inverse-text and
//  shadow opacities), §7 (`AnyShapeStyle` wrapping for ternary
//  shape-styles in fill / stroke), §10 (previews compile in
//  isolation — `.task` doesn't run in the preview canvas, so the
//  store stays in `.loading` and never hits the network).
//
//  Cohort B — fully dynamic (SKILL.md §3 real-data pledge · 2027
//  motivation: dynamic ready pages with real backend state,
//  plugged into backend"):
//
//    • Match detail → `CatalystMatchDetailStore`
//      (LiveDataStores.swift, added in this firing) →
//      `loads.getById` (input `{ id: string }`). Verified live at
//      `frontend/server/routers/loads.ts:1046`. Same procedure the
//      Broker Tender Detail (402), Carrier Load Detail (302), and
//      Shipper Load Detail (205) already use — the role distinction
//      is in framing only.
//    • Candidate shortlist → `catalysts.getBidsForLoad` (input
//      `{ loadId: string }`, server `catalysts.ts:3505`) returns the
//      live load-scoped bid rows. It is field-identical to the shipper
//      bid-review payload; this file decodes it locally because the
//      shared wrapper targets `shippers.getBidsForLoad`.
//    • Override-to-manual CTA → routes to the production 305 Load
//      Detail surface, where the existing carrier assignment/reassign,
//      status, message and ESANG actions already live.
//    • Empty / blank server fields surface as em-dash sentinels
//      ("-") — every nullable column on a fresh match (no pickup
//      date scheduled, no rate posted, no agent attached) renders
//      as a neutral em-dash, never a fabricated value.
//    • Preview hint passthrough (loadNumber / lane / startedAt /
//      candidateCount / bestFitScore / agentName) so the sheet
//      has paint-1 visible content while the detail fetch is in
//      flight. Mirrors the 402_BrokerTenderDetail preview-hint
//      pattern.
//
//  Wired into `ContentView.ScreenRegistry` as id="502".
//
//  Powered by ESANG AI™.
//

import SwiftUI

/// One bid row from `catalysts.getBidsForLoad` (server catalysts.ts:3505).
/// Field-identical to ShipperAPI.Bid; decoded file-locally because the
/// shipped wrapper targets the shipper-gated `shippers.getBidsForLoad`.
private struct CandidateBid_502: Decodable, Identifiable, Hashable {
    let id: String
    let catalystId: String
    let catalystName: String
    let dotNumber: String
    let safetyScore: Double
    let amount: Double
    let transitTime: String
    let submittedAt: String
    let message: String
    let recommended: Bool
}

private struct LoadIdInput_502: Encodable { let loadId: String }

// MARK: - Screen body

struct CatalystMatchDetail: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    /// The match (load) id to fetch. Server expects `{ id: string }`
    /// per the Zod input on `loads.getById`. The 501 row carries
    /// `id: String` already (CatalystAPI.ActiveMatch).
    let matchId: String

    /// Optional preview header values used while the detail fetch is
    /// in flight. The sheet caller (501's row tap) carries these for
    /// free — passing them through prevents the perceptible "blank
    /// header → real header" flash on first paint. When unavailable,
    /// pass `nil` and the screen renders em-dash sentinels.
    let previewLoadNumber: String?
    let previewLane: String?
    let previewStartedAt: String?
    let previewCandidateCount: Int?
    let previewBestFitScore: Double?
    let previewAgentName: String?

    @StateObject private var detailStore = CatalystMatchDetailStore()

    @State private var presentingFullLoadDetail: Bool = false

    /// Exact, independent renderer lines from the server-owned route plan.
    @State private var canonicalRouteLines: [[HereLatLng]] = []
    @State private var canonicalRouteStatus: String?
    @State private var canonicalRouteVersion: Int?
    @State private var canonicalResolvedPurpose: CanonicalRoutePlanClient.Purpose?
    @State private var canonicalRouteMode: CanonicalRoutePlanClient.Mode?
    @State private var candidateBids: [CandidateBid_502] = []
    @State private var candidatesLoading: Bool = false
    @State private var candidatesError: String? = nil
    @State private var candidateFetchCompleted: Bool = false

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
        .task {
            await refreshAll()
            await refreshCandidates()
            await refreshCanonicalRoute()
            joinLoadRoom()
        }
        .eusoRefreshable {
            await refreshAll()
            await refreshCandidates()
            await refreshCanonicalRoute()
        }
        .onDisappear { leaveLoadRoom() }
        // RealtimeService → live updates from the match's Socket.IO
        // room (status changes, candidate fan-out, carrier accept,
        // reassignment) refresh the detail surface in place.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await refreshAll(); await refreshCandidates(); await refreshCanonicalRoute() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await refreshAll(); await refreshCandidates(); await refreshCanonicalRoute() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadReassigned)) { _ in
            Task { await refreshAll(); await refreshCandidates(); await refreshCanonicalRoute() }
        }
        // "Open full load detail" CTA → 305 Catalyst Load Detail with
        // the resolved loadId so the catalyst can update status,
        // reassign carrier, or message eSang from the load surface.
        .sheet(isPresented: $presentingFullLoadDetail) {
            CatalystLoadDetailScreen(theme: palette, loadId: resolvedLoadId)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    /// Live load id from the loaded detail row — falls back to the
    /// matchId if the detail hasn't arrived yet (the 305 sheet will
    /// then either resolve it or show its own "match not found"
    /// state). Never returns an empty string so the sheet always
    /// has *some* id to dispatch on.
    private var resolvedLoadId: String {
        if let live = detailStore.state.value ?? nil {
            return live.id
        }
        return matchId
    }

    private func joinLoadRoom() {
        guard let live = detailStore.state.value ?? nil else { return }
        guard let intId = Int(live.id), intId > 0 else { return }
        Task { @MainActor in
            RealtimeService.shared.joinLoad(intId)
        }
    }

    private func leaveLoadRoom() {
        guard let live = detailStore.state.value ?? nil else { return }
        guard let intId = Int(live.id), intId > 0 else { return }
        Task { @MainActor in
            RealtimeService.shared.leaveLoad(intId)
        }
    }

    // MARK: - Header
    //
    // Always-visible header. Renders from preview hints until the live
    // detail row arrives, then swaps in the server-emitted values.

    private var header: some View {
        let live: LoadsAPI.LoadDetail? = detailStore.state.value ?? nil
        let loadNumber = live?.loadNumber ?? previewLoadNumber ?? "-"
        let lane: String = live?.laneDisplay ?? previewLane ?? "-"
        let status = live?.status ?? ""

        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 10) {
                Image(systemName: "scope")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        EusoTripBrandMark(size: 12)
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("CATALYST · MATCH DETAIL")
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Text(loadNumber)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2).minimumScaleFactor(0.75)
                }
                Spacer(minLength: 0)
                if !status.isEmpty {
                    statusPill(status)
                }
            }
            Text(lane)
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Content body (state machine)

    @ViewBuilder
    private var contentBody: some View {
        switch detailStore.state {
        case .loading:
            loadingCard
        case .loaded(let opt):
            if let detail = opt {
                detailCards(for: detail)
            } else {
                EusoEmptyState(
                    systemImage: "scope",
                    title: "Match not found",
                    subtitle: "The match you tapped is no longer in the system. Pull to refresh or pick another match from the board."
                )
            }
        case .empty:
            EusoEmptyState(
                systemImage: "scope",
                title: "Match not found",
                subtitle: "The match you tapped is no longer in the system. Pull to refresh or pick another match from the board."
            )
        case .error(let err):
            errorBanner(message: readableError(err))
        }
    }

    // MARK: - Detail cards (live data)

    @ViewBuilder
    private func detailCards(for detail: LoadsAPI.LoadDetail) -> some View {
        metricsRow(detail)
        routeMapCard(detail)
        scheduleCard(detail)
        cargoCard(detail)
        spectraMatchCard(detail)
        candidatesCard(detail)
        notesCard(detail)
        overrideCTA(detail)
    }

    /// Three-tile row: best fit / candidates / started.
    /// Em-dash on missing values so a brand-new match doesn't
    /// fabricate values.
    private func metricsRow(_ d: LoadsAPI.LoadDetail) -> some View {
        HStack(spacing: Space.s2) {
            metricTile(
                label: "BEST FIT",
                value: bestFitDisplay(),
                icon: "sparkles"
            )
            metricTile(
                label: "CANDIDATES",
                value: candidatesDisplay(),
                icon: "person.2.fill"
            )
            metricTile(
                label: "STARTED",
                value: startedDisplay(d),
                icon: "clock"
            )
        }
    }

    /// SpectraMatch fit score (0.0–1.0) → "92%" presentation form.
    /// Mirrors the format used on 500/501 so the same envelope reads
    /// identically across the Catalyst track. Em-dash when the row
    /// hint is missing or zero (no carrier scored yet).
    private func bestFitDisplay() -> String {
        guard let v = previewBestFitScore, v > 0 else { return "-" }
        let clamped = min(max(v, 0), 1)
        let pct = Int((clamped * 100).rounded())
        return "\(pct)%"
    }

    /// "0 candidates" / "1 candidate" / "12 candidates" — live count
    /// after `catalysts.getBidsForLoad` completes, preview hint only
    /// while the first request is in flight or when that request errors.
    private func candidatesDisplay() -> String {
        if !candidateBids.isEmpty {
            return candidateCountText(candidateBids.count)
        }
        if candidatesError == nil, candidateFetchCompleted {
            return candidateCountText(0)
        }
        guard let n = previewCandidateCount else { return "-" }
        return candidateCountText(n)
    }

    private func candidateCountText(_ n: Int) -> String {
        "\(n) " + (n == 1 ? "candidate" : "candidates")
    }

    /// "started 2m" — server-projected relative label from the
    /// ActiveMatch row. Falls back to the LoadDetail.createdAt
    /// when the row hint is missing. Em-dash when both are absent.
    private func startedDisplay(_ d: LoadsAPI.LoadDetail) -> String {
        if let s = previewStartedAt, !s.isEmpty {
            return s
        }
        return humanDate(d.createdAt)
    }

    private func metricTile(label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(label)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
            Text(value)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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

    // MARK: - Route preview (in-house HERE)
    //
    // Origin → destination route-preview on the OMV vector renderer
    // (HereLiveMapView, `.shipperTracking` watcher add-ons — weather +
    // traffic + ad-zones, no driver gamification fan-out). Coords bind
    // ONLY to the REAL `pickupLocation.lat/.lng` + `deliveryLocation
    // .lat/.lng` the same `loads.getById` envelope carries (the
    // `LoadCityState.lat/lng` slots the server self-heals via HERE
    // geocode, EusoTripAPI.swift:1219-1220 / loads.ts self-heal
    // 175-206). Identical lane-resolution to the sibling
    // 305_CatalystLoadDetail.routeMapCard — same store, same proc,
    // same fields.
    //
    // Driver 013 coord gate (`laneCoords` → nil on any zero/nil
    // endpoint): when this match's load has only city names and no
    // geocoded fix, honest-skip to a neutral "Route loading…"
    // neutral route state. Never geocode a place name client-side; never
    // frame on null island.
    @ViewBuilder
    private func routeMapCard(_ l: LoadsAPI.LoadDetail) -> some View {
        if let coords = laneCoords(l) {
            let midLat = (coords.pickupLat + coords.deliveryLat) / 2
            let midLng = (coords.pickupLng + coords.deliveryLng) / 2
            let mapTransportMode = EusoTripMapTransportMode(
                canonicalValue: canonicalRouteMode?.rawValue ?? l.transportMode
            )
            let requestedPurpose = canonicalRoutePurpose(for: l.status)
            let markerLayer = HereMapLayer.markers([
                .init(at: .init(coords.pickupLat, coords.pickupLng),
                      kind: .pickup, label: coords.originTitle),
                .init(at: .init(coords.deliveryLat, coords.deliveryLng),
                      kind: .delivery, label: coords.destinationTitle)
            ])
            let mapLayers: [HereMapLayer] = canonicalRouteLines.enumerated().map { index, line in
                .eusoRoute(
                    polyline: line,
                    state: canonicalResolvedPurpose == .activeJob ? .active : .planned,
                    label: index == 0
                        ? "Eusorone \(mapTransportMode.rawValue) route plan version \(canonicalRouteVersion ?? 0)"
                        : nil
                )
            } + [markerLayer]
            ZStack(alignment: .bottomLeading) {
                HereLiveMapView(
                    center: canonicalRouteLines.lazy.compactMap(\.first).first
                        ?? .init(midLat, midLng),
                    zoom: 6,
                    route: [],
                    baseLayers: mapLayers,
                    addOns: mapTransportMode == .truck ? .shipperTracking : .weather,
                    activeJob: requestedPurpose == .activeJob,
                    mapModeContext: .unconfirmed(mapTransportMode)
                )
                if let canonicalRouteStatus {
                    canonicalRouteStatusPill(canonicalRouteStatus)
                        .padding(10)
                }
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .accessibilityLabel("Match route preview, \(coords.originTitle) to \(coords.destinationTitle)")
        } else {
            // Coord gate (Driver 013 pattern): no real fix on one or
            // both endpoints yet (match load carries only city names) —
            // neutral route state, never a demo route, never a
            // client-side geocode of the city string.
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
                        if let canonicalRouteStatus {
                            Text(canonicalRouteStatus)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                                .multilineTextAlignment(.center)
                                .accessibilityLabel(canonicalRouteStatus)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
        }
    }

    /// Resolves the match load's REAL pickup → delivery coordinates off
    /// the `loads.getById` envelope (`pickupLocation.lat/.lng` +
    /// `deliveryLocation.lat/.lng`). Returns nil (→ honest-skip) when
    /// either endpoint hasn't been geocoded yet — the exact gate
    /// 305_CatalystLoadDetail.laneCoords uses (non-nil + non-zero on
    /// both lat/lng). No fabrication, no place-name geocoding.
    private func laneCoords(_ l: LoadsAPI.LoadDetail)
        -> (pickupLat: Double, pickupLng: Double,
            deliveryLat: Double, deliveryLng: Double,
            originTitle: String, destinationTitle: String)? {
        guard let p = l.pickupLocation,
              let d = l.deliveryLocation,
              let pickup = LatLongParser.validatedCoordinate(
                  latitude: p.lat,
                  longitude: p.lng
              ),
              let delivery = LatLongParser.validatedCoordinate(
                  latitude: d.lat,
                  longitude: d.lng
              ) else { return nil }
        let origin = p.cityState.isEmpty ? "Origin" : p.cityState
        let dest = d.cityState.isEmpty ? "Dest" : d.cityState
        return (
            pickup.latitude, pickup.longitude,
            delivery.latitude, delivery.longitude,
            origin, dest
        )
    }

    // MARK: - Canonical route authority

    private func canonicalRoutePurpose(for status: String) -> CanonicalRoutePlanClient.Purpose {
        let normalized = status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let active: Set<String> = [
            "assigned", "dispatched", "en_route", "enroute", "at_pickup",
            "loaded", "in_transit", "approaching_delivery", "at_receiver",
            "at_delivery", "unloading", "delivering"
        ]
        if active.contains(normalized) { return .activeJob }
        if ["accepted", "awarded"].contains(normalized) { return .planning }
        return .posting
    }

    /// Match previews remain posting plans until exact server status proves a
    /// planning or active assignment state. Only load subject + purpose cross
    /// the client boundary.
    @MainActor
    private func refreshCanonicalRoute() async {
        canonicalRouteLines = []
        canonicalRouteVersion = nil
        canonicalResolvedPurpose = nil
        canonicalRouteMode = nil
        canonicalRouteStatus = "Verified match route is still being prepared"
        guard let live = detailStore.state.value ?? nil else {
            canonicalRouteStatus = "Canonical route pending a persisted load identity"
            return
        }
        guard let numericId = Int(live.id), numericId > 0 else {
            canonicalRouteStatus = "Canonical route pending a persisted load identity"
            return
        }
        let expectedPurpose = canonicalRoutePurpose(for: live.status)
        do {
            let result = try await CanonicalRoutePlanClient.shared.planLoad(
                id: numericId,
                purpose: expectedPurpose
            )
            switch result {
            case .persisted(let persisted):
                applyCanonicalRoute(persisted.route, expectedPurpose: expectedPurpose)
            case .pending(let pending):
                canonicalRouteStatus = pending.blockers.first?.message
                    ?? "Canonical mode-native route pending verified authority"
                await readExistingCanonicalRoute(loadId: numericId, expectedPurpose: expectedPurpose)
            }
        } catch {
            canonicalRouteStatus = error.eusoUserCopy
            await readExistingCanonicalRoute(loadId: numericId, expectedPurpose: expectedPurpose)
        }
    }

    @MainActor
    private func readExistingCanonicalRoute(
        loadId: Int,
        expectedPurpose: CanonicalRoutePlanClient.Purpose
    ) async {
        do {
            applyCanonicalRoute(
                try await CanonicalRoutePlanClient.shared.getBoundLoad(id: loadId),
                expectedPurpose: expectedPurpose
            )
        } catch {
            if canonicalRouteStatus == nil { canonicalRouteStatus = error.eusoUserCopy }
        }
    }

    @MainActor
    private func applyCanonicalRoute(
        _ route: CanonicalRoutePlanClient.BoundRoutePlan,
        expectedPurpose: CanonicalRoutePlanClient.Purpose
    ) {
        guard route.plan.purpose == expectedPurpose,
              let payload = route.rendererPayload else {
            canonicalRouteLines = []
            canonicalRouteVersion = nil
            canonicalResolvedPurpose = nil
            canonicalRouteMode = nil
            canonicalRouteStatus = "Canonical \(expectedPurpose.rawValue) route exists but is not released for rendering"
            return
        }
        canonicalRouteLines = payload.lines
        canonicalRouteVersion = payload.identity.version
        canonicalResolvedPurpose = route.plan.purpose
        canonicalRouteMode = payload.identity.mode
        canonicalRouteStatus = nil
    }

    private func canonicalRouteStatusPill(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(palette.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(palette.bgCard.opacity(0.92))
            .overlay(Capsule().strokeBorder(Brand.warning.opacity(0.45)))
            .clipShape(Capsule())
            .accessibilityLabel(message)
    }

    /// Pickup / delivery / bidding-ends. Em-dash on missing columns
    /// so a fresh match doesn't show synthetic dates.
    private func scheduleCard(_ d: LoadsAPI.LoadDetail) -> some View {
        let mode = TransportMode(rawValue: d.transportMode ?? "truck") ?? .truck
        return VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("SCHEDULE", icon: "calendar")
            scheduleRow(label: TransportLexicon.short(.originWindow, mode: mode, equipmentRaw: d.equipmentType),
                        value: humanDate(d.pickupDate))
            scheduleRow(label: TransportLexicon.short(.destinationWindow, mode: mode, equipmentRaw: d.equipmentType),
                        value: humanDate(d.deliveryDate))
            if d.biddingEnds != nil {
                scheduleRow(label: "Bidding ends", value: humanDate(d.biddingEnds))
            }
            if d.estimatedDeliveryDate != nil {
                scheduleRow(label: "Est. delivery", value: humanDate(d.estimatedDeliveryDate))
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

    private func scheduleRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: Space.s2)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    /// Cargo card mirrors 402's cargoCard. Hazmat row only renders
    /// when the load is hazmat (so non-hazmat loads don't show
    /// "Hazmat: —" filler).
    private func cargoCard(_ d: LoadsAPI.LoadDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("CARGO", icon: "shippingbox")
            scheduleRow(label: "Type", value: humanCargoType(d.cargoType))
            if let commodity = (d.commodity ?? d.commodityName), !commodity.isEmpty {
                scheduleRow(label: "Commodity", value: commodity)
            }
            if let equip = d.equipmentType, !equip.isEmpty {
                scheduleRow(label: "Equipment", value: equip)
            }
            // 2026-05-17 — Multi-modal payload on Catalyst Match Detail.
            // Same shape as the Shipper detail (205) cargo card.
            if let mode = d.transportMode, !mode.isEmpty, mode != "truck" {
                scheduleRow(label: "Mode", value: mode.uppercased())
            }
            if let vc = d.vesselClass, !vc.isEmpty {
                scheduleRow(label: "Vessel class", value: vc)
            }
            if let count = d.multiVehicleCount, count > 1 {
                scheduleRow(label: "Vehicles", value: "\(count) ×")
            }
            if let perm = d.permitType, !perm.isEmpty, perm != "none" {
                scheduleRow(label: "Permit", value: perm.replacingOccurrences(of: "_", with: " ").uppercased())
            }
            if let ws = d.worldscalePct, !ws.isEmpty, let n = Double(ws), n > 0 {
                scheduleRow(label: "Worldscale", value: "WS \(Int(n.rounded()))")
            }
            if let w = d.weightDisplay as String?, w != "-" {
                scheduleRow(label: "Weight", value: w)
            }
            if let dist = d.distanceDisplay as String?, dist != "-" {
                scheduleRow(label: "Distance", value: dist)
            }
            if let hz = d.hazmatClass, !hz.isEmpty {
                scheduleRow(label: "Hazmat class", value: hz)
                if let un = d.unNumber, !un.isEmpty {
                    scheduleRow(label: "UN number", value: un)
                }
                if let g = d.ergGuide {
                    scheduleRow(label: "ERG guide", value: "#\(g)")
                }
            }
            if d.spectraMatchVerified == true {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SPECTRA-MATCH VERIFIED")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .padding(.top, 2)
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

    /// SpectraMatch card — catalyst-specific framing of the autopilot
    /// envelope. Surfaces fit score, agent in the loop, and a
    /// posture badge that interprets the score relative to the
    /// Autopilot 7-layer cortex high-confidence threshold (0.85).
    /// Em-dash when the server hasn't scored a candidate yet.
    private func spectraMatchCard(_ d: LoadsAPI.LoadDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("SPECTRAMATCH", icon: "wand.and.stars")
            scheduleRow(label: "Best fit",  value: bestFitDisplay())
            scheduleRow(
                label: "Agent",
                value: (previewAgentName?.isEmpty == false ? previewAgentName! : "Manual")
            )
            if let label = fitPosture(previewBestFitScore ?? 0) {
                HStack(spacing: 6) {
                    Image(systemName: label.icon)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(label.text)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .padding(.top, 2)
            }
            // If the server has computed a market range for this
            // lane, surface it as context — useful when the catalyst
            // is choosing whether to override to a manual price.
            if let lo = d.suggestedRateMin, let hi = d.suggestedRateMax,
               lo > 0, hi > 0 {
                scheduleRow(
                    label: "Lane market",
                    value: "\(currency(lo)) – \(currency(hi))"
                )
            }
            if let cur = d.currency, !cur.isEmpty, cur.uppercased() != "USD" {
                scheduleRow(label: "Currency", value: cur.uppercased())
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

    /// Compute a small badge-style label describing the fit score's
    /// posture relative to the Autopilot high-confidence band (0.85).
    /// Returns nil when the score is zero (no badge).
    private func fitPosture(_ score: Double) -> (text: String, icon: String)? {
        guard score > 0 else { return nil }
        if score >= 0.85 {
            return ("HIGH-CONFIDENCE FIT", "checkmark.circle.fill")
        }
        if score >= 0.6 {
            return ("MODERATE FIT", "exclamationmark.circle.fill")
        }
        return ("LOW FIT - CONSIDER OVERRIDE", "arrow.triangle.swap")
    }

    /// Candidates card — real bid candidates from `catalysts.getBidsForLoad`.
    /// The server's current shape carries bid amount, submitted time, message,
    /// carrier identity and a recommended flag. Safety score / transit time
    /// render only when persisted by the server payload.
    private func candidatesCard(_ d: LoadsAPI.LoadDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("CANDIDATES", icon: "person.2.fill")
            HStack(alignment: .firstTextBaseline) {
                Text(candidatesDisplay())
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: Space.s2)
                Text("SCORED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            if let agent = previewAgentName, !agent.isEmpty, candidateBids.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                    Text("Agent · \(agent)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
            if candidatesLoading && candidateBids.isEmpty {
                candidateStatusRow(
                    icon: "arrow.clockwise",
                    title: "Loading live bids",
                    subtitle: "Pulling carrier submissions for this load."
                )
            } else if let candidatesError {
                candidateErrorRow(candidatesError)
            } else if candidateBids.isEmpty {
                candidateStatusRow(
                    icon: "tray",
                    title: "No live bids yet",
                    subtitle: "Carrier submissions appear here as soon as they are posted against this load."
                )
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(candidateBids) { bid in
                        candidateBidRow(bid)
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

    private func candidateStatusRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
                .frame(width: 24, height: 24)
                .background(palette.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func candidateErrorRow(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            candidateStatusRow(
                icon: "exclamationmark.triangle.fill",
                title: "Couldn't load bid candidates",
                subtitle: message
            )
            Button {
                Task { await refreshCandidates() }
            } label: {
                Text("Retry candidates")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func candidateBidRow(_ bid: CandidateBid_502) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: Space.s2) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(bid.catalystName.isEmpty ? "Carrier" : bid.catalystName)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        if bid.recommended {
                            Text("RECOMMENDED")
                                .font(.system(size: 8, weight: .heavy))
                                .tracking(0.7)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(LinearGradient.diagonal)
                                .clipShape(Capsule())
                        }
                    }
                    Text(candidateMetaLine(bid))
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: Space.s2)
                Text(bid.amount > 0 ? currency(bid.amount) : "-")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            if !bid.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(bid.message)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if bid.safetyScore > 0 {
                    miniPill("Safety \(Int(bid.safetyScore.rounded()))")
                }
                if !bid.transitTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    miniPill(bid.transitTime)
                }
            }
        }
        .padding(Space.s2)
        .background(palette.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func candidateMetaLine(_ bid: CandidateBid_502) -> String {
        var pieces: [String] = []
        if !bid.dotNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pieces.append("DOT \(bid.dotNumber)")
        }
        let submitted = humanDate(bid.submittedAt)
        if submitted != "-" {
            pieces.append(submitted)
        }
        return pieces.isEmpty ? "Bid on file" : pieces.joined(separator: " · ")
    }

    private func miniPill(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(palette.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(palette.tintNeutral)
            .clipShape(Capsule())
    }

    /// Notes block — only renders when the load actually carries
    /// special-instructions text from the server. Drafts with no
    /// notes get the section omitted entirely (no "-" filler).
    @ViewBuilder
    private func notesCard(_ d: LoadsAPI.LoadDetail) -> some View {
        if let notes = d.notes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                sectionHeader("NOTES", icon: "text.alignleft")
                Text(notes)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
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
    }

    /// Override-to-manual CTA — routes the catalyst to 305 Load
    /// Detail where the existing assign/reassign carrier picker is
    /// the production manual-override path. Renders only on matches
    /// in a state where overriding would be plausible (status
    /// `available` / `posted` / `bidding_open` / `matching`); the
    /// CTA is suppressed for already-locked / in-flight / delivered
    /// matches.
    @ViewBuilder
    private func overrideCTA(_ d: LoadsAPI.LoadDetail) -> some View {
        let overridable: Set<String> = ["available", "posted", "bidding_open", "open", "matching"]
        if overridable.contains(d.status.lowercased()) {
            Button {
                presentingFullLoadDetail = true
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Open full load detail")
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right.square.fill")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    Text("Open the full Load Detail surface to assign or reassign a carrier (manual override), update status, send to eSang or message the driver. Manual override pulls the match out of SpectraMatch.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            // Even on non-overridable matches the catalyst should be
            // able to drill into the load (e.g. to see live driver
            // location once the carrier accepts). Same target — just
            // worded as a navigation, not an override.
            Button {
                presentingFullLoadDetail = true
            } label: {
                HStack {
                    Text("Open full load detail")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.right.square.fill")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
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
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading + error states

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionHeader("LOADING", icon: "arrow.clockwise")
            Text("Pulling the latest from the match record…")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
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
            Button(action: { Task { await refreshAll() } }) {
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

    private func sectionHeader(_ text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text(text)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func statusPill(_ raw: String) -> some View {
        let label = raw.replacingOccurrences(of: "_", with: " ").uppercased()
        let isLive = liveStatuses.contains(raw.lowercased())
        let style: AnyShapeStyle = isLive
            ? AnyShapeStyle(LinearGradient.diagonal)
            : AnyShapeStyle(palette.tintNeutral)
        let fg: Color = isLive ? .white : palette.textSecondary
        return Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
            .foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(style)
            .clipShape(Capsule())
    }

    /// "Live" framing for a catalyst — matches that are still in
    /// the autopilot loop. Anything past assignment reads as neutral.
    private var liveStatuses: Set<String> {
        ["available", "posted", "bidding_open", "open", "matching"]
    }

    /// Map the backend's lowercase enum value to a sentence-case label.
    /// Em-dash on empty/nil so a draft cargoType missing from the row
    /// surfaces as a neutral cell.
    private func humanCargoType(_ raw: String?) -> String {
        guard let r = raw, !r.isEmpty else { return "-" }
        switch r.lowercased() {
        case "general":      return "General freight"
        case "hazmat":       return "Hazmat"
        case "petroleum":    return "Petroleum"
        case "gas":          return "Gas"
        case "chemicals":    return "Chemicals"
        case "refrigerated": return "Refrigerated"
        case "container":    return "Container"
        case "bulk":         return "Bulk"
        default:             return r.capitalized
        }
    }

    /// Parse an ISO-8601 date string from the server and render as a
    /// short human-readable form (e.g. "Apr 28 · 09:30"). Em-dash
    /// when nil / empty / unparseable so missing dates always look
    /// like a deliberate sentinel.
    private func humanDate(_ iso: String?) -> String {
        guard let iso = iso, !iso.isEmpty else { return "-" }
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = isoFmt.date(from: iso)
        if date == nil {
            isoFmt.formatOptions = [.withInternetDateTime]
            date = isoFmt.date(from: iso)
        }
        if date == nil {
            // Server occasionally hands back YYYY-MM-DD only.
            let day = DateFormatter()
            day.dateFormat = "yyyy-MM-dd"
            day.locale = Locale(identifier: "en_US_POSIX")
            date = day.date(from: iso)
        }
        guard let d = date else { return iso }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d · HH:mm"
        return fmt.string(from: d)
    }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    private func readableError(_ error: Error) -> String {
        if let api = error as? EusoTripAPIError {
            return api.errorDescription ?? "Request failed."
        }
        return error.localizedDescription
    }

    private func refreshAll() async {
        detailStore.loadId = matchId
        await detailStore.refresh()
    }

    @MainActor
    private func refreshCandidates() async {
        let loadId = resolvedLoadId
        guard !loadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              loadId != "0" else {
            candidateBids = []
            candidatesError = nil
            candidateFetchCompleted = true
            return
        }
        candidatesLoading = true
        candidatesError = nil
        defer { candidatesLoading = false }
        do {
            let rows: [CandidateBid_502] = try await EusoTripAPI.shared.query(
                "catalysts.getBidsForLoad",
                input: LoadIdInput_502(loadId: loadId)
            )
            candidateBids = rows
            candidateFetchCompleted = true
        } catch {
            candidateBids = []
            candidatesError = readableError(error)
            candidateFetchCompleted = false
        }
    }
}

// MARK: - Screen wrapper (Shell + BottomNav)

struct CatalystMatchDetailScreen: View {
    let theme: Theme.Palette
    let matchId: String
    let previewLoadNumber: String?
    let previewLane: String?
    let previewStartedAt: String?
    let previewCandidateCount: Int?
    let previewBestFitScore: Double?
    let previewAgentName: String?

    init(
        theme: Theme.Palette,
        matchId: String,
        previewLoadNumber: String? = nil,
        previewLane: String? = nil,
        previewStartedAt: String? = nil,
        previewCandidateCount: Int? = nil,
        previewBestFitScore: Double? = nil,
        previewAgentName: String? = nil
    ) {
        self.theme = theme
        self.matchId = matchId
        self.previewLoadNumber = previewLoadNumber
        self.previewLane = previewLane
        self.previewStartedAt = previewStartedAt
        self.previewCandidateCount = previewCandidateCount
        self.previewBestFitScore = previewBestFitScore
        self.previewAgentName = previewAgentName
    }

    var body: some View {
        Shell(theme: theme) {
            CatalystMatchDetail(
                matchId: matchId,
                previewLoadNumber: previewLoadNumber,
                previewLane: previewLane,
                previewStartedAt: previewStartedAt,
                previewCandidateCount: previewCandidateCount,
                previewBestFitScore: previewBestFitScore,
                previewAgentName: previewAgentName
            )
        } nav: {
            BottomNav(
                leading: catalystNavLeading_502(),
                trailing: catalystNavTrailing_502(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_502() -> [NavSlot] {
    CarrierNavRoute.leading(current: .loads)
}

private func catalystNavTrailing_502() -> [NavSlot] {
    CarrierNavRoute.trailing(current: .loads)
}

// MARK: - Previews
//
// Previews don't run `.task`, so the store stays in `.loading` —
// both registers render the loading skeleton without hitting the
// network. Per doctrine §10: previews must compile in isolation.

#Preview("502 · Catalyst · Match Detail · Night") {
    CatalystMatchDetailScreen(
        theme: Theme.dark,
        matchId: "0",
        previewLoadNumber: "-",
        previewLane: "-",
        previewStartedAt: nil,
        previewCandidateCount: nil,
        previewBestFitScore: nil,
        previewAgentName: nil
    )
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.dark)
}

#Preview("502 · Catalyst · Match Detail · Afternoon") {
    CatalystMatchDetailScreen(
        theme: Theme.light,
        matchId: "0",
        previewLoadNumber: "-",
        previewLane: "-",
        previewStartedAt: nil,
        previewCandidateCount: nil,
        previewBestFitScore: nil,
        previewAgentName: nil
    )
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.light)
}
