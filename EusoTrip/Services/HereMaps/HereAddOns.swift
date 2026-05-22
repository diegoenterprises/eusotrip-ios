//
//  HereAddOns.swift
//  EusoTrip — the live add-on overlay layer for the canonical HERE map.
//
//  2026-05-22: `HereVectorMapView` (HereMapWebView.swift) renders the
//  basemap + whatever `[HereMapLayer]` a screen hands it. This file turns
//  the HERE REST add-ons into those layers so a screen doesn't have to
//  know how to call fuel / EV / weather / traffic / parking / truck-stops
//  / weigh-stations / safety-cameras / ad-zones — it just declares which
//  add-ons it wants and gets branded, TAPPABLE pins on the map plus a
//  ticker, a legend, and (optionally) a first-person tilt.
//
//  Doctrine for this layer:
//   • EVERY pin is tappable — each carries a stable `id` and a
//     `HereAddOnDetail`. Tapping surfaces a branded detail card. There is
//     no such thing as a "dead" / non-tappable pin.
//   • Every fetch fails *soft* — a down add-on hides its pins, it never
//     blanks the map ("no fake data": when HERE can't answer, that layer
//     simply isn't there).
//
//  Add-on → source:
//     .fuel          → HereFuelPricesClient        → .fuel pins (+ cheapest-diesel chip)
//     .ev            → HereEVClient                → .charger pins (+ kW)
//     .weather       → HereWeatherClient           → .weather pin at center
//     .traffic       → HereTrafficClient.incidents → .alert pins
//     .parking       → HereParkingClient           → .parking pins
//     .truckStops    → hereMaps.discoverNearby      → .truckStop pins
//     .weighStations → hereMaps.discoverNearby      → .weigh pins
//     .safetyCameras → HereSafetyCamerasClient      → .camera pins
//     .adZones       → hereMaps.adZonesInBbox       → .adZones polygons + .adZone centroid pins (MONETIZATION)
//     .missions      → caller-supplied geo pins      → .missionPins (GAMIFICATION)
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation

// MARK: - Which add-ons a screen wants surfaced

/// Bit-set of HERE add-on overlays a screen wants drawn on the live map.
public struct HereAddOnSet: OptionSet, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let fuel          = HereAddOnSet(rawValue: 1 << 0)
    public static let ev            = HereAddOnSet(rawValue: 1 << 1)
    public static let weather       = HereAddOnSet(rawValue: 1 << 2)
    public static let traffic       = HereAddOnSet(rawValue: 1 << 3)
    public static let adZones       = HereAddOnSet(rawValue: 1 << 4)
    public static let missions      = HereAddOnSet(rawValue: 1 << 5)
    public static let parking       = HereAddOnSet(rawValue: 1 << 6)
    public static let truckStops    = HereAddOnSet(rawValue: 1 << 7)
    public static let weighStations = HereAddOnSet(rawValue: 1 << 8)
    public static let safetyCameras = HereAddOnSet(rawValue: 1 << 9)
    public static let isa           = HereAddOnSet(rawValue: 1 << 10)  // speed limit (ticker chip)

    /// Long-haul driver en-route — don't miss a thing: fuel, chargers,
    /// weather, traffic, parking, truck stops, weigh stations, safety
    /// cameras, ISA speed limit, sponsored ad-zones, and missions.
    public static let driverEnRoute: HereAddOnSet =
        [.fuel, .ev, .weather, .traffic, .adZones, .missions,
         .parking, .truckStops, .weighStations, .safetyCameras, .isa]

    /// Shipper / dispatcher tracking — situational awareness layers that
    /// matter to a watcher (no driver-only amenity/gamification pins).
    public static let shipperTracking: HereAddOnSet =
        [.weather, .traffic, .adZones]
}

// MARK: - Legend / ticker item

