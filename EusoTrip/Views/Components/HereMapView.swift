//
//  HereMapView.swift
//  EusoTrip — SwiftUI map wrapper (legacy raster API surface).
//
//  This view's public API is unchanged
//  (same `HereMapView(...)` memberwise init, same nested `Lane` /
//  `LoadMarker` types, same stored properties), but the rendering engine
//  while its production renderer delegates to `HereVectorMapView`, the
//  app-wide live HERE OMV map with labeled road and place cartography.
//
//  The legacy inputs are mapped onto the canonical `[HereMapLayer]`
//  contract (HereMapWebView.swift):
//    • `stops` (first = Pickup, last = Delivery, middle = stops)  → markers
//    • `lanes` (pickup→delivery pairs)                            → pickup/
//                                                                   delivery
//                                                                   markers
//    • `markers` (one pin per load at pickup)                     → markers
//    • `route` (decoded HERE truck route)                         → route
//    • `yardLayoutPolygons` ([MKPolygon] dock lanes / staging)    → .adZones
//                                                                   polygons
//  Camera center is derived from the data (or the supplied
//  `initialRegion`), and dark/light follows `@Environment(\.colorScheme)`
//  exactly as before. `onSelectMarker` is forwarded straight through to
//  the live map, which hit-tests taps against the marker pins.
//
//  Only this file changed — the 022_DockAssigned yardmap caller and every
//  other call site keep their existing `HereMapView(...)` calls verbatim.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import MapKit

struct HereMapView: View {

    // MARK: - Input
    //
    // Stored properties are IDENTICAL to the legacy MKMapView version so the
    // memberwise initializer every caller uses keeps the same shape. A few
    // are no longer read by the native renderer (they were MapKit-specific:
    // `useHereTiles`, `userTracking`, `showsUserLocation`, `showsCompass`,
    // `extraAnnotations`); they remain part of the public init for source
    // compatibility and are intentionally retained even though unused here.

    /// Optional preferred HERE tile style. Retained for API compatibility;
    /// the native renderer follows `@Environment(\.colorScheme)`.
    var style: HereTileStyle? = nil

    /// A decoded HERE route to render as a route polyline.
    var route: HereRoute? = nil

    /// Legacy stop list (flat pins). First = Pickup, last = Delivery.
    /// Prefer `lanes` for multi-load views so pickup/delivery can be
    /// distinguished per lane.
    var stops: [LoadLocation] = []

    /// Per-load pickup → delivery pairs. Each lane renders as a route
    /// polyline plus two pins (pickup, delivery).
    /// Legacy — prefer `markers` for the public board view.
    var lanes: [Lane] = []

    /// One pin per load at its pickup coordinate. Tapping a pin invokes
    /// `onSelectMarker(id)` so the caller can present a detail sheet.
    var markers: [LoadMarker] = []

    /// Invoked when the user taps a marker. Forwarded straight to the
    /// canvas, which hit-tests taps and bubbles the marker id back.
    var onSelectMarker: ((String) -> Void)? = nil

    /// Retained for API compatibility (was the MapKit HERE-raster toggle).
    /// The native renderer always paints the bespoke cartography.
    var useHereTiles: Bool = true

    /// Retained for API compatibility (MapKit annotation passthrough).
    var extraAnnotations: [MKPointAnnotation] = []

    /// Optional yard-layout polygon overlay (terminal dock lanes / staging /
    /// hazmat segregation). Caller pre-parses the terminal's GeoJSON into
    /// `MKPolygon` instances; we convert each to a `HerePolygon` and render
    /// it as an `.adZones` layer (translucent brand-blue fill + stroke) on
    /// the native canvas.
    var yardLayoutPolygons: [MKPolygon] = []

    /// Initial map camera. If nil, the view auto-centers on the data.
    var initialRegion: MKCoordinateRegion? = nil

    /// User-location tracking mode. Retained for API compatibility.
    var userTracking: MKUserTrackingMode = .none

    /// Whether to show the user-location dot. Retained for API compatibility.
    var showsUserLocation: Bool = false

    /// Whether to show the compass control. Retained for API compatibility.
    var showsCompass: Bool = true

