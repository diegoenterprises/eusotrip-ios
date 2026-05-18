//
//  MultiModalCore.swift
//  EusoTrip — Multi-modal lane + cargo + vessel foundation.
//
//  Single foundational types file for the Post-a-Load wizard's
//  multi-modal upgrade (2026-05-17 ship). Combines:
//    • TransportMode      — truck / rail / vessel / barge
//    • ModeRoute          — per-mode distance + ETA + cost range + feasibility
//    • Port directory     — top US/MX/CA/Caribbean ports for vessel feasibility
//    • VesselClass        — tanker / bulk / container / LNG classes with bbl/TEU/DWT
//    • LoadCapacityEstimate — multi-vehicle splitter ("how many trucks/cars/ships?")
//
//  Authority sources cited inline. Updates to constants must cite the
//  underlying regulation or industry source.
//

import Foundation
import CoreLocation

// MARK: - TransportMode

/// The four canonical freight modes EusoTrip's Post-a-Load wizard supports.
/// Order = display order in the Step 1 Lane mode picker.
public enum TransportMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case truck
    case rail
    case vessel
    case barge

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .truck:  return "Truck"
        case .rail:   return "Rail"
        case .vessel: return "Vessel"
        case .barge:  return "Barge"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .truck:  return "truck.box.fill"
        case .rail:   return "tram.fill"
        case .vessel: return "ferry.fill"
        case .barge:  return "sailboat.fill"
        }
    }

    /// Native rate unit per industry convention. Surfaced on the Step 3
    /// pricing card so a vessel quote never reads "$/mi" (founder bug
    /// 2026-05-17 — `LaneComparison` showed trucking $/mi for a vessel).
    public var nativeRateUnit: String {
        switch self {
        case .truck:  return "$/mi"
        case .rail:   return "$/ton-mile"
        case .vessel: return "WS · $/MT"
        case .barge:  return "$/short ton"
        }
    }
}

// MARK: - ModeRoute

/// One route option for the Step 1 Lane multi-modal picker. Built per mode
/// by `MultiModalRouter` — truck uses HERE Routing v8, vessel uses the
/// `Port` + great-circle estimator, rail uses the AAR transit-time table.
public struct ModeRoute: Identifiable, Codable, Equatable, Sendable {
    public let id: TransportMode
    public let mode: TransportMode
    public let distanceMiles: Double
    public let transitDaysRange: ClosedRange<Double>
    public let estCostUSDRange: ClosedRange<Double>
    public let feasible: Bool
    public let infeasibilityReason: String?
    public let originPort: PortHandle?         // vessel + barge only
    public let destPort: PortHandle?
    public let capacityAdvisory: String?       // "1 MR2 — 80% util"

    public init(mode: TransportMode,
                distanceMiles: Double,
                transitDaysRange: ClosedRange<Double>,
                estCostUSDRange: ClosedRange<Double>,
                feasible: Bool = true,
                infeasibilityReason: String? = nil,
                originPort: PortHandle? = nil,
                destPort: PortHandle? = nil,
                capacityAdvisory: String? = nil) {
        self.id = mode
        self.mode = mode
        self.distanceMiles = distanceMiles
        self.transitDaysRange = transitDaysRange
        self.estCostUSDRange = estCostUSDRange
        self.feasible = feasible
        self.infeasibilityReason = infeasibilityReason
        self.originPort = originPort
        self.destPort = destPort
        self.capacityAdvisory = capacityAdvisory
    }
}

extension ClosedRange where Bound == Double {
    public var asTransitLabel: String {
        let lo = lowerBound, hi = upperBound
        if lo < 1 && hi < 1 {
            return "\(Int(lo * 24))–\(Int(hi * 24)) hr"
        }
        if abs(hi - lo) < 0.25 { return "\(Int(hi.rounded())) d" }
        return "\(Int(lo.rounded()))–\(Int(hi.rounded())) d"
    }
    public var asDollarsLabel: String {
        let lo = Int(lowerBound), hi = Int(upperBound)
        if lo < 10_000 && hi < 10_000 {
            return "$\(lo)–$\(hi)"
        }
        let loK = Double(lo) / 1_000.0
        let hiK = Double(hi) / 1_000.0
        return String(format: "$%.1fk–$%.1fk", loK, hiK)
    }
}

