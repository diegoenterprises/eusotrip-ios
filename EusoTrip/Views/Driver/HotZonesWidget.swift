//
//  HotZonesWidget.swift
//  EusoTrip — Driver Home Hot Zones widget.
//
//  Twin of the web platform's `/hot-zones` page (frontend/client/src/pages/
//  HotZones.tsx). The web surface is a full-page heatmap + rate feed; this
//  widget condenses the same intelligence into a glanceable tile that sits
//  under the Recent activity card on DriverHome.
//
//  Pulls live data from the same tRPC procedure (`hotZones.getRateFeed`)
//  so drivers see the exact same load-to-truck ratios, live $/mile rates,
//  surge multipliers, and demand levels that dispatch sees on the web.
//
//  Composition:
//    • Header           — gradient flame glyph + "HOT ZONES" micro label +
//                         pulsing live dot + "See all" link.
//    • Pulse strip      — market avgRate · critical-zone count · avgRatio.
//    • HERE heatmap     — WKWebView hosting HERE Maps JS v3.1. The
//                         heatmap is rendered natively by HERE via
//                         `H.data.heatmap.Provider` (true density
//                         heatmap, pixel-parity with the web
//                         `/hot-zones` page). Basemap is HERE's
//                         `normal.day` / `normal.night` vector style —
//                         no MapKit, no Apple POIs, no colour drift
//                         between mobile and web. The MKMapView
//                         workaround (radial-gradient overlays over
//                         HERE raster tiles) is retired in Build 49.
//    • Zone chips       — horizontal carousel of the top 3-5 zones, each
//                         with rank dot, zone name/state, demand badge,
//                         live rate + delta, and surge bar.
//    • Tap any zone     — presents `HotZonesDetailSheet` with the full
//                         breakdown mirroring the web detail panel.
//
//  Design: matches DriverHome's ActiveCard rhythm (Radius.xl, gradient
//  border, paired brand shadows). No stock iconography — all glyphs are
//  SF Symbols hand-picked to read well at 10-12pt against the brand
//  gradient.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import WebKit
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - HotZonesStore

/// ObservableObject that hydrates `hotZones.getRateFeed` and exposes the
/// feed + market pulse to the widget. Mirrors the web page's
/// stale-while-revalidate pattern — first paint from the last cached
/// feed, then a background refresh on widget appear.
@MainActor
final class HotZonesStore: ObservableObject {
    @Published var zones: [HotZoneEntry] = []
    @Published var marketPulse: HotZonesMarketPulse?
    @Published var feedSource: String?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var lastLoadedAt: Date?

    /// Equipment filter applied to the feed. When set, only zones whose
    /// `topEquipment` contains this code are returned by the server.
    @Published var equipmentFilter: String?

    /// How long a cached feed is considered fresh before a background
    /// refresh kicks in on `.onAppear`. Matches the web page's 5-min TTL.
    private let staleAfter: TimeInterval = 300

    /// True stale-while-revalidate: when there's already cached data,
    /// surface it immediately AND fire a background refresh so the next
    /// frame paints with fresh server values. The previous behavior
    /// short-circuited inside the 5-minute TTL window, which froze the
    /// widget on the first feed snapshot for any tab away & back within
    /// that window — exactly the "old stale data" the driver was seeing.
    func bootstrap() async {
        async let fuel: Void = refreshFuel()
        await refresh()
        _ = await fuel
    }

    /// Force a full refresh regardless of cache state.
    ///
    /// Why no in-flight short-circuit: the previous version had
    /// `if isLoading { return }` which made every concurrent caller
    /// (.task firing alongside .onAppear, or rapid tab-back) silently
    /// no-op and the widget froze on whichever fetch happened to be
    /// in flight at the moment. The driver experience was "data
    /// reverts to old stale data" — actually, the new fetch was
    /// being skipped entirely and the prior load's values stayed.
    /// Now we let concurrent refreshes overlap: last-write-wins on
    /// `zones` / `marketPulse`, which is fine because `getRateFeed`
    /// is idempotent.
    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let feed = try await EusoTripAPI.shared.hotZones
                .getRateFeed(equipment: equipmentFilter)
            // Sort by live ratio (load-to-truck pressure) desc so the
            // tightest markets rise to the top of the widget carousel.
            self.zones = feed.zones.sorted { $0.liveRatio > $1.liveRatio }
            // Preserve the last good marketPulse if the server didn't
            // include one this round — without this guard the strip
            // briefly read "AVG RATE $0.00 / CRITICAL 0 zones / L/T
            // 0.0x" between fetches, which is what the driver was
            // perceiving as "old stale data".
            if let pulse = feed.marketPulse {
                self.marketPulse = pulse
            }
            self.feedSource = feed.feedSource
            self.lastLoadedAt = Date()
        } catch {
            self.errorMessage = (error as? LocalizedError)?.errorDescription
                ?? String(describing: error)
        }
    }

    /// Top-N slice rendered in the carousel. Web hides the long tail too —
    /// 5 is enough to give the driver a sense of where demand is hot
    /// without pushing too much beneath the card's fold.
    func topZones(_ limit: Int = 5) -> [HotZoneEntry] {
        Array(zones.prefix(limit))
    }

    // MARK: - HERE Fuel Prices layer
    //
    // Folded into the HotZones widget at the user's direction
    // (2026-04-24): "fuel prices nearby should go in the hotzones
    // widget. it is already here map so it would be seamless."
    //
    // The widget doesn't care about the rate-feed API for this — it
    // calls HERE Fuel Prices v3 directly with a proximity query
    // centered on the driver's current CoreLocation fix. Refreshes
    // piggyback on the same `bootstrap()` call the heatmap uses, so
    // one `.task { await store.bootstrap() }` hydrates both layers.
    //
    // Empty result + error both fall through to `fuelStations = []`
    // so the widget's fuel strip silently hides when there's no
    // data (matches the §3 "no fake data" doctrine).

    /// Stations returned by `HereFuelPricesClient.nearby` for the
    /// driver's current fix. Sorted ascending by cheapest diesel
    /// price so the first element is the best deal nearby.
    @Published private(set) var fuelStations: [HereFuelStation] = []

    /// Timestamp of the most recent successful fuel fetch. Reused
    /// by the existing `staleAfter` cache gate — refreshes piggy
    /// on the heatmap's TTL so we don't double-poll.
    private var fuelLoadedAt: Date?

    /// Cheapest diesel price at any of the fetched stations. nil
    /// when HERE returned no diesel-bearing stations.
    var cheapestDieselStation: HereFuelStation? {
        fuelStations
            .compactMap { station -> (HereFuelStation, HereFuelPrice)? in
                guard let price = station.cheapestDieselPrice else { return nil }
                return (station, price)
            }
            .min { $0.1.price < $1.1.price }?
            .0
    }

    /// Fetches up to 20 diesel-bearing stations within 40 km of the
    /// driver's current fix. Silently no-ops when CoreLocation is
    /// denied / unavailable — the UI hides its fuel strip in that
    /// case instead of flashing an error banner.
    func refreshFuel() async {
        guard let coord = await DriverLocationResolver.shared.currentCoordinate() else {
            return
        }
        do {
            let stations = try await HereFuelPricesClient.shared.nearby(
                center: coord,
                radiusMeters: 40_000
            )
            self.fuelStations = stations
                .sorted { lhs, rhs in
                    let l = lhs.cheapestDieselPrice?.price ?? .infinity
                    let r = rhs.cheapestDieselPrice?.price ?? .infinity
                    return l < r
                }
            self.fuelLoadedAt = Date()
        } catch {
            // Don't clobber the main `errorMessage` — fuel is
            // ancillary to the heatmap hero. Leave prior stations
            // in place so a transient HERE outage doesn't blank
            // the strip mid-scroll.
        }
    }
}

// MARK: - Demand level helpers

/// Shared style tokens for the three demand tiers the backend emits.
/// Pulled out of the widget + detail sheet so the badge, chip accent,
/// and heatmap overlay all read the same colour for the same tier.
enum HotZoneDemand {
    case critical, high, elevated, unknown

    init(_ raw: String) {
        switch raw.uppercased() {
        case "CRITICAL": self = .critical
        case "HIGH":     self = .high
        case "ELEVATED": self = .elevated
        default:         self = .unknown
        }
    }

    var color: Color {
        switch self {
        case .critical: return Brand.danger
        case .high:     return Brand.warning
        case .elevated: return Color(red: 1.0, green: 0.76, blue: 0.20) // amber
        case .unknown:  return Brand.info
        }
    }

    var uiColor: UIColor { UIColor(color) }

    var label: String {
        switch self {
        case .critical: return "CRITICAL"
        case .high:     return "HIGH"
        case .elevated: return "ELEVATED"
        case .unknown:  return "—"
        }
    }

    /// Patch #2 — map the demand tier onto the unified `EusoBadgeKind`.
    /// `critical` → `.hot` (gradient fill reads as "red-hot" demand),
    /// `high` / `elevated` → `.warning` (amber tint), `.unknown` → `.neutral`.
    var eusoBadgeKind: EusoBadgeKind {
        switch self {
        case .critical: return .hot
        case .high:     return .warning
        case .elevated: return .warning
        case .unknown:  return .neutral
        }
    }
}

// MARK: - HotZonesHeatmapPoint

