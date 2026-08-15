#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const reportsRoot = path.resolve(root, "../_the_oath_reports");
const cachePath = path.join(
  reportsRoot,
  "asc_feedback_2026-08-14T0205",
  "_summary.json",
);
const ledgerPath = process.env.ASC_CRASH_LEDGER ?? path.join(
  reportsRoot,
  "_ASC_CRASH_LEDGER_BUILD_850_2026-08-14.json",
);

const readJSON = (file) => JSON.parse(fs.readFileSync(file, "utf8"));
const cache = readJSON(cachePath);
const ledger = readJSON(ledgerPath);
const source = {
  api: fs.readFileSync(path.join(root, "EusoTrip/Services/EusoTripAPI.swift"), "utf8"),
  erg: fs.readFileSync(path.join(root, "EusoTrip/Views/Driver/096_MeErg.swift"), "utf8"),
  postLoad: fs.readFileSync(path.join(root, "EusoTrip/Views/Shipper/204_ShipperPostLoad.swift"), "utf8"),
  project: fs.readFileSync(path.join(root, "EusoTrip.xcodeproj/project.pbxproj"), "utf8"),
};

const assert = (condition, message) => {
  if (!condition) throw new Error(message);
};
const requireText = (target, needle, label) => {
  assert(target.includes(needle), `${label}: missing ${needle}`);
};
const forbidText = (target, needle, label) => {
  assert(!target.includes(needle), `${label}: forbidden ${needle}`);
};

const ascRows = cache.crashFeedback;
assert(Array.isArray(ascRows) && ascRows.length === 9, "ASC cache must contain 9 crash submissions");
assert(Array.isArray(ledger.rows) && ledger.rows.length === 9, "ledger must contain 9 crash rows");
assert(ledger.currentSourceBuild === "850", "ledger current source build must remain 850");
assert(ledger.buildChanged === false, "crash lane must not bump the build");

const projectBuilds = [...source.project.matchAll(/CURRENT_PROJECT_VERSION = (\d+);/g)]
  .map((match) => match[1]);
assert(projectBuilds.length > 0, "project build settings not found");
assert(projectBuilds.every((build) => build === "850"), "project build settings changed from 850");

const expected = new Map(ascRows.map((row) => [row.id, row.buildVersion]));
const actual = new Map(ledger.rows.map((row) => [row.ascId, row.affectedBuild]));
assert(actual.size === 9, "ledger ASC IDs must be unique");
for (const [id, build] of expected) {
  assert(actual.get(id) === build, `ledger row mismatch for ${id}`);
}

const logCount = ascRows.filter((row) => row.crashLogFile != null).length;
assert(logCount === 5, "ASC cache must retain exactly 5 downloaded logs");
assert(
  ledger.rows.filter((row) => row.signature === "UNAVAILABLE_NO_DOWNLOADED_CRASH_LOG").length === 4,
  "ledger must mark exactly 4 metadata-only signatures",
);

for (const row of ledger.rows) {
  assert(Object.hasOwn(row, "signature"), `${row.ascId}: signature missing`);
  assert(Object.hasOwn(row, "rootCause"), `${row.ascId}: rootCause missing`);
  assert(Object.hasOwn(row, "duplicateOf"), `${row.ascId}: duplicateOf missing`);
  assert(Array.isArray(row.stackEvidence), `${row.ascId}: stackEvidence missing`);
  assert(Array.isArray(row.verification) && row.verification.length > 0, `${row.ascId}: verification missing`);
  if (row.duplicateOf) {
    assert(actual.has(row.duplicateOf), `${row.ascId}: duplicate target is not in this ledger`);
    assert(row.duplicateOf !== row.ascId, `${row.ascId}: self-duplicate`);
  }
}

const serialized = JSON.stringify(ledger);
for (const key of [
  '"comment"',
  '"deviceModel"',
  '"deviceFamily"',
  '"locale"',
  '"screenWidth"',
  '"screenHeight"',
  '"incidentIdentifier"',
]) {
  forbidText(serialized, key, "tester privacy");
}
for (const secretMarker of ["BEGIN PRIVATE KEY", "ASC_KEY_ID", "ASC_ISSUER_ID", "sk_live_"]) {
  forbidText(serialized, secretMarker, "secret hygiene");
}

requireText(source.api, "URLSessionConfiguration.ephemeral", "API private transport");
requireText(source.api, "config.urlCache = nil", "API cache isolation");
requireText(source.api, "try Task.checkCancellation()", "API cancellation boundary");
requireText(source.api, "private func transportData(for original: URLRequest)", "API shared transport");
requireText(source.erg, ".task(id: retryAttempt)", "ERG structured request ownership");
requireText(source.erg, "let response = try await EusoTripAPI.shared.erg.searchByUN(unNumber)", "ERG real request");
forbidText(source.erg, "while store.detail == nil", "ERG retry loop removal");
requireText(source.postLoad, "draftPersistWork?.cancel()", "post-load teardown");
requireText(source.postLoad, "DispatchQueue.global(qos: .utility).async", "post-load off-main persistence");
requireText(source.postLoad, "generation == draftHydrationGeneration", "post-load stale hydration rejection");

console.log(JSON.stringify({
  verified: true,
  ascRows: ascRows.length,
  downloadedLogs: logCount,
  metadataOnly: 4,
  currentBuild: ledger.currentSourceBuild,
  duplicateRows: ledger.rows.filter((row) => row.duplicateOf != null).length,
  sourceContracts: 11,
  privacy: "tester PII and secret markers absent",
}, null, 2));