// MARK: - Port directory

/// Cargo capabilities a port can handle. Drives vessel/barge feasibility.
public struct PortCapability: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let crude         = PortCapability(rawValue: 1 << 0)
    public static let products      = PortCapability(rawValue: 1 << 1)
    public static let lpg           = PortCapability(rawValue: 1 << 2)
    public static let lng           = PortCapability(rawValue: 1 << 3)
    public static let chemicals     = PortCapability(rawValue: 1 << 4)
    public static let container     = PortCapability(rawValue: 1 << 5)
    public static let dryBulk       = PortCapability(rawValue: 1 << 6)
    public static let breakbulk     = PortCapability(rawValue: 1 << 7)
    public static let roro          = PortCapability(rawValue: 1 << 8)
    public static let reefer        = PortCapability(rawValue: 1 << 9)
    public static let barge         = PortCapability(rawValue: 1 << 10)
}

/// Minimal port reference for use inside ModeRoute (lat/lng + name).
public struct PortHandle: Codable, Equatable, Hashable, Sendable {
    public let unlocode: String
    public let name: String
    public let lat: Double
    public let lng: Double

    public init(unlocode: String, name: String, lat: Double, lng: Double) {
        self.unlocode = unlocode; self.name = name
        self.lat = lat; self.lng = lng
    }
}

/// Authoritative port record. Source: NGA Pub 150 World Port Index +
/// USACE Waterborne Commerce + USACE Lock Performance Monitoring.
public struct Port: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let unlocode: String                 // ISO 3166-1 + 3-letter, e.g. "USHOU"
    public let name: String
    public let country: String                  // ISO 3166-1 alpha-2
    public let stateProv: String?
    public let lat: Double
    public let lng: Double
    public let depthFeet: Int?
    public let capabilities: PortCapability
    public let typicalDwellHours: ClosedRange<Double>
    public let portDuesRangeUSD: ClosedRange<Double>
    public let vlsfoUSDPerMT: Double            // bunker reference (Ship & Bunker)
    public let isBargePort: Bool                // navigable inland waterway

    public var id: String { unlocode }
    public var handle: PortHandle {
        PortHandle(unlocode: unlocode, name: name, lat: lat, lng: lng)
    }
    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

/// Curated top-50 North American port directory. Coordinates from NGA
/// Pub 150 World Port Index (public domain). Capabilities cross-referenced
/// against USACE Waterborne Commerce + AAPA member-port profiles.
/// Bunker prices May 2026 indication from Ship & Bunker.
public enum PortDirectory {