public struct HereAddOnLegendItem: Identifiable, Hashable {
    public let id = UUID()
    public let glyph: String      // "F" / "E" / "W" / "!" / "$" / "M" …
    public let colorHex: String
    public let text: String       // "Diesel from $3.89" / "3 alerts" …
}

// MARK: - Detail surfaced when a pin is tapped

public struct HereAddOnDetail: Identifiable, Hashable {
    public let id: String
    public let kind: HereMarker.Kind
    public let title: String
    public let subtitle: String?
    public let glyph: String
    public let colorHex: String
    public let at: HereLatLng
}

// MARK: - Brand glyph / color per marker kind (mirrors the map JS)

enum HereMarkerStyle {
    static func glyph(_ k: HereMarker.Kind) -> String {
        switch k {
        case .truck: return "T"
        case .pickup: return "P"
        case .delivery: return "D"
        case .stop: return "S"
        case .fuel: return "F"
        case .charger: return "E"
        case .parking: return "P"
        case .alert: return "!"
        case .weather: return "W"
        case .mission: return "M"
        case .adZone: return "$"
        case .truckStop: return "T"
        case .weigh: return "S"
        case .camera: return "C"
        case .hotZone: return "H"
        }
    }
    static func color(_ k: HereMarker.Kind) -> String {
        switch k {
        case .truck: return "#1473FF"
        case .pickup: return "#16A34A"
        case .delivery: return "#DC2626"
        case .stop: return "#6B7280"
        case .fuel: return "#F59E0B"
        case .charger: return "#10B981"
        case .parking: return "#2563EB"
        case .alert: return "#EF4444"
        case .weather: return "#38BDF8"
        case .mission: return "#A855F7"
        case .adZone: return "#EC4899"
        case .truckStop: return "#B45309"
        case .weigh: return "#0EA5E9"
        case .camera: return "#6366F1"
        case .hotZone: return "#F97316"
        }
    }
    static func title(_ k: HereMarker.Kind) -> String {
        switch k {
        case .truck: return "Vehicle"
        case .pickup: return "Pickup"
        case .delivery: return "Delivery"
        case .stop: return "Stop"
        case .fuel: return "Fuel"
        case .charger: return "EV charger"
        case .parking: return "Parking"
        case .alert: return "Traffic alert"
        case .weather: return "Weather"
        case .mission: return "Haul mission"
        case .adZone: return "Sponsored zone"
        case .truckStop: return "Truck stop"
        case .weigh: return "Weigh station"
        case .camera: return "Safety camera"
        case .hotZone: return "Demand hot zone"
        }
    }
}

// MARK: - The model

@MainActor
public final class HereAddOnsModel: ObservableObject {
    /// Add-on pins/polygons, ready to concatenate onto a screen's base layers.
    @Published public private(set) var layers: [HereMapLayer] = []
    /// Compact legend / ticker describing what's currently on the map.
    @Published public private(set) var legend: [HereAddOnLegendItem] = []
    /// id → detail, for the tap-to-open card.
    @Published public private(set) var details: [String: HereAddOnDetail] = [:]
    @Published public private(set) var isLoading = false

    public init() {}

    /// Internal accumulator each fetcher returns.
    struct AddOnFetch {
        var markers: [HereMarker] = []
        var polygons: [HerePolygon] = []
        var details: [HereAddOnDetail] = []
        var chip: HereAddOnLegendItem? = nil
    }

