//
//  HereMatrixClient.swift
//  EusoTrip — authenticated backend client for HERE Matrix Routing API v8
//
//  Used by the dispatch board for many-to-many cost calculations:
//    "Given 10 available trucks and 15 pickup points, what's the cheapest
//    assignment?"
//
//  HERE supports both **sync** and **async** calls; sync caps at about
//  15×100 matrix cells, async supports up to a few thousand. EusoTrip uses
//  the sync path in-app (dispatch board fits 15×15 comfortably); large
//  fleet-wide optimizations should run server-side via the async API.
//
//  Provider credentials stay on the EusoTrip server. The app calls the typed
//  `hereMaps.matrix` procedure and retains the existing row-major interface.
//
//  Body:
//    {
//      "origins":      [{"lat":32.44,"lng":-93.70}, ...],
//      "destinations": [{"lat":29.76,"lng":-95.37}, ...],
//      "regionDefinition": { "type": "world" },
//      "transportMode": "truck",
//      "matrixAttributes": ["travelTimes","distances"],
//      "vehicle": { ... from TruckProfile ... }
//    }
//
//  Powered by ESANG AI™.
//

import Foundation
import CoreLocation

actor HereMatrixClient {

    static let shared = HereMatrixClient()

    init(session: URLSession = .shared) {
        _ = session
    }

    // MARK: - Main call

    /// Computes a travel-time + distance matrix between origins and destinations.
    ///
    /// - Parameters:
    ///   - origins:       anywhere from 1 to ~15 points (sync limit).
    ///   - destinations:  same; matrix has `origins.count × destinations.count` cells.
    ///   - profile:       truck vehicle profile.
    ///   - departureTime: ISO-8601 timestamp. nil → depart now.
    /// - Returns: Matrix with travelTimes (seconds) and distances (meters),
    ///   both flat row-major arrays.
    func matrix(
        origins: [CLLocationCoordinate2D],
        destinations: [CLLocationCoordinate2D],
        profile: TruckProfile,
        departureTime: String? = nil
    ) async throws -> HereMatrixResponse {
        guard !origins.isEmpty, !destinations.isEmpty else {
            throw HereMapsError.providerError("Matrix requires at least one origin and destination.")
        }
        let response: BackendResponse = try await EusoTripAPI.shared.query(
            "hereMaps.matrix",
            input: BackendRequest(
                origins: origins.map(Coord.init),
                destinations: destinations.map(Coord.init),
                transportMode: "truck",
                truck: VehicleParams(profile: profile),
                departureTime: departureTime
            )
        )
        guard response.ok else {
            throw HereMapsError.providerError("HERE returned no matrix.")
        }
        let distances = response.distances.flatMap { $0.map { Int($0.rounded()) } }
        let durations = response.durations.flatMap { $0.map { Int($0.rounded()) } }
        return HereMatrixResponse(
            matrix: HereMatrixResponse.Matrix(
                numOrigins: origins.count,
                numDestinations: destinations.count,
                travelTimes: durations,
                distances: distances
            ),
            regionDefinition: nil
        )
    }

    // MARK: - Request types

    private struct Coord: Encodable {
        let lat: Double
        let lng: Double
        init(_ c: CLLocationCoordinate2D) { lat = c.latitude; lng = c.longitude }
    }
    private struct BackendRequest: Encodable {
        let origins: [Coord]
        let destinations: [Coord]
        let transportMode: String
        let truck: VehicleParams
        let departureTime: String?
    }
    private struct BackendResponse: Decodable {
        let ok: Bool
        let distances: [[Double]]
        let durations: [[Double]]
    }
    /// Matrix API takes vehicle params as a nested JSON object (unlike Routing
    /// v8 which uses repeated `vehicle[field]=value` GET params).
    private struct VehicleParams: Encodable {
        let grossWeightKg: Int?
        let weightPerAxleKg: Int?
        let heightCm: Int?
        let widthCm: Int?
        let lengthCm: Int?
        let axleCount: Int?
        let trailerCount: Int?
        // 2026-06-03 — removed `type` + `emissionType`: invalid in Matrix v8
        // vehicle schema (type allows only straightTruck/tractor; there is no
        // emissionType field) → every POST 400'd → empty candidates strip.
        let tunnelCategory: String?
        let shippedHazardousGoods: [String]?

        init(profile: TruckProfile) {
            grossWeightKg         = profile.grossWeightKg
            weightPerAxleKg       = profile.weightPerAxleKg
            heightCm              = profile.heightCm
            widthCm               = profile.widthCm
            lengthCm              = profile.lengthCm
            axleCount             = profile.axleCount
            trailerCount          = profile.trailerCount
            tunnelCategory        = profile.tunnelCategory?.hereValue
            shippedHazardousGoods = profile.shippedHazardousGoods.isEmpty
                ? nil
                : profile.shippedHazardousGoods.map {
                    $0 == .radioactive ? "radioActive" : $0.hereValue
                }.sorted()
        }
    }

}
