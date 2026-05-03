//
//  HereMapView.swift
//  EusoTrip — SwiftUI wrapper around MKMapView.
//
//  Rendering modes:
//    1. HERE basemap (DEFAULT) — HERE Platform raster tiles (v3) served
//       via `HereTileOverlay` on top of MKMapView. `canReplaceMapContent`
//       is set, so HERE completely owns the canvas (Apple's basemap is
//       suppressed, no beige land, no Apple POIs). `explore.day` in
//       light mode, `explore.night` in dark mode. This is the only
//       on-brand mapping surface across the app — iPhone, Watch, and
//       the web platform all render HERE tiles. (Build 48, 2026-04-22.)
//    2. Brand basemap (fallback only) — MKStandardMapConfiguration with
//       `emphasisStyle: .muted` is applied as an invisible floor so the
//       map never shows Apple's default beige if a HERE tile 404s. In
//       the normal case the HERE overlay paints over the top of it and
//       the Apple basemap is never visible. Only kicks in if the HERE
//       API key is missing (dev builds without xcconfig).
//
//  Data model:
//    • `stops: [LoadLocation]`          — individual pins (legacy API).
//    • `lanes: [Lane]`                   — per-load (pickup, delivery)
//                                          pairs used to draw a
//                                          blue→magenta gradient polyline
//                                          per lane and to color pins
//                                          (blue = pickup, magenta =
//                                          delivery).
//    • `route: HereRoute?`               — optional decoded HERE truck
//                                          route; rendered as a single
//                                          blue→magenta gradient polyline.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import MapKit

struct HereMapView: UIViewRepresentable {

    // MARK: - Input

    /// Optional preferred HERE tile style. Only used when
    /// `useHereTiles == true`. If nil, follows `@Environment(\.colorScheme)`.
    var style: HereTileStyle? = nil

    /// A decoded HERE route to render as a blue→magenta gradient polyline.
    var route: HereRoute? = nil

    /// Legacy stop list (flat pins). First = Pickup, last = Delivery.
    /// Prefer `lanes` for multi-load views so pickup/delivery can be
    /// distinguished per lane.
    var stops: [LoadLocation] = []

    /// Per-load pickup → delivery pairs. Each lane renders as a gradient
    /// polyline plus two pins (pickup blue, delivery magenta).
    /// Legacy — prefer `markers` for the public board view.
    var lanes: [Lane] = []

    /// One pin per load at its pickup coordinate. Use this on the public
    /// Eusoboards surface where drivers want a clean overview of available
    /// loads (no polylines, no clutter). Tapping a pin invokes
    /// `onSelectMarker(id)` so the caller can present a detail sheet.
    var markers: [LoadMarker] = []

    /// Invoked when the user taps a marker annotation. Wired via MKMapView's
    /// `didSelect` delegate callback; the coordinator stores the latest
    /// closure so it doesn't capture a stale struct.
    var onSelectMarker: ((String) -> Void)? = nil

    /// Whether to render HERE Platform raster tiles as the basemap.
    /// Default ON — HERE is our canonical mapping provider (brand parity
    /// with the web platform, truck-aware routing on the same stack,
    /// uniform dark/light palette). Callers should leave this alone
    /// unless a test/preview explicitly wants the Apple fallback.
    /// (Build 48, 2026-04-22 — flipped from false → true to unify
    /// mapping across iOS + Watch + Web on HERE.)
    var useHereTiles: Bool = true

    /// Optional extra annotations (e.g. truck position, dispatch markers).
    var extraAnnotations: [MKPointAnnotation] = []

    /// Optional GeoJSON polygon overlay rendered on top of the basemap.
    /// Used by the terminal yardmap surface (022_DockAssigned.swift)
    /// when the active terminal's `TerminalCapabilities.yardLayoutGeoJson`
    /// is populated. Caller pre-parses the GeoJSON into MKPolygon
    /// instances; HereMapView paints them with a Brand.blue stroke +
    /// translucent fill so dock lanes / staging zones / hazmat
    /// segregation areas read clearly over the HERE tiles.
    var yardLayoutPolygons: [MKPolygon] = []

    /// Initial map camera. If nil, the view auto-fits to `stops`/`lanes`/route.
    var initialRegion: MKCoordinateRegion? = nil