    public static let ports: [Port] = [
        // US Gulf
        .init(unlocode: "USHOU", name: "Houston, TX", country: "US", stateProv: "TX",
              lat: 29.7339, lng: -95.2772, depthFeet: 45,
              capabilities: [.crude, .products, .lpg, .lng, .chemicals, .container, .dryBulk, .breakbulk, .roro, .barge],
              typicalDwellHours: 24...48, portDuesRangeUSD: 30_000...80_000,
              vlsfoUSDPerMT: 655, isBargePort: true),
        .init(unlocode: "USCRP", name: "Corpus Christi, TX", country: "US", stateProv: "TX",
              lat: 27.8006, lng: -97.3964, depthFeet: 54,
              capabilities: [.crude, .products, .lpg, .chemicals, .dryBulk],
              typicalDwellHours: 24...48, portDuesRangeUSD: 25_000...70_000,
              vlsfoUSDPerMT: 650, isBargePort: true),
        .init(unlocode: "USBPT", name: "Beaumont / Port Arthur, TX", country: "US", stateProv: "TX",
              lat: 30.0860, lng: -94.0911, depthFeet: 40,
              capabilities: [.crude, .products, .chemicals, .dryBulk, .roro, .barge],
              typicalDwellHours: 24...48, portDuesRangeUSD: 20_000...60_000,
              vlsfoUSDPerMT: 655, isBargePort: true),
        .init(unlocode: "USMSY", name: "New Orleans / South Louisiana", country: "US", stateProv: "LA",
              lat: 29.9311, lng: -90.0658, depthFeet: 50,
              capabilities: [.crude, .products, .chemicals, .container, .dryBulk, .breakbulk, .barge],
              typicalDwellHours: 24...72, portDuesRangeUSD: 30_000...80_000,
              vlsfoUSDPerMT: 640, isBargePort: true),
        .init(unlocode: "USMOB", name: "Mobile, AL", country: "US", stateProv: "AL",
              lat: 30.6954, lng: -88.0399, depthFeet: 45,
              capabilities: [.products, .chemicals, .container, .dryBulk, .breakbulk, .roro, .barge],
              typicalDwellHours: 24...48, portDuesRangeUSD: 15_000...45_000,
              vlsfoUSDPerMT: 645, isBargePort: true),
        .init(unlocode: "USTPA", name: "Tampa, FL", country: "US", stateProv: "FL",
              lat: 27.9506, lng: -82.4572, depthFeet: 43,
              capabilities: [.products, .chemicals, .dryBulk, .container],
              typicalDwellHours: 24...48, portDuesRangeUSD: 15_000...40_000,
              vlsfoUSDPerMT: 660, isBargePort: false),

        // US East Coast
        .init(unlocode: "USJAX", name: "Jacksonville, FL", country: "US", stateProv: "FL",
              lat: 30.3322, lng: -81.6557, depthFeet: 47,
              capabilities: [.container, .roro, .breakbulk, .dryBulk, .reefer],
              typicalDwellHours: 24...48, portDuesRangeUSD: 18_000...50_000,
              vlsfoUSDPerMT: 665, isBargePort: false),
        .init(unlocode: "USSAV", name: "Savannah, GA", country: "US", stateProv: "GA",
              lat: 32.0809, lng: -81.0912, depthFeet: 47,
              capabilities: [.container, .reefer, .breakbulk, .roro],
              typicalDwellHours: 24...60, portDuesRangeUSD: 25_000...70_000,
              vlsfoUSDPerMT: 665, isBargePort: false),
        .init(unlocode: "USCHS", name: "Charleston, SC", country: "US", stateProv: "SC",
              lat: 32.7765, lng: -79.9311, depthFeet: 52,
              capabilities: [.container, .reefer, .roro, .breakbulk],
              typicalDwellHours: 24...48, portDuesRangeUSD: 22_000...60_000,
              vlsfoUSDPerMT: 665, isBargePort: false),
        .init(unlocode: "USNFK", name: "Norfolk / Virginia, VA", country: "US", stateProv: "VA",
              lat: 36.8508, lng: -76.2859, depthFeet: 55,
              capabilities: [.container, .dryBulk, .roro, .breakbulk],
              typicalDwellHours: 24...48, portDuesRangeUSD: 25_000...65_000,
              vlsfoUSDPerMT: 665, isBargePort: false),
        .init(unlocode: "USBAL", name: "Baltimore, MD", country: "US", stateProv: "MD",
              lat: 39.2604, lng: -76.5811, depthFeet: 50,
              capabilities: [.container, .dryBulk, .roro, .breakbulk],
              typicalDwellHours: 24...48, portDuesRangeUSD: 25_000...65_000,
              vlsfoUSDPerMT: 665, isBargePort: false),
        .init(unlocode: "USPHL", name: "Philadelphia, PA", country: "US", stateProv: "PA",
              lat: 39.9526, lng: -75.1652, depthFeet: 45,
              capabilities: [.crude, .products, .container, .dryBulk, .reefer],
              typicalDwellHours: 24...48, portDuesRangeUSD: 22_000...60_000,
              vlsfoUSDPerMT: 660, isBargePort: false),
        .init(unlocode: "USNYC", name: "New York / New Jersey", country: "US", stateProv: "NY",
              lat: 40.6692, lng: -74.0451, depthFeet: 50,
              capabilities: [.container, .reefer, .roro, .breakbulk, .products],
              typicalDwellHours: 24...60, portDuesRangeUSD: 35_000...90_000,
              vlsfoUSDPerMT: 660, isBargePort: false),
        .init(unlocode: "USBOS", name: "Boston, MA", country: "US", stateProv: "MA",
              lat: 42.3601, lng: -71.0589, depthFeet: 47,
              capabilities: [.container, .breakbulk, .lng],
              typicalDwellHours: 24...48, portDuesRangeUSD: 20_000...55_000,
              vlsfoUSDPerMT: 665, isBargePort: false),

        // US West Coast
        .init(unlocode: "USLAX", name: "Los Angeles, CA", country: "US", stateProv: "CA",
              lat: 33.7395, lng: -118.2610, depthFeet: 53,
              capabilities: [.container, .reefer, .roro, .breakbulk, .crude, .products],
              typicalDwellHours: 24...96, portDuesRangeUSD: 40_000...110_000,
              vlsfoUSDPerMT: 675, isBargePort: false),
        .init(unlocode: "USLGB", name: "Long Beach, CA", country: "US", stateProv: "CA",
              lat: 33.7701, lng: -118.1937, depthFeet: 76,
              capabilities: [.container, .reefer, .roro, .breakbulk, .crude, .products],
              typicalDwellHours: 24...96, portDuesRangeUSD: 40_000...110_000,
              vlsfoUSDPerMT: 675, isBargePort: false),
        .init(unlocode: "USOAK", name: "Oakland, CA", country: "US", stateProv: "CA",
              lat: 37.7959, lng: -122.2783, depthFeet: 50,
              capabilities: [.container, .reefer, .breakbulk, .roro],
              typicalDwellHours: 24...72, portDuesRangeUSD: 30_000...80_000,
              vlsfoUSDPerMT: 675, isBargePort: false),
        .init(unlocode: "USSEA", name: "Seattle, WA", country: "US", stateProv: "WA",
              lat: 47.6062, lng: -122.3321, depthFeet: 50,
              capabilities: [.container, .reefer, .breakbulk, .roro],
              typicalDwellHours: 24...60, portDuesRangeUSD: 25_000...70_000,
              vlsfoUSDPerMT: 670, isBargePort: false),
        .init(unlocode: "USTIW", name: "Tacoma, WA", country: "US", stateProv: "WA",
              lat: 47.2529, lng: -122.4443, depthFeet: 51,
              capabilities: [.container, .reefer, .breakbulk, .roro, .dryBulk],
              typicalDwellHours: 24...60, portDuesRangeUSD: 22_000...60_000,
              vlsfoUSDPerMT: 670, isBargePort: false),
        .init(unlocode: "USPDX", name: "Portland, OR", country: "US", stateProv: "OR",
              lat: 45.5152, lng: -122.6784, depthFeet: 43,
              capabilities: [.container, .dryBulk, .breakbulk, .roro, .barge],
              typicalDwellHours: 24...60, portDuesRangeUSD: 18_000...50_000,
              vlsfoUSDPerMT: 670, isBargePort: true),
        .init(unlocode: "USANC", name: "Anchorage, AK", country: "US", stateProv: "AK",
              lat: 61.2181, lng: -149.9003, depthFeet: 35,
              capabilities: [.container, .breakbulk, .roro, .products],
              typicalDwellHours: 24...72, portDuesRangeUSD: 18_000...50_000,
              vlsfoUSDPerMT: 720, isBargePort: false),
        .init(unlocode: "USHNL", name: "Honolulu, HI", country: "US", stateProv: "HI",
              lat: 21.3099, lng: -157.8581, depthFeet: 45,
              capabilities: [.container, .breakbulk, .roro, .products],
              typicalDwellHours: 24...60, portDuesRangeUSD: 20_000...55_000,
              vlsfoUSDPerMT: 720, isBargePort: false),

        // US inland barge hubs
        .init(unlocode: "USSTL", name: "St. Louis, MO", country: "US", stateProv: "MO",
              lat: 38.6270, lng: -90.1994, depthFeet: 9,
              capabilities: [.barge, .dryBulk, .breakbulk],
              typicalDwellHours: 24...96, portDuesRangeUSD: 5_000...15_000,
              vlsfoUSDPerMT: 0, isBargePort: true),
        .init(unlocode: "USMEM", name: "Memphis, TN", country: "US", stateProv: "TN",
              lat: 35.1495, lng: -90.0490, depthFeet: 9,
              capabilities: [.barge, .dryBulk, .container, .breakbulk],
              typicalDwellHours: 24...96, portDuesRangeUSD: 5_000...15_000,
              vlsfoUSDPerMT: 0, isBargePort: true),
        .init(unlocode: "USPIT", name: "Pittsburgh, PA", country: "US", stateProv: "PA",
              lat: 40.4406, lng: -79.9959, depthFeet: 9,
              capabilities: [.barge, .dryBulk, .breakbulk],
              typicalDwellHours: 24...96, portDuesRangeUSD: 5_000...15_000,
              vlsfoUSDPerMT: 0, isBargePort: true),

        // Mexico (USMCA)
        .init(unlocode: "MXLZC", name: "Lázaro Cárdenas", country: "MX", stateProv: "MICH",
              lat: 17.9579, lng: -102.1700, depthFeet: 60,
              capabilities: [.container, .reefer, .dryBulk, .roro, .breakbulk],
              typicalDwellHours: 24...72, portDuesRangeUSD: 20_000...60_000,
              vlsfoUSDPerMT: 680, isBargePort: false),
        .init(unlocode: "MXZLO", name: "Manzanillo", country: "MX", stateProv: "COL",
              lat: 19.0432, lng: -104.3208, depthFeet: 54,
              capabilities: [.container, .reefer, .dryBulk, .roro],
              typicalDwellHours: 24...72, portDuesRangeUSD: 20_000...60_000,
              vlsfoUSDPerMT: 680, isBargePort: false),
        .init(unlocode: "MXVER", name: "Veracruz", country: "MX", stateProv: "VER",
              lat: 19.1738, lng: -96.1342, depthFeet: 46,
              capabilities: [.container, .roro, .dryBulk, .breakbulk],
              typicalDwellHours: 24...72, portDuesRangeUSD: 15_000...50_000,
              vlsfoUSDPerMT: 680, isBargePort: false),
        .init(unlocode: "MXATM", name: "Altamira", country: "MX", stateProv: "TAMP",
              lat: 22.4853, lng: -97.8829, depthFeet: 46,
              capabilities: [.container, .chemicals, .dryBulk, .roro],
              typicalDwellHours: 24...72, portDuesRangeUSD: 15_000...45_000,
              vlsfoUSDPerMT: 680, isBargePort: false),

        // Canada
        .init(unlocode: "CAVAN", name: "Vancouver, BC", country: "CA", stateProv: "BC",
              lat: 49.2827, lng: -123.1207, depthFeet: 52,
              capabilities: [.container, .dryBulk, .breakbulk, .roro, .products],
              typicalDwellHours: 24...72, portDuesRangeUSD: 25_000...70_000,
              vlsfoUSDPerMT: 680, isBargePort: false),
        .init(unlocode: "CAPRR", name: "Prince Rupert, BC", country: "CA", stateProv: "BC",
              lat: 54.3150, lng: -130.3209, depthFeet: 56,
              capabilities: [.container, .dryBulk],
              typicalDwellHours: 24...72, portDuesRangeUSD: 18_000...50_000,
              vlsfoUSDPerMT: 680, isBargePort: false),
        .init(unlocode: "CAMTR", name: "Montreal, QC", country: "CA", stateProv: "QC",
              lat: 45.5017, lng: -73.5673, depthFeet: 37,
              capabilities: [.container, .dryBulk, .breakbulk, .products],
              typicalDwellHours: 24...60, portDuesRangeUSD: 18_000...50_000,
              vlsfoUSDPerMT: 670, isBargePort: false),
        .init(unlocode: "CAHAL", name: "Halifax, NS", country: "CA", stateProv: "NS",
              lat: 44.6488, lng: -63.5752, depthFeet: 60,
              capabilities: [.container, .breakbulk, .roro],
              typicalDwellHours: 24...60, portDuesRangeUSD: 18_000...50_000,
              vlsfoUSDPerMT: 670, isBargePort: false),
    ]

