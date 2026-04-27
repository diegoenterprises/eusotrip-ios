//
//  WatchLoad.swift
//  EusoTrip Watch App
//
//  The skinny version of a load the wrist shows. Same vocabulary as the
//  iOS `Load` model but stripped to what fits on a 45mm face.
//

import Foundation

struct WatchLoad: Codable, Identifiable, Equatable {
    let id: String
    let displayId: String     // e.g. "LD-48291"
    let originCity: String
    let originState: String
    let destCity: String
    let destState: String
    let pickupAt: Date
    let deliverBy: Date
    let ratePerMile: Double?
    let totalRate: Double?
    let miles: Double?
    let status: String         // "assigned" | "en_route_pickup" | "loaded" | "en_route_delivery" | "delivered"
    let hazmat: Bool
    let temperatureF: Int?
    let equipment: String?     // "dry_van" | "reefer" | "flatbed"
    let brokerName: String?

    var originShort: String { "\(originCity), \(originState)" }
    var destShort: String   { "\(destCity), \(destState)" }

    static let placeholder = WatchLoad(
        id: "demo",
        displayId: "LD-48291",
        originCity: "Laredo",
        originState: "TX",
        destCity: "Atlanta",
        destState: "GA",
        pickupAt: Date().addingTimeInterval(3600 * 4),
        deliverBy: Date().addingTimeInterval(3600 * 30),
        ratePerMile: 2.85,
        totalRate: 3900,
        miles: 1368,
        status: "assigned",
        hazmat: false,
        temperatureF: nil,
        equipment: "dry_van",
        brokerName: "PaccoLogistics"
    )
}
