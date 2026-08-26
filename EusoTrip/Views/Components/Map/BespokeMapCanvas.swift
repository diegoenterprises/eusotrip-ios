//
//  BespokeMapCanvas.swift
//  EusoTrip — the in-house SwiftUI Canvas map renderer.
//
//  This is the DROP-IN replacement for the WKWebView `HereMapWebViewRepresentable`.
//  It paints the bespoke SVG cartography (light + dark + cosmos + lightDriver)
//  VERBATIM and draws the real route / markers / heatmap / ad-zone polygons over
//  it, using ONLY SwiftUI — NO WKWebView, NO MapKit, NO CoreLocation types.
//
//  It reads the typed cartography tokens from `BespokeMapStyle` (the single
//  source of truth for every color / width / radius / dash / gradient), projects
//  geo → screen with `BespokeMapViewport` (Web-Mercator, fit-to-route or fixed
//  camera), and consumes the canonical `[HereMapLayer]` data contract
//  (HereMapWebView.swift) so it can be swapped in anywhere `HereVectorMapView`
//  is used today.
//
//  Public entry signature is IDENTICAL to the representable it replaces:
//      (center:HereLatLng, zoom:Int, interactive:Bool, tilt:Double,
//       isDark:Bool, layers:[HereMapLayer], onSelectMarker:((String)->Void)?)
//
//  Register selection (VERBATIM): a forward-tilt / first-person camera
//  (`tilt > 0`) is the driver "Active Enroute" surface → `.cosmos` (dark) /
//  `.lightDriver` (light). Everything else is a flat shipper / catalyst board →
//  `.dark` / `.light`.
//
//  PERFORMANCE MODEL (2026-06-05 freeze/crash fix)
//  ───────────────────────────────────────────────
//  The whole scene's screen-space geometry is precomputed ONCE into a cached
//  `RenderModel` whenever (layers, base viewport, register) change — keyed by a
//  cheap hash. The per-frame `Canvas` draw closure then just rasterizes that
//  already-projected geometry; it NEVER re-projects continents, re-flattens the
//  route, or re-runs Catmull-Rom smoothing. Concretely the precompute:
//    • projects + caches the continent basemap rings (culled to the viewport),
//    • simplifies the route polyline (Douglas–Peucker to ~canvas pixel res,
//      hard-capped) BEFORE Catmull-Rom smoothing, so a 2000-pt HERE route never
//      spawns 2000 Bézier segments,
//    • culls markers + labels to the visible bounds (+ margin) with a HARD CAP,
//    • caches the route gradient endpoints, endpoint pins, heatmap blobs, and
//      ad-zone polygons in screen space.
//  Live pan/zoom (`liveDrag` / `liveZoom`) apply a CHEAP affine to the cached
//  base scene inside the draw closure — they do NOT rebuild the model. Only when
//  a gesture COMMITS (onEnded → panOffset/zoomDelta) does the model recompute,
//  exactly once.
//
//  Draw order (matches the SVG ground truth + the JS __applyLayers z-order):
//    1. background  (linear vertical gradient, or radial cosmos)
//    2. faint grid  (straight authored lines at fixed spacing — no warp)
//    3. layered horizon silhouettes (abstract — NOT real streets)
//    4. per layer:  heatmap → adZones → traffic-flow ribbons → route
//                   (active + pending) → geofence rings (+ breach node) →
//                   endpoints (origin / dest) → live puck (truck OR ping)
//    5. callout pills (authored marker labels + a computed scale pill)
//
//  Powered by ESANG AI™.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Style hint

/// Optional cartography-register hint a caller passes to `BespokeMapCanvas`.
///
/// `.auto` (the default) preserves the historical behavior: a forward-tilt /
/// first-person camera resolves to the driver "Active Enroute" register and
/// everything else to the flat shipper / catalyst board. `.ocean` forces the
/// Vessel 003 "Live Tracking" ocean register (`.ocean` dark /
/// `.lightOcean` light) — the AIS orb, port pins, latitude grid, coast hints,
/// and the speed/heading/coords callout chip. `.rail` forces the Rail 003
/// hero registers (`.darkRail` / `.lightRail` — topology-bound EusoLine).
/// `.nav` forces the driver turn-by-turn register (035/116 — one uncased w9
/// gradient ribbon, road ribbons, maneuver node, heading-arrow puck).
/// `.portApproach` forces the Vessel 660 port-approach chart (deep navy in
/// BOTH modes — #15233A landmass, history wake, container-vessel AIS hull).
/// `.geothermal` forces the Hot Zones thermal register: a CONTINUOUS
/// blue→red geothermal field (inverse-distance-weighted from the live
/// `.heatmap` load-to-truck ratios) painted UNDER the route, replacing the
/// legacy 3-band demand blobs. A land board otherwise (states / cities /
/// corridors still render beneath the field).
public enum BespokeMapStyleHint: Hashable {
    case auto
    case ocean
    case rail
    case nav
    case portApproach
    case geothermal
}

// MARK: - Public entry (drop-in for HereMapWebViewRepresentable)

/// In-house native map. Constructs a `BespokeMapStyle` from `isDark` + `tilt`
/// (forward tilt ⇒ the driver cosmos register), projects with
/// `BespokeMapViewport`, and paints everything in a single `Canvas`.
public struct BespokeMapCanvas: View {
    let center: HereLatLng
    let zoom: Int
    let interactive: Bool
    let tilt: Double
    let isDark: Bool
    let layers: [HereMapLayer]
    let style: BespokeMapStyleHint
    let onSelectMarker: ((String) -> Void)?

    /// Backward-compatible: the original 7-arg signature is preserved verbatim
    /// (every existing caller compiles unchanged) and routes to the hinted
    /// initializer with `style: .auto`.
    public init(
        center: HereLatLng,
        zoom: Int = 6,
        interactive: Bool = true,
        tilt: Double = 0,
        isDark: Bool = false,
        layers: [HereMapLayer] = [],
        onSelectMarker: ((String) -> Void)? = nil
    ) {
        self.init(
            center: center,
            zoom: zoom,
            interactive: interactive,
            tilt: tilt,
            isDark: isDark,
            layers: layers,
            style: .auto,
            onSelectMarker: onSelectMarker
        )
    }

    /// Hinted initializer: pass `style: .ocean` for the Vessel 003 ocean
    /// register. `style:` carries no default here so it never shadows the
    /// 7-arg overload above (which IS the backward-compatible default path).
    public init(
        center: HereLatLng,
        zoom: Int = 6,
        interactive: Bool = true,
        tilt: Double = 0,
        isDark: Bool = false,
        layers: [HereMapLayer] = [],
        style: BespokeMapStyleHint,
        onSelectMarker: ((String) -> Void)? = nil
    ) {
        self.center = center
        self.zoom = zoom
        self.interactive = interactive
        self.tilt = tilt
        self.isDark = isDark
        self.layers = layers
        self.style = style
        self.onSelectMarker = onSelectMarker
    }

    // Live interaction state — pan offset (points) + pinch scale (zoom delta).
    @State private var panOffset: CGSize = .zero
    @State private var liveDrag: CGSize = .zero
    @State private var zoomDelta: Double = 0
    @State private var liveZoom: Double = 0

    // Canon motion (puck pulse / route flow) honors the system setting — the
    // TimelineView pauses and the painters fall back to the authored statics.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Precomputed scene — the projected, simplified, culled geometry that the
    // per-frame draw closure rasterizes. Rebuilt ONLY when the cache key flips
    // (layers / committed camera / register / size change), never per frame.
    @State private var model: RenderModel = .empty
    @State private var modelKey: Int = .min

    public var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let style = resolvedStyle
            // The committed (non-gesture) viewport. Live pan/zoom is folded in
            // at DRAW time as a cheap affine — NOT by re-fitting here.
            let baseViewport = makeBaseViewport(size: size)
            let key = Self.cacheKey(layers: layers, viewport: baseViewport,
                                    isOcean: Self.isOcean(style), hint: self.style)
            // Canon motion shell (same 30fps TimelineView discipline as
            // EquipmentAnimation): drives the 2.2s/2.4s puck pulse + the 1.4s
            // route-flow dash offset. Paused — one static frame — whenever
            // reduce-motion is on or the scene carries no live motion, so a
            // static board never burns frames.
            let motionPaused = reduceMotion || !model.hasLiveMotion

            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: motionPaused)) { timeline in
                    Canvas { context, canvasSize in
                        // Apply the live-gesture affine (pan + pinch) about the
                        // canvas center to the cached base scene. Committed pan/zoom
                        // is already baked into `baseViewport`/`model`; only the
                        // in-flight delta is applied here so a drag/pinch costs one
                        // matrix concat, not a full re-projection.
                        if liveDrag != .zero || liveZoom != 0 {
                            let s = pow(2.0, liveZoom)
                            let cx = canvasSize.width / 2
                            let cy = canvasSize.height / 2
                            context.translateBy(x: liveDrag.width, y: liveDrag.height)
                            context.translateBy(x: cx, y: cy)
                            context.scaleBy(x: CGFloat(s), y: CGFloat(s))
                            context.translateBy(x: -cx, y: -cy)
                        }
                        let phase = motionPaused ? PulsePhase.still : Self.pulsePhase(at: timeline.date)
                        Self.paint(context: &context, size: canvasSize, model: model, phase: phase)
                    }
                    .background(Color.clear)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            // Container is square in EVERY register (full-bleed map band):
            // square corners (Rectangle clip), no border. No rounded clip.
            .clipShape(Rectangle())
            .gesture(interactive ? combinedGesture(size: size) : nil)
            .onTapGesture { location in
                handleTap(at: location, viewport: baseViewport)
            }
            // Build the cached scene once per key change. `onChange(of:key)`
            // fires on first appearance too (initial key != sentinel) and on
            // every layers/camera/register/size flip — but NOT per frame.
            .onAppear {
                rebuildIfNeeded(key: key, size: size, style: style, viewport: baseViewport)
            }
            .onChange(of: key) { _, newKey in
                rebuildIfNeeded(key: newKey, size: size, style: style, viewport: baseViewport)
            }
        }
        // 2026-06-03 — intrinsic minimum height so no parent can collapse the
        // engine to zero size (the frame.zero blank-map trap) for ANY caller.
        .frame(minHeight: 160)
    }

    /// Recompute the cached `RenderModel` when (and only when) the cache key
    /// changes. Pure + value-typed inputs; the heavy projection / simplify /
    /// cull pass runs here, off the per-frame path.
    private func rebuildIfNeeded(
        key: Int,
        size: CGSize,
        style: BespokeMapStyle,
        viewport: BespokeMapViewport
    ) {
        guard key != modelKey else { return }
        modelKey = key
        model = RenderModel.build(size: size, style: style, viewport: viewport,
                                  layers: layers, hint: self.style)
    }

    // MARK: Style resolution

    /// Picks the cartography register VERBATIM:
    ///   tilt > 0  (forward / first-person camera) ⇒ driver "Active Enroute"
    ///             → `.cosmos` (dark) / `.lightDriver` (light)
    ///   otherwise ⇒ flat shipper / catalyst board → `.dark` / `.light`.
    private var resolvedStyle: BespokeMapStyle {
        // Explicit register hints win over the tilt heuristic — each of these
        // surfaces is selected deliberately by its screen, never inferred.
        switch style {
        case .ocean:        return BespokeMapStyle.ocean(isDark: isDark)
        case .rail:         return BespokeMapStyle.rail(isDark: isDark)
        case .nav:          return BespokeMapStyle.nav(isDark: isDark)
        case .portApproach: return BespokeMapStyle.portApproach
        // Geothermal = a flat shipper/catalyst land board with the continuous
        // thermal field painted over it; resolve to the standard board register
        // (falls through with .auto), the field is layered in paint().
        case .geothermal:   break
        case .auto:         break
        }
        if tilt > 0 {
            return BespokeMapStyle.driver(isDark: isDark)
        }
        return BespokeMapStyle.standard(isDark: isDark)
    }

    /// The ocean register is uniquely identified by its hollow port-pin ring.
    static func isOcean(_ style: BespokeMapStyle) -> Bool {
        style.originMarker.ringStroke != nil
    }

    // MARK: Viewport

    /// The COMMITTED camera (no in-flight gesture delta). Fit to the route when
    /// one exists (so the whole lane is framed), else the fixed center + zoom
    /// camera, with any COMMITTED pan/zoom folded in. Live pan/zoom is applied
    /// later as a cheap draw-time affine, so this is recomputed only when the
    /// committed camera actually moves — not on every gesture frame.
    private func makeBaseViewport(size: CGSize) -> BespokeMapViewport {
        let routeCoords = Self.allRouteCoords(layers)
        let base: BespokeMapViewport
        if let fitted = BespokeMapViewport(
            fitting: routeCoords,
            size: size,
            padding: 48,
            minZoom: 1,
            maxZoom: 16
        ) {
            base = fitted
        } else {
            base = BespokeMapViewport(center: center, zoom: zoom, size: size)
        }

        let effZoom = base.zoom + zoomDelta
        if panOffset == .zero && effZoom == base.zoom {
            return base
        }
        // Apply committed zoom first (about center), then committed pan by
        // converting the panned screen-center back to a geo coordinate.
        let zoomed = BespokeMapViewport(center: base.center, fractionalZoom: effZoom, size: size)
        guard panOffset != .zero else { return zoomed }
        let centerPt = CGPoint(x: size.width / 2 - panOffset.width,
                               y: size.height / 2 - panOffset.height)
        let newCenter = zoomed.coordinate(centerPt)
        return BespokeMapViewport(center: newCenter, fractionalZoom: effZoom, size: size)
    }

    /// A cheap, collision-resistant cache key over the inputs that change the
    /// projected scene: the layer data, the committed viewport, the register
    /// hint, and whether the ocean register is active. Hashes the viewport's
    /// center/zoom/size so a new camera invalidates the cache; hashes `layers`
    /// (Hashable) so new route / marker data does too.
    static func cacheKey(
        layers: [HereMapLayer],
        viewport: BespokeMapViewport,
        isOcean: Bool,
        hint: BespokeMapStyleHint = .auto
    ) -> Int {
        var h = Hasher()
        h.combine(layers)
        h.combine(viewport.center.lat)
        h.combine(viewport.center.lng)
        h.combine(viewport.zoom)
        h.combine(viewport.size.width)
        h.combine(viewport.size.height)
        h.combine(isOcean)
        h.combine(hint)
        return h.finalize()
    }

    // MARK: Gestures

    private func combinedGesture(size: CGSize) -> some Gesture {
        let drag = DragGesture(minimumDistance: 4)
            .onChanged { value in liveDrag = value.translation }
            .onEnded { value in
                panOffset = CGSize(width: panOffset.width + value.translation.width,
                                   height: panOffset.height + value.translation.height)
                liveDrag = .zero
            }
        let magnify = MagnificationGesture()
            .onChanged { scale in liveZoom = log2(Swift.max(0.1, Double(scale))) }
            .onEnded { scale in
                zoomDelta += log2(Swift.max(0.1, Double(scale)))
                zoomDelta = Swift.min(8, Swift.max(-6, zoomDelta))
                liveZoom = 0
            }
        return drag.simultaneously(with: magnify)
    }

    // MARK: Tap hit-testing → onSelectMarker

    private func handleTap(at location: CGPoint, viewport: BespokeMapViewport) {
        guard let cb = onSelectMarker else { return }
        let candidates = Self.allTappableMarkers(layers)
        var bestID: String?
        var bestDist = CGFloat.greatestFiniteMagnitude
        let hitRadius: CGFloat = 26
        for m in candidates {
            guard let id = Self.stableID(for: m) else { continue }
            let p = viewport.screenPoint(m.at)
            let d = hypot(p.x - location.x, p.y - location.y)
            if d < hitRadius && d < bestDist {
                bestDist = d
                bestID = id
            }
        }
        if let id = bestID { cb(id) }
    }

    // MARK: - Layer extraction helpers (static, pure)

    static func allRouteCoords(_ layers: [HereMapLayer]) -> [HereLatLng] {
        var out: [HereLatLng] = []
        for layer in layers {
            switch layer {
            case .route(let poly, _), .eusoRoute(let poly, _, _),
                 .observationTrail(let poly, _):
                out.append(contentsOf: poly)
            default:
                break
            }
        }
        return out
    }

    static func allTappableMarkers(_ layers: [HereMapLayer]) -> [HereMarker] {
        var out: [HereMarker] = []
        for layer in layers {
            switch layer {
            case .markers(let ms), .missionPins(let ms): out.append(contentsOf: ms)
            default: break
            }
        }
        return out
    }

    static func stableID(for m: HereMarker) -> String? {
        if let id = m.id, !id.isEmpty { return id }
        return "\(m.kind.rawValue):\(m.at.lat),\(m.at.lng)"
    }

    /// Observation coordinate helper retained for marker camera work. It must
    /// never be used to infer route completion or traveled progress.
    static func liveMarkerCoord(_ layers: [HereMapLayer]) -> HereLatLng? {
        for layer in layers {
            switch layer {
            case .markers(let ms), .missionPins(let ms):
                if let asset = ms.first(where: { [.truck, .rail, .vessel].contains($0.kind) }) {
                    return asset.at
                }
            default: break
            }
        }
        return nil
    }

}

