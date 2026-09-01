//
//  Load.swift
//  EusoTrip — Codable mirrors of tRPC `loadsRouter` response shapes
//
//  Authority: frontend/server/routers/loads.ts
//    • loads.search       → returns [LoadSummary] (projection)
//    • loads.getById /
//      load_details MCP   → returns Load (full record with pickup/delivery JSON)
//
//  tRPC returns numeric DECIMAL columns as strings ("10200.00") and
//  dates as ISO-8601. We decode both safely.
//

import Foundation
import CoreLocation

// MARK: - Location

/// Matches `LocationJson` from loads.ts (pickupLocation / deliveryLocation).
struct LoadLocation: Codable, Hashable {
    let address: String
    let city: String
    let state: String
    let zipCode: String
    let lat: Double?
    let lng: Double?

    /// "Shreveport, LA"
    var cityState: String {
        [city, state].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Street + city/state + zip for map markers and route cards. Coordinates
    /// are a last-resort label only when the address block is genuinely absent.
    var streetCityStateZip: String {
        let place = [cityState, zipCode].filter { !$0.isEmpty }.joined(separator: " ")
        return [address, place].filter { !$0.isEmpty }.joined(separator: " - ")
    }

    var hasDisplayableCoordinate: Bool {
        coordinatePair != nil
    }

    var coordinatePair: (lat: Double, lng: Double)? {
        guard let coordinate = LatLongParser.validatedCoordinate(
            latitude: lat,
            longitude: lng
        ) else { return nil }
        return (coordinate.latitude, coordinate.longitude)
    }

    var mapDisplayLabel: String {
        if !streetCityStateZip.isEmpty { return streetCityStateZip }
        if let coordinatePair {
            return LatLongParser.displayString(
                CLLocationCoordinate2D(
                    latitude: coordinatePair.lat,
                    longitude: coordinatePair.lng
                )
            )
        }
        return ""
    }

    var optionalMapDisplayLabel: String? {
        let label = mapDisplayLabel
        return label.isEmpty ? nil : label
    }

    static let empty = LoadLocation(
        address: "", city: "", state: "", zipCode: "", lat: nil, lng: nil
    )
}

// MARK: - LoadSummary  (response of loads.search)

struct LoadSummary: Codable, Identifiable, Hashable {
    let id: String
    let loadNumber: String
    let status: String
    let cargoType: String?
    /// "Shreveport, LA"
    let origin: String
    /// "Dallas, TX"
    let destination: String
    /// Rate in USD (loads.ts returns `parseFloat(...)`).
    let rate: Double
    let pickupDate: String
    /// Committed delivery date (ISO-8601). Added to the `loads.search`
    /// projection in the build-752 server batch so the 058 Weekly Plan can
    /// place each load on its delivery day. OPTIONAL: legacy deploys omit it
    /// from the projection (it decodes nil) and draft rows may have no date,
    /// so the Weekly Plan falls back to `pickupDate` when it's nil. Empty
    /// string from the server (`?.toISOString() || ''`) is normalized to nil.
    let deliveryDate: String?
    let createdAt: String
    // 2026-05-17 — Multi-modal payload on every load row. Nullable on
    // the wire so older deploys decode cleanly; UI defaults `mode` to
    // "truck" when nil so the row always reads honestly. Powers the
    // mode badge on every load list across all 24 role surfaces
    // (shipper loads, catalyst board, broker board, dispatch, driver
    // available-loads).
    let transportMode: String?
    let multiVehicleCount: Int?
    let permitType: String?
    let rateUnit: String?
    let worldscalePct: String?
}

// MARK: - LoadSummary tolerant decode (2026-06-09 · audit M2)
//
// `loads.search` now emits the five multi-modal fields and Number()-wraps
// `worldscalePct` (DECIMAL) per the decode-shape doctrine, while legacy
// deploys still ship DECIMALs as Strings ("102.50"). This custom
// `init(from:)` lives in an EXTENSION so the synthesized memberwise init
// (used by the demo fixture below) survives. `worldscalePct` decodes
// tolerantly — String | Number → String?, absent/null → nil — so a wire
// number can never kill the whole search-row decode.
extension LoadSummary {
    private enum WireKeys: String, CodingKey {
        case id, loadNumber, status, cargoType, origin, destination
        case rate, pickupDate, deliveryDate, createdAt
        case transportMode, multiVehicleCount, permitType, rateUnit, worldscalePct
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: WireKeys.self)
        let worldscale: String? = {
            if let s = try? c.decodeIfPresent(String.self, forKey: .worldscalePct) { return s }
            if let d = try? c.decodeIfPresent(Double.self, forKey: .worldscalePct) {
                // Whole numbers without trailing ".0" — mirrors
                // Load.flexStringIfPresent's canonical form.
                return d == d.rounded() ? String(Int(d)) : String(d)
            }
            return nil   // absent / explicit null / unexpected shape
        }()
        // deliveryDate: present on the build-752 projection, absent on legacy.
        // The server emits `?.toISOString() || ''`, so an empty string means
        // "no committed delivery date" — normalize it to nil so the 058
        // Weekly Plan can cleanly fall back to pickupDate.
        // `try?` flattens `decodeIfPresent`'s `String??` to `String?`, so a
        // single bind unwraps the value; empty string ⇒ no committed date.
        let deliveryDate: String? = {
            guard let raw = try? c.decodeIfPresent(String.self, forKey: .deliveryDate),
                  !raw.isEmpty else { return nil }
            return raw
        }()
        self.init(
            id: try c.decode(String.self, forKey: .id),
            loadNumber: try c.decode(String.self, forKey: .loadNumber),
            status: try c.decode(String.self, forKey: .status),
            cargoType: try c.decodeIfPresent(String.self, forKey: .cargoType),
            origin: try c.decode(String.self, forKey: .origin),
            destination: try c.decode(String.self, forKey: .destination),
            rate: try c.decode(Double.self, forKey: .rate),
            pickupDate: try c.decode(String.self, forKey: .pickupDate),
            deliveryDate: deliveryDate,
            createdAt: try c.decode(String.self, forKey: .createdAt),
            transportMode: try c.decodeIfPresent(String.self, forKey: .transportMode),
            multiVehicleCount: (try? c.decodeIfPresent(Int.self, forKey: .multiVehicleCount)) ?? nil,
            permitType: try c.decodeIfPresent(String.self, forKey: .permitType),
            rateUnit: try c.decodeIfPresent(String.self, forKey: .rateUnit),
            worldscalePct: worldscale
        )
    }
}

