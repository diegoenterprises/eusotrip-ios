import Foundation
import JavaScriptCore

private struct Point {
    let lat: Double
    let lng: Double
    let timestamp: String
    let speed: Double?
    let heading: Double?
    let accuracy: Double?
    let altitude: Double?
    let batteryLevel: Double?
    let isCharging: Bool?
    let odometer: Double?
    let activity: String?
    let isMock: Bool?
}

private func canonicalPayload(
    locations: [Point],
    loadId: Int?,
    vehicleId: Int?,
    loadState: String?
) throws -> String {
    func number(_ value: Double?) -> Any {
        value.map { NSNumber(value: $0) } ?? NSNull()
    }
    func integer(_ value: Int?) -> Any {
        value.map { NSNumber(value: $0) } ?? NSNull()
    }
    func boolean(_ value: Bool?) -> Any {
        value.map { NSNumber(value: $0) } ?? NSNull()
    }
    func string(_ value: String?) -> Any {
        value ?? NSNull()
    }

    let rows: [[Any]] = locations.map { point in
        [
            NSNumber(value: point.lat),
            NSNumber(value: point.lng),
            point.timestamp,
            number(point.speed),
            number(point.heading),
            number(point.accuracy),
            number(point.altitude),
            number(point.batteryLevel),
            boolean(point.isCharging),
            number(point.odometer),
            string(point.activity),
            boolean(point.isMock),
        ]
    }
    let payload: [Any] = [
        "location.telemetry.locationBatch.v1",
        integer(loadId),
        integer(vehicleId),
        string(loadState),
        rows,
    ]
    guard let context = JSContext(),
          let stringify = context.evaluateScript("JSON.stringify"),
          let payloadValue = JSValue(object: payload, in: context),
          let result = stringify.call(withArguments: [payloadValue as Any])?.toString(),
          context.exception == nil else {
        fatalError("JavaScriptCore could not stringify the canonical payload")
    }
    return result
}

@main
private struct LocationBatchAttestationPayloadTest {
    static func main() throws {
        let points = [
            Point(
                lat: 29.7604,
                lng: -95.3698,
                timestamp: "2026-08-24T12:00:00.000Z",
                speed: 55.5,
                heading: 180,
                accuracy: nil,
                altitude: 13.25,
                batteryLevel: 84,
                isCharging: true,
                odometer: nil,
                activity: "automotive",
                isMock: false
            ),
            Point(
                lat: 30,
                lng: -96,
                timestamp: "2026-08-24T12:01:00.000Z",
                speed: nil,
                heading: nil,
                accuracy: nil,
                altitude: nil,
                batteryLevel: nil,
                isCharging: nil,
                odometer: nil,
                activity: nil,
                isMock: nil
            ),
        ]
        let actual = try canonicalPayload(
            locations: points,
            loadId: 7003,
            vehicleId: nil,
            loadState: "in_transit"
        )
        let expected = #"["location.telemetry.locationBatch.v1",7003,null,"in_transit",[[29.7604,-95.3698,"2026-08-24T12:00:00.000Z",55.5,180,null,13.25,84,true,null,"automotive",false],[30,-96,"2026-08-24T12:01:00.000Z",null,null,null,null,null,null,null,null,null]]]"#
        precondition(actual == expected, "Canonical App Attest payload mismatch:\n\(actual)")

        let nullContext = try canonicalPayload(
            locations: [points[1]],
            loadId: nil,
            vehicleId: nil,
            loadState: nil
        )
        precondition(
            nullContext.hasPrefix(#"["location.telemetry.locationBatch.v1",null,null,null,"#),
            "Optional top-level context must preserve null slots"
        )
        print("iOS location batch App Attest payload verified byte-for-byte.")
    }
}