// MARK: - Precomputed render model

extension BespokeMapCanvas {

    /// The fully projected, simplified, culled scene the per-frame draw closure
    /// rasterizes. Built ONCE per cache-key change (`RenderModel.build`), never
    /// per frame. Everything here is already in SCREEN space for the committed
    /// (base) viewport; live pan/zoom is applied as a draw-time affine.
    struct RenderModel {
        // Chrome (background / grid / silhouettes) is re-emitted from the
        // captured style each draw — it is cheap (a handful of strokes / fills)
        // and must track the canvas rect, so we keep the style + flags only.
        var size: CGSize = .zero
        var style: BespokeMapStyle = .standard(isDark: false)
        var isOcean: Bool = false
        var isDriverGrid: Bool = false
        // Register flags resolved from the caller's style hint: the nav
        // register swaps the grid/ribbon grammar (035), the port-approach
        // register swaps the basemap + grid grammar (660).
        var isNav: Bool = false
        var isPortApproach: Bool = false
        // Geothermal register (Hot Zones): the heatmap renders as ONE
        // continuous IDW thermal field (geoField) instead of the legacy
        // 3-band demand blobs.
        var isGeothermal: Bool = false
        // Dark-backdrop register (white-tinted grid) — picks the §2/§3c dark
        // fence + traffic opacities, same probe as the basemap land wash.
        var isDarkRegister: Bool = false
        // Whether the scene carries renderer-driven motion (puck pulse /
        // route flow) — used to pause the TimelineView when there is nothing
        // to animate, so static boards never burn frames.
        var hasLiveMotion: Bool = false

        // Basemap — projected continent rings (screen space), pre-culled to the
        // viewport, with their derived land + coast colors.
        var basemapRings: [[CGPoint]] = []
        var landColor: Color = .clear
        var coastColor: Color = .clear
        var coastWidth: CGFloat = 0.9

        // Geographic context (§1b, land registers only) — projected ONCE in
        // build, culled to the viewport, zoom-gated. State/province + national
        // borders as screen-space ring polylines, interstate freight corridors
        // as screen-space polylines, and the rank-tagged metro labels.
        var stateBorders: [[CGPoint]] = []
        var nationalBorders: [[CGPoint]] = []
        var corridors: [[CGPoint]] = []
        var placeLabels: [(at: CGPoint, text: String, rank: Int)] = []

        // Heatmap blobs (screen-space centers + weights), pre-culled.
        var heatBlobs: [(center: CGPoint, weight: Double)] = []

        // Geothermal field (§4a, .geothermal register) — ONE prebuilt CGImage
        // of the IDW thermal field, drawn scaled to the view rect under the
        // route. nil when not geothermal or no live heat points.
        var geoField: CGImage? = nil
        var geoFieldRect: CGRect = .zero

        // Ad-zone polygons (screen space) + their fill.
        var adZones: [(pts: [CGPoint], fill: Color, opacity: Double)] = []

        struct RouteMember {
            let points: [CGPoint]
            /// Exact caller-owned canonical `.eusoRoute` state.
            let state: HereRouteVisualState
        }

        // Each LineString member remains independent. The renderer never
        // concatenates MultiLineString members or bridges an invalid point.
        var routeMembers: [RouteMember] = []
        var hasRoute: Bool { !routeMembers.isEmpty }

        // Geofence rings (§3c) — screen-space center + POINT radius (meters
        // projected through the committed camera) + kind, with the optional
        // breach/EXIT node pre-projected onto the rim.
        var fences: [(center: CGPoint, radius: CGFloat, kind: HereGeofenceKind, breach: CGPoint?)] = []

        // Traffic-flow ribbons (§2, 536) — pre-smoothed screen Paths + severity.
        var traffic: [(path: Path, severity: HereTrafficSegment.Severity)] = []

        // Endpoint pins (origin / dest) — screen-space anchors.
        var endpoints: [(at: CGPoint, marker: BespokeMapStyle.EndpointMarker)] = []

        // Generic markers (truck/ping/pickup/delivery/branded) — culled + capped.
        var markers: [(at: CGPoint, kind: HereMarker.Kind)] = []

        // Label pills — anchor + text (measured lazily in-draw with a cache).
        var labels: [(anchor: CGPoint, text: String)] = []

        // Scale pill payload (driver registers only).
        var scalePillText: String? = nil

        static let empty = RenderModel()

        /// The heavy precompute. Pure + deterministic given its value inputs.
        /// Projects continents, preserves canonical route vertices, culls + caps
        /// markers / labels, and resolves the scale pill text — once.
        static func build(
            size: CGSize,
            style: BespokeMapStyle,
            viewport: BespokeMapViewport,
            layers: [HereMapLayer],
            hint: BespokeMapStyleHint = .auto
        ) -> RenderModel {
            var m = RenderModel()
            m.size = size
            m.style = style
            m.isOcean = BespokeMapCanvas.isOcean(style)
            m.isDriverGrid = style.ping != nil
            m.isNav = hint == .nav
            m.isPortApproach = hint == .portApproach
            m.isGeothermal = hint == .geothermal
            m.isDarkRegister = BespokeMapCanvas.gridIsLight(style.grid.color)
            let rect = CGRect(origin: .zero, size: size)

            // ── 1b — basemap (skipped on the open-water ocean register) ──
            if !m.isOcean {
                if m.isPortApproach {
                    // 660 chart: landmass #15233A, coastline #27406A w1.3.
                    m.landColor = Color(hex: 0x15233A)
                    m.coastColor = Color(hex: 0x27406A)
                    m.coastWidth = 1.3
                } else if BespokeMapCanvas.gridIsLight(style.grid.color) {
                    // Driver surfaces (013 ping / 035 nav puck) take the
                    // fainter land wash; boards take the fuller one.
                    let isDriverSurface = style.ping != nil || style.truckMarker?.glyph == .navArrow
                    let a = isDriverSurface ? 0.10 : 0.16
                    m.landColor = Color.white.opacity(a)
                    m.coastColor = Color.white.opacity(a + 0.14)
                } else {
                    m.landColor = Color.black.opacity(0.05)
                    m.coastColor = Color.black.opacity(0.12)
                }
                let cullRect = rect.insetBy(dx: -160, dy: -160)
                for ring in BespokeMapBasemap.continents {
                    guard ring.count > 2 else { continue }
                    let pts = ring.map { viewport.screenPoint(HereLatLng($0.lat, $0.lng)) }
                    let bb = BespokeMapCanvas.boundingBox(pts)
                    guard bb.intersects(cullRect) else { continue }
                    m.basemapRings.append(pts)
                }

                // ── 1c — REAL geographic context (FEATURE 1). Projected ONCE
                //    through the committed camera (so it's cached + culled),
                //    zoom-gated so a CONUS framing shows nation outline + a few
                //    primary metros while a route/metro framing reveals states,
                //    cities, and freight corridors. Off the open-water ocean
                //    register (handled by !isOcean above). ──
                m.buildGeography(viewport: viewport, rect: rect)
            }

            // ── 4a — heatmap (cull off-screen blobs) ──
            let heatCull = rect.insetBy(dx: -120, dy: -120)
            for layer in layers {
                if case .heatmap(let pts) = layer {
                    for p in pts {
                        let c = viewport.screenPoint(p)
                        guard heatCull.contains(c) else { continue }
                        m.heatBlobs.append((c, p.weight ?? 1.0))
                    }
                }
            }

            // ── 4a2 — geothermal field (FEATURE 2). On the .geothermal
            //    register the heat points are rasterized ONCE into a single
            //    inverse-distance-weighted thermal field CGImage (blue cold →
            //    red hot), drawn scaled under the route in paint(). ZERO
            //    fabrication — built only when real heat points exist. ──
            if m.isGeothermal && !m.heatBlobs.isEmpty {
                m.geoFieldRect = rect
                m.geoField = BespokeMapCanvas.geothermalField(blobs: m.heatBlobs, rect: rect)
            }

            // ── 4b — ad-zones ──
            for layer in layers {
                if case .adZones(let polys) = layer {
                    for poly in polys {
                        guard poly.ring.count > 2 else { continue }
                        let pts = poly.ring.map { viewport.screenPoint($0) }
                        m.adZones.append((pts, Color(hex: poly.fillHex), poly.opacity))
                    }
                }
            }

            // ── 4b2 — traffic-flow ribbons (project + simplify once, cull) ──
            let trafficCull = rect.insetBy(dx: -120, dy: -120)
            for layer in layers {
                if case .trafficFlow(let segs) = layer {
                    for seg in segs where seg.polyline.count >= 2 {
                        let pts = seg.polyline.map { viewport.screenPoint($0) }
                        guard BespokeMapCanvas.boundingBox(pts).intersects(trafficCull) else { continue }
                        let simplified = BespokeMapCanvas.simplify(
                            pts, tolerance: 1.5, cap: BespokeMapCanvas.maxRoutePoints)
                        m.traffic.append((BespokeMapCanvas.smoothPath(simplified), seg.severity))
                    }
                }
            }

            // ── 4c — route (validate → simplify, once) ──
            // Route state is caller-owned server truth. Raw position evidence
            // never authorizes a traveled/remaining split. Legacy `.route`
            // geometry fails closed: a flat/static provider line is not a
            // second route grammar and cannot be promoted by this renderer.
            for layer in layers {
                switch layer {
                case .route:
                    break
                case .eusoRoute(let poly, let state, _):
                    guard m.buildRoute(
                        poly: poly,
                        state: state,
                        viewport: viewport
                    ) else { continue }
                    m.endpoints.append((viewport.screenPoint(poly.first!), style.originMarker))
                    m.endpoints.append((viewport.screenPoint(poly.last!), style.destMarker))
                default:
                    break
                }
            }

            // ── 4c2 — geofence rings (§3c). The fence radius arrives in
            //    METERS and is projected to points through the committed
            //    camera's Web-Mercator ground resolution (`metersPerPoint`),
            //    so the ring tracks real-world scale across zoom levels —
            //    same rule as the scale pill. ──
            let fenceCull = rect.insetBy(dx: -160, dy: -160)
            let mpp = Swift.max(viewport.metersPerPoint, 0.000_1)
            for layer in layers {
                if case .geofenceRing(let fc, let radiusMeters, let kind, let breach) = layer {
                    let c = viewport.screenPoint(fc)
                    let r = Swift.max(1, CGFloat(radiusMeters / mpp))
                    let bb = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                    guard bb.intersects(fenceCull) else { continue }
                    m.fences.append((c, r, kind, breach.map { viewport.screenPoint($0) }))
                }
            }

            // ── 4e — generic markers (CULL to visible bounds + HARD CAP) ──
            let markerCull = rect.insetBy(dx: -BespokeMapCanvas.markerCullMargin,
                                          dy: -BespokeMapCanvas.markerCullMargin)
            var painted = 0
            outer: for layer in layers {
                switch layer {
                case .markers(let ms), .missionPins(let ms):
                    for mk in ms {
                        if painted >= BespokeMapCanvas.maxVisibleMarkers { break outer }
                        let c = viewport.screenPoint(mk.at)
                        guard markerCull.contains(c) else { continue }
                        m.markers.append((c, mk.kind))
                        painted += 1
                    }
                default: break
                }
            }

            // ── 5 — label pills (CULL + HARD CAP; dedupe by rounded coord) ──
            var labelled = Set<String>()
            var labelCount = 0
            var hasAuthoredLabels = false
            let labelCull = rect.insetBy(dx: -BespokeMapCanvas.labelCullMargin,
                                         dy: -BespokeMapCanvas.labelCullMargin)
            labels: for layer in layers {
                switch layer {
                case .markers(let ms), .missionPins(let ms):
                    for mk in ms {
                        guard let label = mk.label, !label.isEmpty else { continue }
                        hasAuthoredLabels = true
                        if labelCount >= BespokeMapCanvas.maxVisibleLabels { break labels }
                        let anchor = viewport.screenPoint(mk.at)
                        labelled.insert(BespokeMapCanvas.coordKey(mk.at))
                        guard labelCull.contains(anchor) else { continue }
                        m.labels.append((anchor, label))
                        labelCount += 1
                    }
                default: break
                }
            }
            // Endpoint coordinate fallback only when the caller supplied no
            // authored place labels at all. If pickup/delivery labels exist,
            // city/state/street must win and raw coordinate pills must not
            // appear beside a real freight lane.
            if !hasAuthoredLabels {
                for layer in layers {
                    let poly: [HereLatLng]?
                    switch layer {
                    case .eusoRoute(let points, _, _): poly = points
                    default: poly = nil
                    }
                    if let poly, let first = poly.first, let last = poly.last {
                        if labelCount < BespokeMapCanvas.maxVisibleLabels,
                           !labelled.contains(BespokeMapCanvas.coordKey(first)) {
                            let a = viewport.screenPoint(first)
                            if labelCull.contains(a) {
                                m.labels.append((a, BespokeMapCanvas.coordText(first)))
                                labelCount += 1
                            }
                        }
                        if labelCount < BespokeMapCanvas.maxVisibleLabels,
                           !labelled.contains(BespokeMapCanvas.coordKey(last)) {
                            let a = viewport.screenPoint(last)
                            if labelCull.contains(a) {
                                m.labels.append((a, BespokeMapCanvas.coordText(last)))
                                labelCount += 1
                            }
                        }
                    }
                }
            }

            // ── 5b — scale pill (driver registers only) ──
            if style.pill.scalePillEnabled {
                let barPoints: CGFloat = 64
                let meters = viewport.metersPerPoint * Double(barPoints)
                let miles = meters / 1609.344
                let nice = BespokeMapCanvas.niceScale(miles)
                m.scalePillText = "\(BespokeMapCanvas.trimmed(nice)) MI"
            }

            // ── motion eligibility — a live puck pulses; a board route
            //    carries the 222 flow overlay; an animated fence (the
            //    pilot-ground dash march, the rail-ramp fencePulse, any
            //    breach exitPulse) keeps the timeline running even on an
            //    otherwise static board. Anything else stays static and
            //    pauses the TimelineView entirely. ──
            let hasLivePuck = m.markers.contains { $0.kind == .truck }
            let fenceMotion = m.fences.contains {
                $0.kind == .pilotGround || $0.kind == .railRamp || $0.breach != nil
            }
            m.hasLiveMotion = hasLivePuck || fenceMotion

            return m
        }

