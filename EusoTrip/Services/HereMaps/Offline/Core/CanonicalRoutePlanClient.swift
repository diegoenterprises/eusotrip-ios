//
//  CanonicalRoutePlanClient.swift
//  EusoTrip
//
//  Authenticated transport for server-canonical offline route packages.
//  The device sends only a typed freight subject. Tenant, user, route mode,
//  geometry, and signature scope remain server-authoritative.
//

import Foundation

enum CanonicalRoutePlanClientError: Error, Equatable, LocalizedError {
    case invalidSubjectIdentifier
    case authenticatedTenantUnavailable
    case invalidAuthenticatedPrincipal
    case malformedEnvelope
    case malformedSignedPayload
    case signedScopeMismatch
    case signedModeMismatch(expected: OfflineRouteMode, actual: OfflineRouteMode)
    case invalidReceiptTimestamp

    var errorDescription: String? {
        switch self {
        case .invalidSubjectIdentifier:
            return "The freight record identifier is invalid."
        case .authenticatedTenantUnavailable:
            return "A tenant-bound signed-in account is required to download this offline route."
        case .invalidAuthenticatedPrincipal:
            return "The signed-in account identity cannot be used for an offline route package."
        case .malformedEnvelope:
            return "The server returned an invalid signed-route envelope."
        case .malformedSignedPayload:
            return "The server returned an invalid canonical-route payload."
        case .signedScopeMismatch:
            return "The signed route does not belong to this account and freight record."
        case .signedModeMismatch:
            return "The signed route mode does not match the requested freight record."
        case .invalidReceiptTimestamp:
            return "The device could not record a valid route receipt time."
        }
    }
}

/// Exact subject union accepted by `route.getOfflinePackage`.
///
/// IDs are validated against JavaScript's safe-integer boundary because the
/// backend Zod contract accepts a positive `number().int().safe()` and rejects
/// tenant, user, mode, or geometry fields supplied by the client.
enum CanonicalRouteFreightSubject: Hashable, Codable, Sendable {
    case load(Int64)
    case railShipment(Int64)
    case vesselShipment(Int64)
    case vesselVoyage(Int64)

    private static let maximumJavaScriptSafeInteger: Int64 = 9_007_199_254_740_991

    var id: Int64 {
        switch self {
        case .load(let id), .railShipment(let id), .vesselShipment(let id), .vesselVoyage(let id):
            return id
        }
    }

    var wireType: String {
        switch self {
        case .load:
            return "load"
        case .railShipment:
            return "rail_shipment"
        case .vesselShipment:
            return "vessel_shipment"
        case .vesselVoyage:
            return "vessel_voyage"
        }
    }

    var typedScopeIdentifier: String {
        "\(wireType):\(id)"
    }

    var expectedRouteMode: OfflineRouteMode {
        switch self {
        case .load:
            return .truck
        case .railShipment:
            return .rail
        case .vesselShipment, .vesselVoyage:
            return .vessel
        }
    }

    func validate() throws {
        guard id > 0, id <= Self.maximumJavaScriptSafeInteger else {
            throw CanonicalRoutePlanClientError.invalidSubjectIdentifier
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, id
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(wireType, forKey: .type)
        try container.encode(id, forKey: .id)
    }

    init(from decoder: Decoder) throws {
        let dynamic = try decoder.container(keyedBy: CanonicalRouteDynamicCodingKey.self)
        guard Set(dynamic.allKeys.map(\.stringValue)) == Set(["type", "id"]) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "The freight subject shape is invalid.")
            )
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let id = try container.decode(Int64.self, forKey: .id)
        switch type {
        case "load":
            self = .load(id)
        case "rail_shipment":
            self = .railShipment(id)
        case "vessel_shipment":
            self = .vesselShipment(id)
        case "vessel_voyage":
            self = .vesselVoyage(id)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "The freight subject type is unsupported."
            )
        }
        do {
            try validate()
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "The freight subject identifier is invalid."
            )
        }
    }
}

/// Principal snapshot taken from the authenticated app session before the
/// request. A response signed for any other principal is rejected even when
/// its signature is otherwise valid.
struct CanonicalRouteAuthenticatedPrincipal: Hashable, Sendable {
    let tenantID: String
    let userID: String

    init(tenantID: String, userID: String) throws {
        guard Self.isExactIdentifier(tenantID), Self.isExactIdentifier(userID) else {
            throw CanonicalRoutePlanClientError.invalidAuthenticatedPrincipal
        }
        self.tenantID = tenantID
        self.userID = userID
    }

    init(authenticatedUser: AuthUser) throws {
        guard let tenantID = authenticatedUser.companyId else {
            throw CanonicalRoutePlanClientError.authenticatedTenantUnavailable
        }
        try self.init(tenantID: tenantID, userID: authenticatedUser.id)
    }

