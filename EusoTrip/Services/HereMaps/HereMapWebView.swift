//
//  HereMapWebView.swift
//  EusoTrip — the ONE canonical HERE Maps JS 3.2 renderer.
//
//  2026-05-21: extracted + generalized from HotZonesWidget so EVERY map
//  surface (Hot Zones, Live Tracking, Control Tower, Load Detail, driver
//  En-Route, Dock Assigned) uses a single, correct map instead of each
//  screen rolling its own (most rolled NONE, which is why Live Tracking /
//  Control Tower / Load Detail showed empty grids + "Route loading…").
//
//  Two things every prior embed got wrong and this one gets right:
//
//   1. REFERRER. The HERE Maps JS apiKey is validated against the portal
//      trusted-domains list via the HTTP `Referer` header. The WebView
//      `baseURL` IS that referrer. We use `HereMapsConfig
//      .jsTrustedReferrerOrigin` (a whitelisted domain) — NOT
//      `js.api.here.com` (HERE's own CDN, which is not whitelisted and
//      403'd every tile → blank map).
//
//   2. CUSTOM BASE LAYERS. Operational, Navigation, and Terrain resolve the
//      exact Truck/Rail/Vessel x light/dark artifact from the 18-outcome
//      content-addressed registry. Pending artifacts stay behind the visual-
//      review gate. A failure uses only the matching HERE family/theme and is
//      surfaced as degraded; route, camera, and overlay state are preserved.
//
//   3. SDK VERSION — this is load-bearing, do not "simplify" it back to 3.1.
//      2026-07-28: every map surface in the app rendered "Map unavailable"
//      because the page loaded **3.1** while `createDefaultLayers` was called
//      with `ppi: 200`. Read straight out of the shipped SDK bytes:
//
//        3.1 mapsjs-service.js:
//          if(0>[72,250,320,500].indexOf(+b)){ if(b!==A) throw new C(...); }
//        3.2 mapsjs-service.js:
//          h=[256,512].includes(f.tileSize)?f.tileSize:512,
//          k=[100,200,400].includes(f.ppi)?f.ppi:2<=window.devicePixelRatio?200:100
//
//      So ppi 200 is INVALID in 3.1 (it throws, buildBase returns null, the
//      map shows the error state) and VALID in 3.2 — and 3.2 clamps instead of
//      throwing. The call was written against 3.2 semantics while the page
//      loaded 3.1. tileSize 512 is legal in both. All six assets we load exist
//      on 3.2 (verified 200). Production pins the full 3.2.8.0 release, as
//      HERE recommends for high-load applications, so a rolling CDN patch
//      cannot change this contract underneath us.
//
//  Layer model: a screen declares what it wants via `[HereMapLayer]`
//  (heatmap / markers / route polyline / ad-zone polygons / mission pins /
//  geofence rings / traffic-flow ribbons). Swift pushes the layer data into
//  the live map via `evaluateJavaScript` whenever `layers` changes — no
//  WebView reload, no flicker.
//
//  2026-06-09: render grammar recut to the wireframe canon
//  (_MAP_DESIGN_LANGUAGE_2026-06-09): the Google-style teardrop pins and
//  the Tailwind palette are gone — concentric endpoint discs, the 013
//  glass-pill destination flag, the live-ping puck, Brand-accent POI
//  discs, one continuous eusoPrimary route sweep, §3c dashed
//  geofence rings (+ pulse + breach node), and §2 traffic-flow ribbons.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation
#if canImport(UIKit)
import UIKit
import WebKit
#endif

// MARK: - Public layer model

public struct HereLatLng: Hashable, Codable, Sendable {
    public let lat: Double
    public let lng: Double
    public var weight: Double?      // heatmap weight (ignored by other layers)
    public init(_ lat: Double, _ lng: Double, weight: Double? = nil) {
        self.lat = lat; self.lng = lng; self.weight = weight
    }
    public init(_ c: CLLocationCoordinate2D, weight: Double? = nil) {
        self.lat = c.latitude; self.lng = c.longitude; self.weight = weight
    }

    /// Only complete, finite WGS-84 coordinates may reach the renderer.
    /// Zero is data on either axis, including the valid coordinate `(0,0)`.
    var isUsableCoordinate: Bool {
        LatLongParser.validatedCoordinate(latitude: lat, longitude: lng) != nil
    }
}

public struct HereMarker: Hashable, Codable, Sendable {
    public let at: HereLatLng
    public let kind: Kind
    public let label: String?
    /// Optional stable identity passed back through `onSelectMarker` when
    /// the pin is tapped (e.g. a load id on the board). nil = not tappable.
    public let id: String?
    /// Truthful observation state supplied by the caller. The renderer uses
    /// pattern/silhouette in addition to color so stale and degraded remain
    /// distinguishable with color-vision deficiencies.
    public let observationState: HereObservationState
    public let sourceLabel: String?
    public let accessibilityLabel: String?
    public let clusterCount: Int?
    public enum Kind: String, Codable, Sendable {
        case truck, rail, vessel, cluster
        case pickup, delivery, stop, fuel, charger, parking, alert, weather
        case mission, adZone, truckStop, weigh, camera, hotZone
    }

    private enum CodingKeys: String, CodingKey {
        case at, kind, label, id, observationState, sourceLabel
        case accessibilityLabel, clusterCount
    }

    public init(
        at: HereLatLng,
        kind: Kind,
        label: String? = nil,
        id: String? = nil,
        observationState: HereObservationState? = nil,
        sourceLabel: String? = nil,
        accessibilityLabel: String? = nil,
        clusterCount: Int? = nil
    ) {
        self.at = at
        self.kind = kind
        self.label = label
        self.id = id
        if let observationState {
            self.observationState = observationState
        } else {
            switch kind {
            case .truck, .rail, .vessel, .cluster:
                // A mode marker without caller-supplied freshness must never
                // silently claim to be current.
                self.observationState = .degraded
            default:
                self.observationState = .current
            }
        }
        self.sourceLabel = sourceLabel
        self.accessibilityLabel = accessibilityLabel
        self.clusterCount = clusterCount.map { max(2, $0) }
    }

    /// Older cached marker payloads predate observation truth fields. Decode
    /// them fail-soft: mode markers become degraded, while static POIs retain
    /// their non-observation current default.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            at: try values.decode(HereLatLng.self, forKey: .at),
            kind: try values.decode(Kind.self, forKey: .kind),
            label: try values.decodeIfPresent(String.self, forKey: .label),
            id: try values.decodeIfPresent(String.self, forKey: .id),
            observationState: try values.decodeIfPresent(
                HereObservationState.self,
                forKey: .observationState
            ),
            sourceLabel: try values.decodeIfPresent(String.self, forKey: .sourceLabel),
            accessibilityLabel: try values.decodeIfPresent(
                String.self,
                forKey: .accessibilityLabel
            ),
            clusterCount: try values.decodeIfPresent(Int.self, forKey: .clusterCount)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(at, forKey: .at)
        try values.encode(kind, forKey: .kind)
        try values.encodeIfPresent(label, forKey: .label)
        try values.encodeIfPresent(id, forKey: .id)
        try values.encode(observationState, forKey: .observationState)
        try values.encodeIfPresent(sourceLabel, forKey: .sourceLabel)
        try values.encodeIfPresent(accessibilityLabel, forKey: .accessibilityLabel)
        try values.encodeIfPresent(clusterCount, forKey: .clusterCount)
    }
}

public enum HereObservationState: String, CaseIterable, Codable, Hashable, Sendable {
    case current
    case stale
    case degraded
    case offline

    public var displayName: String {
        switch self {
        case .current: return "Current"
        case .stale: return "Stale"
        case .degraded: return "Degraded"
        case .offline: return "Offline"
        }
    }
}

/// Caller-owned source/freshness truth for the native Live Operations chrome.
/// This contract never fetches or synthesizes observations.
public struct HereLiveOperationsStatus: Hashable, Sendable {
    public enum Availability: String, Hashable, Sendable {
        case live, stale, degraded, empty, unavailable
    }

    public let availability: Availability
    public let sourceLabel: String?
    public let freshnessLabel: String?
    public let detail: String
    public let observationCount: Int

    public init(
        availability: Availability,
        sourceLabel: String? = nil,
        freshnessLabel: String? = nil,
        detail: String,
        observationCount: Int = 0
    ) {
        self.availability = availability
        self.sourceLabel = sourceLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.freshnessLabel = freshnessLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        self.observationCount = max(0, observationCount)
    }

    public static let noAuthorizedFeed = HereLiveOperationsStatus(
        availability: .unavailable,
        detail: "No authorized live feed"
    )
}

public enum HereRouteVisualState: String, CaseIterable, Codable, Hashable, Sendable {
    case planned, active, completed, rerouting, stale, hazard, offRoute

    public var displayName: String {
        switch self {
        case .planned: return "Planned"
        case .active: return "Active"
        case .completed: return "Completed"
        case .rerouting: return "Rerouting"
        case .stale: return "Stale"
        case .hazard: return "Hazard"
        case .offRoute: return "Off Route"
        }
    }
}

public struct HerePolygon: Hashable, Codable, Sendable {
    public let ring: [HereLatLng]
    public let fillHex: String      // "#1473FF"
    public let opacity: Double
    public let label: String?
    public init(ring: [HereLatLng], fillHex: String, opacity: Double = 0.25, label: String? = nil) {
        self.ring = ring; self.fillHex = fillHex; self.opacity = opacity; self.label = label
    }
}

/// Which canon fence grammar a `geofenceRing` layer renders — §3c of
/// _MAP_DESIGN_LANGUAGE_2026-06-09: every fence is a dashed circle, and
/// each kind carries its own wireframe-verbatim ring color + dash cadence.
public enum HereGeofenceKind: String, Codable, Sendable {
    case receiver          // #F44336 w1.6 dash [6,5] — receiver fence (536)
    case railRamp          // #00C48C w1.4 dash [3,4] + fencePulse (003-rail)
    case pilotGround       // #3FA9F5 @0.65 w1.4 dash [5,5], animated dashoffset (660)
    case destinationPort   // #1473FF @0.55 w1.6 dash [4,5] — dest-port fence (vessel 003)
}

/// One congestion ribbon for a `trafficFlow` layer — §2: jam = #FFA726 w6
/// round @0.9, severe = #F44336 w6 @0.85, painted over the road network (536).
public struct HereTrafficSegment: Hashable, Codable, Sendable {
    public let polyline: [HereLatLng]
    public let severity: Severity
    public enum Severity: String, Codable, Sendable { case jam, severe }
    public init(polyline: [HereLatLng], severity: Severity) {
        self.polyline = polyline; self.severity = severity
    }
}

/// What a screen wants drawn on the shared map.
public enum HereMapLayer: Hashable {
    case heatmap(points: [HereLatLng])
    case markers([HereMarker])
    /// Deprecated non-canonical route input. Shared renderers fail this case
    /// closed; callers must provide server-bound `.eusoRoute` geometry.
    case route(polyline: [HereLatLng], colorHex: String)
    /// Canonical EusoTrip route overlay. The renderer owns its blue-violet-
    /// purple sweep; state remains accessible through width and label without
    /// adding a casing, halo, dash, outline, or alternate route stroke.
    case eusoRoute(polyline: [HereLatLng], state: HereRouteVisualState, label: String?)
    /// Raw GNSS/AEI/AIS history. It is deliberately a neutral dotted trail,
    /// never a route core and never evidence of completed route progress.
    case observationTrail(points: [HereLatLng], label: String)
    /// Sponsored ad-zone polygons (monetization) — HERE `adZonesInBbox`.
    case adZones([HerePolygon])
    /// Gamified mission pins (Haul Missions) — geofence-anchored.
    case missionPins([HereMarker])
    /// Dashed geofence circle (+ optional breach/EXIT node riding the rim)
    /// per §3c — receiver / rail-ramp / pilot-ground / dest-port grammars.
    case geofenceRing(center: HereLatLng, radiusMeters: Double, kind: HereGeofenceKind, breachAt: HereLatLng?)
    /// Congestion ribbons over the road network (536 fleet map) — §2.
    case trafficFlow([HereTrafficSegment])
}