        /// Preserve one validated LineString member as its own screen-space
        /// path. Invalid members fail closed; they are never repaired by
        /// dropping a point and joining the coordinates around it.
        @discardableResult
        mutating func buildRoute(
            poly: [HereLatLng],
            state: HereRouteVisualState,
            viewport: BespokeMapViewport
        ) -> Bool {
            guard poly.count >= 2, poly.allSatisfy(\.isUsableCoordinate) else { return false }
            // Project exact canonical geometry once. It is evidence, so the
            // renderer neither simplifies nor repairs its coordinates.
            let projected = poly.map { viewport.screenPoint($0) }
            guard projected.count >= 2 else { return false }
            routeMembers.append(
                .init(
                    points: projected,
                    state: state
                )
            )
            return true
        }

        /// FEATURE 1 — project the real geographic context (state / province +
        /// national borders, interstate freight corridors, metro labels) into
        /// screen space ONCE, culled to the viewport and zoom-gated. Mirrors the
        /// continents-loop projection + cull (so it's cached, never per-frame).
        /// Mutates `self`. The thresholds are tuned so a continental framing
        /// reads as nation outline + a handful of primary metros, and a route /
        /// metro framing reveals states, cities, and the freight corridors.
        mutating func buildGeography(viewport: BespokeMapViewport, rect: CGRect) {
            let z = viewport.zoom
            // Generous cull so a border ring or corridor straddling the edge is
            // still drawn (its on-screen portion clips naturally at paint time).
            let cull = rect.insetBy(dx: -BespokeMapCanvas.geoCullMargin,
                                    dy: -BespokeMapCanvas.geoCullMargin)

            // National outlines (US / CA / MX) — ALWAYS on (the coarsest, most
            // stabilizing register; a bare CONUS framing still gets its border).
            for feature in BespokeMapGeography.naOutlines {
                for ring in feature.rings where ring.count >= 2 {
                    let pts = ring.map { viewport.screenPoint(HereLatLng($0.lat, $0.lng)) }
                    guard BespokeMapCanvas.boundingBox(pts).intersects(cull) else { continue }
                    nationalBorders.append(pts)
                }
            }

            // State / province borders — regional-or-closer only (≥ ~4.5), so a
            // whole-continent view stays clean. Per-feature span gate drops a
            // state whose bbox is a sliver of the viewport at very low zoom.
            if z >= BespokeMapCanvas.geoStateZoom {
                for feature in BespokeMapGeography.usStates + BespokeMapGeography.caProvinces {
                    for ring in feature.rings where ring.count >= 2 {
                        let pts = ring.map { viewport.screenPoint(HereLatLng($0.lat, $0.lng)) }
                        guard BespokeMapCanvas.boundingBox(pts).intersects(cull) else { continue }
                        stateBorders.append(pts)
                    }
                }
            }

            // Interstate freight corridors ("the streets" indication) — only
            // when closer in (≥ ~5.5), so they read as lanes along the route,
            // not continental clutter.
            if z >= BespokeMapCanvas.geoCorridorZoom {
                for corridor in BespokeMapGeography.interstates where corridor.path.count >= 2 {
                    let pts = corridor.path.map { viewport.screenPoint(HereLatLng($0.lat, $0.lng)) }
                    guard BespokeMapCanvas.boundingBox(pts).intersects(cull) else { continue }
                    corridors.append(pts)
                }
            }

            // Metro labels — rank-gated by zoom (rank 1 from ~3.5, rank 2 from
            // ~5, rank 3 from ~6.5), culled to the visible rect, then capped to
            // the nearest-to-center N so a dense region never over-labels.
            let center = CGPoint(x: rect.midX, y: rect.midY)
            var candidates: [(at: CGPoint, text: String, rank: Int, d2: CGFloat)] = []
            for place in BespokeMapGeography.metros {
                let minZoom: Double
                switch place.rank {
                case 1:  minZoom = BespokeMapGeography_rank1Zoom
                case 2:  minZoom = BespokeMapGeography_rank2Zoom
                default: minZoom = BespokeMapGeography_rank3Zoom
                }
                guard z >= minZoom else { continue }
                let p = viewport.screenPoint(HereLatLng(place.lat, place.lng))
                guard rect.contains(p) else { continue }
                let dx = p.x - center.x, dy = p.y - center.y
                candidates.append((p, place.name, place.rank, dx * dx + dy * dy))
            }
            // Primary metros first, then nearest-to-center, capped.
            candidates.sort { a, b in
                if a.rank != b.rank { return a.rank < b.rank }
                return a.d2 < b.d2
            }
            for c in candidates.prefix(BespokeMapCanvas.maxPlaceLabels) {
                placeLabels.append((c.at, c.text, c.rank))
            }
        }
    }
}

// Metro-label zoom thresholds (file-scope so `buildGeography` reads cleanly).
private let BespokeMapGeography_rank1Zoom = 3.5
private let BespokeMapGeography_rank2Zoom = 5.0
private let BespokeMapGeography_rank3Zoom = 6.5

// MARK: - Tuning constants

extension BespokeMapCanvas {
    /// Hard cap on simplified route vertices fed into Catmull-Rom. A 2000-pt
    /// HERE route collapses to at most this many Bézier segments.
    static let maxRoutePoints = 400
    /// Hard cap on visible pins drawn per frame.
    static let maxVisibleMarkers = 150
    /// Hard cap on label pills drawn per frame.
    static let maxVisibleLabels = 40
    /// Off-screen margin (points) added to the visible-bounds cull for markers.
    static let markerCullMargin: CGFloat = 40
    /// Off-screen margin (points) added to the visible-bounds cull for labels.
    static let labelCullMargin: CGFloat = 120

    // FEATURE 1 — geography tuning.
    /// Off-screen margin (points) for the geography border / corridor cull.
    static let geoCullMargin: CGFloat = 200
    /// Fractional zoom at/above which state + province borders render.
    static let geoStateZoom: Double = 4.5
    /// Fractional zoom at/above which interstate corridors render.
    static let geoCorridorZoom: Double = 5.5
    /// Hard cap on metro labels drawn (nearest-to-center, primary first).
    static let maxPlaceLabels = 18

    // FEATURE 2 — geothermal field tuning.
    /// Downsampled IDW grid resolution (px) — aspect-matched at build, capped.
    static let geoFieldGridW = 88
    static let geoFieldGridH = 56
}

// MARK: - Geothermal field (FEATURE 2 — continuous IDW thermal map)

extension BespokeMapCanvas {

    /// The exact geothermal ramp, interpolated LINEARLY in sRGB. `t ∈ [0,1]`
    /// (cold → hot). Returns straight-alpha 0–255 RGB bytes for the bitmap.
    ///   0.00 #0A2A8C · 0.20 #1E6BFF · 0.40 #00C8D7 · 0.55 #43D17A ·
    ///   0.70 #FFD23F · 0.85 #FF7A29 · 1.00 #F0322B
    static func geothermalRGB(_ t: Double) -> (r: UInt8, g: UInt8, b: UInt8) {
        // Stops: (location, R, G, B).
        let stops: [(Double, Double, Double, Double)] = [
            (0.00, 0x0A, 0x2A, 0x8C),
            (0.20, 0x1E, 0x6B, 0xFF),
            (0.40, 0x00, 0xC8, 0xD7),
            (0.55, 0x43, 0xD1, 0x7A),
            (0.70, 0xFF, 0xD2, 0x3F),
            (0.85, 0xFF, 0x7A, 0x29),
            (1.00, 0xF0, 0x32, 0x2B),
        ]
        let x = Swift.min(1.0, Swift.max(0.0, t))
        var lo = stops[0]
        var hi = stops[stops.count - 1]
        for i in 0..<(stops.count - 1) {
            if x >= stops[i].0 && x <= stops[i + 1].0 {
                lo = stops[i]; hi = stops[i + 1]; break
            }
        }
        let span = hi.0 - lo.0
        let f = span > 1e-9 ? (x - lo.0) / span : 0
        let r = lo.1 + (hi.1 - lo.1) * f
        let g = lo.2 + (hi.2 - lo.2) * f
        let b = lo.3 + (hi.3 - lo.3) * f
        return (UInt8(r.rounded()), UInt8(g.rounded()), UInt8(b.rounded()))
    }

    /// Map a raw load-to-truck ratio onto the geothermal domain `t ∈ [0,1]`
    /// through a FIXED piecewise scale (0.5→0 cold … 1.4→~0.36 … 3.0→1 hot),
    /// clamped — so the same ratio always reads the same temperature across
    /// cameras / datasets (no per-frame renormalization).
    static func geothermalT(forRatio ratio: Double) -> Double {
        let r = ratio
        if r <= 0.5 { return 0.0 }
        if r >= 3.0 { return 1.0 }
        if r <= 1.4 {
            // 0.5 → 0.0 … 1.4 → 0.36
            return (r - 0.5) / (1.4 - 0.5) * 0.36
        }
        // 1.4 → 0.36 … 3.0 → 1.0
        return 0.36 + (r - 1.4) / (3.0 - 1.4) * (1.0 - 0.36)
    }