    public static func find(unlocode: String) -> Port? {
        ports.first { $0.unlocode == unlocode }
    }

    /// Nearest port within `maxMiles` of the given coordinate that supports
    /// at least one of the requested capabilities. Returns nil if no port
    /// matches — used by `MultiModalRouter` to gate vessel/barge mode
    /// feasibility ("Dallas has no port → Vessel infeasible").
    public static func nearest(to coord: CLLocationCoordinate2D,
                               requiring cap: PortCapability,
                               maxMiles: Double = 200) -> Port? {
        var best: (Port, Double)? = nil
        for p in ports where !p.capabilities.intersection(cap).isEmpty {
            let d = greatCircleMiles(from: coord, to: p.coordinate)
            if d <= maxMiles, best == nil || d < best!.1 {
                best = (p, d)
            }
        }
        return best?.0
    }

    /// Haversine miles between two coordinates (statute miles, not nm).
    public static func greatCircleMiles(from a: CLLocationCoordinate2D,
                                        to b: CLLocationCoordinate2D) -> Double {
        let earthRadiusMi: Double = 3958.8
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLng = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat/2) * sin(dLat/2)
              + cos(lat1) * cos(lat2) * sin(dLng/2) * sin(dLng/2)
        return 2 * earthRadiusMi * asin(min(1, sqrt(h)))
    }
}

