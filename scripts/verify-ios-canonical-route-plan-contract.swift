import Foundation

// Standalone transport doubles let this script compile and exercise the real
// CanonicalRoutePlanClient.swift without pulling the complete iOS target into
// a command-line executable.
struct HereLatLng: Equatable, Sendable {
    let lat: Double
    let lng: Double
    var weight: Double?

    init(_ lat: Double, _ lng: Double, weight: Double? = nil) {
        self.lat = lat
        self.lng = lng
        self.weight = weight
    }
}

@MainActor
final class EusoTripAPI {
    static let shared = EusoTripAPI()

    var responseData = Data()
    var lastPath: String?
    var lastInputData: Data?
    var lastVerb: String?

    func query<Output: Decodable, Input: Encodable>(
        _ path: String,
        input: Input
    ) async throws -> Output {
        try recordAndDecode(path: path, input: input, verb: "query")
    }

    func mutation<Output: Decodable, Input: Encodable>(
        _ path: String,
        input: Input
    ) async throws -> Output {
        try recordAndDecode(path: path, input: input, verb: "mutation")
    }

    private func recordAndDecode<Output: Decodable, Input: Encodable>(
        path: String,
        input: Input,
        verb: String
    ) throws -> Output {
        lastPath = path
        lastInputData = try JSONEncoder().encode(input)
        lastVerb = verb
        return try JSONDecoder().decode(Output.self, from: responseData)
    }
}

private enum VerificationFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw VerificationFailure.failed(message) }
}

private func sha(_ byte: Character) -> String {
    String(repeating: String(byte), count: 64)
}

private func uuid(_ suffix: Int) -> String {
    "00000000-0000-4000-8000-" + String(format: "%012d", suffix)
}

