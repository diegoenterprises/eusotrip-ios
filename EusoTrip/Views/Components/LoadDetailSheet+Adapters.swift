//
//  LoadDetailSheet+Adapters.swift
//  EusoTrip — Bridges alternate load models onto `AvailableLoad` so any
//  caller can present the canonical `LoadDetailSheet` without a bespoke
//  detail view per model.
//
//  The Eusoboards surface uses `AvailableLoad` natively. Two other
//  callers — Driver Home's assigned-load card and the My Loads pane —
//  use `Load` (backend `loads.getById` shape) and `MyLoad` (a lighter
//  UI-only model) respectively. Rather than branch the detail sheet for
//  each of those, this file provides `AvailableLoad.from(...)` factory
//  methods that do the lossy-but-legal projection onto the shared model.
//
//  The projections preserve every field the detail sheet reads. Fields
//  that the richer models don't carry (hazmat UN/ERG, prohibited routes,
//  weight, hot score) fall back to safe neutrals — the detail sheet
//  already renders "-" for empty strings and skips empty collections,
//  so omitted data shows up as graceful blanks rather than broken UI.
//
//  Powered by ESANG AI™.
//

import Foundation
import CoreLocation

// MARK: - From MyLoad

extension AvailableLoad {

    /// Build an `AvailableLoad` from a `MyLoad` row. The My Loads surface
    /// holds aggregate UI data (origin/destination city, miles, rate,
    /// broker, progress) but not route geometry or hazmat metadata; we
    /// synthesize plausible coordinates by looking up the city in a
    /// lightweight centroid table so the map preview still draws a real
    /// polyline between the two endpoints.
    static func from(_ my: MyLoad) -> AvailableLoad {
        // Honest-or-nothing: only plot a pin when BOTH endpoints resolve
        // from the STRICT centroid table. The loose `centroid(for:)` used
        // to fall back to the CONUS geographic center (39.83, -98.58) on
        // any miss, which dropped a real-looking pickup/delivery pin in
        // Lebanon, Kansas while the label still read the true city. On a
        // miss the geometry remains nil so the map/route card suppresses
        // the lane instead of fabricating a location.
        let oReal = Self.centroidStrict(for: my.origin)
        let dReal = Self.centroidStrict(for: my.destination)
        let hasCoordinatePair = oReal != nil && dReal != nil
        let rpm = my.miles > 0 ? my.rate / Double(my.miles) : 0
        return AvailableLoad(
            id: my.id,
            origin: my.origin,
            destination: my.destination,
            miles: my.miles,
            equipment: "Dry van",
            rate: my.rate,
            rpm: rpm,
            pickupWindow: my.eta,
            broker: my.broker,
            hazmat: false,
            weight: "-",
            hotScore: 0,
            originLat: hasCoordinatePair ? oReal?.0 : nil,
            originLng: hasCoordinatePair ? oReal?.1 : nil,
            destLat: hasCoordinatePair ? dReal?.0 : nil,
            destLng: hasCoordinatePair ? dReal?.1 : nil,
            // MyLoad.id IS the numeric loadId stringified server-side
            // (`String(load.id)` in loads.search projection); preserve it
            // so Book Now can call `loadBidding.submit({ loadId: Int })`.
            backendLoadId: Int(my.id),
            originState: Self.stateFromCityState(my.origin),
            destState: Self.stateFromCityState(my.destination),
            // MyLoad is a UI-only model that carries no mode column —
            // default to truck so the detail sheet's mode-aware surfaces
            // (compliance authority, escort vocab) read correctly.
            transportMode: "truck",
            equipmentRaw: "Dry van"
        )
    }

    /// Pull the 2-letter state code out of "City, ST" strings the
    /// `MyLoad` / `LoadSummary` rows surface. Returns nil when the
    /// string isn't in city-comma-state form so the caller can decide
    /// whether to skip the rate-meter call rather than send a malformed
    /// query.
    static func stateFromCityState(_ s: String) -> String? {
        let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2 else { return nil }
        let st = parts[1].uppercased()
        return st.count == 2 ? st : nil
    }
}

// MARK: - From Load (backend `loads.getById` shape)

extension AvailableLoad {

