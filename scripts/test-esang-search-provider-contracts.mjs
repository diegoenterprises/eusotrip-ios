import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = process.cwd();
const read = (path) => readFileSync(resolve(root, path), "utf8");

const search = read("EusoTrip/Views/Shipper/393_SearchResults.swift");
const shipperCoach = read("EusoTrip/Views/Shipper/ShipperESangCoachSheet.swift");
const driverCoach = read("EusoTrip/Views/Driver/DriverTabPanes.swift");
const postLoad = read("EusoTrip/Views/Shipper/204_ShipperPostLoad.swift");
const commission = read("EusoTrip/Views/Catalyst/331_CatalystCommissionEngine.swift");

assert.match(search, /struct In: Encodable \{ let query: String \}/);
assert.doesNotMatch(search, /struct In: Encodable \{ let q: String \}/);
assert.match(search, /forKey: \.results/);
assert.match(search, /forKey: \.type/);
assert.match(search, /payload\["loadId"\] = hit\.id/);

assert.match(shipperCoach, /sessionId: conversationSessionId/);
assert.match(driverCoach, /sessionId: conversationSessionId/);
assert.doesNotMatch(shipperCoach, /ShipmentAgentService\.shared\.ask/);
assert.doesNotMatch(driverCoach, /ShipmentAgentService\.shared\.ask/);
assert.doesNotMatch(driverCoach, /come back with specifics in a sec/i);
assert.doesNotMatch(shipperCoach, /Three lanes need posting|Two of your loads need attention|Settlement queue cleared/i);

assert.match(postLoad, /rateCompareTask\?\.cancel\(\)/);
assert.match(postLoad, /Task\.sleep\(nanoseconds: 350_000_000\)/);
assert.match(postLoad, /lastRateCompareKey == key/);

assert.match(commission, /onChange\(of: calculationSignature\)/);
assert.match(commission, /scheduleCalculation\(delayNanoseconds: 0\)/);
assert.match(commission, /temporarily rate-limited\. Wait a moment, then retry\./);
assert.doesNotMatch(commission, /onChange\(of: [^)]+\)\s*\{[^}]*Task \{ await calculate\(\)/s);

console.log("ESANG/search/provider iOS source contracts: PASS");