    /// User-location tracking mode (none / follow / followWithHeading).
    var userTracking: MKUserTrackingMode = .none

    /// Whether to show the user-location blue dot.
    var showsUserLocation: Bool = false

    /// Whether to show the compass control.
    var showsCompass: Bool = true

    // MARK: - Lane

    /// A single bookable lane — pickup → delivery — used to draw a per-load
    /// gradient polyline and to color the pins (pickup = blue, delivery =
    /// magenta) so the map reads as a real load board.
    struct Lane: Identifiable, Hashable {
        let id: String
        let originTitle: String
        let destinationTitle: String
        let pickup: CLLocationCoordinate2D
        let delivery: CLLocationCoordinate2D

        static func == (lhs: Lane, rhs: Lane) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    /// A single pickup pin on the public load board. No polylines, no
    /// delivery pin — the driver sees only where loads start. Tapping a pin
    /// opens the load detail sheet.
    struct LoadMarker: Identifiable, Hashable {
        let id: String
        let title: String          // e.g. "Dallas, TX"
        let subtitle: String       // e.g. "$2,980 · 781 mi · Dry Van"
        let coordinate: CLLocationCoordinate2D

        static func == (lhs: LoadMarker, rhs: LoadMarker) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    // MARK: - Environment

    @Environment(\.colorScheme) private var colorScheme

    private var effectiveStyle: HereTileStyle {
        style ?? (colorScheme == .dark ? .dark : .light)
    }

    // MARK: - Coordinator (MKMapView delegate)

    final class Coordinator: NSObject, MKMapViewDelegate {
        var tileOverlay: HereTileOverlay?
        weak var mapView: MKMapView?

        /// Cached selection callback — refreshed on every `updateUIView` so
        /// we never hold a stale struct's closure.
        var onSelectMarker: ((String) -> Void)?

        /// Road-following polylines for each lane id, fetched once via
        /// `MKDirections` and re-used across subsequent `apply(...)` passes.
        /// Without this cache every state change would re-request the same
        /// route and replace a smooth curved line with a blink of straight
        /// A→B until the fresh response landed. (Wave-5, 2026-04-20.)
        var laneRouteCache: [String: MKPolyline] = [:]

        /// Lane ids currently in flight against `MKDirections` — prevents
        /// duplicate requests when SwiftUI drives multiple rapid
        /// `updateUIView` passes (scroll, theme flip, fitCamera, …).
        var pendingLaneRequests: Set<String> = []

        // Tint colors for pickup vs delivery pins.
        static let blue    = UIColor(red: 0.08,  green: 0.45,  blue: 1.0, alpha: 1.0)
        static let magenta = UIColor(red: 0.745, green: 0.004, blue: 1.0, alpha: 1.0)

        // Annotation subtitle role tags used by viewFor + didSelect.
        static let markerRolePrefix = "marker"

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tile)
            }
            if let poly = overlay as? MKPolyline {
                // Brand gradient polyline: Brand.blue → Brand.magenta sweeps
                // from the pickup end to the delivery end. Same treatment
                // whether it's a single full HERE truck route or a straight
                // lane connector for the market-board view.
                let renderer = MKGradientPolylineRenderer(polyline: poly)
                renderer.setColors(
                    [Coordinator.blue, Coordinator.magenta],
                    locations: [0.0, 1.0]
                )
                renderer.lineWidth = 5
                renderer.lineCap   = .round
                renderer.lineJoin  = .round
                return renderer
            }
            if let polygon = overlay as? MKPolygon {
                // Yard-layout polygon: terminal admin uploads a
                // GeoJSON describing dock lanes / staging / hazmat
                // segregation. Translucent fill + Brand.blue stroke
                // so the polygons read on top of HERE tiles without
                // burying the underlying basemap.
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.fillColor   = Coordinator.blue.withAlphaComponent(0.18)
                renderer.strokeColor = Coordinator.blue.withAlphaComponent(0.85)
                renderer.lineWidth   = 1.5
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            let id = "stop"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation         = annotation
            view.titleVisibility    = .adaptive
            view.subtitleVisibility = .adaptive
            view.glyphTintColor     = .white
            view.canShowCallout     = false    // we present our own detail sheet

            // `subtitle` carries a tagged role from `apply(...)` — "pickup",
            // "delivery", or "marker" — so the annotation view can pick a
            // brand color without needing a custom MKAnnotation subclass.
            let role = (annotation.subtitle ?? nil) ?? ""
            if role.hasPrefix(Coordinator.markerRolePrefix) {
                // Public load board marker: single pin per load at pickup.
                // Use magenta as the brand accent so it reads as "tappable
                // detail" rather than a pickup/delivery role marker.
                view.markerTintColor = Coordinator.magenta
                view.glyphImage      = UIImage(systemName: "shippingbox.fill")
            } else if role.hasPrefix("pickup") {
                view.markerTintColor = Coordinator.blue
                view.glyphImage      = UIImage(systemName: "arrow.up.circle.fill")
            } else if role.hasPrefix("delivery") {
                view.markerTintColor = Coordinator.magenta
                view.glyphImage      = UIImage(systemName: "flag.fill")
            } else {
                view.markerTintColor = Coordinator.magenta
            }
            return view
        }

