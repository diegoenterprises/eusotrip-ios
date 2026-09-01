//
//  601_EscortAssignmentDetail.swift
//  EusoTrip — Escort · Assignment Detail (brick 601).
//
//  Second brick on the Escort role track (600s). The natural follow-on
//  to 600_EscortHome — when the operator taps an active-assignment row
//  on the home, this is the deep assignment-detail surface that opens.
//  Until 601 shipped, that row tap was a no-op (an empty closure).
//  Now the tap presents this real surface so Escort depth matches the
//  structural depth of Carrier (300/301/302), Broker (400/401/402), and
//  Catalyst (500/501/502): three production screens per role.
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
//    • Assignment detail → `EscortAssignmentDetailStore`
//      (LiveDataStores.swift) → `escorts.getActiveAssignmentDetail`
//      (input `{ id: string }`). If the parallel router has not
//      shipped, the store resolves to `.error` and the screen
//      surfaces an honest retry banner. No fixture data ever.
//    • "Confirm route" CTA → `escorts.confirmRoute` mutation
//      (input `{ id: string }`). Disabled while the detail fetch
//      is in flight, while the mutation is in flight, and once
//      the server-side `routeConfirmed: true` flag has flipped.
//      On success the local cell repaints from the mutation's
//      returned envelope (no extra round-trip). On failure the
//      CTA flips back to its idle label and the inline error
//      surfaces — local state never lies about the commit landing.
//    • Empty / blank server fields surface as em-dash sentinels
//      ("-") — every nullable column on a fresh assignment (no
//      permit attached, no driver paired, no bridge clearance
//      surveyed, no notes) renders as a neutral em-dash, never
//      a fabricated value.
//    • Preview hint passthrough (loadNumber / lane / startedAt /
//      escortRole / corridorCoverage / permitNumber) so the
//      sheet has paint-1 visible content while the detail fetch
//      is in flight. Mirrors the 502_CatalystMatchDetail
//      preview-hint pattern.
//
//  Wired into `ContentView.ScreenRegistry` as id="601".
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation

// MARK: - Screen body