/// A single (lat, lng, weight) sample fed into HERE's heatmap provider.
/// `weight` is a normalized >= 0 scalar — higher means a hotter sample,
/// which HERE's heatmap blends into a higher colour-ramp stop. In
/// practice the widget derives weights from `liveRatio × demandTier`,
/// clamped to a sane 0…3 range before reaching this type.
struct HotZonesHeatmapPoint: Equatable, Codable {
    let lat: Double
    let lng: Double
    let weight: Double
}

// MARK: - Legacy heat-blob overlay (removed)
//
// The prior MKOverlay/MKOverlayRenderer approach (`HeatBlobOverlay`,
// `HeatBlobRenderer`, `USAOutlineOverlay`, `USAOutlineRenderer`) was an
// MKMapView-era workaround — radial gradients drawn per-zone on top of
// HERE raster tiles. Superseded by `HotZonesHeatmapWebView` below,
// which loads HERE Maps JS v3 and renders a true density heatmap via
// `H.data.heatmap.Provider`.
//
// The MapKit blob code is intentionally dropped here; git history has
// the reference implementation if it's ever needed again. (Build 49.)
#if false
final class HeatBlobOverlay: NSObject, MKOverlay {
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    let zone: HotZoneEntry
    /// Outer radius in metres. The gradient fades from fully-saturated at
    /// the centre to transparent at `radiusMeters`.
    let radiusMeters: CLLocationDistance

    init(zone: HotZoneEntry) {
        self.zone = zone
        self.coordinate = CLLocationCoordinate2D(
            latitude: zone.center.lat, longitude: zone.center.lng
        )
        // The server-side radius is expressed in miles. Multiply by an
        // "intensity" factor so critical/high zones bleed further than
        // elevated ones — gives the heatmap its characteristic uneven
        // plume shape instead of identical discs.
        let intensity: Double
        switch HotZoneDemand(zone.demandLevel) {
        case .critical: intensity = 1.55
        case .high:     intensity = 1.30
        case .elevated: intensity = 1.10
        case .unknown:  intensity = 1.00
        }
        let rMiles = max(zone.radius, 20) * intensity
        self.radiusMeters = rMiles * 1609.34

        // Compute a bounding rect that covers the full plume so MapKit
        // invalidates the right tiles when we move/zoom.
        let center = MKMapPoint(self.coordinate)
        let mapPointsPerMeter = MKMapPointsPerMeterAtLatitude(self.coordinate.latitude)
        let side = self.radiusMeters * mapPointsPerMeter * 2.0
        self.boundingMapRect = MKMapRect(
            x: center.x - side / 2.0,
            y: center.y - side / 2.0,
            width: side,
            height: side
        )
    }
}

/// Renderer that paints a radial gradient from the zone's demand colour
/// (fully-saturated at the centre) out to transparent at the plume edge.
/// Uses `kCGBlendModePlusLighter` so overlapping plumes add — identical
/// behaviour to the web heatmap canvas layer.
final class HeatBlobRenderer: MKOverlayRenderer {
    let blob: HeatBlobOverlay

    init(overlay: HeatBlobOverlay) {
        self.blob = overlay
        super.init(overlay: overlay)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in ctx: CGContext) {
        // Convert the overlay's bounding rect into the renderer's own
        // drawing-space. Using `rect(for:)` lets MapKit handle the
        // zoomScale maths for us — the resulting CGRect already matches
        // the current tile pyramid level.
        let drawRect = rect(for: blob.boundingMapRect)
        guard drawRect.width > 4 else { return }

        let centerCG = CGPoint(x: drawRect.midX, y: drawRect.midY)
        let radiusCG = drawRect.width / 2.0

        let demand = HotZoneDemand(blob.zone.demandLevel)
        let core   = demand.uiColor
        let outer  = demand.uiColor.withAlphaComponent(0.0)

        // Intensity at the centre scales mildly with load-to-truck
        // ratio — ratio 3.0+ paints at ~0.85, calmer zones at ~0.55.
        let intensityAlpha: CGFloat = {
            let base = max(0.45, min(blob.zone.liveRatio / 3.5, 1.0)) * 0.9
            return CGFloat(base)
        }()

        let coreCGColor = core.withAlphaComponent(intensityAlpha).cgColor
        let midCGColor  = core.withAlphaComponent(intensityAlpha * 0.40).cgColor
        let outerCGColor = outer.cgColor

        // Three-stop gradient — hot core → warm halo → fully transparent.
        let colors: [CGColor] = [coreCGColor, midCGColor, outerCGColor]
        let locations: [CGFloat] = [0.0, 0.55, 1.0]

        guard let cs = core.cgColor.colorSpace,
              let grad = CGGradient(
                colorsSpace: cs,
                colors: colors as CFArray,
                locations: locations
              )
        else { return }

        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        ctx.drawRadialGradient(
            grad,
            startCenter: centerCG,
            startRadius: 0,
            endCenter: centerCG,
            endRadius: radiusCG,
            options: [.drawsAfterEndLocation]
        )
        ctx.restoreGState()

        // Thin accent ring so the centre of each zone still reads as a
        // discrete hot-spot when many plumes overlap. Matches the web
        // page's "click target" ring.
        let ringRadius = radiusCG * 0.18
        ctx.saveGState()
        ctx.setStrokeColor(core.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(max(1.0 / zoomScale, 0.25))
        ctx.strokeEllipse(in: CGRect(
            x: centerCG.x - ringRadius,
            y: centerCG.y - ringRadius,
            width: ringRadius * 2,
            height: ringRadius * 2
        ))
        ctx.restoreGState()
    }
}

// MARK: - USA Outline Overlay

/// Simplified Lower-48 silhouette rendered as an `MKPolyline` overlay so
/// the heatmap always shows recognizable US geography even when the HERE
/// tile request fails (and the map would otherwise paint as a black grid
/// with floating dots). Uses MKMapView's native projection — the outline
/// and the heat blobs share the exact same lat/lon → screen transform, so
/// there is no alignment drift.
///
/// Coordinates hand-traced at low fidelity (~55 points). Accuracy is not
/// the goal at widget zoom — recognizability is. Alaska / Hawaii are
/// intentionally omitted; the compact 190pt-tall tile frames the CONUS.
final class USAOutlineOverlay: NSObject, MKOverlay {
    let polyline: MKPolyline
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect

    override init() {
        // Simplified Lower-48 coastline + northern border + Gulf coast.
        // Traced clockwise starting from the Pacific Northwest.
        let pts: [CLLocationCoordinate2D] = [
            // Pacific NW → down the West coast
            .init(latitude: 48.98, longitude: -123.00), // Puget Sound
            .init(latitude: 46.20, longitude: -124.10), // OR/WA coast
            .init(latitude: 43.30, longitude: -124.40),
            .init(latitude: 40.40, longitude: -124.40), // N. California
            .init(latitude: 37.80, longitude: -122.50), // Bay Area
            .init(latitude: 35.00, longitude: -120.80),
            .init(latitude: 34.00, longitude: -118.50), // LA
            .init(latitude: 32.70, longitude: -117.20), // San Diego
            // Mexican border eastward
            .init(latitude: 32.55, longitude: -114.80),
            .init(latitude: 31.80, longitude: -111.00),
            .init(latitude: 31.33, longitude: -108.20),
            .init(latitude: 31.78, longitude: -106.50), // El Paso
            .init(latitude: 29.80, longitude: -101.40),
            .init(latitude: 28.50, longitude: -100.30),
            .init(latitude: 26.20, longitude: -98.20),  // Brownsville
            // Gulf coast sweep
            .init(latitude: 27.80, longitude: -97.00),
            .init(latitude: 29.40, longitude: -94.80),  // Galveston
            .init(latitude: 29.60, longitude: -91.30),
            .init(latitude: 29.20, longitude: -89.30),  // MS delta
            .init(latitude: 30.40, longitude: -88.00),
            .init(latitude: 30.10, longitude: -85.60),
            .init(latitude: 29.10, longitude: -83.00),
            // Florida peninsula
            .init(latitude: 25.20, longitude: -81.10),  // tip of FL
            .init(latitude: 26.70, longitude: -80.00),
            .init(latitude: 30.70, longitude: -81.40),  // Jacksonville
            // Atlantic coast
            .init(latitude: 32.10, longitude: -80.80),
            .init(latitude: 34.70, longitude: -76.70),  // Cape Hatteras region
            .init(latitude: 36.90, longitude: -76.00),  // Norfolk
            .init(latitude: 38.80, longitude: -75.10),
            .init(latitude: 40.50, longitude: -74.00),  // NYC
            .init(latitude: 41.30, longitude: -71.80),
            .init(latitude: 42.35, longitude: -70.90),  // Boston
            .init(latitude: 43.70, longitude: -70.10),
            .init(latitude: 44.80, longitude: -67.00),  // Maine tip
            // Northern border (Canada) heading west
            .init(latitude: 45.20, longitude: -67.80),
            .init(latitude: 45.00, longitude: -71.10),
            .init(latitude: 45.00, longitude: -74.70),
            .init(latitude: 44.10, longitude: -76.40),  // Lake Ontario
            .init(latitude: 43.10, longitude: -79.10),  // Niagara
            .init(latitude: 42.30, longitude: -82.90),  // Detroit
            .init(latitude: 45.90, longitude: -84.50),  // Straits of Mackinac
            .init(latitude: 46.80, longitude: -88.00),  // U.P.
            .init(latitude: 47.50, longitude: -90.10),  // Lake Superior
            .init(latitude: 48.00, longitude: -92.00),
            .init(latitude: 49.00, longitude: -95.15),  // NW Angle
            .init(latitude: 49.00, longitude: -104.00),
            .init(latitude: 49.00, longitude: -114.00),
            .init(latitude: 49.00, longitude: -123.00), // back to Puget
            .init(latitude: 48.98, longitude: -123.00)
        ]
        self.polyline = MKPolyline(coordinates: pts, count: pts.count)
        self.coordinate = CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35)
        self.boundingMapRect = self.polyline.boundingMapRect
        super.init()
    }
}