private struct EusoTripMapStyleTransitionEvent: Sendable {
    enum Phase: String, Sendable {
        case pending, committed, failed
    }

    let phase: Phase
    let family: EusoTripMapFamily
    let requestID: Int
    let message: String?
}

// MARK: - SwiftUI entry point

/// The live labeled HERE map every surface should use. Its public name is
/// retained for source compatibility; the canonical registry selects one of
/// 18 mode/family/theme exports without coupling mode to user role.
///
/// ```swift
/// HereVectorMapView(
///     center: .init(29.76, -95.37),
///     zoom: 6,
///     layers: [ .eusoRoute(polyline: pts, state: .planned, label: "Route"),
///               .markers([.init(at: .init(29.76,-95.37), kind: .pickup)]) ]
/// )
/// ```
public struct HereVectorMapView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @AppStorage(EusoTripMapFamilyPreference.storageKey)
    private var persistedMapFamilyRawValue = ""
    @State private var mapFamilyTransition: EusoTripMapFamilyTransitionState?
    @State private var appRadioSilenceRevision: UInt64 = 0

    let center: HereLatLng
    let zoom: Int
    let interactive: Bool
    let tilt: Double
    let layers: [HereMapLayer]
    /// Legacy canvas hint retained for non-UIKit previews. `.nav` and
    /// `.geothermal` also map to Navigation and Terrain when no explicit family
    /// is supplied, so production no longer discards the caller's intent.
    let styleHint: BespokeMapStyleHint
    let mapFamily: EusoTripMapFamily?
    let activeJob: Bool
    let mapModeContext: EusoTripMapModeContext
    let showsMapFamilyControl: Bool
    let liveOperationsStatus: HereLiveOperationsStatus?
    let endpointLabelToggle: Bool
    let onSelectMarker: ((String) -> Void)?

    public init(
        center: HereLatLng,
        zoom: Int = 6,
        interactive: Bool = true,
        tilt: Double = 0,
        layers: [HereMapLayer] = [],
        styleHint: BespokeMapStyleHint = .auto,
        mapFamily: EusoTripMapFamily? = nil,
        activeJob: Bool = false,
        mapModeContext: EusoTripMapModeContext = .unknown,
        showsMapFamilyControl: Bool = true,
        liveOperationsStatus: HereLiveOperationsStatus? = nil,
        endpointLabelToggle: Bool = false,
        onSelectMarker: ((String) -> Void)? = nil
    ) {
        self.center = center
        self.zoom = zoom
        self.interactive = interactive
        self.tilt = tilt
        self.layers = layers
        self.styleHint = styleHint
        self.mapFamily = mapFamily
        self.activeJob = activeJob
        self.mapModeContext = mapModeContext
        self.showsMapFamilyControl = showsMapFamilyControl
        self.liveOperationsStatus = liveOperationsStatus
        self.endpointLabelToggle = endpointLabelToggle
        self.onSelectMarker = onSelectMarker
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                #if canImport(UIKit)
                // Live HERE OMV is the production renderer. It supplies the
                // labeled global cartography beneath EusoTrip's mode grammar.
                HereMapWebViewRepresentable(
                    center: resolvedCenter,
                    zoom: zoom,
                    interactive: interactive,
                    tilt: tilt,
                    isDark: colorScheme == .dark,
                    mapFamily: renderedMapFamily,
                    familySelectionSource: renderedFamilySelectionSource,
                    styleRequestID: renderedStyleRequestID,
                    mapModeContext: mapModeContext,
                    reducedMotion: accessibilityReduceMotion,
                    layers: layers,
                    endpointLabelToggle: endpointLabelToggle,
                    onSelectMarker: onSelectMarker,
                    onStyleTransition: handleStyleTransition
                )
                #else
                BespokeMapCanvas(
                    center: resolvedCenter,
                    zoom: zoom,
                    interactive: interactive,
                    tilt: tilt,
                    isDark: colorScheme == .dark,
                    layers: layers,
                    style: styleHint,
                    onSelectMarker: onSelectMarker
                )
                #endif
            }

            VStack(alignment: .trailing, spacing: 8) {
                if interactive, showsMapFamilyControl, mapFamily == nil {
                    EusoTripMapFamilyMenu(
                        activeFamily: mapFamilyResolution.family,
                        pendingFamily: mapFamilyTransition?.pendingFamily,
                        failedFamily: mapFamilyTransition?.failedFamily,
                        failureMessage: mapFamilyTransition?.failureMessage,
                        onRequest: requestMapFamily
                    )
                }
                if !routeStateSummaries.isEmpty {
                    EusoTripRouteStateControl(routes: routeStateSummaries)
                }
                if let liveOperationsStatus {
                    EusoTripLiveOperationsControl(
                        status: liveOperationsStatus,
                        mode: styleResolution.descriptor?.mode,
                        observations: accessibleObservations,
                        onSelectMarker: onSelectMarker
                    )
                }
            }
            .padding(8)

            if let message = styleResolution.unavailableMessage {
                EusoTripMapModeUnavailablePill(message: message)
                    .padding(8)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .bottomTrailing
                    )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Freight map")
        .accessibilityValue(mapAccessibilityValue)
        // Recreate the renderer on both policy edges. The engage notification
        // first stops and blanks the live WebView synchronously; its new
        // identity can only build an empty local document while the lease is
        // active. The final-release edge creates a fresh governed renderer.
        .id(appRadioSilenceRevision)
        .onReceive(
            NotificationCenter.default.publisher(for: .eusoAppRadioSilenceWillEngage)
        ) { _ in
            appRadioSilenceRevision &+= 1
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .eusoAppRadioSilenceDidRelease)
        ) { _ in
            appRadioSilenceRevision &+= 1
        }
        .onChange(of: baselineMapFamilyResolution.family) { _, family in
            guard mapFamily == nil, var transition = mapFamilyTransition else { return }
            transition.synchronizeActive(family)
            mapFamilyTransition = transition
        }
    }

    private var surfaceDefaultMapFamily: EusoTripMapFamily {
        switch styleHint {
        case .nav: return .navigation
        case .geothermal: return .terrain
        case .auto, .ocean, .rail, .portApproach: return .operational
        }
    }

    private var baselineMapFamilyResolution: EusoTripMapFamilyResolution {
        EusoTripMapFamilyPreference.resolve(
            explicitFamily: mapFamily,
            persistedRawValue: persistedMapFamilyRawValue,
            activeJob: activeJob,
            surfaceDefault: surfaceDefaultMapFamily
        )
    }

    /// The family proven active by the renderer. A pending menu choice cannot
    /// change this value or its persisted preference.
    private var mapFamilyResolution: EusoTripMapFamilyResolution {
        guard mapFamily == nil, let transition = mapFamilyTransition else {
            return baselineMapFamilyResolution
        }
        return .init(family: transition.activeFamily, source: .manualPreference)
    }

    private var renderedMapFamily: EusoTripMapFamily {
        guard mapFamily == nil else { return mapFamilyResolution.family }
        return mapFamilyTransition?.pendingFamily ?? mapFamilyResolution.family
    }

    private var renderedFamilySelectionSource: EusoTripMapFamilySelectionSource {
        mapFamilyTransition == nil ? mapFamilyResolution.source : .manualPreference
    }

    private var renderedStyleRequestID: Int {
        mapFamilyTransition?.latestRequestID ?? 0
    }

    private var mapAccessibilityValue: String {
        var value = "\(mapFamilyResolution.family.displayName) active, \(mapModeAccessibilityValue)"
        if let pending = mapFamilyTransition?.pendingFamily {
            value += ". Loading \(pending.displayName)"
        } else if let failed = mapFamilyTransition?.failedFamily {
            value += ". \(failed.displayName) did not load; retry available"
        }
        return value
    }

    private func requestMapFamily(_ family: EusoTripMapFamily) {
        var transition = mapFamilyTransition
            ?? EusoTripMapFamilyTransitionState(activeFamily: baselineMapFamilyResolution.family)
        transition.request(family)
        mapFamilyTransition = transition
    }

    private func handleStyleTransition(_ event: EusoTripMapStyleTransitionEvent) {
        guard mapFamily == nil else { return }
        var transition = mapFamilyTransition
            ?? EusoTripMapFamilyTransitionState(activeFamily: baselineMapFamilyResolution.family)
        switch event.phase {
        case .pending:
            break
        case .committed:
            guard transition.commit(event.family, requestID: event.requestID) else { return }
            persistedMapFamilyRawValue = event.family.rawValue
        case .failed:
            guard transition.fail(
                event.family,
                requestID: event.requestID,
                message: event.message ?? "Map family could not be prepared."
            ) else { return }
        }
        mapFamilyTransition = transition
    }

    /// Prefer the caller's real camera, then the first usable layer point.
    /// The final value is a neutral world frame, not a fabricated asset
    /// location, and still renders HERE's labeled global cartography.
    private var resolvedCenter: HereLatLng {
        if center.isUsableCoordinate { return center }
        for layer in layers {
            switch layer {
            case .heatmap(let points), .route(let points, _), .eusoRoute(let points, _, _),
                 .observationTrail(let points, _):
                if let point = points.first(where: \.isUsableCoordinate) { return point }
            case .markers(let markers), .missionPins(let markers):
                if let point = markers.map(\.at).first(where: \.isUsableCoordinate) { return point }
            case .adZones(let polygons):
                if let point = polygons.lazy.flatMap(\.ring).first(where: \.isUsableCoordinate) {
                    return point
                }
            case .geofenceRing(let center, _, _, _):
                if center.isUsableCoordinate { return center }
            case .trafficFlow(let segments):
                if let point = segments.lazy.flatMap(\.polyline).first(where: \.isUsableCoordinate) {
                    return point
                }
            }
        }
        return HereLatLng(20, 0)
    }

    private var styleResolution: EusoTripMapStyleResolution {
        EusoTripMapStyleRegistry.resolve(
            context: mapModeContext,
            family: mapFamilyResolution.family,
            theme: colorScheme == .dark ? .dark : .light
        )
    }

    private var mapModeAccessibilityValue: String {
        if let mode = styleResolution.descriptor?.mode {
            return "\(mode.displayName) mode"
        }
        return styleResolution.unavailableMessage ?? "mode unavailable"
    }

    private var accessibleObservations: [HereMarker] {
        layers.flatMap { layer -> [HereMarker] in
            switch layer {
            case .markers(let markers), .missionPins(let markers): return markers
            default: return []
            }
        }
    }

    private var routeStateSummaries: [EusoTripRouteStateSummary] {
        var summaries: [EusoTripRouteStateSummary] = []
        for layer in layers {
            switch layer {
            case .route:
                // A legacy/reference line is deliberately not promoted into
                // the canonical route key. Only `.eusoRoute` carries owned
                // route-plan state and the Eusorone gradient.
                break
            case .eusoRoute(_, let state, let label):
                let normalized = label?.trimmingCharacters(in: .whitespacesAndNewlines)
                summaries.append(
                    .init(
                        index: summaries.count,
                        state: state,
                        label: normalized?.isEmpty == false ? normalized : nil
                    )
                )
            default:
                break
            }
        }
        return summaries
    }
}