    /// Fetch every enabled add-on around `center` (ad-zones use the bbox of
    /// `route` when present), then publish layers + details + legend.
    public func load(
        center: HereLatLng,
        route: [HereLatLng] = [],
        enabled: HereAddOnSet,
        radiusMeters: Int = 40_000,
        missionPins: [HereMarker] = []
    ) async {
        isLoading = true
        defer { isLoading = false }

        let coord = CLLocationCoordinate2D(latitude: center.lat, longitude: center.lng)

        // Independent fetches, concurrent. Explicit AddOnFetch type so the
        // disabled-branch default coerces cleanly.
        async let fuel: AddOnFetch =
            enabled.contains(.fuel)          ? Self.fetchFuel(coord, radiusMeters)            : AddOnFetch()
        async let ev: AddOnFetch =
            enabled.contains(.ev)            ? Self.fetchEV(coord)                            : AddOnFetch()
        async let weather: AddOnFetch =
            enabled.contains(.weather)       ? Self.fetchWeather(coord)                       : AddOnFetch()
        async let traffic: AddOnFetch =
            enabled.contains(.traffic)       ? Self.fetchTraffic(coord)                       : AddOnFetch()
        async let parking: AddOnFetch =
            enabled.contains(.parking)       ? Self.fetchParking(coord)                       : AddOnFetch()
        async let cameras: AddOnFetch =
            enabled.contains(.safetyCameras) ? Self.fetchCameras(coord)                       : AddOnFetch()
        async let truckStops: AddOnFetch =
            enabled.contains(.truckStops)    ? Self.fetchDiscover(center, "truck stop", .truckStop) : AddOnFetch()
        async let weighStations: AddOnFetch =
            enabled.contains(.weighStations) ? Self.fetchDiscover(center, "weigh station", .weigh)  : AddOnFetch()
        async let adZones: AddOnFetch =
            enabled.contains(.adZones)       ? Self.fetchAdZones(center, route)               : AddOnFetch()
        async let isa: AddOnFetch =
            enabled.contains(.isa)           ? Self.fetchISA(center)                          : AddOnFetch()

        let parts: [AddOnFetch] = [
            await fuel, await ev, await weather, await traffic,
            await parking, await cameras, await truckStops, await weighStations,
            await adZones, await isa
        ]

        var newLayers: [HereMapLayer] = []
        var newLegend: [HereAddOnLegendItem] = []
        var newDetails: [String: HereAddOnDetail] = [:]
        var allMarkers: [HereMarker] = []
        var allPolys: [HerePolygon] = []

        for p in parts {
            allMarkers.append(contentsOf: p.markers)
            allPolys.append(contentsOf: p.polygons)
            for d in p.details { newDetails[d.id] = d }
            if let chip = p.chip { newLegend.append(chip) }
        }

        if !allPolys.isEmpty   { newLayers.append(.adZones(allPolys)) }
        if !allMarkers.isEmpty { newLayers.append(.markers(allMarkers)) }

        // Missions — caller-supplied geo pins, get ids + details too.
        if enabled.contains(.missions), !missionPins.isEmpty {
            var mp: [HereMarker] = []
            for (i, m) in missionPins.enumerated() {
                let id = (m.id?.isEmpty == false) ? m.id! : "mission:\(i)"
                mp.append(HereMarker(at: m.at, kind: .mission, label: m.label, id: id))
                newDetails[id] = HereAddOnDetail(
                    id: id, kind: .mission,
                    title: m.label ?? "Haul mission",
                    subtitle: "Tap to view this mission",
                    glyph: "M", colorHex: "#A855F7", at: m.at
                )
            }
            newLayers.append(.missionPins(mp))
            newLegend.append(.init(glyph: "M", colorHex: "#A855F7", text: "\(mp.count) missions"))
        }

        self.layers = newLayers
        self.legend = newLegend
        self.details = newDetails
    }

    // MARK: - Per-add-on fetchers (all fail soft → empty AddOnFetch)

