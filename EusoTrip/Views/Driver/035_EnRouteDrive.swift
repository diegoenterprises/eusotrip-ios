//
//  035_EnRouteDrive.swift
//  EusoTrip 2027 UI — Wave 2 (main haul · turn-by-turn)
//
//  Screen 035 · En Route Drive — the driver has departed the pickup (034)
//  and is now on the main haul. The route is the exact server-owned,
//  source-bound geometry and is painted as the single uncased EusoLine
//  gradient. A server-projected current observation may release tilted close
//  guidance, speed/course, ETA/remaining, and the next instruction. Stale,
//  off-route, unobserved, unlicensed, version-mismatched, or unavailable
//  evidence pauses those claims. The screen never uploads a device-authored
//  coordinate, progress, speed, course, ETA, or maneuver.
//
//  The screen is map-first: the verified maneuver banner, map controls,
//  execution truth chip, live speed/course card, and bottom summary float on
//  the map canvas. The driver's only primary actions are:
//      • Exit (red) — stop nav + open exception flow
//      • Mute/voice — toggle ESANG voice coaching
//
//  Doctrine refs:
//    §2  nav invariants — no secondary chrome; BottomNav with Trips current.
//    §4.3 iridescent hairline → the route polyline IS the hairline on this
//         screen; gradient stroke, diagonal topLeading→bottomTrailing.
//    §6   dual register; both Dark + Light previews at the bottom.
//    §7   breathe density; map is the canvas, discs and cards float.
//    §8   Driver rhythm — turn banner → map → speed + summary card.
//    §11  visible operational copy is server-evidence-driven, never fixture data.
//

import SwiftUI
import CoreLocation
import Foundation

// MARK: - Screen

struct EnRouteDrive: View {
    @Environment(\.palette) var palette
    @Environment(\.lifecycleExit) private var lifecycleExit
    @Environment(\.driverToggleVoiceMute) private var toggleVoiceMute
    @EnvironmentObject private var session: EusoTripSession
    @AppStorage("com.eusorone.EusoTrip.voice.muted") private var voiceCoachMuted = false

    @StateObject private var lifecycle = TripLifecycleStore()
    @StateObject private var hos = HOSLiveStore()
    @State private var activeLoad: Load?
    @State private var presentsOfflineRoadDesk = false
    @State private var appRadioSilenceLease: AppRadioSilenceLease?

    /// §3 per-load weather for the ACTIVE haul — the canonical
    /// `weather.forLoad` store (origin/dest realtime + LaneImpact peakLeg/
    /// riskTier/drivers). Drives the bespoke route-cell hazard band over the
    /// active route + the severe-cell ETA annotation. Honesty doctrine: the
    /// store keeps last-good + `isStale` on failure and the card is
    /// enterprise-gated server-side (expect `available:false` / nil today),
    /// so every weather affordance HIDES until a real actionable risk lands.
    @StateObject private var wx = WeatherCardStore()

    /// Exact independent lines released by the committed server route binding.
    /// No device-authored endpoints, profile, geometry, or mode coercion.
    @State private var canonicalRouteLines: [[HereLatLng]] = []
    @State private var canonicalRouteStatus: String?
    @State private var canonicalRouteVersion: Int?
    @State private var canonicalRoutePlanVersionID: CanonicalRoutePlanClient.UnsignedBigIntID?
    @State private var canonicalRouteMode: CanonicalRoutePlanClient.Mode?

    /// The server is the sole execution authority. This screen never uploads a
    /// coordinate, speed, course, progress, ETA, or maneuver claim. A decoded
    /// state is retained only when it names the exact route-plan version that
    /// is currently rendered above.
    @State private var canonicalExecutionState: CanonicalRoutePlanClient.ExecutionState?
    @State private var canonicalExecutionStatusOverride: String?
    @State private var mapRecenterGeneration = 0

    /// §3c receiver fence on the main-haul corridor terminus (map-layer
    /// adoption 2026-06-10). Resolved from a REAL `tracking.getGeofences`
    /// row matched against the load's delivery coordinate — the ring is
    /// the row's own center + radius (meters). nil ⇒ no ring is painted
    /// (honest absence; the radius is never invented). Mirrors 013/018.
    @State private var receiverFence: TrackingGeofencesAPI.ResolvedFence?

    enum Register { case dark, light }
    let register: Register

    // Invariants (shared across both registers)
    private let loadBinderId = "ESO-89xxxxxxx"

    /// Vertical + product dispatcher. Hazmat reroute, binder coverage,
    /// and any product-aware copy on this screen reads from `ctx` so
    /// a dry-van load never paints a tunnel-skip banner and a reefer
    /// load surfaces cold-chain trace instead of an NH3 binder figure.
    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: Canonical live guidance

    /// A second identity check at the final presentation boundary. Even if a
    /// stale async request completes after a new route is rendered, its state
    /// cannot move the camera or release navigation facts.
    private var canonicalGuidance: CanonicalRoutePlanClient.ExecutionGuidanceSnapshot? {
        guard let expectedVersionID = canonicalRoutePlanVersionID,
              let state = canonicalExecutionState,
              state.assignment.routePlanVersionId == expectedVersionID,
              state.mode == canonicalRouteMode else { return nil }
        return state.guidanceSnapshot
    }

    private var executionPollIdentity: String {
        "\(activeLoad?.id ?? 0):\(canonicalRoutePlanVersionID?.rawValue ?? "pending")"
    }

    private var executionStatusText: String {
        if let canonicalExecutionStatusOverride { return canonicalExecutionStatusOverride }
        guard canonicalRoutePlanVersionID != nil else { return "ROUTE AUTHORITY PENDING" }
        guard let state = canonicalExecutionState else { return "LIVE POSITION PENDING" }
        if let guidance = canonicalGuidance {
            return guidance.evidenceState == .arrived
                ? "ARRIVAL VERIFIED"
                : "LIVE · \(guidance.observation.provider.uppercased())"
        }
        if state.observation?.operationalUseAllowed == false {
            return "GUIDANCE PAUSED · SOURCE NOT RELEASED"
        }
        if let observation = state.observation,
           observation.freshnessState != .current {
            return "GUIDANCE PAUSED · POSITION STALE"
        }
        if let observation = state.observation,
           observation.qualityState == .conflicted || observation.qualityState == .rejected {
            return "GUIDANCE PAUSED · POSITION UNVERIFIED"
        }
        switch state.evidenceState {
        case .unobserved:
            return "LIVE POSITION PENDING"
        case .stale:
            return "GUIDANCE PAUSED · POSITION STALE"
        case .offRoute:
            return "OFF ROUTE · VERIFIED REROUTE REQUIRED"
        case .arrived:
            return "ARRIVAL OBSERVED · GUIDANCE PAUSED"
        case .current:
            if state.projection?.status == .offRoute {
                return "OFF ROUTE · VERIFIED REROUTE REQUIRED"
            }
            return "GUIDANCE PAUSED · EVIDENCE INCOMPLETE"
        }
    }