private struct EusoTripRouteStateSummary: Identifiable {
    let index: Int
    let state: HereRouteVisualState
    let label: String?
    var id: String { "\(index):\(state.rawValue):\(label ?? "")" }
}

private struct EusoTripMapFamilyMenu: View {
    let activeFamily: EusoTripMapFamily
    let pendingFamily: EusoTripMapFamily?
    let failedFamily: EusoTripMapFamily?
    let failureMessage: String?
    let onRequest: (EusoTripMapFamily) -> Void

    var body: some View {
        Menu {
            ForEach(EusoTripMapFamily.allCases) { family in
                Button {
                    onRequest(family)
                } label: {
                    Label(
                        menuLabel(for: family),
                        systemImage: menuIcon(for: family)
                    )
                }
                .disabled(family == activeFamily && pendingFamily == nil && failedFamily == nil)
            }
            if let failedFamily {
                Section("Map style") {
                    if let failureMessage, !failureMessage.isEmpty {
                        Label(failureMessage, systemImage: "exclamationmark.triangle")
                    }
                    Button {
                        onRequest(failedFamily)
                    } label: {
                        Label("Retry \(failedFamily.displayName)", systemImage: "arrow.clockwise")
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon(for: activeFamily))
                    .font(.system(size: 14, weight: .bold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(activeFamily.displayName)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    if let pendingFamily {
                        Text("Loading \(pendingFamily.displayName)")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                if pendingFamily != nil {
                    ProgressView()
                        .controlSize(.mini)
                } else if failedFamily != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .heavy))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(EusoTripMapChrome.gradient)
                    .frame(height: 3)
                    .padding(.horizontal, 5)
                    .padding(.bottom, 3)
            }
            .overlay(Capsule().stroke(.white.opacity(0.34), lineWidth: 1))
            .shadow(color: .black.opacity(0.13), radius: 7, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Map family")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Choose Operational, Navigation, or Terrain")
    }

    private var accessibilityValue: String {
        if let pendingFamily {
            return "\(activeFamily.displayName) active. Loading \(pendingFamily.displayName)"
        }
        if let failedFamily {
            return "\(activeFamily.displayName) active. \(failedFamily.displayName) retry available"
        }
        return "\(activeFamily.displayName) active"
    }

    private func menuLabel(for family: EusoTripMapFamily) -> String {
        if family == activeFamily { return "\(family.displayName), active" }
        if family == pendingFamily { return "\(family.displayName), loading" }
        return family.displayName
    }

    private func menuIcon(for family: EusoTripMapFamily) -> String {
        if family == activeFamily { return "checkmark.circle.fill" }
        if family == pendingFamily { return "hourglass" }
        return icon(for: family)
    }

    private func icon(for family: EusoTripMapFamily) -> String {
        switch family {
        case .operational: return "map"
        case .navigation: return "arrow.triangle.turn.up.right.diamond"
        case .terrain: return "mountain.2"
        }
    }
}

private enum EusoTripMapChrome {
    static let gradient = LinearGradient(
        colors: [
            Color(red: 20 / 255, green: 115 / 255, blue: 1),
            Color(red: 129 / 255, green: 63 / 255, blue: 245 / 255),
            Color(red: 190 / 255, green: 1 / 255, blue: 1),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

private struct EusoTripMapModeUnavailablePill: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: 250, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.orange.opacity(0.62), style: .init(lineWidth: 1, dash: [4, 3]))
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Map mode unavailable. \(message)")
    }
}

private struct EusoTripLiveOperationsControl: View {
    let status: HereLiveOperationsStatus
    let mode: EusoTripMapProductMode?
    let observations: [HereMarker]
    let onSelectMarker: ((String) -> Void)?

    var body: some View {
        Menu {
            Section("Live Operations") {
                Label(status.detail, systemImage: statusIcon)
                if let source = status.sourceLabel, !source.isEmpty {
                    Label("Source: \(source)", systemImage: "antenna.radiowaves.left.and.right")
                }
                if let freshness = status.freshnessLabel, !freshness.isEmpty {
                    Label("Freshness: \(freshness)", systemImage: "clock")
                }
            }
            if observations.isEmpty {
                Text("No authorized live feed")
            } else {
                Section("Observations") {
                    ForEach(Array(observations.prefix(20).enumerated()), id: \.offset) { _, marker in
                        Button {
                            if let id = marker.id, !id.isEmpty { onSelectMarker?(id) }
                        } label: {
                            Label(observationLabel(marker), systemImage: markerIcon(marker.kind))
                        }
                        .disabled(marker.id?.isEmpty != false)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .font(.system(size: 13, weight: .heavy))
                VStack(alignment: .leading, spacing: 1) {
                    Text("LIVE OPS")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                    Text(statusLabel)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .heavy))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 11)
            .frame(minHeight: 44)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(EusoTripMapChrome.gradient)
                    .frame(width: 4)
                    .padding(.vertical, 5)
                    .padding(.leading, 3)
            }
            .overlay(Capsule().stroke(statusBorder, style: statusStroke))
            .shadow(color: .black.opacity(0.13), radius: 7, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Live Operations")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Shows source, freshness, status, and selectable observations")
    }

    private var statusLabel: String {
        switch status.availability {
        case .live: return "\(status.observationCount) current"
        case .stale: return "Stale · \(status.observationCount)"
        case .degraded: return "Degraded"
        case .empty, .unavailable: return "No authorized feed"
        }
    }

    private var statusIcon: String {
        switch status.availability {
        case .live: return modeIcon
        case .stale: return "clock.badge.exclamationmark"
        case .degraded: return "exclamationmark.triangle.fill"
        case .empty: return "tray"
        case .unavailable: return "antenna.radiowaves.left.and.right.slash"
        }
    }

    private var modeIcon: String {
        switch mode {
        case .truck: return "truck.box.fill"
        case .rail: return "train.side.front.car"
        case .vessel: return "ferry.fill"
        case nil: return "location.fill.viewfinder"
        }
    }

    private var statusBorder: Color {
        switch status.availability {
        case .live: return Color.blue.opacity(0.55)
        case .stale, .degraded: return Color.orange.opacity(0.65)
        case .empty, .unavailable: return Color.secondary.opacity(0.48)
        }
    }

    private var statusStroke: StrokeStyle {
        switch status.availability {
        case .live: return .init(lineWidth: 1)
        case .stale: return .init(lineWidth: 1.2, dash: [4, 3])
        case .degraded: return .init(lineWidth: 1.2, dash: [2, 2])
        case .empty, .unavailable: return .init(lineWidth: 1)
        }
    }

    private var accessibilityValue: String {
        let source = status.sourceLabel.map { ", source \($0)" } ?? ""
        let freshness = status.freshnessLabel.map { ", freshness \($0)" } ?? ""
        return "\(status.availability.rawValue), \(status.detail)\(source)\(freshness)"
    }

    private func observationLabel(_ marker: HereMarker) -> String {
        if let accessibilityLabel = marker.accessibilityLabel, !accessibilityLabel.isEmpty {
            return accessibilityLabel
        }
        let label = marker.label?.isEmpty == false ? marker.label! : marker.kind.rawValue.capitalized
        let source = marker.sourceLabel.map { ", source \($0)" } ?? ""
        return "\(label), \(marker.observationState.displayName)\(source)"
    }

    private func markerIcon(_ kind: HereMarker.Kind) -> String {
        switch kind {
        case .truck: return "truck.box.fill"
        case .rail: return "train.side.front.car"
        case .vessel: return "ferry.fill"
        case .cluster: return "circle.grid.3x3.fill"
        case .pickup: return "circle.circle.fill"
        case .delivery: return "flag.checkered"
        case .alert: return "exclamationmark.triangle.fill"
        default: return "mappin.circle.fill"
        }
    }
}

private struct EusoTripRouteStateControl: View {
    let routes: [EusoTripRouteStateSummary]

    var body: some View {
        Menu {
            Section("Route key") {
                ForEach(routes) { route in
                    Label(
                        "\(route.label ?? "Route") · \(route.state.displayName)",
                        systemImage: icon(for: route.state)
                    )
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon(for: primary.state))
                    .font(.system(size: 12, weight: .heavy))
                VStack(alignment: .leading, spacing: 1) {
                    Text("ROUTE")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                    Text(primary.state.displayName)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .heavy))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 11)
            .frame(minHeight: 44)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(EusoTripMapChrome.gradient)
                    .frame(height: 3)
                    .padding(.horizontal, 5)
                    .padding(.bottom, 3)
            }
            .overlay(Capsule().stroke(borderColor, style: strokeStyle))
            .shadow(color: .black.opacity(0.13), radius: 7, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Route key")
        .accessibilityValue(
            routes.map { "\($0.label ?? "Route"), \($0.state.displayName)" }
                .joined(separator: "; ")
        )
        .accessibilityHint("Shows route state labels and pattern key")
    }

    private var primary: EusoTripRouteStateSummary {
        routes.first ?? .init(index: 0, state: .planned, label: "Route")
    }

    private var borderColor: Color {
        switch primary.state {
        case .hazard: return Color.red.opacity(0.68)
        case .rerouting, .offRoute, .stale: return Color.orange.opacity(0.68)
        case .completed: return Color.secondary.opacity(0.52)
        case .planned, .active: return Color.blue.opacity(0.56)
        }
    }

    private var strokeStyle: StrokeStyle {
        switch primary.state {
        case .active: return .init(lineWidth: 1.2)
        case .completed: return .init(lineWidth: 1.2, dash: [10, 3])
        case .rerouting: return .init(lineWidth: 1.4, dash: [8, 3, 2, 3])
        case .stale: return .init(lineWidth: 1.2, dash: [4, 5])
        case .hazard: return .init(lineWidth: 1.4, dash: [2, 4])
        case .offRoute: return .init(lineWidth: 1.4, dash: [8, 4])
        case .planned: return .init(lineWidth: 1.2, dash: [2, 8])
        }
    }

    private func icon(for state: HereRouteVisualState) -> String {
        switch state {
        case .planned: return "circle.dotted"
        case .active: return "location.fill"
        case .completed: return "checkmark.circle.fill"
        case .rerouting: return "arrow.triangle.2.circlepath"
        case .stale: return "clock.badge.exclamationmark"
        case .hazard: return "exclamationmark.triangle.fill"
        case .offRoute: return "arrow.triangle.branch"
        }
    }
}

#if canImport(UIKit)

// MARK: - UIViewRepresentable bridge

private struct HereMapWebViewRepresentable: UIViewRepresentable {
    let center: HereLatLng
    let zoom: Int
    let interactive: Bool
    let tilt: Double
    let isDark: Bool
    let mapFamily: EusoTripMapFamily
    let familySelectionSource: EusoTripMapFamilySelectionSource
    let styleRequestID: Int
    let mapModeContext: EusoTripMapModeContext
    let reducedMotion: Bool
    let layers: [HereMapLayer]
    let endpointLabelToggle: Bool
    let onSelectMarker: ((String) -> Void)?
    let onStyleTransition: (EusoTripMapStyleTransitionEvent) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        context.coordinator.onSelectMarker = onSelectMarker
        context.coordinator.onStyleTransition = onStyleTransition
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "hzLog")
        userContent.add(context.coordinator, name: "mapReady")
        userContent.add(context.coordinator, name: "markerTap")
        userContent.add(context.coordinator, name: "mapStyleTransition")

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = interactive
        context.coordinator.webView = webView
        let resolution = EusoTripMapStyleRegistry.resolve(
            context: mapModeContext,
            family: mapFamily,
            theme: isDark ? .dark : .light
        )
        let customStylesRequested = HereMapsConfig.customMapStylesEnabled
        let customStylesEnabled = customStylesRequested
            && (resolution.descriptor?.isProductionEligible == true)
        context.coordinator.activeStyleKey = Self.styleKey(
            resolution: resolution,
            customStylesEnabled: customStylesEnabled,
            mapModeContext: mapModeContext
        )
        context.coordinator.lastHandledStyleRequestID = styleRequestID
        context.coordinator.lastCameraKey = Self.cameraKey(
            center: center, zoom: zoom, tilt: tilt)

        let html = Self.buildHTML(
            apiKey: HereMapsConfig.jsApiKey,
            styleConfigurationJSON: Self.styleConfigurationJSON(
                resolution: resolution,
                customStylesEnabled: customStylesEnabled,
                customStylesRequested: customStylesRequested,
                familySelectionSource: familySelectionSource,
                mapModeContext: mapModeContext,
                requestID: styleRequestID
            ),
            interactive: interactive,
            centerLat: center.lat,
            centerLng: center.lng,
            zoom: zoom,
            tilt: tilt,
            reducedMotion: reducedMotion,
            endpointLabelToggle: endpointLabelToggle
        )
        if EusoTripAPI.shared.isAppRadioSilenceEnforced {
            // A view rebuilt during an active offline lease must never create
            // a remote HERE JS navigation, even transiently.
            webView.loadHTMLString("", baseURL: nil)
        } else {
            // THE FIX: origin = a HERE-portal trusted domain (not js.api.here.com).
            webView.loadHTMLString(html, baseURL: URL(string: HereMapsConfig.jsTrustedReferrerOrigin))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard !EusoTripAPI.shared.isAppRadioSilenceEnforced else {
            context.coordinator.disposeForAppRadioSilence()
            return
        }
        context.coordinator.onSelectMarker = onSelectMarker
        context.coordinator.onStyleTransition = onStyleTransition
        let resolution = EusoTripMapStyleRegistry.resolve(
            context: mapModeContext,
            family: mapFamily,
            theme: isDark ? .dark : .light
        )
        let customStylesRequested = HereMapsConfig.customMapStylesEnabled
        let customStylesEnabled = customStylesRequested
            && (resolution.descriptor?.isProductionEligible == true)
        let styleKey = Self.styleKey(
            resolution: resolution,
            customStylesEnabled: customStylesEnabled,
            mapModeContext: mapModeContext
        )
        let matchesPending = context.coordinator.pendingStyleKey == styleKey
            && context.coordinator.pendingStyleRequestID == styleRequestID
        let isNewUserRequest = styleRequestID > context.coordinator.lastHandledStyleRequestID
        if !matchesPending,
           context.coordinator.activeStyleKey != styleKey || isNewUserRequest {
            context.coordinator.pendingStyleKey = styleKey
            context.coordinator.pendingStyleRequestID = styleRequestID
            context.coordinator.lastHandledStyleRequestID = max(
                context.coordinator.lastHandledStyleRequestID,
                styleRequestID
            )
            let configuration = Self.styleConfigurationJSON(
                resolution: resolution,
                customStylesEnabled: customStylesEnabled,
                customStylesRequested: customStylesRequested,
                familySelectionSource: familySelectionSource,
                mapModeContext: mapModeContext,
                requestID: styleRequestID
            )
            let styleJS = "window.__setMapStyle && window.__setMapStyle(\(configuration));"
            context.coordinator.pendingStyleJS = styleJS
            if context.coordinator.mapReady {
                webView.evaluateJavaScript(styleJS)
            }
        }
        webView.evaluateJavaScript(
            "window.__setEndpointLabelToggle && window.__setEndpointLabelToggle(\(endpointLabelToggle ? "true" : "false"));"
        )
        webView.evaluateJavaScript(
            "window.__setReducedMotion && window.__setReducedMotion(\(reducedMotion ? "true" : "false"));"
        )
        let cameraKey = Self.cameraKey(center: center, zoom: zoom, tilt: tilt)
        if context.coordinator.lastCameraKey != cameraKey {
            context.coordinator.lastCameraKey = cameraKey
            let cameraJS = "window.__setCamera && window.__setCamera(\(center.lat),\(center.lng),\(zoom),\(tilt));"
            context.coordinator.pendingCameraJS = cameraJS
            if context.coordinator.mapReady {
                webView.evaluateJavaScript(cameraJS)
            }
        }
        // Push layer data once the map signals ready (or immediately if it is).
        let payload = Self.encodeLayers(layers)
        context.coordinator.pendingLayerJSON = payload
        if context.coordinator.mapReady {
            webView.evaluateJavaScript("window.__applyLayers && window.__applyLayers(\(payload));")
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        coordinator.webView = nil
        coordinator.resetRendererState(clearCallbacks: true)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var mapReady = false
        var activeStyleKey: String?
        var pendingStyleKey: String?
        var pendingStyleRequestID: Int?
        var lastHandledStyleRequestID = 0
        var pendingStyleJS: String?
        var lastCameraKey: String?
        var pendingCameraJS: String?
        var pendingLayerJSON = "{}"
        var onSelectMarker: ((String) -> Void)?
        var onStyleTransition: ((EusoTripMapStyleTransitionEvent) -> Void)?

        override init() {
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(appRadioSilenceWillEngage),
                name: .eusoAppRadioSilenceWillEngage,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func appRadioSilenceWillEngage() {
            disposeForAppRadioSilence()
        }

        func disposeForAppRadioSilence() {
            guard let webView else {
                resetRendererState(clearCallbacks: true)
                return
            }
            webView.stopLoading()
            webView.configuration.userContentController.removeAllScriptMessageHandlers()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.loadHTMLString("", baseURL: nil)
            self.webView = nil
            mapReady = false
            activeStyleKey = nil
            pendingStyleKey = nil
            pendingStyleRequestID = nil
            lastHandledStyleRequestID = 0
            pendingStyleJS = nil
            lastCameraKey = nil
            pendingCameraJS = nil
            pendingLayerJSON = "{}"
            onSelectMarker = nil
            onStyleTransition = nil
        }

        func resetRendererState(clearCallbacks: Bool) {
            webView = nil
            mapReady = false
            activeStyleKey = nil
            pendingStyleKey = nil
            pendingStyleRequestID = nil
            lastHandledStyleRequestID = 0
            pendingStyleJS = nil
            lastCameraKey = nil
            pendingCameraJS = nil
            pendingLayerJSON = "{}"
            if clearCallbacks {
                onSelectMarker = nil
                onStyleTransition = nil
            }
        }

        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "mapReady":
                mapReady = true
                if let pendingStyleJS {
                    webView?.evaluateJavaScript(pendingStyleJS)
                }
                if let pendingCameraJS {
                    webView?.evaluateJavaScript(pendingCameraJS)
                }
                webView?.evaluateJavaScript("window.__applyLayers && window.__applyLayers(\(pendingLayerJSON));")
            case "markerTap":
                if let id = message.body as? String, !id.isEmpty {
                    onSelectMarker?(id)
                }
            case "mapStyleTransition":
                guard
                    let body = message.body as? [String: Any],
                    let phaseRaw = body["phase"] as? String,
                    let phase = EusoTripMapStyleTransitionEvent.Phase(rawValue: phaseRaw),
                    let familyRaw = body["family"] as? String,
                    let family = EusoTripMapFamily(rawValue: familyRaw)
                else { return }
                let requestID = (body["requestID"] as? NSNumber)?.intValue ?? 0
                let event = EusoTripMapStyleTransitionEvent(
                    phase: phase,
                    family: family,
                    requestID: requestID,
                    message: body["message"] as? String
                )
                if event.requestID == pendingStyleRequestID {
                    switch event.phase {
                    case .pending:
                        break
                    case .committed:
                        activeStyleKey = pendingStyleKey
                        pendingStyleKey = nil
                        pendingStyleRequestID = nil
                        pendingStyleJS = nil
                    case .failed:
                        pendingStyleKey = nil
                        pendingStyleRequestID = nil
                        pendingStyleJS = nil
                    }
                }
                DispatchQueue.main.async { [weak self] in
                    self?.onStyleTransition?(event)
                }
            case "hzLog":
                #if DEBUG
                print("[HereMap] \(message.body)")
                #endif
            default: break
            }
        }
    }

    private static func cameraKey(center: HereLatLng, zoom: Int, tilt: Double) -> String {
        "\(center.lat),\(center.lng),\(zoom),\(tilt)"
    }

    private static func styleKey(
        resolution: EusoTripMapStyleResolution,
        customStylesEnabled: Bool,
        mapModeContext: EusoTripMapModeContext
    ) -> String {
        let selection = resolution.descriptor?.id
            ?? "unavailable.\(resolution.unavailableReason?.rawValue ?? "unknown")"
        let foundation = resolution.foundation
        return [
            selection,
            foundation.family.rawValue,
            foundation.theme.rawValue,
            mapModeContext.sourceTransportMode.rawValue,
            customStylesEnabled ? "custom" : "standard",
        ].joined(separator: ":")
    }

    private static func styleConfigurationJSON(
        resolution: EusoTripMapStyleResolution,
        customStylesEnabled: Bool,
        customStylesRequested: Bool,
        familySelectionSource: EusoTripMapFamilySelectionSource,
        mapModeContext: EusoTripMapModeContext,
        requestID: Int
    ) -> String {
        let origin = HereMapsConfig.jsTrustedReferrerOrigin
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let descriptor = resolution.descriptor
        let foundation = resolution.foundation
        var object: [String: Any] = [
            "family": foundation.family.rawValue,
            "theme": foundation.theme.rawValue,
            "displayName": descriptor?.assetName ?? foundation.hereDefaultFallbackName,
            "artifactURL": descriptor.map { "\(origin)\($0.artifactPath)" } ?? "",
            "artifactSHA256": descriptor?.artifactSHA256 ?? "",
            "fallbackIdentity": foundation.hereDefaultStyleIdentity,
            "omvContent": foundation.omvContent,
            "transportMode": mapModeContext.sourceTransportMode.rawValue,
            "productMode": descriptor?.mode.rawValue ?? "",
            "familySelectionSource": familySelectionSource.rawValue,
            "customStylesRequested": customStylesRequested,
            "customStylesEnabled": customStylesEnabled,
            "requestID": requestID,
            "resolutionState": descriptor == nil ? "unavailable" : "resolved",
            "visualReviewState": descriptor?.visualReviewState.rawValue
                ?? EusoTripMapIdentityContract.visualReviewState.rawValue,
            "visualReviewNote": descriptor?.visualReviewNote
                ?? "Product mode unresolved; matching stock family is shown without claiming product styling.",
        ]
        if let reason = resolution.unavailableReason {
            object["unavailableReason"] = reason.rawValue
        }
        if let message = resolution.unavailableMessage {
            object["unavailableMessage"] = message
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    // MARK: Layer JSON

    static func encodeLayers(_ layers: [HereMapLayer]) -> String {
        var heatmap: [[String: Any]] = []
        var markers: [[String: Any]] = []
        var routes: [[String: Any]] = []
        var observationTrails: [[String: Any]] = []
        var polygons: [[String: Any]] = []
        var fences: [[String: Any]] = []
        var traffic: [[String: Any]] = []

        for layer in layers {
            switch layer {
            case .heatmap(let pts):
                heatmap = pts
                    .filter(\.isUsableCoordinate)
                    .map { ["lat": $0.lat, "lng": $0.lng, "value": $0.weight ?? 1.0] }
            case .markers(let ms), .missionPins(let ms):
                markers.append(contentsOf: ms.filter(\.at.isUsableCoordinate).map { m in
                    // Every pin is tappable: synthesize a stable id when the
                    // caller didn't supply one (kind + rounded coords).
                    let mid = (m.id?.isEmpty == false)
                        ? m.id!
                        : "\(m.kind.rawValue):\(m.at.lat),\(m.at.lng)"
                    return [
                        "lat": m.at.lat,
                        "lng": m.at.lng,
                        "kind": m.kind.rawValue,
                        "label": m.label ?? "",
                        "id": mid,
                        "observationState": m.observationState.rawValue,
                        "sourceLabel": m.sourceLabel ?? "",
                        "accessibilityLabel": m.accessibilityLabel ?? "",
                        "clusterCount": m.clusterCount ?? 0,
                        "coordinateLabel": LatLongParser.displayString(
                            CLLocationCoordinate2D(latitude: m.at.lat, longitude: m.at.lng)
                        ),
                    ]
                })
            case .route:
                // Legacy/static route-like geometry is not a separate visual
                // grammar. It fails closed until the caller supplies exact,
                // server-bound `.eusoRoute` geometry and state.
                break
            case .eusoRoute(let poly, let state, let label):
                // A filtered/reconnected line is not the server-authored
                // geometry. Fail the whole member closed on any bad point.
                if poly.count >= 2, poly.allSatisfy(\.isUsableCoordinate) {
                    routes.append([
                        "state": state.rawValue,
                        "label": label ?? state.rawValue.capitalized,
                        "pts": poly.map { ["lat": $0.lat, "lng": $0.lng] },
                    ])
                }
            case .observationTrail(let poly, let label):
                let points = poly.filter(\.isUsableCoordinate)
                if points.count >= 2 {
                    observationTrails.append([
                        "label": label,
                        "pts": points.map { ["lat": $0.lat, "lng": $0.lng] },
                    ])
                }
            case .adZones(let polys):
                polygons.append(contentsOf: polys.compactMap { p in
                    let ring = p.ring.filter(\.isUsableCoordinate)
                    guard ring.count >= 3 else { return nil }
                    return [
                        "fill": p.fillHex,
                        "opacity": p.opacity,
                        "label": p.label ?? "",
                        "ring": ring.map { ["lat": $0.lat, "lng": $0.lng] },
                    ]
                })
            case .geofenceRing(let center, let radius, let kind, let breach):
                guard center.isUsableCoordinate, radius.isFinite, radius > 0 else { continue }
                var f: [String: Any] = ["lat": center.lat, "lng": center.lng,
                                        "radius": radius, "kind": kind.rawValue]
                if let b = breach, b.isUsableCoordinate {
                    f["breachLat"] = b.lat
                    f["breachLng"] = b.lng
                }
                fences.append(f)
            case .trafficFlow(let segs):
                traffic.append(contentsOf: segs.compactMap { s in
                    let points = s.polyline.filter(\.isUsableCoordinate)
                    guard points.count >= 2 else { return nil }
                    return [
                        "severity": s.severity.rawValue,
                        "pts": points.map { ["lat": $0.lat, "lng": $0.lng] },
                    ]
                })
            }
        }
        let obj: [String: Any] = [
            "heatmap": heatmap,
            "markers": markers,
            "routes": routes,
            "observationTrails": observationTrails,
            "polygons": polygons,
            "fences": fences,
            "traffic": traffic,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    // MARK: HTML template

    static func buildHTML(
        apiKey: String?,
        styleConfigurationJSON: String,
        interactive: Bool,
        centerLat: Double,
        centerLng: Double,
        zoom: Int,
        tilt: Double = 0,
        reducedMotion: Bool = false,
        endpointLabelToggle: Bool = false
    ) -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            return """
            <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"/>
            <style>html,body{margin:0;height:100%;background:#0b0b0f;color:#fff;font:12px -apple-system}
            .e{height:100%;display:flex;align-items:center;justify-content:center;opacity:.6;text-align:center;padding:12px}</style>
            </head><body><div class="e">Map unavailable. Everything else on this screen still works.</div></body></html>
            """
        }
        let dragFlags = interactive
            ? ""
            : "behavior.disable(H.mapevents.Behavior.DRAGGING | H.mapevents.Behavior.WHEELZOOM | H.mapevents.Behavior.DBLTAPZOOM | H.mapevents.Behavior.FRACTIONALZOOM);"

        return """
        <!doctype html><html><head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"/>
        <link rel="stylesheet" href="https://js.api.here.com/v3/3.2.8.0/mapsjs-ui.css"/>
        <style>
        html,body,#map{margin:0;padding:0;width:100%;height:100%;background:#0b0b0f;position:relative}
        #style-status{display:none;position:absolute;right:8px;bottom:8px;z-index:4;max-width:260px;padding:8px 10px;border:1px solid rgba(255,255,255,.24);border-radius:12px;background:rgba(16,24,40,.88);box-shadow:0 5px 16px rgba(0,0,0,.18);color:#f5f5f7;font:600 11px -apple-system;text-align:left}
        #style-status:before{content:"";display:block;height:3px;margin:-5px -6px 6px;border-radius:999px;background:linear-gradient(90deg,#1473FF 0%,#813FF5 52%,#BE01FF 100%)}
        #style-status.loading{display:block;border-color:rgba(129,63,245,.72)}
        #style-status.retryable{display:block;border-style:dashed;border-color:rgba(255,174,66,.78)}
        #style-status.mode-unavailable{display:block;border-style:dashed;border-color:rgba(255,174,66,.75)}
        #style-status.unavailable{display:flex;box-sizing:border-box;inset:0;right:0;bottom:0;width:auto;max-width:none;align-items:center;justify-content:center;border-radius:0;padding:18px;background:#111318;font-size:12px}
        .sr-only{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}
        </style>
        <script src="https://js.api.here.com/v3/3.2.8.0/mapsjs-core.js"></script>
        <script src="https://js.api.here.com/v3/3.2.8.0/mapsjs-service.js"></script>
        <script src="https://js.api.here.com/v3/3.2.8.0/mapsjs-ui.js"></script>
        <script src="https://js.api.here.com/v3/3.2.8.0/mapsjs-data.js"></script>
        <script src="https://js.api.here.com/v3/3.2.8.0/mapsjs-mapevents.js"></script>
        </head><body><div id="map" role="application" aria-label="EusoTrip freight map"></div><div id="style-status" role="status" aria-live="polite"></div><div id="map-accessibility-summary" class="sr-only" aria-live="polite"></div><script>
        (function(){
          function log(m){ try{ window.webkit.messageHandlers.hzLog.postMessage(String(m)); }catch(e){} }
          var map, behavior, platform, heatLayer=null, objLayer=null;
          var styleConfiguration = \(styleConfigurationJSON);
          var styleGeneration = 0;
          var currentSelection = null;
          var pendingSelection = null;
          var hasCommittedStyle = false;
          var endpointLabelToggle = \(endpointLabelToggle ? "true" : "false");
          var reducedMotion = \(reducedMotion ? "true" : "false");
          var cameraTilt = \(tilt);
          var lastRouteSignature = "";
          // Deliberately does NOT say "check your connection". The base-layer
          // path fails on a provider-contract change far more often than on a
          // dead network, and telling someone with working signal to check
          // their connection sends them to debug the wrong thing.
          function familyName(cfg){
            var raw=String((cfg&&cfg.family)||"");
            return raw ? raw.charAt(0).toUpperCase()+raw.slice(1) : "Selected";
          }
          function safeStyleFailureMessage(reason,cfg){
            var raw="";
            try{
              raw=String(reason&&reason.message ? reason.message : (reason||""));
            }catch(e){}
            var name=familyName(cfg);
            if(raw.indexOf("must end in .tar.gz")>=0){
              return name+" map export is not in the required HERE archive format.";
            }
            if(raw.indexOf("did not become READY")>=0){
              return name+" map did not become ready. Retry when HERE is available.";
            }
            if(raw.indexOf("Unsupported map family")>=0 || raw.indexOf("Unsupported matching fallback")>=0){
              return name+" is not available for this map.";
            }
            if(raw.indexOf("did not commit")>=0){
              return name+" map was not committed. "+familyName(styleConfiguration)+" remains active.";
            }
            return hasCommittedStyle
              ? name+" map could not be prepared. "+familyName(styleConfiguration)+" remains active."
              : name+" map could not be prepared.";
          }
          function notifyStyleTransition(phase,cfg,message){
            try{
              window.webkit.messageHandlers.mapStyleTransition.postMessage({
                phase:String(phase),
                family:String((cfg&&cfg.family)||""),
                requestID:Number((cfg&&cfg.requestID)||0),
                message:message ? String(message) : ""
              });
            }catch(e){}
          }
          function setStyleState(state,cfg){
            var el=document.getElementById("style-status");
            if(!el) return;
            el.className="";
            if(state==="loading"){
              el.style.display="block";
              el.className="loading";
              el.textContent="Loading "+familyName(cfg)+" map...";
            }else if(state==="failed"){
              el.style.display="block";
              el.className="retryable";
              el.textContent=familyName(cfg)+" did not load. "+familyName(styleConfiguration)+" remains active. Retry from the map menu.";
            }else if(state==="fallback"){
              el.style.display="block";
              el.textContent="Standard map · custom styling unavailable";
            }else if(state==="standard"){
              el.style.display="block";
              el.textContent="Standard family · EusoTrip visual review pending";
            }else if(state==="mode-unavailable"){
              el.style.display="block";
              el.className="mode-unavailable";
              el.textContent="Map mode unresolved · matching standard family retained";
            }else if(state==="stale"){
              el.style.display="block";
              el.textContent="Map type update unavailable · previous map retained";
            }else if(state==="unavailable"){
              el.style.display="flex";
              el.className="unavailable";
              el.textContent="Map unavailable. Live freight data remains available.";
            }else{
              el.style.display="none";
              el.textContent="";
            }
          }
          // Animated map fx (fence pulses / breach exitPulse / pilot-ground
          // dashoffset) — one shared timer, rebuilt on every __applyLayers.
          var fx = [], fxTimer = null;
          function stopFx(){ if(fxTimer){ clearInterval(fxTimer); fxTimer=null; } fx = []; }
          function startFx(){
            if(reducedMotion || fxTimer || !fx.length) return;
            var t = 0;
            fxTimer = setInterval(function(){
              t += 0.08;
              for(var i=0;i<fx.length;i++){ try{ fx[i](t); }catch(e){} }
            }, 80);
          }

          var contentByFamily = {
            operational: "default,advanced_roads,advanced_pois,transit",
            navigation: "default,transit",
            terrain: "default,hillshade,contours,transit"
          };
          var fallbackIdentities = {
            "logistics.day":true, "logistics.night":true,
            "topo.day":true, "topo.night":true
          };
          function fallbackStyleURL(identity){
            return "https://js.api.here.com/v3/3.2.8.0/styles/harp/oslo/"+identity+".json";
          }
          function createStyleHandle(url,family,onReady,onError){
            if(!contentByFamily[family]) throw new Error("Unsupported map family");
            var style = new H.map.render.harp.Style(url);
            var layer = null, settled = false, disposed = false, timeoutID = null;
            function settleReady(){
              if(disposed || settled) return;
              settled = true;
              if(timeoutID){ clearTimeout(timeoutID); timeoutID=null; }
              onReady();
            }
            function settleError(error){
              if(disposed || settled) return;
              settled = true;
              if(timeoutID){ clearTimeout(timeoutID); timeoutID=null; }
              onError(error);
            }
            function inspect(){
              if(style.getState() === H.map.render.Style.State.READY) settleReady();
            }
            function fail(event){ settleError(event); }
            style.addEventListener("change", inspect);
            style.addEventListener("error", fail);
            var service = platform.getOMVService({ queryParams: { content: contentByFamily[family] } });
            layer = service.createLayer(style);
            timeoutID = setTimeout(function(){
              settleError(new Error("HERE style did not become READY within 20000ms"));
            }, 20000);
            Promise.resolve().then(inspect);
            return {
              layer:layer,
              dispose:function(){
                if(disposed) return;
                disposed=true;
                if(timeoutID){ clearTimeout(timeoutID); timeoutID=null; }
                try{ style.removeEventListener("change",inspect); }catch(e){}
                try{ style.removeEventListener("error",fail); }catch(e){}
                try{ if(layer && layer.dispose){ layer.dispose(); } }catch(e){}
                try{ if(style && style.dispose){ style.dispose(); } }catch(e){}
                layer=null;
              }
            };
          }
          function createSelection(cfg,generation,onReady,onFailure){
            var current=null, disposed=false, selection=null;
            function fail(reason){
              Promise.resolve().then(function(){
                if(!disposed){ onFailure(selection,reason); }
              });
            }
            function startFallback(reason){
              if(disposed) return;
              if(reason){ log(cfg.displayName+" failed; matching fallback: "+reason); }
              if(!fallbackIdentities[cfg.fallbackIdentity]){
                fail(new Error("Unsupported matching fallback identity"));
                return;
              }
              if(current){ current.dispose(); current=null; }
              try{
                current=createStyleHandle(
                  fallbackStyleURL(cfg.fallbackIdentity), cfg.family,
                  function(){
                    if(!disposed){
                      onReady(
                        selection,
                        cfg.resolutionState==="unavailable"
                          ? "mode-unavailable"
                          : (cfg.customStylesEnabled?"fallback":"standard")
                      );
                    }
                  },
                  function(err){
                    if(!disposed){ log("fallback style "+err); fail(err); }
                  }
                );
              }catch(err){
                log("fallback construction "+err);
                fail(err);
              }
            }
            selection={
              get layer(){ return current?current.layer:null; },
              generation:generation,
              dispose:function(){
                if(disposed) return;
                disposed=true;
                if(current) current.dispose();
                current=null;
              }
            };
            if(cfg.customStylesEnabled){
              if(!/\\.tar\\.gz$/.test(cfg.artifactURL)){
                startFallback("custom style URL must end in .tar.gz");
              }else{
                try{
                  current=createStyleHandle(
                    cfg.artifactURL, cfg.family,
                    function(){ if(!disposed){ onReady(selection,"custom"); } },
                    startFallback
                  );
                }catch(err){
                  log("custom construction "+err);
                  startFallback(err);
                }
              }
            }else{
              startFallback(null);
            }
            return selection;
          }

          try{
            platform = new H.service.Platform({ apikey: "\(apiKey)" });
            styleGeneration += 1;
            var selection = createSelection(
              styleConfiguration,
              styleGeneration,
              function(prepared,state){
                if(prepared!==currentSelection || prepared.generation!==styleGeneration) return;
                try{
                  if(map && prepared.layer){ map.setBaseLayer(prepared.layer); }
                  if(map && map.getBaseLayer && map.getBaseLayer()!==prepared.layer){
                    throw new Error("HERE did not commit the requested base layer");
                  }
                  hasCommittedStyle=true;
                  setStyleState(state,styleConfiguration);
                  notifyStyleTransition("committed",styleConfiguration,"");
                }catch(err){
                  log("initial style commit "+err);
                  setStyleState("unavailable");
                  notifyStyleTransition("failed",styleConfiguration,safeStyleFailureMessage(err,styleConfiguration));
                }
              },
              function(failed,reason){
                if(failed!==currentSelection || failed.generation!==styleGeneration) return;
                log("initial style failed "+reason);
                setStyleState("unavailable");
                notifyStyleTransition("failed",styleConfiguration,safeStyleFailureMessage(reason,styleConfiguration));
              }
            );
            if(!selection.layer){ setStyleState("unavailable"); return; }

            var baseOpts = { center:{lat:\(centerLat),lng:\(centerLng)}, zoom:\(zoom), pixelRatio: window.devicePixelRatio||1 };
            var el = document.getElementById("map");
            map = new H.Map(el, selection.layer, baseOpts);
            currentSelection = selection;
            window.addEventListener("resize", function(){ map.getViewPort().resize(); });
            behavior = new H.mapevents.Behavior(new H.mapevents.MapEvents(map));
            \(dragFlags)

            // First-person / navigation tilt (0 = flat top-down). Gives the
            // driver an immersive perspective view of the lane ahead.
            try{ if(\(Int(tilt)) > 0 && map.getViewModel){ map.getViewModel().setLookAtData({ tilt: \(Int(tilt)) }); } }catch(e){ log("tilt "+e); }

            // Family/theme changes swap only the base layer. Camera, maneuvers,
            // route objects, overlays, and active guidance remain on this map.
            window.__setMapStyle = function(cfg){
              try{
                styleGeneration += 1;
                var requestedGeneration=styleGeneration;
                if(pendingSelection){ pendingSelection.dispose(); pendingSelection=null; }
                setStyleState("loading",cfg);
                notifyStyleTransition("pending",cfg,"");
                var next = createSelection(
                  cfg,
                  requestedGeneration,
                  function(prepared,state){
                    if(prepared!==pendingSelection || prepared.generation!==styleGeneration){
                      prepared.dispose();
                      return;
                    }
                    var previous=currentSelection;
                    try{
                      map.setBaseLayer(prepared.layer);
                      if(map.getBaseLayer && map.getBaseLayer()!==prepared.layer){
                        throw new Error("HERE did not commit the requested base layer");
                      }
                      currentSelection=prepared;
                      pendingSelection=null;
                      styleConfiguration=cfg;
                      hasCommittedStyle=true;
                      setStyleState(state,cfg);
                      notifyStyleTransition("committed",cfg,"");
                      if(previous) previous.dispose();
                    }catch(err){
                      log("style commit "+err);
                      prepared.dispose();
                      pendingSelection=null;
                      setStyleState(hasCommittedStyle ? "failed" : "unavailable",cfg);
                      notifyStyleTransition("failed",cfg,safeStyleFailureMessage(err,cfg));
                    }
                  },
                  function(failed,reason){
                    if(failed!==pendingSelection || failed.generation!==styleGeneration){
                      failed.dispose();
                      return;
                    }
                    log("style prepare failed "+reason);
                    failed.dispose();
                    pendingSelection=null;
                    setStyleState(hasCommittedStyle ? "failed" : "unavailable",cfg);
                    notifyStyleTransition("failed",cfg,safeStyleFailureMessage(reason,cfg));
                  }
                );
                pendingSelection=next;
              }catch(e){
                log("setMapStyle "+e);
                setStyleState(hasCommittedStyle ? "failed" : "unavailable",cfg);
                notifyStyleTransition("failed",cfg,safeStyleFailureMessage(e,cfg));
              }
            };

            window.__setEndpointLabelToggle = function(enabled){
              endpointLabelToggle = Boolean(enabled);
            };

            window.__setReducedMotion = function(enabled){
              reducedMotion = Boolean(enabled);
              if(reducedMotion){ stopFx(); }
              else{ startFx(); }
            };

            window.__setCamera = function(lat,lng,z,t){
              try{
                cameraTilt = Number(t)||0;
                map.setCenter({lat:Number(lat),lng:Number(lng)}, !reducedMotion);
                map.setZoom(Number(z), !reducedMotion);
                if(map.getViewModel){ map.getViewModel().setLookAtData({tilt:cameraTilt}); }
              }catch(e){ log("setCamera "+e); }
            };

            function clearObjects(){ if(objLayer){ map.removeObjects(map.getObjects()); } }

            window.__applyLayers = function(L){
              try{
                stopFx();
                // heatmap
                if(heatLayer){ map.removeLayer(heatLayer); heatLayer=null; }
                if(L.heatmap && L.heatmap.length){
                  var hp = new H.data.heatmap.Provider({ colors:H.data.heatmap.Colors.DEFAULT, opacity:0.75, assumeValues:true, interpolate:true });
                  hp.addData(L.heatmap);
                  heatLayer = new H.map.layer.TileLayer(hp);
                  map.addLayer(heatLayer);
                }
                // vector objects (routes, traffic, polygons, fences, markers)
                map.removeObjects(map.getObjects());
                var grp = new H.map.Group();

                // EusoLine grammar: one slim continuous ROUTE-ORDER ribbon,
                // origin #1473FF → midpoint #813FF5 → destination #BE01FF.
                // Raw GNSS, AIS, or rail positions never infer progress. State
                // remains caller-owned through localized glyphs and accessible
                // text; it never modifies or adds a route stroke.
                (L.routes||[]).forEach(function(r){
                  var pts = r.pts||[];
                  if(pts.length<2) return;
                  var spec = routeStateSpec(r.state);
                  addEusoLine(grp, pts, spec);
                });

                // Position history is observation evidence, not route
                // authority. Neutral dotted grammar prevents progress claims.
                (L.observationTrails||[]).forEach(function(t){
                  var pts=t.pts||[];
                  if(pts.length<2) return;
                  var ls=new H.geo.LineString();
                  pts.forEach(function(p){ls.pushPoint({lat:p.lat,lng:p.lng});});
                  grp.addObject(new H.map.Polyline(ls,{style:{
                    lineWidth:3,
                    strokeColor:"rgba(96,125,139,.82)",
                    lineDash:[2,5],
                    lineCap:"round"
                  }}));
                });

                // Traffic-flow ribbons over the road network (536, §2):
                // jam = #FFA726 w6 round @0.9 · severe = #F44336 w6 @0.85.
                (L.traffic||[]).forEach(function(s){
                  var pts = s.pts||[];
                  if(pts.length<2) return;
                  var spec = (s.severity==="severe") ? {c:"#F44336",a:0.85} : {c:"#FFA726",a:0.90};
                  var ls = new H.geo.LineString();
                  pts.forEach(function(p){ ls.pushPoint({lat:p.lat,lng:p.lng}); });
                  grp.addObject(new H.map.Polyline(ls, { style:{
                    lineWidth:6, strokeColor:hexA(spec.c, spec.a), lineCap:"round" } }));
                });

                (L.polygons||[]).forEach(function(pg){
                  var ring = pg.ring||[];
                  var ls = new H.geo.LineString();
                  ring.forEach(function(p){ ls.pushPoint({lat:p.lat,lng:p.lng}); });
                  if(ring.length>2){
                    grp.addObject(new H.map.Polygon(ls, { style:{ fillColor:hexA(pg.fill, pg.opacity), strokeColor:pg.fill, lineWidth:2 } }));
                    // (Tappable centroid pin for the zone is emitted as a
                    //  separate marker by HereAddOnsModel, so none here.)
                  }
                });

                // Geofence rings (§3c): dashed circle fences, per-kind color
                // + dash cadence, plus pulse fx and the breach/EXIT node.
                (L.fences||[]).forEach(function(f){ try{ addFence(grp, f); }catch(e){ log("fence "+e); } });

                (L.markers||[]).forEach(function(m){
                  try{
                    var ic = iconFor(
                      m.kind,
                      m.label,
                      m.observationState,
                      m.accessibilityLabel,
                      m.clusterCount
                    );
                    var mk = ic ? new H.map.Marker({lat:m.lat,lng:m.lng},{icon:ic})
                                : new H.map.Marker({lat:m.lat,lng:m.lng});
                    // A destination has one label slot. On detail maps a tap
                    // replaces the address with the exact coordinate and a
                    // second tap restores it; the two never overlap.
                    if(m.id || (m.kind==="delivery" && m.label)){
                      var showingCoordinate = false;
                      mk.setData(m.id);
                      mk.addEventListener("tap", function(ev){
                        if(endpointLabelToggle && m.kind==="delivery" && m.label && m.coordinateLabel){
                          showingCoordinate = !showingCoordinate;
                          var nextIcon = iconFor(
                            m.kind,
                            showingCoordinate ? m.coordinateLabel : m.label
                          );
                          if(nextIcon){ ev.target.setIcon(nextIcon); }
                          return;
                        }
                        try{ window.webkit.messageHandlers.markerTap.postMessage(String(ev.target.getData())); }catch(e){}
                      });
                    }
                    grp.addObject(mk);
                  }catch(e){ grp.addObject(new H.map.Marker({lat:m.lat,lng:m.lng})); }
                });
                if(grp.getObjects().length){ map.addObject(grp); }

                var a11y=[];
                (L.routes||[]).forEach(function(r){
                  a11y.push((r.label||"Route")+", "+(r.state||"planned"));
                });
                (L.observationTrails||[]).forEach(function(t){
                  a11y.push((t.label||"Position history")+", observation trail, not route progress");
                });
                (L.markers||[]).forEach(function(m){
                  var name=m.accessibilityLabel||m.label||m.kind||"observation";
                  var source=m.sourceLabel ? ", source "+m.sourceLabel : "";
                  a11y.push(name+", "+(m.observationState||"current")+source);
                });
                var a11yEl=document.getElementById("map-accessibility-summary");
                if(a11yEl){ a11yEl.textContent=a11y.join(". "); }

                // Fit a newly supplied route once. Add-on refreshes reuse the
                // same signature, so they do not keep stealing the camera
                // after the user pans or zooms. First-person navigation keeps
                // its authored camera instead of fitting the whole trip.
                var routeSig = "";
                var fitRoutes=(L.routes||[]);
                if(fitRoutes.length){
                  routeSig = fitRoutes.map(function(r){
                    var p=r.pts||[], a=p[0]||{}, b=p[p.length-1]||{};
                    return p.length+":"+a.lat+","+a.lng+":"+b.lat+","+b.lng;
                  }).join("|");
                }
                if(routeSig && routeSig!==lastRouteSignature && cameraTilt<=1){
                  lastRouteSignature=routeSig;
                  try{
                    var bounds=grp.getBoundingBox();
                    if(bounds){ map.getViewModel().setLookAtData({bounds:bounds}); }
                  }catch(e){ log("fit route "+e); }
                }
                startFx();
              }catch(e){ log("applyLayers "+e); }
            };

            function hexA(hex, a){
              try{ var h=hex.replace('#',''); var r=parseInt(h.substr(0,2),16),g=parseInt(h.substr(2,2),16),b=parseInt(h.substr(4,2),16);
                   return "rgba("+r+","+g+","+b+","+(a||0.25)+")"; }catch(e){ return "rgba(20,115,255,0.25)"; }
            }

            // ── Route sweep (§2) ─────────────────────────────────────────
            // HERE polylines have no gradient stroke, so render deterministic
            // route-order chunks. Geographic direction cannot invert identity.
            function mix(a,b,t){ return Math.round(a+(b-a)*t); }
            function sweepColor(t, a){
              t = Math.max(0, Math.min(1, t));
              var from,to,local,midpoint=.52;
              if(t<=midpoint){
                from=[0x14,0x73,0xFF]; to=[0x81,0x3F,0xF5]; local=t/midpoint;
              }else{
                from=[0x81,0x3F,0xF5]; to=[0xBE,0x01,0xFF]; local=(t-midpoint)/(1-midpoint);
              }
              return "rgba("+mix(from[0],to[0],local)+","+mix(from[1],to[1],local)+","+mix(from[2],to[2],local)+","+a+")";
            }
            function routeStateSpec(state){
              // Route state belongs to text and localized glyphs. Every state
              // preserves the same five-point EusoLine with no dash or edge.
              return {width:5};
            }
            function wrappedLngDelta(from,to){
              var delta=to-from;
              while(delta>180){delta-=360;}
              while(delta< -180){delta+=360;}
              return delta;
            }
            function normalizedLng(value){
              while(value>180){value-=360;}
              while(value< -180){value+=360;}
              return value;
            }
            // Renderer-local cumulative-distance subdivision. It colors the
            // exact supplied polyline locus only; it is never route distance,
            // route progress, ETA, Haul, pricing, or a replacement solver.
            function eusoLineSegments(pts,budget){
              if(!pts || pts.length<2) return;
              var weights=[], cumulative=[0], total=0, epsilon=1e-12;
              for(var i=0;i<pts.length-1;i++){
                var a=pts[i], b=pts[i+1];
                var dy=(b.lat-a.lat)*Math.PI/180;
                var dx=wrappedLngDelta(a.lng,b.lng)*Math.PI/180;
                var mean=(a.lat+b.lat)*Math.PI/360;
                var weight=Math.sqrt((dy*dy)+(dx*Math.cos(mean))*(dx*Math.cos(mean)));
                weights.push(weight); total+=weight; cumulative.push(total);
              }
              if(total<=epsilon){ return [{points:pts.slice(),progress:.5}]; }
              var count=Math.max(1,Math.min(96,Math.floor(budget||72)));
              function pointAt(distance){
                if(distance<=0){return {lat:pts[0].lat,lng:pts[0].lng};}
                if(distance>=total){var last=pts[pts.length-1];return {lat:last.lat,lng:last.lng};}
                var low=0, high=cumulative.length-1;
                while(low+1<high){
                  var middle=Math.floor((low+high)/2);
                  if(cumulative[middle]<=distance){low=middle;}else{high=middle;}
                }
                var edge=Math.min(low,weights.length-1);
                while(edge<weights.length-1 && weights[edge]<=epsilon){edge++;}
                var w=weights[edge];
                if(w<=epsilon){return {lat:pts[edge+1].lat,lng:pts[edge+1].lng};}
                var local=Math.max(0,Math.min(1,(distance-cumulative[edge])/w));
                var start=pts[edge], end=pts[edge+1];
                return {
                  lat:start.lat+(end.lat-start.lat)*local,
                  lng:normalizedLng(start.lng+wrappedLngDelta(start.lng,end.lng)*local)
                };
              }
              var segments=[], interior=1;
              for(var segmentIndex=0;segmentIndex<count;segmentIndex++){
                var startDistance=total*segmentIndex/count;
                var endDistance=total*(segmentIndex+1)/count;
                var segmentPoints=[pointAt(startDistance)];
                while(interior<pts.length-1 && cumulative[interior]<=startDistance+epsilon){interior++;}
                while(interior<pts.length-1 && cumulative[interior]<endDistance-epsilon){
                  segmentPoints.push({lat:pts[interior].lat,lng:pts[interior].lng}); interior++;
                }
                segmentPoints.push(pointAt(endDistance));
                segments.push({
                  points:segmentPoints,
                  progress:(startDistance+endDistance)/(2*total)
                });
              }
              return segments;
            }
            function addEusoLine(grp,pts,spec){
              // One gradient ribbon only: no outline, backdrop, casing, or
              // route halo. State remains available in text and width.
              addSweepLine(grp,pts,spec.width);
            }
            function addSweepLine(grp, pts, width){
              var segments=eusoLineSegments(pts,72)||[];
              for(var i=0;i<segments.length;i++){
                var segment=segments[i];
                var ls = new H.geo.LineString();
                segment.points.forEach(function(p){ls.pushPoint({lat:p.lat,lng:p.lng});});
                var style = { lineWidth:width, strokeColor:sweepColor(segment.progress, 1),
                              lineCap:"round", lineJoin:"round" };
                grp.addObject(new H.map.Polyline(ls, { style:style }));
              }
            }

            // ── Geofence rings (§3c) ─────────────────────────────────────
            // Dashed circle fences, per-kind canon color/dash. railRamp gets
            // the fencePulse halo, pilotGround animates its dashoffset, and a
            // breach point gets the #F44336 EXIT node + exitPulse.
            var FENCES = {
              receiver:        { ring:"#F44336", ringA:0.85, w:1.6, dash:[6,5], fillA:0.08, fillHex:"#F44336" },
              railRamp:        { ring:"#00C48C", ringA:0.85, w:1.4, dash:[3,4], fillA:0.07, fillHex:"#00C48C" },
              pilotGround:     { ring:"#3FA9F5", ringA:0.65, w:1.4, dash:[5,5], fillA:0.05, fillHex:"#1473FF" },
              destinationPort: { ring:"#1473FF", ringA:0.55, w:1.6, dash:[4,5], fillA:0.0,  fillHex:"#1473FF" }
            };
            function addFence(grp, f){
              var spec = FENCES[f.kind] || FENCES.receiver;
              var ringStyle = { strokeColor:hexA(spec.ring, spec.ringA),
                                fillColor:hexA(spec.fillHex, spec.fillA),
                                lineWidth:spec.w, lineDash:spec.dash };
              var ring = new H.map.Circle({lat:f.lat,lng:f.lng}, f.radius, { style:ringStyle });
              grp.addObject(ring);
              if(f.kind==="pilotGround"){
                // 660: SpatialStyle.lineDashOffset was removed in Maps JS
                // 3.2. Keep the pilot fence alive with a supported opacity
                // pulse instead of silently assigning a dead property.
                fx.push(function(t){
                  var pulse = 0.62 + 0.28 * ((Math.sin(t*2.4)+1)/2);
                  ring.setStyle(new H.map.SpatialStyle({ strokeColor:ringStyle.strokeColor,
                    fillColor:hexA(spec.fillHex, pulse*0.18), lineWidth:spec.w,
                    lineDash:spec.dash }));
                });
              }
              if(f.kind==="railRamp"){
                // 003-rail fencePulse: a breathing #00C48C halo fading out.
                var halo = new H.map.Circle({lat:f.lat,lng:f.lng}, f.radius,
                  { style:{ strokeColor:"rgba(0,0,0,0)", fillColor:hexA("#00C48C",0.4), lineWidth:0 } });
                grp.addObject(halo);
                fx.push(function(t){
                  var ph = (t % 2.4) / 2.4;
                  halo.setRadius(f.radius * (1 + 0.3*ph));
                  halo.setStyle(new H.map.SpatialStyle({ strokeColor:"rgba(0,0,0,0)",
                    fillColor:hexA("#00C48C", 0.4*(1-ph)), lineWidth:0 }));
                });
              }
              if(typeof f.breachLat==="number" && typeof f.breachLng==="number"){
                // Breach/EXIT node riding the fence (536): #F44336 r5 disc,
                // white stroke 1.5, with the exitPulse halo behind it.
                var pulse = new H.map.Circle({lat:f.breachLat,lng:f.breachLng}, f.radius*0.08,
                  { style:{ strokeColor:"rgba(0,0,0,0)", fillColor:hexA("#F44336",0.55), lineWidth:0 } });
                grp.addObject(pulse);
                fx.push(function(t){
                  var ph = (t % 2.0) / 2.0;
                  pulse.setRadius(f.radius * (0.08 + 0.16*ph));
                  pulse.setStyle(new H.map.SpatialStyle({ strokeColor:"rgba(0,0,0,0)",
                    fillColor:hexA("#F44336", 0.55*(1-ph)), lineWidth:0 }));
                });
                var node = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">'
                  + '<circle cx="8" cy="8" r="5" fill="#F44336" stroke="#F5F5F7" stroke-width="1.5"/></svg>';
                try{ grp.addObject(new H.map.Marker({lat:f.breachLat,lng:f.breachLng},
                  { icon:new H.map.Icon(node, { anchor:{x:8,y:8} }) })); }catch(e){}
              }
            }

            // ── Canon marker grammar (§3) — NO teardrops ────────────────
            // Three families, mirroring BespokeMapCanvas.paintMarker:
            //  • endpoints — Truck gets the soft concentric route bloom from
            //    the authored mockups; Rail gets the exact larger 003 terminal
            //    shell; Vessel keeps a hollow 003 port ring with ring-only
            //    bloom. Active navigation never receives an automatic node.
            //  • live truck — the 013 ping: radial halo + white ring +
            //    eusoDiagonal r9 core.
            //  • add-on POIs — tinted disc r7 + white core, in the Brand
            //    accent set (the Tailwind set appears in ZERO wireframes).
            var EG = '<defs><linearGradient id="eg" x1="0" y1="0" x2="1" y2="0">'
              + '<stop offset="0" stop-color="#1473FF"/><stop offset="0.5" stop-color="#813FF5"/><stop offset="1" stop-color="#BE01FF"/>'
              + '</linearGradient></defs>';
            function xmlEsc(s){
              return String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");
            }
            function endpointMode(){
              var raw=String(styleConfiguration.productMode||styleConfiguration.transportMode||"").toLowerCase();
              if(raw.indexOf("vessel")>=0 || raw.indexOf("marine")>=0){return "vessel";}
              if(raw.indexOf("rail")>=0){return "rail";}
              return "truck";
            }
            function endpointBloomDefs(tint){
              return '<defs><radialGradient id="endpointBloom">'
                + '<stop offset="0" stop-color="'+tint+'" stop-opacity=".22"/>'
                + '<stop offset=".55" stop-color="'+tint+'" stop-opacity=".09"/>'
                + '<stop offset="1" stop-color="'+tint+'" stop-opacity="0"/>'
                + '</radialGradient></defs>';
            }
            function svgEndpoint(kind,mode,title){
              var isDestination=kind==="delivery";
              var dark=styleConfiguration.theme==="dark";
              var shell=mode==="rail" ? "#FFFFFF" : (dark ? "#0D0E1A" : "#FFFFFF");
              var tint=isDestination ? "#BE01FF" : "#1473FF";
              var safeTitle=xmlEsc(title||(isDestination?"Destination":"Origin"));
              if(mode==="vessel"){
                var ring=isDestination ? (dark?"#6E7681":"#8A96A3") : "url(#eg)";
                var bloom=isDestination ? (dark?"#6E7681":"#8A96A3") : "#1473FF";
                return '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">'
                  + '<title>'+safeTitle+'</title>'+EG
                  + '<circle cx="20" cy="20" r="13" fill="none" stroke="'+bloom+'" stroke-opacity=".12" stroke-width="5"/>'
                  + '<circle cx="20" cy="20" r="6.5" fill="none" stroke="'+ring+'" stroke-width="3"/></svg>';
              }
              var outer=mode==="rail" ? 7.5 : 6;
              var inner=mode==="rail" ? 5.5 : 4;
              var bloomRadius=mode==="rail" ? 15 : 16;
              var core=isDestination ? "#BE01FF" : "url(#eg)";
              return '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40" viewBox="0 0 40 40">'
                + '<title>'+safeTitle+'</title>'+EG+endpointBloomDefs(tint)
                + '<circle cx="20" cy="20" r="'+bloomRadius+'" fill="url(#endpointBloom)"/>'
                + '<circle cx="20" cy="20" r="'+outer+'" fill="'+shell+'" stroke="rgba(13,17,23,0.12)" stroke-width="1"/>'
                + '<circle cx="20" cy="20" r="'+inner+'" fill="'+core+'"/></svg>';
            }
            function stateDecoration(state){
              if(state==="stale"){
                return '<circle cx="24" cy="24" r="14" fill="none" stroke="#FFA726" stroke-width="2" stroke-dasharray="4 3"/>';
              }
              if(state==="degraded"){
                return '<circle cx="24" cy="24" r="14" fill="none" stroke="#F44336" stroke-width="2" stroke-dasharray="2 2"/>'
                  + '<path d="M15 15L33 33M33 15L15 33" stroke="#F44336" stroke-width="1.5" opacity=".82"/>';
              }
              if(state==="offline"){
                return '<circle cx="24" cy="24" r="14" fill="none" stroke="#607D8B" stroke-width="2"/>'
                  + '<path d="M14 34L34 14" stroke="#607D8B" stroke-width="3" stroke-linecap="round"/>';
              }
              return '<circle cx="24" cy="24" r="14" fill="none" stroke="#1473FF" stroke-width="1.4"/>';
            }
            function modeGlyph(kind,count){
              if(kind==="rail"){
                return '<path d="M24 14L33 20V29L24 34L15 29V20Z" fill="url(#eg)" stroke="#fff" stroke-width="1.3"/>'
                  + '<path d="M20 19V29M28 19V29M19 22H29M19 27H29" stroke="#fff" stroke-width="1.2"/>';
              }
              if(kind==="vessel"){
                return '<path d="M24 13L31 23L29 31Q24 35 19 31L17 23Z" fill="url(#eg)" stroke="#fff" stroke-width="1.3"/>'
                  + '<path d="M24 14V31M18 23H30" stroke="#fff" stroke-width="1.2"/>';
              }
              if(kind==="cluster"){
                return '<circle cx="24" cy="24" r="11" fill="url(#eg)" stroke="#fff" stroke-width="1.4"/>'
                  + '<text x="24" y="28" text-anchor="middle" font-size="10" font-weight="800" font-family="-apple-system,sans-serif" fill="#fff">'+xmlEsc(count||"2+")+'</text>';
              }
              return '<rect x="14" y="18" width="18" height="12" rx="4" fill="url(#eg)" stroke="#fff" stroke-width="1.3"/>'
                + '<path d="M18 18V15H27V18M18 30V33M29 30V33" stroke="#fff" stroke-width="1.5" stroke-linecap="round"/>';
            }
            function svgPuck(kind,state,title,count){
              return '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">'
                + '<title>'+xmlEsc(title||kind||"Live observation")+'</title>'
                + '<defs><radialGradient id="halo"><stop offset="0" stop-color="#1473FF" stop-opacity="0.55"/>'
                + '<stop offset="1" stop-color="#1473FF" stop-opacity="0"/></radialGradient>'
                + '<linearGradient id="eg" x1="0" y1="0" x2="1" y2="0">'
                + '<stop offset="0" stop-color="#1473FF"/><stop offset="0.5" stop-color="#813FF5"/><stop offset="1" stop-color="#BE01FF"/></linearGradient></defs>'
                + '<circle cx="24" cy="24" r="22" fill="url(#halo)"/>'
                + '<circle cx="24" cy="24" r="12" fill="rgba(255,255,255,.94)"/>'
                + modeGlyph(kind,count)
                + stateDecoration(state)
                + '</svg>';
            }
            function svgDisc(tint){
              return '<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 22 22">'
                + '<circle cx="11" cy="11" r="7" fill="'+tint+'" stroke="rgba(255,255,255,0.85)" stroke-width="1.4"/>'
                + '<circle cx="11" cy="11" r="3.5" fill="rgba(255,255,255,0.92)"/></svg>';
            }
            function isCoordinateLabel(label){
              return /^[-+]?\\d+(?:\\.\\d+)?,\\s*[-+]?\\d+(?:\\.\\d+)?$/.test(String(label));
            }
            function flagText(label){
              return isCoordinateLabel(label)
                ? String(label)
                : String(label).toUpperCase().slice(0,28);
            }
            function flagWidth(label){
              var raw = flagText(label);
              return Math.min(240, Math.max(46, Math.round(raw.length*6.2)+20));
            }
            function svgFlag(label){
              var raw = flagText(label);
              var text = xmlEsc(raw);
              var w = flagWidth(label);
              var cx = w/2;
              var dark = styleConfiguration.theme==="dark";
              var fill = dark ? "rgba(13,14,26,0.88)" : "rgba(255,255,255,0.82)";
              var border = dark ? "rgba(255,255,255,0.12)" : "rgba(13,17,23,0.12)";
              var ink = dark ? "#F5F5F7" : "#0D1117";
              var fit = raw.length*6.2 > w-16
                ? ' textLength="'+(w-16)+'" lengthAdjust="spacingAndGlyphs"'
                : '';
              return '<svg xmlns="http://www.w3.org/2000/svg" width="'+w+'" height="56" viewBox="0 0 '+w+' 56">' + EG
                + endpointBloomDefs("#BE01FF")+'<title>'+text+'</title>'
                + '<rect x="1" y="1" width="'+(w-2)+'" height="22" rx="11" fill="'+fill+'" stroke="'+border+'" stroke-width="1"/>'
                + '<text x="'+cx+'" y="15.5" font-size="9" font-weight="700" letter-spacing="0.4" font-family="ui-monospace,Menlo,monospace" text-anchor="middle" fill="'+ink+'"'+fit+'>'+text+'</text>'
                + '<circle cx="'+cx+'" cy="40" r="15" fill="url(#endpointBloom)"/>'
                + '<rect x="'+(cx-6)+'" y="34" width="12" height="12" rx="2" fill="url(#eg)" transform="rotate(-45 '+cx+' 40)"/>'
                + '</svg>';
            }
            // Canon Brand accents for POI discs (§3d) — keep in lockstep
            // with HereMarkerStyle.color (HereAddOns.swift).
            var POI = {
              stop:"#607D8B", fuel:"#E8731C", charger:"#00C48C", parking:"#2196F3",
              alert:"#F44336", weather:"#2196F3", mission:"#9C27B0", adZone:"#9C27B0",
              truckStop:"#E8731C", weigh:"#607D8B", camera:"#FFA726", hotZone:"#FF7A00"
            };
            var ICONS = {};
            function iconFor(kind, label, state, accessibilityLabel, clusterCount){
              var mode=endpointMode();
              var title=accessibilityLabel||label||kind||"Map marker";
              var key = kind+":"+(state||"current")+":"+(clusterCount||0)+":"+mode+":"+styleConfiguration.theme+":"+title, svg, anchor;
              if(kind==="delivery" && label && mode==="truck"){
                key = "flag:"+styleConfiguration.theme+":"+label;
                if(ICONS[key]) return ICONS[key];
                svg = svgFlag(label);
                var w = flagWidth(label);
                anchor = { x:w/2, y:40 };   // the diamond marks the geo point
              } else {
                if(ICONS[key]) return ICONS[key];
                if(kind==="truck" || kind==="rail" || kind==="vessel" || kind==="cluster"){
                  svg = svgPuck(kind,state,accessibilityLabel||label,clusterCount);
                  anchor = {x:24,y:24};
                }
                else if(kind==="pickup" || kind==="delivery"){
                  svg = svgEndpoint(kind,mode,title); anchor = {x:20,y:20};
                }
                else { svg = svgDisc(POI[kind]||"#1473FF"); anchor = {x:11,y:11}; }
              }
              try{ var ic = new H.map.Icon(svg, { anchor:anchor }); ICONS[key]=ic; return ic; }
              catch(e){ return null; }
            }

            window.addEventListener("beforeunload", function(){
              stopFx();
              try{ if(pendingSelection){ pendingSelection.dispose(); pendingSelection=null; } }catch(e){}
              try{ if(currentSelection){ currentSelection.dispose(); currentSelection=null; } }catch(e){}
              try{ if(map && map.dispose){ map.dispose(); } }catch(e){}
            });
            try{ window.webkit.messageHandlers.mapReady.postMessage("ok"); }catch(e){}
          }catch(err){ showError(); log("init "+err); }
        })();
        </script></body></html>
        """
    }
}
#endif