    private static func fetchFuel(_ coord: CLLocationCoordinate2D, _ radius: Int) async -> AddOnFetch {
        var out = AddOnFetch()
        do {
            let stations = try await HereFuelPricesClient.shared.nearby(center: coord, radiusMeters: radius)
            for s in stations {
                let id = "fuel:\(s.id)"
                let name = s.brand ?? s.name ?? "Fuel stop"
                let at = HereLatLng(s.position.latitude, s.position.longitude)
                let priceTxt = s.cheapestDieselPrice.map { "\($0.currency) \(String(format: "%.2f", $0.price))/gal diesel" }
                let label = s.cheapestDieselPrice.map { "\(name) · \($0.currency) \(String(format: "%.2f", $0.price))" } ?? name
                var subs: [String] = []
                if let p = priceTxt { subs.append(p) }
                if let a = s.address?.oneLine, !a.isEmpty { subs.append(a) }
                out.markers.append(HereMarker(at: at, kind: .fuel, label: label, id: id))
                out.details.append(HereAddOnDetail(
                    id: id, kind: .fuel, title: name,
                    subtitle: subs.isEmpty ? nil : subs.joined(separator: " · "),
                    glyph: "F", colorHex: "#F59E0B", at: at))
            }
            if let cheapest = stations.compactMap({ $0.cheapestDieselPrice }).min(by: { $0.price < $1.price }) {
                out.chip = .init(glyph: "F", colorHex: "#F59E0B",
                                 text: "Diesel from \(cheapest.currency) \(String(format: "%.2f", cheapest.price))")
            }
        } catch {}
        return out
    }

    private static func fetchEV(_ coord: CLLocationCoordinate2D) async -> AddOnFetch {
        var out = AddOnFetch()
        do {
            let items = try await HereEVClient.shared.chargingStations(near: coord, limit: 30)
            for item in items {
                guard let pos = item.position else { continue }
                let id = "ev:\(item.id)"
                let at = HereLatLng(pos.latitude, pos.longitude)
                let kw = item.chargingStation?.connectors?.compactMap { $0.maxPowerLevel }.max()
                let conns = item.chargingStation?.totalNumberOfConnectors
                var subs: [String] = []
                if let kw { subs.append("\(Int(kw)) kW max") }
                if let conns { subs.append("\(conns) connectors") }
                if subs.isEmpty, let a = item.address?.label { subs.append(a) }
                let label = kw.map { "\(item.title) · \(Int($0)) kW" } ?? item.title
                out.markers.append(HereMarker(at: at, kind: .charger, label: label, id: id))
                out.details.append(HereAddOnDetail(
                    id: id, kind: .charger, title: item.title,
                    subtitle: subs.isEmpty ? nil : subs.joined(separator: " · "),
                    glyph: "E", colorHex: "#10B981", at: at))
            }
            if !out.markers.isEmpty {
                out.chip = .init(glyph: "E", colorHex: "#10B981", text: "\(out.markers.count) chargers")
            }
        } catch {}
        return out
    }

    private static func fetchWeather(_ coord: CLLocationCoordinate2D) async -> AddOnFetch {
        var out = AddOnFetch()
        do {
            let place = try await HereWeatherClient.shared.report(at: coord, products: [.observation])
            guard let obs = place.observations?.current else { return out }
            let at = HereLatLng(coord.latitude, coord.longitude)
            let desc = obs.description ?? "Current conditions"
            let chip: String = obs.temperatureFahrenheit.map { "\(Int($0.rounded()))°F · \(desc)" } ?? desc
            var subs: [String] = [desc]
            if let h = obs.humidity { subs.append("\(Int(h))% humidity") }
            if let w = obs.windSpeedMph { subs.append("wind \(Int(w)) mph") }
            let id = "wx:center"
            out.markers.append(HereMarker(at: at, kind: .weather, label: chip, id: id))
            out.details.append(HereAddOnDetail(
                id: id, kind: .weather, title: "Weather", subtitle: subs.joined(separator: " · "),
                glyph: "W", colorHex: "#38BDF8", at: at))
            out.chip = .init(glyph: "W", colorHex: "#38BDF8", text: chip)
        } catch {}
        return out
    }

