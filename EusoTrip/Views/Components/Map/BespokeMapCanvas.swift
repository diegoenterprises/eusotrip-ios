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
//  Draw order (matches the SVG ground truth):
//    1. background  (linear vertical gradient, or radial cosmos)
//    2. faint grid  (straight authored lines at fixed spacing — no warp)
//    3. layered horizon silhouettes (abstract — NOT real streets)
//    4. per layer:  heatmap → adZones → route (active + pending) →
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
/// Vessel 003 "Live Tracking" great-circle register (`.ocean` dark /
/// `.lightOcean` light) — the AIS orb, port pins, latitude grid, coast hints,
/// and the speed/heading/coords callout chip.
public enum BespokeMapStyleHint {
    case auto
    case ocean
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

    /// Hinted initializer: pass `style: .ocean` for the Vessel 003 great-circle
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
            let key = Self.cacheKey(layers: layers, viewport: baseViewport, isOcean: Self.isOcean(style))

            ZStack {
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
                    Self.paint(context: &context, size: canvasSize, model: model)
                }
                .background(Color.clear)
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
            .onChange(of: key) { newKey in
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
        model = RenderModel.build(size: size, style: style, viewport: viewport, layers: layers)
    }

    // MARK: Style resolution

    /// Picks the cartography register VERBATIM:
    ///   tilt > 0  (forward / first-person camera) ⇒ driver "Active Enroute"
    ///             → `.cosmos` (dark) / `.lightDriver` (light)
    ///   otherwise ⇒ flat shipper / catalyst board → `.dark` / `.light`.
    private var resolvedStyle: BespokeMapStyle {
        // Explicit ocean hint wins over the tilt heuristic — the Vessel 003
        // great-circle surface is a flat board with no first-person tilt.
        if case .ocean = style {
            return BespokeMapStyle.ocean(isDark: isDark)
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
        if !routeCoords.isEmpty {
            base = BespokeMapViewport(fitting: routeCoords, size: size, padding: 48, minZoom: 1, maxZoom: 16)
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
    /// projected scene: the layer data, the committed viewport, and whether the
    /// ocean register is active. Hashes the viewport's center/zoom/size so a new
    /// camera invalidates the cache; hashes `layers` (Hashable) so new route /
    /// marker data does too.
    static func cacheKey(layers: [HereMapLayer], viewport: BespokeMapViewport, isOcean: Bool) -> Int {
        var h = Hasher()
        h.combine(layers)
        h.combine(viewport.center.lat)
        h.combine(viewport.center.lng)
        h.combine(viewport.zoom)
        h.combine(viewport.size.width)
        h.combine(viewport.size.height)
        h.combine(isOcean)
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
            if case .route(let poly, _) = layer { out.append(contentsOf: poly) }
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
        return "\(m.kind.rawValue):\(String(format: "%.5f", m.at.lat)),\(String(format: "%.5f", m.at.lng))"
    }

    /// The live puck coordinate: the first `.truck`-kind marker across all
    /// marker layers (the AIS vessel on the ocean register, the truck on road
    /// boards). nil when no live puck is present — callers fall back to the
    /// authored route split.
    static func liveMarkerCoord(_ layers: [HereMapLayer]) -> HereLatLng? {
        for layer in layers {
            switch layer {
            case .markers(let ms), .missionPins(let ms):
                if let truck = ms.first(where: { $0.kind == .truck }) { return truck.at }
            default: break
            }
        }
        return nil
    }

    /// Index of the polyline vertex geodesically closest to `target`. Used to
    /// split the great-circle route at the live AIS position. Returns 0 for an
    /// empty polyline (degenerate-safe; the caller clamps).
    static func nearestVertexIndex(in poly: [HereLatLng], to target: HereLatLng) -> Int {
        guard !poly.isEmpty else { return 0 }
        var bestIndex = 0
        var bestDist = Double.greatestFiniteMagnitude
        for (i, v) in poly.enumerated() {
            let d = BespokeMapProjection.haversineMeters(v, target)
            if d < bestDist { bestDist = d; bestIndex = i }
        }
        return bestIndex
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

        // Basemap — projected continent rings (screen space), pre-culled to the
        // viewport, with their derived land + coast colors.
        var basemapRings: [[CGPoint]] = []
        var landColor: Color = .clear
        var coastColor: Color = .clear

        // Heatmap blobs (screen-space centers + weights), pre-culled.
        var heatBlobs: [(center: CGPoint, weight: Double)] = []

        // Ad-zone polygons (screen space) + their fill.
        var adZones: [(pts: [CGPoint], fill: Color, opacity: Double)] = []

        // Route — already-simplified + Catmull-Rom-smoothed Paths in screen
        // space, plus the FIXED map-space gradient direction.
        var routeActivePath: Path = Path()
        var routePendingPath: Path = Path()
        var routeGradStart: CGPoint = .zero
        var routeGradEnd: CGPoint = .zero
        var breadcrumbDots: [CGPoint] = []
        var hasRoute: Bool = false

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
        /// Projects continents, simplifies + smooths the route, culls + caps
        /// markers / labels, and resolves the scale pill text — once.
        static func build(
            size: CGSize,
            style: BespokeMapStyle,
            viewport: BespokeMapViewport,
            layers: [HereMapLayer]
        ) -> RenderModel {
            var m = RenderModel()
            m.size = size
            m.style = style
            m.isOcean = BespokeMapCanvas.isOcean(style)
            m.isDriverGrid = style.ping != nil
            let rect = CGRect(origin: .zero, size: size)

            // ── 1b — basemap (skipped on the open-water ocean register) ──
            if !m.isOcean {
                let isDarkRegister = BespokeMapCanvas.gridIsLight(style.grid.color)
                if isDarkRegister {
                    let a = style.ping != nil ? 0.10 : 0.16
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

            // ── 4c — route (simplify → smooth, once) ──
            let liveCoord = BespokeMapCanvas.liveMarkerCoord(layers)
            for layer in layers {
                if case .route(let poly, _) = layer, poly.count >= 2 {
                    m.buildRoute(poly: poly, style: style, viewport: viewport, liveCoord: liveCoord)
                    // Endpoints derived from route geometry.
                    m.endpoints.append((viewport.screenPoint(poly.first!), style.originMarker))
                    m.endpoints.append((viewport.screenPoint(poly.last!), style.destMarker))
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
            let labelCull = rect.insetBy(dx: -BespokeMapCanvas.labelCullMargin,
                                         dy: -BespokeMapCanvas.labelCullMargin)
            labels: for layer in layers {
                switch layer {
                case .markers(let ms), .missionPins(let ms):
                    for mk in ms {
                        guard let label = mk.label, !label.isEmpty else { continue }
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
            // Endpoint coordinate fallback (only when unlabelled).
            for layer in layers {
                if case .route(let poly, _) = layer, let first = poly.first, let last = poly.last {
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

            // ── 5b — scale pill (driver registers only) ──
            if style.pill.scalePillEnabled {
                let barPoints: CGFloat = 64
                let meters = viewport.metersPerPoint * Double(barPoints)
                let miles = meters / 1609.344
                let nice = BespokeMapCanvas.niceScale(miles)
                m.scalePillText = "\(BespokeMapCanvas.trimmed(nice)) MI"
            }

            return m
        }

        /// Build the simplified + smoothed active / pending route Paths in
        /// screen space, plus the fixed map-space gradient direction and the
        /// light-register breadcrumb dots. Mutates `self`.
        mutating func buildRoute(
            poly: [HereLatLng],
            style: BespokeMapStyle,
            viewport: BespokeMapViewport,
            liveCoord: HereLatLng?
        ) {
            guard poly.count >= 2 else { return }
            // Project once.
            let projected = poly.map { viewport.screenPoint($0) }

            // FIX 2 — simplify (Douglas–Peucker) to ~the canvas pixel
            // resolution BEFORE Catmull-Rom smoothing, so a 2000-pt HERE route
            // never spawns 2000 Bézier segments. We keep index correspondence
            // for the live-split by simplifying the screen polyline and
            // re-finding the split on the simplified set.
            let tolerance: CGFloat = 1.5   // ~1.5pt ≈ on-screen pixel resolution
            let simplified = BespokeMapCanvas.simplify(projected,
                                                       tolerance: tolerance,
                                                       cap: BespokeMapCanvas.maxRoutePoints)
            guard simplified.count >= 2 else {
                // Degenerate: a straight 2-point line, split at midpoint.
                routeActivePath = BespokeMapCanvas.smoothPath(simplified)
                routePendingPath = Path()
                hasRoute = true
                let bb = BespokeMapCanvas.boundingBox(simplified)
                routeGradStart = CGPoint(x: bb.minX, y: bb.maxY)
                routeGradEnd = CGPoint(x: bb.maxX, y: bb.minY)
                return
            }

            // Split index — geodesic nearest to the live puck, else the
            // authored 0.62 fraction. Resolve on the GEO polyline for the live
            // case, then map that fraction onto the simplified screen polyline.
            let splitIndex: Int
            if let live = liveCoord {
                let geoIdx = BespokeMapCanvas.nearestVertexIndex(in: poly, to: live)
                let frac = poly.count > 1 ? Double(geoIdx) / Double(poly.count - 1) : 0.62
                splitIndex = Swift.max(1, Swift.min(simplified.count - 1,
                                                    Int(Double(simplified.count - 1) * frac)))
            } else {
                splitIndex = Swift.max(1, Swift.min(simplified.count - 1,
                                                    Int(Double(simplified.count - 1) * 0.62)))
            }

            let activePts = Array(simplified.prefix(splitIndex + 1))
            let pendingPts = Array(simplified.suffix(from: splitIndex))

            // FIXED map-space gradient direction (bottom-leading → top-trailing)
            // over the FULL route bounds, for BOTH active + pending.
            let bounds = BespokeMapCanvas.boundingBox(simplified)
            routeGradStart = CGPoint(x: bounds.minX, y: bounds.maxY)
            routeGradEnd = CGPoint(x: bounds.maxX, y: bounds.minY)

            routeActivePath = BespokeMapCanvas.smoothPath(activePts)
            routePendingPath = BespokeMapCanvas.smoothPath(pendingPts)
            hasRoute = true

            // Light-register breadcrumbs along the traveled portion.
            if style.ping == nil, style.truckMarker?.glyphColor == Color(hex: 0x0D1117) {
                for (offset, pt) in activePts.enumerated() where offset % 2 == 0 {
                    breadcrumbDots.append(pt)
                }
            }
        }
    }
}

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
}

// MARK: - Canvas painting (static so no closures capture self)

extension BespokeMapCanvas {

    /// The full draw pipeline. Static + value-typed so the `Canvas` closure
    /// holds nothing referential. Consumes the PRECOMPUTED `RenderModel` — it
    /// only re-emits cheap chrome (background / grid / silhouettes) and
    /// rasterizes already-projected geometry. No projection, no simplify, no
    /// smoothing happens here.
    static func paint(
        context: inout GraphicsContext,
        size: CGSize,
        model: RenderModel
    ) {
        let rect = CGRect(origin: .zero, size: size)
        let style = model.style

        // 1 — background
        paintBackground(&context, rect: rect, bg: style.background)

        // 1b — basemap (pre-projected rings).
        if !model.isOcean {
            paintBasemap(&context, model: model)
        }

        // 2 — faint grid.
        paintGrid(&context, rect: rect, grid: style.grid, isDriver: model.isDriverGrid, isOcean: model.isOcean)

        // 3 — abstract silhouettes.
        paintSilhouettes(&context, rect: rect, silhouettes: style.silhouettes, isOcean: model.isOcean)

        // 4a — heatmap.
        for blob in model.heatBlobs {
            paintHeatBlob(&context, center: blob.center, weight: blob.weight, maxWeight: heatMaxWeight(model))
        }
        // 4b — ad-zones.
        for z in model.adZones {
            paintAdZone(&context, pts: z.pts, fill: z.fill, opacity: z.opacity)
        }
        // 4c — route (pre-smoothed paths).
        if model.hasRoute {
            paintRoutePaths(&context, model: model)
        }
        // 4d — endpoints.
        for ep in model.endpoints {
            paintEndpoint(&context, at: ep.at, marker: ep.marker)
        }
        // 4e — generic markers (culled + capped).
        for mk in model.markers {
            paintMarker(&context, at: mk.at, kind: mk.kind, style: style)
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
                style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round)
            )
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
        isOcean: Bool = false
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
        let hSpacing: CGFloat = isDriver ? 44 : 60   // vertical line spacing (columns)
        let vSpacing: CGFloat = isDriver ? 44 : 80   // horizontal line spacing (rows)

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
        isOcean: Bool = false
    ) {
        guard let s = silhouettes else { return }
        let w0 = rect.width, h0 = rect.height
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
        let radius = CGFloat(28 + 46 * weight)
        let coreOpacity = 0.10 + 0.34 * weight
        let blob = Path(ellipseIn: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2))
        let g = Gradient(stops: [
            Gradient.Stop(color: Brand.magenta.opacity(coreOpacity), location: 0.0),
            Gradient.Stop(color: Brand.blue.opacity(coreOpacity * 0.7), location: 0.45),
            Gradient.Stop(color: Brand.blue.opacity(0.0), location: 1.0)
        ])
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

    // MARK: 4c — Route (solid traveled + dashed remaining; NO glow underlay)

    /// Stroke the PRE-smoothed active + pending route Paths from the model.
    /// No simplify / smoothing here — that ran once in `RenderModel.build`.
    static func paintRoutePaths(_ context: inout GraphicsContext, model: RenderModel) {
        let style = model.style
        let gradStart = model.routeGradStart
        let gradEnd = model.routeGradEnd

        // Active — iridescent gradient, solid, round caps.
        let routeGradient = GraphicsContext.Shading.linearGradient(
            Gradient(colors: style.routeActive.stops),
            startPoint: gradStart,
            endPoint: gradEnd
        )
        context.stroke(
            model.routeActivePath,
            with: routeGradient,
            style: StrokeStyle(lineWidth: style.routeActive.width, lineCap: .round, lineJoin: .round)
        )

        // Pending — dashed, gradient (if present) else flat color, round caps.
        let pendingShading: GraphicsContext.Shading
        if let stops = style.routePending.stops, !stops.isEmpty {
            pendingShading = .linearGradient(
                Gradient(colors: stops),
                startPoint: gradStart,
                endPoint: gradEnd
            )
        } else {
            pendingShading = .color(style.routePending.color)
        }
        context.stroke(
            model.routePendingPath,
            with: pendingShading,
            style: StrokeStyle(
                lineWidth: style.routePending.width,
                lineCap: .round,
                lineJoin: .round,
                dash: style.routePending.dashPattern
            )
        )

        // Light decoration: breadcrumbs sprinkled along the traveled portion.
        for pt in model.breadcrumbDots {
            let dot = Path(ellipseIn: CGRect(
                x: pt.x - BespokeMapStyle.lightBreadcrumbRadius,
                y: pt.y - BespokeMapStyle.lightBreadcrumbRadius,
                width: BespokeMapStyle.lightBreadcrumbRadius * 2,
                height: BespokeMapStyle.lightBreadcrumbRadius * 2))
            context.fill(dot, with: .color(BespokeMapStyle.lightBreadcrumbColor))
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

    /// A smooth (Catmull-Rom-ish) path through screen points. Falls back to a
    /// straight polyline for < 3 points.
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

        // VERBATIM: a glass-pill + rounded-diamond destination glyph replaces the
        // concentric circles entirely when present (cosmos / lightDriver dest).
        if let dp = marker.destPill {
            paintDestPill(&context, at: c, pill: dp)
            return
        }

        // VERBATIM (ocean 003): a HOLLOW port pin — `outerFill` center disc
        // (page bg) with a thick `ringStroke` ring AT `outerRadius`, no inner
        // core. Origin ring = eusoPrimary, dest ring = #6E7681 / #8A96A3.
        if let ringStroke = marker.ringStroke, marker.ringWidth > 0 {
            let ring = Path(ellipseIn: CGRect(
                x: c.x - marker.outerRadius, y: c.y - marker.outerRadius,
                width: marker.outerRadius * 2, height: marker.outerRadius * 2))
            context.fill(ring, with: .color(marker.outerFill))
            context.stroke(ring, with: .color(ringStroke), lineWidth: marker.ringWidth)
            return
        }

        // Standard concentric origin / dest.
        let outer = Path(ellipseIn: CGRect(
            x: c.x - marker.outerRadius, y: c.y - marker.outerRadius,
            width: marker.outerRadius * 2, height: marker.outerRadius * 2))
        context.fill(outer, with: .color(marker.outerFill))

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
        style: BespokeMapStyle
    ) {
        switch kind {
        case .truck:
            // Exactly ONE puck per register: truck on standard, ping on driver.
            if let truck = style.truckMarker {
                paintTruck(&context, at: c, truck: truck)
            } else if let ping = style.ping {
                paintPing(&context, at: c, ping: ping)
            }
        case .pickup:
            paintEndpoint(&context, at: c, marker: style.originMarker)
        case .delivery:
            paintEndpoint(&context, at: c, marker: style.destMarker)
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
    /// two-rect truck silhouette. NO green status dot anywhere.
    static func paintTruck(
        _ context: inout GraphicsContext,
        at c: CGPoint,
        truck: BespokeMapStyle.TruckMarker
    ) {
        // Halo — radial gradient out to haloRadius at haloOpacity.
        let halo = Path(ellipseIn: CGRect(
            x: c.x - truck.haloRadius, y: c.y - truck.haloRadius,
            width: truck.haloRadius * 2, height: truck.haloRadius * 2))
        let haloGrad = Gradient(stops: [
            Gradient.Stop(color: (truck.haloStops.first ?? Brand.blue).opacity(truck.haloOpacity), location: 0.0),
            Gradient.Stop(color: (truck.haloStops.last ?? Brand.magenta).opacity(truck.haloOpacity * 0.6), location: 0.6),
            Gradient.Stop(color: (truck.haloStops.last ?? Brand.magenta).opacity(0.0), location: 1.0)
        ])
        context.fill(halo, with: .radialGradient(haloGrad, center: c, startRadius: 0, endRadius: truck.haloRadius))

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
    static func paintPing(
        _ context: inout GraphicsContext,
        at c: CGPoint,
        ping: BespokeMapStyle.PingMarker
    ) {
        // Pulse halo — radial center color fading to clear at the rim.
        let halo = Path(ellipseIn: CGRect(
            x: c.x - ping.haloRadius, y: c.y - ping.haloRadius,
            width: ping.haloRadius * 2, height: ping.haloRadius * 2))
        let haloGrad = Gradient(stops: [
            Gradient.Stop(color: ping.haloColor.opacity(ping.haloOpacity), location: 0.0),
            Gradient.Stop(color: ping.haloColor.opacity(0.0), location: 1.0)
        ])
        context.fill(halo, with: .radialGradient(haloGrad, center: c, startRadius: 0, endRadius: ping.haloRadius))

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
        String(format: "%.4f, %.4f", c.lat, c.lng)
    }

    static func coordKey(_ c: HereLatLng) -> String {
        String(format: "%.4f,%.4f", c.lat, c.lng)
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
