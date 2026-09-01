import Foundation
import CoreLocation

private struct ExpectedCoordinate {
    let input: String
    let latitude: Double
    let longitude: Double
}

private func requireCoordinate(
    _ expected: ExpectedCoordinate,
    tolerance: Double = 0.000_000_000_001
) {
    guard let parsed = LatLongParser.parseDetailed(expected.input) else {
        fatalError("Expected coordinate input to parse: \(expected.input)")
    }
    precondition(
        abs(parsed.coordinate.latitude - expected.latitude) <= tolerance,
        "Latitude mismatch for \(expected.input): \(parsed.coordinate.latitude)"
    )
    precondition(
        abs(parsed.coordinate.longitude - expected.longitude) <= tolerance,
        "Longitude mismatch for \(expected.input): \(parsed.coordinate.longitude)"
    )
    precondition(
        parsed.originalText == expected.input.trimmingCharacters(in: .whitespacesAndNewlines),
        "Original coordinate text was not preserved for \(expected.input)"
    )
}

@main
private struct LatLongParserContract {
    static func main() {
        let valid = [
            ExpectedCoordinate(
                input: "40.712800123456, -74.006000987654",
                latitude: 40.712800123456,
                longitude: -74.006000987654
            ),
            ExpectedCoordinate(input: "+40.7128; -74.006", latitude: 40.7128, longitude: -74.006),
            ExpectedCoordinate(input: "40.7128N 74.0060W", latitude: 40.7128, longitude: -74.006),
            ExpectedCoordinate(input: "N40.7128 W74.0060", latitude: 40.7128, longitude: -74.006),
            ExpectedCoordinate(input: "-33.8688, 151.2093", latitude: -33.8688, longitude: 151.2093),
            ExpectedCoordinate(input: "0, -74.006", latitude: 0, longitude: -74.006),
            ExpectedCoordinate(input: "40.7128, 0", latitude: 40.7128, longitude: 0),
            ExpectedCoordinate(input: "0,0", latitude: 0, longitude: 0),
            ExpectedCoordinate(
                input: "40°42'46.08\"N, 74°0'21.6\"W",
                latitude: 40.7128,
                longitude: -74.006
            ),
            ExpectedCoordinate(
                input: "40° 42′ 46.08″ N, 74° 0′ 21.6″ W",
                latitude: 40.7128,
                longitude: -74.006
            ),
            ExpectedCoordinate(input: "40°42.768'N, 74°0.36'W", latitude: 40.7128, longitude: -74.006),
            ExpectedCoordinate(
                input: "geo:40.712800123456,-74.006000987654",
                latitude: 40.712800123456,
                longitude: -74.006000987654
            ),
            ExpectedCoordinate(input: "geo:0,0", latitude: 0, longitude: 0),
            ExpectedCoordinate(
                input: "geo:0,0?q=40.7128,-74.0060(New%20York)",
                latitude: 40.7128,
                longitude: -74.006
            ),
            ExpectedCoordinate(
                input: "https://maps.apple.com/?ll=40.712800123456,-74.006000987654",
                latitude: 40.712800123456,
                longitude: -74.006000987654
            ),
            ExpectedCoordinate(
                input: "https://www.google.com/maps/place/New+York/@40.7128,-74.006,15z",
                latitude: 40.7128,
                longitude: -74.006
            ),
            ExpectedCoordinate(
                input: "https://www.openstreetmap.org/#map=15/40.7128/-74.006",
                latitude: 40.7128,
                longitude: -74.006
            ),
            ExpectedCoordinate(
                input: "https://wego.here.com/?map=40.7128,-74.006,15,normal",
                latitude: 40.7128,
                longitude: -74.006
            ),
            ExpectedCoordinate(
                input: "https://www.bing.com/maps?cp=40.7128~-74.006",
                latitude: 40.7128,
                longitude: -74.006
            ),
        ]
        valid.forEach { requireCoordinate($0) }

        let invalid = [
            "",
            "40.7128",
            "91,0",
            "40,181",
            "-40N, 74W",
            "40N, +74W",
            "40°60'0\"N, 74°0'0\"W",
            "40°0'60\"N, 74°0'0\"W",
            "https://example.com/?q=40.7128,-74.006",
            "523 W Adams Street",
        ]
        for input in invalid {
            precondition(LatLongParser.parse(input) == nil, "Invalid coordinate parsed: \(input)")
        }

        for input in [
            "91,0",
            "0,0",
            "40.7128",
            "geo:91,0",
            "https://maps.apple.com/?ll=91,0",
        ] {
            precondition(
                LatLongParser.hasCoordinateIntent(input),
                "Malformed coordinate intent was mistaken for free text: \(input)"
            )
        }
        for input in ["523 W Adams Street", "Dock 4, Port of Houston"] {
            precondition(
                !LatLongParser.hasCoordinateIntent(input),
                "Ordinary location text was mistaken for a coordinate: \(input)"
            )
        }

        precondition(
            LatLongParser.validatedCoordinate(latitude: nil, longitude: -74) == nil,
            "Missing latitude must remain missing"
        )
        precondition(
            LatLongParser.validatedCoordinate(latitude: 40, longitude: nil) == nil,
            "Missing longitude must remain missing"
        )
        precondition(
            LatLongParser.validatedCoordinate(latitude: 0, longitude: -74) != nil,
            "A legitimate zero latitude must remain valid"
        )
        precondition(
            LatLongParser.validatedCoordinate(latitude: 40, longitude: 0) != nil,
            "A legitimate zero longitude must remain valid"
        )
        precondition(
            LatLongParser.validatedCoordinate(latitude: 0, longitude: 0) != nil,
            "The valid WGS-84 coordinate 0,0 must remain usable"
        )
        for coordinate in [
            (Double.nan, 10.0),
            (10.0, Double.nan),
            (Double.infinity, 10.0),
            (10.0, -Double.infinity),
            (90.000_001, 10.0),
            (10.0, -180.000_001),
        ] {
            precondition(
                LatLongParser.validatedCoordinate(
                    latitude: coordinate.0,
                    longitude: coordinate.1
                ) == nil,
                "Nonfinite or out-of-range coordinates must be rejected"
            )
        }

        let precision = CLLocationCoordinate2D(
            latitude: 40.712800123456,
            longitude: -74.006000987654
        )
        precondition(
            LatLongParser.displayString(precision) == "40.712800123456, -74.006000987654",
            "Coordinate display truncated the stored precision"
        )

        print("LatLongParser contract verified: 19 valid formats, complete-pair enforcement, nonfinite/range rejection, exact precision, and zero-axis support.")
    }
}