    /// FEATURE 2 — rasterize the heat blobs into ONE continuous geothermal
    /// field CGImage via inverse-distance weighting on a downsampled grid.
    /// Built ONCE in `RenderModel.build`; the per-frame closure just blits it.
    /// Each cell's temperature is the IDW of the nearby zones' ratios mapped
    /// through `geothermalT`; cell alpha rises with both a base tint and the
    /// IDW coverage so the whole field is graded yet readable under the route.
    /// Returns nil when there are no blobs (zero-fabrication contract).
    static func geothermalField(
        blobs: [(center: CGPoint, weight: Double)],
        rect: CGRect
    ) -> CGImage? {
        guard !blobs.isEmpty, rect.width > 1, rect.height > 1 else { return nil }

        // Aspect-matched grid, capped at the tuning resolution.
        let aspect = rect.width / Swift.max(1, rect.height)
        var gw = geoFieldGridW
        var gh = geoFieldGridH
        if aspect >= 1 {
            gh = Swift.max(8, Swift.min(geoFieldGridH, Int((Double(gw) / Double(aspect)).rounded())))
        } else {
            gw = Swift.max(8, Swift.min(geoFieldGridW, Int((Double(gh) * Double(aspect)).rounded())))
        }

        // Influence radius (points) — scaled to the view so isolated zones
        // bleed into a field rather than reading as dots. IDW power 2.
        let influence = Double(Swift.max(rect.width, rect.height)) * 0.42
        let inf2 = influence * influence

        let cellW = Double(rect.width) / Double(gw)
        let cellH = Double(rect.height) / Double(gh)

        // Precompute blob centers (relative to rect origin) + their temperature.
        let pts: [(x: Double, y: Double, t: Double)] = blobs.map {
            (Double($0.center.x - rect.minX),
             Double($0.center.y - rect.minY),
             geothermalT(forRatio: $0.weight))
        }

        let bytesPerPixel = 4
        let bytesPerRow = gw * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: gh * bytesPerRow)

        for gy in 0..<gh {
            let py = (Double(gy) + 0.5) * cellH
            for gx in 0..<gw {
                let px = (Double(gx) + 0.5) * cellW
                // IDW over the zones (power 2). `cover` is the summed inverse-
                // distance weight → drives alpha so cells far from any zone fade.
                var wsum = 0.0
                var tsum = 0.0
                var nearest2 = Double.greatestFiniteMagnitude
                for p in pts {
                    let dx = px - p.x, dy = py - p.y
                    let d2 = dx * dx + dy * dy
                    if d2 < nearest2 { nearest2 = d2 }
                    let w = 1.0 / (d2 + 60.0)   // +eps avoids singularity at a zone
                    wsum += w
                    tsum += w * p.t
                }
                let t = wsum > 0 ? tsum / wsum : 0
                let (r, g, b) = geothermalRGB(t)

                // Coverage falloff: full alpha within the influence radius of the
                // nearest zone, easing to a low base tint beyond it (so the whole
                // field is graded, denser near zones).
                let near = Swift.min(1.0, nearest2 / inf2)
                let coverage = 1.0 - near          // 1 at a zone → 0 past influence
                let baseAlpha = 0.16               // everything tinted
                let peakAlpha = 0.62               // near a zone
                let a = baseAlpha + (peakAlpha - baseAlpha) * coverage
                let alpha = UInt8((Swift.min(1.0, Swift.max(0.0, a)) * 255.0).rounded())

                let off = gy * bytesPerRow + gx * bytesPerPixel
                // Premultiplied straight→premul (premultipliedLast): scale RGB by α.
                let af = Double(alpha) / 255.0
                buffer[off]     = UInt8((Double(r) * af).rounded())
                buffer[off + 1] = UInt8((Double(g) * af).rounded())
                buffer[off + 2] = UInt8((Double(b) * af).rounded())
                buffer[off + 3] = alpha
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx = CGContext(
            data: &buffer,
            width: gw,
            height: gh,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        return ctx.makeImage()
    }
}

// MARK: - Canvas painting (static so no closures capture self)

extension BespokeMapCanvas {

    /// Per-frame canon motion phases, derived from the shared wall clock so
    /// every map on screen pulses in lockstep with the brand rhythm.
    /// `.still` paints the wireframes' authored static geometry
    /// (reduce-motion / paused timeline).
    struct PulsePhase {
        /// 0…1 sawtooth over the 2.2 s board-puck pulse period (222).
        var pulse22: Double = 0
        /// 0…1 sawtooth over the 2.4 s AIS / port-approach pulse period (660).
        var pulse24: Double = 0
        /// 0…1 sawtooth over the 2.0 s breach exitPulse period (536).
        var pulse20: Double = 0
        /// Animated route-flow dash offset: 0 → −20 over 1.4 s (222).
        var flowDashOffset: CGFloat = 0
        /// Pilot-ground fence dash march (660): dashPhase 0 → 10 over 1 s —
        /// one full [5,5] cadence per second, the legacy JS fx clock verbatim.
        var fenceDashOffset: CGFloat = 0
        /// false ⇒ static frame — painters skip the pulse math entirely.
        var animated: Bool = false

        static let still = PulsePhase()
    }

    /// Resolve the motion phases for a timeline tick. Pure arithmetic on the
    /// wall clock — no allocation, no state.
    static func pulsePhase(at date: Date) -> PulsePhase {
        let t = date.timeIntervalSinceReferenceDate
        var p = PulsePhase()
        p.pulse22 = (t / 2.2).truncatingRemainder(dividingBy: 1)
        p.pulse24 = (t / 2.4).truncatingRemainder(dividingBy: 1)
        p.pulse20 = (t / 2.0).truncatingRemainder(dividingBy: 1)
        p.flowDashOffset = CGFloat(-20.0 * (t / 1.4).truncatingRemainder(dividingBy: 1))
        p.fenceDashOffset = CGFloat((t * 10.0).truncatingRemainder(dividingBy: 10.0))
        p.animated = true
        return p
    }

    /// 0→1→0 triangle wave over a 0…1 sawtooth — the canon pulse easing
    /// (r12→22→12 / opacity 0.9→0.3→0.9 read as one out-and-back sweep).
    static func pulseTriangle(_ saw: Double) -> Double {
        1.0 - abs(2.0 * saw - 1.0)
    }

    /// The full draw pipeline. Static + value-typed so the `Canvas` closure
    /// holds nothing referential. Consumes the PRECOMPUTED `RenderModel` — it
    /// only re-emits cheap chrome (background / grid / silhouettes) and
    /// rasterizes already-projected geometry. No projection, no simplify, no
    /// smoothing happens here. `phase` carries the canon motion clock.
    static func paint(
        context: inout GraphicsContext,
        size: CGSize,
        model: RenderModel,
        phase: PulsePhase = .still
    ) {
        let rect = CGRect(origin: .zero, size: size)
        let style = model.style

        // 1 — background
        paintBackground(&context, rect: rect, bg: style.background)

        // 1b — basemap (pre-projected rings).
        if !model.isOcean {
            paintBasemap(&context, model: model)
            // 1c — real geographic context (FEATURE 1): national + state
            // borders, interstate corridors, metro labels — UNDER the route.
            paintGeography(&context, model: model)
        }

        // 2 — faint grid.
        paintGrid(&context, rect: rect, grid: style.grid, isDriver: model.isDriverGrid,
                  isOcean: model.isOcean, isNav: model.isNav, isPortApproach: model.isPortApproach)

        // 3 — abstract silhouettes.
        paintSilhouettes(&context, rect: rect, silhouettes: style.silhouettes,
                         isOcean: model.isOcean, isNav: model.isNav)

        // 4a — heatmap. The .geothermal register paints ONE continuous IDW
        // thermal field (FEATURE 2) UNDER the route; every other register keeps
        // the legacy per-zone demand blobs (contract preserved).
        if model.isGeothermal {
            if let field = model.geoField {
                // High interpolation so the downsampled grid blits as a SMOOTH
                // field (continuous grade, no blocks). The interpolation quality
                // travels on the Image itself (.interpolation(.high)) rather than
                // the GraphicsContext, so no quality state leaks to later painters.
                let img = Image(decorative: field, scale: 1, orientation: .up)
                    .interpolation(.high)
                context.draw(img, in: model.geoFieldRect)
            }
        } else {
            for blob in model.heatBlobs {
                paintHeatBlob(&context, center: blob.center, weight: blob.weight, maxWeight: heatMaxWeight(model))
            }
        }
        // 4b — ad-zones.
        for z in model.adZones {
            paintAdZone(&context, pts: z.pts, fill: z.fill, opacity: z.opacity)
        }
        // 4b2 — traffic-flow ribbons: ABOVE the basemap road grammar, BELOW
        // the route + every pin.
        for seg in model.traffic {
            paintTrafficSegment(&context, path: seg.path, severity: seg.severity,
                                isDark: model.isDarkRegister)
        }
        // 4c — independent exact route/reference members.
        if model.hasRoute {
            paintRoutePaths(&context, model: model)
        }
        // 4c2 — geofence rings (+ breach node): above the route, below pins
        // (the JS __applyLayers z-order — fences before markers).
        for fence in model.fences {
            paintFence(&context, center: fence.center, radius: fence.radius,
                       kind: fence.kind, breach: fence.breach,
                       isDark: model.isDarkRegister, phase: phase)
        }
        // 4d — endpoints.
        for ep in model.endpoints {
            paintEndpoint(&context, at: ep.at, marker: ep.marker)
        }
        // 4e — generic markers (culled + capped).
        for mk in model.markers {
            paintMarker(&context, at: mk.at, kind: mk.kind, style: style, phase: phase)
        }

        // 5 — callout pills (culled + capped) + scale pill.
        for label in model.labels {
            paintPill(&context, anchor: label.anchor, text: label.text, style: style, above: true)
        }
        if let scale = model.scalePillText {
            paintScalePill(&context, rect: rect, text: scale, style: style)
        }
    }

    /// Normalized heatmap denominator from the model's blobs.
    static func heatMaxWeight(_ model: RenderModel) -> Double {
        var maxW = 0.0
        for b in model.heatBlobs { maxW = Swift.max(maxW, b.weight) }
        return maxW > 0 ? maxW : 1.0
    }

    // MARK: 1 — Background

    static func paintBackground(_ context: inout GraphicsContext, rect: CGRect, bg: BespokeMapStyle.Background) {
        let gradient = Gradient(stops: zip(bg.stops, bg.locations).map {
            Gradient.Stop(color: $0.0, location: CGFloat($0.1))
        })
        if bg.isRadial {
            let maxEdge = Swift.max(rect.width, rect.height)
            let cx = rect.width * bg.radialCenter.x
            let cy = rect.height * bg.radialCenter.y
            let r = maxEdge * CGFloat(bg.radialRadius)
            // Underfill with the outermost stop so corners the radial can't
            // reach still read as deep space (matches the SVG's solid base rect).
            if let outer = bg.stops.last {
                context.fill(Path(rect), with: .color(outer))
            }
            context.fill(
                Path(rect),
                with: .radialGradient(
                    gradient,
                    center: CGPoint(x: cx, y: cy),
                    startRadius: 0,
                    endRadius: r
                )
            )
        } else {
            context.fill(
                Path(rect),
                with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                )
            )
        }
    }

    // MARK: 1b — Abstract land basemap (PRE-projected continental coastlines)

    /// Rasterize the pre-projected + pre-culled continent rings the model
    /// computed. No projection happens here — `RenderModel.build` already
    /// projected through the committed viewport and culled off-screen rings.
    static func paintBasemap(_ context: inout GraphicsContext, model: RenderModel) {
        for pts in model.basemapRings {
            guard pts.count > 2 else { continue }
            var path = Path()
            path.move(to: pts[0])
            for p in pts.dropFirst() { path.addLine(to: p) }
            path.closeSubpath()
            context.fill(path, with: .color(model.landColor))
            context.stroke(
                path,
                with: .color(model.coastColor),
                style: StrokeStyle(lineWidth: model.coastWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }

    // MARK: 1c — Real geographic context (FEATURE 1 — borders / roads / cities)

    /// Rasterize the pre-projected geography the model computed: national
    /// borders (a slightly bolder coastColor stroke), state / province borders
    /// (thin, low-opacity coastColor), interstate freight corridors (thin warm
    /// desaturated "streets" along the lanes), and metro labels (small haloed
    /// text). All UNDER the route / markers so the lane stays the focal layer.
    /// Nothing here projects — `RenderModel.buildGeography` already did, culled
    /// + zoom-gated. Tasteful + faint by design; matches the light/dark register
    /// via `model.coastColor` / `model.isDarkRegister`.
    static func paintGeography(_ context: inout GraphicsContext, model: RenderModel) {
        // State / province borders — THIN, low-opacity (≈0.6pt, coast @~0.5α).
        if !model.stateBorders.isEmpty {
            var statePath = Path()
            for pts in model.stateBorders where pts.count >= 2 {
                statePath.move(to: pts[0])
                for p in pts.dropFirst() { statePath.addLine(to: p) }
            }
            context.stroke(
                statePath,
                with: .color(model.coastColor.opacity(0.5)),
                style: StrokeStyle(lineWidth: 0.6, lineCap: .round, lineJoin: .round))
        }

        // Interstate corridors — thin warm desaturated road-tint ("streets").
        // Slightly brighter on dark registers so they read over the land wash.
        if !model.corridors.isEmpty {
            let roadTint = model.isDarkRegister
                ? Color(hex: 0xC9A36B).opacity(0.40)   // warm tan, dark backdrop
                : Color(hex: 0xB07B3A).opacity(0.34)   // warm desaturated, light
            var roadPath = Path()
            for pts in model.corridors where pts.count >= 2 {
                roadPath.move(to: pts[0])
                for p in pts.dropFirst() { roadPath.addLine(to: p) }
            }
            context.stroke(
                roadPath,
                with: .color(roadTint),
                style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round))
        }

        // National borders — a slightly BOLDER coastColor stroke (the most
        // stabilizing register). Painted last of the line work so it reads on top
        // of the fainter state lines.
        if !model.nationalBorders.isEmpty {
            var natPath = Path()
            for pts in model.nationalBorders where pts.count >= 2 {
                natPath.move(to: pts[0])
                for p in pts.dropFirst() { natPath.addLine(to: p) }
            }
            context.stroke(
                natPath,
                with: .color(model.coastColor.opacity(0.85)),
                style: StrokeStyle(lineWidth: model.coastWidth + 0.4, lineCap: .round, lineJoin: .round))
        }

        // Metro labels — small system text with a subtle halo/shadow so they
        // stay legible over the land wash, UNDER the route. Primary metros a
        // touch larger / bolder than secondary + tertiary.
        guard !model.placeLabels.isEmpty else { return }
        let textColor: Color = model.isDarkRegister
            ? Color.white.opacity(0.82)
            : Color(hex: 0x2A2F36).opacity(0.78)
        let haloColor: Color = model.isDarkRegister
            ? Color.black.opacity(0.55)
            : Color.white.opacity(0.75)
        for label in model.placeLabels {
            let size: CGFloat = label.rank == 1 ? 10.5 : (label.rank == 2 ? 9.5 : 9.0)
            let weight: Font.Weight = label.rank == 1 ? .semibold : .medium
            var resolved = context.resolve(
                Text(label.text)
                    .font(.system(size: size, weight: weight, design: .default))
                    .foregroundColor(textColor))
            let ts = resolved.measure(in: CGSize(width: 160, height: 24))
            // Anchor the label just above its place dot.
            let origin = CGPoint(x: label.at.x - ts.width / 2, y: label.at.y - ts.height - 3)
            // Halo — draw the text offset in 4 directions in the halo color.
            var halo = resolved
            halo.shading = .color(haloColor)
            for off in [(-0.6, 0.0), (0.6, 0.0), (0.0, -0.6), (0.0, 0.6)] as [(CGFloat, CGFloat)] {
                context.draw(halo, in: CGRect(x: origin.x + off.0, y: origin.y + off.1,
                                              width: ts.width, height: ts.height))
            }
            resolved.shading = .color(textColor)
            context.draw(resolved, in: CGRect(origin: origin, size: ts))
            // A small place dot at the metro anchor (primary only, to avoid
            // clutter at the dense secondary tier).
            if label.rank == 1 {
                let r: CGFloat = 1.6
                let dot = Path(ellipseIn: CGRect(x: label.at.x - r, y: label.at.y - r,
                                                 width: r * 2, height: r * 2))
                context.fill(dot, with: .color(textColor))
            }
        }
    }

    /// Whether a register's grid color is white-tinted (⇒ a dark-backdrop
    /// register). Resolved via the platform color components; falls back to
    /// `false` (light register) when components are unavailable.
    static func gridIsLight(_ color: Color) -> Bool {
        #if canImport(UIKit)
        var white: CGFloat = 0
        var alpha: CGFloat = 0
        if UIColor(color).getWhite(&white, alpha: &alpha) {
            return white > 0.5
        }
        #endif
        return false
    }

    // MARK: 2 — Grid (straight authored lines at fixed spacing)

    static func paintGrid(
        _ context: inout GraphicsContext,
        rect: CGRect,
        grid: BespokeMapStyle.Grid,
        isDriver: Bool,
        isOcean: Bool = false,
        isNav: Bool = false,
        isPortApproach: Bool = false
    ) {
        // OCEAN (003 Vessel): the SVG authors ONLY 3 horizontal latitude lines
        // (no longitude verticals). Paint exactly those — never the board crosshatch.
        if isOcean {
            var oceanPath = Path()
            for f in [0.30, 0.50, 0.70] as [CGFloat] {
                let y = rect.minY + rect.height * f
                oceanPath.move(to: CGPoint(x: rect.minX, y: y))
                oceanPath.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            context.stroke(oceanPath, with: .color(grid.color), lineWidth: grid.width)
            return
        }
        // VERBATIM: straight authored graticule at FIXED spacing — NO
        // foreshorten / warp on horizontals. Driver register: 44pt square grid.
        // Shipper board: 60pt vertical columns / 80pt horizontal rows.
        // Nav (035): 73pt columns / 96pt rows. Port approach (660): 72/32.
        let hSpacing: CGFloat   // vertical line spacing (columns)
        let vSpacing: CGFloat   // horizontal line spacing (rows)
        if isPortApproach {
            hSpacing = 72; vSpacing = 32
        } else if isNav {
            hSpacing = 73; vSpacing = 96
        } else if isDriver {
            hSpacing = 44; vSpacing = 44
        } else {
            hSpacing = 60; vSpacing = 80
        }

        var path = Path()
        var x: CGFloat = 0
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += hSpacing
        }
        var y: CGFloat = 0
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += vSpacing
        }
        context.stroke(path, with: .color(grid.color), lineWidth: grid.width)
    }

    // MARK: 3 — Abstract horizon silhouettes

    static func paintSilhouettes(
        _ context: inout GraphicsContext,
        rect: CGRect,
        silhouettes: BespokeMapStyle.Silhouettes?,
        isOcean: Bool = false,
        isNav: Bool = false
    ) {
        guard let s = silhouettes else { return }
        let w0 = rect.width, h0 = rect.height
        // NAV (035): TWO secondary-road ribbons at authored positions, each
        // stroked with EVERY silhouette pass on the SAME geometry (light:
        // #FFFFFF w9 then the #000000@0.05 w9 tint that greys the ribbon;
        // dark: a single #161B27 w9 pass). Normalized off the 440×956 frame:
        //   A: M-20 612 L210 540 L470 600 · B: M340 -20 L300 230 L360 470.
        if isNav {
            var roadA = Path()
            roadA.move(to: CGPoint(x: -0.045 * w0, y: 0.640 * h0))
            roadA.addLine(to: CGPoint(x: 0.477 * w0, y: 0.565 * h0))
            roadA.addLine(to: CGPoint(x: 1.068 * w0, y: 0.628 * h0))
            var roadB = Path()
            roadB.move(to: CGPoint(x: 0.773 * w0, y: -0.021 * h0))
            roadB.addLine(to: CGPoint(x: 0.682 * w0, y: 0.241 * h0))
            roadB.addLine(to: CGPoint(x: 0.818 * w0, y: 0.492 * h0))
            let passes = Swift.min(s.colors.count, s.widths.count)
            for i in 0..<passes {
                let st = StrokeStyle(lineWidth: s.widths[i], lineCap: .round, lineJoin: .round)
                context.stroke(roadA, with: .color(s.colors[i]), style: st)
                context.stroke(roadB, with: .color(s.colors[i]), style: st)
            }
            return
        }
        // OCEAN (003 Vessel): the SVG hugs TWO discrete VERTICAL coast squiggles
        // at the left + right card margins (not a horizontal horizon sweep).
        if isOcean, s.colors.count > 0, s.widths.count > 0 {
            let col = s.colors[0], lw = s.widths[0]
            // Left edge coast hint (~x 0.09w): M40 200 q14 30 -2 60 q-12 26 6 50.
            var left = Path()
            left.move(to: CGPoint(x: 0.09 * w0, y: 0.36 * h0))
            left.addQuadCurve(to: CGPoint(x: 0.06 * w0, y: 0.47 * h0), control: CGPoint(x: 0.12 * w0, y: 0.41 * h0))
            left.addQuadCurve(to: CGPoint(x: 0.08 * w0, y: 0.56 * h0), control: CGPoint(x: 0.04 * w0, y: 0.52 * h0))
            // Right edge coast hint (~x 0.91w), mirrored.
            var right = Path()
            right.move(to: CGPoint(x: 0.91 * w0, y: 0.62 * h0))
            right.addQuadCurve(to: CGPoint(x: 0.94 * w0, y: 0.73 * h0), control: CGPoint(x: 0.88 * w0, y: 0.67 * h0))
            right.addQuadCurve(to: CGPoint(x: 0.92 * w0, y: 0.82 * h0), control: CGPoint(x: 0.96 * w0, y: 0.78 * h0))
            let st = StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)
            context.stroke(left, with: .color(col), style: st)
            context.stroke(right, with: .color(col), style: st)
            return
        }
        // Paint min(colors,widths) layered horizon ribbons. These are ABSTRACT
        // (parametric fractions of the canvas), never real geometry — matching
        // the SVG's decorative silhouette band. Each stroke i uses colors[i] /
        // widths[i] (1:1). .dark/.light supply ONE stroke; cosmos/lightDriver
        // supply THREE (descending opacity / width → layered horizons).
        let count = Swift.min(s.colors.count, s.widths.count)
        guard count > 0 else { return }
        let w = rect.width
        let h = rect.height

        for i in 0..<count {
            // Stagger each successive ribbon's vertical band so the three driver
            // strokes read as separate horizons rather than one thick road.
            let band = 0.30 + 0.16 * CGFloat(i)
            var path = Path()
            path.move(to: CGPoint(x: -0.05 * w, y: (band + 0.06) * h))
            path.addQuadCurve(
                to: CGPoint(x: 0.5 * w, y: band * h),
                control: CGPoint(x: 0.27 * w, y: (band + 0.02) * h)
            )
            path.addQuadCurve(
                to: CGPoint(x: 1.05 * w, y: (band - 0.04) * h),
                control: CGPoint(x: 0.78 * w, y: (band - 0.03) * h)
            )
            context.stroke(
                path,
                with: .color(s.colors[i]),
                style: StrokeStyle(lineWidth: s.widths[i], lineCap: .round, lineJoin: .round)
            )
        }
    }

    // MARK: 4a — Heatmap (weighted soft radial blobs)

    static func paintHeatBlob(
        _ context: inout GraphicsContext,
        center: CGPoint,
        weight rawWeight: Double,
        maxWeight: Double
    ) {
        let weight = rawWeight / maxWeight
        // Radius ∝ the normalized demand weight (load-to-truck ratio).
        let radius = CGFloat(28 + 46 * weight)
        let blob = Path(ellipseIn: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2))
        // VERBATIM 544 Dispatcher Demand Map intensity ramp (NOT the brand
        // sweep) — keyed hot / warm / soft by the normalized weight:
        //   hot  ≥ 0.66 : #F44336@0.60 → #FF7043@0.28 → clear
        //   warm ≥ 0.33 : #FFA726@0.52 → clear
        //   soft        : #2196F3@0.34 → clear  (surplus / cold)
        let g: Gradient
        if weight >= 0.66 {
            let ember = Color(hex: 0xFF7043)
            g = Gradient(stops: [
                Gradient.Stop(color: Brand.danger.opacity(0.60), location: 0.0),
                Gradient.Stop(color: ember.opacity(0.28), location: 0.55),
                Gradient.Stop(color: ember.opacity(0.0), location: 1.0)
            ])
        } else if weight >= 0.33 {
            g = Gradient(stops: [
                Gradient.Stop(color: Brand.warning.opacity(0.52), location: 0.0),
                Gradient.Stop(color: Brand.warning.opacity(0.0), location: 1.0)
            ])
        } else {
            g = Gradient(stops: [
                Gradient.Stop(color: Brand.info.opacity(0.34), location: 0.0),
                Gradient.Stop(color: Brand.info.opacity(0.0), location: 1.0)
            ])
        }
        context.fill(
            blob,
            with: .radialGradient(g, center: center, startRadius: 0, endRadius: radius)
        )
    }

