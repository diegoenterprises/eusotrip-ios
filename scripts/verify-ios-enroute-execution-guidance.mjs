#!/usr/bin/env node

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const source = readFileSync(
  join(process.cwd(), "EusoTrip/Views/Driver/035_EnRouteDrive.swift"),
  "utf8",
);

function includesAll(values, label) {
  for (const value of values) {
    assert.ok(
      source.includes(value),
      `${label} is missing ${JSON.stringify(value)}`,
    );
  }
}

includesAll(
  [
    "@State private var canonicalRoutePlanVersionID:",
    "payload.identity.routePlanVersionId",
    "state.assignment.routePlanVersionId == expectedVersionID",
    "state.assignment.routePlanVersionId == expectedVersionID,",
    "state.mode == expectedMode",
    "return state.guidanceSnapshot",
    ".task(id: executionPollIdentity)",
    "refreshExecution(\n                subject: .load(loadID)",
    "canonicalGuidance?.observation.speedMetersPerSecond",
    "canonicalGuidance?.observation.courseDegrees",
    "guidance.projection.remainingMeters",
    "guidance.projection.remainingSeconds",
    "guidance.projection.eta",
    "canonicalGuidance?.nextInstruction",
    "instruction.triggerDistanceMeters",
    "guidance.projection.distanceAlongMeters",
    "HereLatLng($0.liveCoordinate.lat, $0.liveCoordinate.lng)",
    "firstPerson: guidance != nil",
    "zoom: guidance == nil ? 7 : 16",
    ".eusoRoute(",
    "GUIDANCE PAUSED · SOURCE NOT RELEASED",
    "GUIDANCE PAUSED · POSITION STALE",
    "OFF ROUTE · VERIFIED REROUTE REQUIRED",
    "LIVE POSITION PENDING",
  ],
  "server-verifiable en-route guidance",
);

assert.ok(
  !source.includes("HereCurrentLocationChip()") &&
    !source.includes("HereTypicalSpeedChip()"),
  "client-local location and traffic estimates must not masquerade as canonical execution state",
);
assert.ok(
  !source.includes('Text("LIMIT")') && !source.includes("speedLimit"),
  "035 must not fabricate or placeholder a speed limit absent from the execution contract",
);
assert.ok(
  !source.includes("exitChip"),
  "035 must not invent an exit identifier absent from the execution contract",
);

const refreshStart = source.indexOf("private func refreshCanonicalExecution(");
const refreshEnd = source.indexOf(
  "private static func distanceDisplay(",
  refreshStart,
);
assert.ok(
  refreshStart >= 0 && refreshEnd > refreshStart,
  "execution refresh boundaries must exist",
);
const refresh = source.slice(refreshStart, refreshEnd);
assert.ok(
  !/\b(lat|lng|coordinate|progress|speed|course|eta)\s*:/.test(refresh),
  "execution refresh must send no client coordinate, progress, speed, course, or ETA claim",
);
assert.ok(
  refresh.includes("canonicalExecutionState = nil") &&
    refresh.includes("GUIDANCE PAUSED · VERIFICATION UNAVAILABLE"),
  "network or identity failures must clear accepted guidance instead of retaining last-known claims",
);

console.log("iOS en-route canonical execution guidance: PASS");