// MARK: - VesselClass

/// Vessel size classes used by the Step 2 Equipment preview, the Step 3
/// Worldscale calculator, and the multi-vehicle splitter.
///
/// Sources: EIA AFRA method, Baltic Exchange GMB v8.3 (April 2026),
/// Clarksons SIN, BIMCO/Wikipedia consolidated.
public enum VesselClass: String, CaseIterable, Codable, Sendable {
    // Tankers
    case gp, mr1, mr2, lr1, lr2, aframax, suezmax, vlcc, ulcc
    // Bulk
    case handysize, supramax, ultramax, panamaxBulk, kamsarmax, capesize, valemax
    // Container
    case feeder, panamaxBox, neoPanamax, ulcv
    // LNG
    case lngConventional, lngQFlex, lngQMax
    // RoRo / other
    case roro

    public var displayName: String {
        switch self {
        case .gp:        return "General Purpose"
        case .mr1:       return "MR1"
        case .mr2:       return "MR2 Product Tanker"
        case .lr1:       return "LR1"
        case .lr2:       return "LR2 / Aframax-Product"
        case .aframax:   return "Aframax"
        case .suezmax:   return "Suezmax"
        case .vlcc:      return "VLCC"
        case .ulcc:      return "ULCC"
        case .handysize: return "Handysize Bulker"
        case .supramax:  return "Supramax Bulker"
        case .ultramax:  return "Ultramax Bulker"
        case .panamaxBulk: return "Panamax Bulker"
        case .kamsarmax: return "Kamsarmax Bulker"
        case .capesize:  return "Capesize Bulker"
        case .valemax:   return "Valemax"
        case .feeder:    return "Container Feeder"
        case .panamaxBox: return "Container Panamax"
        case .neoPanamax: return "Container Neo-Panamax"
        case .ulcv:      return "Container ULCV"
        case .lngConventional: return "LNG Conventional 174k m³"
        case .lngQFlex:  return "LNG Q-Flex"
        case .lngQMax:   return "LNG Q-Max"
        case .roro:      return "RoRo / PCC"
        }
    }