/// Thin stroked renderer — white at 18% opacity, 0.8pt, so the outline
/// reads as a subtle guide without competing with the dots.
final class USAOutlineRenderer: MKOverlayPathRenderer {
    init(overlay: USAOutlineOverlay) {
        super.init(overlay: overlay)
        self.strokeColor = UIColor.white.withAlphaComponent(0.18)
        self.lineWidth   = 0.8
        self.lineJoin    = .round
        self.lineCap     = .round
    }

    override func createPath() {
        guard let outline = overlay as? USAOutlineOverlay else { return }
        let line  = outline.polyline
        let count = line.pointCount
        guard count > 1 else { return }

        let path = CGMutablePath()
        let pts  = line.points()
        for i in 0..<count {
            let cg = point(for: pts[i])
            if i == 0 { path.move(to: cg) }
            else      { path.addLine(to: cg) }
        }
        self.path = path
    }
}

// MARK: - HotZonesHeatMapView

/// UIViewRepresentable wrapping MKMapView for the widget's compact
/// heatmap. The basemap is HERE Platform raster tiles — `canReplaceMapContent`
/// is set on the overlay so the Apple basemap is completely suppressed
/// (no beige land, no Apple POIs, no mixed branding). This matches the
/// WebGL heatmap on the web `/hot-zones` page: same HERE tile source,
/// same dark/light palette, same radial-gradient plume math so
/// overlapping plumes add together identically. (Build 48, 2026-04-22 —
/// promoted HERE tiles from opt-in overlay to the always-on canonical
/// basemap, removing the Apple-Maps fallback the user spotted.)
struct HotZonesHeatMapView: UIViewRepresentable {

    /// Zones to paint on top of the tile layer.
    var zones: [HotZoneEntry]
    /// Optional selected zone — ignored for now, reserved for future
    /// "tap a zone in the heatmap" wiring.
    var selectedZoneId: String? = nil
    /// Invoked when the user taps a heatmap blob.
    var onSelectZone: ((HotZoneEntry) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var tileStyle: HereTileStyle {
        colorScheme == .dark ? .dark : .light
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        weak var mapView: MKMapView?
        var tileOverlay: HereTileOverlay?
        var blobForZoneId: [String: HeatBlobOverlay] = [:]
        var onSelectZone: ((HotZoneEntry) -> Void)?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tile)
            }
            if let outline = overlay as? USAOutlineOverlay {
                return USAOutlineRenderer(overlay: outline)
            }
            if let blob = overlay as? HeatBlobOverlay {
                return HeatBlobRenderer(overlay: blob)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        /// Pick the nearest zone within its plume radius. Gives users a
        /// forgiving tap target — tapping anywhere in a hot plume opens
        /// the detail sheet for that zone.
        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            guard let map = mapView else { return }
            let pt = gr.location(in: map)
            let coord = map.convert(pt, toCoordinateFrom: map)
            let tapLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)

            var best: (HotZoneEntry, CLLocationDistance)? = nil
            for blob in blobForZoneId.values {
                let c = CLLocation(latitude: blob.coordinate.latitude,
                                   longitude: blob.coordinate.longitude)
                let d = tapLoc.distance(from: c)
                if d <= blob.radiusMeters {
                    if best == nil || d < best!.1 {
                        best = (blob.zone, d)
                    }
                }
            }
            if let zone = best?.0 {
                onSelectZone?(zone)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Lifecycle

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate              = context.coordinator
        map.showsCompass          = false
        map.showsScale            = false
        map.isRotateEnabled       = false
        map.isPitchEnabled        = false
        map.showsUserLocation     = false
        map.pointOfInterestFilter = .excludingAll
        map.isZoomEnabled         = true
        map.isScrollEnabled       = true

        context.coordinator.mapView = map
        context.coordinator.onSelectZone = onSelectZone

        // Tap → open zone detail.
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.cancelsTouchesInView = false
        map.addGestureRecognizer(tap)

        // Muted Apple basemap set as an invisible floor — HERE tiles are
        // added on top with `canReplaceMapContent = true`, so this only
        // ever shows through if a HERE tile request 404s mid-render.
        // Kept so the widget never flashes Apple's beige land tone.
        applyBrandBasemap(to: map)

        // HERE Platform raster tiles — unconditionally the basemap. Even
        // if `HereMapsConfig.hasBearerCredentials` is false (dev without
        // xcconfig), the overlay serves a transparent 1×1 PNG, which is
        // still preferable to rendering Apple Maps with a different
        // palette from the web platform. (Build 48 — removed the gate.)
        let overlay = HereTileOverlay(style: tileStyle)
        map.addOverlay(overlay, level: .aboveLabels)
        context.coordinator.tileOverlay = overlay

        // Faint USA silhouette sits between the tile layer and the heat
        // blobs. Guarantees the driver always sees recognizable geography
        // even if HERE tile requests fail — the dots are never "floating
        // on a black grid" again. Shares MKMap's projection with the
        // blobs so there is zero alignment drift.
        let outline = USAOutlineOverlay()
        map.addOverlay(outline, level: .aboveRoads)

        apply(map: map, coordinator: context.coordinator, animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.onSelectZone = onSelectZone
        applyBrandBasemap(to: map)

        // Swap the HERE tile style when the palette flips light↔dark.
        // HERE is always the basemap — we only rebuild the overlay to
        // change style, never to fall back to Apple Maps.
        if context.coordinator.tileOverlay?.style != tileStyle {
            if let old = context.coordinator.tileOverlay {
                map.removeOverlay(old)
            }
            let overlay = HereTileOverlay(style: tileStyle)
            map.addOverlay(overlay, level: .aboveLabels)
            context.coordinator.tileOverlay = overlay
        }

        apply(map: map, coordinator: context.coordinator, animated: true)
    }

    // MARK: - Basemap

    private func applyBrandBasemap(to map: MKMapView) {
        if #available(iOS 17.0, *) {
            let config = MKStandardMapConfiguration(
                elevationStyle: .flat,
                emphasisStyle: .muted
            )
            config.pointOfInterestFilter = .excludingAll
            config.showsTraffic          = false
            map.preferredConfiguration   = config
        } else {
            map.mapType = .mutedStandard
        }
    }

    // MARK: - Render

    private func apply(map: MKMapView, coordinator: Coordinator, animated: Bool) {
        // Rebuild heat-blob overlays.
        let oldBlobs = map.overlays.compactMap { $0 as? HeatBlobOverlay }
        map.removeOverlays(oldBlobs)
        coordinator.blobForZoneId.removeAll(keepingCapacity: true)

        for zone in zones {
            let blob = HeatBlobOverlay(zone: zone)
            coordinator.blobForZoneId[zone.zoneId] = blob
            map.addOverlay(blob, level: .aboveLabels)
        }

        // Fit the camera to all zones with a small inset so the full
        // national spread is visible without clipping the outer plumes.
        fitCamera(map: map, animated: animated)
    }

    private func fitCamera(map: MKMapView, animated: Bool) {
        guard !zones.isEmpty else {
            // Continental-US default framing so the map is never blank.
            let usa = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
                span:   MKCoordinateSpan(latitudeDelta: 36, longitudeDelta: 60)
            )
            map.setRegion(usa, animated: animated)
            return
        }

        var rect = MKMapRect.null
        let eps  = MKMapSize(width: 0.01, height: 0.01)
        for zone in zones {
            let pt = MKMapPoint(CLLocationCoordinate2D(
                latitude: zone.center.lat, longitude: zone.center.lng
            ))
            rect = rect.union(MKMapRect(origin: pt, size: eps))
        }
        guard !rect.isNull else { return }
        let padding = UIEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        map.setVisibleMapRect(rect, edgePadding: padding, animated: animated)
    }
}
#endif // legacy MapKit heatmap (replaced by HotZonesHeatmapWebView)

// MARK: - HotZonesHeatmapWebView

