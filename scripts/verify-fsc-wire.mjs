import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const sourcePath = fileURLToPath(new URL('../EusoTrip/Views/Catalyst/395_CatalystFuelSurchargeSchedule.swift', import.meta.url));
const source = readFileSync(sourcePath, 'utf8');
const names = ['FuelSource_395', 'ContractDiesel_395', 'MatchedBracket_395', 'PreviewWire_395'];
const declarations = names.map(name => {
  const start = source.indexOf(`    private struct ${name}:`);
  assert.ok(start >= 0, `Missing ${name}`);
  // These nested declarations end at the parent's four-space indentation.
  const end = source.indexOf('\n    }', start);
  const oneLine = source.indexOf('\n', start);
  const text = source.slice(start, source.slice(start, oneLine).endsWith('}') ? oneLine : end + 6);
  return text.replace('private struct', 'struct');
}).join('\n');
assert.doesNotMatch(source, /rateSheet\.getCurrentDiesel|liveDieselValue \?\? 3\.50|preview\.fsc > 0/);
assert.match(source, /let active = row\.id == matchedId/);
assert.match(source, /PreviewInput_395\(scheduleId: schedule\.id\)/);
assert.match(source, /fuelType: "diesel"/);
assert.match(source, /fuelExpiredThrough = max\(fuelExpiredThrough, deadline\)\s+loadGeneration = UUID\(\)/);
const program = `import Foundation
${declarations}
let now = ISO8601DateFormatter().date(from: "2026-09-04T12:00:00Z")!
let observation: [String: Any] = ["price": 5.599, "period": "2026-08-31", "region": "PADD2", "change1w": NSNull(),
  "freshnessSec": 410400, "nextReleaseAt": "2026-09-09T14:00:00.000Z",
  "sources": [["provider": "EIA", "scopeKey": "PADD2", "url": "https://www.eia.gov/dnav/pet/hist/LeafHandler.ashx"]]]
func decode(_ fields: [String: Any]) throws -> PreviewWire_395 {
    try JSONDecoder().decode(PreviewWire_395.self, from: JSONSerialization.data(withJSONObject: fields))
}
let table: [String: Any] = ["fsc": 0, "fscUnit": "per_mile", "method": "table", "paddPrice": 5.599,
  "basePrice": NSNull(), "fuel": observation, "matchedBracket": ["id": 11]]
let zero = try decode(table)
precondition(zero.fsc == 0 && zero.basePrice == nil && zero.matchedBracket?.id == 11)
precondition(zero.fuel?.isUsable(for: "2", now: now) == true)
precondition(zero.fuel?.isUsable(for: "3", now: now) == false)
precondition(zero.fuel?.isUsable(for: "2", now: now.addingTimeInterval(7 * 86400)) == false)
var fixed = table
fixed["method"] = "cpm"; fixed["fsc"] = 0.04; fixed["paddPrice"] = NSNull(); fixed["fuel"] = NSNull(); fixed["matchedBracket"] = NSNull()
let fallback = try decode(fixed)
precondition(fallback.fsc == 0.04 && fallback.paddPrice == nil && fallback.fuel == nil)
var exact = table; exact["fsc"] = 0.1555
let precise = try decode(exact)
precondition(precise.fsc == 0.1555)
for (key, value) in [("sources", [] as Any), ("region", "PADD3" as Any), ("nextReleaseAt", "invalid" as Any), ("price", 0 as Any)] {
    var broken = observation; broken[key] = value
    var payload = table; payload["fuel"] = broken
    let invalid = try decode(payload)
    precondition(invalid.fuel?.isUsable(for: "2", now: now) == false)
}
print("10 FSC decoder/evidence assertions passed (source-extracted Swift, not a SwiftUI build)")
`;
const directory = mkdtempSync(join(tmpdir(), 'eusotrip-fsc-wire-'));
try {
  const swift = join(directory, 'main.swift');
  const binary = join(directory, 'fsc-wire');
  writeFileSync(swift, program);
  for (const [command, args] of [
    ['swiftc', ['-swift-version', '6', '-strict-concurrency=complete', '-warnings-as-errors', swift, '-o', binary]],
    [binary, []],
    ['swiftc', ['-frontend', '-parse', sourcePath]],
  ]) {
    const result = spawnSync(command, args, { stdio: 'inherit', timeout: 120000 });
    if (result.status !== 0) throw new Error(`${command} did not pass (status ${result.status}, signal ${result.signal})`);
  }
} finally { rmSync(directory, { recursive: true, force: true }); }
