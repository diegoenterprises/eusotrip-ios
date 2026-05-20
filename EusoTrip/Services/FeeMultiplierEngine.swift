//
//  FeeMultiplierEngine.swift
//  Canonical 7-multiplier fee engine matching the EusoWallet spec:
//    BASE × COUNTRY × VERTICAL × PRODUCT × HAZMAT × DISTANCE × CYCLE_DAMPENER
//
//  Audit found CommissionEngine.swift implementing only BASE (4 flat rates).
//  This file declares the full parametric engine so every fee surface
//  (broker rate sheet, shipper Step 3, driver settlement preview, EusoWallet
//  ledger row) computes the same value from the same inputs.
//
//  Drop into: EusoTrip/Services/FeeMultiplierEngine.swift
//

import Foundation

// MARK: - Inputs

public struct FeeComputationInput: Codable, Hashable {
    public let baseRate: Decimal            // e.g., 0.05 = 5%
    public let originCountry: Country
    public let destinationCountry: Country
    public let vertical: Vertical
    public let trailer: TrailerCode
    public let mode: TransportMode
    public let isHazmat: Bool
    public let distanceMiles: Decimal
    public let shipperPostingCycleDays: Int   // days since shipper last posted same lane
    public let isCrossBorder: Bool
}

public enum Country: String, Codable, CaseIterable {
    case US, MX, CA
}

// MARK: - Output

public struct FeeBreakdown: Codable, Hashable {
    public let base: Decimal
    public let country: Decimal
    public let vertical: Decimal
    public let product: Decimal
    public let hazmat: Decimal
    public let distance: Decimal
    public let cycleDampener: Decimal
    public let effective: Decimal
    public let inputs: FeeComputationInput

    public var asDictionary: [String: Decimal] {
        [
            "base":           base,
            "country":        country,
            "vertical":       vertical,
            "product":        product,
            "hazmat":         hazmat,
            "distance":       distance,
            "cycleDampener":  cycleDampener,
            "effective":      effective,
        ]
    }
}

// MARK: - Engine

public enum FeeMultiplierEngine {

    /// Compute the full fee breakdown for a shipment.
    /// Effective = BASE × COUNTRY × VERTICAL × PRODUCT × HAZMAT × DISTANCE × CYCLE
    public static func compute(_ input: FeeComputationInput) -> FeeBreakdown {
        let base    = input.baseRate
        let country = countryMultiplier(origin: input.originCountry, destination: input.destinationCountry, crossBorder: input.isCrossBorder)
        let vertical = verticalMultiplier(input.vertical)
        let product = productMultiplier(input.trailer, mode: input.mode)
        let hazmat  = hazmatMultiplier(isHazmat: input.isHazmat, trailer: input.trailer)
        let distance = distanceMultiplier(input.distanceMiles)
        let cycle    = cycleDampener(input.shipperPostingCycleDays)

        let effective = base * country * vertical * product * hazmat * distance * cycle

        return FeeBreakdown(
            base: base, country: country, vertical: vertical, product: product,
            hazmat: hazmat, distance: distance, cycleDampener: cycle,
            effective: effective, inputs: input,
        )
    }

    // MARK: COUNTRY
    /// Cross-border lanes pay more (additional compliance, FX risk).
    private static func countryMultiplier(origin: Country, destination: Country, crossBorder: Bool) -> Decimal {
        if !crossBorder { return 1.00 }
        switch (origin, destination) {
        case (.US, .MX), (.MX, .US):  return 1.15
        case (.US, .CA), (.CA, .US):  return 1.08
        case (.MX, .CA), (.CA, .MX):  return 1.22
        default: return 1.05
        }
    }

    // MARK: VERTICAL
    /// Per-vertical risk + regulatory loading.
    private static func verticalMultiplier(_ v: Vertical) -> Decimal {
        switch v {
        case .generalFreight:        return 1.00
        case .ltlPartial:            return 1.05
        case .refrigerated:          return 1.10
        case .flatbedOpenDeck:       return 1.08
        case .autoTransport:         return 1.12
        case .intermodalContainer:   return 1.06
        case .dryBulkPneumatic:      return 1.08
        case .householdGoods:        return 1.15
        case .tankerLiquidBulk:      return 1.18
        case .livestock:             return 1.20
        case .heavyHaulSpecialized:  return 1.30
        case .hazmat:                return 1.35
        }
    }

    // MARK: PRODUCT
    /// Per-trailer adjustment on top of vertical (rare equipment costs more).
    private static func productMultiplier(_ t: TrailerCode, mode: TransportMode) -> Decimal {
        var m: Decimal = 1.00
        switch t {
        case .cryogenicTank:        m = 1.25
        case .lowboyRgn:            m = 1.18
        case .doubleDrop:           m = 1.15
        case .livestockCattlePot:   m = 1.12
        case .pneumaticTank:        m = 1.10
        case .hazmatBox:            m = 1.08
        case .reefer, .foodGradeLiquidTank: m = 1.06
        default:                    m = 1.00
        }
        // Rail intermodal is cheaper per mile but adds a handoff surcharge
        if mode == .rail   { m *= 0.92 }
        if mode == .vessel { m *= 0.85 }
        return m
    }

    // MARK: HAZMAT
    /// Hazmat loading on top of vertical/product (placards, ERG, segregation,
    /// driver hazmat training amortization).
    private static func hazmatMultiplier(isHazmat: Bool, trailer: TrailerCode) -> Decimal {
        guard isHazmat else { return 1.00 }
        // Tanker hazmat is the highest because of vapor recovery + tank wash + class 3/8 surcharge
        if trailer == .pressurizedGasTank || trailer == .cryogenicTank { return 1.45 }
        if trailer == .liquidTank { return 1.30 }
        if trailer == .hazmatBox  { return 1.20 }
        return 1.20
    }

    // MARK: DISTANCE
    /// Long-haul efficiency: per-mile fee decreases with distance.
    private static func distanceMultiplier(_ miles: Decimal) -> Decimal {
        switch miles {
        case ..<100:        return 1.30   // local/drayage
        case 100..<500:     return 1.10   // regional
        case 500..<1500:    return 1.00   // medium-haul
        case 1500..<3000:   return 0.95   // long-haul
        default:            return 0.92   // transcontinental
        }
    }

    // MARK: CYCLE
    /// Shipper-posting cycle dampener: rewards consistent shippers who post
    /// frequently on the same lane (discount), penalizes one-offs.
    private static func cycleDampener(_ days: Int) -> Decimal {
        switch days {
        case ..<7:     return 0.95  // weekly cadence discount
        case 7..<30:   return 1.00  // baseline
        case 30..<90:  return 1.05
        default:       return 1.10  // first-time or stale lane
        }
    }
}

// MARK: - Convenience

public extension FeeBreakdown {
    /// Render the breakdown as a human-readable rate-sheet block.
    var humanRateSheet: String {
        func pct(_ d: Decimal) -> String {
            let n = NSDecimalNumber(decimal: d).doubleValue
            return String(format: "%.1f%%", (n - 1) * 100)
        }
        return """
        BASE          \(base)
        × COUNTRY     \(country)  (\(pct(country)))
        × VERTICAL    \(vertical) (\(pct(vertical)))
        × PRODUCT     \(product)  (\(pct(product)))
        × HAZMAT      \(hazmat)   (\(pct(hazmat)))
        × DISTANCE    \(distance) (\(pct(distance)))
        × CYCLE       \(cycleDampener) (\(pct(cycleDampener)))
        = EFFECTIVE   \(effective)
        """
    }
}