// MARK: - Load  (full record — from get_load_details / loads.getById)

struct Load: Codable, Identifiable, Hashable {
    let id: Int
    let shipperId: Int?
    let driverId: Int?
    let loadNumber: String
    let status: String
    /// Wave-4 tanker sub-state chip (loads.tanker_sub_state, migration
    /// 0100: FLOWING, SAMPLE_2_OF_4, DETACH_ARM_CAPPED…). `loads.getById`
    /// returns the full row, so the column is already on the wire —
    /// consumed by the driver equipment band's state_label (Wave B,
    /// 2026-06-10).
    let tankerSubState: String?
    let cargoType: String?
    let hazmatClass: String?
    let unNumber: String?

    /// Stored as DECIMAL string by the backend.
    let weight: String?
    let weightUnit: String?

    let pickupLocation: LoadLocation?
    let deliveryLocation: LoadLocation?

    let pickupDate: String?
    let deliveryDate: String?

    /// DECIMAL string: miles or km.
    let distance: String?
    let distanceUnit: String?
    /// DECIMAL string: "800.00".
    let rate: String?
    let currency: String?

    let commodityName: String?

    let requiresEscort: Bool?
    let escortCount: Int?

    let originState: String?
    let destState: String?

    let brokerChainDepth: Int?
    let version: Int?

