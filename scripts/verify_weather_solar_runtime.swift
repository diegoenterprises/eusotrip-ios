import Foundation
import SwiftUI

// WeatherSnapshot's solar policy is Foundation-only; these color tokens are
// the minimal compile shim for unrelated alert/risk presentation properties.
enum Brand {
    static let blue = Color.blue
    static let danger = Color.red
    static let info = Color.cyan
    static let rail = Color.gray
    static let success = Color.green
    static let vessel = Color.teal
    static let warning = Color.orange
}

// The runtime gate compiles WeatherSnapshot in isolation from WeatherService.
// Keep the production numeric contract available without loading networking,
// CoreLocation, WeatherKit, or app authentication dependencies.
enum WeatherNumeric {
    static let temperatureF = -200...250
    static let windMph = 0...600
    static let visibilityMi = 0...1_000
    static let percent = 0...100
    static let uvIndex = 0...100

    static func roundedInt(
        _ value: Double?,
        allowed range: ClosedRange<Int>? = nil
    ) -> Int? {
        guard let value, value.isFinite else { return nil }
        let rounded = value.rounded()
        guard rounded >= Double(Int.min), rounded < Double(Int.max) else { return nil }
        let result = Int(rounded)
        guard range?.contains(result) ?? true else { return nil }
        return result
    }

    static func validatedInt(
        _ value: Int?,
        allowed range: ClosedRange<Int>? = nil
    ) -> Int? {
        guard let value, range?.contains(value) ?? true else { return nil }
        return value
    }

    static func finite(
        _ value: Double?,
        allowed range: ClosedRange<Double>? = nil
    ) -> Double? {
        guard let value, value.isFinite, range?.contains(value) ?? true else { return nil }
        return value
    }

    static func nonnegativeFinite(_ value: Double?) -> Double? {
        guard let value = finite(value), value >= 0 else { return nil }
        return value
    }

    static func elapsedWholeSeconds(from start: Date, to end: Date = Date()) -> Int? {
        guard let interval = finite(end.timeIntervalSince(start)) else { return nil }
        return roundedInt(max(0, interval.rounded(.down)))
    }
}

@main
private struct WeatherSolarRuntimeGate {
    static func main() throws {
        let formatter = ISO8601DateFormatter()
        let austinNight = try require(
            formatter.date(from: "2026-08-14T06:57:00Z"),
            "invalid Austin fixture timestamp"
        )

        var staleHint = snapshot()
        staleHint.latitude = 30.2672
        staleHint.longitude = -97.7431
        staleHint.timezoneId = "America/Chicago"
        staleHint.observedAt = austinNight.addingTimeInterval(-3600)
        staleHint.isNightHint = false
        try expect(
            staleHint.displaySolarState(at: austinNight) == .night,
            "stale daytime hint painted daylight at Austin night"
        )

        var freshProvider = staleHint
        freshProvider.observedAt = austinNight
        freshProvider.isNightHint = true
        try expect(
            freshProvider.displaySolarState(at: austinNight) == .night,
            "fresh provider night condition was ignored"
        )

        let providerDay = try require(
            formatter.date(from: "2026-08-14T00:00:00Z"),
            "invalid provider-day fixture timestamp"
        )
        let nextNight = try require(
            formatter.date(from: "2026-08-15T06:30:00Z"),
            "invalid next-night fixture timestamp"
        )
        var projectedWindow = snapshot()
        projectedWindow.timezoneId = "America/Chicago"
        projectedWindow.sunriseAt = providerDay.addingTimeInterval(11.5 * 3600)
        projectedWindow.sunsetAt = providerDay.addingTimeInterval(25 * 3600)
        try expect(
            projectedWindow.solarState(at: nextNight) == .night,
            "provider sun window did not project in the location timezone"
        )

        let unknown = snapshot()
        try expect(
            unknown.solarState(at: austinNight) == .unknown,
            "missing solar evidence invented a celestial state"
        )
        try expect(
            unknown.dayPart(at: austinNight) == .night,
            "missing solar evidence invented a daytime atmosphere"
        )
        try expect(
            unknown.hemisphere == .unknown && unknown.season(at: austinNight) == .unknown,
            "missing latitude invented a hemisphere or season"
        )

        var equatorial = snapshot()
        equatorial.latitude = 0
        equatorial.longitude = 78
        try expect(
            equatorial.hemisphere == .equatorial && equatorial.season(at: austinNight) == .unknown,
            "a valid equatorial coordinate was rejected or assigned a false four-season state"
        )

        print("WEATHER_SOLAR_RUNTIME_GATE=PASS")
    }

    private static func snapshot() -> WeatherSnapshot {
        WeatherSnapshot(
            city: "Austin, TX",
            tempF: 80,
            windMph: 8,
            visibilityMi: 10,
            condition: "Clear",
            symbol: "sun.max.fill",
            nextAlert: nil,
            accent: .calm
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw GateError.failure(message)
        }
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw GateError.failure(message)
        }
        return value
    }

    private enum GateError: Error, CustomStringConvertible {
        case failure(String)

        var description: String {
            switch self {
            case .failure(let message): return message
            }
        }
    }
}