    /// Typical cargo capacity in barrels (tankers + LNG). nil for non-liquid.
    public var typicalBbl: Int? {
        switch self {
        case .gp:        return 130_000
        case .mr1:       return 240_000
        case .mr2:       return 330_000
        case .lr1:       return 470_000
        case .lr2:       return 675_000
        case .aframax:   return 750_000
        case .suezmax:   return 1_000_000
        case .vlcc:      return 2_000_000
        case .ulcc:      return 3_000_000
        case .lngConventional: return 1_092_000     // 174k m³ → bbl LNG-eq
        case .lngQFlex:  return 1_320_000
        case .lngQMax:   return 1_670_000
        default:         return nil
        }
    }

    /// Typical cargo in metric tons (bulkers). nil for non-bulk.
    public var typicalMT: Int? {
        switch self {
        case .handysize: return 35_000
        case .supramax:  return 58_000
        case .ultramax:  return 65_000
        case .panamaxBulk: return 75_000
        case .kamsarmax: return 82_000
        case .capesize:  return 180_000
        case .valemax:   return 400_000
        default:         return nil
        }
    }

    /// Typical TEU (containers). nil for non-container.
    public var typicalTEU: Int? {
        switch self {
        case .feeder:     return 2_000
        case .panamaxBox: return 4_500
        case .neoPanamax: return 13_000
        case .ulcv:       return 22_000
        default:          return nil
        }
    }

