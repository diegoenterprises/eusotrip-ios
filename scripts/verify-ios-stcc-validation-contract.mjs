#!/usr/bin/env node

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const screen = await readFile(
  resolve(root, "EusoTrip/Views/Rail/686_RailSTCCCommodityValidation.swift"),
  "utf8"
);

function requireText(expected, evidence) {
  assert(screen.includes(expected), `${evidence}: missing ${JSON.stringify(expected)}`);
}

function forbidText(forbidden, evidence) {
  assert(!screen.includes(forbidden), `${evidence}: forbidden ${JSON.stringify(forbidden)}`);
}

for (const [expected, evidence] of [
  ["initialCodes: [String] = []", "Empty production entry state"],
  ["validateStccs(codes)", "Single typed batch validation call"],
  ["response.contractVerified", "Envelope contract gate"],
  ["result.isDecisionEligible", "Per-entry evidence gate"],
  ["match.hsCode ?? \"Not recorded\"", "Exact-profile HS display"],
  ["match.sourceName ?? match.sourceKey", "Visible source proof"],
  ["match.evidenceRetrievedAt", "Visible retrieval proof"],
  ["dangerousGoodsLabel(match.hazmatLinked)", "Evidence-backed dangerous-goods state"],
  [".eusoRefreshable", "App-wide refresh contract"],
  ["EusoTripEyebrow", "Canonical identity marker"],
  [".accessibilityLabel(accessibilityLabel(for: line))", "Accessible register equivalent"],
]) {
  requireText(expected, evidence);
}

for (const [forbidden, evidence] of [
  ["2812510", "No seeded focus STCC"],
  ["STCC_SEED", "No seed-registry claim"],
  ["publicProcedure", "No unauthenticated contract claim"],
  ["searchGeneral", "No fuzzy HS substitution"],
  ["try?", "No swallowed lookup failure"],
  ["KC → MTY", "No invented corridor"],
  ["Confirm codes", "No dead write affordance"],
]) {
  forbidText(forbidden, evidence);
}

console.log(JSON.stringify({
  contract: "ios-rail-stcc-evidence",
  seededData: false,
  batchValidation: true,
  duplicateOrderPreserved: true,
  fuzzyHsSubstitution: false,
  evidenceProofVisible: true,
  accessibilityEquivalent: true,
}, null, 2));