    private static func fetchTraffic(_ coord: CLLocationCoordinate2D) async -> AddOnFetch {
        var out = AddOnFetch()
        do {
            let incidents = try await HereTrafficClient.shared.incidents(near: coord)
            for (idx, inc) in incidents.enumerated() {
                guard let pt = inc.location?.shape?.links?.first?.points?.first else { continue }
                let id = "alert:\(idx):\(inc.id)"
                let at = HereLatLng(pt.lat, pt.lng)
                let title = (inc.incidentDetails?.type?.replacingOccurrences(of: "_", with: " ").capitalized) ?? "Incident"
                let subtitle = inc.incidentDetails?.summary ?? inc.incidentDetails?.description
                out.markers.append(HereMarker(at: at, kind: .alert, label: subtitle ?? title, id: id))
                out.details.append(HereAddOnDetail(
                    id: id, kind: .alert, title: title, subtitle: subtitle,
                    glyph: "!", colorHex: "#EF4444", at: at))
            }
            if !out.markers.isEmpty {
                out.chip = .init(glyph: "!", colorHex: "#EF4444", text: "\(out.markers.count) alerts")
            }
        } catch {}
        return out
    }

    private static func fetchParking(_ coord: CLLocationCoordinate2D) async -> AddOnFetch {
        var out = AddOnFetch()
        do {
            let items = try await HereParkingClient.shared.parkingNearby(center: coord, limit: 30)
            for item in items {
                guard let pos = item.position else { continue }
                let id = "parking:\(item.id)"
                let at = HereLatLng(pos.latitude, pos.longitude)
                out.markers.append(HereMarker(at: at, kind: .parking, label: item.title, id: id))
                out.details.append(HereAddOnDetail(
                    id: id, kind: .parking, title: item.title,
                    subtitle: item.address?.label ?? "Truck parking",
                    glyph: "P", colorHex: "#2563EB", at: at))
            }
            if !out.markers.isEmpty {
                out.chip = .init(glyph: "P", colorHex: "#2563EB", text: "\(out.markers.count) parking")
            }
        } catch {}
        return out
    }

    private static func fetchCameras(_ coord: CLLocationCoordinate2D) async -> AddOnFetch {
        var out = AddOnFetch()
        do {
            let items = try await HereSafetyCamerasClient.shared.camerasNearby(center: coord, limit: 40)
            for item in items {
                guard let pos = item.position else { continue }
                let id = "camera:\(item.id)"
                let at = HereLatLng(pos.latitude, pos.longitude)
                var subs: [String] = []
                if let t = item.cameraType { subs.append(t.replacingOccurrences(of: "_", with: " ").capitalized) }
                if let sl = item.speedLimit { subs.append("\(Int(sl)) limit") }
                out.markers.append(HereMarker(at: at, kind: .camera, label: item.title, id: id))
                out.details.append(HereAddOnDetail(
                    id: id, kind: .camera, title: item.title,
                    subtitle: subs.isEmpty ? "Safety camera" : subs.joined(separator: " · "),
                    glyph: "C", colorHex: "#6366F1", at: at))
            }
            if !out.markers.isEmpty {
                out.chip = .init(glyph: "C", colorHex: "#6366F1", text: "\(out.markers.count) cameras")
            }
        } catch {}
        return out
    }

