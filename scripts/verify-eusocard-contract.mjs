#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const api = readFileSync(resolve(root, "EusoTrip/Services/EusoTripAPI.swift"), "utf8");
const panel = readFileSync(resolve(root, "EusoTrip/Views/Components/EusoCardIssuePanel.swift"), "utf8");
const failures = [];

function requireSource(condition, message) {
  if (!condition) failures.push(message);
}

requireSource(api.includes('queryNoInput("wallet.getEusoCardStatus")'), "missing status query");
requireSource(api.includes('mutationNoInput("wallet.createEusoCardOnboardingLink")'), "missing onboarding mutation");
requireSource(api.includes('"wallet.createEusoCard"'), "missing card creation mutation");
requireSource(api.includes("let idempotencyKey: String"), "creation request does not carry a required idempotency key");
requireSource(panel.includes("issuanceIdempotencyKey"), "panel does not retain one issuance idempotency key");
requireSource(panel.includes("idempotencyKey: issuanceIdempotencyKey"), "panel does not send its retained issuance key");
requireSource(panel.includes('guard let cents else { return "Unavailable" }'), "panel invents an absent Treasury balance");
requireSource(!panel.includes('if status.canCreate { return "READY" }'), "panel presents unverified setup as READY");
requireSource(panel.includes('case "setup_required": return "SETUP REQUIRED"'), "panel lacks the setup-required state");
requireSource(!panel.includes("API method cannot be found"), "panel contains an API-method fallback");
requireSource(!panel.match(/\b(DRIVER|DISPATCH|SHIPPER|BROKER)\b.*qualif/i), "panel duplicates server role eligibility");

if (failures.length) {
  for (const failure of failures) console.error(`FAIL ${failure}`);
  process.exit(1);
}
console.log("PASS iOS EusoCard procedure, idempotency, eligibility, and truthful-state contract");
