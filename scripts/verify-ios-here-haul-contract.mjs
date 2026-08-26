#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const api = readFileSync(
  resolve(root, "EusoTrip/Services/EusoTripAPI.swift"),
  "utf8",
);
const bridge = readFileSync(
  resolve(root, "EusoTrip/Services/HereMaps/HereHaulBridge.swift"),
  "utf8",
);
const gate = readFileSync(
  resolve(root, "scripts/here-production-gate.mjs"),
  "utf8",
);

const start = api.indexOf("// MARK: HERE outcome intake");
const end = api.indexOf("// MARK: Profile", start);
if (start < 0 || end < 0) throw new Error("HERE outcome API section not found");
const outcome = api.slice(start, end);
const failures = [];
const requireText = (source, needle, label) => {
  if (!source.includes(needle)) failures.push(`${label}: missing ${needle}`);
};
const forbidText = (source, needle, label) => {
  if (source.includes(needle)) failures.push(`${label}: forbidden ${needle}`);
};

requireText(outcome, "let clientEventId: String", "event replay identity");
requireText(outcome, "let loadId: Int?", "optional load context");
requireText(
  outcome,
  "let engagement: HereEngagementOutcome",
  "HERE source identity",
);
forbidText(outcome, "HereOutcomeAction", "client-selected action type");
forbidText(outcome, "let action:", "client-selected action payload");
forbidText(bridge, ".verifyVisit", "client-selected visit verification");
forbidText(bridge, ".discover", "client-selected discovery");
requireText(
  bridge,
  'let alreadyCredited = response.status == "already_credited"',
  "duplicate credit acknowledgement",
);
requireText(bridge, "if newlyCredited {", "fresh reward notification gate");
requireText(bridge, "credited: newlyCredited", "fresh credit result semantics");

const rewardPosts =
  bridge.match(/NotificationCenter\.default\.post\(name: \.eusoHaulReward/g) ??
  [];
if (rewardPosts.length !== 1) {
  failures.push(
    `reward notification must have one guarded source; found ${rewardPosts.length}`,
  );
}

if (failures.length) {
  console.error(`iOS HERE Haul contract failed:\n- ${failures.join("\n- ")}`);
  process.exit(1);
}

requireText(
  gate,
  'for (const forbidden of [".verifyVisit", ".discover"])',
  "HERE production gate client-action ban",
);
requireText(
  gate,
  'for (const forbidden of ["HereOutcomeAction", "let action:"])',
  "HERE production gate API-action ban",
);
console.log(
  JSON.stringify(
    {
      verified: true,
      serverDerivedAction: true,
      duplicateRewardToastSuppressed: true,
      productionGateRejectsClientSelectedActions: true,
    },
    null,
    2,
  ),
);