    /// Build an `AvailableLoad` from a fully-hydrated `Load` row (the
    /// shape returned by `loads.getById`). Used when the Driver Home
    /// active-load card presents its details sheet — the Home VM holds
    /// the full record so we can surface pickup address, delivery
    /// address, hazmat class, and both geos without synthesizing them.
    ///
    /// Rate, RPM, and miles come straight off the `rateValue`,
    /// `distanceValue` helpers — which themselves coerce the backend's
    /// DECIMAL-as-string payload safely.
    static func from(_ load: Load, originCity: String? = nil, destCity: String? = nil) -> AvailableLoad {
        let pickup = load.pickupLocation ?? .empty
        let delivery = load.deliveryLocation ?? .empty
        let miles = Int(load.distanceValue.rounded())
        let rate = load.rateValue
        let rpm = miles > 0 ? rate / Double(miles) : 0
        let originDisplay: String = originCity
            ?? (pickup.cityState.isEmpty ? "-" : pickup.cityState)
        let destDisplay: String = destCity
            ?? (delivery.cityState.isEmpty ? "-" : delivery.cityState)
        let hazmat = (load.hazmatClass?.isEmpty == false)
        let weightDisplay: String = {
            let wv = load.weightValue
            guard wv > 0 else { return "-" }
            let kLbs = Int((wv / 1000.0).rounded())
            return "\(kLbs)k lb"
        }()
        let pickupWindow: String = Self.formatWindow(load.pickupDate)
        return AvailableLoad(
            id: load.loadNumber,
            origin: originDisplay,
            destination: destDisplay,
            miles: miles,
            equipment: (load.cargoType ?? "Dry").capitalized,
            rate: rate,
            rpm: rpm,
            pickupWindow: pickupWindow,
            broker: "Dispatch",  // Load model doesn't carry broker name;
                                 // detail sheet renders this as caption text.
            hazmat: hazmat,
            weight: weightDisplay,
            hotScore: 0,
            originLat: pickup.lat,
            originLng: pickup.lng,
            destLat: delivery.lat,
            destLng: delivery.lng,
            backendLoadId: load.id,
            originState: load.originState ?? (pickup.state.isEmpty ? nil : pickup.state),
            destState: load.destState ?? (delivery.state.isEmpty ? nil : delivery.state),
            // Preserve missing/unknown mode so the map can fail visibly
            // instead of silently selecting Truck.
            transportMode: load.transportMode,
            equipmentRaw: load.cargoType
        )
    }

    /// Human-readable pickup window — "Today 11:30 AM", "Tomorrow", etc.
    /// Falls back to a dash when the backend hasn't populated the ISO
    /// string yet.
    private static func formatWindow(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "-" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date: Date? = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return "-" }
        let cal = Calendar.current
        let df = DateFormatter()
        df.dateStyle = .none
        df.timeStyle = .short
        if cal.isDateInToday(date)    { return "Today · \(df.string(from: date))" }
        if cal.isDateInTomorrow(date) { return "Tomorrow · \(df.string(from: date))" }
        df.dateStyle = .medium
        return df.string(from: date)
    }
}

// MARK: - From LoadSummary (backend `loads.search` shape)

extension AvailableLoad {

    /// Build an `AvailableLoad` from the trimmed `LoadSummary` the
    /// backend's `loads.search` procedure returns. Used by the live
    /// Eusoboards board store to project wire data onto the existing
    /// card UI without touching the renderer.
    ///
    /// `LoadSummary` carries display-level strings (`origin`,
    /// `destination`, `rate`) but no route geometry or authoritative distance.
    /// This adapter therefore leaves route facts empty. The detail surface
    /// hydrates the exact load and released route.plan before rendering a line,
    /// mileage, duration, rate-per-mile, or distance-sensitive fee.
    static func from(_ s: LoadSummary) -> AvailableLoad {
        return AvailableLoad(
            id: s.loadNumber,
            origin: s.origin,
            destination: s.destination,
            miles: 0,
            equipment: (s.cargoType ?? "Dry").capitalized,
            rate: s.rate,
            rpm: 0,
            pickupWindow: s.pickupDate,
            broker: "-",                   // summary doesn't carry broker name
            hazmat: false,
            weight: "-",
            hotScore: 0,
            originLat: nil,
            originLng: nil,
            destLat: nil,
            destLng: nil,
            backendLoadId: Int(s.id),
            originState: Self.stateFromCityState(s.origin),
            destState: Self.stateFromCityState(s.destination),
            // Preserve missing/unknown mode so the map can fail visibly
            // instead of silently selecting Truck.
            transportMode: s.transportMode,
            equipmentRaw: s.cargoType
        )
    }

}

// MARK: - MyLoad projection from LoadSummary

extension MyLoad {
    /// Fold a wire `LoadSummary` onto the UI-only `MyLoad` model used
    /// by the MyLoadsSheet + DriverLoadsPane. The bucket is passed in
    /// explicitly so caller side (the store) can route the result into
    /// the right segmented tab — the summary itself only carries a
    /// free-form `status` string.
    static func from(_ s: LoadSummary, bucket: MyLoadBucket) -> MyLoad {
        MyLoad(
            id: s.loadNumber,
            bucket: bucket,
            origin: s.origin,
            destination: s.destination,
            miles: 0,
            rate: s.rate,
            status: s.status,
            eta: s.pickupDate,
            broker: "-",
            progress: bucket == .finished ? 1.0 : (bucket == .active ? 0.5 : 0.0)
        )
    }
}