    // MARK: 4b — Ad-zone polygons (filled)

    static func paintAdZone(
        _ context: inout GraphicsContext,
        pts: [CGPoint],
        fill: Color,
        opacity: Double
    ) {
        guard pts.count > 2 else { return }
        var path = Path()
        path.move(to: pts[0])
        for pt in pts.dropFirst() { path.addLine(to: pt) }
        path.closeSubpath()
        context.fill(path, with: .color(fill.opacity(opacity)))
        context.stroke(path, with: .color(fill.opacity(Swift.min(1.0, opacity + 0.35))), lineWidth: 1.4)
    }

    // MARK: 4b2 — Traffic-flow ribbons (§2 — 536 congestion segments)

    /// One congestion ribbon over the road grammar, under the route: jam =
    /// #FFA726 w6 round @0.9 (L) / 0.95 (D) · severe = #F44336 w6 @0.85 (L) /
    /// 0.9 (D). The Path was projected + smoothed once in `RenderModel.build`.
    static func paintTrafficSegment(
        _ context: inout GraphicsContext,
        path: Path,
        severity: HereTrafficSegment.Severity,
        isDark: Bool
    ) {
        let tint: Color
        let alpha: Double
        switch severity {
        case .jam:    tint = Brand.warning; alpha = isDark ? 0.95 : 0.90
        case .severe: tint = Brand.danger;  alpha = isDark ? 0.90 : 0.85
        }
        context.stroke(
            path,
            with: .color(tint.opacity(alpha)),
            style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
    }

    // MARK: 4c — Route (owned gradient + redundant state truth)

    private struct RouteVisualSpec {
        let width: CGFloat
    }

    private static func routeVisualSpec(_: HereRouteVisualState) -> RouteVisualSpec {
        // Route state is expressed by accessible text and localized glyphs.
        // The authored EusoLine itself never changes width, pattern, or edge.
        .init(width: 5)
    }

    /// Exact interpolation through the shared three authored route stops. The
    /// input is member-local route order, never screen geography.
    private static func routeColor(at progress: Double) -> Color {
        let t = Swift.max(0, Swift.min(1, progress))
        let midpoint = 0.52
        let from: (Double, Double, Double)
        let to: (Double, Double, Double)
        let local: Double
        if t <= midpoint {
            from = (0x14, 0x73, 0xFF)
            to = (0x81, 0x3F, 0xF5)
            local = t / midpoint
        } else {
            from = (0x81, 0x3F, 0xF5)
            to = (0xBE, 0x01, 0xFF)
            local = (t - midpoint) / (1 - midpoint)
        }
        return Color(
            red: (from.0 + (to.0 - from.0) * local) / 255,
            green: (from.1 + (to.1 - from.1) * local) / 255,
            blue: (from.2 + (to.2 - from.2) * local) / 255
        )
    }

    private struct EusoLineSegment {
        let points: [CGPoint]
        let progress: Double
    }

    /// Renderer-only cumulative screen-distance parameterization. Every added
    /// point subdivides an existing straight edge; original corners remain
    /// exact. This is never canonical distance, progress, ETA, Haul, or price.
    private static func eusoLineSegments(
        _ points: [CGPoint],
        budget: Int = 72
    ) -> [EusoLineSegment] {
        guard points.count >= 2 else { return [] }
        let epsilon = 0.000_001
        var weights: [Double] = []
        var cumulative: [Double] = [0]
        var total = 0.0
        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            let weight = hypot(Double(end.x - start.x), Double(end.y - start.y))
            weights.append(weight)
            total += weight
            cumulative.append(total)
        }

        guard total > epsilon else {
            return [.init(points: points, progress: 0.5)]
        }
        let count = Swift.max(1, Swift.min(96, budget))

        func point(at distance: Double) -> CGPoint {
            if distance <= 0 { return points[0] }
            if distance >= total { return points[points.count - 1] }
            var low = 0
            var high = cumulative.count - 1
            while low + 1 < high {
                let middle = (low + high) / 2
                if cumulative[middle] <= distance {
                    low = middle
                } else {
                    high = middle
                }
            }

            var edge = Swift.min(low, weights.count - 1)
            while edge < weights.count - 1, weights[edge] <= epsilon {
                edge += 1
            }
            let weight = weights[edge]
            guard weight > epsilon else { return points[edge + 1] }
            let local = Swift.max(
                0,
                Swift.min(1, (distance - cumulative[edge]) / weight)
            )
            let start = points[edge]
            let end = points[edge + 1]
            return CGPoint(
                x: start.x + (end.x - start.x) * CGFloat(local),
                y: start.y + (end.y - start.y) * CGFloat(local)
            )
        }

        var segments: [EusoLineSegment] = []
        segments.reserveCapacity(count)
        var interiorVertex = 1
        for index in 0..<count {
            let startDistance = total * Double(index) / Double(count)
            let endDistance = total * Double(index + 1) / Double(count)
            var segmentPoints = [point(at: startDistance)]
            while interiorVertex < points.count - 1,
                  cumulative[interiorVertex] <= startDistance + epsilon {
                interiorVertex += 1
            }
            while interiorVertex < points.count - 1,
                  cumulative[interiorVertex] < endDistance - epsilon {
                segmentPoints.append(points[interiorVertex])
                interiorVertex += 1
            }
            segmentPoints.append(point(at: endDistance))
            segments.append(
                .init(
                    points: segmentPoints,
                    progress: (startDistance + endDistance) / (2 * total)
                )
            )
        }
        return segments
    }

