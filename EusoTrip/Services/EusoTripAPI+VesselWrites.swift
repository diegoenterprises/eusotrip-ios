//
//  EusoTripAPI+VesselWrites.swift
//  EusoTrip
//
//  Native bindings for the five persisted vessel/intermodal write paths.
//  Request field names and enum raw values mirror server/routers/vesselWrites.ts.
//

import Foundation

extension EusoTripAPI {
    struct VesselWriteAcknowledgement: Decodable, Equatable {
        let id: Int
        let idempotent: Bool
    }

    struct VesselBunkerWriteAcknowledgement: Decodable, Equatable {
        let id: Int
        let idempotent: Bool
        let totalCost: String
    }

    enum VesselFreightContainerSize: String, CaseIterable, Codable, Identifiable {
        case twentyFoot = "20ft"
        case fortyFoot = "40ft"
        case fortyFootHighCube = "40ft_hc"
        case fortyFiveFoot = "45ft"
        case twentyFootReefer = "20ft_reefer"
        case fortyFootReefer = "40ft_reefer"

        var id: String { rawValue }
    }

    enum VesselInventoryContainerSize: String, CaseIterable, Codable, Identifiable {
        case twentyFoot = "20ft"
        case fortyFoot = "40ft"
        case fortyFiveFoot = "45ft"
        case fiftyThreeFoot = "53ft"

        var id: String { rawValue }
    }

    enum VesselInventoryContainerType: String, CaseIterable, Codable, Identifiable {
        case standard
        case highCube = "high_cube"
        case reefer
        case openTop = "open_top"
        case flatRack = "flat_rack"
        case tank

        var id: String { rawValue }
    }

    enum VesselInventoryStatus: String, CaseIterable, Codable, Identifiable {
        case onChassis = "on_chassis"
        case grounded
        case loaded
        case empty
        case inTransit = "in_transit"
        case atPort = "at_port"

        var id: String { rawValue }
    }

    enum VesselFuelType: String, CaseIterable, Codable, Identifiable {
        case hfo
        case vlsfo
        case mgo
        case lng

        var id: String { rawValue }
    }

    struct PublishVesselFreightRateInput: Encodable {
        var requestKey: String
        let originPortId: Int
        let destinationPortId: Int
        let containerSize: VesselFreightContainerSize
        let ratePerUnit: String
        let currency: String
        let bafSurcharge: String?
        let thcOrigin: String?
        let thcDestination: String?
        let peakSeasonSurcharge: String?
        let effectiveDate: String
        let expirationDate: String?
        let transitDays: Int
        let serviceRoute: String?
    }

    struct CreateVesselVoyageInput: Encodable {
        var requestKey: String
        let vesselId: Int
        let voyageNumber: String
        let serviceRoute: String?
        let departurePortId: Int
        let arrivalPortId: Int
        let scheduledDeparture: String
        let scheduledArrival: String
        let captainId: Int?
    }

    struct CreateVesselCargoManifestInput: Encodable {
        var requestKey: String
        let voyageId: Int
        let shipmentId: Int
        let containerNumber: String?
        let sealNumber: String?
        let cargoDescription: String
        let packageCount: Int?
        let grossWeightKg: String
        let volumeCBM: String?
        let loadPortId: Int
        let dischargePortId: Int
        let hazmatClass: String?
        let temperatureRequired: String?
        let stowagePosition: String?
    }

    struct RecordVesselBunkerDeliveryInput: Encodable {
        var requestKey: String
        let vesselId: Int
        let voyageId: Int?
        let portId: Int
        let fuelType: VesselFuelType
        let quantityMT: String
        let pricePerMT: String
        let currency: String
        let supplier: String
        let deliveryDate: String
        let bunkerDeliveryNote: String
        let sulphurContent: String?
    }

    struct RegisterIntermodalContainerInput: Encodable {
        var requestKey: String
        let containerNumber: String
        let size: VesselInventoryContainerSize
        let type: VesselInventoryContainerType
        let status: VesselInventoryStatus
        let chassisId: Int?
        let locationId: String?
        let spotId: String?
        let steamshipLine: String?
        let bookingNumber: String?
        let sealNumber: String?
        let weight: Int?
        let lastFreeDay: String?
        let demurrageRate: String?
        let arrivalTime: String?
        let departureTime: String?
        let notes: String?
    }

    struct VesselWritePort: Decodable, Identifiable, Hashable {
        let id: Int
        let name: String?
        let unlocode: String?
        let city: String?
        let state: String?
        let country: String?

        var displayLabel: String {
            let identity = [name, unlocode]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            let place = [city, state, country]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            if !identity.isEmpty && !place.isEmpty { return "\(identity) — \(place)" }
            if !identity.isEmpty { return identity }
            if !place.isEmpty { return place }
            return "Port ID \(id)"
        }
    }

    struct VesselWriteFleetRow: Decodable, Identifiable, Hashable {
        let id: Int
        let name: String?
        let imoNumber: String?
        let callSign: String?
        let vesselType: String?
        let status: String?

        var displayLabel: String {
            let vesselName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let imo = imoNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !vesselName.isEmpty && !imo.isEmpty { return "\(vesselName) · IMO \(imo)" }
            if !vesselName.isEmpty { return vesselName }
            if !imo.isEmpty { return "IMO \(imo)" }
            return "Vessel ID \(id)"
        }
    }

    struct VesselWriteFleetEnvelope: Decodable {
        let vessels: [VesselWriteFleetRow]
        let total: Int
    }