// MARK: - Centroid table (lightweight)

extension AvailableLoad {

    /// Strict lookup — returns nil when the city isn't in the table
    /// so callers can branch. The previous loose `centroid(for:)`
    /// resolved every miss to the US geographic center, which made
    /// haversine distance computations between an unknown origin
    /// (Long Beach, Reno, etc.) and a known destination report
    /// 1000+ fabricated miles. Founder report 2026-05-04. With the
    /// strict lookup, callers get 0 mi instead of a wildly wrong
    /// fake distance — the UI's `miles > 0` guard then hides the
    /// badge entirely, which is the honest answer.
    fileprivate static func centroidStrict(for cityState: String) -> (Double, Double)? {
        let key = cityState
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        if let hit = Self.centroids[key] { return hit }
        if let comma = key.firstIndex(of: ",") {
            let city = key[..<comma].trimmingCharacters(in: .whitespaces)
            if let hit = Self.centroids[city] { return hit }
        }
        return nil
    }

    /// Small hand-curated table of US freight cities — matches the cities
    /// referenced in the `MyLoad` demo fixture + a handful of common
    /// expansion targets. Extend as the demo data grows.
    private static let centroids: [String: (Double, Double)] = [
        "dallas, tx":         (32.7767, -96.7970),
        "dallas":             (32.7767, -96.7970),
        "atlanta, ga":        (33.7490, -84.3880),
        "atlanta":            (33.7490, -84.3880),
        "fort worth, tx":     (32.7555, -97.3308),
        "fort worth":         (32.7555, -97.3308),
        "memphis, tn":        (35.1495, -90.0490),
        "memphis":            (35.1495, -90.0490),
        "oklahoma city, ok":  (35.4676, -97.5164),
        "oklahoma city":      (35.4676, -97.5164),
        "kansas city, mo":    (39.0997, -94.5786),
        "kansas city":        (39.0997, -94.5786),
        "houston, tx":        (29.7604, -95.3698),
        "houston":            (29.7604, -95.3698),
        "austin, tx":         (30.2672, -97.7431),
        "austin":             (30.2672, -97.7431),
        "san antonio, tx":    (29.4241, -98.4936),
        "san antonio":        (29.4241, -98.4936),
        "shreveport, la":     (32.5252, -93.7502),
        "shreveport":         (32.5252, -93.7502),
        "new orleans, la":    (29.9511, -90.0715),
        "new orleans":        (29.9511, -90.0715),
        "birmingham, al":     (33.5186, -86.8104),
        "birmingham":         (33.5186, -86.8104),
        "nashville, tn":      (36.1627, -86.7816),
        "nashville":          (36.1627, -86.7816),
        "chicago, il":        (41.8781, -87.6298),
        "chicago":            (41.8781, -87.6298),
        "denver, co":         (39.7392, -104.9903),
        "denver":             (39.7392, -104.9903),
        "phoenix, az":        (33.4484, -112.0740),
        "phoenix":            (33.4484, -112.0740),
        "los angeles, ca":    (34.0522, -118.2437),
        "los angeles":        (34.0522, -118.2437),
        "las vegas, nv":      (36.1699, -115.1398),
        "las vegas":          (36.1699, -115.1398),
        "jacksonville, fl":   (30.3322, -81.6557),
        "jacksonville":       (30.3322, -81.6557),
        "orlando, fl":        (28.5383, -81.3792),
        "orlando":            (28.5383, -81.3792),
        "miami, fl":          (25.7617, -80.1918),
        "miami":              (25.7617, -80.1918),
        // California freight network — expanded 2026-05-05 after
        // founder report ("how do you get 1000+ mile from ca to nv
        // that doesn't make sense"). Long Beach was the missing entry
        // that made `Long Beach → Las Vegas` haversine resolve from
        // US-center → 1100+ fake miles.
        "long beach, ca":     (33.7701, -118.1937),
        "long beach":         (33.7701, -118.1937),
        "san diego, ca":      (32.7157, -117.1611),
        "san diego":          (32.7157, -117.1611),
        "san francisco, ca":  (37.7749, -122.4194),
        "san francisco":      (37.7749, -122.4194),
        "oakland, ca":        (37.8044, -122.2712),
        "oakland":            (37.8044, -122.2712),
        "sacramento, ca":     (38.5816, -121.4944),
        "sacramento":         (38.5816, -121.4944),
        "fresno, ca":         (36.7378, -119.7871),
        "fresno":             (36.7378, -119.7871),
        "bakersfield, ca":    (35.3733, -119.0187),
        "bakersfield":        (35.3733, -119.0187),
        "stockton, ca":       (37.9577, -121.2908),
        "stockton":           (37.9577, -121.2908),
        "ontario, ca":        (34.0633, -117.6509),
        "ontario":            (34.0633, -117.6509),
        "riverside, ca":      (33.9533, -117.3962),
        "riverside":          (33.9533, -117.3962),
        // Pacific NW + Mountain West
        "seattle, wa":        (47.6062, -122.3321),
        "seattle":            (47.6062, -122.3321),
        "tacoma, wa":         (47.2529, -122.4443),
        "tacoma":             (47.2529, -122.4443),
        "portland, or":       (45.5152, -122.6784),
        "portland":           (45.5152, -122.6784),
        "salt lake city, ut": (40.7608, -111.8910),
        "salt lake city":     (40.7608, -111.8910),
        "boise, id":          (43.6150, -116.2023),
        "boise":              (43.6150, -116.2023),
        "reno, nv":           (39.5296, -119.8138),
        "reno":               (39.5296, -119.8138),
        "tucson, az":         (32.2226, -110.9747),
        "tucson":             (32.2226, -110.9747),
        "albuquerque, nm":    (35.0844, -106.6504),
        "albuquerque":        (35.0844, -106.6504),
        "el paso, tx":        (31.7619, -106.4850),
        "el paso":            (31.7619, -106.4850),
        // Northeast + Midwest
        "new york, ny":       (40.7128, -74.0060),
        "new york":           (40.7128, -74.0060),
        "newark, nj":         (40.7357, -74.1724),
        "newark":             (40.7357, -74.1724),
        "philadelphia, pa":   (39.9526, -75.1652),
        "philadelphia":       (39.9526, -75.1652),
        "boston, ma":         (42.3601, -71.0589),
        "boston":             (42.3601, -71.0589),
        "detroit, mi":        (42.3314, -83.0458),
        "detroit":            (42.3314, -83.0458),
        "indianapolis, in":   (39.7684, -86.1581),
        "indianapolis":       (39.7684, -86.1581),
        "columbus, oh":       (39.9612, -82.9988),
        "columbus":           (39.9612, -82.9988),
        "cleveland, oh":      (41.4993, -81.6944),
        "cleveland":          (41.4993, -81.6944),
        "cincinnati, oh":     (39.1031, -84.5120),
        "cincinnati":         (39.1031, -84.5120),
        "minneapolis, mn":    (44.9778, -93.2650),
        "minneapolis":        (44.9778, -93.2650),
        "milwaukee, wi":      (43.0389, -87.9065),
        "milwaukee":          (43.0389, -87.9065),
        "st. louis, mo":      (38.6270, -90.1994),
        "st louis, mo":       (38.6270, -90.1994),
        "saint louis, mo":    (38.6270, -90.1994),
        "st. louis":          (38.6270, -90.1994),
        "st louis":           (38.6270, -90.1994),
        "saint louis":        (38.6270, -90.1994),
        "louisville, ky":     (38.2527, -85.7585),
        "louisville":         (38.2527, -85.7585),
        // South + Southeast
        "charlotte, nc":      (35.2271, -80.8431),
        "charlotte":          (35.2271, -80.8431),
        "raleigh, nc":        (35.7796, -78.6382),
        "raleigh":            (35.7796, -78.6382),
        "richmond, va":       (37.5407, -77.4360),
        "richmond":           (37.5407, -77.4360),
        "savannah, ga":       (32.0809, -81.0912),
        "savannah":           (32.0809, -81.0912),
        "tampa, fl":          (27.9506, -82.4572),
        "tampa":              (27.9506, -82.4572),
        "fort lauderdale, fl": (26.1224, -80.1373),
        "fort lauderdale":    (26.1224, -80.1373),
        "mobile, al":         (30.6954, -88.0399),
        "mobile":             (30.6954, -88.0399),
        "baton rouge, la":    (30.4515, -91.1871),
        "baton rouge":        (30.4515, -91.1871),
        "lake charles, la":   (30.2266, -93.2174),
        "lake charles":       (30.2266, -93.2174),
        "little rock, ar":    (34.7465, -92.2896),
        "little rock":        (34.7465, -92.2896),
        // Texas freight hubs
        "lubbock, tx":        (33.5779, -101.8552),
        "lubbock":            (33.5779, -101.8552),
        "amarillo, tx":       (35.2220, -101.8313),
        "amarillo":           (35.2220, -101.8313),
        "laredo, tx":         (27.5036, -99.5076),
        "laredo":             (27.5036, -99.5076),
        "midland, tx":        (31.9974, -102.0779),
        "midland":            (31.9974, -102.0779),
        "odessa, tx":         (31.8457, -102.3676),
        "odessa":             (31.8457, -102.3676),
        "corpus christi, tx": (27.8006, -97.3964),
        "corpus christi":     (27.8006, -97.3964),
    ]
}
