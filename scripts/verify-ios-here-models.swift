import CoreLocation
import Foundation

private func jsonData(_ object: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

@main
private struct HereModelContract {
    static func main() throws {
        let zero = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let encoded = HereFlexiblePolyline.encode([
            zero,
            CLLocationCoordinate2D(latitude: 0.125, longitude: -0.25),
        ])
        let decoded = HereFlexiblePolyline.decode(encoded)
        precondition(decoded.count == 2, "Flexible polyline dropped a valid zero coordinate")
        precondition(decoded[0].latitude == 0 && decoded[0].longitude == 0)

        let routePayload: [String: Any] = [
            "routes": [[
                "sections": [[
                    "type": "vehicle",
                    "departure": [
                        "time": "2026-08-23T12:00:00Z",
                        "place": ["location": ["lat": 0.0, "lng": 0.0]],
                    ],
                    "arrival": [
                        "time": "2026-08-23T12:30:00Z",
                        "place": ["location": ["lat": 0.125, "lng": -0.25]],
                    ],
                    "summary": ["duration": 1_800, "length": 42_000],
                    "polyline": encoded,
                    "spans": [[
                        "offset": 0,
                        "length": 2,
                        "maxSpeed": 27.78,
                        "functionalClass": 1,
                        "truckAttributes": ["open"],
                    ]],
                    "tolls": [[
                        "countryCode": "USA",
                        "tollSystem": "Example Authority",
                        "fares": [[
                            "price": ["value": 12.5, "currency": "USD"],
                        ]],
                    ]],
                    "actions": [[
                        "action": "depart",
                        "offset": 0,
                        "instruction": "Head south",
                    ]],
                ]],
            ]],
        ]
        let response = try JSONDecoder().decode(
            HereRoutesResponse.self,
            from: jsonData(routePayload)
        )
        let section = response.routes[0].sections[0]
        precondition(section.departure.place.coordinate?.latitude == 0)
        precondition(section.departure.place.coordinate?.longitude == 0)
        precondition(section.spans?.first?.effectiveMaxSpeed == 27.78)
        precondition(section.spans?.first?.functionalClass == 1)
        precondition(section.spans?.first?.truckAttributes?.flags == ["open"])
        precondition(section.tolls?.first?.fares?.first?.price?.value == 12.5)
        precondition(section.actions?.first?.offset == 0)

        let geocodePayload: [String: Any] = [
            "id": "here:af:streetsection:1",
            "title": "1600 Pennsylvania Avenue NW, Washington, DC",
            "resultType": "houseNumber",
            "position": ["lat": 38.8977, "lng": -77.0365],
            "address": [
                "houseNumber": "1600",
                "street": "Pennsylvania Avenue NW",
                "city": "Washington",
                "stateCode": "DC",
                "postalCode": "20500",
                "countryName": "United States",
            ],
        ]
        let item = try JSONDecoder().decode(
            HereGeocodeItem.self,
            from: jsonData(geocodePayload)
        )
        let formatted = item.formattedAddress(provenance: .hereGeocode)
        precondition(
            formatted.label == "1600 Pennsylvania Avenue NW, Washington, DC 20500, United States",
            "Canonical address order drifted: \(formatted.label)"
        )
        precondition(formatted.provider == "HERE")
        precondition(formatted.provenance == .hereGeocode)

        let unknown = HereAddressFormatter.format(
            address: HereAddress(
                label: nil,
                countryCode: nil,
                countryName: nil,
                stateCode: nil,
                state: nil,
                county: nil,
                city: nil,
                district: nil,
                street: nil,
                postalCode: nil,
                houseNumber: nil
            ),
            fallbackTitle: nil,
            provenance: .hereReverseGeocode
        )
        precondition(unknown.label == "Unknown address")
        precondition(!unknown.isKnown)
        precondition(unknown.provider == "HERE")

        print("HERE native models verified: zero-coordinate polyline, route spans/tolls/actions, and canonical address provenance.")
    }
}