    // 2026-05-17 — Multi-modal columns (migration 0307).
    let transportMode: String?
    let vesselClass: String?
    let multiVehicleCount: Int?
    let permitType: String?
    let originPort: String?
    let destPort: String?
    let worldscalePct: String?
    let worldscaleFlat: String?
    let rateUnit: String?

    // MARK: Derived

    /// Rate as Double (currency-major unit).
    var rateValue: Double {
        Double(rate ?? "") ?? 0
    }

    /// Weight as Double.
    var weightValue: Double {
        Double(weight ?? "") ?? 0
    }

    /// Distance as Double.
    var distanceValue: Double {
        Double(distance ?? "") ?? 0
    }

    /// "$2,440"
    var rateDisplay: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency ?? "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: rateValue)) ?? "$\(Int(rateValue))"
    }

    /// "linehaul · $3.94/mi · 620 mi"
    var rpmDisplay: String {
        let miles = distanceValue
        let lane = (cargoType ?? "linehaul").lowercased()
        guard miles > 0 else { return lane }
        let rpm = rateValue / miles
        return String(format: "%@ · $%.2f/mi · %d mi",
                      lane, rpm, Int(miles))
    }

    /// "Dry · 42k lb"
    var cargoWeightPill: String {
        let cargo = (cargoType ?? "General").capitalized
        let kLbs = Int((weightValue / 1000.0).rounded())
        return "\(cargo) · \(kLbs)k lb"
    }

    // MARK: - Memberwise init
    //
    // Declaring a custom `init(from decoder:)` below suppresses the
    // synthesized memberwise initializer, so we restore it explicitly here.
    // Used by the demo fixtures (`Load.demoActive()`) and any future direct
    // construction. Field order/optionality is unchanged from the original.
    init(
        id: Int,
        shipperId: Int?,
        driverId: Int?,
        loadNumber: String,
        status: String,
        cargoType: String?,
        hazmatClass: String?,
        unNumber: String?,
        weight: String?,
        weightUnit: String?,
        pickupLocation: LoadLocation?,
        deliveryLocation: LoadLocation?,
        pickupDate: String?,
        deliveryDate: String?,
        distance: String?,
        distanceUnit: String?,
        rate: String?,
        currency: String?,
        commodityName: String?,
        requiresEscort: Bool?,
        escortCount: Int?,
        originState: String?,
        destState: String?,
        brokerChainDepth: Int?,
        version: Int?,
        transportMode: String?,
        vesselClass: String?,
        multiVehicleCount: Int?,
        permitType: String?,
        originPort: String?,
        destPort: String?,
        worldscalePct: String?,
        worldscaleFlat: String?,
        rateUnit: String?,
        tankerSubState: String? = nil
    ) {
        self.id = id
        self.shipperId = shipperId
        self.driverId = driverId
        self.loadNumber = loadNumber
        self.status = status
        self.tankerSubState = tankerSubState
        self.cargoType = cargoType
        self.hazmatClass = hazmatClass
        self.unNumber = unNumber
        self.weight = weight
        self.weightUnit = weightUnit
        self.pickupLocation = pickupLocation
        self.deliveryLocation = deliveryLocation
        self.pickupDate = pickupDate
        self.deliveryDate = deliveryDate
        self.distance = distance
        self.distanceUnit = distanceUnit
        self.rate = rate
        self.currency = currency
        self.commodityName = commodityName
        self.requiresEscort = requiresEscort
        self.escortCount = escortCount
        self.originState = originState
        self.destState = destState
        self.brokerChainDepth = brokerChainDepth
        self.version = version
        self.transportMode = transportMode
        self.vesselClass = vesselClass
        self.multiVehicleCount = multiVehicleCount
        self.permitType = permitType
        self.originPort = originPort
        self.destPort = destPort
        self.worldscalePct = worldscalePct
        self.worldscaleFlat = worldscaleFlat
        self.rateUnit = rateUnit
    }

    // MARK: - Custom decode (loads.getById / get_load_details)
    //
    // The tRPC `loads.getById` shape (loads.ts ~1338-1380) does NOT line up
    // with the synthesized Codable for this struct:
    //   • `id`        → STRING  (`String(load.id)`)            — declared Int
    //   • `distance`  → NUMBER  (`resolvedDistance`)           — declared String?
    //   • rate/weight/worldscalePct/worldscaleFlat → raw DECIMAL columns that
    //     may serialize as EITHER String or Number depending on the driver.
    //   • `pickupLocation`/`deliveryLocation` → `{city,state}` ONLY (no
    //     address/zip/lat/lng) — `LoadLocation` requires all six keys.
    //   • The REAL coords live in top-level `pickupCoord`/`deliveryCoord`
    //     ({lat,lng}|null); the street address + zip live in top-level
    //     `origin`/`destination` ({address,city,state,zip}).
    //
    // This decoder is tolerant of all of the above and MERGES the four
    // location sources into the existing `LoadLocation?` fields so every
    // caller (rateValue / distanceValue / pickupLocation.cityState / …)
    // keeps working unchanged. The synthesized memberwise init (used by the
    // demo fixtures) and Hashable conformance are unaffected.

    private enum CodingKeys: String, CodingKey {
        case id, shipperId, driverId, loadNumber, status, tankerSubState, cargoType
        case hazmatClass, unNumber, weight, weightUnit
        case pickupLocation, deliveryLocation
        case pickupDate, deliveryDate
        case distance, distanceUnit, rate, currency
        case commodityName
        case requiresEscort, escortCount
        case originState, destState
        case brokerChainDepth, version
        case transportMode, vesselClass, multiVehicleCount, permitType
        case originPort, destPort
        case worldscalePct, worldscaleFlat, rateUnit
        // Sidecar keys the server emits that we merge into LoadLocation:
        case pickupCoord, deliveryCoord
        case origin, destination
    }

    /// City/state echo emitted by the server (`{city, state}` only).
    private struct CityStateEcho: Codable {
        let city: String?
        let state: String?
    }

    /// Top-level `{lat,lng}|null` route anchor.
    private struct CoordEcho: Codable {
        let lat: Double?
        let lng: Double?
    }

    /// Top-level `origin`/`destination` = `{address,city,state,zip}`.
    private struct AddressEcho: Codable {
        let address: String?
        let city: String?
        let state: String?
        let zip: String?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // 1) id — accepts String | Int | Double. Server sends String(load.id);
        //    prefer Int(string) and fall back to a bare numeric.
        self.id = try Self.flexInt(c, .id) ?? 0

        self.shipperId = Self.flexIntIfPresent(c, .shipperId)
        self.driverId  = Self.flexIntIfPresent(c, .driverId)

        self.loadNumber = try c.decodeIfPresent(String.self, forKey: .loadNumber) ?? ""
        self.status     = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        self.tankerSubState = try c.decodeIfPresent(String.self, forKey: .tankerSubState)
        self.cargoType  = try c.decodeIfPresent(String.self, forKey: .cargoType)
        self.hazmatClass = try c.decodeIfPresent(String.self, forKey: .hazmatClass)
        self.unNumber    = try c.decodeIfPresent(String.self, forKey: .unNumber)

        // weight — DECIMAL, may be String or Number → keep as String?
        self.weight     = Self.flexStringIfPresent(c, .weight)
        self.weightUnit = try c.decodeIfPresent(String.self, forKey: .weightUnit)

        // 3) Merge the 4 location sources into LoadLocation?.
        let pickupEcho   = try c.decodeIfPresent(CityStateEcho.self, forKey: .pickupLocation)
        let deliveryEcho = try c.decodeIfPresent(CityStateEcho.self, forKey: .deliveryLocation)
        let pickupCoord   = try c.decodeIfPresent(CoordEcho.self, forKey: .pickupCoord)
        let deliveryCoord = try c.decodeIfPresent(CoordEcho.self, forKey: .deliveryCoord)
        let originAddr = try c.decodeIfPresent(AddressEcho.self, forKey: .origin)
        let destAddr   = try c.decodeIfPresent(AddressEcho.self, forKey: .destination)

        self.pickupLocation = Self.mergeLocation(
            echo: pickupEcho, coord: pickupCoord, addr: originAddr
        )
        self.deliveryLocation = Self.mergeLocation(
            echo: deliveryEcho, coord: deliveryCoord, addr: destAddr
        )

        self.pickupDate   = try c.decodeIfPresent(String.self, forKey: .pickupDate)
        self.deliveryDate = try c.decodeIfPresent(String.self, forKey: .deliveryDate)

        // distance — NUMBER on the wire, declared String? → coerce to String.
        self.distance     = Self.flexStringIfPresent(c, .distance)
        self.distanceUnit = try c.decodeIfPresent(String.self, forKey: .distanceUnit)

        // rate — DECIMAL, String or Number → keep as String?
        self.rate     = Self.flexStringIfPresent(c, .rate)
        self.currency = try c.decodeIfPresent(String.self, forKey: .currency)

        self.commodityName = try c.decodeIfPresent(String.self, forKey: .commodityName)

        self.requiresEscort = try c.decodeIfPresent(Bool.self, forKey: .requiresEscort)
        self.escortCount    = Self.flexIntIfPresent(c, .escortCount)

        self.originState = try c.decodeIfPresent(String.self, forKey: .originState)
        self.destState   = try c.decodeIfPresent(String.self, forKey: .destState)

        self.brokerChainDepth = Self.flexIntIfPresent(c, .brokerChainDepth)
        self.version          = Self.flexIntIfPresent(c, .version)

        self.transportMode     = try c.decodeIfPresent(String.self, forKey: .transportMode)
        self.vesselClass       = try c.decodeIfPresent(String.self, forKey: .vesselClass)
        self.multiVehicleCount = Self.flexIntIfPresent(c, .multiVehicleCount)
        self.permitType        = try c.decodeIfPresent(String.self, forKey: .permitType)
        self.originPort        = try c.decodeIfPresent(String.self, forKey: .originPort)
        self.destPort          = try c.decodeIfPresent(String.self, forKey: .destPort)

        // worldscalePct / worldscaleFlat — DECIMAL, String or Number → String?
        self.worldscalePct  = Self.flexStringIfPresent(c, .worldscalePct)
        self.worldscaleFlat = Self.flexStringIfPresent(c, .worldscaleFlat)
        self.rateUnit       = try c.decodeIfPresent(String.self, forKey: .rateUnit)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Encode id back as a String to mirror the server contract.
        try c.encode(String(id), forKey: .id)
        try c.encodeIfPresent(shipperId, forKey: .shipperId)
        try c.encodeIfPresent(driverId, forKey: .driverId)
        try c.encode(loadNumber, forKey: .loadNumber)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(tankerSubState, forKey: .tankerSubState)
        try c.encodeIfPresent(cargoType, forKey: .cargoType)
        try c.encodeIfPresent(hazmatClass, forKey: .hazmatClass)
        try c.encodeIfPresent(unNumber, forKey: .unNumber)
        try c.encodeIfPresent(weight, forKey: .weight)
        try c.encodeIfPresent(weightUnit, forKey: .weightUnit)
        // Re-emit the city/state echoes + sidecar coord/address fields so a
        // round-trip is lossless against the server shape.
        if let p = pickupLocation {
            try c.encode(CityStateEcho(city: p.city, state: p.state), forKey: .pickupLocation)
            if let coordinate = p.coordinatePair {
                try c.encode(CoordEcho(lat: coordinate.lat, lng: coordinate.lng),
                             forKey: .pickupCoord)
            } else {
                try c.encodeNil(forKey: .pickupCoord)
            }
            try c.encode(AddressEcho(address: p.address, city: p.city, state: p.state, zip: p.zipCode), forKey: .origin)
        }
        if let d = deliveryLocation {
            try c.encode(CityStateEcho(city: d.city, state: d.state), forKey: .deliveryLocation)
            if let coordinate = d.coordinatePair {
                try c.encode(CoordEcho(lat: coordinate.lat, lng: coordinate.lng),
                             forKey: .deliveryCoord)
            } else {
                try c.encodeNil(forKey: .deliveryCoord)
            }
            try c.encode(AddressEcho(address: d.address, city: d.city, state: d.state, zip: d.zipCode), forKey: .destination)
        }
        try c.encodeIfPresent(pickupDate, forKey: .pickupDate)
        try c.encodeIfPresent(deliveryDate, forKey: .deliveryDate)
        try c.encodeIfPresent(distance, forKey: .distance)
        try c.encodeIfPresent(distanceUnit, forKey: .distanceUnit)
        try c.encodeIfPresent(rate, forKey: .rate)
        try c.encodeIfPresent(currency, forKey: .currency)
        try c.encodeIfPresent(commodityName, forKey: .commodityName)
        try c.encodeIfPresent(requiresEscort, forKey: .requiresEscort)
        try c.encodeIfPresent(escortCount, forKey: .escortCount)
        try c.encodeIfPresent(originState, forKey: .originState)
        try c.encodeIfPresent(destState, forKey: .destState)
        try c.encodeIfPresent(brokerChainDepth, forKey: .brokerChainDepth)
        try c.encodeIfPresent(version, forKey: .version)
        try c.encodeIfPresent(transportMode, forKey: .transportMode)
        try c.encodeIfPresent(vesselClass, forKey: .vesselClass)
        try c.encodeIfPresent(multiVehicleCount, forKey: .multiVehicleCount)
        try c.encodeIfPresent(permitType, forKey: .permitType)
        try c.encodeIfPresent(originPort, forKey: .originPort)
        try c.encodeIfPresent(destPort, forKey: .destPort)
        try c.encodeIfPresent(worldscalePct, forKey: .worldscalePct)
        try c.encodeIfPresent(worldscaleFlat, forKey: .worldscaleFlat)
        try c.encodeIfPresent(rateUnit, forKey: .rateUnit)
    }

    // MARK: Flexible decode helpers

    /// Merge the city/state echo + {lat,lng} coord + {address,zip} into a
    /// `LoadLocation`. Returns nil only when NEITHER city/state nor a coord
    /// is present (so an all-empty echo doesn't fabricate a 0,0 location).
    private static func mergeLocation(
        echo: CityStateEcho?,
        coord: CoordEcho?,
        addr: AddressEcho?
    ) -> LoadLocation? {
        let city  = echo?.city  ?? addr?.city  ?? ""
        let state = echo?.state ?? addr?.state ?? ""
        let address = addr?.address ?? ""
        let zip     = addr?.zip ?? ""
        let coordinate = LatLongParser.validatedCoordinate(
            latitude: coord?.lat,
            longitude: coord?.lng
        )

        let hasPlace = !city.isEmpty || !state.isEmpty
        guard hasPlace || coordinate != nil else { return nil }

        return LoadLocation(
            address: address,
            city: city,
            state: state,
            zipCode: zip,
            lat: coordinate?.latitude,
            lng: coordinate?.longitude
        )
    }

    /// Decode an Int from String | Int | Double; nil if the key is absent/null.
    private static func flexInt(
        _ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
    ) throws -> Int? {
        guard c.contains(key) else { return nil }
        if let i = try? c.decode(Int.self, forKey: key) { return i }
        if let d = try? c.decode(Double.self, forKey: key) { return Int(d) }
        if let s = try? c.decode(String.self, forKey: key) {
            if let i = Int(s) { return i }
            if let d = Double(s) { return Int(d) }
            return nil
        }
        return nil   // explicit null
    }

    private static func flexIntIfPresent(
        _ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
    ) -> Int? {
        (try? flexInt(c, key)) ?? nil
    }

    /// Decode a String from String | Int | Double | Bool; nil if absent/null.
    /// Numbers are coerced to their canonical string form so the declared
    /// `String?` fields (distance/rate/weight/worldscale*) decode cleanly.
    private static func flexStringIfPresent(
        _ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
    ) -> String? {
        guard c.contains(key) else { return nil }
        if let s = try? c.decode(String.self, forKey: key) { return s }
        if let i = try? c.decode(Int.self, forKey: key) { return String(i) }
        if let d = try? c.decode(Double.self, forKey: key) {
            // Render whole numbers without a trailing ".0" so "620" not "620.0".
            return d == d.rounded() ? String(Int(d)) : String(d)
        }
        if let b = try? c.decode(Bool.self, forKey: key) { return String(b) }
        return nil   // explicit null
    }
}