    /// Stroke every independent canonical LineString as one slim, continuous
    /// EusoLine from origin blue through 52%-violet to destination purple.
    /// Legacy `.route` members fail closed during model construction; there is
    /// no neutral/static alternative route grammar.
    static func paintRoutePaths(
        _ context: inout GraphicsContext,
        model: RenderModel
    ) {
        for member in model.routeMembers {
            let spec = routeVisualSpec(member.state)
            // The route itself is the identity: one continuous gradient
            // ribbon with no outline, backdrop, casing, or route halo.
            for segment in eusoLineSegments(member.points) {
                context.stroke(
                    BespokeMapCanvas.polylinePath(segment.points),
                    with: .color(routeColor(at: segment.progress)),
                    style: StrokeStyle(
                        lineWidth: spec.width,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
    }

    // MARK: 4c2 — Geofence rings (§3c — dashed circle fences + breach node)

    /// One canon geofence: a dashed circle in the kind's wireframe-verbatim
    /// ring color / dash cadence over its authored fill — receiver (536) /
    /// rail ramp (003-rail, + fencePulse) / pilot ground (660, marching
    /// dashoffset) / dest port (vessel 003) — plus the breach/EXIT node +
    /// exitPulse riding the rim when a breach coordinate is present. The
    /// radius arrives already projected to points; `phase` carries the canon
    /// motion clock (the static frame paints the authored geometry, so
    /// reduce-motion / paused boards stay wireframe-true).
    static func paintFence(
        _ context: inout GraphicsContext,
        center c: CGPoint,
        radius r: CGFloat,
        kind: HereGeofenceKind,
        breach: CGPoint?,
        isDark: Bool,
        phase: PulsePhase = .still
    ) {
        let circle = Path(ellipseIn: CGRect(
            x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))

        switch kind {
        case .receiver:
            // 536 receiver fence: #F44336 w1.6 dash [6,5] @0.8 (L) / 0.85 (D)
            // over a #F44336 @0.05 (L) / 0.08 (D) wash.
            context.fill(circle, with: .color(Brand.danger.opacity(isDark ? 0.08 : 0.05)))
            context.stroke(
                circle,
                with: .color(Brand.danger.opacity(isDark ? 0.85 : 0.80)),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [6, 5]))

        case .railRamp:
            // 003-rail ramp fence: #00C48C w1.4 dash [3,4] @0.85; the fill IS
            // the fencePulse — a radial #00C48C @0.40 (L) / 0.45 (D) → 0 halo
            // swelling r → 1.3 r as it fades out, on the 2.4 s sawtooth.
            let saw = phase.animated ? phase.pulse24 : 0
            let pulseR = r * CGFloat(1.0 + 0.3 * saw)
            let pulseA = (isDark ? 0.45 : 0.40) * (1.0 - saw)
            let halo = Path(ellipseIn: CGRect(
                x: c.x - pulseR, y: c.y - pulseR, width: pulseR * 2, height: pulseR * 2))
            let haloGrad = Gradient(stops: [
                Gradient.Stop(color: Brand.success.opacity(pulseA), location: 0.0),
                Gradient.Stop(color: Brand.success.opacity(0.0), location: 1.0)
            ])
            context.fill(halo, with: .radialGradient(haloGrad, center: c, startRadius: 0, endRadius: pulseR))
            context.stroke(
                circle,
                with: .color(Brand.success.opacity(0.85)),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [3, 4]))

        case .pilotGround:
            // 660 pilot ground: #3FA9F5 @0.65 w1.4 dash [5,5] marching its
            // dashoffset (one full cadence per second), #1473FF @0.05 fill.
            context.fill(circle, with: .color(Brand.blue.opacity(0.05)))
            context.stroke(
                circle,
                with: .color(Color(hex: 0x3FA9F5).opacity(0.65)),
                style: StrokeStyle(
                    lineWidth: 1.4, lineCap: .round, dash: [5, 5],
                    dashPhase: phase.animated ? phase.fenceDashOffset : 0))

        case .destinationPort:
            // Vessel 003 dest-port fence: #1473FF @0.55 w1.6 dash [4,5], no fill.
            context.stroke(
                circle,
                with: .color(Brand.blue.opacity(0.55)),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [4, 5]))
        }

        // Breach/EXIT node riding the rim (536, §3b): the exitPulse — a
        // radial #F44336 @0.55 (L) / 0.6 (D) → 0 halo swelling 0.08 r →
        // 0.24 r over 2.0 s — under a #F44336 r5 disc with the #FFFFFF (L) /
        // #F5F5F7 (D) stroke 1.5. The static frame is the authored seed.
        if let b = breach {
            let saw = phase.animated ? phase.pulse20 : 0
            let pulseR = Swift.max(3, r * CGFloat(0.08 + 0.16 * saw))
            let pulseA = (isDark ? 0.60 : 0.55) * (1.0 - saw)
            let pulse = Path(ellipseIn: CGRect(
                x: b.x - pulseR, y: b.y - pulseR, width: pulseR * 2, height: pulseR * 2))
            let pulseGrad = Gradient(stops: [
                Gradient.Stop(color: Brand.danger.opacity(pulseA), location: 0.0),
                Gradient.Stop(color: Brand.danger.opacity(0.0), location: 1.0)
            ])
            context.fill(pulse, with: .radialGradient(pulseGrad, center: b, startRadius: 0, endRadius: pulseR))

            let nodeR: CGFloat = 5
            let node = Path(ellipseIn: CGRect(
                x: b.x - nodeR, y: b.y - nodeR, width: nodeR * 2, height: nodeR * 2))
            context.fill(node, with: .color(Brand.danger))
            context.stroke(
                node,
                with: .color(isDark ? Color(hex: 0xF5F5F7) : .white),
                lineWidth: 1.5)
        }
    }

    /// Axis-aligned bounding box of a set of screen points (degenerate-safe).
    static func boundingBox(_ pts: [CGPoint]) -> CGRect {
        guard let first = pts.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in pts.dropFirst() {
            minX = Swift.min(minX, p.x); maxX = Swift.max(maxX, p.x)
            minY = Swift.min(minY, p.y); maxY = Swift.max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: Swift.max(1, maxX - minX), height: Swift.max(1, maxY - minY))
    }

    /// Exact polyline path. Canonical route geometry uses this helper so the
    /// renderer does not round a server-authored corner into new geometry.
    static func polylinePath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for point in pts.dropFirst() { path.addLine(to: point) }
        return path
    }

    /// A smooth (Catmull-Rom-ish) path through screen points. Falls back to a
    /// straight polyline for < 3 points. Reserved for non-authoritative map
    /// decoration; canonical route members use `polylinePath`.
    static func smoothPath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        guard pts.count >= 3 else {
            for pt in pts.dropFirst() { path.addLine(to: pt) }
            return path
        }
        for i in 0..<(pts.count - 1) {
            let p0 = pts[Swift.max(0, i - 1)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[Swift.min(pts.count - 1, i + 2)]
            // Catmull-Rom → cubic Bézier control points.
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6.0, y: p1.y + (p2.y - p0.y) / 6.0)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6.0, y: p2.y - (p3.y - p1.y) / 6.0)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    /// FIX 2 — Douglas–Peucker polyline simplification on SCREEN points to a
    /// pixel-scale `tolerance`, then a hard `cap` (uniform stride decimation if
    /// the simplified set still exceeds the cap). Endpoints are always kept, so
    /// the route's origin / destination never drift. Returns the input verbatim
    /// when it already has ≤ 2 points.
    static func simplify(_ pts: [CGPoint], tolerance: CGFloat, cap: Int) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        // Mark which indices to keep.
        var keep = [Bool](repeating: false, count: pts.count)
        keep[0] = true
        keep[pts.count - 1] = true
        // Iterative DP (explicit stack — no recursion blowup on long routes).
        var stack: [(Int, Int)] = [(0, pts.count - 1)]
        let tol2 = tolerance * tolerance
        while let (lo, hi) = stack.popLast() {
            guard hi > lo + 1 else { continue }
            let a = pts[lo], b = pts[hi]
            var maxD2: CGFloat = -1
            var idx = lo
            for i in (lo + 1)..<hi {
                let d2 = perpendicularDistanceSquared(pts[i], a, b)
                if d2 > maxD2 { maxD2 = d2; idx = i }
            }
            if maxD2 > tol2 {
                keep[idx] = true
                stack.append((lo, idx))
                stack.append((idx, hi))
            }
        }
        var out: [CGPoint] = []
        out.reserveCapacity(pts.count)
        for (i, p) in pts.enumerated() where keep[i] { out.append(p) }