    private var turnDistanceValue: (value: String, unit: String, spoken: String)? {
        guard let guidance = canonicalGuidance,
              let instruction = guidance.nextInstruction,
              let trigger = instruction.triggerDistanceMeters?.uint64Value,
              let travelled = guidance.projection.distanceAlongMeters?.uint64Value,
              trigger >= travelled else { return nil }
        return Self.distanceDisplay(meters: trigger - travelled)
    }

    private var turnDistance: String { turnDistanceValue?.value ?? "—" }
    private var turnDistanceUnit: String { turnDistanceValue?.unit ?? "" }

    private var turnHeadline: String {
        if let instruction = canonicalGuidance?.nextInstruction { return instruction.title }
        if canonicalGuidance?.evidenceState == .arrived { return "Arrival verified" }
        return canonicalExecutionState == nil ? "Awaiting live position" : "Guidance paused"
    }

    private var turnSubhead: String {
        canonicalGuidance?.nextInstruction?.visualText ?? executionStatusText
    }

    private var turnInstructionAccessibility: String {
        guard let instruction = canonicalGuidance?.nextInstruction else {
            return executionStatusText
        }
        if let distance = turnDistanceValue {
            return "In \(distance.spoken), \(instruction.accessibilityText)"
        }
        return instruction.accessibilityText
    }

    private var turnSystemImage: String {
        guard let guidance = canonicalGuidance else { return "pause.fill" }
        guard guidance.evidenceState != .arrived else { return "flag.checkered" }
        let type = guidance.nextInstruction?.instructionType.lowercased() ?? ""
        if type.contains("u_turn") || type.contains("uturn") {
            return type.contains("left") ? "arrow.uturn.left" : "arrow.uturn.right"
        }
        if type.contains("left") { return "arrow.turn.up.left" }
        if type.contains("right") { return "arrow.turn.up.right" }
        return "arrow.up"
    }

    /// Hazmat reroute callout — ctx-driven. Returns empty for
    /// non-hazmat loads so the band hides. Empty when no live load
    /// either (the band is meaningless without a hazmat context).
    private var hazmatReroute: String { ctx.enRouteHazmatBand }

    /// Speed and course are released only from the accepted observation. The
    /// route-execution contract does not yet carry a speed limit, so this
    /// screen deliberately renders no speed-limit sign.
    private var currentSpeed: String {
        guard let metersPerSecond = canonicalGuidance?.observation.speedMetersPerSecond else {
            return "—"
        }
        return String(Int((metersPerSecond * 2.236_936_292_054_4).rounded()))
    }

    private var currentCourse: String? {
        guard let degrees = canonicalGuidance?.observation.courseDegrees else { return nil }
        let normalized = Int(degrees.rounded()) % 360
        return String(format: "COURSE %03d°", normalized)
    }

    private var currentSpeedAccessibility: String {
        guard canonicalGuidance?.observation.speedMetersPerSecond != nil else {
            return "Current speed unavailable; \(executionStatusText.lowercased())"
        }
        var label = "Current speed \(currentSpeed) miles per hour"
        if let currentCourse { label += ", \(currentCourse.lowercased())" }
        return label
    }