/// SwiftUI → UIKit bridge that hosts a `WKWebView` rendering a true
/// density heatmap via **HERE Maps JS v3.1** (the web platform's
/// `/hot-zones` page uses the same stack, so we get pixel-parity
/// between the driver app and dispatch).
///
/// ## HERE JS API surface used
///
/// Loader scripts (all from `https://js.api.here.com/v3/3.1/...`):
///   - `mapsjs-core.js`      — `H.service.Platform`, `H.Map`, `H.geo.Point`
///   - `mapsjs-service.js`   — default raster tile layer factory
///   - `mapsjs-ui.js`        — (optional) zoom / scale bar UI
///   - `mapsjs-data.js`      — `H.data.heatmap.Provider` + `H.map.layer.TileLayer`
///
/// Heatmap wiring (per HERE docs):
/// ```js
/// const provider = new H.data.heatmap.Provider({
///   colors:       H.data.heatmap.Colors.DEFAULT,
///   assumeValues: true,          // points carry their own `value`
///   opacity:      0.75
/// });
/// provider.addData(points);      // [{lat, lng, value}, ...]
/// map.addLayer(new H.map.layer.TileLayer(provider));
/// ```
///
/// Basemap: `normal.day` (light) / `normal.night` (dark) via
/// `platform.createDefaultLayers({tileSize: 512, ppi: 400})`.
///
/// ## Update model
///
/// The bridge posts a JSON payload (`{ points: [...] }`) to the JS
/// runtime on every `updateUIView`. The JS side tears down the old
/// heatmap provider and rebuilds it, so re-renders are O(n) in the
/// number of points — trivial at our zone counts (< 200 national).
///
/// ## Gotchas
/// - Every HERE JS script is `https://` → no ATS / mixed-content issues
///   even though `loadHTMLString` uses `about:blank` as the origin. The
///   `baseURL` is set to `https://js.api.here.com` so the sub-scripts
///   resolve cleanly.
/// - `WKWebView` swallows `console.log` — we register a JS message
///   handler (`hzLog`) so errors from the JS side surface in Xcode.
/// - If `HereMapsConfig.jsApiKey` is nil (dev build without the
///   xcconfig substitution, or before the JS-specific key has been
///   provisioned from the HERE portal) we render a graceful "key
///   missing" placeholder inside the WebView instead of silently
///   blanking.
/// - TODO(here-js-key): migrate to a JS-specific apiKey pulled from the
///   HERE portal. The REST APIs moved to OAuth2 Bearer auth on
///   2026-04-22, but `H.service.Platform` in Maps JS 3.1 does not
///   accept Bearer tokens — it still requires an apiKey. Until the
///   JS-scoped apiKey is provisioned, this widget will show its
///   "key missing" placeholder.
struct HotZonesHeatmapWebView: UIViewRepresentable {

    /// Heatmap samples rendered by HERE's density provider.
    var points: [HotZonesHeatmapPoint]

    /// Widget's current colour scheme — swaps HERE's basemap style.
    var colorScheme: ColorScheme = .light

    /// Initial camera — USA-wide framing (~39.8°N, -98.5°W, zoom 4).
    var initialCenterLat: Double = 39.8283
    var initialCenterLng: Double = -98.5795
    var initialZoom: Int = 4

    // MARK: Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        /// Most-recent points we've pushed into JS, so updateUIView can
        /// skip the postMessage when nothing changed.
        var lastPointsSignature: Int = 0
        /// `true` once the HTML's `mapReady` callback fires.
        var isMapReady: Bool = false
        /// Buffer of the latest payload we wanted to send before the
        /// map finished loading — flushed from `mapReady`.
        var pendingPayload: String?

        func userContentController(
            _ controller: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case "mapReady":
                isMapReady = true
                if let pending = pendingPayload {
                    webView?.evaluateJavaScript("window.__hzApplyPoints(\(pending));", completionHandler: nil)
                    pendingPayload = nil
                }
            case "hzLog":
                #if DEBUG
                print("[HotZonesHeatmap/JS] \(message.body)")
                #endif
            default:
                break
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: Lifecycle

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "mapReady")
        controller.add(context.coordinator, name: "hzLog")

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.allowsInlineMediaPlayback = true
        if #available(iOS 14.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false   // HERE handles pan/zoom
        webView.scrollView.bounces = false

        context.coordinator.webView = webView

        // Inline HTML with HERE's loader + heatmap glue. Base URL is set
        // to HERE's CDN origin so the relative <script src="..."> tags
        // (if anyone converts them later) resolve; absolute URLs are
        // used for clarity + ATS compliance.
        // TODO(here-js-key): migrate to a JS-specific apiKey pulled
        // from the HERE portal. HERE Maps JS 3.1 does NOT accept OAuth
        // Bearer tokens — `H.service.Platform({ apikey })` is the only
        // supported constructor. Until the JS-scoped key is wired into
        // `HERE_JS_API_KEY` in EusoTrip.xcconfig, the heatmap falls
        // back to its "key missing" placeholder.
        let html = buildHTML(
            apiKey: HereMapsConfig.jsApiKey,
            styleIsDark: colorScheme == .dark,
            centerLat: initialCenterLat,
            centerLng: initialCenterLng,
            zoom: initialZoom
        )
        webView.loadHTMLString(
            html,
            baseURL: URL(string: "https://js.api.here.com")
        )
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let signature = pointsSignature(points)
        guard signature != context.coordinator.lastPointsSignature else { return }
        context.coordinator.lastPointsSignature = signature