struct EscortAssignmentDetail: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    /// The assignment id to fetch. Server expects `{ id: string }`
    /// per the Zod input on `escorts.getActiveAssignmentDetail`. The
    /// 600 row carries `id: String` already (EscortAPI.ActiveAssignment).
    let assignmentId: String

    /// Optional preview header values used while the detail fetch is
    /// in flight. The sheet caller (600's row tap) carries these for
    /// free — passing them through prevents the perceptible "blank
    /// header → real header" flash on first paint. When unavailable,
    /// pass `nil` and the screen renders em-dash sentinels.
    let previewLoadNumber: String?
    let previewLane: String?
    let previewStartedAt: String?
    let previewEscortRole: String?
    let previewPermitNumber: String?
    let previewCorridorCoverage: Double?

    @StateObject private var detailStore = EscortAssignmentDetailStore()

    /// CTA in-flight state. Drives the "Confirm route" button label
    /// and disabled state separately from `detailStore.state`. Reset
    /// on retry / refresh.
    @State private var confirmInFlight: Bool = false
    /// CTA local error (post-mutation). Cleared on retry. Distinct
    /// from `detailStore`'s own `.error` — that one's about the
    /// detail fetch, this one's about the confirm-route mutation.
    @State private var confirmError: String? = nil
    /// Local override for the server's `routeConfirmed` flag. Set by
    /// a successful mutation so the CTA flips immediately without
    /// waiting for the next refresh round-trip.
    @State private var localConfirmed: Bool = false

    /// Toggle that presents the 602 corridor-map sheet. Set by the
    /// "View corridor →" drill-in CTA. Added 2026-04-27 in the 159th
    /// eusotrip-killers firing alongside the 602 brick.
    @State private var showCorridorMap: Bool = false

    /// Real corridor endpoint coordinates for the route-preview map.
    ///
    /// `EscortAPI.AssignmentDetail` (the canonical envelope decoded by the
    /// store) does not surface lat/lng — `escorts.getActiveAssignmentDetail`
    /// historically only put origin/destination on the wire as city/state
    /// strings. The proc now ALSO returns `originLat/originLng/destLat/destLng`
    /// straight off `loads.pickupLocation.lat/lng` + `loads.deliveryLocation`
    /// (the same real columns the shipper LoadDetail hero map reads). To
    /// consume them without widening the shared model, we decode a tiny
    /// coordinate-only projection of the SAME proc, screen-local. Nil until
    /// the fetch lands; `(0,0)` ends are treated as "awaiting coordinates"
    /// (null-island gate) so a brand-new load with no geocode never draws.
    @State private var corridorCoords: EscortCorridorCoords? = nil

    /// Exact, independent renderer members from the load's canonical Truck
    /// plan. The escort client never turns assignment endpoints into a route.
    @State private var canonicalRouteLines: [[HereLatLng]] = []
    @State private var canonicalRouteStatus: String?
    @State private var canonicalRouteVersion: Int?
    @State private var canonicalResolvedPurpose: CanonicalRoutePlanClient.Purpose?

    /// Route-wide wind-gust go/no-go envelope for the high-profile load —
    /// decoded from the Wave-4 `escorts.getCorridor.windGate` block (the
    /// route-wide status + the worst forecast gust measured against the
    /// PUBLISHED escort caution/nogo wind thresholds). Each threshold
    /// carries the server's operating-standard `basis`. Nil until the
    /// corridor fetch lands; the gust feed is enterprise-gated
    /// (`available:false`) today, so a present-but-ungated envelope reads
    /// as the honest "awaiting wind feed" state and lights the moment the
    /// key lands. We decode a screen-local projection of `escorts.getCorridor`
    /// (mirrors the `EscortCorridorCoords` pattern) so the shared
    /// `EscortAPI.EscortCorridor` model stays untouched — 601 only needs
    /// the gate envelope, not the full corridor topology.
    @State private var windGate: EscortWindGateEnvelope? = nil

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
        .task { await refreshAll() }
        .eusoRefreshable { await refreshAll() }
        // Corridor-map sheet — opened by tapping the "View corridor →"
        // drill-in CTA. Detents `[.large]` mirrors the Me sub-route
        // pattern in MeDetailScreens. The corridor screen reads from
        // `escorts.getCorridor` independently, so the parent's detail
        // fetch does not block the corridor open.
        .sheet(isPresented: $showCorridorMap) {
            let live: EscortAPI.AssignmentDetail? = detailStore.state.value ?? nil
            EscortCorridorMapScreen(
                theme: palette,
                assignmentId: assignmentId,
                previewLoadNumber: live?.loadNumber ?? previewLoadNumber,
                previewLane: corridorLanePreview,
                previewStatus: live?.status
            )
            .environmentObject(session)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    /// Lane string used as a preview hint when opening the 602 sheet —
    /// avoids a paint-1 blank header on the corridor screen.
    private var corridorLanePreview: String? {
        if let live = detailStore.state.value ?? nil {
            return "\(live.origin) → \(live.destination)"
        }
        return previewLane
    }

    // MARK: - Header

    private var header: some View {
        let live: EscortAPI.AssignmentDetail? = detailStore.state.value ?? nil
        let loadNumber = live?.loadNumber ?? previewLoadNumber ?? "-"
        let lane: String = {
            if let live { return "\(live.origin) → \(live.destination)" }
            return previewLane ?? "-"
        }()
        let status = live?.status ?? ""

        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
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
                        Text("ESCORT · ASSIGNMENT DETAIL")
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    Text(loadNumber)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
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
                    systemImage: "shield.lefthalf.filled",
                    title: "Assignment not found",
                    subtitle: "This corridor is no longer on your plate. Pull to refresh or pick another assignment from the home."
                )
            }
        case .empty:
            EusoEmptyState(
                systemImage: "shield.lefthalf.filled",
                title: "Assignment not found",
                subtitle: "This corridor is no longer on your plate. Pull to refresh or pick another assignment from the home."
            )
        case .error(let err):
            errorBanner(message: readableError(err))
        }
    }

    // MARK: - Detail cards (live data)

    @ViewBuilder
    private func detailCards(for detail: EscortAPI.AssignmentDetail) -> some View {
        metricsRow(detail)
        windGateChip(detail)
        routePreviewCard(detail)
        scheduleCard(detail)
        corridorCard(detail)
        pairingCard(detail)
        contactCard(detail)
        notesCard(detail)
        viewCorridorMapCTA(detail)
        confirmRouteCTA(detail)
    }

    // MARK: - Route-preview map (real corridor coordinates / honest seam)

    /// Static route-preview thumbnail above the CORRIDOR card: origin →
    /// destination corridor sketch on the in-house HERE vector basemap.
    /// This is the upstream half of the same seam the "View corridor"
    /// CTA drills into (602) — it surfaces the corridor at a glance
    /// without leaving the detail surface.
    ///
    /// Coordinates come from the proc's `originLat/originLng/destLat/destLng`
    /// (real `loads.pickupLocation` / `loads.deliveryLocation` JSON columns).
    /// Both endpoints are null-island gated: if either end is `(0,0)` — i.e.
    /// the load has no geocode yet — we render an honest "awaiting corridor
    /// coordinates" placeholder instead of fabricating a route. No hardcoded
    /// demo coordinates anywhere; the map lights up the moment the load's
    /// location JSON carries real lat/lng.
    @ViewBuilder
    private func routePreviewCard(_ d: EscortAPI.AssignmentDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("ROUTE PREVIEW", icon: "map.fill")
            if let coords = corridorCoords,
               let origin = coords.originCoordinate,
               let destination = coords.destinationCoordinate {
                let pickup = HereLatLng(origin.latitude, origin.longitude)
                let delivery = HereLatLng(destination.latitude, destination.longitude)
                let requestedPurpose = canonicalRoutePurpose(for: d.status)
                let markerLayer = HereMapLayer.markers([
                    HereMarker(at: pickup, kind: .pickup, label: d.origin.isEmpty ? nil : d.origin),
                    HereMarker(at: delivery, kind: .delivery, label: d.destination.isEmpty ? nil : d.destination)
                ])
                let mapLayers: [HereMapLayer] = canonicalRouteLines.enumerated().map { index, line in
                    .eusoRoute(
                        polyline: line,
                        state: canonicalResolvedPurpose == .activeJob ? .active : .planned,
                        label: index == 0
                            ? "Eusorone truck escort route plan version \(canonicalRouteVersion ?? 0)"
                            : nil
                    )
                } + [markerLayer]
                ZStack(alignment: .bottomLeading) {
                    HereLiveMapView(
                        center: canonicalRouteLines.lazy.compactMap(\.first).first
                            ?? HereLatLng(
                                (origin.latitude + destination.latitude) / 2,
                                (origin.longitude + destination.longitude) / 2
                            ),
                        zoom: 6,
                        interactive: false,
                        route: [],
                        baseLayers: mapLayers,
                        addOns: .shipperTracking,
                        showTicker: false,
                        activeJob: requestedPurpose == .activeJob,
                        mapModeContext: .escort(activeRoadEscort: true)
                    )
                    if let canonicalRouteStatus {
                        canonicalRouteStatusPill(canonicalRouteStatus)
                            .padding(10)
                    }
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1)
                )
                .allowsHitTesting(false)
            } else {
                routePreviewAwaiting
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

    /// Honest empty state shown until the load's pickup/delivery location
    /// JSON carries real lat/lng (both endpoints non-null-island). Never a
    /// fabricated route — the corridor surfaces the moment coordinates land.
    private var routePreviewAwaiting: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Awaiting corridor coordinates")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("The route preview lights up once this load is geocoded. Tap \u{201C}View corridor\u{201D} for the full corridor map.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let canonicalRouteStatus {
                    Text(canonicalRouteStatus)
                        .font(EType.micro)
                        .foregroundStyle(Brand.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(canonicalRouteStatus)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(Space.s3)
        .background(palette.tintNeutral.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Drill-in CTA that opens the 602 corridor-map sheet. Added 2026-04-27
    /// in the 159th eusotrip-killers firing alongside the 602 brick.
    /// Closes the role-by-role 3-deep parity gap from the 158th firing
    /// (Escort was the only 2-deep non-driver role before this brick).
    @ViewBuilder
    private func viewCorridorMapCTA(_ d: EscortAPI.AssignmentDetail) -> some View {
        Button {
            showCorridorMap = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "map.fill")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("View corridor")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textSecondary)
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

    /// Three-tile row: corridor coverage / escort role / started.
    /// Em-dash on missing values so a brand-new assignment doesn't
    /// fabricate values.
    private func metricsRow(_ d: EscortAPI.AssignmentDetail) -> some View {
        HStack(spacing: Space.s2) {
            metricTile(
                label: "COVERAGE",
                value: coverage(d.corridorCoverage),
                icon: "scope"
            )
            metricTile(
                label: "ESCORT ROLE",
                value: roleDisplay(d.escortRole),
                icon: "car.2.fill"
            )
            metricTile(
                label: "STARTED",
                value: startedDisplay(d),
                icon: "clock"
            )
        }
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

    // MARK: - Wind-gust go/no-go chip (pre-roll gate)

    /// Pre-roll wind-gust go/no-go for the high-profile load. Binds the
    /// route-wide `windGate` envelope off `escorts.getCorridor`: the worst
    /// forecast gust along the corridor measured against the PUBLISHED
    /// escort caution/nogo wind thresholds (high-profile loads sail-area
    /// out at wind, so this is the operator's first roll/hold call).
    ///
    /// Bespoke glyph: `WeatherIcons.utility(.wind)` (ZERO SF Symbols on the
    /// weather element). Color reads the gate verdict — go (success) /
    /// caution (warning) / nogo (danger).
    ///
    /// Honest states:
    ///   • envelope nil (proc predates Wave 4 / corridor not fetched) → the
    ///     whole chip is HIDDEN (no fabricated verdict).
    ///   • envelope present but the gust feed is enterprise-gated
    ///     (`available == false`, gust null) → a neutral "wind feed pending"
    ///     chip that reads now and lights to a real verdict the moment the
    ///     enterprise key lands. Never a fabricated gust/verdict.
    @ViewBuilder
    private func windGateChip(_ d: EscortAPI.AssignmentDetail) -> some View {
        if let gate = windGate {
            if gate.available, let verdict = gate.verdict {
                resolvedWindChip(gate, verdict)
            } else {
                pendingWindChip(gate)
            }
        }
        // gate == nil ⇒ render nothing (honest absence — no wind data).
    }

    /// The lit chip — a real go/caution/nogo verdict from a real worst-gust
    /// reading against the published thresholds.
    private func resolvedWindChip(
        _ gate: EscortWindGateEnvelope,
        _ verdict: EscortWindStatus
    ) -> some View {
        let tint = verdict.color
        return HStack(spacing: 10) {
            WeatherIcons.utility(.wind, size: 18, tint: tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("WIND GATE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(palette.textTertiary)
                    Text(verdict.label)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(tint)
                        .clipShape(Capsule())
                }
                Text(windGateDetail(gate, verdict))
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let basis = gate.basis, !basis.isEmpty {
                    Text(basis)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(tint.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// The honest pending chip — the gate envelope shipped, but the gust
    /// forecast is enterprise-gated (`available:false`), so we cannot
    /// resolve a verdict yet. Surfaces the published thresholds it WILL be
    /// measured against so the operator knows the gate is armed and what it
    /// keys off — it never fabricates a gust or a go/no-go.
    private func pendingWindChip(_ gate: EscortWindGateEnvelope) -> some View {
        HStack(spacing: 10) {
            WeatherIcons.utility(.wind, size: 18, tint: palette.textTertiary)
                .frame(width: 30, height: 30)
                .background(palette.tintNeutral.opacity(0.5))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("WIND GATE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Text("Wind-gust feed pending")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text(windThresholdsLine(gate)
                     ?? "Lights a roll / hold call once the gust forecast is provisioned.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let basis = gate.basis, !basis.isEmpty {
                    Text(basis)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.tintNeutral.opacity(0.4))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Detail line for the lit chip — the real worst gust + the threshold
    /// it tripped (or cleared). Built only from present fields; absent
    /// numbers fold out (never a fabricated gust).
    private func windGateDetail(
        _ gate: EscortWindGateEnvelope,
        _ verdict: EscortWindStatus
    ) -> String {
        let gustPart: String? = gate.gustMph.map { "Gust \(Int($0.rounded())) mph" }
        let thresholdPart: String?
        switch verdict {
        case .nogo:
            thresholdPart = gate.nogoMph.map { "≥ no-go \(Int($0.rounded())) mph" }
        case .caution:
            thresholdPart = gate.cautionMph.map { "≥ caution \(Int($0.rounded())) mph" }
        case .go:
            thresholdPart = gate.cautionMph.map { "< caution \(Int($0.rounded())) mph" }
        }
        let parts = [gustPart, thresholdPart].compactMap { $0 }
        if parts.isEmpty { return verdict.sentence }
        return parts.joined(separator: " · ")
    }

    /// The published-threshold line for the pending chip ("Caution N · No-go
    /// M mph"). Nil when neither threshold is on the wire yet.
    private func windThresholdsLine(_ gate: EscortWindGateEnvelope) -> String? {
        var parts: [String] = []
        if let c = gate.cautionMph { parts.append("Caution \(Int(c.rounded()))") }
        if let n = gate.nogoMph { parts.append("No-go \(Int(n.rounded())) mph") }
        guard !parts.isEmpty else { return nil }
        return "Arms against " + parts.joined(separator: " · ")
    }

    /// Lane / origin / destination + routed miles when present.
    private func scheduleCard(_ d: EscortAPI.AssignmentDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("CORRIDOR", icon: "map")
            scheduleRow(label: "Origin",      value: d.origin.isEmpty ? "-" : d.origin)
            scheduleRow(label: "Destination", value: d.destination.isEmpty ? "-" : d.destination)
            if let miles = d.routedMiles, miles > 0 {
                scheduleRow(label: "Routed miles", value: milesString(miles))
            }
            if let route = d.routeName, !route.isEmpty {
                scheduleRow(label: "Route", value: route)
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

    /// Permit + hazmat + OS-OW context. Rows only render when the
    /// underlying field is set, so a permit-less assignment doesn't
    /// surface "Permit: —" filler.
    @ViewBuilder
    private func corridorCard(_ d: EscortAPI.AssignmentDetail) -> some View {
        // Decide whether anything in this card has signal — if all
        // fields are empty, skip the section entirely.
        let hasPermit  = !d.permitNumber.isEmpty
        let hasHazmat  = (d.hazmatClass?.isEmpty == false)
        let hasUN      = (d.unNumber?.isEmpty == false)
        let hasOS      = (d.oversizeFlag == true)
        let hasOW      = (d.overweightFlag == true)
        let hasBridge  = (d.bridgeClearanceFt.map { $0 > 0 } ?? false)
        if hasPermit || hasHazmat || hasUN || hasOS || hasOW || hasBridge {
            VStack(alignment: .leading, spacing: Space.s2) {
                sectionHeader("PERMIT & COMPLIANCE", icon: "doc.badge.gearshape.fill")
                if hasPermit {
                    scheduleRow(label: "Permit", value: d.permitNumber)
                }
                if hasHazmat {
                    scheduleRow(label: "Hazmat class", value: d.hazmatClass!)
                }
                if hasUN {
                    scheduleRow(label: "UN number", value: d.unNumber!)
                }
                if hasOS || hasOW {
                    let chips: [String] = {
                        var c: [String] = []
                        if hasOS { c.append("OS") }
                        if hasOW { c.append("OW") }
                        return c
                    }()
                    scheduleRow(label: "Dimensional", value: chips.joined(separator: " · "))
                }
                if hasBridge, let bc = d.bridgeClearanceFt {
                    scheduleRow(label: "Bridge clearance", value: clearanceString(bc))
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
    }

    /// Lead / chase pairing identifiers. Only renders when at least
    /// one slot is filled.
    @ViewBuilder
    private func pairingCard(_ d: EscortAPI.AssignmentDetail) -> some View {
        let lead = d.leadVehicleId ?? ""
        let chase = d.chaseVehicleId ?? ""
        if !lead.isEmpty || !chase.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                sectionHeader("LEAD / CHASE", icon: "car.2.fill")
                if !lead.isEmpty {
                    scheduleRow(label: "Lead vehicle",  value: lead)
                }
                if !chase.isEmpty {
                    scheduleRow(label: "Chase vehicle", value: chase)
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
    }

    /// Driver / shipper contacts. Only renders when at least one
    /// field is set.
    @ViewBuilder
    private func contactCard(_ d: EscortAPI.AssignmentDetail) -> some View {
        let driver = d.driverName ?? ""
        let driverPhone = d.driverPhone ?? ""
        let shipper = d.shipperName ?? ""
        if !driver.isEmpty || !driverPhone.isEmpty || !shipper.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                sectionHeader("CONTACT", icon: "person.crop.circle")
                if !driver.isEmpty {
                    scheduleRow(label: "Driver", value: driver)
                }
                if !driverPhone.isEmpty {
                    scheduleRow(label: "Driver phone", value: driverPhone)
                }
                if !shipper.isEmpty {
                    scheduleRow(label: "Shipper", value: shipper)
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
    }

    /// Free-form corridor notes from dispatch. Only renders when set.
    @ViewBuilder
    private func notesCard(_ d: EscortAPI.AssignmentDetail) -> some View {
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

    // MARK: - Confirm route CTA

    /// "Confirm route" CTA. Drives `escorts.confirmRoute` and re-paints
    /// the cell from the mutation envelope. Disabled while the detail
    /// fetch is loading, while the mutation is in flight, and once the
    /// route has already been confirmed (server flag or local override).
    @ViewBuilder
    private func confirmRouteCTA(_ d: EscortAPI.AssignmentDetail) -> some View {
        // Only show the CTA on assignments where confirming is
        // plausible — the corridor must be in a pre-roll or live
        // status. Anything past `completed` / `cancelled` suppresses
        // the CTA so we don't offer a no-op.
        let confirmable: Set<String> = [
            "pending", "dispatched", "enroute", "at_origin", "at_destination"
        ]
        let alreadyConfirmed = (d.routeConfirmed == true) || localConfirmed
        if confirmable.contains(d.status.lowercased()) {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    Task { await confirmRoute(id: d.id) }
                } label: {
                    HStack(spacing: 8) {
                        if confirmInFlight {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: alreadyConfirmed ? "checkmark.circle.fill" : "arrow.up.right.circle.fill")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                        Text(alreadyConfirmed ? "Route confirmed" : "Confirm route")
                            .font(.system(size: 13, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background { LinearGradient.diagonal.opacity(alreadyConfirmed ? 0.55 : 1.0) }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(alreadyConfirmed || confirmInFlight)

                if let msg = confirmError, !msg.isEmpty {
                    Text(msg)
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !alreadyConfirmed && confirmError == nil {
                    Text("Confirms this corridor with dispatch and arms the lead/chase pairing for departure. Sends `escorts.confirmRoute`.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func confirmRoute(id: String) async {
        guard !id.isEmpty, !confirmInFlight else { return }
        confirmInFlight = true
        confirmError = nil
        defer { confirmInFlight = false }
        do {
            let updated = try await EusoTripAPI.shared.escort.confirmRoute(id: id)
            // Re-paint the cell from the mutation envelope and flip
            // the local override so the CTA disables immediately.
            detailStore.state = .loaded(updated)
            localConfirmed = true
        } catch {
            confirmError = readableError(error)
        }
    }

    // MARK: - Loading + error states

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            sectionHeader("LOADING", icon: "arrow.clockwise")
            Text("Pulling the latest from the assignment record…")
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
        }
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

    /// "Live" framing for an escort assignment — anything pre-roll
    /// or rolling is gradient. Past completion reads as neutral.
    private var liveStatuses: Set<String> {
        ["pending", "dispatched", "enroute", "at_origin", "at_destination"]
    }

    /// Format a corridor-coverage ratio (0.0…1.0) as a percentage
    /// rounded to whole digits. Returns "-" for zero so the empty
    /// case never renders as "0%".
    private func coverage(_ v: Double) -> String {
        guard v > 0 else { return "-" }
        return "\(Int((v * 100).rounded()))%"
    }

    /// Sentence-case the server enum so the metric tile reads
    /// "Lead", "Chase", or "Lead+Chase" instead of the raw token.
    private func roleDisplay(_ raw: String) -> String {
        guard !raw.isEmpty else { return "-" }
        switch raw.lowercased() {
        case "lead":         return "Lead"
        case "chase":        return "Chase"
        case "lead+chase",
             "lead_chase",
             "leadchase":    return "Lead + Chase"
        default:             return raw.capitalized
        }
    }

    /// "started 2m" — server-projected relative label from the
    /// ActiveAssignment row. Falls back to the AssignmentDetail.startedAt
    /// when the row hint is missing. Em-dash when both are absent.
    private func startedDisplay(_ d: EscortAPI.AssignmentDetail) -> String {
        if let s = previewStartedAt, !s.isEmpty {
            return s
        }
        return humanDate(d.startedAt)
    }

    /// Format escort-corridor mileage as a thousands-separated whole-mile
    /// string. Returns "-" for zero so the empty case never renders as
    /// "0 mi".
    private func milesString(_ v: Double) -> String {
        guard v > 0 else { return "-" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let core = f.string(from: NSNumber(value: v)) ?? "\(Int(v))"
        return "\(core) mi"
    }

    /// Format bridge clearance feet as a doctrinal "13'6\"" string.
    /// Returns "-" for zero.
    private func clearanceString(_ ft: Double) -> String {
        guard ft > 0 else { return "-" }
        let whole = Int(ft)
        let inches = Int(((ft - Double(whole)) * 12).rounded())
        if inches == 0 { return "\(whole)'" }
        return "\(whole)'\(inches)\""
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

    /// Operator-language copy for a failed read or commit. The error itself
    /// stays intact for logging; the escort reads a sentence they can act on,
    /// never a raw system error string.
    private func readableError(_ error: Error) -> String {
        guard let api = error as? EusoTripAPIError else {
            return "Something went wrong on this device. Try that again."
        }
        switch api {
        case .trpcError(let reason), .forbidden(let reason):
            return reason
        case .unauthenticated:
            return "Your sign-in has expired. Sign in again, then reopen this move."
        case .decodingFailed:
            return "This came back in a form this build can't read. Update the app, then try again."
        case .queuedForOfflineReplay:
            return "You're offline — this will send when you reconnect."
        case .httpStatus, .badURL, .notConfigured, .empty:
            return "Couldn't reach the network. Check your signal and try again."
        }
    }

    private func refreshAll() async {
        detailStore.assignmentId = assignmentId
        confirmError = nil
        await detailStore.refresh()
        // Re-sync the local override against whatever the server
        // says — if the assignment was re-opened upstream, reflect it.
        if case .loaded(let opt) = detailStore.state, let v = opt {
            localConfirmed = (v.routeConfirmed == true)
        }
        await loadCorridorCoords()
        await refreshCanonicalRoute()
        await loadWindGate()
    }

    /// Decode the corridor endpoint coordinates off the SAME proc the
    /// detail store reads (`escorts.getActiveAssignmentDetail`), via a
    /// screen-local coordinate-only Decodable. This keeps the shared
    /// `EscortAPI.AssignmentDetail` model untouched while still consuming
    /// the proc's real `originLat/originLng/destLat/destLng` fields
    /// (sourced from `loads.pickupLocation` / `loads.deliveryLocation`).
    /// On any failure (proc not yet deployed, transport error) the coords
    /// stay nil and the route preview falls back to its honest awaiting
    /// state — it never fabricates a route.
    private func loadCorridorCoords() async {
        guard !assignmentId.isEmpty else { return }
        do {
            let coords: EscortCorridorCoords = try await EusoTripAPI.shared.query(
                "escorts.getActiveAssignmentDetail",
                input: EscortCorridorCoordsInput(id: assignmentId)
            )
            corridorCoords = coords
        } catch {
            // Honest seam: no coords → awaiting state, never a fake route.
            corridorCoords = nil
        }
    }

    private func canonicalRoutePurpose(for status: String) -> CanonicalRoutePlanClient.Purpose {
        let normalized = status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let active: Set<String> = [
            "accepted", "active", "dispatched", "en_route", "enroute",
            "at_origin", "at_destination"
        ]
        return active.contains(normalized) ? .activeJob : .planning
    }

    /// Escort assignments route through their underlying load subject. The
    /// assignment envelope must expose that exact binding; assignment IDs are
    /// never guessed to be load IDs. Until the server adds `loadId`, the map
    /// remains endpoint-reference-only with an explicit pending message.
    @MainActor
    private func refreshCanonicalRoute() async {
        canonicalRouteLines = []
        canonicalRouteVersion = nil
        canonicalResolvedPurpose = nil
        canonicalRouteStatus = "Verified escort route is still being prepared"
        guard let loadId = corridorCoords?.loadId, loadId > 0 else {
            canonicalRouteStatus = "This escort assignment is not yet linked to its load"
            return
        }
        let status = (detailStore.state.value ?? nil)?.status ?? ""
        let expectedPurpose = canonicalRoutePurpose(for: status)
        do {
            let result = try await CanonicalRoutePlanClient.shared.planLoad(
                id: loadId,
                purpose: expectedPurpose
            )
            switch result {
            case .persisted(let persisted):
                applyCanonicalRoute(persisted.route, expectedPurpose: expectedPurpose)
            case .pending(let pending):
                canonicalRouteStatus = pending.blockers.first?.message
                    ?? "Canonical mode-native escort route pending verified authority"
                await readExistingCanonicalRoute(loadId: loadId, expectedPurpose: expectedPurpose)
            }
        } catch {
            canonicalRouteStatus = error.eusoUserCopy
            await readExistingCanonicalRoute(loadId: loadId, expectedPurpose: expectedPurpose)
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
              route.plan.identity.mode == .truck,
              let payload = route.rendererPayload else {
            canonicalRouteLines = []
            canonicalRouteVersion = nil
            canonicalResolvedPurpose = nil
            canonicalRouteStatus = "Canonical truck escort route exists but is not released for rendering"
            return
        }
        canonicalRouteLines = payload.lines
        canonicalRouteVersion = payload.identity.version
        canonicalResolvedPurpose = route.plan.purpose
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

    /// Decode the route-wide `windGate` envelope off the SAME corridor proc
    /// (`escorts.getCorridor`) the 602 map reads, via a screen-local
    /// `windGate`-only Decodable. Keeps the shared `EscortAPI.EscortCorridor`
    /// model untouched while still consuming the Wave-4 `windGate` block
    /// (route-wide status + gust vs the published caution/nogo thresholds,
    /// each carrying its operating-standard `basis`). On any failure (proc
    /// predates Wave 4, transport error, or no envelope) the gate stays nil
    /// and the chip is hidden — it never fabricates a gust or a verdict.
    private func loadWindGate() async {
        guard !assignmentId.isEmpty else { return }
        do {
            let env: EscortWindGateProjection = try await EusoTripAPI.shared.query(
                "escorts.getCorridor",
                input: EscortCorridorCoordsInput(id: assignmentId)
            )
            windGate = env.windGate
        } catch {
            windGate = nil
        }
    }
}

// MARK: - Wind-gate projection (pre-roll go/no-go chip)

/// Go/caution/nogo verdict for the route-wide wind gate. Server enum
/// `go|caution|nogo`; anything unmapped folds to `nil` (hidden — never a
/// fabricated verdict).
private enum EscortWindStatus: String, Decodable {
    case go, caution, nogo

    /// Doctrinal verdict color — go (success) / caution (warning) /
    /// nogo (danger).
    var color: Color {
        switch self {
        case .go:      return Brand.success
        case .caution: return Brand.warning
        case .nogo:    return Brand.danger
        }
    }

    /// Pill label.
    var label: String {
        switch self {
        case .go:      return "GO"
        case .caution: return "CAUTION"
        case .nogo:    return "NO-GO"
        }
    }

    /// Plain-language fallback when no numeric gust/threshold is on the
    /// wire (still a REAL server verdict, just no figures to show).
    var sentence: String {
        switch self {
        case .go:      return "Corridor winds within escort limits."
        case .caution: return "Gusting toward the escort caution band."
        case .nogo:    return "Gusts exceed the escort no-go limit — hold."
        }
    }
}

/// Route-wide wind-gate envelope decoded from `escorts.getCorridor.windGate`.
/// The high-profile load's sail area makes wind the first roll/hold call, so
/// 601 pre-rolls this gate before the operator scrolls. The gust forecast is
/// enterprise-gated (`available:false`) today — when so, `verdict`/`gustMph`
/// arrive nil and the chip renders its honest pending state. The
/// `cautionMph`/`nogoMph` thresholds are PUBLISHED operating standards
/// (carried with a `basis`), so they can light the pending chip even before
/// the gust feed is provisioned. All fields optional so a partial / older
/// envelope still decodes.
private struct EscortWindGateEnvelope: Decodable {
    /// Whether the gust forecast feed is provisioned. Mirrors the server's
    /// enterprise gate; `false`/absent ⇒ pending chip (no verdict).
    let available: Bool
    /// Route-wide verdict. Nil while enterprise-gated.
    let verdict: EscortWindStatus?
    /// Worst forecast gust along the corridor, mph. Nil while gated.
    let gustMph: Double?
    /// Published caution threshold (mph) the gate arms against.
    let cautionMph: Double?
    /// Published no-go threshold (mph) the gate arms against.
    let nogoMph: Double?
    /// Operating-standard basis label for the thresholds (e.g. the
    /// published escort wind standard the server measures against).
    let basis: String?

    enum CodingKeys: String, CodingKey {
        case available, status, verdict
        case gust, gustMph, forecastGustKt
        case cautionMph, nogoMph, basis
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `available` may be absent on older envelopes — default false so a
        // partial envelope reads as pending (honest), never as a verdict.
        self.available = ((try? c.decodeIfPresent(Bool.self, forKey: .available)) ?? nil) ?? false
        // Verdict can arrive under `verdict` or `status`.
        let rawStatus = (try? c.decodeIfPresent(EscortWindStatus.self, forKey: .verdict)) ?? nil
            ?? ((try? c.decodeIfPresent(EscortWindStatus.self, forKey: .status)) ?? nil)
        self.verdict = rawStatus
        // Gust can arrive as mph (`gust`/`gustMph`) — prefer an explicit mph
        // field; never convert a knot field into a fake mph reading.
        self.gustMph = ((try? c.decodeIfPresent(Double.self, forKey: .gustMph)) ?? nil)
            ?? ((try? c.decodeIfPresent(Double.self, forKey: .gust)) ?? nil)
        self.cautionMph = (try? c.decodeIfPresent(Double.self, forKey: .cautionMph)) ?? nil
        self.nogoMph = (try? c.decodeIfPresent(Double.self, forKey: .nogoMph)) ?? nil
        self.basis = (try? c.decodeIfPresent(String.self, forKey: .basis)) ?? nil
    }
}

/// Top-level projection that decodes ONLY the `windGate` block off the
/// `escorts.getCorridor` envelope, ignoring the full corridor topology.
private struct EscortWindGateProjection: Decodable {
    let windGate: EscortWindGateEnvelope?

    enum CodingKeys: String, CodingKey { case windGate }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.windGate = (try? c.decodeIfPresent(EscortWindGateEnvelope.self, forKey: .windGate)) ?? nil
    }
}

// MARK: - Corridor coordinate projection (route-preview map)

/// Input echo for the coordinate-only decode of
/// `escorts.getActiveAssignmentDetail`. Mirrors the proc's `{ id: string }`
/// Zod input.
private struct EscortCorridorCoordsInput: Encodable {
    let id: String
}

/// Coordinate-only projection of the `escorts.getActiveAssignmentDetail`
/// envelope. The proc returns the full assignment detail; this struct
/// decodes the optional exact load binding plus the four real corridor-
/// endpoint coordinate fields the route-preview map needs, ignoring
/// everything else. The fields come
/// straight off `loads.pickupLocation.lat/lng` + `loads.deliveryLocation`
/// (`fmtLoc`), the same real columns the shipper LoadDetail hero map reads.
///
/// Missing or partial endpoints stay nil when an older proc omits them or a
/// load has no geocode. No coordinate is synthesized here.
private struct EscortCorridorCoords: Decodable {
    /// Exact load subject behind the escort assignment. Older server
    /// envelopes omit it; nil is an intentional fail-closed state.
    let loadId: Int?
    let originLat: Double?
    let originLng: Double?
    let destLat: Double?
    let destLng: Double?

    enum CodingKeys: String, CodingKey {
        case loadId, originLat, originLng, destLat, destLng
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? c.decode(Int.self, forKey: .loadId) {
            loadId = value
        } else if let raw = try? c.decode(String.self, forKey: .loadId) {
            loadId = Int(raw)
        } else {
            loadId = nil
        }
        originLat = try c.decodeIfPresent(Double.self, forKey: .originLat)
        originLng = try c.decodeIfPresent(Double.self, forKey: .originLng)
        destLat = try c.decodeIfPresent(Double.self, forKey: .destLat)
        destLng = try c.decodeIfPresent(Double.self, forKey: .destLng)
    }

    var originCoordinate: CLLocationCoordinate2D? {
        LatLongParser.validatedCoordinate(latitude: originLat, longitude: originLng)
    }

    var destinationCoordinate: CLLocationCoordinate2D? {
        LatLongParser.validatedCoordinate(latitude: destLat, longitude: destLng)
    }
}

// MARK: - Screen wrapper (Shell + BottomNav)

struct EscortAssignmentDetailScreen: View {
    let theme: Theme.Palette
    let assignmentId: String
    let previewLoadNumber: String?
    let previewLane: String?
    let previewStartedAt: String?
    let previewEscortRole: String?
    let previewPermitNumber: String?
    let previewCorridorCoverage: Double?

    init(
        theme: Theme.Palette,
        assignmentId: String,
        previewLoadNumber: String? = nil,
        previewLane: String? = nil,
        previewStartedAt: String? = nil,
        previewEscortRole: String? = nil,
        previewPermitNumber: String? = nil,
        previewCorridorCoverage: Double? = nil
    ) {
        self.theme = theme
        self.assignmentId = assignmentId
        self.previewLoadNumber = previewLoadNumber
        self.previewLane = previewLane
        self.previewStartedAt = previewStartedAt
        self.previewEscortRole = previewEscortRole
        self.previewPermitNumber = previewPermitNumber
        self.previewCorridorCoverage = previewCorridorCoverage
    }

    var body: some View {
        Shell(theme: theme) {
            EscortAssignmentDetail(
                assignmentId: assignmentId,
                previewLoadNumber: previewLoadNumber,
                previewLane: previewLane,
                previewStartedAt: previewStartedAt,
                previewEscortRole: previewEscortRole,
                previewPermitNumber: previewPermitNumber,
                previewCorridorCoverage: previewCorridorCoverage
            )
        } nav: {
            BottomNav(
                leading: escortNavLeading_601(),
                trailing: escortNavTrailing_601(),
                orbState: .idle
            )
        }
    }
}

private func escortNavLeading_601() -> [NavSlot] {
    EscortNavRoute.leading(current: .assignments)
}

private func escortNavTrailing_601() -> [NavSlot] {
    EscortNavRoute.trailing(current: .assignments)
}

// MARK: - Previews
//
// Previews don't run `.task`, so the store stays in `.loading` —
// both registers render the loading skeleton without hitting the
// network. Per doctrine §10: previews must compile in isolation.

#Preview("601 · Escort · Assignment Detail · Night") {
    EscortAssignmentDetailScreen(
        theme: Theme.dark,
        assignmentId: "0",
        previewLoadNumber: "-",
        previewLane: "-",
        previewStartedAt: nil,
        previewEscortRole: nil,
        previewPermitNumber: nil,
        previewCorridorCoverage: nil
    )
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.dark)
}

#Preview("601 · Escort · Assignment Detail · Afternoon") {
    EscortAssignmentDetailScreen(
        theme: Theme.light,
        assignmentId: "0",
        previewLoadNumber: "-",
        previewLane: "-",
        previewStartedAt: nil,
        previewEscortRole: nil,
        previewPermitNumber: nil,
        previewCorridorCoverage: nil
    )
    .environmentObject(EusoTripSession())
    .preferredColorScheme(.light)
}
