//
//  TruckProfile.swift
//  EusoTrip — Swift mirror of HERE Routing v8 `vehicle` parameters
//
//  HERE's Routing API v8 accepts truck-specific parameters via repeated
//  `vehicle[<field>]=<value>` query pairs (or a JSON body on POST). This type
//  mirrors every field EusoTrip actually uses, plus a factory initializer that
//  maps our `Load` model → a fully-formed truck profile.
//
//  Docs: https://developer.here.com/documentation/routing-api/dev_guide/topics/concepts/trailer.html
//        https://developer.here.com/documentation/routing-api/dev_guide/topics/concepts/hazardous-goods.html
//
//  Units:
//    - Weights are in kilograms (HERE does not accept lbs).
//    - Lengths / heights / widths are in centimeters.
//    - Speeds are in km/h.
//
//  Powered by ESANG AI™.
//

import Foundation

// MARK: - TruckProfile

struct TruckProfile: Hashable {

    // MARK: Dimensions

    /// Gross vehicle weight including trailer + cargo, in **kg**.
    var grossWeightKg: Int?
    /// Per-axle weight in **kg** (most permits cap at 9072kg / 20k lb in the US).
    var weightPerAxleKg: Int?
    /// Height in **cm** (typical US semi: 4.11m = 411cm).
    var heightCm: Int?
    /// Width in **cm** (typical US semi: 2.59m = 259cm).
    var widthCm: Int?
    /// Overall length in **cm** (typical US tractor + 53' trailer: 2286cm).
    var lengthCm: Int?
    /// Axle count (5 = standard 18-wheeler).
    var axleCount: Int?
    /// Number of trailers (0 = straight truck, 1 = conventional, 2+ = B-train / LCV).
    var trailerCount: Int?
    /// Type of trailer — HERE uses this to pick appropriate restrictions.
    var trailerType: TrailerType?
    /// Engine emission class (for low-emission zones).
    var emissionType: EmissionType?

    // MARK: Hazmat (ADR) + tunnel

    /// Shipped hazardous goods classes (ADR 1–9). Multiple may be combined.
    var shippedHazardousGoods: Set<HazardousGoods>

    /// Tunnel restriction category per ADR.
    /// b/c/d/e — e is most restrictive. Match the driver's credentialing.
    var tunnelCategory: TunnelCategory?

    /// Shipper's disposal reported as "difficult" to route around sensitive areas.
    var disableHighwayTransitions: Bool?

    // MARK: Commercial defaults

    /// Average speed in km/h; cap so ETA math doesn't overstate.
    /// (HERE uses its traffic layer by default; this is a ceiling, not a floor.)
    var speedCapKph: Int?

    // MARK: - Nested types

    enum TrailerType: String {
        case straight       // truck body only
        case semiTrailer    // 53' or 48' semi
        case trailer        // small trailer
        case bTrain         // double-trailer
        case other

        var hereValue: String {
            switch self {
            case .straight:     return "straightTruck"
            case .semiTrailer:  return "semiTrailer"
            case .trailer:      return "trailer"
            case .bTrain:       return "bTrain"
            case .other:        return "other"
            }
        }
    }

    enum EmissionType: String {
        case euro1 = "euro1"
        case euro2 = "euro2"
        case euro3 = "euro3"
        case euro4 = "euro4"
        case euro5 = "euro5"
        case euro6 = "euro6"
        case epa   = "epa"
        case arb   = "carb"
    }

    /// ADR hazmat classes (1–9). `explosive`, `flammable`, etc. map to
    /// HERE's canonical identifiers.
    enum HazardousGoods: String, CaseIterable {
        case explosive               // Class 1
        case gas                     // Class 2
        case flammable               // Class 3
        case combustible             // Class 4
        case organic                 // Class 5
        case poison                  // Class 6
        case radioactive             // Class 7
        case corrosive               // Class 8
        case poisonousInhalation     // Class 6.1 special
        case harmfulToWater          // Class 9 (environmental)
        case other                   // Class 9 (residual)

        var hereValue: String { rawValue }

        /// Maps from EusoTrip's `Load.hazmatClass` string ("1", "2.1", "3", ...)
        /// to the HERE enumeration.
        static func fromADRClass(_ raw: String?) -> HazardousGoods? {
            guard let first = raw?.split(separator: ".").first else { return nil }
            switch first {
            case "1": return .explosive
            case "2": return .gas
            case "3": return .flammable
            case "4": return .combustible
            case "5": return .organic
            case "6": return .poison
            case "7": return .radioactive
            case "8": return .corrosive
            case "9": return .harmfulToWater
            default:  return nil
            }
        }
    }

    enum TunnelCategory: String, CaseIterable {
        case b, c, d, e
        var hereValue: String { rawValue.uppercased() }
    }

    // MARK: - Defaults

