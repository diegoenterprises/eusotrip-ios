import CryptoKit
import Foundation
import XCTest
@testable import EusoTrip

@MainActor
private final class CanonicalRouteOfflinePackageTransportStub: CanonicalRouteOfflinePackageTransport {
    var response: CanonicalRouteOfflinePackageWireEnvelope
    private(set) var requestedSubjects: [CanonicalRouteFreightSubject] = []

    init(response: CanonicalRouteOfflinePackageWireEnvelope) {
        self.response = response
    }

    func getOfflinePackage(
        subject: CanonicalRouteFreightSubject
    ) async throws -> CanonicalRouteOfflinePackageWireEnvelope {
        requestedSubjects.append(subject)
        return response
    }
}

@MainActor
final class CanonicalRoutePlanClientTests: XCTestCase {
    private let receiptTime = Date(timeIntervalSince1970: 1_788_220_923)

    func testRequestEmitsOnlyTheExactTypedFreightSubject() throws {
        let subjects: [(CanonicalRouteFreightSubject, String)] = [
            (.load(5), "{\"subject\":{\"id\":5,\"type\":\"load\"}}"),
            (.railShipment(41), "{\"subject\":{\"id\":41,\"type\":\"rail_shipment\"}}"),
            (.vesselShipment(19), "{\"subject\":{\"id\":19,\"type\":\"vessel_shipment\"}}"),
            (.vesselVoyage(23), "{\"subject\":{\"id\":23,\"type\":\"vessel_voyage\"}}")
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        for (subject, expectedJSON) in subjects {
            let request = try CanonicalRouteOfflinePackageRequest(subject: subject)
            let encoded = try encoder.encode(request)
            XCTAssertEqual(String(data: encoded, encoding: .utf8), expectedJSON)
        }
        XCTAssertEqual(
            EusoTripCanonicalRouteOfflinePackageTransport.procedure,
            "route.getOfflinePackage"
        )
    }

    func testSubjectRejectsNonPositiveAndUnsafeJavaScriptIdentifiers() {
        for subject in [
            CanonicalRouteFreightSubject.load(0),
            .railShipment(-1),
            .vesselShipment(9_007_199_254_740_992),
            .vesselVoyage(Int64.max)
        ] {
            XCTAssertThrowsError(
                try CanonicalRouteOfflinePackageRequest(subject: subject)
            ) { error in
                XCTAssertEqual(
                    error as? CanonicalRoutePlanClientError,
                    .invalidSubjectIdentifier
                )
            }
        }
    }

    func testBackendGoldenRailAndVesselEnvelopesReachThePinnedVerifierLosslessly() async throws {
        let fixture = try loadGoldenFixture()
        XCTAssertEqual(fixture.schemaVersion, 1)
        XCTAssertEqual(fixture.generatedBy.backendCommit, "9ed38a69")
        XCTAssertEqual(
            fixture.generatedBy.implementation,
            "frontend/server/services/routing/offlineRoutePackage.ts:createOfflineRoutePackageSigner"
        )
        let publicKey = try XCTUnwrap(Data(base64Encoded: fixture.publicKeyB64))
        let verifier = try CanonicalRoutePlanVerifier(
            expectedIssuer: "https://api.eusotrip.com/route",
            expectedAudience: "com.eusorone.eusotrip.ios",
            keys: [
                try CanonicalRouteVerificationKey(
                    keyID: "offline-route-2026-09-a",
                    ed25519RawRepresentation: publicKey
                )
            ]
        )
        let principal = try CanonicalRouteAuthenticatedPrincipal(
            tenantID: "71",
            userID: "7"
        )

        for goldenCase in fixture.cases {
            let transport = CanonicalRouteOfflinePackageTransportStub(
                response: goldenCase.envelope
            )
            let client = CanonicalRoutePlanClient(
                transport: transport,
                receiptClock: { self.receiptTime }
            )

            let delivery = try await client.download(
                subject: goldenCase.subject,
                principal: principal
            )

            XCTAssertEqual(transport.requestedSubjects, [goldenCase.subject])
            XCTAssertEqual(delivery.expectedScope, goldenCase.scope)
            XCTAssertEqual(delivery.receivedAt, receiptTime)

            let envelope = try JSONDecoder().decode(
                CanonicalRouteSignedEnvelope.self,
                from: delivery.encodedEnvelope
            )
            XCTAssertEqual(envelope.keyID, goldenCase.envelope.keyID)
            XCTAssertEqual(envelope.algorithm, goldenCase.envelope.algorithm)
            XCTAssertEqual(
                envelope.payload,
                try XCTUnwrap(Data(base64Encoded: goldenCase.envelope.payload))
            )
            XCTAssertEqual(
                envelope.signature,
                try XCTUnwrap(Data(base64Encoded: goldenCase.envelope.signature))
            )

            let package = try verifier.verify(
                envelope,
                expectedScope: delivery.expectedScope
            )
            XCTAssertEqual(package.scope, goldenCase.scope)
            XCTAssertEqual(package.mode, goldenCase.mode)
            XCTAssertEqual(package.provenance, .serverCanonical)
        }
    }

    func testSignedScopeSubstitutionIsRejectedBeforeStoreHandoff() async throws {
        let goldenCase = try loadGoldenFixture().cases[0]
        let substituted = try replacingPayload(in: goldenCase.envelope) { object in
            var scope = try XCTUnwrap(object["scope"] as? [String: Any])
            scope["userID"] = "8"
            object["scope"] = scope
        }
        let client = CanonicalRoutePlanClient(
            transport: CanonicalRouteOfflinePackageTransportStub(response: substituted),
            receiptClock: { self.receiptTime }
        )
        let principal = try CanonicalRouteAuthenticatedPrincipal(
            tenantID: "71",
            userID: "7"
        )

        do {
            _ = try await client.download(
                subject: goldenCase.subject,
                principal: principal
            )
            XCTFail("A signed scope for another user must not reach the route store.")
        } catch {
            XCTAssertEqual(
                error as? CanonicalRoutePlanClientError,
                .signedScopeMismatch
            )
        }
    }

    func testRailSubjectCannotAcceptAWellShapedVesselPayload() async throws {
        let goldenCase = try loadGoldenFixture().cases[0]
        let vesselMode = try replacingPayload(in: goldenCase.envelope) { object in
            object["mode"] = "vessel"
            var segments = try XCTUnwrap(object["segments"] as? [[String: Any]])
            for index in segments.indices {
                segments[index]["mode"] = "vessel"
            }
            object["segments"] = segments
        }
        let client = CanonicalRoutePlanClient(
            transport: CanonicalRouteOfflinePackageTransportStub(response: vesselMode),
            receiptClock: { self.receiptTime }
        )
        let principal = try CanonicalRouteAuthenticatedPrincipal(
            tenantID: "71",
            userID: "7"
        )

        do {
            _ = try await client.download(
                subject: goldenCase.subject,
                principal: principal
            )
            XCTFail("A vessel package must not be admitted for a rail shipment.")
        } catch {
            XCTAssertEqual(
                error as? CanonicalRoutePlanClientError,
                .signedModeMismatch(expected: .rail, actual: .vessel)
            )
        }
    }

    func testEnvelopeRequiresCanonicalBase64AndAnExactResponseShape() async throws {
        let goldenCase = try loadGoldenFixture().cases[0]
        let nonCanonical = CanonicalRouteOfflinePackageWireEnvelope(
            keyID: goldenCase.envelope.keyID,
            algorithm: goldenCase.envelope.algorithm,
            payload: goldenCase.envelope.payload + "=",
            signature: goldenCase.envelope.signature
        )
        let client = CanonicalRoutePlanClient(
            transport: CanonicalRouteOfflinePackageTransportStub(response: nonCanonical)
        )
        let principal = try CanonicalRouteAuthenticatedPrincipal(
            tenantID: "71",
            userID: "7"
        )

        do {
            _ = try await client.download(
                subject: goldenCase.subject,
                principal: principal
            )
            XCTFail("Non-canonical Base64 must not reach the route store.")
        } catch {
            XCTAssertEqual(
                error as? CanonicalRoutePlanClientError,
                .malformedEnvelope
            )
        }

        let encoded = try JSONEncoder().encode(goldenCase.envelope)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["tenantID"] = "client-must-not-supply-this"
        let expanded = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                CanonicalRouteOfflinePackageWireEnvelope.self,
                from: expanded
            )
        )
    }

    func testAuthenticatedPrincipalRequiresExactTenantAndUserIdentity() throws {
        for pair in [
            ("", "7"),
            (" 71", "7"),
            ("71", "7 "),
            ("71", "user\u{7f}")
        ] {
            XCTAssertThrowsError(
                try CanonicalRouteAuthenticatedPrincipal(
                    tenantID: pair.0,
                    userID: pair.1
                )
            ) { error in
                XCTAssertEqual(
                    error as? CanonicalRoutePlanClientError,
                    .invalidAuthenticatedPrincipal
                )
            }
        }

        let tenantless = AuthUser(
            id: "7",
            email: "signed-in@example.invalid",
            role: "RAIL_SHIPPER",
            name: nil,
            companyId: nil
        )
        XCTAssertThrowsError(
            try CanonicalRouteAuthenticatedPrincipal(
                authenticatedUser: tenantless
            )
        ) { error in
            XCTAssertEqual(
                error as? CanonicalRoutePlanClientError,
                .authenticatedTenantUnavailable
            )
        }
    }

    func testGoldenFixtureContainsOnlyPublicVerificationMaterial() throws {
        let url = goldenFixtureURL()
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("EUSOTRIP_OFFLINE_ROUTE_SIGNING_KEY_B64"))
        XCTAssertFalse(text.lowercased().contains("privatekey"))
        XCTAssertFalse(text.lowercased().contains("private_key"))
        XCTAssertTrue(text.contains("publicKeyB64"))
    }

    private func replacingPayload(
        in envelope: CanonicalRouteOfflinePackageWireEnvelope,
        mutation: (inout [String: Any]) throws -> Void
    ) throws -> CanonicalRouteOfflinePackageWireEnvelope {
        let payload = try XCTUnwrap(Data(base64Encoded: envelope.payload))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: payload) as? [String: Any]
        )
        try mutation(&object)
        let changed = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        return CanonicalRouteOfflinePackageWireEnvelope(
            keyID: envelope.keyID,
            algorithm: envelope.algorithm,
            payload: changed.base64EncodedString(),
            signature: envelope.signature
        )
    }

    private func loadGoldenFixture() throws -> GoldenFixture {
        try JSONDecoder().decode(
            GoldenFixture.self,
            from: Data(contentsOf: goldenFixtureURL())
        )
    }

    private func goldenFixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("CanonicalRoutePackageGolden.json")
    }
}

private struct GoldenFixture: Decodable {
    struct Generator: Decodable {
        let backendCommit: String
        let implementation: String
    }

    struct GoldenCase: Decodable {
        let name: String
        let subject: CanonicalRouteFreightSubject
        let scope: CanonicalRouteScope
        let mode: OfflineRouteMode
        let envelope: CanonicalRouteOfflinePackageWireEnvelope
    }

    let schemaVersion: Int
    let generatedBy: Generator
    let publicKeyB64: String
    let cases: [GoldenCase]
}
