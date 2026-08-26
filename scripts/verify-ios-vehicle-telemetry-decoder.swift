import Foundation

private struct VehicleTelemetryFixture: Decodable {
    struct Metric: Decodable {
        let tracked: Bool?
        let source: String?
        let freshness: String?
    }

    struct Provenance: Decodable {
        let odometer: Metric?
        let fuelLevel: Metric?
        let speed: Metric?
        let heading: Metric?
    }

    let odometer: Double?
    let fuelLevel: Double?
    let speed: Double?
    let heading: Double?
    let provenance: Provenance?

    private enum Keys: String, CodingKey {
        case odometer, fuelLevel, speed, heading, telemetry, provenance
    }

    private static func optionalDouble(
        _ container: KeyedDecodingContainer<Keys>,
        _ key: Keys
    ) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key), value.isFinite {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let raw = try? container.decodeIfPresent(String.self, forKey: key),
           let value = Double(raw), value.isFinite {
            return value
        }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        odometer = Self.optionalDouble(container, .odometer)
        fuelLevel = Self.optionalDouble(container, .fuelLevel)
        speed = Self.optionalDouble(container, .speed)
        heading = Self.optionalDouble(container, .heading)
        provenance = try container.decodeIfPresent(Provenance.self, forKey: .provenance)
            ?? container.decodeIfPresent(Provenance.self, forKey: .telemetry)
    }
}

@main
private enum VerifyVehicleTelemetryDecoder {
    static func main() throws {
        let decoder = JSONDecoder()
        let unknown = try decoder.decode(
            VehicleTelemetryFixture.self,
            from: Data(#"{"odometer":null,"fuelLevel":null,"speed":null,"heading":null}"#.utf8)
        )
        precondition(unknown.odometer == nil)
        precondition(unknown.fuelLevel == nil)
        precondition(unknown.speed == nil)
        precondition(unknown.heading == nil)

        let observed = try decoder.decode(
            VehicleTelemetryFixture.self,
            from: Data(#"{"odometer":0,"fuelLevel":0,"speed":"0","heading":0,"telemetry":{"odometer":{"tracked":true,"source":"vehicles.mileage","freshness":"2026-08-24T12:00:00Z"}}}"#.utf8)
        )
        precondition(observed.odometer == 0)
        precondition(observed.fuelLevel == 0)
        precondition(observed.speed == 0)
        precondition(observed.heading == 0)
        precondition(observed.provenance?.odometer?.tracked == true)
        precondition(observed.provenance?.odometer?.source == "vehicles.mileage")

        let malformed = try decoder.decode(
            VehicleTelemetryFixture.self,
            from: Data(#"{"odometer":"unknown","fuelLevel":"NaN","speed":{},"heading":[]}"#.utf8)
        )
        precondition(malformed.odometer == nil)
        precondition(malformed.fuelLevel == nil)
        precondition(malformed.speed == nil)
        precondition(malformed.heading == nil)

        print("iOS vehicle telemetry decoder verified: null, real zero, provenance, and malformed input.")
    }
}