    private var etaBig: String {
        guard let guidance = canonicalGuidance else { return "—" }
        if guidance.projection.status == .arrived { return "ARRIVED" }
        guard let eta = guidance.projection.eta,
              let date = Self.parseExecutionInstant(eta) else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private var etaSub: String {
        guard let guidance = canonicalGuidance else { return executionStatusText }
        var parts: [String] = []
        if let seconds = guidance.projection.remainingSeconds?.uint64Value {
            parts.append(Self.durationDisplay(seconds: seconds))
        }
        if let meters = guidance.projection.remainingMeters?.uint64Value {
            parts.append("\(Self.distanceDisplay(meters: meters).spoken) remaining")
        }
        return parts.isEmpty ? executionStatusText : parts.joined(separator: " · ")
    }

    /// Live HOS drive bank from HOSLiveStore. `drivingRemaining` is
    /// hours-remaining-in-the-11h drive window (Double). Uses the
    /// model's own `drivingRemainingDisplay` formatter so the same
    /// "Xh YYm" string the HOS dashboard renders shows up here.
    /// Em-dash until the store hydrates a status snapshot.
    private var hosDriveLeft: String {
        guard let status = hos.status, status.hasCurrentObservation() else { return "—" }
        return status.drivingRemainingDisplay
    }

    /// In-transit binder summary — product-aware at runtime, neutral
    /// "binder" placeholder when no live load is hydrated.
    private var shieldValue: String {
        guard activeLoad != nil else { return "BINDER -" }
        return ctx.enRouteBinderValue
    }

    // Ping position, normalized to the map frame

    // MARK: §3 weather — live or honest-empty (Waves 1-3b-server)
    //
    // Every weather affordance below reads from `wx.card` (weather.forLoad).
    // Weather is enterprise-gated server-side, so the card arrives with
    // `available:false` / a `LaneImpact` whose `riskTier == .none` until the
    // key lands — and EVERY accessor returns nil/false in that state so the
    // band + chip + ETA pill stay hidden. No fabricated risk, ever.

    /// The §3 LaneImpact for the active load — only when the server marked
    /// the per-load card AND the lane impact `available` and the tier is
    /// actionable (watch+). nil ⇒ no band, no pill (honest absence).
    private var activeLaneImpact: WeatherForLoad.LaneImpact? {
        guard let card = wx.card, card.available, card.hasLaneRisk else { return nil }
        return card.laneImpact
    }

    /// The §3 risk tier driving the band intensity + ETA pill — nil when
    /// no actionable lane risk is live.
    private var weatherRiskTier: LaneRiskTier? {
        activeLaneImpact.map { $0.riskTier }
    }

    /// The peak leg the route reduction surfaced ("I-83 N · 4 PM") — the
    /// band labels itself from this, never a fabricated segment.
    private var weatherPeakLeg: WeatherForLoad.LaneImpact.PeakLeg? {
        activeLaneImpact?.peakLeg
    }

    /// True when a §3 driver indicates a freezing / wet-pavement hazard
    /// (ICE PELLETS / FREEZING / SLEET / wet PRECIP) — drives the
    /// ice/wet-pavement-ahead warning chip. Reads the server-formatted
    /// driver fields/values verbatim; absent ⇒ chip hidden.
    private var pavementHazard: PavementHazard? {
        guard let drivers = activeLaneImpact?.drivers else { return nil }
        for d in drivers {
            let f = d.field.lowercased()
            let v = d.value.lowercased()
            // Em-dash / empty values never trip the chip (honest).
            let hasValue = !v.isEmpty && v != "—" && v != "-"
            if (f.contains("ice") || f.contains("freez") || f.contains("sleet")
                || v.contains("ice") || v.contains("freez") || v.contains("sleet")), hasValue {
                return .ice
            }
            if (f.contains("precip") || f.contains("rain")), hasValue,
               weatherRiskTier?.isActionable == true {
                return .wet
            }
        }
        return nil
    }

    /// Hazard kind for the pavement-ahead warning chip.
    private enum PavementHazard {
        case ice, wet
        var label: String { self == .ice ? "ICE AHEAD" : "WET PAVEMENT AHEAD" }
        var glyph: WeatherIcons.Glyph { self == .ice ? .sleet : .rain }
        var tone: Color { self == .ice ? Brand.info : WeatherV3.drop }
    }

    /// A SEVERE / ELEVATED cell crossing the NEXT leg → the ETA card gets a
    /// bespoke weather-risk pill. nil ⇒ no annotation (watch tier stays on
    /// the band only; the ETA pill is reserved for the loudest tiers).
    private var etaWeatherFlag: (label: String, tone: Color)? {
        guard let li = activeLaneImpact else { return nil }
        switch li.riskTier {
        case .severe, .elevated:
            let head = (li.headline ?? "").trimmingCharacters(in: .whitespaces)
            return (head.isEmpty ? "WEATHER ON NEXT LEG" : head.uppercased(),
                    li.riskTier.color)
        case .watch, .none, .unknown:
            return nil
        }
    }

    var body: some View {
        Group {
            if presentsOfflineRoadDesk {
                palette.bgPage
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            } else {
                ZStack(alignment: .top) {
                    // Map canvas — fills the whole screen behind every overlay
                    mapBackground
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                        .clipped()

                    // Verified maneuver and only the exception intelligence
                    // supported by current route evidence.
                    VStack(spacing: 10) {
                        turnBanner
                            .padding(.horizontal, 14)
                        if !hazmatReroute.isEmpty {
                            hazmatBand
                                .padding(.horizontal, 14)
                        }
                        // §3 route-cell weather band — a translucent hazard band over
                        // the active load's peak leg + an ice/wet-pavement warning
                        // chip when the §3 drivers indicate it. Renders ONLY on a real
                        // actionable lane risk (weatherRiskTier != nil); hidden when
                        // the card is enterprise-gated / clear (honest absence).
                        if let tier = weatherRiskTier {
                            weatherRouteBand(tier: tier)
                                .padding(.horizontal, 14)
                        }
                        // HERE Dynamic Map Content — live Real-Time Traffic,
                        // Road Alerts (incidents), and Safety Cameras. Chips
                        // hide per-layer when HERE returns nothing. The active
                        // load id also feeds the §3 "WEATHER AHEAD" 4th chip
                        // (hidden when the lane is clear / enterprise-gated).
                        EnRouteRoadIntelStrip(loadId: activeLoad.map { String($0.id) })
                            .padding(.horizontal, 14)
                        Spacer()
                    }
                    .padding(.top, 8)

                    GeometryReader { proxy in
                        let controlY = min(
                            max(proxy.size.height * 0.43, 210),
                            max(210, proxy.size.height - 250)
                        )
                        let speedY = min(
                            max(proxy.size.height * 0.68, controlY + 82),
                            max(controlY + 82, proxy.size.height - 185)
                        )

                        mapControlRail
                            .position(x: proxy.size.width - 36, y: controlY)

                        speedCluster
                            .fixedSize()
                            .position(x: 58, y: speedY)
                    }

                    VStack(spacing: 6) {
                        Spacer()
                        executionTruthChip
                            .padding(.horizontal, 14)
                        bottomSummaryCard
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8) // nav clearance handled by Shell
                    }
                }
                .eusoRefreshTask { await hydrateLiveTrip() }
                .task(id: executionPollIdentity) { await pollCanonicalExecution() }
                // Replacing this subtree with the offline desk cancels every
                // online poll and removes the HERE web renderer.
                .onDisappear {
                    wx.stop()
                    canonicalExecutionState = nil
                    canonicalExecutionStatusOverride = nil
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("En route drive")
        // Uniform cafe-door entrance.
        .screenTileRoot()
        .fullScreenCover(
            isPresented: $presentsOfflineRoadDesk,
            onDismiss: releaseAppRadioSilenceLease
        ) {
            NavigationStack {
                Group {
                    if let composition = OfflineMapProductionComposition.shared {
                        OfflineRoadJourneyView(composition: composition)
                    } else {
                        EusoEmptyState(
                            systemImage: "map.fill",
                            title: "Offline navigation unavailable",
                            subtitle: "This app version could not install the approved native offline composition. No online substitute was opened."
                        )
                        .padding(24)
                        .navigationTitle("Offline journey")
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Return to live map") {
                            Task { @MainActor in
                                await OfflineMapProductionComposition.shared?
                                    .stopNavigation()
                                releaseAppRadioSilenceLease()
                                presentsOfflineRoadDesk = false
                            }
                        }
                    }
                }
            }
            .interactiveDismissDisabled()
        }
    }

    private func presentOfflineRoadDesk() {
        if appRadioSilenceLease == nil {
            appRadioSilenceLease = AppRadioSilenceCoordinator.shared.acquire(
                reason: .offlineRoadJourney
            )
        }
        presentsOfflineRoadDesk = true
    }

    private func releaseAppRadioSilenceLease() {
        guard let lease = appRadioSilenceLease else { return }
        AppRadioSilenceCoordinator.shared.release(lease)
        appRadioSilenceLease = nil
    }

    private func hydrateLiveTrip() async {
        // HOS bootstrap runs in parallel with the lifecycle/load hydrate
        // so the bottom-card HOS pill paints as soon as either signal
        // lands. Both are idempotent — safe to call on every appearance.
        async let hosBoot: () = hos.bootstrap()
        await lifecycle.hydrateActiveLoad()
        guard !Task.isCancelled else { return }
        await lifecycle.refresh()
        guard !Task.isCancelled else { return }
        if !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) {
            activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
            guard !Task.isCancelled else { return }
        }
        if let load = activeLoad {
            await refreshRoutePolyline(for: load)
            guard !Task.isCancelled else { return }
            await resolveReceiverFence(for: load)
            guard !Task.isCancelled else { return }
            // §3 weather for the active haul — in-progress refresh (~30s).
            // Idempotent: startAutoRefresh stops any prior poll first.
            wx.startAutoRefresh(loadId: String(load.id), inProgress: true)
        } else {
            clearCanonicalRouteAndExecution()
        }
        _ = await hosBoot
    }

    /// Looks up the company's REAL geofence row covering the delivery
    /// coordinate (`tracking.getGeofences` → nearest active circle row
    /// whose center sits within max(its radius, 1.5 km) of the
    /// receiver). The §3c receiver ring renders only when such a row
    /// exists — its own center + radius — otherwise the map stays
    /// ring-free. No invented coordinates, no invented radius.
    @MainActor
    private func resolveReceiverFence(for load: Load) async {
        guard let delivery = load.deliveryLocation,
              let coordinate = delivery.coordinatePair else {
            receiverFence = nil
            return
        }
        receiverFence = await EusoTripAPI.shared.trackingGeofences
            .fence(near: coordinate.lat, coordinate.lng)
    }

    /// Resolves the exact server-owned active-job route. Mode, waypoints,
    /// assigned profile, graph, evidence, constraints, and geometry never come
    /// from this screen.
    @MainActor
    private func refreshRoutePolyline(for load: Load) async {
        canonicalRouteLines = []
        canonicalRouteStatus = nil
        canonicalRouteVersion = nil
        canonicalRoutePlanVersionID = nil
        canonicalRouteMode = nil
        canonicalExecutionState = nil
        canonicalExecutionStatusOverride = nil
        do {
            let result = try await CanonicalRoutePlanClient.shared.planLoad(
                id: load.id,
                purpose: .activeJob
            )
            switch result {
            case .persisted(let persisted):
                applyCanonicalRoute(persisted.route)
            case .pending(let pending):
                canonicalRouteStatus = pending.blockers.first?.message
                    ?? "Canonical mode-native route pending verified authority"
                await readExistingCanonicalRoute(loadId: load.id)
            }
        } catch {
            canonicalRouteStatus = error.eusoUserCopy
            await readExistingCanonicalRoute(loadId: load.id)
        }
    }

    @MainActor
    private func readExistingCanonicalRoute(loadId: Int) async {
        do {
            applyCanonicalRoute(
                try await CanonicalRoutePlanClient.shared.getBoundLoad(id: loadId)
            )
        } catch {
            if canonicalRouteStatus == nil { canonicalRouteStatus = error.eusoUserCopy }
        }
    }

    @MainActor
    private func applyCanonicalRoute(_ route: CanonicalRoutePlanClient.BoundRoutePlan) {
        guard let payload = route.rendererPayload else {
            clearCanonicalRouteAndExecution()
            canonicalRouteStatus = "Canonical route exists but is not released for rendering"
            return
        }
        let routePlanVersionID = payload.identity.routePlanVersionId
        if canonicalRoutePlanVersionID != routePlanVersionID ||
            canonicalRouteMode != payload.identity.mode {
            canonicalExecutionState = nil
            canonicalExecutionStatusOverride = nil
        }
        canonicalRouteLines = payload.lines
        canonicalRouteVersion = payload.identity.version
        canonicalRoutePlanVersionID = routePlanVersionID
        canonicalRouteMode = payload.identity.mode
        canonicalRouteStatus = nil
    }

    @MainActor
    private func clearCanonicalRouteAndExecution() {
        canonicalRouteLines = []
        canonicalRouteVersion = nil
        canonicalRoutePlanVersionID = nil
        canonicalRouteMode = nil
        canonicalExecutionState = nil
        canonicalExecutionStatusOverride = nil
    }

    /// Polls the canonical runtime while this view and this exact route version
    /// remain active. `refreshExecution(subject:)` sends only the load identity;
    /// all observation ingestion and route projection happen server-side.
    @MainActor
    private func pollCanonicalExecution() async {
        guard let loadID = activeLoad?.id,
              let expectedVersionID = canonicalRoutePlanVersionID,
              let expectedMode = canonicalRouteMode else { return }

        while !Task.isCancelled {
            await refreshCanonicalExecution(
                loadID: loadID,
                expectedVersionID: expectedVersionID,
                expectedMode: expectedMode
            )
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                return
            }
        }
    }