        /// Route taps on load-board markers back to the SwiftUI caller's
        /// `onSelectMarker` closure. The subtitle carries the load id
        /// (format: `"marker · <id>"`).
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let sub = view.annotation?.subtitle ?? nil else { return }
            guard sub.hasPrefix(Coordinator.markerRolePrefix) else { return }
            // Strip "marker · " prefix.
            let id = sub.replacingOccurrences(of: "\(Coordinator.markerRolePrefix) · ",
                                              with: "")
            onSelectMarker?(id)
            // Deselect so repeated taps on the same marker fire again.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                mapView.deselectAnnotation(view.annotation, animated: false)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Lifecycle

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate             = context.coordinator
        map.showsCompass         = showsCompass
        map.showsScale           = false
        map.showsUserLocation    = showsUserLocation
        map.userTrackingMode     = userTracking
        map.pointOfInterestFilter = .excludingAll       // we render our own POIs
        context.coordinator.mapView = map
        context.coordinator.onSelectMarker = onSelectMarker

        // Apply the brand basemap (muted + no POIs) so land reads near-white
        // / deep-slate instead of Apple's default beige / green.
        applyBrandBasemap(to: map)

        // HERE tile overlay is opt-in. Gated on the presence of OAuth
        // Bearer credentials (access key id + secret + token endpoint).
        // If they're missing, the tile overlay is omitted and the muted
        // Apple basemap shows through — same "no creds" UX as before.
        // Token-exchange failures at runtime are handled inside
        // `HereTileOverlay.loadTile(...)` (serves a transparent PNG) so
        // a transient OAuth outage never blanks the whole map.
        if useHereTiles, HereMapsConfig.hasBearerCredentials {
            let overlay = HereTileOverlay(style: effectiveStyle)
            map.addOverlay(overlay, level: .aboveLabels)
            context.coordinator.tileOverlay = overlay
        }

        apply(map: map, coordinator: context.coordinator)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // Keep basemap in sync with the current register.
        applyBrandBasemap(to: map)

        // Refresh the selection callback so we never hold a stale struct's
        // closure.
        context.coordinator.onSelectMarker = onSelectMarker

        // Manage HERE tile overlay visibility. Same no-creds fallback
        // as `makeUIView`: if the OAuth credentials aren't wired or the
        // token exchange is otherwise unavailable, drop the overlay and
        // fall back to the muted Apple basemap.
        let wantsHere = useHereTiles && HereMapsConfig.hasBearerCredentials
        if wantsHere {
            if context.coordinator.tileOverlay?.style != effectiveStyle {
                if let old = context.coordinator.tileOverlay {
                    map.removeOverlay(old)
                }
                let overlay = HereTileOverlay(style: effectiveStyle)
                map.addOverlay(overlay, level: .aboveLabels)
                context.coordinator.tileOverlay = overlay
            }
        } else if let old = context.coordinator.tileOverlay {
            map.removeOverlay(old)
            context.coordinator.tileOverlay = nil
        }

        apply(map: map, coordinator: context.coordinator)
    }

    // MARK: - Basemap