private func jsonData(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func sourceProof(
    id: Int,
    role: String,
    sourceRole: String,
    checksumByte: Character,
    snapshotByte: Character
) -> [String: Any] {
    [
        "sourceSnapshotId": String(id),
        "sourcePublicId": uuid(id),
        "role": role,
        "sourceRole": sourceRole,
        "authority": "Licensed rail infrastructure authority",
        "provider": "EusoRail source adapter",
        "dataset": "Authorized rail network",
        "recordId": "network-2026-08-25",
        "sourceVersion": "2026.08.25",
        "adapterVersion": "1.0.0",
        "retrievedAt": "2026-08-24T00:00:00.000Z",
        "effectiveAt": "2026-08-24T00:00:00.000Z",
        "expiresAt": "2026-09-24T00:00:00.000Z",
        "rightsState": "valid",
        "freshnessState": "current",
        "qualityState": "verified",
        "revocationState": "active",
        "permitsOperationalUse": true,
        "checksum": sha(checksumByte),
        "snapshotHash": sha(snapshotByte),
        "attribution": "Licensed operational rail network",
    ]
}

private func geometry() -> [String: Any] {
    [
        "type": "MultiLineString",
        "coordinates": [
            [[-122.50, 37.70], [-122.40, 37.80]],
            [[-122.30, 37.90], [-122.20, 38.00]],
        ],
    ]
}

private func boundRoute() -> [String: Any] {
    let sources = [
        sourceProof(
            id: 601,
            role: "route_engine",
            sourceRole: "foundation_graph",
            checksumByte: "4",
            snapshotByte: "9"
        ),
        sourceProof(
            id: 602,
            role: "graph",
            sourceRole: "foundation_graph",
            checksumByte: "5",
            snapshotByte: "a"
        ),
        sourceProof(
            id: 603,
            role: "constraint",
            sourceRole: "operational_constraint",
            checksumByte: "6",
            snapshotByte: "b"
        ),
        sourceProof(
            id: 604,
            role: "regulatory",
            sourceRole: "regulatory",
            checksumByte: "7",
            snapshotByte: "c"
        ),
        sourceProof(
            id: 605,
            role: "validation",
            sourceRole: "operational_constraint",
            checksumByte: "8",
            snapshotByte: "d"
        ),
    ]
    return [
        "plan": [
            "identity": [
                "routePlanId": "101",
                "routePlanPublicId": uuid(101),
                "routePlanVersionId": "102",
                "version": 1,
                "mode": "RAIL",
                "planChecksum": sha("a"),
                "geometryChecksum": sha("b"),
            ],
            "purpose": "active_job",
            "state": "ready",
            "operational": true,
            "operationalReason": NSNull(),
            "rightsState": "valid",
            "freshnessState": "current",
            "modeGrammarVersion": "eusorone.rail.v1",
            "engine": [
                "adapter": "eusorail-route-engine",
                "version": "1.0.0",
                "graphVersionId": "501",
            ],
            "waypoints": [
                [
                    "sequence": 0,
                    "kind": "rail_yard",
                    "coordinate": ["lat": 37.70, "lng": -122.50],
                    "label": "Origin Yard",
                    "sourceEntityType": "rail_yard",
                    "sourceEntityId": "701",
                    "identityHash": sha("c"),
                ],
                [
                    "sequence": 1,
                    "kind": "destination",
                    "coordinate": ["lat": 38.00, "lng": -122.20],
                    "label": "Destination Yard",
                    "sourceEntityType": "rail_yard",
                    "sourceEntityId": "702",
                    "identityHash": sha("d"),
                ],
            ],
            "geometry": geometry(),
            "distanceMeters": 100,
            "durationSeconds": 60,
            "sources": sources,
            "segments": [[
                "sequence": 0,
                "stableEdgeId": "rail-edge-1",
                "geometry": geometry(),
                "geometryChecksum": sha("e"),
                "distanceMeters": 100,
                "durationSeconds": 60,
                "cumulativeStartMeters": 0,
                "cumulativeEndMeters": 100,
                "sourceSnapshotId": "602",
                "logisticsEdgeId": NSNull(),
                "fromNodeId": 1,
                "toNodeId": 2,
                "operatorRef": "EUSORAIL",
                "semantics": ["corridor": "Pacific"],
                "constraints": ["clearance": "verified"],
            ]],
            "instructions": [[
                "sequence": 0,
                "segmentSequence": 0,
                "instructionType": "rail.depart_yard",
                "title": "Depart Origin Yard",
                "visualText": "Proceed onto the Pacific corridor.",
                "spokenText": "Proceed onto the Pacific corridor.",
                "accessibilityText": "Depart Origin Yard on the authorized Pacific rail corridor.",
                "triggerCoordinate": ["lat": 37.70, "lng": -122.50],
                "triggerDistanceMeters": 0,
                "courseDegrees": 45.0,
                "semantics": ["railAction": "depart_yard"],
            ]],
            "constraints": [
                [
                    "sequence": 0,
                    "segmentSequence": 0,
                    "constraintType": "rail.profile.clearance",
                    "outcome": "cleared",
                    "requiredValue": "A",
                    "observedValue": "A",
                    "unit": "plate",
                    "legalReference": "Authorized equipment profile",
                    "sourceSnapshotId": "603",
                    "evidence": ["verified": true],
                ],
                [
                    "sequence": 1,
                    "segmentSequence": 0,
                    "constraintType": "rail.network.clearance",
                    "outcome": "cleared",
                    "requiredValue": "A",
                    "observedValue": "A",
                    "unit": "plate",
                    "legalReference": "Authorized clearance record",
                    "sourceSnapshotId": "603",
                    "evidence": ["verified": true],
                ],
                [
                    "sequence": 2,
                    "segmentSequence": 0,
                    "constraintType": "rail.regulatory.authority",
                    "outcome": "applied",
                    "requiredValue": "authorized",
                    "observedValue": "authorized",
                    "unit": NSNull(),
                    "legalReference": "Licensed operating authority",
                    "sourceSnapshotId": "604",
                    "evidence": ["verified": true],
                ],
                [
                    "sequence": 3,
                    "segmentSequence": 0,
                    "constraintType": "rail.operational.warrant",
                    "outcome": "cleared",
                    "requiredValue": "active",
                    "observedValue": "active",
                    "unit": NSNull(),
                    "legalReference": "Authorized operating warrant",
                    "sourceSnapshotId": "605",
                    "evidence": ["verified": true],
                ],
            ],
            "warnings": [],
            "createdAt": "2026-08-25T00:00:00.000Z",
            "validFrom": "2026-08-25T00:00:00.000Z",
            "validUntil": "2026-08-26T00:00:00.000Z",
        ],
        "request": [
            "requestId": "201",
            "routePlanId": "101",
            "requestKey": "route-request-1",
            "requestFingerprint": sha("f"),
            "waypointManifestHashSha256": sha("1"),
            "modeProfilePurpose": "assigned_asset",
            "modeSubjectProfileRegistrationId": "301",
            "modeAssetProfileVersionId": "302",
            "modeProfileBindingHashSha256": sha("2"),
            "requestVersion": 1,
            "supersedesRequestId": NSNull(),
            "state": "succeeded",
            "auditOutboxId": "401",
        ],
        "attempt": [
            "attemptId": "202",
            "requestId": "201",
            "attemptNumber": 1,
            "status": "succeeded",
            "solverInputHashSha256": sha("3"),
            "solverOutputHashSha256": sha("4"),
            "graphVersionId": "501",
            "modeProfileBindingHashSha256": sha("2"),
            "graphBindingHashSha256": sha("5"),
        ],
        "binding": [
            "bindingId": "801",
            "bindingPublicId": uuid(801),
            "bindingVersionId": "802",
            "bindingRevision": 1,
            "bindingHash": sha("6"),
            "activePlanChecksum": sha("a"),
            "state": "active",
        ],
        "sourceBindings": sources.map { source in
            [
                "proof": source,
                "requiredForOperationalUse": true,
            ] as [String: Any]
        },
    ]
}

private func persistedMutation() -> [String: Any] {
    [
        "persisted": true,
        "state": "ready",
        "operational": true,
        "route": boundRoute(),
    ]
}

private func pendingMutation() -> [String: Any] {
    [
        "persisted": false,
        "state": "route_pending",
        "operational": false,
        "route": NSNull(),
        "reasonCode": "PROFILE_AUTHORITY_REQUIRED",
        "blockers": [[
            "code": "PROFILE_REQUIRED",
            "path": "profile.authority",
            "message": "A current assigned asset profile is required.",
            "evidenceKind": NSNull(),
        ]],
    ]
}

private func executionAssignment() -> [String: Any] {
    [
        "mode": "RAIL",
        "assignment": [
            "id": "901",
            "publicId": uuid(901),
            "replayed": false,
        ],
    ]
}

private func executionState() -> [String: Any] {
    [
        "mode": "RAIL",
        "evidenceState": "current",
        "assignment": [
            "publicId": uuid(901),
            "routePlanVersionId": "102",
            "assetType": "train",
            "assetRecordId": "44",
            "operatorUserId": 17,
            "effectiveAt": "2026-08-25T00:00:00.000Z",
            "expiresAt": "2099-08-25T00:00:00.000Z",
            "totalDistanceMeters": "100",
            "totalDurationSeconds": "60",
        ],
        "observation": [
            "publicId": uuid(902),
            "sequence": 1,
            "coordinate": ["lat": 37.8, "lng": -122.4],
            "observedAt": "2026-08-25T00:01:00.000Z",
            "receivedAt": "2026-08-25T00:01:01.000Z",
            "validUntil": "2099-08-25T00:02:00.000Z",
            "freshnessState": "current",
            "qualityState": "verified",
            "operationalUseAllowed": true,
            "accuracyMeters": 4.0,
            "speedMetersPerSecond": 8.0,
            "courseDegrees": 45.0,
            "sourceType": "rail_provider",
            "provider": "Authorized rail provider",
            "dataset": "Exact consist observations",
            "attribution": "Licensed operational evidence",
        ],
        "projection": [
            "publicId": uuid(903),
            "status": "on_route",
            "projectedCoordinate": ["lat": 37.8, "lng": -122.4],
            "distanceAlongMeters": "40",
            "remainingMeters": "60",
            "remainingSeconds": "36",
            "progressBasisPoints": 4_000,
            "eta": "2099-08-25T00:01:36.000Z",
            "confidence": 0.98,
            "currentForGuidance": true,
        ],
        "nextInstruction": [
            "id": "1",
            "sequence": 0,
            "instructionType": "rail.depart_yard",
            "title": "Depart Origin Yard",
            "visualText": "Proceed on the authorized rail corridor.",
            "spokenText": "Proceed on the authorized rail corridor.",
            "accessibilityText": "Proceed on the authorized rail corridor.",
            "triggerCoordinate": ["lat": 37.8, "lng": -122.4],
            "triggerDistanceMeters": "0",
            "courseDegrees": 45.0,
            "semantics": ["railAction": "depart_yard"],
        ],
    ]
}

@MainActor
private func assertPlanWire(
    api: EusoTripAPI,
    expectedType: String,
    expectedID: Int,
    expectedPurpose: String
) throws {
    try require(api.lastVerb == "mutation", "route.plan must remain a mutation")
    try require(api.lastPath == "route.plan", "unexpected route planning path")
    guard let data = api.lastInputData,
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let subject = object["subject"] as? [String: Any] else {
        throw VerificationFailure.failed("route.plan input was not canonical JSON")
    }
    try require(Set(object.keys) == Set(["subject", "purpose"]),
                "route.plan input admitted client authority beyond subject + purpose")
    try require(Set(subject.keys) == Set(["type", "id"]),
                "route.plan subject admitted extra client authority")
    try require(subject["type"] as? String == expectedType, "subject type drifted")
    try require(subject["id"] as? Int == expectedID, "subject id drifted")
    try require(object["purpose"] as? String == expectedPurpose, "purpose drifted")
}

@main
struct CanonicalRoutePlanContractVerification {
    @MainActor
    static func main() async throws {
        let api = EusoTripAPI.shared
        let client = CanonicalRoutePlanClient(api: api)

        api.responseData = try jsonData(persistedMutation())
        let result = try await client.planLoad(id: 41, purpose: .activeJob)
        try assertPlanWire(
            api: api,
            expectedType: "load",
            expectedID: 41,
            expectedPurpose: "active_job"
        )
        guard case .persisted(let persisted) = result,
              let payload = persisted.route.rendererPayload else {
            throw VerificationFailure.failed("operational persisted route did not release renderer geometry")
        }
        try require(payload.lines.count == 2, "MultiLineString discontinuity was flattened")
        try require(payload.lines.map(\.count) == [2, 2], "renderer line membership drifted")
        try require(payload.segments.count == 1, "segment identity was lost")
        try require(payload.segments[0].lines.count == 2, "segment MultiLineString was flattened")
        try require(payload.identity.routePlanPublicId.rawValue == uuid(101),
                    "public route identity was not preserved")
        try require(payload.identity.routePlanVersionId.rawValue == "102" &&
                        payload.identity.version == 1,
                    "immutable route version was not preserved")
        try require(payload.identity.planChecksum.rawValue == sha("a") &&
                        payload.identity.geometryChecksum?.rawValue == sha("b"),
                    "plan/geometry checksum identity was not preserved")
        try require(payload.binding.activePlanChecksum == payload.identity.planChecksum,
                    "renderer payload lost its exact active checksum binding")
        try require(persisted.route.plan.freshnessState == .current,
                    "source freshness truth was not preserved")
        try require(
            persisted.route.plan.instructions[0].accessibilityText ==
                "Depart Origin Yard on the authorized Pacific rail corridor.",
            "accessibility guidance was not decoded exactly"
        )

        api.responseData = try jsonData(pendingMutation())
        _ = try await client.planLoad(id: 42, purpose: .posting)
        try assertPlanWire(api: api, expectedType: "load", expectedID: 42, expectedPurpose: "posting")
        _ = try await client.planRailShipment(id: 43, purpose: .planning)
        try assertPlanWire(api: api, expectedType: "rail_shipment", expectedID: 43, expectedPurpose: "planning")
        _ = try await client.planVesselShipment(id: 44, purpose: .activeJob)
        try assertPlanWire(api: api, expectedType: "vessel_shipment", expectedID: 44, expectedPurpose: "active_job")
        let pending = try await client.planVesselVoyage(id: 45, purpose: .reroute)
        try assertPlanWire(api: api, expectedType: "vessel_voyage", expectedID: 45, expectedPurpose: "reroute")
        guard case .pending(let pendingTruth) = pending else {
            throw VerificationFailure.failed("truthful unpersisted pending union was not preserved")
        }
        try require(pendingTruth.blockers.count == 1, "pending blockers were discarded")

        api.responseData = try jsonData(boundRoute())
        _ = try await client.getBoundVesselVoyage(id: 45)
        try require(api.lastVerb == "query" && api.lastPath == "route.getBound",
                    "exact bound read must remain route.getBound query")
        if let data = api.lastInputData,
           let input = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            try require(Set(input.keys) == Set(["by", "subject"]),
                        "subject read admitted tenant/mode/geometry authority")
        } else {
            throw VerificationFailure.failed("subject bound-read input was not JSON")
        }

        let bindingID = UUID(uuidString: uuid(801))!
        _ = try await client.getBound(bindingPublicID: bindingID)
        if let data = api.lastInputData,
           let input = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            try require(Set(input.keys) == Set(["by", "bindingPublicId"]),
                        "binding read admitted non-identity authority")
            try require(input["bindingPublicId"] as? String == uuid(801),
                        "binding UUID was not sent canonically")
        } else {
            throw VerificationFailure.failed("binding bound-read input was not JSON")
        }

        api.responseData = try jsonData(executionAssignment())
        let execution = try await client.assignExecution(subject: .railShipment(43))
        try require(api.lastVerb == "mutation" && api.lastPath == "route.assignExecution",
                    "execution assignment must use the intent-only mutation")
        try require(execution.mode == .rail && execution.assignment.publicId.rawValue == uuid(901),
                    "exact execution assignment identity was not decoded")
        if let data = api.lastInputData,
           let input = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let subject = input["subject"] as? [String: Any] {
            try require(Set(input.keys) == Set(["subject", "requestId"]),
                        "assignment admitted client asset/operator authority")
            try require(Set(subject.keys) == Set(["type", "id"]),
                        "assignment subject admitted extra client authority")
        } else {
            throw VerificationFailure.failed("execution assignment input was not JSON")
        }

        api.responseData = try jsonData([
            "synchronized": false,
            "reason": "NO_NEW_AUTHORIZED_OBSERVATION",
        ])
        _ = try await client.synchronizeExecution(
            assignmentPublicID: execution.assignment.publicId
        )
        try require(api.lastVerb == "mutation" && api.lastPath == "route.synchronizeExecution",
                    "execution synchronization must use the server observation mutation")
        if let data = api.lastInputData,
           let input = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            try require(Set(input.keys) == Set(["assignmentPublicId", "requestId"]),
                        "synchronization admitted coordinate/progress/provider authority")
        } else {
            throw VerificationFailure.failed("execution synchronization input was not JSON")
        }

        api.responseData = try jsonData(executionState())
        let liveState = try await client.getExecutionState(
            assignmentPublicID: execution.assignment.publicId
        )
        try require(api.lastVerb == "query" && api.lastPath == "route.getExecutionState",
                    "execution state must be a read-only exact-assignment query")
        if let data = api.lastInputData,
           let input = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            try require(Set(input.keys) == Set(["assignmentPublicId"]),
                        "execution-state read admitted client navigation claims")
        } else {
            throw VerificationFailure.failed("execution-state input was not JSON")
        }
        try require(liveState.guidanceSnapshot?.nextInstruction?.title == "Depart Origin Yard",
                    "current server-projected guidance did not release natively")

        var staleExecution = executionState()
        staleExecution["evidenceState"] = "stale"
        let staleState = try JSONDecoder().decode(
            CanonicalRoutePlanClient.ExecutionState.self,
            from: jsonData(staleExecution)
        )
        try require(staleState.guidanceSnapshot == nil,
                    "stale execution evidence reached native guidance")

        do {
            _ = try await client.planLoad(id: 0, purpose: .planning)
            throw VerificationFailure.failed("invalid public subject id reached transport")
        } catch CanonicalRoutePlanClient.ClientError.invalidSubjectID {
            // Expected fail-closed result.
        }

        var malformedUnion = persistedMutation()
        malformedUnion["route"] = NSNull()
        do {
            _ = try JSONDecoder().decode(
                CanonicalRoutePlanClient.PlanMutationResult.self,
                from: jsonData(malformedUnion)
            )
            throw VerificationFailure.failed("malformed persisted union decoded")
        } catch is DecodingError {
            // Expected.
        }

        var mismatched = boundRoute()
        var mismatchedBinding = mismatched["binding"] as! [String: Any]
        mismatchedBinding["activePlanChecksum"] = sha("9")
        mismatched["binding"] = mismatchedBinding
        let mismatchedPlan = try JSONDecoder().decode(
            CanonicalRoutePlanClient.BoundRoutePlan.self,
            from: jsonData(mismatched)
        )
        try require(mismatchedPlan.rendererPayload == nil,
                    "checksum-mismatched binding reached renderer")

        var stale = boundRoute()
        var stalePlan = stale["plan"] as! [String: Any]
        stalePlan["freshnessState"] = "stale"
        stale["plan"] = stalePlan
        let staleRoute = try JSONDecoder().decode(
            CanonicalRoutePlanClient.BoundRoutePlan.self,
            from: jsonData(stale)
        )
        try require(staleRoute.rendererPayload == nil,
                    "stale operational claim reached renderer")

        var inaccessible = boundRoute()
        var inaccessiblePlan = inaccessible["plan"] as! [String: Any]
        var inaccessibleInstructions = inaccessiblePlan["instructions"] as! [[String: Any]]
        inaccessibleInstructions[0]["accessibilityText"] = ""
        inaccessiblePlan["instructions"] = inaccessibleInstructions
        inaccessible["plan"] = inaccessiblePlan
        let inaccessibleRoute = try JSONDecoder().decode(
            CanonicalRoutePlanClient.BoundRoutePlan.self,
            from: jsonData(inaccessible)
        )
        try require(inaccessibleRoute.rendererPayload == nil,
                    "active route without accessible guidance reached renderer")

        var incompleteSources = boundRoute()
        var incompletePlan = incompleteSources["plan"] as! [String: Any]
        var planSources = incompletePlan["sources"] as! [[String: Any]]
        planSources.removeLast()
        incompletePlan["sources"] = planSources
        incompleteSources["plan"] = incompletePlan
        var bindings = incompleteSources["sourceBindings"] as! [[String: Any]]
        bindings.removeLast()
        incompleteSources["sourceBindings"] = bindings
        let incompleteSourceRoute = try JSONDecoder().decode(
            CanonicalRoutePlanClient.BoundRoutePlan.self,
            from: jsonData(incompleteSources)
        )
        try require(incompleteSourceRoute.rendererPayload == nil,
                    "mode route missing required validation evidence reached renderer")

        var nonOperational = boundRoute()
        var nonOperationalPlan = nonOperational["plan"] as! [String: Any]
        nonOperationalPlan["operational"] = false
        nonOperationalPlan["state"] = "blocked"
        nonOperationalPlan["operationalReason"] = "Licensed coverage is incomplete."
        nonOperational["plan"] = nonOperationalPlan
        let blockedPlan = try JSONDecoder().decode(
            CanonicalRoutePlanClient.BoundRoutePlan.self,
            from: jsonData(nonOperational)
        )
        try require(blockedPlan.rendererLines == nil,
                    "non-operational geometry reached renderer")

        var invalidCoordinate = boundRoute()
        var invalidPlan = invalidCoordinate["plan"] as! [String: Any]
        var invalidGeometry = invalidPlan["geometry"] as! [String: Any]
        invalidGeometry["coordinates"] = [[[181.0, 37.0], [-122.0, 38.0]]]
        invalidPlan["geometry"] = invalidGeometry
        invalidCoordinate["plan"] = invalidPlan
        do {
            _ = try JSONDecoder().decode(
                CanonicalRoutePlanClient.BoundRoutePlan.self,
                from: jsonData(invalidCoordinate)
            )
            throw VerificationFailure.failed("out-of-bounds GeoJSON decoded")
        } catch is DecodingError {
            // Expected.
        }

        print("Canonical route iOS contract: PASS")
    }
}