    // MARK: - Lane

    /// A single bookable lane — pickup → delivery — rendered as a route
    /// polyline with pickup/delivery pins.
    struct Lane: Identifiable, Hashable {
        let id: String
        let originTitle: String
        let destinationTitle: String
        let pickup: CLLocationCoordinate2D
        let delivery: CLLocationCoordinate2D

        static func == (lhs: Lane, rhs: Lane) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    /// A single pickup pin on the public load board. Tapping a pin opens the
    /// load detail sheet via `onSelectMarker`.
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

    // MARK: - Body

    var body: some View {
        HereVectorMapView(
            center: derivedCenter,
            zoom: derivedZoom,
            interactive: true,
            tilt: 0,
            layers: buildLayers(),
            onSelectMarker: onSelectMarker
        )
    }

    // MARK: - Input → contract mapping

    /// Translate the legacy inputs into the canonical `[HereMapLayer]`.
    private func buildLayers() -> [HereMapLayer] {
        var layers: [HereMapLayer] = []

        // Yard-layout polygons → ad-zone polygons (brand-blue, translucent).
        let zonePolys = yardLayoutPolygons.compactMap(Self.herePolygon(from:))
        if !zonePolys.isEmpty {
            layers.append(.adZones(zonePolys))
        }

        // Full HERE route → route polyline.
        // Gate out null-island (0,0) vertices so an un-geocoded endpoint isn't
        // plotted in the Atlantic (same guard the `stops` branch applies).
        if let route {
            let coords = HereRoutingClient.polyline(for: route)
                .filter { !Self.isNullIsland($0.latitude, $0.longitude) }
            if coords.count >= 2 {
                layers.append(.route(polyline: coords.map { HereLatLng($0) },
                                     colorHex: "#1473FF"))
            }
        }

        // Public load-board markers: one pin per load at pickup.
        // Drop pins at (0,0) — an un-geocoded pickup must not render a
        // real-looking pin on null island.
        if !markers.isEmpty {
            let pins = markers
                .filter { !Self.isNullIsland($0.coordinate.latitude, $0.coordinate.longitude) }
                .map { m in
                    HereMarker(at: HereLatLng(m.coordinate),
                               kind: .pickup,
                               label: m.title,
                               id: m.id)
                }
            if !pins.isEmpty {
                layers.append(.markers(pins))
            }
        } else {
            // Lanes → pickup/delivery pins. Endpoints are not a route:
            // drawing a straight segment through land or water fabricates
            // geometry. A real decoded provider route is rendered above.
            // (Mirrors the legacy guard: lanes are only drawn when the public
            //  board `markers` surface isn't in use.)
            // Skip any lane with an un-geocoded (0,0) pickup or delivery so a
            // fabricated endpoint doesn't draw a line/pin across the Atlantic.
            for lane in lanes {
                let pickupOK   = !Self.isNullIsland(lane.pickup.latitude, lane.pickup.longitude)
                let deliveryOK = !Self.isNullIsland(lane.delivery.latitude, lane.delivery.longitude)
                var pins: [HereMarker] = []
                if pickupOK {
                    pins.append(HereMarker(at: HereLatLng(lane.pickup),
                                           kind: .pickup, label: lane.originTitle, id: lane.id))
                }
                if deliveryOK {
                    pins.append(HereMarker(at: HereLatLng(lane.delivery),
                                           kind: .delivery, label: lane.destinationTitle, id: lane.id))
                }
                if !pins.isEmpty {
                    layers.append(.markers(pins))
                }
            }
        }

        // Legacy flat-stop pins (single-load detail view): first = pickup,
        // last = delivery, middle = generic stops.
        if !stops.isEmpty {
            let pins: [HereMarker] = stops.enumerated().compactMap { i, stop in
                guard !Self.isNullIsland(stop.lat, stop.lng) else { return nil }
                let kind: HereMarker.Kind
                let label: String
                if i == 0 {
                    kind = .pickup; label = stop.mapDisplayLabel.isEmpty ? "Pickup" : stop.mapDisplayLabel
                } else if i == stops.count - 1 {
                    kind = .delivery; label = stop.mapDisplayLabel.isEmpty ? "Delivery" : stop.mapDisplayLabel
                } else {
                    kind = .stop; label = "Stop \(i)"
                }
                return HereMarker(at: HereLatLng(stop.lat, stop.lng), kind: kind, label: label)
            }
            if !pins.isEmpty {
                layers.append(.markers(pins))
            }
        }

        return layers
    }