    /// Sets the Apple basemap to a brand-friendly configuration — muted
    /// emphasis on iOS 17+, no points of interest. This is what kills the
    /// beige look: `.muted` renders land as a soft near-white (light mode)
    /// and deep-slate (dark mode), both of which sit comfortably alongside
    /// our blue→magenta gradient polylines.
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

    private func apply(map: MKMapView, coordinator: Coordinator) {
        // Remove old polylines + annotations (but keep the tile overlay).
        map.removeOverlays(map.overlays.filter { !($0 is MKTileOverlay) })
        map.removeAnnotations(map.annotations)

        // Yard-layout polygon overlays — caller pre-parses the
        // terminal's GeoJSON (DockYardmapSheet does so when caps
        // are populated). Painted under polylines + pins so dock
        // lanes / staging zones render as background context.
        for poly in yardLayoutPolygons {
            map.addOverlay(poly, level: .aboveRoads)
        }

        // Full HERE route polyline (detail view).
        if let route {
            let coords = HereRoutingClient.polyline(for: route)
            if !coords.isEmpty {
                let poly = MKPolyline(coordinates: coords, count: coords.count)
                map.addOverlay(poly, level: .aboveLabels)
            }
        }

        // Public load-board markers: one pin per load at pickup. No
        // polylines, no delivery pin — the driver gets a clean overview,
        // and taps surface a full load-detail sheet.
        for marker in markers {
            let a = MKPointAnnotation()
            a.coordinate = marker.coordinate
            a.title      = marker.title
            a.subtitle   = "\(Coordinator.markerRolePrefix) · \(marker.id)"
            map.addAnnotation(a)
        }

        // Per-lane road-following route + colored pins. Kept for the
        // single-load detail/map view; the public Eusoboards surface uses
        // `markers` above instead.
        //
        // Routing (Wave-5, 2026-04-20): we no longer draw a naive
        // straight A→B `MKPolyline` here — that line cut across state
        // lines and read as a placeholder. Instead we request a real
        // driveable route via `MKDirections` (Apple's on-device routing)
        // and cache the resulting polyline on the Coordinator so repeat
        // `apply(...)` passes don't refetch. First paint of a lane shows
        // pins only for the ~300 ms the request takes; the smooth curved
        // route then lands and replaces nothing since there was no
        // stopgap straight line to remove.
        //
        // Defensive guard (2026-04-19): never render lane connectors OR
        // the dual pickup/delivery pins when `markers` is populated. The
        // Eusoboards public board is a pick-a-load surface — origin →
        // destination polylines do not belong on it. If a caller passes
        // both `markers` and `lanes` by mistake, `markers` wins and the
        // lanes are silently dropped so the user never sees the
        // "polyline + dual pin" clutter again.
        if markers.isEmpty {
            for lane in lanes {
                // Pickup/delivery pins always render immediately so the
                // user sees *where* the load is even before the route
                // comes back.
                let pickup = MKPointAnnotation()
                pickup.coordinate = lane.pickup
                pickup.title      = lane.originTitle
                pickup.subtitle   = "pickup · \(lane.id)"
                map.addAnnotation(pickup)

                let delivery = MKPointAnnotation()
                delivery.coordinate = lane.delivery
                delivery.title      = lane.destinationTitle
                delivery.subtitle   = "delivery · \(lane.id)"
                map.addAnnotation(delivery)

                // Real driveable polyline. Cache hit → draw now. Cache
                // miss → kick off one `MKDirections.calculate` request,
                // cache the result, and add the overlay on the main
                // thread when it lands.
                if let cached = coordinator.laneRouteCache[lane.id] {
                    map.addOverlay(cached, level: .aboveLabels)
                } else if !coordinator.pendingLaneRequests.contains(lane.id) {
                    coordinator.pendingLaneRequests.insert(lane.id)

                    let req = MKDirections.Request()
                    req.source        = MKMapItem(placemark: MKPlacemark(coordinate: lane.pickup))
                    req.destination   = MKMapItem(placemark: MKPlacemark(coordinate: lane.delivery))
                    req.transportType = .automobile

                    MKDirections(request: req).calculate { [weak map, weak coordinator] response, _ in
                        guard let map, let coordinator else { return }
                        coordinator.pendingLaneRequests.remove(lane.id)

                        // Pick the chosen route (first is fastest). Fall
                        // back to a straight line only if Apple's router
                        // can't produce one (e.g. across water without a
                        // bridge) — this keeps the map from ever looking
                        // empty, while still giving the user a real
                        // curved route 99 % of the time.
                        let poly: MKPolyline
                        if let route = response?.routes.first {
                            poly = route.polyline
                        } else {
                            var coords = [lane.pickup, lane.delivery]
                            poly = MKPolyline(coordinates: &coords, count: coords.count)
                        }
                        poly.title = lane.id
                        coordinator.laneRouteCache[lane.id] = poly
                        map.addOverlay(poly, level: .aboveLabels)
                    }
                }
            }
        }

        // Legacy flat-stop rendering (single-load detail view).
        for (i, stop) in stops.enumerated() {
            let a = MKPointAnnotation()
            a.coordinate = CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lng)
            let role: String
            if i == 0 {
                role = "pickup"
                a.title = "Pickup"
            } else if i == stops.count - 1 {
                role = "delivery"
                a.title = "Delivery"
            } else {
                role = "waypoint"
                a.title = "Stop \(i)"
            }
            a.subtitle = "\(role) · \(stop.cityState)"
            map.addAnnotation(a)
        }
        for extra in extraAnnotations { map.addAnnotation(extra) }

