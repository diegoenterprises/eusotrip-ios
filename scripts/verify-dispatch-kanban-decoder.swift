import Foundation

private struct StrictStringLoad: Decodable {
    let id: String
    let loadNumber: String
    let status: String
}

private struct CompatibleLoad: Decodable {
    let id: String
    let loadNumber: String
    let status: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let string = try? container.decode(String.self, forKey: .id) {
            id = string
        } else if let integer = try? container.decode(Int.self, forKey: .id) {
            id = String(integer)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                .init(
                    codingPath: container.codingPath + [CodingKeys.id],
                    debugDescription: "Expected a string or integer load id"
                )
            )
        }
        loadNumber = try container.decode(String.self, forKey: .loadNumber)
        status = try container.decode(String.self, forKey: .status)
    }

    private enum CodingKeys: String, CodingKey {
        case id, loadNumber, status
    }
}

private struct Board<Load: Decodable>: Decodable {
    let loads: [Load]
    let total: Int
}

private let fixture = Data(#"""
{
  "loads": [
    { "id": 2, "loadNumber": "AP-TEST-0002", "status": "assigned" },
    { "id": "900719925474099312345", "loadNumber": "AP-OPAQUE", "status": "in_transit" }
  ],
  "total": 2
}
"""#.utf8)

private var reproducedASCFailure = false
do {
    _ = try JSONDecoder().decode(Board<StrictStringLoad>.self, from: fixture)
} catch DecodingError.typeMismatch(let type, let context) {
    let path = context.codingPath.map { key -> String in
        if let index = key.intValue { return "[\(index)]" }
        return key.stringValue
    }.joined(separator: ".")
    precondition(type == String.self, "Strict decoder failed on an unexpected type: \(type)")
    precondition(path == "loads.[0].id", "Strict decoder failed at an unexpected path: \(path)")
    reproducedASCFailure = true
} catch {
    fatalError("Strict decoder failed unexpectedly: \(error)")
}

precondition(reproducedASCFailure, "The ASC String decoder unexpectedly accepted a numeric id")

do {
    let decoded = try JSONDecoder().decode(Board<CompatibleLoad>.self, from: fixture)
    precondition(decoded.loads.map(\.id) == ["2", "900719925474099312345"])
    precondition(decoded.total == 2)
    print("Dispatcher Live Ops decoder verified: ASC numeric mismatch reproduced; numeric compatibility and opaque string IDs both round-trip.")
} catch {
    fatalError("Compatible Dispatcher decoder failed: \(error)")
}