    // @MainActor: hereMaps.* lives on the main-actor EusoTripAPI.
    @MainActor
    private static func fetchDiscover(
        _ center: HereLatLng, _ query: String, _ kind: HereMarker.Kind
    ) async -> AddOnFetch {
        var out = AddOnFetch()
        do {
            let places = try await EusoTripAPI.shared.hereMaps.discoverNearby(
                query: query,
                at: .init(lat: center.lat, lng: center.lng),
                radiusMeters: 60_000
            )
            for place in places {
                guard let lat = place.lat, let lng = place.lng else { continue }
                let id = "\(kind.rawValue):\(place.id)"
                let at = HereLatLng(lat, lng)
                let title = place.title ?? HereMarkerStyle.title(kind)
                var subs: [String] = []
                if let c = place.category { subs.append(c) }
                if let d = place.distanceMeters { subs.append("\(d / 1609) mi away") }
                out.markers.append(HereMarker(at: at, kind: kind, label: title, id: id))
                out.details.append(HereAddOnDetail(
                    id: id, kind: kind, title: title,
                    subtitle: subs.isEmpty ? HereMarkerStyle.title(kind) : subs.joined(separator: " · "),
                    glyph: HereMarkerStyle.glyph(kind), colorHex: HereMarkerStyle.color(kind), at: at))
            }
            if !out.markers.isEmpty {
                out.chip = .init(glyph: HereMarkerStyle.glyph(kind), colorHex: HereMarkerStyle.color(kind),
                                 text: "\(out.markers.count) \(HereMarkerStyle.title(kind).lowercased())s")
            }
        } catch {}
        return out
    }

    @MainActor
    private static func fetchAdZones(_ center: HereLatLng, _ route: [HereLatLng]) async -> AddOnFetch {
        var out = AddOnFetch()
        do {
            let bbox = Self.boundingBox(center: center, route: route)
            let zones = try await EusoTripAPI.shared.hereMaps.adZonesInBbox(bbox)
            for z in zones {
                guard let poly = z.polygon, poly.count > 2 else { continue }
                let ring = poly.map { HereLatLng($0.lat, $0.lng) }
                out.polygons.append(HerePolygon(ring: ring, fillHex: "#EC4899", opacity: 0.18, label: z.name))
                let cLat = ring.map { $0.lat }.reduce(0, +) / Double(ring.count)
                let cLng = ring.map { $0.lng }.reduce(0, +) / Double(ring.count)
                let at = HereLatLng(cLat, cLng)
                let id = "adzone:\(z.id)"
                let title = z.name ?? "Sponsored zone"
                var subs: [String] = []
                if let lvl = z.saeLevel { subs.append("SAE L\(lvl)") }
                if let c = z.conditions, !c.isEmpty { subs.append(c.joined(separator: ", ")) }
                out.markers.append(HereMarker(at: at, kind: .adZone, label: title, id: id))
                out.details.append(HereAddOnDetail(
                    id: id, kind: .adZone, title: title,
                    subtitle: subs.isEmpty ? "Sponsored / SAE-ODD zone" : subs.joined(separator: " · "),
                    glyph: "$", colorHex: "#EC4899", at: at))
            }
            if !out.polygons.isEmpty {
                out.chip = .init(glyph: "$", colorHex: "#EC4899", text: "\(out.polygons.count) sponsored")
            }
        } catch {}
        return out
    }

    // ISA — intelligent speed assist. Not a pin (it's a point attribute);
    // surfaced as a ticker chip showing the posted limit at the anchor.
    @MainActor
    private static func fetchISA(_ center: HereLatLng) async -> AddOnFetch {
        var out = AddOnFetch()
        do {
            let isa = try await EusoTripAPI.shared.hereMaps.isaForPoint(lat: center.lat, lng: center.lng)
            guard let kph = isa.speedLimitKph else { return out }
            let unit = (isa.speedUnit ?? "kph").lowercased()
            let text: String
            if unit.contains("mph") {
                text = "Limit \(Int(kph.rounded())) mph"
            } else {
                text = "Limit \(Int((kph * 0.621371).rounded())) mph"
            }
            let schoolSuffix = (isa.inSchoolZone == true) ? " · school zone" : ""
            out.chip = .init(glyph: "L", colorHex: "#0EA5E9", text: text + schoolSuffix)
        } catch {}
        return out
    }