    func scope(for subject: CanonicalRouteFreightSubject) throws -> CanonicalRouteScope {
        try subject.validate()
        return try CanonicalRouteScope(
            tenantID: tenantID,
            userID: userID,
            loadID: subject.typedScopeIdentifier
        )
    }

    private static func isExactIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              value.utf8.count <= 128 else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x20 && scalar.value != 0x7f
        }
    }
}

struct CanonicalRouteOfflinePackageRequest: Encodable, Sendable {
    let subject: CanonicalRouteFreightSubject

    init(subject: CanonicalRouteFreightSubject) throws {
        try subject.validate()
        self.subject = subject
    }
}

/// String-backed wire model keeps the server's canonical Base64 text intact
/// until it has passed exact-length and round-trip validation.
struct CanonicalRouteOfflinePackageWireEnvelope: Codable, Equatable, Sendable {
    let keyID: String
    let algorithm: CanonicalRouteSignatureAlgorithm
    let payload: String
    let signature: String

    init(
        keyID: String,
        algorithm: CanonicalRouteSignatureAlgorithm,
        payload: String,
        signature: String
    ) {
        self.keyID = keyID
        self.algorithm = algorithm
        self.payload = payload
        self.signature = signature
    }

    private enum CodingKeys: String, CodingKey {
        case keyID, algorithm, payload, signature
    }

    init(from decoder: Decoder) throws {
        let dynamic = try decoder.container(keyedBy: CanonicalRouteDynamicCodingKey.self)
        guard Set(dynamic.allKeys.map(\.stringValue)) == Set(["keyID", "algorithm", "payload", "signature"]) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "The signed envelope shape is invalid.")
            )
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyID = try container.decode(String.self, forKey: .keyID)
        algorithm = try container.decode(CanonicalRouteSignatureAlgorithm.self, forKey: .algorithm)
        payload = try container.decode(String.self, forKey: .payload)
        signature = try container.decode(String.self, forKey: .signature)
    }
}

/// Ready-to-ingest values. The payload is structurally screened here, but
/// becomes authoritative only after `CanonicalRoutePackageStore` verifies its
/// Ed25519 signature against the release-pinned key.
struct CanonicalRoutePlanDelivery: Equatable, Sendable {
    let encodedEnvelope: Data
    let expectedScope: CanonicalRouteScope
    let receivedAt: Date
}

@MainActor
protocol CanonicalRouteOfflinePackageTransport {
    func getOfflinePackage(
        subject: CanonicalRouteFreightSubject
    ) async throws -> CanonicalRouteOfflinePackageWireEnvelope
}

/// Production transport. `EusoTripAPI.query` supplies the existing cookie /
/// Bearer session, cache bypass, bounded URLSession, and one-shot auth refresh.
@MainActor
struct EusoTripCanonicalRouteOfflinePackageTransport: CanonicalRouteOfflinePackageTransport {
    static let procedure = "route.getOfflinePackage"

    let api: EusoTripAPI

    init(api: EusoTripAPI = .shared) {
        self.api = api
    }

    func getOfflinePackage(
        subject: CanonicalRouteFreightSubject
    ) async throws -> CanonicalRouteOfflinePackageWireEnvelope {
        let request = try CanonicalRouteOfflinePackageRequest(subject: subject)
        return try await api.query(Self.procedure, input: request)
    }
}

@MainActor
final class CanonicalRoutePlanClient {
    private static let maximumSignedPayloadBytes = 8 * 1_024 * 1_024
    private static let maximumPayloadBase64Bytes =
        ((maximumSignedPayloadBytes + 2) / 3) * 4

    private let transport: any CanonicalRouteOfflinePackageTransport
    private let receiptClock: @MainActor () -> Date

    init(
        api: EusoTripAPI = .shared,
        receiptClock: @escaping @MainActor () -> Date = Date.init
    ) {
        transport = EusoTripCanonicalRouteOfflinePackageTransport(api: api)
        self.receiptClock = receiptClock
    }

    init(
        transport: any CanonicalRouteOfflinePackageTransport,
        receiptClock: @escaping @MainActor () -> Date = Date.init
    ) {
        self.transport = transport
        self.receiptClock = receiptClock
    }

    func download(
        subject: CanonicalRouteFreightSubject,
        authenticatedUser: AuthUser
    ) async throws -> CanonicalRoutePlanDelivery {
        let principal = try CanonicalRouteAuthenticatedPrincipal(
            authenticatedUser: authenticatedUser
        )
        return try await download(subject: subject, principal: principal)
    }