        // Hard cap — uniform stride decimation keeping first + last.
        if out.count > cap {
            var capped: [CGPoint] = []
            capped.reserveCapacity(cap)
            let stride = Double(out.count - 1) / Double(cap - 1)
            for i in 0..<cap {
                let j = Swift.min(out.count - 1, Int((Double(i) * stride).rounded()))
                capped.append(out[j])
            }
            // Guarantee the true endpoints survive rounding.
            capped[0] = out[0]
            capped[cap - 1] = out[out.count - 1]
            return capped
        }
        return out
    }

    /// Squared perpendicular distance from point `p` to the segment `a–b`
    /// (treated as an infinite line; degenerate `a==b` falls back to |p−a|²).
    static func perpendicularDistanceSquared(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 1e-9 else {
            let ex = p.x - a.x, ey = p.y - a.y
            return ex * ex + ey * ey
        }
        let num = (p.x - a.x) * dy - (p.y - a.y) * dx
        return (num * num) / len2
    }

    // MARK: 4d — Endpoint markers (concentric origin / dest, or glass dest pill)

    static func paintEndpoint(
        _ context: inout GraphicsContext,
        at c: CGPoint,
        marker: BespokeMapStyle.EndpointMarker
    ) {
        // VERBATIM: omitted endpoints paint NOTHING (cosmos / lightDriver origin).
        if marker.omitted { return }

        // Local endpoint grace from the authored route mockups. This stays
        // beneath the marker and never becomes a route outline or geometry.
        if let bloom = marker.bloom {
            paintEndpointBloom(&context, at: c, bloom: bloom)
        }

        // VERBATIM: a glass-pill + rounded-diamond destination glyph replaces the
        // concentric circles entirely when present (cosmos / lightDriver dest).
        if let dp = marker.destPill {
            paintDestPill(&context, at: c, pill: dp)
            return
        }

        // OCEAN 003: a genuinely HOLLOW port pin. The underlying water stays
        // visible through the center; only the sourced port ring is painted.
        // Origin ring = eusoPrimary, dest ring = #6E7681 / #8A96A3.
        if let ringStroke = marker.ringStroke, marker.ringWidth > 0 {
            let ring = Path(ellipseIn: CGRect(
                x: c.x - marker.outerRadius, y: c.y - marker.outerRadius,
                width: marker.outerRadius * 2, height: marker.outerRadius * 2))
            if let stops = marker.ringGradient, !stops.isEmpty {
                context.stroke(
                    ring,
                    with: .linearGradient(
                        Gradient(colors: stops),
                        startPoint: CGPoint(x: c.x - marker.outerRadius, y: c.y),
                        endPoint: CGPoint(x: c.x + marker.outerRadius, y: c.y)
                    ),
                    lineWidth: marker.ringWidth
                )
            } else {
                context.stroke(ring, with: .color(ringStroke), lineWidth: marker.ringWidth)
            }
            return
        }

        // Standard concentric origin / dest.
        let outer = Path(ellipseIn: CGRect(
            x: c.x - marker.outerRadius, y: c.y - marker.outerRadius,
            width: marker.outerRadius * 2, height: marker.outerRadius * 2))
        context.fill(outer, with: .color(marker.outerFill))
        // Optional outer hairline (035 maneuver node / 660 dest halo ring).
        if let stroke = marker.outerStroke, marker.outerStrokeWidth > 0 {
            context.stroke(outer, with: .color(stroke), lineWidth: marker.outerStrokeWidth)
        }

        // Inner core — gradient if provided, else solid fill. Gradient is fixed
        // map-space bottom-leading → top-trailing across the inner disc.
        let inner = Path(ellipseIn: CGRect(
            x: c.x - marker.innerRadius, y: c.y - marker.innerRadius,
            width: marker.innerRadius * 2, height: marker.innerRadius * 2))
        if let grad = marker.innerGradient, !grad.isEmpty {
            context.fill(
                inner,
                with: .linearGradient(
                    Gradient(colors: grad),
                    startPoint: CGPoint(x: c.x - marker.innerRadius, y: c.y + marker.innerRadius),
                    endPoint: CGPoint(x: c.x + marker.innerRadius, y: c.y - marker.innerRadius)
                )
            )
        } else {
            context.fill(inner, with: .color(marker.innerFill))
        }
    }

    /// Paint a soft endpoint-local bloom. `.ring` never paints inside its
    /// inner edge, preserving the transparent center of Vessel port rings.
    static func paintEndpointBloom(
        _ context: inout GraphicsContext,
        at c: CGPoint,
        bloom: BespokeMapStyle.EndpointBloom
    ) {
        guard bloom.radius > 0, bloom.opacity > 0 else { return }
        let rect = CGRect(
            x: c.x - bloom.radius,
            y: c.y - bloom.radius,
            width: bloom.radius * 2,
            height: bloom.radius * 2
        )
        let path = Path(ellipseIn: rect)
        switch bloom.treatment {
        case .disc:
            context.fill(
                path,
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: bloom.color.opacity(bloom.opacity), location: 0),
                        .init(color: bloom.color.opacity(bloom.opacity * 0.42), location: 0.55),
                        .init(color: .clear, location: 1),
                    ]),
                    center: c,
                    startRadius: 0,
                    endRadius: bloom.radius
                )
            )
        case .ring:
            let width = Swift.max(1, bloom.ringWidth)
            context.stroke(
                path,
                with: .color(bloom.color.opacity(bloom.opacity * 0.30)),
                lineWidth: width * 1.8
            )
            context.stroke(
                path,
                with: .color(bloom.color.opacity(bloom.opacity)),
                lineWidth: width
            )
        }
    }

    /// The cosmos / lightDriver destination glyph: a glass pill backing with a
    /// small rounded diamond (eusoDiagonal) rotated −45° centered on it.
    static func paintDestPill(
        _ context: inout GraphicsContext,
        at c: CGPoint,
        pill dp: BespokeMapStyle.DestPill
    ) {
        // Glass pill — sized to comfortably back the diamond.
        let pillW = dp.diamondSize + 16
        let pillH = dp.diamondSize + 10
        let pillRect = CGRect(x: c.x - pillW / 2, y: c.y - pillH / 2, width: pillW, height: pillH)
        let pillPath = Path(roundedRect: pillRect, cornerRadius: dp.pillCornerRadius, style: .continuous)
        context.fill(pillPath, with: .color(dp.pillFill))
        context.stroke(pillPath, with: .color(dp.pillBorder), lineWidth: dp.pillBorderWidth)

        // Rounded diamond — a rounded square rotated `diamondRotation`° about c.
        let half = dp.diamondSize / 2
        let squareRect = CGRect(x: c.x - half, y: c.y - half, width: dp.diamondSize, height: dp.diamondSize)
        let squarePath = Path(roundedRect: squareRect, cornerRadius: dp.diamondCornerRadius, style: .continuous)
        var transform = context
        transform.translateBy(x: c.x, y: c.y)
        transform.rotate(by: .degrees(dp.diamondRotation))
        transform.translateBy(x: -c.x, y: -c.y)
        transform.fill(
            squarePath,
            with: .linearGradient(
                Gradient(colors: dp.diamondGradient),
                startPoint: CGPoint(x: squareRect.minX, y: squareRect.maxY),
                endPoint: CGPoint(x: squareRect.maxX, y: squareRect.minY)
            )
        )
    }

    // MARK: 4e — Generic markers (truck / ping puck + endpoint-style pins)

    static func paintMarker(
        _ context: inout GraphicsContext,
        at c: CGPoint,
        kind: HereMarker.Kind,
        style: BespokeMapStyle,
        phase: PulsePhase = .still
    ) {
        switch kind {
        case .truck, .rail, .vessel:
            // Exactly ONE puck per register: truck on standard, ping on driver.
            if let truck = style.truckMarker {
                paintTruck(&context, at: c, truck: truck, phase: phase)
            } else if let ping = style.ping {
                paintPing(&context, at: c, ping: ping, phase: phase)
            }
        case .cluster:
            let r: CGFloat = 10
            let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            context.fill(
                disc,
                with: .linearGradient(
                    Gradient(colors: [Color(hex: "#1473FF"), Color(hex: "#813FF5"), Color(hex: "#BE01FF")]),
                    startPoint: CGPoint(x: c.x - r, y: c.y),
                    endPoint: CGPoint(x: c.x + r, y: c.y)
                )
            )
            context.stroke(disc, with: .color(.white.opacity(0.92)), lineWidth: 1.5)
        case .pickup:
            paintEndpoint(&context, at: c, marker: style.originMarker)
        case .delivery:
            paintEndpoint(&context, at: c, marker: style.destMarker)
        case .weather:
            // Bespoke storm marker — danger disc + amber bolt (the WeatherIcons storm grammar at map scale).
            let r: CGFloat = 7.5
            let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            context.fill(disc, with: .color(Color(hex: "#FF5A4D")))
            context.stroke(disc, with: .color(.white.opacity(0.9)), lineWidth: 1.4)
            var bolt = Path()
            bolt.move(to: CGPoint(x: c.x + 1.6, y: c.y - 4.2))
            bolt.addLine(to: CGPoint(x: c.x - 2.6, y: c.y + 0.6))
            bolt.addLine(to: CGPoint(x: c.x - 0.2, y: c.y + 0.6))
            bolt.addLine(to: CGPoint(x: c.x - 1.6, y: c.y + 4.2))
            bolt.addLine(to: CGPoint(x: c.x + 2.9, y: c.y - 1.1))
            bolt.addLine(to: CGPoint(x: c.x + 0.5, y: c.y - 1.1))
            bolt.closeSubpath()
            context.fill(bolt, with: .color(Color(hex: "#FFD24A")))
        default:
            // Branded teardrop-equivalent: a filled disc in the kind's hue with
            // a white core, matching the HERE marker color palette.
            let hex = HereMarkerStyle.color(kind)
            let tint = Color(hex: hex)
            let r: CGFloat = 7
            let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            context.fill(disc, with: .color(tint))
            let core = Path(ellipseIn: CGRect(x: c.x - r * 0.5, y: c.y - r * 0.5, width: r, height: r))
            context.fill(core, with: .color(.white.opacity(0.92)))
            context.stroke(disc, with: .color(.white.opacity(0.85)), lineWidth: 1.4)
        }
    }

    /// STANDARD-register live puck (.dark / .light): halo + ring + a cab+box
    /// two-rect truck silhouette. NO green status dot anywhere. `phase`
    /// drives the canon halo pulse (222: r12→22→12 / opacity 0.9→0.3→0.9
    /// over 2.2 s; AIS surfaces keep their 2.4 s rhythm).
    ///
    /// DESIGN-AUTHORITY SANCTION (W13 hygiene · E2E audit §4 · 2026-06-10):
    /// the hand-drawn vehicle Paths below (nav arrowhead, vessel top-down
    /// hull + container slots, AIS hull chevron, cab+box truck silhouette)
    /// are wireframe-VERBATIM puck glyphs transcribed 1:1 from the canon
    /// SVG wireframes (035 / 660 / 003 / 222) per _MAP_DESIGN_LANGUAGE_
    /// 2026-06-09. They are map-scale position pucks (≤ ~20 pt) drawn in a
    /// single GraphicsContext pass — NOT equipment renders — so the
    /// canonical-equipment-model mandate (Animation Design System via
    /// NativeSVGView) does not apply at this dimension; full-size vehicle
    /// markers (560/643/003 live-position cars) keep the canonical models.
    /// Any change to these paths must re-derive from the wireframes, never
    /// freehand.
    static func paintTruck(
        _ context: inout GraphicsContext,
        at c: CGPoint,
        truck: BespokeMapStyle.TruckMarker,
        phase: PulsePhase = .still
    ) {
        switch truck.glyph {
        case .navArrow:
            // 035 own-truck halo: a FLAT eusoDiagonal disc at haloOpacity —
            // the wireframe authors it static (no pulse on the nav puck).
            let halo = Path(ellipseIn: CGRect(
                x: c.x - truck.haloRadius, y: c.y - truck.haloRadius,
                width: truck.haloRadius * 2, height: truck.haloRadius * 2))
            let stops = truck.haloStops.map { $0.opacity(truck.haloOpacity) }
            context.fill(
                halo,
                with: .linearGradient(
                    Gradient(colors: stops),
                    startPoint: CGPoint(x: c.x - truck.haloRadius, y: c.y + truck.haloRadius),
                    endPoint: CGPoint(x: c.x + truck.haloRadius, y: c.y - truck.haloRadius)
                )
            )
        case .vesselTopDown:
            // 660 AIS pulse: a FLAT #2BE0B0 disc breathing r7→15 / opacity
            // 0.35→0 over 2.4 s. The static frame is the authored r7 @0.35.
            let minFrac = 7.0 / 15.0
            let tri = phase.animated ? pulseTriangle(phase.pulse24) : 0
            let r = truck.haloRadius * CGFloat(minFrac + (1 - minFrac) * tri)
            let op = truck.haloOpacity * (1 - tri)
            let pulse = Path(ellipseIn: CGRect(
                x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            context.fill(pulse, with: .color((truck.haloStops.first ?? Color(hex: 0x2BE0B0)).opacity(op)))
        case .cabBox, .aisHull:
            // Halo — radial gradient out to the pulsing radius. Canon pulse
            // (222): r12→22→12 with the layer fading 0.9→0.3→0.9 over 2.2 s
            // (AIS orb: 2.4 s). The static frame keeps the full authored halo.
            let minFrac = 12.0 / 22.0
            let saw = truck.glyph == .aisHull ? phase.pulse24 : phase.pulse22
            let tri = phase.animated ? pulseTriangle(saw) : 1.0
            let fade = phase.animated ? (0.9 - 0.6 * tri) : 1.0
            let haloR = truck.haloRadius * CGFloat(minFrac + (1 - minFrac) * tri)
            let halo = Path(ellipseIn: CGRect(
                x: c.x - haloR, y: c.y - haloR,
                width: haloR * 2, height: haloR * 2))
            let haloGrad = Gradient(stops: [
                Gradient.Stop(color: (truck.haloStops.first ?? Brand.blue).opacity(truck.haloOpacity * fade), location: 0.0),
                Gradient.Stop(color: (truck.haloStops.last ?? Brand.magenta).opacity(truck.haloOpacity * 0.6 * fade), location: 0.6),
                Gradient.Stop(color: (truck.haloStops.last ?? Brand.magenta).opacity(0.0), location: 1.0)
            ])
            context.fill(halo, with: .radialGradient(haloGrad, center: c, startRadius: 0, endRadius: haloR))
        }

        // NAV own-truck puck (VERBATIM 035): r17 disc + hairline ring + the
        // eusoDiagonal heading-up arrowhead `M0 -9 L8 9 L0 4 L-8 9 Z`.
        if truck.glyph == .navArrow {
            let ring = Path(ellipseIn: CGRect(
                x: c.x - truck.ringRadius, y: c.y - truck.ringRadius,
                width: truck.ringRadius * 2, height: truck.ringRadius * 2))
            context.fill(ring, with: .color(truck.ringFill))
            context.stroke(ring, with: .color(truck.ringStroke), lineWidth: truck.ringWidth)
            let u = truck.ringRadius / 17.0
            var arrow = Path()
            arrow.move(to: CGPoint(x: c.x, y: c.y - 9 * u))
            arrow.addLine(to: CGPoint(x: c.x + 8 * u, y: c.y + 9 * u))
            arrow.addLine(to: CGPoint(x: c.x, y: c.y + 4 * u))
            arrow.addLine(to: CGPoint(x: c.x - 8 * u, y: c.y + 9 * u))
            arrow.closeSubpath()
            context.fill(
                arrow,
                with: .linearGradient(
                    Gradient(colors: truck.coreGradient ?? BespokeMapStyle.routeGradientStops),
                    startPoint: CGPoint(x: c.x - 8 * u, y: c.y + 9 * u),
                    endPoint: CGPoint(x: c.x + 8 * u, y: c.y - 9 * u)
                )
            )
            return
        }

        // PORT-APPROACH AIS vessel (VERBATIM 660): the canonical container-
        // vessel top-down hull `M-14 -4 H6 L14 0 L6 4 H-14 Z` (ringFill body,
        // ringStroke outline) + the canon container-slot fills + the bridge.
        if truck.glyph == .vesselTopDown {
            let u = truck.ringRadius / 14.0
            var hull = Path()
            hull.move(to: CGPoint(x: c.x - 14 * u, y: c.y - 4 * u))
            hull.addLine(to: CGPoint(x: c.x + 6 * u, y: c.y - 4 * u))
            hull.addLine(to: CGPoint(x: c.x + 14 * u, y: c.y))
            hull.addLine(to: CGPoint(x: c.x + 6 * u, y: c.y + 4 * u))
            hull.addLine(to: CGPoint(x: c.x - 14 * u, y: c.y + 4 * u))
            hull.closeSubpath()
            context.fill(hull, with: .color(truck.ringFill))
            context.stroke(hull, with: .color(truck.ringStroke),
                           style: StrokeStyle(lineWidth: truck.ringWidth, lineJoin: .round))
            // Container slots — canon hue row #1473FF · #9C27B0 · #E2A33C ·
            // #2BB673 (660 §3b), authored at (x, w): (-12, 3.8) (-7.6, 3.8)
            // (-3.2, 3.8) (1.2, 3.0), y -3 h6 rx0.6.
            let slots: [(x: CGFloat, w: CGFloat, hue: UInt32)] = [
                (-12.0, 3.8, 0x1473FF),
                (-7.6, 3.8, 0x9C27B0),
                (-3.2, 3.8, 0xE2A33C),
                (1.2, 3.0, 0x2BB673)
            ]
            for s in slots {
                let rect = CGRect(x: c.x + s.x * u, y: c.y - 3 * u, width: s.w * u, height: 6 * u)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 0.6 * u, style: .continuous),
                    with: .color(Color(hex: s.hue))
                )
            }
            // Bridge block at the stern-side, glyph-tinted (#F5F5F7).
            let bridge = CGRect(x: c.x + 4.8 * u, y: c.y - 2.2 * u, width: 2.2 * u, height: 4.4 * u)
            context.fill(
                Path(roundedRect: bridge, cornerRadius: 0.6 * u, style: .continuous),
                with: .color(truck.glyphColor)
            )
            return
        }

        // OCEAN AIS orb (VERBATIM 003): r11 eusoDiagonal core disc (NO ring
        // stroke) + a white hull chevron (`M-7 -1 H7 L4 5 H-4 Z`) with a small
        // bridge rect on top. The gradient IS the body — there is no flat ring.
        if truck.glyph == .aisHull {
            let cr = truck.ringRadius
            let core = Path(ellipseIn: CGRect(x: c.x - cr, y: c.y - cr, width: cr * 2, height: cr * 2))
            context.fill(
                core,
                with: .linearGradient(
                    Gradient(colors: truck.coreGradient ?? BespokeMapStyle.routeGradientStops),
                    startPoint: CGPoint(x: c.x - cr, y: c.y + cr),
                    endPoint: CGPoint(x: c.x + cr, y: c.y - cr)
                )
            )
            // Hull chevron, scaled off the SVG's 14pt-wide authored glyph.
            let u = cr / 11.0
            var hull = Path()
            hull.move(to: CGPoint(x: c.x - 7 * u, y: c.y - 1 * u))
            hull.addLine(to: CGPoint(x: c.x + 7 * u, y: c.y - 1 * u))
            hull.addLine(to: CGPoint(x: c.x + 4 * u, y: c.y + 5 * u))
            hull.addLine(to: CGPoint(x: c.x - 4 * u, y: c.y + 5 * u))
            hull.closeSubpath()
            context.fill(hull, with: .color(truck.glyphColor))
            let bridge = Path(roundedRect: CGRect(
                x: c.x - 3 * u, y: c.y - 5 * u, width: 6 * u, height: 3 * u),
                cornerRadius: 0.6 * u, style: .continuous)
            context.fill(bridge, with: .color(truck.glyphColor))
            return
        }

        // Ring — filled core disc + token stroke.
        let ring = Path(ellipseIn: CGRect(
            x: c.x - truck.ringRadius, y: c.y - truck.ringRadius,
            width: truck.ringRadius * 2, height: truck.ringRadius * 2))
        context.fill(ring, with: .color(truck.ringFill))
        context.stroke(ring, with: .color(truck.ringStroke), lineWidth: truck.ringWidth)

        // Truck glyph = a CAB + BOX two-rect silhouette (NOT a chevron/arrow).
        // box (~9×6) trails a smaller cab (~5×8); both centered on the puck.
        let unit = truck.ringRadius / 9.0           // scale glyph to the ring
        let boxW = 9 * unit, boxH = 6 * unit
        let cabW = 5 * unit, cabH = 8 * unit
        let gap = 1.0 * unit
        let totalW = boxW + gap + cabW
        let originX = c.x - totalW / 2
        let boxRect = CGRect(x: originX, y: c.y - boxH / 2, width: boxW, height: boxH)
        let cabRect = CGRect(x: originX + boxW + gap, y: c.y - cabH / 2, width: cabW, height: cabH)
        var glyph = Path()
        glyph.addRect(boxRect)
        glyph.addRect(cabRect)
        context.fill(glyph, with: .color(truck.glyphColor))
        // (NO green status dot — removed in all registers.)
    }

    /// DRIVER-register live puck (.cosmos / .lightDriver): a soft radial halo
    /// (pulse) + gradient core disc + two concentric rings. NO chevron, NO dot.
    /// `phase` drives the canon halo pulse (same 2.2 s out-and-back sweep as
    /// the board puck, scaled to the register's halo radius).
    static func paintPing(
        _ context: inout GraphicsContext,
        at c: CGPoint,
        ping: BespokeMapStyle.PingMarker,
        phase: PulsePhase = .still
    ) {
        // Pulse halo — radial center color fading to clear at the rim. The
        // canon pulse breathes the radius (12/22 → full) with the layer
        // fading 0.9→0.3→0.9; the static frame keeps the authored full halo.
        let minFrac = 12.0 / 22.0
        let tri = phase.animated ? pulseTriangle(phase.pulse22) : 1.0
        let fade = phase.animated ? (0.9 - 0.6 * tri) : 1.0
        let haloR = ping.haloRadius * CGFloat(minFrac + (1 - minFrac) * tri)
        let halo = Path(ellipseIn: CGRect(
            x: c.x - haloR, y: c.y - haloR,
            width: haloR * 2, height: haloR * 2))
        let haloGrad = Gradient(stops: [
            Gradient.Stop(color: ping.haloColor.opacity(ping.haloOpacity * fade), location: 0.0),
            Gradient.Stop(color: ping.haloColor.opacity(0.0), location: 1.0)
        ])
        context.fill(halo, with: .radialGradient(haloGrad, center: c, startRadius: 0, endRadius: haloR))

        // Core disc — eusoDiagonal gradient (fixed map-space sweep).
        let core = Path(ellipseIn: CGRect(
            x: c.x - ping.coreRadius, y: c.y - ping.coreRadius,
            width: ping.coreRadius * 2, height: ping.coreRadius * 2))
        context.fill(
            core,
            with: .linearGradient(
                Gradient(colors: ping.coreGradient),
                startPoint: CGPoint(x: c.x - ping.coreRadius, y: c.y + ping.coreRadius),
                endPoint: CGPoint(x: c.x + ping.coreRadius, y: c.y - ping.coreRadius)
            )
        )

        // Two concentric rings around the core.
        context.stroke(core, with: .color(ping.ringInnerColor), lineWidth: ping.ringInnerWidth)
        let outerRing = Path(ellipseIn: CGRect(
            x: c.x - ping.coreRadius - ping.ringInnerWidth,
            y: c.y - ping.coreRadius - ping.ringInnerWidth,
            width: (ping.coreRadius + ping.ringInnerWidth) * 2,
            height: (ping.coreRadius + ping.ringInnerWidth) * 2))
        context.stroke(outerRing, with: .color(ping.ringOuterColor), lineWidth: ping.ringOuterWidth)
        // (NO green status dot, NO chevron.)
    }

    // MARK: 5 — Callout pills (authored labels + computed scale pill)

    /// Paint a single authored / coordinate label pill at a pre-projected
    /// `anchor`. `Text` resolution + measure happen here (few, capped labels).
    static func paintPill(
        _ context: inout GraphicsContext,
        anchor: CGPoint,
        text: String,
        style: BespokeMapStyle,
        above: Bool
    ) {
        // Resolve the label text (mono for coordinate readouts, body otherwise).
        let isCoord = text.contains(",") && text.allSatisfy { $0.isNumber || $0 == "." || $0 == "-" || $0 == "," || $0 == " " }
        var resolved = context.resolve(
            Text(text)
                .font(.system(
                    size: isCoord ? style.pill.monoTextSize : style.pill.textSize,
                    weight: .medium,
                    design: isCoord ? .monospaced : .default))
                .foregroundColor(style.pill.textPrimary)
        )
        let textSize = resolved.measure(in: CGSize(width: 220, height: 40))
        let padH: CGFloat = 8
        let padV: CGFloat = 5
        let pillW = textSize.width + padH * 2
        let pillH = textSize.height + padV * 2
        let gap: CGFloat = style.originMarker.outerRadius + 8
        let pillRect = CGRect(
            x: anchor.x - pillW / 2,
            y: (above ? anchor.y - gap - pillH : anchor.y + gap),
            width: pillW, height: pillH)

        let pillPath = Path(roundedRect: pillRect, cornerRadius: style.pill.cornerRadius, style: .continuous)
        context.fill(pillPath, with: .color(style.pill.fill))
        context.stroke(pillPath, with: .color(style.pill.borderColor), lineWidth: style.pill.borderWidth)
        resolved.shading = .color(style.pill.textPrimary)
        context.draw(resolved, in: CGRect(
            x: pillRect.minX + padH, y: pillRect.minY + padV,
            width: textSize.width, height: textSize.height))
    }

    /// A computed "N MI" scale pill (driver registers only), bottom-leading.
    /// The mileage was resolved once in `RenderModel.build`; here we only lay
    /// out + draw the pill.
    static func paintScalePill(
        _ context: inout GraphicsContext,
        rect: CGRect,
        text: String,
        style: BespokeMapStyle
    ) {
        var resolved = context.resolve(
            Text(text)
                .font(.system(size: style.pill.monoTextSize, weight: .semibold, design: .monospaced))
                .foregroundColor(style.pill.textPrimary)
        )
        let textSize = resolved.measure(in: CGSize(width: 160, height: 30))
        let padH: CGFloat = 8
        let padV: CGFloat = 5
        let pillW = textSize.width + padH * 2
        let pillH = textSize.height + padV * 2
        let margin: CGFloat = 12
        let pillRect = CGRect(
            x: rect.minX + margin,
            y: rect.maxY - margin - pillH,
            width: pillW, height: pillH)

        let pillPath = Path(roundedRect: pillRect, cornerRadius: style.pill.cornerRadius, style: .continuous)
        context.fill(pillPath, with: .color(style.pill.fill))
        context.stroke(pillPath, with: .color(style.pill.borderColor), lineWidth: style.pill.borderWidth)
        resolved.shading = .color(style.pill.textPrimary)
        context.draw(resolved, in: CGRect(
            x: pillRect.minX + padH, y: pillRect.minY + padV,
            width: textSize.width, height: textSize.height))
    }

    // MARK: Formatting

    static func coordText(_ c: HereLatLng) -> String {
        guard let coordinate = LatLongParser.validatedCoordinate(
            latitude: c.lat,
            longitude: c.lng
        ) else { return "Location unavailable" }
        return LatLongParser.displayString(coordinate)
    }

    static func coordKey(_ c: HereLatLng) -> String {
        guard let coordinate = LatLongParser.validatedCoordinate(
            latitude: c.lat,
            longitude: c.lng
        ) else { return "unavailable" }
        return "\(coordinate.latitude),\(coordinate.longitude)"
    }

    /// Round a raw mileage to a clean 1 / 2 / 5 × 10ⁿ magnitude for the bar.
    static func niceScale(_ miles: Double) -> Double {
        guard miles.isFinite, miles > 0 else { return 1 }
        let exp = floor(log10(miles))
        let base = pow(10.0, exp)
        let frac = miles / base
        let mult: Double
        if frac < 1.5 { mult = 1 }
        else if frac < 3.5 { mult = 2 }
        else if frac < 7.5 { mult = 5 }
        else { mult = 10 }
        return mult * base
    }

    /// Drop a trailing ".0" so "5.0" reads "5".
    static func trimmed(_ value: Double) -> String {
        if value >= 1 { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }
}