    /// A "standard US 18-wheeler, empty" profile — use when a Load isn't yet
    /// tied to specific equipment but you still want truck-aware routing.
    static let standardUSSemiEmpty = TruckProfile(
        grossWeightKg: 15_000,        // tractor + empty 53' dry van ≈ 33k lb
        weightPerAxleKg: 3_000,
        heightCm: 411,
        widthCm: 259,
        lengthCm: 2_286,
        axleCount: 5,
        trailerCount: 1,
        trailerType: .semiTrailer,
        emissionType: .epa,
        shippedHazardousGoods: [],
        tunnelCategory: nil,
        disableHighwayTransitions: false,
        speedCapKph: 105          // 65 mph
    )

    /// A "standard US 18-wheeler, fully loaded" profile.
    static let standardUSSemiLoaded = TruckProfile(
        grossWeightKg: 36_287,     // 80,000 lb GVWR cap
        weightPerAxleKg: 7_257,    // 16,000 lb per tandem
        heightCm: 411,
        widthCm: 259,
        lengthCm: 2_286,
        axleCount: 5,
        trailerCount: 1,
        trailerType: .semiTrailer,
        emissionType: .epa,
        shippedHazardousGoods: [],
        tunnelCategory: nil,
        disableHighwayTransitions: false,
        speedCapKph: 105
    )

    // MARK: - Factory from Load

    /// Derives a TruckProfile from an EusoTrip `Load`.
    ///
    /// Gross weight comes from `load.weight` + `load.weightUnit` — we convert lb → kg.
    /// Hazmat class maps through `HazardousGoods.fromADRClass`.
    /// Tunnel category defaults to `b` if the load is hazmat (safest in absence of data).
    ///
    /// - Parameter load: the Load model.
    /// - Parameter equipment: Optional equipment override — if the carrier has
    ///   already committed a specific tractor/trailer, pass its TruckProfile
    ///   and this function will overlay only the load-specific bits (weight /
    ///   hazmat) onto it.
    static func from(load: Load, baseEquipment: TruckProfile = .standardUSSemiLoaded) -> TruckProfile {
        var p = baseEquipment

        // Weight — HERE wants kg.
        if let weightValue = Double(load.weight ?? ""), weightValue > 0 {
            let unit = (load.weightUnit ?? "lb").lowercased()
            let kg: Double = (unit == "kg") ? weightValue : weightValue * 0.4535924
            p.grossWeightKg = Int(kg.rounded())
            // Rough per-axle estimate for a 5-axle rig: total / 5.
            p.weightPerAxleKg = Int((kg / Double(p.axleCount ?? 5)).rounded())
        }

        // Hazmat — one class per load in our schema. Belt-and-suspenders
        // detection: if `hazmatClass` is missing but the load carries a
        // UN number, or its cargoType screams hazmat/tanker, force a
        // safe-default Class 9 (harmfulToWater) so HERE Routing still
        // honors hazmat tunnel/viaduct restrictions per 49 CFR 173.27.
        // Without this fallback a poorly-tagged load would route via
        // hazmat-restricted infrastructure — a real DOT violation.
        let cargo = (load.cargoType ?? "").lowercased()
        let hazByClass = HazardousGoods.fromADRClass(load.hazmatClass)
        let hazByCargo = (cargo.contains("hazmat") || cargo.contains("tanker"))
            ? HazardousGoods.harmfulToWater
            : nil
        let hazByUN = (load.unNumber?.isEmpty == false)
            ? HazardousGoods.harmfulToWater
            : nil
        let resolvedHaz = hazByClass ?? hazByCargo ?? hazByUN
        if let h = resolvedHaz {
            p.shippedHazardousGoods = [h]
            // Default conservative tunnel restriction when hazmat is set.
            if p.tunnelCategory == nil { p.tunnelCategory = .b }
        }

        return p
    }

    // MARK: - Query-param serialization

    /// Serializes this profile into the flat `URLQueryItem` form used by the
    /// HERE Routing v8 API. HERE spec: `vehicle[<field>]=<value>` — each on
    /// its own query item.
    func asRoutingQueryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = []

        func item(_ name: String, _ value: Int?) {
            if let v = value { items.append(URLQueryItem(name: name, value: String(v))) }
        }
        func item(_ name: String, _ value: String?) {
            if let v = value, !v.isEmpty { items.append(URLQueryItem(name: name, value: v)) }
        }

        item("vehicle[grossWeight]",        grossWeightKg)
        item("vehicle[weightPerAxle]",      weightPerAxleKg)
        item("vehicle[height]",             heightCm)
        item("vehicle[width]",              widthCm)
        item("vehicle[length]",             lengthCm)
        item("vehicle[axleCount]",          axleCount)
        item("vehicle[trailerCount]",       trailerCount)
        item("vehicle[type]",               trailerType?.hereValue)
        item("vehicle[emissionType]",       emissionType?.rawValue)
        item("vehicle[tunnelCategory]",     tunnelCategory?.hereValue)

        if !shippedHazardousGoods.isEmpty {
            let csv = shippedHazardousGoods.map(\.hereValue).sorted().joined(separator: ",")
            items.append(URLQueryItem(name: "vehicle[shippedHazardousGoods]", value: csv))
        }

        return items
    }
}
