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
//  already renders "—" for empty strings and skips empty collections,
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
        let (oLat, oLng) = Self.centroid(for: my.origin)
        let (dLat, dLng) = Self.centroid(for: my.destination)
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
            weight: "—",
            hotScore: 0,
            originLat: oLat,
            originLng: oLng,
            destLat: dLat,
            destLng: dLng,
            // MyLoad.id IS the numeric loadId stringified server-side
            // (`String(load.id)` in loads.search projection); preserve it
            // so Book Now can call `loadBidding.submit({ loadId: Int })`.
            backendLoadId: Int(my.id),
            originState: Self.stateFromCityState(my.origin),
            destState: Self.stateFromCityState(my.destination)
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
            ?? (pickup.cityState.isEmpty ? "—" : pickup.cityState)
        let destDisplay: String = destCity
            ?? (delivery.cityState.isEmpty ? "—" : delivery.cityState)
        let hazmat = (load.hazmatClass?.isEmpty == false)
        let weightDisplay: String = {
            let wv = load.weightValue
            guard wv > 0 else { return "—" }
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
            destState: load.destState ?? (delivery.state.isEmpty ? nil : delivery.state)
        )
    }

    /// Human-readable pickup window — "Today 11:30 AM", "Tomorrow", etc.
    /// Falls back to a dash when the backend hasn't populated the ISO
    /// string yet.
    private static func formatWindow(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "—" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date: Date? = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return "—" }
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
    /// `destination`, `rate`) but no route geometry, weight, or hazmat
    /// class — those get plausible centroid lookups + neutral defaults,
    /// matching the shape the `MyLoad` adapter already uses so the map
    /// draws a valid polyline instead of dropping the camera into the
    /// Atlantic.
    static func from(_ s: LoadSummary) -> AvailableLoad {
        let (oLat, oLng) = Self.centroid(for: s.origin)
        let (dLat, dLng) = Self.centroid(for: s.destination)
        return AvailableLoad(
            id: s.loadNumber,
            origin: s.origin,
            destination: s.destination,
            miles: 0,                      // not in LoadSummary — hidden in UI
            equipment: (s.cargoType ?? "Dry").capitalized,
            rate: s.rate,
            rpm: 0,                        // miles missing → rpm unknown
            pickupWindow: s.pickupDate,
            broker: "—",                   // summary doesn't carry broker name
            hazmat: false,
            weight: "—",
            hotScore: 0,
            originLat: oLat,
            originLng: oLng,
            destLat: dLat,
            destLng: dLng,
            backendLoadId: Int(s.id),
            originState: Self.stateFromCityState(s.origin),
            destState: Self.stateFromCityState(s.destination)
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
            broker: "—",
            progress: bucket == .finished ? 1.0 : (bucket == .active ? 0.5 : 0.0)
        )
    }
}

// MARK: - Centroid table (lightweight)

extension AvailableLoad {

    /// Best-effort lat/lng lookup for common US freight cities. Used by
    /// the `MyLoad` adapter so the detail-sheet map can still draw a
    /// blue→magenta polyline instead of a broken pin.
    ///
    /// Unknown cities fall back to a neutral CONUS centroid (39.83, -98.58
    /// — the geographic center of the continental US) so MapKit has
    /// something legal to render instead of (0, 0) which drops the camera
    /// into the Atlantic.
    fileprivate static func centroid(for cityState: String) -> (Double, Double) {
        let key = cityState
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        if let hit = Self.centroids[key] { return hit }
        // Try "city" prefix — handles "Dallas, TX" / "Dallas TX" variants.
        if let comma = key.firstIndex(of: ",") {
            let city = key[..<comma].trimmingCharacters(in: .whitespaces)
            if let hit = Self.centroids[city] { return hit }
        }
        return (39.8283, -98.5795)
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
    ]
}
