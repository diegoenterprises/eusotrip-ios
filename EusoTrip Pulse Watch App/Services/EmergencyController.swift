//
//  EmergencyController.swift
//  EusoTrip Watch App
//
//  One coordinator for manual, crash, voice, and silent-duress SOS events.
//  A reachable iPhone is the primary relay. The Watch declares directly
//  only when the phone cannot be reached, then persists an SOS in the
//  priority outbox when the server does not return a receipt.
//

import Foundation
import Combine
import WatchKit
import CoreLocation

enum EmergencyServerEvidence: Equatable {
    case contacting
    case acknowledged(reference: String)
    case queued(reference: String)
    case notAcknowledged
}

enum EmergencyCallEvidence: Equatable {
    case opening
    case opened
    case notRequested
    case unavailable
}

enum EmergencyRelayRoute: Equatable {
    case iPhone
    case watch
}

@MainActor
final class EmergencyController: NSObject, ObservableObject {
    static let shared = EmergencyController()

    @Published private(set) var isActive = false
    @Published private(set) var eventId = ""
    @Published private(set) var reason = ""
    @Published private(set) var silent = false
    @Published private(set) var serverEvidence: EmergencyServerEvidence = .contacting
    @Published private(set) var callEvidence: EmergencyCallEvidence = .opening
    @Published private(set) var relayRoute: EmergencyRelayRoute = .iPhone
    @Published private(set) var locationCoordinate: CLLocationCoordinate2D?
    @Published private(set) var locationCapturedAt: Date?

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func activate(
        reason: String,
        auth: AuthStore,
        connectivity: WatchConnectivityManager,
        silent: Bool = false
    ) async {
        guard !isActive else { return }

        let eventId = UUID().uuidString
        let sample = currentLocationEvidence()
        let coordinate = sample?.coordinate

        self.eventId = eventId
        self.reason = reason
        self.silent = silent
        self.serverEvidence = .contacting
        self.callEvidence = silent ? .notRequested : .opening
        self.relayRoute = .iPhone
        self.locationCoordinate = coordinate
        self.locationCapturedAt = sample?.timestamp
        self.isActive = true

        WKInterfaceDevice.current().play(silent ? .notification : .failure)
        appendAuditEvidence(eventId: eventId, reason: reason, silent: silent, sample: sample)
        ConvoyCoordinator.shared.broadcastLocalSOS(reason: reason, coordinate: coordinate)

        let phoneResult = await connectivity.triggerEmergencySOS(
            eventId: eventId,
            reason: reason,
            silent: silent,
            coordinate: coordinate.map { ($0.latitude, $0.longitude) }
        )

        if phoneResult.phoneReached {
            relayRoute = .iPhone
            serverEvidence = phoneResult.serverAcknowledged
                ? .acknowledged(reference: phoneResult.emergencyId ?? eventId)
                : .notAcknowledged
            if silent {
                callEvidence = .notRequested
            } else {
                callEvidence = phoneResult.callHandoffOpened == true ? .opened : .unavailable
            }
            return
        }

        relayRoute = .watch
        callEvidence = silent ? .notRequested : .unavailable
        await declareFromWatch(
            eventId: eventId,
            reason: reason,
            silent: silent,
            coordinate: coordinate,
            auth: auth
        )
    }

    func dismiss() {
        isActive = false
        WKInterfaceDevice.current().play(.click)
    }

    private func declareFromWatch(
        eventId: String,
        reason: String,
        silent: Bool,
        coordinate: CLLocationCoordinate2D?,
        auth: AuthStore
    ) async {
        do {
            let data = try await EsangClient(auth: auth).mutateJSON(
                "emergencyProtocols.declareEmergency",
                input: Self.declareEmergencyInput(
                    eventId: eventId,
                    reason: reason,
                    silent: silent,
                    lat: coordinate?.latitude,
                    lon: coordinate?.longitude,
                    at: Date()
                )
            )
            let reference = try Self.emergencyReference(from: data)
            serverEvidence = .acknowledged(reference: reference)
        } catch {
            let queueReference = OfflineQueue.shared.enqueueSOS(
                reason: reason,
                silent: silent,
                lat: coordinate?.latitude,
                lon: coordinate?.longitude,
                idempotencyKey: eventId
            )
            serverEvidence = .queued(reference: queueReference)
        }
    }

    private func currentLocationEvidence() -> CLLocation? {
        guard let location = locationManager.location,
              location.horizontalAccuracy >= 0,
              Date().timeIntervalSince(location.timestamp) <= 10 * 60,
              location.coordinate.latitude.isFinite,
              location.coordinate.longitude.isFinite,
              (-90...90).contains(location.coordinate.latitude),
              (-180...180).contains(location.coordinate.longitude) else {
            return nil
        }
        return location
    }

    private func appendAuditEvidence(
        eventId: String,
        reason: String,
        silent: Bool,
        sample: CLLocation?
    ) {
        guard EusoTripConfig.blockchainAuditEnabled else { return }
        var payload = [
            "eventId": eventId,
            "reason": reason,
            "silent": silent ? "1" : "0",
            "source": "watch",
        ]
        if let sample {
            payload["lat"] = String(format: "%.6f", sample.coordinate.latitude)
            payload["lon"] = String(format: "%.6f", sample.coordinate.longitude)
            payload["locationCapturedAt"] = ISO8601DateFormatter.iso.string(from: sample.timestamp)
        }
        BlockchainAudit.shared.append(kind: .emergency, payload: payload)
    }

    nonisolated static func declareEmergencyInput(
        eventId: String? = nil,
        reason: String,
        silent: Bool = false,
        lat: Double?,
        lon: Double?,
        at: Date
    ) -> [String: Any] {
        let lower = reason.lowercased()
        let type: String = {
            if lower.contains("crash") || lower.contains("accident") { return "accident" }
            if lower.contains("medical") || lower.contains("injur") { return "medical" }
            if lower.contains("hazmat") || lower.contains("spill") { return "hazmat_spill" }
            if lower.contains("breakdown") || lower.contains("mechan") { return "breakdown" }
            if lower.contains("fire") { return "fire" }
            if lower.contains("weather") || lower.contains("storm") { return "weather" }
            if lower.contains("theft") || lower.contains("cargo") { return "cargo_theft" }
            return "security"
        }()
        let eventDescription = eventId.map { " Event \($0)." } ?? ""
        var input: [String: Any] = [
            "type": type,
            "severity": "critical",
            "title": "Wrist SOS - EusoTrip Pulse",
            "description": "Driver-initiated SOS escalated from EusoTrip Pulse.\(eventDescription) Reason: \(reason). Raised at \(ISO8601DateFormatter.iso.string(from: at)).\(silent ? " Silent duress mode." : "")",
        ]
        if let lat,
           let lon,
           lat.isFinite,
           lon.isFinite,
           (-90...90).contains(lat),
           (-180...180).contains(lon) {
            input["latitude"] = lat
            input["longitude"] = lon
            input["location"] = String(format: "%.5f, %.5f", lat, lon)
        }
        return input
    }

    nonisolated static func emergencyReference(from data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let dataNode = result["data"] as? [String: Any],
              let json = dataNode["json"] as? [String: Any],
              json["success"] as? Bool == true,
              let emergencyId = json["emergencyId"] as? String,
              !emergencyId.isEmpty else {
            throw NSError(
                domain: "EusoTrip.Pulse.Emergency",
                code: 502,
                userInfo: [NSLocalizedDescriptionKey: "Emergency server receipt was missing."]
            )
        }
        return emergencyId
    }
}