    /// Camera center: explicit `initialRegion` wins; otherwise the centroid
    /// of whatever data we're rendering; otherwise a continental-US default
    /// so the canvas never opens on null island.
    private var derivedCenter: HereLatLng {
        if let region = initialRegion {
            return HereLatLng(region.center)
        }
        var lats: [Double] = []
        var lngs: [Double] = []
        // Accumulate only real, geocoded coordinates — drop any null-island
        // (0,0)/NaN endpoint so one un-geocoded point can't drag the camera.
        func accumulate(_ lat: Double, _ lng: Double) {
            guard !Self.isNullIsland(lat, lng) else { return }
            lats.append(lat); lngs.append(lng)
        }
        if let route {
            for c in HereRoutingClient.polyline(for: route) {
                accumulate(c.latitude, c.longitude)
            }
        }
        for lane in lanes {
            accumulate(lane.pickup.latitude,   lane.pickup.longitude)
            accumulate(lane.delivery.latitude, lane.delivery.longitude)
        }
        for m in markers {
            accumulate(m.coordinate.latitude, m.coordinate.longitude)
        }
        for s in stops {
            accumulate(s.lat, s.lng)
        }
        for poly in yardLayoutPolygons {
            for c in Self.coordinates(of: poly) {
                accumulate(c.latitude, c.longitude)
            }
        }
        guard !lats.isEmpty else {
            // Continental-US default framing.
            return HereLatLng(39.5, -98.35)
        }
        let cLat = lats.reduce(0, +) / Double(lats.count)
        let cLng = lngs.reduce(0, +) / Double(lngs.count)
        return HereLatLng(cLat, cLng)
    }

    /// Zoom is informational only when a route exists (the canvas fits to the
    /// route), so a sensible mid-range default is fine. When the caller hands
    /// an `initialRegion`, approximate a zoom from its longitude span.
    private var derivedZoom: Int {
        guard let region = initialRegion else { return 6 }
        let span = region.span.longitudeDelta
        switch span {
        case ..<0.05:  return 14
        case ..<0.2:   return 12
        case ..<1:     return 10
        case ..<5:     return 8
        case ..<20:    return 6
        default:       return 4
        }
    }

    // MARK: - Coordinate validation

    /// A coordinate is unusable if it's null island (0,0) — the classic
    /// un-geocoded / fabricated sentinel — or non-finite (NaN/∞), or outside
    /// valid WGS-84 bounds. Such a point is dropped rather than plotted or
    /// averaged into the camera center.
    private static func isNullIsland(_ lat: Double, _ lng: Double) -> Bool {
        if (lat == 0 && lng == 0) { return true }
        if !lat.isFinite || !lng.isFinite { return true }
        if lat < -90 || lat > 90 || lng < -180 || lng > 180 { return true }
        return false
    }

    // MARK: - MKPolygon → HerePolygon

    /// Pull the ring coordinates out of an `MKPolygon`.
    private static func coordinates(of polygon: MKPolygon) -> [CLLocationCoordinate2D] {
        let count = polygon.pointCount
        guard count > 0 else { return [] }
        var coords = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(), count: count)
        polygon.getCoordinates(&coords, range: NSRange(location: 0, length: count))
        return coords
    }

    /// Convert an `MKPolygon` (dock lane / staging zone) to a `HerePolygon`
    /// rendered by the native canvas as a translucent brand-blue ad-zone.
    private static func herePolygon(from polygon: MKPolygon) -> HerePolygon? {
        let ring = coordinates(of: polygon).map { HereLatLng($0) }
        guard ring.count > 2 else { return nil }
        return HerePolygon(ring: ring, fillHex: "#1473FF", opacity: 0.18,
                           label: polygon.title)
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