    @MainActor
    private func refreshCanonicalExecution(
        loadID: Int,
        expectedVersionID: CanonicalRoutePlanClient.UnsignedBigIntID,
        expectedMode: CanonicalRoutePlanClient.Mode
    ) async {
        do {
            let state = try await CanonicalRoutePlanClient.shared.refreshExecution(
                subject: .load(loadID)
            )
            guard !Task.isCancelled,
                  activeLoad?.id == loadID,
                  canonicalRoutePlanVersionID == expectedVersionID,
                  canonicalRouteMode == expectedMode else { return }
            guard state.assignment.routePlanVersionId == expectedVersionID,
                  state.mode == expectedMode else {
                canonicalExecutionState = nil
                canonicalExecutionStatusOverride = "GUIDANCE PAUSED · ROUTE VERSION CHANGED"
                return
            }
            canonicalExecutionState = state
            canonicalExecutionStatusOverride = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled,
                  activeLoad?.id == loadID,
                  canonicalRoutePlanVersionID == expectedVersionID else { return }
            canonicalExecutionState = nil
            canonicalExecutionStatusOverride = "GUIDANCE PAUSED · VERIFICATION UNAVAILABLE"
        }
    }

    private static func distanceDisplay(
        meters: UInt64
    ) -> (value: String, unit: String, spoken: String) {
        let metersValue = Double(meters)
        let miles = metersValue / 1_609.344
        if miles >= 10 {
            let rounded = Int(miles.rounded())
            return (String(rounded), "mi", "\(rounded) miles")
        }
        if miles >= 0.1 {
            let value = String(format: "%.1f", miles)
            return (value, "mi", "\(value) miles")
        }
        let feet = Int((metersValue * 3.280_839_895).rounded())
        return (String(feet), "ft", "\(feet) feet")
    }

