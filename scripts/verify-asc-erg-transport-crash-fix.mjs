#!/usr/bin/env node

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const root = process.cwd();
const api = readFileSync(join(root, "EusoTrip/Services/EusoTripAPI.swift"), "utf8");
const erg = readFileSync(join(root, "EusoTrip/Views/Driver/096_MeErg.swift"), "utf8");

assert.match(
  api,
  /URLSessionConfiguration\.ephemeral/,
  "EusoTripAPI must use an isolated ephemeral URLSession configuration"
);
assert.match(
  api,
  /config\.httpCookieStorage\s*=\s*HTTPCookieStorage\.shared/,
  "The isolated API session must retain the authenticated shared cookie jar"
);
assert.match(
  api,
  /config\.httpShouldSetCookies\s*=\s*true/,
  "The isolated API session must accept refreshed authentication cookies"
);
assert.doesNotMatch(
  api,
  /URLCache\.shared\.removeAllCachedResponses/,
  "EusoTripAPI must not mutate the process-wide URLCache"
);
assert.equal(
  [...api.matchAll(/session\.data\(for:/g)].length,
  1,
  "Every EusoTripAPI request must pass through the single transportData boundary"
);

const transportStart = api.indexOf("private func transportData");
const performStart = api.indexOf("private func perform", transportStart);
assert.ok(transportStart >= 0 && performStart > transportStart, "transportData boundary is missing");
const transport = api.slice(transportStart, performStart);
assert.equal(
  [...transport.matchAll(/try Task\.checkCancellation\(\)/g)].length,
  2,
  "transportData must check cancellation before and after URLSession work"
);
assert.match(transport, /reloadIgnoringLocalAndRemoteCacheData/);
assert.match(transport, /"no-store, no-cache"/);
assert.equal(
  [...api.matchAll(/try await transportData\(for: req\)/g)].length,
  4,
  "typed, raw, authenticated-download, and wallet-pass paths must share transportData"
);

const detailMarker = "// MARK: - Detail sheet";
const detailStart = erg.indexOf(detailMarker);
assert.ok(detailStart >= 0, "ERG detail section is missing");
const detail = erg.slice(detailStart);

assert.match(detail, /@State private var detail: ErgAPI\.MaterialDetail\?/);
assert.match(detail, /\.task\(id: retryAttempt\)/);
assert.match(detail, /private func loadDetail\(\) async/);
assert.equal(
  [...detail.matchAll(/try Task\.checkCancellation\(\)/g)].length,
  2,
  "ERG detail must reject canceled work before request and before publication"
);
assert.doesNotMatch(detail, /@ObservedObject var store/);
assert.doesNotMatch(detail, /store\.loadDetail/);
assert.doesNotMatch(detail, /while\s+store\.detail\s*==\s*nil/);
assert.doesNotMatch(detail, /try\?\s+await\s+Task\.sleep/);

console.log("ASC ERG/transport crash contract: 19/19 passed");
