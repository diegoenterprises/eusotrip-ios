#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const apiPath = new URL("../EusoTrip/Services/EusoTripAPI.swift", import.meta.url);
const source = readFileSync(apiPath, "utf8");
const marker = "    struct CommodityHit: Decodable, Equatable, Identifiable {";
const start = source.indexOf(marker);
if (start < 0) throw new Error("CommodityHit decoder was not found");

let depth = 0;
let end = -1;
for (let index = start; index < source.length; index += 1) {
  if (source[index] === "{") depth += 1;
  if (source[index] === "}") {
    depth -= 1;
    if (depth === 0) {
      end = index + 1;
      break;
    }
  }
}
if (end < 0) throw new Error("CommodityHit decoder is not balanced");

const commodityHit = source.slice(start, end).replace(/^ {4}/gm, "");
const swiftSource = `
import Foundation

${commodityHit}

struct Fixture {
    let json: String
    let name: String
    let code: String?
    let low: Double?
    let high: Double?
}

let fixtures = [
    Fixture(
        json: #"{"productName":"Latex (carboxylated styrene-butadiene)","pollutionCategory":"D","shipType":3,"tankType":"Gravity","unNumber":"—"}"#,
        name: "Latex (carboxylated styrene-butadiene)", code: "—", low: nil, high: nil
    ),
    Fixture(
        json: #"{"product":"Ultra-low sulfur diesel (ULSD #2)","sulfurClass":"ULSD","apiGravityBand":"33-37 (medium)"}"#,
        name: "Ultra-low sulfur diesel (ULSD #2)", code: nil, low: nil, high: nil
    ),
    Fixture(
        json: #"{"productName":"Apples","tempMinF":30,"tempMaxF":35,"fsmaRegulated":true,"notes":"High ethylene producer."}"#,
        name: "Apples", code: nil, low: 30, high: 35
    ),
    Fixture(
        json: #"{"isoCode":"22G1","name":"20ft Standard (20GP / TEU)","class":"std"}"#,
        name: "20ft Standard (20GP / TEU)", code: "22G1", low: nil, high: nil
    ),
    Fixture(
        json: #"{"stcc":"2911210","description":"Gasoline (UN1203)","hazmatLinked":true}"#,
        name: "Gasoline (UN1203)", code: "2911210", low: nil, high: nil
    ),
]

let decoder = JSONDecoder()
for fixture in fixtures {
    let hit = try decoder.decode(CommodityHit.self, from: Data(fixture.json.utf8))
    precondition(hit.name == fixture.name, "Identity mismatch for \\(fixture.name)")
    precondition(hit.code == fixture.code, "Code mismatch for \\(fixture.name)")
    precondition(hit.tempLowF == fixture.low, "Low temperature mismatch for \\(fixture.name)")
    precondition(hit.tempHighF == fixture.high, "High temperature mismatch for \\(fixture.name)")
}

do {
    _ = try decoder.decode(CommodityHit.self, from: Data(#"{"unknown":"value"}"#.utf8))
    fatalError("Malformed commodity rows must not become a fabricated identity")
} catch DecodingError.keyNotFound {
    // Expected: unknown remains unknown instead of becoming a placeholder row.
}

print("Commodity decoder runtime verification passed (\\(fixtures.count)/\\(fixtures.count) live response families)")
`;

const directory = mkdtempSync(join(tmpdir(), "eusotrip-commodity-decoder-"));
const swiftPath = join(directory, "CommodityDecoderRuntime.swift");
try {
  writeFileSync(swiftPath, swiftSource);
  execFileSync("xcrun", ["swift", swiftPath], { stdio: "inherit" });
} finally {
  rmSync(directory, { recursive: true, force: true });
}
