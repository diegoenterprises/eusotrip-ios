#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const source = readFileSync(
  resolve(root, "EusoTrip/Services/EusoTripAPI.swift"),
  "utf8",
);
const start = source.indexOf("struct LocationBatchPoint");
const end = source.indexOf("// MARK: Offline-outbox eligibility", start);
if (start < 0 || end < 0)
  throw new Error("Location batch API section not found");
const batch = source.slice(start, end);
const failures = [];

for (const required of [
  "location.telemetry.locationBatch.v1",
  "jsonInteger(loadId)",
  "jsonInteger(vehicleId)",
  "jsonString(loadState)",
  "jsonNumber(point.speed)",
  "jsonNumber(point.heading)",
  "jsonNumber(point.accuracy)",
  "jsonNumber(point.altitude)",
  "jsonNumber(point.batteryLevel)",
  "jsonBoolean(point.isCharging)",
  "jsonNumber(point.odometer)",
  "jsonString(point.activity)",
  "jsonBoolean(point.isMock)",
  'context.evaluateScript("JSON.stringify")',
  "AppAttestClient.attestation(for: context)",
  "let _attest: AppAttestClient.AttestEnvelope?",
  "let provenance: LocationBatchProvenance?",
  "let rewardQualityEligible: Bool",
  "var persistedCount: Int?",
  "var isRealtimeEvidence: Bool",
]) {
  if (!batch.includes(required)) failures.push(`missing ${required}`);
}

for (const forbidden of [
  "ack.ingested ?? ack.inserted ?? 0",
  "JSONSerialization.data(\n            withJSONObject: canonicalPayload",
  '"_attest": true',
  "let rewardQualityEligible = true",
]) {
  if (batch.includes(forbidden)) failures.push(`forbidden ${forbidden}`);
}

const orderedPointFields = [
  "point.lat",
  "point.lng",
  "point.timestamp",
  "point.speed",
  "point.heading",
  "point.accuracy",
  "point.altitude",
  "point.batteryLevel",
  "point.isCharging",
  "point.odometer",
  "point.activity",
  "point.isMock",
];
let cursor = batch.indexOf("let canonicalLocations");
for (const field of orderedPointFields) {
  const next = batch.indexOf(field, cursor);
  if (next < 0) failures.push(`canonical point order missing ${field}`);
  cursor = Math.max(cursor, next);
}

if (failures.length) {
  console.error(
    `iOS location batch attestation contract failed:\n- ${failures.join("\n- ")}`,
  );
  process.exit(1);
}

console.log("iOS location batch attestation contract verified.");