    /// BBox over the route when present, else a ~0.45° box around center.
    private static func boundingBox(center: HereLatLng, route: [HereLatLng]) -> HereMapsAPI.BBox {
        let pts = route.isEmpty ? [center] : route
        var north = -90.0, south = 90.0, east = -180.0, west = 180.0
        for p in pts {
            north = max(north, p.lat); south = min(south, p.lat)
            east  = max(east,  p.lng); west  = min(west,  p.lng)
        }
        let pad = 0.45
        return HereMapsAPI.BBox(
            north: min(90, north + pad), south: max(-90, south - pad),
            east:  min(180, east + pad), west:  max(-180, west - pad))
    }
}

// MARK: - Drop-in live map (basemap + base layers + add-ons + tap detail + ticker)

/// `HereVectorMapView` that also surfaces live HERE add-ons. Hand it the
/// route/markers the screen already knows (`baseLayers`) plus the add-ons
/// you want; it fetches them and overlays TAPPABLE pins. Tapping any
/// add-on / base pin opens a branded detail card; a `load` pin (a base
/// marker the caller gave an explicit id) routes through `onSelectMarker`
/// instead. Optional first-person tilt + ticker + legend.
public struct HereLiveMapView: View {
    let center: HereLatLng
    let zoom: Int
    let interactive: Bool
    let firstPerson: Bool
    let route: [HereLatLng]
    let baseLayers: [HereMapLayer]
    let addOns: HereAddOnSet
    let missionPins: [HereMarker]
    let showLegend: Bool
    let showTicker: Bool
    let onSelectMarker: ((String) -> Void)?

    @StateObject private var model = HereAddOnsModel()
    @State private var selectedDetail: HereAddOnDetail?

    public init(
        center: HereLatLng,
        zoom: Int = 6,
        interactive: Bool = true,
        firstPerson: Bool = false,
        route: [HereLatLng] = [],
        baseLayers: [HereMapLayer] = [],
        addOns: HereAddOnSet = .driverEnRoute,
        missionPins: [HereMarker] = [],
        showLegend: Bool = false,
        showTicker: Bool = true,
        onSelectMarker: ((String) -> Void)? = nil
    ) {
        self.center = center
        self.zoom = zoom
        self.interactive = interactive
        self.firstPerson = firstPerson
        self.route = route
        self.baseLayers = baseLayers
        self.addOns = addOns
        self.missionPins = missionPins
        self.showLegend = showLegend
        self.showTicker = showTicker
        self.onSelectMarker = onSelectMarker
    }