    struct VesselWriteVoyageRow: Decodable, Identifiable, Hashable {
        let id: Int
        let vesselId: Int
        let voyageNumber: String?
        let vesselName: String?
        let departurePortName: String?
        let departurePortCode: String?
        let arrivalPortName: String?
        let arrivalPortCode: String?

        var displayLabel: String {
            let number = voyageNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let vessel = vesselName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let route = [departurePortCode, arrivalPortCode]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " → ")
            let parts = [number, vessel, route].filter { !$0.isEmpty }
            return parts.isEmpty ? "Voyage ID \(id)" : parts.joined(separator: " · ")
        }
    }

    struct VesselWriteShipmentRow: Decodable, Identifiable, Hashable {
        let id: Int
        let vesselId: Int?
        let bookingNumber: String?
        let commodity: String?
        let origin: String?
        let destination: String?

        var displayLabel: String {
            let booking = bookingNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cargo = commodity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let route = [origin, destination]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " → ")
            let parts = [booking, cargo, route].filter { !$0.isEmpty }
            return parts.isEmpty ? "Shipment ID \(id)" : parts.joined(separator: " · ")
        }
    }

    struct VesselWriteShipmentEnvelope: Decodable {
        let shipments: [VesselWriteShipmentRow]
        let total: Int
    }

    struct VesselContainerInventorySummary: Decodable, Equatable {
        let total: Int
        let loaded: Int
        let empty: Int
        let damaged: Int
    }

    private struct VesselPortsInput: Encodable {
        let limit: Int
        let offset: Int
        let activeOnly: Bool
    }

    private struct VesselFleetInput: Encodable {
        let limit: Int
        let offset: Int
    }

    private struct VesselSchedulesInput: Encodable {
        let limit: Int
    }

    private struct VesselShipmentsInput: Encodable {
        let limit: Int
        let offset: Int
    }

    func getVesselWritePorts() async throws -> [VesselWritePort] {
        try await query(
            "vesselShipments.getPorts",
            input: VesselPortsInput(limit: 1_000, offset: 0, activeOnly: true)
        )
    }

    func getVesselWriteFleet() async throws -> VesselWriteFleetEnvelope {
        try await query(
            "vesselShipments.getVesselFleet",
            input: VesselFleetInput(limit: 100, offset: 0)
        )
    }

    func getVesselWriteVoyages() async throws -> [VesselWriteVoyageRow] {
        try await query(
            "vesselShipments.getVesselSchedules",
            input: VesselSchedulesInput(limit: 200)
        )
    }

    func getVesselWriteShipments() async throws -> VesselWriteShipmentEnvelope {
        try await query(
            "vesselShipments.getVesselShipments",
            input: VesselShipmentsInput(limit: 200, offset: 0)
        )
    }

    func getVesselContainerInventorySummary() async throws -> VesselContainerInventorySummary {
        try await queryNoInput("vesselShipments.getContainerInventory")
    }

    func publishVesselFreightRate(
        _ input: PublishVesselFreightRateInput
    ) async throws -> VesselWriteAcknowledgement {
        let acknowledgement: VesselWriteAcknowledgement = try await mutation(
            "vesselShipments.publishFreightRate",
            input: input
        )
        return try verifiedVesselWriteAcknowledgement(acknowledgement)
    }

    func createVesselVoyage(
        _ input: CreateVesselVoyageInput
    ) async throws -> VesselWriteAcknowledgement {
        let acknowledgement: VesselWriteAcknowledgement = try await mutation(
            "vesselShipments.createVoyage",
            input: input
        )
        return try verifiedVesselWriteAcknowledgement(acknowledgement)
    }

    func createVesselCargoManifest(
        _ input: CreateVesselCargoManifestInput
    ) async throws -> VesselWriteAcknowledgement {
        let acknowledgement: VesselWriteAcknowledgement = try await mutation(
            "vesselShipments.createCargoManifest",
            input: input
        )
        return try verifiedVesselWriteAcknowledgement(acknowledgement)
    }

    func recordVesselBunkerDelivery(
        _ input: RecordVesselBunkerDeliveryInput
    ) async throws -> VesselBunkerWriteAcknowledgement {
        let acknowledgement: VesselBunkerWriteAcknowledgement = try await mutation(
            "vesselShipments.recordBunkerDelivery",
            input: input
        )
        guard acknowledgement.id > 0, !acknowledgement.totalCost.isEmpty else {
            throw VesselWriteContractError.invalidAcknowledgement
        }
        return acknowledgement
    }

    func registerIntermodalContainer(
        _ input: RegisterIntermodalContainerInput
    ) async throws -> VesselWriteAcknowledgement {
        let acknowledgement: VesselWriteAcknowledgement = try await mutation(
            "vesselShipments.registerContainer",
            input: input
        )
        return try verifiedVesselWriteAcknowledgement(acknowledgement)
    }

    private func verifiedVesselWriteAcknowledgement(
        _ acknowledgement: VesselWriteAcknowledgement
    ) throws -> VesselWriteAcknowledgement {
        guard acknowledgement.id > 0 else {
            throw VesselWriteContractError.invalidAcknowledgement
        }
        return acknowledgement
    }
}

enum VesselWriteContractError: LocalizedError {
    case invalidAcknowledgement

    var errorDescription: String? {
        switch self {
        case .invalidAcknowledgement:
            return "The vessel operation was not confirmed with a saved record."
        }
    }
}