    private static func durationDisplay(seconds: UInt64) -> String {
        let totalMinutes = seconds / 60
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return minutes == 0 ? "\(hours)h remaining" : "\(hours)h \(minutes)m remaining"
        }
        if totalMinutes > 0 { return "\(totalMinutes)m remaining" }
        return seconds == 0 ? "0m remaining" : "<1m remaining"
    }

    private static func parseExecutionInstant(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let wholeSeconds = ISO8601DateFormatter()
        wholeSeconds.formatOptions = [.withInternetDateTime]
        return wholeSeconds.date(from: value)
    }

    // MARK: Turn-by-turn banner

    @ViewBuilder
    private var turnBanner: some View {
        if let composition = OfflineMapProductionComposition.shared {
            OfflineDriverTurnBanner(composition: composition) {
                legacyTurnBanner
            }
        } else {
            legacyTurnBanner
        }
    }

    private var legacyTurnBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            // The glyph is selected from the exact server instruction type.
            // A paused state uses a pause glyph rather than inventing a turn.
            Image(systemName: turnSystemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

            // Distance-to-trigger + exact maneuver text. The runtime does not
            // currently expose a structured exit identifier, so no exit chip
            // is rendered or inferred from free text.
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(turnDistance)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.white)
                        Text(turnDistanceUnit)
                            .font(EType.mono(.caption)).tracking(0.5)
                            .foregroundStyle(Color.white.opacity(0.85))
                    }
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
                Text(turnHeadline)
                    .font(EType.body).fontWeight(.semibold)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(turnSubhead)
                    .font(EType.mono(.micro)).tracking(0.6)
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Image(systemName: canonicalGuidance == nil
                          ? "pause.circle.fill"
                          : "checkmark.shield.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(executionStatusText)
                        .font(EType.mono(.micro)).tracking(0.55)
                        .lineLimit(1)
                }
                .foregroundStyle(Color.white.opacity(0.9))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.white.opacity(0.12), in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(LinearGradient.diagonal)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        // Doctrine §2.1 — dual-shadow brand glow. The turn-card surface
        // uses LinearGradient.diagonal (blue→magenta) for the fill, so the
        // drop shadow is split into blue (-x) + magenta (+x) halves to
        // carry the same gradient feel through the shadow as through
        // the fill. Mirrors the pattern at DriverTabPanes:733/895 and
        // activeTripMap:426-429.
        .shadow(color: Brand.blue.opacity(0.32), radius: 16, x: -2, y: 6)
        .shadow(color: Brand.magenta.opacity(0.32), radius: 16, x: 2, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(turnInstructionAccessibility)
    }

    // MARK: Hazmat reroute band

    private var hazmatBand: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white)
            Text(hazmatReroute)
                .font(EType.mono(.micro)).tracking(0.8)
                .fontWeight(.semibold)
                .foregroundStyle(Color.white)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(
            LinearGradient(
                colors: [Brand.danger, Brand.warning],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.pill)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
        .shadow(color: Brand.danger.opacity(0.28), radius: 10, y: 3)
    }

    // MARK: §3 route-cell weather band (over the active load route)

    /// A bespoke floating panel that draws the §3 weather hazard CROSSING
    /// the active route — the same showpiece idiom as `RouteCellDiagram`
    /// (a curved road with a translucent hazard column over the peak leg),
    /// rendered inline here over the map canvas. The band intensity tracks
    /// `tier` (severe sits mid-lane, lesser tiers shift toward the
    /// destination so it reads "later"), the peak label comes straight from
    /// the §3 `peakLeg`, and an ice/wet-pavement-ahead chip surfaces when
    /// the §3 drivers indicate freezing / wet pavement. Every glyph is a
    /// `WeatherIcons` glyph — zero SF Symbols. Honest: the caller only
    /// mounts this when `weatherRiskTier != nil`.
    @ViewBuilder
    private func weatherRouteBand(tier: LaneRiskTier) -> some View {
        let bandColor = tier == .severe ? WeatherV3.danger
            : (tier == .watch ? Brand.warning : WeatherV3.danger.opacity(0.85))
        VStack(alignment: .leading, spacing: 7) {
            // header row — route glyph · WEATHER ON ROUTE · tier pill
            HStack(spacing: 7) {
                WeatherIcons.utility(.route, size: 13, tint: WeatherV3.nodeOrigin)
                Text("WEATHER ON ROUTE")
                    .font(EType.mono(.micro)).tracking(0.8)
                    .fontWeight(.heavy)
                    .foregroundStyle(.white.opacity(0.82))
                Spacer(minLength: 4)
                Text(tier.rawValue.uppercased())
                    .font(EType.mono(.micro)).tracking(0.6)
                    .fontWeight(.heavy)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(bandColor.opacity(0.22)))
                    .overlay(Capsule().strokeBorder(bandColor.opacity(0.5), lineWidth: 1))
            }

            // the hazard band crossing the route — a curved road with the
            // translucent weather column over the peak leg + the §3 peak
            // label drawn over the band.
            weatherBandCanvas(tier: tier)
                .frame(height: 46)

            // ice / wet-pavement-ahead warning chip — only when a §3 driver
            // indicates it (pavementHazard != nil); otherwise hidden.
            if let hazard = pavementHazard {
                HStack(spacing: 6) {
                    WeatherGlyph(kind: hazard.glyph)
                        .frame(width: 16, height: 16)
                    Text(hazard.label)
                        .font(EType.mono(.micro)).tracking(0.7)
                        .fontWeight(.heavy)
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(hazard.tone.opacity(0.18)))
                .overlay(Capsule().strokeBorder(hazard.tone.opacity(0.55), lineWidth: 1))
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(bandColor.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .shadow(color: bandColor.opacity(0.22), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(weatherBandA11y(tier: tier))
    }

    /// Compact risk-position chart. It deliberately avoids an EusoLine-like
    /// path: only exact route-plan geometry may carry the owned route gradient.
    /// The live tier instead appears as a chart band and peak marker.
    private func weatherBandCanvas(tier: LaneRiskTier) -> some View {
        Canvas { ctx, size in
            // Unknown is absence of classified lane risk, not a safe or
            // hazardous location. Draw no band or marker for that state.
            guard tier != .unknown else { return }
            let w = size.width, h = size.height
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x / 320.0 * w, y: y / 46.0 * h)
            }
            // band center tracks the tier: severe mid-lane, lesser later.
            let bandX: CGFloat = {
                switch tier {
                case .severe:   return 178
                case .elevated: return 206
                case .watch:    return 232
                case .none:     return 256
                case .unknown:  return 0 // unreachable after the guard above
                }
            }()
            let bandColor = tier == .watch ? Brand.warning : WeatherV3.danger

            // translucent hazard column (soft left→right fade, glows mid).
            let bw: CGFloat = 46 / 320.0 * w
            let bx = bandX / 320.0 * w
            ctx.fill(
                Path(CGRect(x: bx - bw / 2, y: 0, width: bw, height: h)),
                with: .linearGradient(
                    Gradient(colors: [bandColor.opacity(0), bandColor.opacity(0.5), bandColor.opacity(0)]),
                    startPoint: CGPoint(x: bx - bw / 2, y: 0),
                    endPoint: CGPoint(x: bx + bw / 2, y: 0)))

            // Quiet chart baseline and ticks: unmistakably analytical chrome,
            // never a navigable route or alternate geometry.
            var baseline = Path()
            baseline.move(to: P(20, 34))
            baseline.addLine(to: P(300, 34))
            ctx.stroke(
                baseline,
                with: .color(palette.textTertiary.opacity(0.34)),
                style: StrokeStyle(lineWidth: 1, lineCap: .round)
            )
            for x in stride(from: CGFloat(20), through: 300, by: 56) {
                var tick = Path()
                tick.move(to: P(x, 31))
                tick.addLine(to: P(x, 37))
                ctx.stroke(tick, with: .color(palette.textTertiary.opacity(0.32)), lineWidth: 1)
            }

            // peak marker on the band.
            let mk = P(bandX, 26)
            let mr: CGFloat = 5
            let mrect = CGRect(x: mk.x - mr, y: mk.y - mr, width: mr * 2, height: mr * 2)
            ctx.fill(Path(ellipseIn: mrect), with: .color(bandColor))
            ctx.stroke(Path(ellipseIn: mrect), with: .color(.white), style: StrokeStyle(lineWidth: 1.6))

            // §3 peak-leg label over the band — real peakLeg only.
            if let peak = weatherPeakLeg {
                let raw = peak.time.isEmpty ? peak.label : peak.time
                let text = raw.trimmingCharacters(in: .whitespaces).uppercased()
                if !text.isEmpty {
                    ctx.draw(
                        Text(text).font(.system(size: 10, weight: .heavy))
                            .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.82)),
                        at: P(bandX, 8), anchor: .center)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func weatherBandA11y(tier: LaneRiskTier) -> String {
        var s = "Weather on route, \(tier.rawValue) risk"
        if let peak = weatherPeakLeg {
            let p = [peak.label, peak.time]
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            if !p.isEmpty { s += ", peak leg \(p)" }
        }
        if let hazard = pavementHazard { s += ", \(hazard.label.lowercased())" }
        return s
    }

    // MARK: Map control rail (right edge)

    private var mapControlRail: some View {
        VStack(spacing: 10) {
            mapControlButton(
                "location.north.fill",
                label: "Open radio-silent offline journey",
                hint: "Opens installed-data search, covered truck routing, and native offline guidance.",
                tinted: true,
                action: presentOfflineRoadDesk
            )
            mapControlButton(
                voiceCoachMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                label: voiceCoachMuted ? "Unmute voice coaching" : "Mute voice coaching",
                enabled: toggleVoiceMute != nil,
                action: { toggleVoiceMute?() }
            )
            if canonicalGuidance != nil {
                mapControlButton(
                    "location.north.circle.fill",
                    label: "Re-center on verified position",
                    tinted: true,
                    action: { mapRecenterGeneration &+= 1 }
                )
            }
        }
    }

    @ViewBuilder
    private func mapControlButton(
        _ systemName: String,
        label: String,
        hint: String = "",
        enabled: Bool = true,
        tinted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                Circle()
                    .strokeBorder(palette.borderSoft, lineWidth: 1)
                if tinted {
                    Image(systemName: systemName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LinearGradient.diagonal)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }

    // MARK: Speed limit + speedometer

    private var speedCluster: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // No speed-limit sign appears until the canonical execution
            // contract actually releases one. Speed and course below are the
            // accepted observation's values, never device-local estimates.
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(currentSpeed)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                    Text("MPH")
                        .font(EType.mono(.micro)).tracking(0.6)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.bottom, 8)
                }
                if let currentCourse {
                    Text(currentCourse)
                        .font(EType.mono(.micro)).tracking(0.55)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(palette.borderSoft)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(currentSpeedAccessibility)
        }
    }

    private var executionTruthChip: some View {
        let isLive = canonicalGuidance != nil
        return HStack(spacing: 7) {
            Circle()
                .fill(isLive ? Brand.success : Brand.warning)
                .frame(width: 7, height: 7)
            Text(executionStatusText)
                .font(EType.mono(.micro)).tracking(0.55)
                .fontWeight(.semibold)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let guidance = canonicalGuidance {
                Text(guidance.observation.dataset.uppercased())
                    .font(EType.mono(.micro)).tracking(0.45)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .overlay(
            Capsule().strokeBorder(
                (isLive ? Brand.success : Brand.warning).opacity(0.5),
                lineWidth: 1
            )
        )
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(executionTruthAccessibility)
    }

    private var executionTruthAccessibility: String {
        guard let guidance = canonicalGuidance else { return executionStatusText }
        return "\(executionStatusText). Source \(guidance.observation.attribution). " +
            "Observed \(guidance.observation.observedAt)."
    }

    private var canonicalRouteVisualState: HereRouteVisualState {
        if let guidance = canonicalGuidance {
            return guidance.evidenceState == .arrived ? .completed : .active
        }
        switch canonicalExecutionState?.evidenceState {
        case .stale: return .stale
        case .offRoute: return .offRoute
        case .arrived: return .stale
        case .current: return .stale
        case .unobserved, .none: return .planned
        }
    }

    private var canonicalLiveOperationsStatus: HereLiveOperationsStatus {
        let observation = canonicalExecutionState?.observation
        let availability: HereLiveOperationsStatus.Availability
        if canonicalGuidance != nil {
            availability = .live
        } else {
            switch canonicalExecutionState?.evidenceState {
            case .stale: availability = .stale
            case .offRoute, .current, .arrived: availability = .degraded
            case .unobserved: availability = .empty
            case .none: availability = canonicalRoutePlanVersionID == nil ? .unavailable : .empty
            }
        }
        return HereLiveOperationsStatus(
            availability: availability,
            sourceLabel: observation?.provider,
            freshnessLabel: observation?.freshnessState.rawValue,
            detail: executionStatusText,
            observationCount: observation == nil ? 0 : 1
        )
    }

    // MARK: Bottom summary card

    private var bottomSummaryCard: some View {
        VStack(spacing: 10) {
            // ETA row
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(etaBig)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(etaSub)
                        .font(EType.mono(.micro)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                    // §3 severe/elevated-cell annotation — a bespoke weather
                    // pill when a loud cell crosses the next leg. The
                    // headline reads straight from the §3 LaneImpact; hidden
                    // when no severe/elevated risk is live (honest).
                    if let flag = etaWeatherFlag {
                        HStack(spacing: 5) {
                            WeatherIcons.utility(.alert, size: 11, tint: flag.tone)
                            Text(flag.label)
                                .font(EType.mono(.micro)).tracking(0.5)
                                .fontWeight(.heavy)
                                .foregroundStyle(flag.tone)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(flag.tone.opacity(0.14)))
                        .overlay(Capsule().strokeBorder(flag.tone.opacity(0.45), lineWidth: 0.5))
                        .padding(.top, 3)
                        .accessibilityLabel("Weather risk on the next leg: \(flag.label)")
                    }
                }
                Spacer()
                // Exit (red)
                Button { lifecycleExit?() } label: {
                    Text("Exit")
                        .font(EType.body).fontWeight(.semibold)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(Brand.danger)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
                        .shadow(color: Brand.danger.opacity(0.35), radius: 8, y: 3)
                }
                .accessibilityLabel("Exit navigation")
            }

            // Status chips row
            HStack(spacing: 8) {
                statusChip(
                    kicker: "HOS DRIVE LEFT",
                    value: hosDriveLeft,
                    tone: .success
                )
                statusChip(
                    kicker: "EUSOSHIELD LIVE",
                    value: shieldValue,
                    tone: .brand
                )
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderSoft)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
    }

    private enum ChipTone { case success, brand }

    @ViewBuilder
    private func statusChip(kicker: String, value: String, tone: ChipTone) -> some View {
        let strokeStyle: AnyShapeStyle = (tone == .brand)
            ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.55))
            : AnyShapeStyle(Brand.success.opacity(0.45))
        let kickerColor: Color = (tone == .brand) ? palette.textSecondary : Brand.success
        let valueColor: AnyShapeStyle = (tone == .brand)
            ? AnyShapeStyle(LinearGradient.diagonal)
            : AnyShapeStyle(palette.textPrimary)

        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kicker)
                    .font(EType.mono(.micro)).tracking(0.7)
                    .foregroundStyle(kickerColor)
                Text(value)
                    .font(EType.bodyStrong)
                    .foregroundStyle(valueColor)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(strokeStyle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: Map background

    /// Live HERE basemap gate (D-maps mandate · mirrors 013). When a load
    /// carries real pickup + delivery coordinates, the map is
    /// the canonical OMV vector `HereLiveMapView` fed the exact persisted
    /// server-owned active-job plan. Independent route lines remain
    /// independent; this screen never repairs, joins, or substitutes geometry.
    /// The coordinate gate matches 013:
    /// the server's geocode self-heal can return a load whose location
    /// JSON is present but whose lat/lng are still 0; drawing those frames
    /// the map on null island, so we require a real fix on BOTH endpoints
    /// and otherwise fall back to the honest placeholder canvas below.
    @ViewBuilder
    private var mapBackground: some View {
        if let load = activeLoad,
           let pickup = load.pickupLocation,
           let delivery = load.deliveryLocation,
           let pickupCoordinate = pickup.coordinatePair,
           let deliveryCoordinate = delivery.coordinatePair {
            let mapTransportMode = EusoTripMapTransportMode(
                canonicalValue: load.transportMode
            )
            let guidance = canonicalGuidance
            let mapCenter = guidance.map {
                HereLatLng($0.liveCoordinate.lat, $0.liveCoordinate.lng)
            } ?? HereLatLng(pickupCoordinate.lat, pickupCoordinate.lng)
            let markerLayer = HereMapLayer.markers([
                .init(at: .init(pickupCoordinate.lat, pickupCoordinate.lng), kind: .pickup,
                      label: pickup.optionalMapDisplayLabel),
                .init(at: .init(deliveryCoordinate.lat, deliveryCoordinate.lng), kind: .delivery,
                      label: delivery.optionalMapDisplayLabel)
            ])
            let livePositionLayers: [HereMapLayer] = guidance.map { snapshot in
                let kind: HereMarker.Kind
                switch snapshot.mode {
                case .truck: kind = .truck
                case .rail: kind = .rail
                case .vessel: kind = .vessel
                }
                let marker = HereMarker(
                    at: .init(snapshot.liveCoordinate.lat, snapshot.liveCoordinate.lng),
                    kind: kind,
                    label: "LIVE",
                    observationState: .current,
                    sourceLabel: snapshot.observation.provider,
                    accessibilityLabel: "Current projected \(snapshot.mode.rawValue.lowercased()) position. " +
                        "\(snapshot.observation.attribution)."
                )
                // `.missionPins` preserves the caller-owned source and
                // freshness fields; it does not downgrade a current mode pin.
                return .missionPins([marker])
            }.map { [$0] } ?? []
            let routeLabel = canonicalRouteVersion.map {
                "Eusorone \(mapTransportMode.rawValue) route plan version \($0)"
            }
            let routeLayers: [HereMapLayer] = canonicalRouteLines.enumerated().map { index, line in
                .eusoRoute(
                    polyline: line,
                    state: canonicalRouteVisualState,
                    label: index == 0 ? routeLabel : nil
                )
            } + [markerLayer]
            // §3c receiver fence at the corridor terminus — ONLY when a
            // real `tracking.getGeofences` row covers the receiver
            // (resolveReceiverFence). Absent row ⇒ absent layer.
            let fenceLayers: [HereMapLayer] = receiverFence.map {
                [.geofenceRing(center: $0.center,
                               radiusMeters: $0.radiusMeters,
                               kind: .receiver,
                               breachAt: nil)]
            } ?? []
            HereLiveMapView(
                center: mapCenter,
                zoom: guidance == nil ? 7 : 16,
                firstPerson: guidance != nil,
                route: [],
                baseLayers: routeLayers + livePositionLayers + fenceLayers,
                addOns: mapTransportMode == .truck ? .driverEnRoute : [],
                activeJob: true,
                mapModeContext: .unconfirmed(mapTransportMode),
                liveOperationsStatus: canonicalLiveOperationsStatus
            )
            .id("verified-camera-\(mapRecenterGeneration)")
            .overlay(alignment: .bottomLeading) {
                if let canonicalRouteStatus {
                    Text(canonicalRouteStatus)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(palette.bgCard.opacity(0.92))
                        .overlay(Capsule().strokeBorder(Brand.warning.opacity(0.45)))
                        .clipShape(Capsule())
                        .padding(10)
                        .accessibilityLabel(canonicalRouteStatus)
                }
            }
        } else {
            mapPlaceholder
        }
    }

    /// Operational empty state shown when the active load has no verified
    /// pickup and delivery coordinates. It contains no route, road, waypoint,
    /// or position graphics that could be mistaken for live navigation data.
    private var mapPlaceholder: some View {
        EusoEmptyState(
            systemImage: "mappin.slash",
            title: "Awaiting route coordinates",
            subtitle: "Live navigation will appear after verified pickup and delivery coordinates are available."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.bgCard)
    }
}

@MainActor
private struct OfflineDriverTurnBanner<Fallback: View>: View {
    @ObservedObject var composition: OfflineMapProductionComposition
    private let fallback: () -> Fallback

    init(
        composition: OfflineMapProductionComposition,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        self.composition = composition
        self.fallback = fallback
    }

    var body: some View {
        if isActive {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: stateSymbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

                VStack(alignment: .leading, spacing: 4) {
                    Text("RADIO-SILENT GUIDANCE")
                        .font(EType.mono(.micro))
                        .tracking(0.7)
                        .foregroundStyle(Color.white.opacity(0.76))
                    if let maneuver = composition.currentNavigationManeuver {
                        Text(maneuver.instruction)
                            .font(EType.body.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .lineLimit(2)
                        Text("In \(distance(maneuver.distanceMeters))")
                            .font(EType.mono(.caption))
                            .foregroundStyle(Color.white.opacity(0.88))
                    } else {
                        Text(stateTitle)
                            .font(EType.body.weight(.semibold))
                            .foregroundStyle(Color.white)
                    }
                    if let deviation = composition.lastNavigationDeviation {
                        Text("Off route · \(Int(deviation.crossTrackMeters.rounded())) m · \(deviation.consecutiveSamples) fixes")
                            .font(EType.mono(.micro))
                            .foregroundStyle(Color.white.opacity(0.82))
                    } else {
                        Text(coverageTitle)
                            .font(EType.mono(.micro))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Circle())
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(LinearGradient.diagonal)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: Brand.blue.opacity(0.32), radius: 16, x: -2, y: 6)
            .shadow(color: Brand.magenta.opacity(0.32), radius: 16, x: 2, y: 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
        } else {
            fallback()
        }
    }

    private var isActive: Bool {
        switch composition.navigationState {
        case .starting, .navigating, .paused, .offRoute, .rerouting:
            return true
        case .idle, .arrived, .stopped, .failed:
            return false
        }
    }

    private var stateSymbol: String {
        switch composition.navigationState {
        case .offRoute, .rerouting: return "arrow.triangle.branch"
        case .paused: return "pause.fill"
        case .starting: return "hourglass"
        case .navigating: return "location.north.fill"
        case .idle, .arrived, .stopped, .failed: return "location.slash"
        }
    }

    private var stateTitle: String {
        switch composition.navigationState {
        case .starting: return "Starting native offline guidance"
        case .navigating: return "Waiting for the next verified maneuver"
        case .paused(_, let reason): return "Guidance paused · \(reason)"
        case .offRoute(_, let deviation):
            return "Off route · \(Int(deviation.crossTrackMeters.rounded())) m"
        case .rerouting: return "Calculating an offline reroute"
        case .idle, .arrived, .stopped, .failed: return "Offline guidance inactive"
        }
    }

    private var coverageTitle: String {
        switch composition.navigationCoverage {
        case .verified(let evidence):
            return "Coverage verified · \(evidence.regionIDs.map(\.rawValue).joined(separator: ", "))"
        case .approachingBoundary(_, let distanceMeters):
            return distanceMeters.map { "Coverage boundary in \(distance($0))" }
                ?? "Approaching the installed-coverage boundary"
        case .outsideInstalledCoverage:
            return "Outside verified installed coverage"
        case .unknown:
            return "Coverage state is being verified"
        }
    }

    private var accessibilityText: String {
        let instruction = composition.currentNavigationManeuver?.instruction ?? stateTitle
        return "Radio-silent guidance. \(instruction). \(coverageTitle)."
    }

    private func distance(_ meters: Int64) -> String {
        meters < 1_000
            ? "\(meters) m"
            : String(format: "%.1f km", Double(meters) / 1_000)
    }
}

// MARK: - Wrapper

struct EnRouteDriveScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            EnRouteDrive(register: theme.bgPage == Theme.dark.bgPage ? .dark : .light)
        } nav: {
            BottomNav(leading: driverNavLeading_035(),
                      trailing: driverNavTrailing_035(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_035() -> [NavSlot] {
    RoleNav.driverLeading(current: .trips)
}
private func driverNavTrailing_035() -> [NavSlot] {
    RoleNav.driverTrailing(current: .none)
}

// MARK: - Previews

#Preview("035 · En Route Drive · Dark") {
    EnRouteDriveScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("035 · En Route Drive · Light") {
    EnRouteDriveScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