    public var body: some View {
        let base = processedBase()
        let combined = base.details.merging(model.details) { _, new in new }

        ZStack(alignment: .bottom) {
            HereVectorMapView(
                center: center,
                zoom: zoom,
                interactive: interactive,
                tilt: firstPerson ? 55 : 0,
                layers: base.layers + model.layers,
                onSelectMarker: { id in
                    // A caller-actionable pin (e.g. a load on the board) →
                    // route to the caller. Everything else → detail card.
                    if base.actionable.contains(id), let cb = onSelectMarker {
                        cb(id); return
                    }
                    if let detail = combined[id] {
                        selectedDetail = detail
                    } else if let cb = onSelectMarker {
                        cb(id)
                    }
                }
            )

            VStack {
                if showTicker, !model.legend.isEmpty {
                    HereAddOnTicker(items: model.legend)
                        .padding(.horizontal, 10)
                        .padding(.top, 10)
                }
                Spacer()
            }

            if showLegend, !model.legend.isEmpty {
                HStack {
                    HereAddOnLegendStrip(items: model.legend)
                        .padding(10)
                        .allowsHitTesting(false)
                    Spacer()
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }

            if let detail = selectedDetail {
                HereAddOnDetailCard(detail: detail) { selectedDetail = nil }
                    .padding(12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: selectedDetail)
        .task(id: reloadKey) {
            await model.load(center: center, route: route, enabled: addOns, missionPins: missionPins)
        }
    }

    /// Re-fetch when the anchor, zoom, add-ons, or pin counts change.
    private var reloadKey: String {
        "\(center.lat),\(center.lng)|\(addOns.rawValue)|\(route.count)|\(missionPins.count)|\(firstPerson)"
    }

    /// Process caller base layers: assign ids to any marker missing one so
    /// EVERYTHING is tappable, register details, and track which ids the
    /// caller marked actionable (i.e. provided their own id → load pin).
    private func processedBase() -> (layers: [HereMapLayer], details: [String: HereAddOnDetail], actionable: Set<String>) {
        var outLayers: [HereMapLayer] = []
        var det: [String: HereAddOnDetail] = [:]
        var actionable = Set<String>()

        for layer in baseLayers {
            if case .markers(let ms) = layer {
                var newMs: [HereMarker] = []
                for (i, m) in ms.enumerated() {
                    let hadID = (m.id?.isEmpty == false)
                    let id = hadID ? m.id! : "pin:\(m.kind.rawValue):\(i)"
                    newMs.append(HereMarker(at: m.at, kind: m.kind, label: m.label, id: id))
                    if hadID { actionable.insert(id) }
                    det[id] = HereAddOnDetail(
                        id: id, kind: m.kind,
                        title: m.label ?? HereMarkerStyle.title(m.kind),
                        subtitle: hadID ? "Tap for details" : nil,
                        glyph: HereMarkerStyle.glyph(m.kind),
                        colorHex: HereMarkerStyle.color(m.kind), at: m.at)
                }
                outLayers.append(.markers(newMs))
            } else {
                outLayers.append(layer)
            }
        }
        return (outLayers, det, actionable)
    }
}

// MARK: - Tap detail card

/// Branded bottom card shown when a pin is tapped.
public struct HereAddOnDetailCard: View {
    let detail: HereAddOnDetail
    let onClose: () -> Void

    @State private var claimMsg: String?
    @State private var claiming = false

    public init(detail: HereAddOnDetail, onClose: @escaping () -> Void) {
        self.detail = detail
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(detail.glyph)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Color(hex: detail.colorHex))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(HereMarkerStyle.title(detail.kind).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: detail.colorHex))
                        .tracking(0.6)
                    Text(detail.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    if let sub = detail.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: 4)

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            // Monetization → The Haul: sponsored zones + affiliate amenities
            // pay XP + Haul points. Informational pins (weather/alert/camera)
            // show no CTA.
            if HereHaulBridge.isRewardable(detail.kind) {
                Button {
                    guard !claiming, claimMsg == nil else { return }
                    claiming = true
                    Task {
                        let msg = await HereHaulBridge.shared.engage(detail)
                        claimMsg = msg
                        claiming = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: claimMsg == nil ? "bolt.fill" : "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(claimMsg ?? "Claim in The Haul")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#A855F7"), Color(hex: detail.colorHex)],
                            startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(claimMsg != nil || claiming)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(hex: detail.colorHex).opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }
}

// MARK: - Ticker (top, horizontally scrolling info pills)

/// Horizontally scrollable "ticker" of the live add-on highlights.
public struct HereAddOnTicker: View {
    let items: [HereAddOnLegendItem]

    public init(items: [HereAddOnLegendItem]) { self.items = items }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    HStack(spacing: 6) {
                        Text(item.glyph)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 17, height: 17)
                            .background(Color(hex: item.colorHex))
                            .clipShape(Circle())
                        Text(item.text)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                }
            }
        }
    }
}

// MARK: - Legend strip (optional, lower-left key)

/// Compact translucent legend chip-column.
public struct HereAddOnLegendStrip: View {
    let items: [HereAddOnLegendItem]

    public init(items: [HereAddOnLegendItem]) { self.items = items }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items) { item in
                HStack(spacing: 6) {
                    Text(item.glyph)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 16, height: 16)
                        .background(Color(hex: item.colorHex))
                        .clipShape(Circle())
                    Text(item.text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }
}

// Color(hex:) is provided project-wide by Theme/DesignSystem.swift
// (`init(hex string: String, alpha: Double = 1.0)`).