    /// Whether this class can fit Panama Canal Neopanamax locks (draft 15.24m).
    public var fitsPanamaNeopanamax: Bool {
        switch self {
        case .gp, .mr1, .mr2, .lr1, .lr2, .aframax,
             .handysize, .supramax, .ultramax, .panamaxBulk, .kamsarmax,
             .feeder, .panamaxBox, .neoPanamax,
             .lngConventional, .lngQFlex,
             .roro:
            return true
        case .suezmax, .vlcc, .ulcc, .capesize, .valemax, .ulcv, .lngQMax:
            return false
        }
    }
}

// MARK: - LoadCapacityEstimate (multi-vehicle calculator)

/// Result returned by `LoadCapacityCalculator.estimate(...)`. Surfaced on
/// the Step 2 Equipment preview as the symbiotic advisory line
/// ("400,000 bbl crude → 1 MR2 tanker, 80% util" or "1,870 trucks —
/// switch to rail").
public struct LoadCapacityEstimate: Codable, Equatable, Sendable {
    public let vehicleCount: Int
    public let utilizationPct: Double           // last vehicle, 0-100
    public let sensible: Bool
    public let advisory: String
    public let suggestedAltMode: TransportMode?
    public let suggestedAltLabel: String?
}

/// Compute "how many vehicles for this load?" given (qty, mode, equipment).
/// Equipment capacity sourced from 49 CFR 178.337/338 (truck tanker), 49
/// CFR 179 (rail tank cars), and BIMCO/Clarksons vessel taxonomy.
public enum LoadCapacityCalculator {

    /// Per-vehicle capacity in bbl for crude/petroleum cargo. Used as the
    /// primary axis when quantity is in bbl. Extend with weight/volume axes
    /// when adding non-liquid cargo flows.
    private static let bblPerVehicle: [String: Double] = [
        "mc306_petroleum":   214,                // 9,000 gal / 42
        "mc307_chemical":    155,                // 6,500 gal / 42
        "mc331_pressure":    275,                // 11,500 gal water cap × 0.85 fill
        "mc338_cryogenic":   310,
        "dot117_crude":      714,                // 30,000 gal / 42
        "dot111_ethanol":    714,
        "dot105_lpg":        798,
    ]