        let payload = encodePointsForJS(points)
        if context.coordinator.isMapReady {
            webView.evaluateJavaScript(
                "window.__hzApplyPoints(\(payload));",
                completionHandler: nil
            )
        } else {
            // Map not ready yet — queue; coordinator flushes on mapReady.
            context.coordinator.pendingPayload = payload
        }
    }

    // MARK: - JS payload helpers

    /// Encode `[HotZonesHeatmapPoint]` as a JSON array literal shaped
    /// exactly like HERE expects: `[{lat, lng, value}, …]`.
    private func encodePointsForJS(_ points: [HotZonesHeatmapPoint]) -> String {
        struct HEREPoint: Encodable {
            let lat: Double
            let lng: Double
            let value: Double
        }
        let mapped = points.map { HEREPoint(lat: $0.lat, lng: $0.lng, value: $0.weight) }
        let data = (try? JSONEncoder().encode(mapped)) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    /// Cheap signature so `updateUIView` can skip JS round-trips when
    /// the input is unchanged.
    private func pointsSignature(_ points: [HotZonesHeatmapPoint]) -> Int {
        var hasher = Hasher()
        hasher.combine(points.count)
        for p in points {
            hasher.combine(p.lat)
            hasher.combine(p.lng)
            hasher.combine(p.weight)
        }
        return hasher.finalize()
    }

    // MARK: - HTML template

    private func buildHTML(
        apiKey: String?,
        styleIsDark: Bool,
        centerLat: Double,
        centerLng: Double,
        zoom: Int
    ) -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            // No key available — render a small diagnostic placeholder
            // so we never ship a silently-blank tile to production.
            return """
            <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"/>
            <style>
              html,body { margin:0; padding:0; height:100%;
                          background:#0b0b0f; color:#fff;
                          font-family:-apple-system,Helvetica,Arial,sans-serif; }
              .err { height:100%; display:flex; align-items:center; justify-content:center;
                     text-align:center; padding:12px; font-size:12px; opacity:.65; }
            </style></head><body>
              <div class="err">HERE JS apiKey not configured.<br/>Set HERE_JS_API_KEY in xcconfig.</div>
            </body></html>
            """
        }

        let styleName = styleIsDark ? "normal.night" : "normal.day"

        // NOTE on escaping: the Swift multi-line string literal below is
        // forwarded verbatim to WKWebView. The only substitutions are
        // the API key, basemap style name, and initial camera coords —
        // everything else is static JS / HTML.
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8"/>
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"/>
          <link rel="stylesheet" href="https://js.api.here.com/v3/3.1/mapsjs-ui.css"/>
          <style>
            /* Solid base so a silent tile-auth failure shows a uniform
               dark surface instead of letting the parent SwiftUI tile
               bleed through and read as a blank rectangle. */
            html, body, #map { margin:0; padding:0; width:100%; height:100%; background:#0b0b0f; position:relative; }
            #diag { position:absolute; bottom:6px; left:8px; right:8px;
                    color:#fff; opacity:0.5; font:9px -apple-system,Helvetica;
                    pointer-events:none; }
            /* Brand tint overlay — matches the EusoTrip blue→magenta
               palette the IMA UI design system specifies. Sits on top
               of the basemap with mix-blend-mode so structural
               cartography (roads, parks, water) reads through clean.
               pointer-events:none keeps pan/zoom unblocked. */
            #brand-tint { position:absolute; inset:0; pointer-events:none;
                          background:linear-gradient(135deg, rgba(20,115,255,0.18) 0%, rgba(190,1,255,0.22) 100%);
                          mix-blend-mode:screen; }
          </style>
          <script type="text/javascript" src="https://js.api.here.com/v3/3.1/mapsjs-core.js"></script>
          <script type="text/javascript" src="https://js.api.here.com/v3/3.1/mapsjs-service.js"></script>
          <script type="text/javascript" src="https://js.api.here.com/v3/3.1/mapsjs-ui.js"></script>
          <script type="text/javascript" src="https://js.api.here.com/v3/3.1/mapsjs-data.js"></script>
        </head>
        <body>
          <div id="map"></div>
          <div id="brand-tint"></div>
          <script type="text/javascript">
            (function(){
              function log(msg){
                try { window.webkit.messageHandlers.hzLog.postMessage(String(msg)); } catch(e) {}
              }

              try {
                var platform = new H.service.Platform({ apikey: "\(apiKey)" });
                var styleName = "\(styleName)";

                // Build basemap from HERE's modern OMV v2 vector tile
                // service directly. Bypasses createDefaultLayers() which
                // leans on H.service.MapTileService — flagged deprecated
                // by HERE 2026-04-29 ("Use HERE Vector Tile API or Raster
                // Tile API v3 instead"). Several tile coords already
                // return 410 Gone from `1.base.maps.ls.hereapi.com/maptile/2.1/`,
                // so the legacy raster fallback path is dead and the
                // path createDefaultLayers walks for many tiers is
                // following it. Going straight to OMV avoids both
                // chains. Mirrors the web /hot-zones fix in
                // client/src/components/maps/HereMap.tsx (commit ba7e32fe).
                function buildOmvBaseLayer(){
                  try {
                    if (!platform.getOMVService) return null;
                    var omvService = platform.getOMVService({
                      path: "v2/vectortiles/core/mc"
                    });
                    // Day YAML is the only one returning 200 on our HERE
                    // plan tier (probed 2026-04-29). Every night YAML
                    // candidate (oslo/normal.night, oslo/japan/night,
                    // miami/normal.night, etc.) returns 403. Use day
                    // for both modes; dark-mode tint is applied via the
                    // brand-tint CSS overlay above the map.
                    var styleUrl = "https://js.api.here.com/v3/3.1/styles/omv/normal.day.yaml";
                    void styleName; // reserved for future night-tier swap
                    var style = new H.map.render.Style(styleUrl);
                    var provider = new H.service.omv.Provider(omvService, style);
                    return new H.map.layer.TileLayer(provider, { tileSize: 512 });
                  } catch (e) {
                    log("buildOmvBaseLayer error: " + e);
                    return null;
                  }
                }

                // Legacy fallback. Same defensive pickLayer as before
                // but vector-first in BOTH modes — raster maptile/2.1
                // is the dead path, no reason to ever prefer it.
                var defaultLayers = null;
                function pickLegacyLayer(){
                  try {
                    if (!defaultLayers) {
                      defaultLayers = platform.createDefaultLayers({ tileSize: 512, ppi: 400 });
                    }
                    if (styleName === "normal.night") {
                      if (defaultLayers.vector
                          && defaultLayers.vector.normal
                          && defaultLayers.vector.normal.mapnight) {
                        return defaultLayers.vector.normal.mapnight;
                      }
                      if (defaultLayers.raster
                          && defaultLayers.raster.normal
                          && defaultLayers.raster.normal.mapnight) {
                        return defaultLayers.raster.normal.mapnight;
                      }
                    }
                    if (defaultLayers.vector
                        && defaultLayers.vector.normal
                        && defaultLayers.vector.normal.map) {
                      return defaultLayers.vector.normal.map;
                    }
                    if (defaultLayers.raster
                        && defaultLayers.raster.normal
                        && defaultLayers.raster.normal.map) {
                      return defaultLayers.raster.normal.map;
                    }
                    return null;
                  } catch (e) { log("pickLegacyLayer error: " + e); return null; }
                }

                var baseLayer = buildOmvBaseLayer() || pickLegacyLayer();
                if (!baseLayer) {
                  log("no basemap available — defaultLayers keys: " + Object.keys(defaultLayers||{}).join(","));
                  document.getElementById("map").innerHTML =
                    '<div style="height:100%;display:flex;align-items:center;justify-content:center;color:#fff;opacity:.6;font-size:11px">basemap unavailable</div>';
                  return;
                }

                var map = new H.Map(
                  document.getElementById("map"),
                  baseLayer,
                  {
                    center: { lat: \(centerLat), lng: \(centerLng) },
                    zoom: \(zoom),
                    pixelRatio: window.devicePixelRatio || 1
                  }
                );

                // Surface tile-fetch failures (auth / network) so a silent
                // 403 doesn't read as "the heatmap doesn't work" — the
                // hzLog channel wires through to Xcode console and the
                // diagnostic overlay below picks the message up.
                map.addEventListener("mapviewchangeend", function(){}, false);
                if (baseLayer.getProvider) {
                  try {
                    var prov = baseLayer.getProvider();
                    if (prov && prov.addEventListener) {
                      prov.addEventListener("tileerror", function(ev){
                        log("tile error: " + (ev && ev.tile && ev.tile.url) + " status=" + (ev && ev.status));
                      });
                    }
                  } catch (e) {}
                }

                // Responsive to orientation changes / frame resizes.
                window.addEventListener("resize", function(){ map.getViewPort().resize(); });

                // Pan + pinch-zoom, no rotate/tilt (keep it 2D to match widget).
                var behavior = new H.mapevents.Behavior(new H.mapevents.MapEvents(map));
                behavior.disable(H.mapevents.Behavior.DRAGGING | H.mapevents.Behavior.WHEELZOOM | H.mapevents.Behavior.PINCHZOOM);
                // Keep the widget deliberately static — the driver interacts
                // with the zone chips below, not the map. Re-enable if UX
                // wants a pannable preview later.

                // Heatmap provider lives in mapsjs-data. Wrapped in a
                // TileLayer so HERE handles server-side binning.
                var heatmapLayer = null;
                var heatmapProvider = null;

                function rebuildHeatmap(points) {
                  if (heatmapLayer) { map.removeLayer(heatmapLayer); heatmapLayer = null; }
                  heatmapProvider = new H.data.heatmap.Provider({
                    colors: H.data.heatmap.Colors.DEFAULT,
                    assumeValues: true,
                    opacity: 0.75,
                    // Hard-clamp the blur so dense clusters don't smear
                    // across the whole CONUS at zoom 4.
                    interpolate: true
                  });
                  heatmapProvider.addData(points || []);
                  heatmapLayer = new H.map.layer.TileLayer(heatmapProvider);
                  map.addLayer(heatmapLayer);
                }

                // Entry point called from Swift via evaluateJavaScript.
                window.__hzApplyPoints = function(pts){
                  try { rebuildHeatmap(pts); }
                  catch (e) { log("applyPoints error: " + e); }
                };

                // Kick off with an empty heatmap so the layer stack is
                // always wired before the first Swift payload arrives.
                rebuildHeatmap([]);

                // Tell Swift the map is ready to receive data.
                try { window.webkit.messageHandlers.mapReady.postMessage("ok"); } catch (e) {}
              } catch (err) {
                log("init failed: " + err);
              }
            })();
          </script>
        </body>
        </html>
        """
    }
}

// MARK: - HotZonesHeatMapView (call-site shim)

/// Thin adapter preserving the old `HotZonesHeatMapView` API surface
/// (zones + onSelectZone closure) so the surrounding widget code is
/// unchanged. Converts `[HotZoneEntry]` into the `[HotZonesHeatmapPoint]`
/// shape HERE's provider wants, then defers to `HotZonesHeatmapWebView`.
///
/// Tap-to-select is intentionally disabled in this pass — the webview's
/// zone discovery would require a reverse geocode or a separate marker
/// layer. The zone chip carousel below the heatmap remains the primary
/// way to open the detail sheet, matching the web `/hot-zones` UX.
struct HotZonesHeatMapView: View {
    var zones: [HotZoneEntry]
    var selectedZoneId: String? = nil
    var onSelectZone: ((HotZoneEntry) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.palette) private var palette

    var body: some View {
        // Render the canonical native HERE map (`HereMapView`) with
        // each hot zone painted as a brand-coloured pin. Was forced
        // to a SwiftUI gradient fallback because the HERE JS WebView
        // was timing out tile auth — but the native OAuth tile path
        // is rock-solid (same one shipper Live Tracking + load
        // detail use), so we use that instead and ditch the
        // WebView entirely. Fallback to the gradient card stays as
        // the empty state when there are no zones to plot.
        // Founder report 2026-05-06: "on homescreen driver the
        // hotzones map doesnt show at all."
        if zones.isEmpty {
            jsKeyMissingFallback
        } else {
            HereMapView(
                markers: zones.map { z in
                    HereMapView.LoadMarker(
                        id: z.zoneId,
                        title: z.zoneName,
                        subtitle: "\(z.demandLevel) · \(z.zoneId)",
                        coordinate: CLLocationCoordinate2D(
                            latitude: z.center.lat,
                            longitude: z.center.lng
                        )
                    )
                },
                onSelectMarker: { id in
                    if let z = zones.first(where: { $0.zoneId == id }) {
                        onSelectZone?(z)
                    }
                },
                useHereTiles: true,
                showsUserLocation: false,
                showsCompass: false
            )
        }
    }

    private var jsKeyMissingFallback: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.45, blue: 1.00).opacity(0.35),
                    Color(red: 0.74, green: 0.00, blue: 1.00).opacity(0.35),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                Color.black.opacity(0.35)
            )
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("DEMAND HEATMAP")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text("\(zones.count) live \(zones.count == 1 ? "zone" : "zones")")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
                Text("Tap a zone below for the detail breakdown.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
        }
    }

    /// Derive heatmap weights from the demand tier + load-to-truck
    /// ratio. Mirrors the web platform's weighting so colour ramps
    /// line up across surfaces.
    static func points(from zones: [HotZoneEntry]) -> [HotZonesHeatmapPoint] {
        zones.map { zone in
            let tierMultiplier: Double
            switch HotZoneDemand(zone.demandLevel) {
            case .critical: tierMultiplier = 1.6
            case .high:     tierMultiplier = 1.25
            case .elevated: tierMultiplier = 1.0
            case .unknown:  tierMultiplier = 0.75
            }
            // Clamp liveRatio into 0…3 so one runaway zone can't drown
            // everything else on the colour ramp.
            let ratio = max(0.25, min(zone.liveRatio, 3.0))
            let weight = ratio * tierMultiplier
            return HotZonesHeatmapPoint(
                lat: zone.center.lat,
                lng: zone.center.lng,
                weight: weight
            )
        }
    }
}

// MARK: - HotZonesWidget

struct HotZonesWidget: View {
    @Environment(\.palette) var palette
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var store = HotZonesStore()

    @State private var pulse: Bool = false
    @State private var selectedZone: HotZoneEntry? = nil
    @State private var showDetailSheet: Bool = false

    var body: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                pulseStrip
                // HERE Fuel Prices strip — silent when the driver
                // hasn't authorized location or HERE returned nothing.
                if !store.fuelStations.isEmpty {
                    fuelStrip
                }
                heatMap
                zoneChipsScroller
                if store.zones.isEmpty && store.isLoading {
                    loadingPlaceholder
                }
                if let msg = store.errorMessage, store.zones.isEmpty {
                    errorPlaceholder(msg)
                }
                footerMeta
            }
        }
        .task { await store.bootstrap() }
        .onAppear {
            // Kick off the infinite "live" pulse on the header dot.
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }
            // Re-fetch on every reappear (NOT just first mount). `.task`
            // attaches to the view's lifetime — when this widget is
            // inside a TabView page that stays alive across tab swaps,
            // `.task` does NOT re-fire on tab-back, so the heat-feed
            // froze at the values from first appear and the user saw
            // 2-month-old "stale" data on every navigation. `.onAppear`
            // fires every time the view enters the hierarchy, which is
            // the right cadence for "always show fresh data when the
            // driver looks at the widget".
            Task { await store.refresh() }
        }
        .sheet(item: $selectedZone) { zone in
            HotZonesDetailSheet(zone: zone, marketPulse: store.marketPulse)
                .environment(\.palette, palette)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDetailSheet) {
            HotZonesListSheet(store: store)
                .environment(\.palette, palette)
                .eusoSheetX()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Space.s2) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient.diagonal)
                    .frame(width: 24, height: 24)
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
            }

            Text("HOT ZONES")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            // Pulsing LIVE dot.
            HStack(spacing: 4) {
                Circle()
                    .fill(Brand.danger)
                    .frame(width: 6, height: 6)
                    .scaleEffect(pulse ? 1.25 : 0.85)
                    .opacity(pulse ? 1.0 : 0.55)
                Text("LIVE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(Brand.danger)
            }

            Spacer(minLength: 0)

            Button { showDetailSheet = true } label: {
                HStack(spacing: 3) {
                    Text("See all")
                        .font(EType.caption)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(palette.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Market Pulse strip

    private var pulseStrip: some View {
        let pulse = store.marketPulse
        return HStack(spacing: Space.s3) {
            pulseChip(
                label: "AVG RATE",
                value: pulse?.avgRate.map { String(format: "$%.2f", $0) } ?? "—",
                trailing: "/mi",
                tint: Brand.success
            )
            pulseChip(
                label: "CRITICAL",
                value: pulse?.criticalZones.map(String.init) ?? "0",
                trailing: "zones",
                tint: Brand.danger
            )
            pulseChip(
                label: "L/T RATIO",
                value: pulse?.avgRatio.map { String(format: "%.1fx", $0) } ?? "—",
                trailing: "",
                tint: Brand.warning
            )
        }
    }

    private func pulseChip(label: String, value: String, trailing: String, tint: Color) -> some View {
        // Each chip wears its own brand tint as a soft fill +
        // saturated stroke instead of the slate `bgCardSoft` washout.
        // Reads as a deliberate market-signal pill, not a placeholder.
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro).tracking(0.5)
                .foregroundStyle(tint.opacity(0.85))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .heavy, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !trailing.isEmpty {
                    Text(trailing)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(tint.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(tint.opacity(0.45), lineWidth: 1)
        )
    }

    // MARK: Fuel strip (HERE Fuel Prices)

    /// Horizontal strip surfaced between the market pulse and the
    /// heatmap. Leads with the cheapest diesel station near the
    /// driver + a scrollable rail of the next best deals. Every row
    /// is a live HERE Fuel Prices v3 result — brand, distance, $/gal,
    /// currency, and the lastUpdate timestamp flow straight from the
    /// API.
    private var fuelStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: "fuelpump.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("FUEL NEAR YOU")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("HERE · \(store.fuelStations.count) stations")
                    .font(EType.micro).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }

            // Hero chip — cheapest diesel nearby.
            if let best = store.cheapestDieselStation,
               let price = best.cheapestDieselPrice {
                HStack(spacing: Space.s3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CHEAPEST DIESEL")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(palette.textTertiary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(formatPrice(price))
                                .font(.system(size: 22, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(LinearGradient.diagonal)
                            Text(price.currency)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(palette.textTertiary)
                        }
                        Text(bestStationLine(best))
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                .padding(Space.s3)
                .background(palette.bgCardSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }

            // Horizontal rail of the next best stations.
            if store.fuelStations.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.s2) {
                        ForEach(store.fuelStations.prefix(8)) { station in
                            fuelRailChip(station: station)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private func fuelRailChip(station: HereFuelStation) -> some View {
        let price = station.cheapestDieselPrice
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "fuelpump")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text(station.brand?.uppercased() ?? station.name?.uppercased() ?? "STATION")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Text(price.map(formatPrice) ?? "—")
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
            if let m = station.distance {
                Text(formatDistanceMiles(meters: m))
                    .font(EType.micro).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 8)
        .background(palette.bgCardSoft)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func formatPrice(_ price: HereFuelPrice) -> String {
        let symbol: String = {
            switch price.currency.uppercased() {
            case "USD": return "$"
            case "EUR": return "€"
            case "GBP": return "£"
            case "CAD": return "$"
            default:    return ""
            }
        }()
        return String(format: "%@%.3f", symbol, price.price)
    }

    private func bestStationLine(_ station: HereFuelStation) -> String {
        var parts: [String] = []
        if let b = station.brand, !b.isEmpty { parts.append(b) }
        else if let n = station.name, !n.isEmpty { parts.append(n) }
        if let a = station.address?.oneLine, !a.isEmpty { parts.append(a) }
        if let m = station.distance {
            parts.append(formatDistanceMiles(meters: m))
        }
        return parts.joined(separator: " · ")
    }

    private func formatDistanceMiles(meters: Int) -> String {
        let miles = Double(meters) / 1609.344
        if miles < 10 {
            return String(format: "%.1f mi", miles)
        }
        return String(format: "%.0f mi", miles)
    }

    // MARK: Heatmap

    private var heatMap: some View {
        ZStack(alignment: .topLeading) {
            HotZonesHeatMapView(
                zones: store.zones,
                onSelectZone: { zone in selectedZone = zone }
            )
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            // Corner glyph so the widget reads as a "heatmap" even when
            // zoomed out and the circles are small.
            HStack(spacing: 4) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 10, weight: .bold))
                Text("HEATMAP")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.55))
            )
            .padding(Space.s2)

            // Demand-level legend, bottom-right.
            VStack(alignment: .trailing, spacing: 3) {
                legendRow(color: Brand.danger,  label: "CRITICAL")
                legendRow(color: Brand.warning, label: "HIGH")
                legendRow(color: Color(red: 1.0, green: 0.76, blue: 0.20),
                          label: "ELEVATED")
            }
            .padding(Space.s2)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Color.black.opacity(0.55))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: .bottomTrailing)
            .padding(Space.s2)
        }
        .frame(height: 190)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.25)
                .allowsHitTesting(false)
        )
    }

    private func legendRow(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(Color.white)
        }
    }

    // MARK: Zone chips carousel

    private var zoneChipsScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s3) {
                ForEach(Array(store.topZones().enumerated()), id: \.element.zoneId) { pair in
                    let rank = pair.offset + 1
                    let zone = pair.element
                    Button {
                        selectedZone = zone
                    } label: {
                        zoneChip(zone: zone, rank: rank)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)   // so gradient borders don't clip
            .padding(.vertical, 2)
        }
    }

    private func zoneChip(zone: HotZoneEntry, rank: Int) -> some View {
        let demand = HotZoneDemand(zone.demandLevel)
        let rateDelta = zone.rateChangePercent ?? 0
        let deltaPositive = rateDelta >= 0

        return VStack(alignment: .leading, spacing: Space.s2) {
            // Rank badge + demand pill
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: 18, height: 18)
                    Text("\(rank)")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color.white)
                }
                Text(demand.label)
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(demand.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(demand.color.opacity(0.16))
                    )
                Spacer(minLength: 0)
            }

            // Zone name + state
            VStack(alignment: .leading, spacing: 1) {
                Text(zone.zoneName)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(zone.state)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.textTertiary)
            }

            // Rate + delta
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "$%.2f", zone.liveRate))
                    .font(.system(size: 15, weight: .heavy, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text("/mi")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 2)
                if abs(rateDelta) >= 0.1 {
                    HStack(spacing: 1) {
                        Image(systemName: deltaPositive ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 8, weight: .heavy))
                        Text(String(format: "%.1f%%", abs(rateDelta)))
                            .font(.system(size: 9, weight: .heavy))
                            .monospacedDigit()
                    }
                    .foregroundStyle(deltaPositive ? Brand.success : Brand.danger)
                }
            }

            // Surge + load-to-truck meter
            surgeMeter(ratio: zone.liveRatio, surge: zone.liveSurge, tint: demand.color)

            // Volume strip
            HStack(spacing: Space.s2) {
                volumePill(glyph: "shippingbox.fill",
                           value: "\(zone.liveLoads)",
                           tint: Brand.blue)
                volumePill(glyph: "box.truck.fill",
                           value: "\(zone.liveTrucks)",
                           tint: Brand.magenta)
            }
        }
        .padding(Space.s3)
        .frame(width: 210, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            demand.color.opacity(0.16),
                            palette.bgCard
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            demand.color.opacity(0.95),
                            demand.color.opacity(0.40)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )
        )
    }

    /// Bar meter showing liveRatio (filled portion) with the surge
    /// multiplier read out on the right. Full bar maps to ratio 3.0
    /// (above that the bar stays clamped but still reads "pegged").
    private func surgeMeter(ratio: Double, surge: Double, tint: Color) -> some View {
        let normalized = max(0, min(ratio / 3.0, 1.0))
        return HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.borderFaint)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.6), tint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * normalized, 6))
                }
            }
            .frame(height: 4)

            Text(String(format: "%.1fx", surge))
                .font(.system(size: 9, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }

    private func volumePill(glyph: String, value: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: glyph)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 10, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }

    // MARK: Footer

    private var footerMeta: some View {
        // Branding-only footer — the server-returned `feedSource`
        // string ("EusoTrip Intelligence (0 carriers) + 27 Gov
        // Sources") leaked the engineering detail about which data
        // sources feed the rate model. Drivers don't need to see
        // that; they need to know one thing: this is EusoTrip's
        // number. The label stays constant regardless of what the
        // backend reports as its source composition, so whether the
        // rate came from FMCSA ingestion, platform settlements, or
        // the market-intel blend, the driver reads it as
        // authoritative "EusoTrip Intelligence."
        HStack(spacing: Space.s2) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("EusoTrip Intelligence")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let at = store.lastLoadedAt {
                Text("Updated " + HotZonesTime.shortAgo(from: at))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(palette.textTertiary)
            }
            if store.isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .tint(palette.textSecondary)
            }
        }
    }

    // MARK: States

    private var loadingPlaceholder: some View {
        HStack(spacing: Space.s2) {
            ProgressView().tint(palette.textSecondary)
            Text("Scanning national freight intelligence…")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.s2)
    }

    /// Graceful placeholder shown when the feed is temporarily
    /// unreachable. Replaces the old "exclamationmark.triangle.fill +
    /// bold red headline + Cannot-read-properties trace" design, which
    /// read like a crash report and alarmed drivers unnecessarily.
    ///
    /// New behavior:
    ///   • No warning icon or alarm copy in the header — it's a neutral
    ///     "Updating" line with a small shimmer.
    ///   • The raw error `message` (e.g. "Cannot read properties of
    ///     undefined (reading 'CA')") is NEVER surfaced to the driver;
    ///     it's useful to engineers, not to someone at the wheel.
    ///   • Retry is a quiet chevron button, not a hero CTA.
    ///   • The widget still auto-retries on every pull-to-refresh from
    ///     the parent, so most drivers will never even see this state.
    private func errorPlaceholder(_ message: String) -> some View {
        #if DEBUG
        // Keep the raw server message available to engineers in
        // development builds so we can diagnose outages without the
        // driver UX taking the hit in production.
        let _ = message
        #endif
        return HStack(spacing: Space.s2) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(palette.textTertiary)
                .symbolEffect(.pulse, options: .repeating)
            VStack(alignment: .leading, spacing: 2) {
                Text("Updating live market data")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                Text("We'll refresh automatically.")
                    .font(EType.micro)
                    .tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: Space.s2)
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .padding(8)
                    .background(
                        Circle().fill(palette.bgCard.opacity(0.6))
                    )
                    .overlay(
                        Circle().strokeBorder(palette.borderFaint.opacity(0.6), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry market data refresh")
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - HotZonesDetailSheet

/// Tap-through detail sheet for a single hot zone. Mirrors the web
/// detail panel — full demand breakdown, rate + surge meters, volume,
/// top equipment, fuel, weather risk, compliance risk.
struct HotZonesDetailSheet: View {
    let zone: HotZoneEntry
    let marketPulse: HotZonesMarketPulse?
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let demand = HotZoneDemand(zone.demandLevel)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    hero(demand: demand)
                    metricGrid
                    if let reasons = zone.reasons, !reasons.isEmpty {
                        reasonsSection(reasons)
                    }
                    if let eq = topEquipment, !eq.isEmpty {
                        equipmentSection(eq)
                    }
                    riskSection
                    if let fmcsa = zone.fmcsa {
                        fmcsaSection(fmcsa)
                    }
                    if let alerts = zone.weatherAlerts, !alerts.isEmpty {
                        weatherAlertsSection(alerts)
                    }
                    // Footer context
                    Text("Live intelligence from hz_zone_intelligence · FMCSA · NWS · EIA. Refreshes every 5 min.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Space.s5)
            }
            .background(palette.bgPage.ignoresSafeArea())
            .navigationTitle("Zone Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    // MARK: Hero

    private func hero(demand: HotZoneDemand) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    Text(demand.label)
                        .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(demand.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(demand.color.opacity(0.18))
                        )
                    if let trend = zone.demandTrend {
                        HStack(spacing: 3) {
                            Image(systemName: trendGlyph(trend))
                                .font(.system(size: 10, weight: .bold))
                            Text(trend)
                                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        }
                        .foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                Text(zone.zoneName)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(zone.state)
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "$%.2f", zone.liveRate))
                        .font(EType.numeric)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("/mi")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: 0)
                    if let pct = zone.rateChangePercent, abs(pct) >= 0.1 {
                        HStack(spacing: 2) {
                            Image(systemName: pct >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .heavy))
                            Text(String(format: "%.1f%%", abs(pct)))
                                .font(.system(size: 12, weight: .heavy))
                                .monospacedDigit()
                        }
                        .foregroundStyle(pct >= 0 ? Brand.success : Brand.danger)
                    }
                }
            }
        }
    }

    private func trendGlyph(_ raw: String) -> String {
        switch raw.uppercased() {
        case "RISING":  return "arrow.up.right.circle.fill"
        case "FALLING": return "arrow.down.right.circle.fill"
        default:        return "minus.circle.fill"
        }
    }

    // MARK: Metric grid

    private var metricGrid: some View {
        // Accent each tile with its semantic color so the grid reads
        // as a real spatial-intel dashboard instead of a stack of
        // slate cards. Live volumes get brand blue/magenta, ratios +
        // surges get gradient numerals (already on-brand), fuel +
        // safety speak in their own commodity tints.
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Space.s3),
                      GridItem(.flexible(), spacing: Space.s3)],
            spacing: Space.s3
        ) {
            MetricTile(label: "Live Loads",
                       value: "\(zone.liveLoads)",
                       accent: Brand.blue)
            MetricTile(label: "Live Trucks",
                       value: "\(zone.liveTrucks)",
                       accent: Brand.magenta)
            MetricTile(label: "L/T Ratio",
                       value: String(format: "%.1fx", zone.liveRatio),
                       gradientNumeral: true)
            MetricTile(label: "Surge",
                       value: String(format: "%.2fx", zone.liveSurge),
                       gradientNumeral: true)
            if let fuel = zone.fuelPrice {
                MetricTile(label: "Diesel",
                           value: String(format: "$%.2f", fuel),
                           accent: Brand.warning)
            }
            if let peak = zone.peakHours, !peak.isEmpty {
                MetricTile(label: "Peak Hours",
                           value: peak,
                           accent: Brand.info)
            }
            if let safety = zone.safetyScore {
                MetricTile(label: "Safety Score",
                           value: String(format: "%.0f/100", safety),
                           gradientNumeral: true,
                           accent: safety >= 80 ? Brand.success : (safety >= 60 ? Brand.warning : Brand.danger))
            }
            if let platform = zone.platformLoads {
                MetricTile(label: "Platform Loads",
                           value: "\(platform)",
                           accent: Brand.success)
            }
        }
    }

    // MARK: Equipment

    private var topEquipment: [String]? {
        zone.topEquipment.isEmpty ? nil : zone.topEquipment
    }

    private func equipmentSection(_ equipment: [String]) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("TOP EQUIPMENT")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                // Wrap equipment codes in chips.
                FlowChips(items: equipment.map { prettify($0) })
            }
        }
    }

    private func prettify(_ code: String) -> String {
        code.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: Risk

    private var riskSection: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("RISK SIGNALS")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                VStack(alignment: .leading, spacing: 6) {
                    riskRow(glyph: "cloud.bolt.fill",
                            label: "Weather Risk",
                            value: zone.weatherRiskLevel ?? "LOW")
                    if let comp = zone.complianceRiskScore {
                        riskRow(glyph: "checkmark.seal.fill",
                                label: "Compliance Risk",
                                value: "\(comp)/100")
                    }
                    if let hz = zone.hazmatClasses, !hz.isEmpty {
                        riskRow(glyph: "exclamationmark.shield.fill",
                                label: "Hazmat Classes",
                                value: hz.joined(separator: ", "))
                    }
                    if let fires = zone.activeWildfires, fires > 0 {
                        riskRow(glyph: "flame.circle.fill",
                                label: "Active Wildfires",
                                value: "\(fires)")
                    }
                    if let fema = zone.femaDisasterActive, fema {
                        riskRow(glyph: "house.lodge.fill",
                                label: "FEMA Disaster",
                                value: "ACTIVE")
                    }
                    if let seismic = zone.seismicRiskLevel,
                       seismic.uppercased() != "LOW" {
                        riskRow(glyph: "waveform.path.ecg",
                                label: "Seismic Risk",
                                value: seismic.uppercased())
                    }
                    if let hazmatInc = zone.recentHazmatIncidents, hazmatInc > 0 {
                        riskRow(glyph: "drop.triangle.fill",
                                label: "Hazmat Incidents",
                                value: "\(hazmatInc)")
                    }
                    if let epa = zone.epaFacilitiesCount, epa > 0 {
                        riskRow(glyph: "leaf.fill",
                                label: "EPA Facilities",
                                value: "\(epa)")
                    }
                    if let aiTrend = zone.aiRateTrend {
                        riskRow(glyph: "cpu",
                                label: "ESANG Rate Trend",
                                value: aiTrend.uppercased())
                    }
                }
            }
        }
    }

    // MARK: Reasons

    private func reasonsSection(_ reasons: [String]) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("WHY THIS ZONE IS HOT")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(reasons, id: \.self) { reason in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(LinearGradient.diagonal)
                                .padding(.top, 3)
                            Text(reason)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let forecast = zone.nextWeekForecast, !forecast.isEmpty {
                    Divider().overlay(palette.borderFaint)
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("Next week: ")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                        Text(forecast)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                    }
                }
            }
        }
    }

    // MARK: FMCSA

    private func fmcsaSection(_ fmcsa: HotZoneFMCSA) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: 4) {
                    // Founder report 2026-05-06: "fmcsa 9.8 m just
                    // needs to say fmcsa" — the 9.8M was the source
                    // database row count, not a per-zone metric, so
                    // it read as confusing trivia in the zone detail.
                    Text("FMCSA")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: Space.s3),
                              GridItem(.flexible(), spacing: Space.s3)],
                    spacing: Space.s3
                ) {
                    if let c = fmcsa.carriers { MetricTile(label: "Carriers", value: "\(c)") }
                    if let p = fmcsa.powerUnits { MetricTile(label: "Power Units", value: "\(p)") }
                    if let d = fmcsa.drivers { MetricTile(label: "Drivers", value: "\(d)") }
                    if let hz = fmcsa.hazmatCarriers { MetricTile(label: "Hazmat Carriers", value: "\(hz)") }
                    if let crashes = fmcsa.crashes90d {
                        MetricTile(label: "Crashes (90d)", value: "\(crashes)",
                                   gradientNumeral: crashes > 0)
                    }
                    if let fat = fmcsa.crashFatalities, fat > 0 {
                        MetricTile(label: "Fatalities", value: "\(fat)")
                    }
                    if let insp = fmcsa.inspections30d {
                        MetricTile(label: "Inspections (30d)", value: "\(insp)")
                    }
                    if let oos = fmcsa.oosRate {
                        MetricTile(label: "OOS Rate",
                                   value: String(format: "%.1f%%", oos),
                                   gradientNumeral: oos >= 5)
                    }
                }
            }
        }
    }

    // MARK: Weather alerts

    private func weatherAlertsSection(_ alerts: [HotZoneWeatherAlert]) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("ACTIVE WEATHER ALERTS")
                    .font(EType.micro).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(alerts.enumerated()), id: \.offset) { pair in
                        let alert = pair.element
                        let severity = (alert.severity ?? "").uppercased()
                        let tint: Color = {
                            switch severity {
                            case "EXTREME", "SEVERE": return Brand.danger
                            case "MODERATE":          return Brand.warning
                            default:                  return Brand.info
                            }
                        }()
                        HStack(alignment: .top, spacing: Space.s2) {
                            Image(systemName: "cloud.bolt.rain.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(tint)
                                .frame(width: 18, alignment: .center)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text((alert.event ?? "Alert").uppercased())
                                        .font(.system(size: 11, weight: .heavy))
                                        .foregroundStyle(palette.textPrimary)
                                    if !severity.isEmpty {
                                        Text(severity)
                                            .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                                            .foregroundStyle(tint)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1.5)
                                            .background(
                                                Capsule(style: .continuous)
                                                    .fill(tint.opacity(0.16))
                                            )
                                    }
                                }
                                if let headline = alert.headline, !headline.isEmpty {
                                    Text(headline)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(palette.textSecondary)
                                        .lineLimit(3)
                                }
                                if let area = alert.areaDesc, !area.isEmpty {
                                    Text(area)
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundStyle(palette.textTertiary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func riskRow(glyph: String, label: String, value: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: glyph)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

// MARK: - HotZonesListSheet

/// "See all" sheet — every zone the driver's role surfaces, sorted by
/// liveRatio desc. Replaces the web /hot-zones full-page list on mobile.
struct HotZonesListSheet: View {
    @ObservedObject var store: HotZonesStore
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    @State private var selectedZone: HotZoneEntry? = nil

    var body: some View {
        // Patch #1: EusoHeader replaces the inline iOS-default
        // `navigationTitle("Hot Zones")` / `.inline` combo so this sheet
        // reads in the 28pt gradient-hero language the rest of the app
        // uses. The Done button is folded into the header's trailing
        // accessory slot so the toolbar goes away entirely.
        VStack(alignment: .leading, spacing: 0) {
            EusoHeader(title: "Hot Zones",
                       subtitle: "Live demand, rate & L/T",
                       size: .sheet) {
                Button { dismiss() } label: {
                    Text("Done")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Hot Zones")
            }
            IridescentHairline()
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s3) {
                    if let pulse = store.marketPulse {
                        summaryStrip(pulse)
                    }
                    ForEach(store.zones) { zone in
                        Button { selectedZone = zone } label: {
                            listRow(zone)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Space.s5)
            }
            .refreshable { await store.refresh() }
        }
        .background(palette.bgPage.ignoresSafeArea())
        .sheet(item: $selectedZone) { zone in
            HotZonesDetailSheet(zone: zone, marketPulse: store.marketPulse)
                .environment(\.palette, palette)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func summaryStrip(_ pulse: HotZonesMarketPulse) -> some View {
        HStack(spacing: Space.s2) {
            summaryTile(label: "AVG RATE",
                        value: pulse.avgRate.map { String(format: "$%.2f", $0) } ?? "—",
                        tint: Brand.success)
            summaryTile(label: "CRITICAL",
                        value: pulse.criticalZones.map(String.init) ?? "0",
                        tint: Brand.danger)
            summaryTile(label: "L/T",
                        value: pulse.avgRatio.map { String(format: "%.1fx", $0) } ?? "—",
                        tint: Brand.warning)
        }
    }

    private func summaryTile(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }

    private func listRow(_ zone: HotZoneEntry) -> some View {
        let demand = HotZoneDemand(zone.demandLevel)
        let delta = zone.rateChangePercent ?? 0
        return HStack(spacing: Space.s3) {
            ZStack {
                Circle()
                    .fill(demand.color.opacity(0.18))
                    .frame(width: 38, height: 38)
                Image(systemName: "flame.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(demand.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(zone.zoneName)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(zone.state)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textTertiary)
                }
                HStack(spacing: 6) {
                    // Patch #2: EusoBadge replaces the bespoke flame-in-circle
                    // ELEVATED marker. `.hot` for CRITICAL (red-hot demand),
                    // `.warning` for HIGH / ELEVATED (amber), `.neutral` for
                    // unknown. The flame glyph is carried inline.
                    EusoBadge(label: demand.label,
                              kind: demand.eusoBadgeKind,
                              icon: Image(systemName: "flame.fill"))
                    Text("· \(zone.liveLoads) loads · \(zone.liveTrucks) trucks")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "$%.2f", zone.liveRate))
                    .font(.system(size: 14, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                if abs(delta) >= 0.1 {
                    HStack(spacing: 1) {
                        Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 8, weight: .heavy))
                        Text(String(format: "%.1f%%", abs(delta)))
                            .font(.system(size: 10, weight: .heavy))
                            .monospacedDigit()
                    }
                    .foregroundStyle(delta >= 0 ? Brand.success : Brand.danger)
                }
            }
        }
        .padding(Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }
}

// MARK: - FlowChips

/// Minimal wrap layout — renders equipment codes as chips that flow onto
/// additional rows when they overflow. Avoids bringing in a 3rd-party
/// FlowLayout dependency.
private struct FlowChips: View {
    let items: [String]
    @Environment(\.palette) var palette

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 92), spacing: 6)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(palette.tintNeutral)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
            }
        }
    }
}

// MARK: - Time helpers

private enum HotZonesTime {
    static func shortAgo(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86_400)d ago"
    }
}
