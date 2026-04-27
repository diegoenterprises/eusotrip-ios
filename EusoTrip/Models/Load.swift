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

// MARK: - Location

/// Matches `LocationJson` from loads.ts (pickupLocation / deliveryLocation).
struct LoadLocation: Codable, Hashable {
    let address: String
    let city: String
    let state: String
    let zipCode: String
    let lat: Double
    let lng: Double

    /// "Shreveport, LA"
    var cityState: String {
        [city, state].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    static let empty = LoadLocation(
        address: "", city: "", state: "", zipCode: "", lat: 0, lng: 0
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
    let createdAt: String
}

// MARK: - Load  (full record — from get_load_details / loads.getById)

struct Load: Codable, Identifiable, Hashable {
    let id: Int
    let shipperId: Int?
    let driverId: Int?
    let loadNumber: String
    let status: String
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
            version: 1
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
        return LoadSummary(
            id: "2026041500198",
            loadNumber: "EUSO-2026-04-18-001984",
            status: "assigned",
            cargoType: "dry",
            origin: "Shreveport, LA",
            destination: "Dallas, TX",
            rate: 2440,
            pickupDate: pickupISO,
            createdAt: createdISO
        )
    }
}