    public static func estimateCrude(barrels: Double,
                                     mode: TransportMode,
                                     equipmentKey: String,
                                     vesselClass: VesselClass? = nil) -> LoadCapacityEstimate {

        switch mode {
        case .vessel:
            guard let vc = vesselClass, let cap = vc.typicalBbl else {
                return LoadCapacityEstimate(
                    vehicleCount: 0, utilizationPct: 0, sensible: false,
                    advisory: "Pick a vessel class to estimate vessel count.",
                    suggestedAltMode: nil, suggestedAltLabel: nil)
            }
            let exact = barrels / Double(cap)
            let count = max(1, Int(ceil(exact)))
            let util = min(100, (exact - Double(count - 1)) * 100)
            if count == 1 && util < 30 {
                // Suggest a smaller class downgrade if utilization is poor.
                let alt: VesselClass? = {
                    switch vc {
                    case .vlcc:    return .suezmax
                    case .suezmax: return .aframax
                    case .aframax: return .lr1
                    case .lr1:     return .mr2
                    case .mr2:     return .mr1
                    default:       return nil
                    }
                }()
                let altLbl = alt.map { "Try \($0.displayName) (\(Int.formatThousands($0.typicalBbl ?? 0)) bbl) for tighter fit." } ?? ""
                return LoadCapacityEstimate(
                    vehicleCount: 1, utilizationPct: util,
                    sensible: true,
                    advisory: "1 × \(vc.displayName) — \(Int(util))% utilization (partial-cargo charter). \(altLbl)",
                    suggestedAltMode: nil, suggestedAltLabel: altLbl)
            }
            return LoadCapacityEstimate(
                vehicleCount: count, utilizationPct: util, sensible: count <= 4,
                advisory: count == 1
                    ? "1 × \(vc.displayName) — \(Int(util))% utilization."
                    : "\(count) × \(vc.displayName) — partial-cargo on last vessel (\(Int(util))%).",
                suggestedAltMode: nil, suggestedAltLabel: nil)

        case .rail:
            let cap = bblPerVehicle[equipmentKey] ?? 714
            let exact = barrels / cap
            let count = max(1, Int(ceil(exact)))
            let util = min(100, (exact - Double(count - 1)) * 100)
            // > 2 unit trains (240 cars) = suggest vessel
            if count > 240 {
                return LoadCapacityEstimate(
                    vehicleCount: count, utilizationPct: util, sensible: false,
                    advisory: "\(count) tank cars (\(count / 100)+ unit trains) — vessel is the right tool for \(Int.formatThousands(Int(barrels))) bbl.",
                    suggestedAltMode: .vessel,
                    suggestedAltLabel: "Charter an Aframax (~750k bbl) instead.")
            }
            let trains = max(1, Int(ceil(Double(count) / 100.0)))
            return LoadCapacityEstimate(
                vehicleCount: count, utilizationPct: util, sensible: true,
                advisory: count >= 100
                    ? "\(count) tank cars — \(trains) unit-train operation."
                    : "\(count) tank cars — block train.",
                suggestedAltMode: nil, suggestedAltLabel: nil)

        case .truck:
            let cap = bblPerVehicle[equipmentKey] ?? 214
            let exact = barrels / cap
            let count = max(1, Int(ceil(exact)))
            let util = min(100, (exact - Double(count - 1)) * 100)
            if count > 50 {
                return LoadCapacityEstimate(
                    vehicleCount: count, utilizationPct: util, sensible: false,
                    advisory: "\(count) tanker trips for \(Int.formatThousands(Int(barrels))) bbl is impractical — switch to rail or vessel.",
                    suggestedAltMode: .rail,
                    suggestedAltLabel: "DOT-117 unit train moves ~71,400 bbl per train (100 cars × 714 bbl).")
            }
            return LoadCapacityEstimate(
                vehicleCount: count, utilizationPct: util, sensible: true,
                advisory: count == 1
                    ? "1 tanker — \(Int(util))% utilization."
                    : "\(count) tankers — last truck \(Int(util))% loaded.",
                suggestedAltMode: nil, suggestedAltLabel: nil)

        case .barge:
            // Approx 30,000 bbl per tanker barge (single-skin / double-skin OPA90)
            let cap = 30_000.0
            let exact = barrels / cap
            let count = max(1, Int(ceil(exact)))
            let util = min(100, (exact - Double(count - 1)) * 100)
            return LoadCapacityEstimate(
                vehicleCount: count, utilizationPct: util, sensible: count <= 30,
                advisory: count == 1
                    ? "1 tanker barge (~30k bbl) — \(Int(util))% utilization."
                    : "\(count) tanker barges — typical 6-barge tow possible.",
                suggestedAltMode: nil, suggestedAltLabel: nil)
        }
    }
}

extension Int {
    fileprivate static func formatThousands(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