    func download(
        subject: CanonicalRouteFreightSubject,
        principal: CanonicalRouteAuthenticatedPrincipal
    ) async throws -> CanonicalRoutePlanDelivery {
        try subject.validate()
        let expectedScope = try principal.scope(for: subject)
        let wireEnvelope = try await transport.getOfflinePackage(subject: subject)
        let receivedAt = receiptClock()
        guard receivedAt.timeIntervalSince1970.isFinite else {
            throw CanonicalRoutePlanClientError.invalidReceiptTimestamp
        }

        let envelope = try Self.validatedEnvelope(wireEnvelope)
        try Self.validateSignedPayload(
            envelope.payload,
            expectedScope: expectedScope,
            expectedMode: subject.expectedRouteMode
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encodedEnvelope: Data
        do {
            encodedEnvelope = try encoder.encode(envelope)
            let roundTrip = try JSONDecoder().decode(
                CanonicalRouteSignedEnvelope.self,
                from: encodedEnvelope
            )
            guard roundTrip == envelope else {
                throw CanonicalRoutePlanClientError.malformedEnvelope
            }
        } catch let error as CanonicalRoutePlanClientError {
            throw error
        } catch {
            throw CanonicalRoutePlanClientError.malformedEnvelope
        }

        return CanonicalRoutePlanDelivery(
            encodedEnvelope: encodedEnvelope,
            expectedScope: expectedScope,
            receivedAt: receivedAt
        )
    }

    private static func validatedEnvelope(
        _ wire: CanonicalRouteOfflinePackageWireEnvelope
    ) throws -> CanonicalRouteSignedEnvelope {
        guard isSafeKeyID(wire.keyID),
              wire.payload.utf8.count <= maximumPayloadBase64Bytes,
              wire.signature.utf8.count == 88,
              let payload = exactBase64(wire.payload),
              !payload.isEmpty,
              payload.count <= maximumSignedPayloadBytes,
              let signature = exactBase64(wire.signature),
              signature.count == 64 else {
            throw CanonicalRoutePlanClientError.malformedEnvelope
        }
        do {
            return try CanonicalRouteSignedEnvelope(
                keyID: wire.keyID,
                algorithm: wire.algorithm,
                payload: payload,
                signature: signature
            )
        } catch {
            throw CanonicalRoutePlanClientError.malformedEnvelope
        }
    }

    private static func validateSignedPayload(
        _ data: Data,
        expectedScope: CanonicalRouteScope,
        expectedMode: OfflineRouteMode
    ) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rawClaims: CanonicalRouteRawBindingClaims
        let payload: CanonicalRouteSignedPayload
        do {
            rawClaims = try decoder.decode(CanonicalRouteRawBindingClaims.self, from: data)
            payload = try decoder.decode(CanonicalRouteSignedPayload.self, from: data)
        } catch {
            throw CanonicalRoutePlanClientError.malformedSignedPayload
        }

        guard rawClaims.scope.tenantID == expectedScope.tenantID,
              rawClaims.scope.userID == expectedScope.userID,
              rawClaims.scope.loadID == expectedScope.loadID,
              payload.scope == expectedScope else {
            throw CanonicalRoutePlanClientError.signedScopeMismatch
        }
        guard rawClaims.mode == expectedMode, payload.mode == expectedMode else {
            throw CanonicalRoutePlanClientError.signedModeMismatch(
                expected: expectedMode,
                actual: payload.mode
            )
        }
    }

    private static func exactBase64(_ encoded: String) -> Data? {
        guard let decoded = Data(base64Encoded: encoded),
              decoded.base64EncodedString() == encoded else {
            return nil
        }
        return decoded
    }

    private static func isSafeKeyID(_ value: String) -> Bool {
        guard !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              value.utf8.count <= 128 else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x30...0x39, 0x41...0x5a, 0x61...0x7a, 0x2e, 0x3a, 0x2d, 0x5f:
                return true
            default:
                return false
            }
        }
    }
}

private struct CanonicalRouteRawBindingClaims: Decodable {
    struct RawScope: Decodable {
        let tenantID: String
        let userID: String
        let loadID: String

        private enum CodingKeys: String, CodingKey {
            case tenantID, userID, loadID
        }

        init(from decoder: Decoder) throws {
            let dynamic = try decoder.container(keyedBy: CanonicalRouteDynamicCodingKey.self)
            guard Set(dynamic.allKeys.map(\.stringValue)) == Set(["tenantID", "userID", "loadID"]) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "The signed route scope shape is invalid.")
                )
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tenantID = try container.decode(String.self, forKey: .tenantID)
            userID = try container.decode(String.self, forKey: .userID)
            loadID = try container.decode(String.self, forKey: .loadID)
        }
    }

    let scope: RawScope
    let mode: OfflineRouteMode
}

private struct CanonicalRouteDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}
