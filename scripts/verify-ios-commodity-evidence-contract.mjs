#!/usr/bin/env node

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const api = await readFile(resolve(root, "EusoTrip/Services/EusoTripAPI.swift"), "utf8");
const postLoad = await readFile(
  resolve(root, "EusoTrip/Views/Shipper/204_ShipperPostLoad.swift"),
  "utf8"
);

function requireText(source, expected, evidence) {
  assert(source.includes(expected), `${evidence}: missing ${JSON.stringify(expected)}`);
}

function forbidText(source, forbidden, evidence) {
  assert(!source.includes(forbidden), `${evidence}: forbidden ${JSON.stringify(forbidden)}`);
}

for (const field of [
  "decisionEligible",
  "tracked",
  "trackingState",
  "freshnessState",
  "profileVersion",
  "evidenceId",
  "evidenceStatus",
  "evidenceObservedAt",
  "evidenceRetrievedAt",
  "evidenceValidUntil",
  "evidenceContentHash",
  "sourceKey",
  "sourceName",
  "sourceClass",
  "sourceRefreshIntervalHours",
  "sourceLastSuccessfulSyncAt",
  "sourceUrl",
  "hsCode",
  "stccCode",
  "unNumber",
  "casNumber",
  "packingGroup",
  "hazmatLinked",
]) {
  requireText(api, `let ${field}:`, `Commodity evidence DTO ${field}`);
}

requireText(api, "decisionEligible = try values.decodeIfPresent(Bool.self, forKey: .decisionEligible) ?? false", "Missing row eligibility fails closed");
requireText(api, "tracked = try values.decodeIfPresent(Bool.self, forKey: .tracked) ?? false", "Missing tracking state fails closed");
requireText(api, "let contractVerified: Bool", "Response contract state");
requireText(api, "guard contractVerified, tracked, decisionEligible else { return [] }", "Response-level selection gate");
requireText(api, '?? "contract_unverified"', "Legacy response state");
requireText(api, "struct StccBatchValidationResponse", "Typed STCC batch response");
requireText(api, "results.allSatisfy(\\.contractVerified)", "Every STCC row contract is verified");
requireText(api, "func validateStccs(_ stccs: [String])", "Typed STCC batch API");
requireText(api, '"commodity.validateStccBatch"', "Canonical batch procedure");
forbidText(api, "backed by seed commodity tables", "No seed-backed client contract");

requireText(postLoad, "@State private var commodityResponseContractVerified = false", "Screen response-contract state");
requireText(postLoad, "commodityResponseContractVerified && hit.isSelectable", "Row and response selection gate");
requireText(postLoad, "self.commodityResponseContractVerified = resp.contractVerified", "Response gate readback");
requireText(postLoad, "guard isCommodityHitSelectable(hit) else", "Selection mutation guard");
requireText(postLoad, "commoditySearchTask?.cancel()", "Search cancellation");
requireText(postLoad, "Entered by shipper · no evidence-backed product profile selected", "Manual-entry provenance");
requireText(postLoad, "commodityEvidenceSubtitle", "Visible source and freshness proof");
requireText(postLoad, "commoditySearchHits = []", "Evidence-state reset");

console.log(JSON.stringify({
  contract: "ios-commodity-evidence",
  responseContractRequired: true,
  rowEligibilityRequired: true,
  unknownDefaultsToSuccess: false,
  staleSelectionBlocked: true,
  manualEntryProvenanceVisible: true,
  resetClearsEvidenceState: true,
}, null, 2));