// MARK: - Demo fixtures (used by DriverHomeViewModel when the backend is
// unreachable so the simulator still shows the full dashboard design.)

extension Load {
    static func demoActive() -> Load {
        let pickup = LoadLocation(
            address: "4800 Industrial Dr",
            city: "Shreveport",
            state: "LA",
            zipCode: "71106",
            lat: 32.4650,
            lng: -93.7950
        )
        let delivery = LoadLocation(
            address: "2115 Dallas Logistics Blvd",
            city: "Dallas",
            state: "TX",
            zipCode: "75212",
            lat: 32.8001,
            lng: -96.8815
        )
        let now = Date()
        let pickupISO = ISO8601DateFormatter().string(
            from: now.addingTimeInterval(60 * 42)         // pickup in 42m
        )
        let deliveryISO = ISO8601DateFormatter().string(
            from: now.addingTimeInterval(60 * 60 * 10)    // delivery +10h
        )
        return Load(
            id: 2026041500198,
            shipperId: 4421,
            driverId: 1,
            loadNumber: "EUSO-2026-04-18-001984",
            status: "assigned",
            cargoType: "dry",
            hazmatClass: nil,
            unNumber: nil,
            weight: "42000.00",
            weightUnit: "lb",
            pickupLocation: pickup,
            deliveryLocation: delivery,
            pickupDate: pickupISO,
            deliveryDate: deliveryISO,
            distance: "620.00",
            distanceUnit: "mi",
            rate: "2440.00",
            currency: "USD",
            commodityName: "Dry palletized",
            requiresEscort: false,
            escortCount: 0,
            originState: "LA",
            destState: "TX",
            brokerChainDepth: 0,
            version: 1,
            transportMode: "truck",
            vesselClass: nil,
            multiVehicleCount: 1,
            permitType: "none",
            originPort: nil,
            destPort: nil,
            worldscalePct: nil,
            worldscaleFlat: nil,
            rateUnit: "usd_per_mile"
        )
    }
}

extension LoadSummary {
    static func demoActive() -> LoadSummary {
        let now = Date()
        let pickupISO = ISO8601DateFormatter().string(
            from: now.addingTimeInterval(60 * 42)
        )
        let createdISO = ISO8601DateFormatter().string(
            from: now.addingTimeInterval(-60 * 60 * 3)   // created 3h ago
        )
        let deliveryISO = ISO8601DateFormatter().string(
            from: now.addingTimeInterval(60 * 60 * 10)   // delivery +10h
        )
        return LoadSummary(
            id: "2026041500198",
            loadNumber: "EUSO-2026-04-18-001984",
            status: "assigned",
            cargoType: "dry",
            origin: "Shreveport, LA",
            destination: "Dallas, TX",
            rate: 2440,
            pickupDate: pickupISO,
            deliveryDate: deliveryISO,
            createdAt: createdISO,
            transportMode: "truck",
            multiVehicleCount: 1,
            permitType: "none",
            rateUnit: "usd_per_mile",
            worldscalePct: nil
        )
    }
}