        // Camera.
        if let region = initialRegion {
            map.setRegion(region, animated: true)
        } else {
            fitCamera(map: map)
        }

        map.userTrackingMode  = userTracking
        map.showsUserLocation = showsUserLocation
        map.showsCompass      = showsCompass
    }

    /// Auto-fits the camera to enclose every coord we're rendering.
    private func fitCamera(map: MKMapView) {
        var rect = MKMapRect.null
        let eps  = MKMapSize(width: 0.01, height: 0.01)

        if let route {
            for section in route.sections {
                for c in HereRoutingClient.polyline(for: section) {
                    rect = rect.union(MKMapRect(origin: MKMapPoint(c), size: eps))
                }
            }
        }
        // Mirror the apply() guard: when markers are present (public
        // Eusoboards surface) we deliberately do not render lanes, so
        // they shouldn't influence the camera fit either.
        if markers.isEmpty {
            for lane in lanes {
                rect = rect.union(MKMapRect(origin: MKMapPoint(lane.pickup),   size: eps))
                rect = rect.union(MKMapRect(origin: MKMapPoint(lane.delivery), size: eps))
            }
        }
        for marker in markers {
            rect = rect.union(MKMapRect(origin: MKMapPoint(marker.coordinate), size: eps))
        }
        for stop in stops {
            let p = MKMapPoint(CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lng))
            rect = rect.union(MKMapRect(origin: p, size: eps))
        }

        guard !rect.isNull else { return }
        let padding = UIEdgeInsets(top: 56, left: 48, bottom: 56, right: 48)
        map.setVisibleMapRect(rect, edgePadding: padding, animated: true)
    }
}

// MARK: - Preview

#Preview("HereMapView · Light (lanes)") {
    HereMapView(
        lanes: [
            .init(id: "TPL-1",
                  originTitle: "Dallas, TX", destinationTitle: "Atlanta, GA",
                  pickup:   CLLocationCoordinate2D(latitude: 32.7767, longitude: -96.7970),
                  delivery: CLLocationCoordinate2D(latitude: 33.7490, longitude: -84.3880)),
            .init(id: "TPL-2",
                  originTitle: "Memphis, TN", destinationTitle: "Chicago, IL",
                  pickup:   CLLocationCoordinate2D(latitude: 35.1495, longitude: -90.0490),
                  delivery: CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298)),
        ]
    )
    .ignoresSafeArea()
    .preferredColorScheme(.light)
}

#Preview("HereMapView · Dark (lanes)") {
    HereMapView(
        lanes: [
            .init(id: "TPL-1",
                  originTitle: "Dallas, TX", destinationTitle: "Atlanta, GA",
                  pickup:   CLLocationCoordinate2D(latitude: 32.7767, longitude: -96.7970),
                  delivery: CLLocationCoordinate2D(latitude: 33.7490, longitude: -84.3880)),
        ]
    )
    .ignoresSafeArea()
    .preferredColorScheme(.dark)
}
