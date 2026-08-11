#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const source = fs.readFileSync(
  path.join(root, "EusoTrip/Views/Shipper/204_ShipperPostLoad.swift"),
  "utf8",
);

const requireText = (needle, label) => {
  if (!source.includes(needle)) throw new Error(`${label}: missing ${needle}`);
};

const section = (start, end, label) => {
  const startIndex = source.indexOf(start);
  const endIndex = source.indexOf(end, startIndex + start.length);
  if (startIndex < 0 || endIndex < 0) throw new Error(`${label}: section not found`);
  return source.slice(startIndex, endIndex);
};

requireText("private struct PostLoadDraftSnapshot: Codable, Sendable", "draft snapshot concurrency");
requireText("draftPersistWork?.cancel()", "debounced draft persistence");
requireText("pickupDate = max(restored, pickupLowerBound)", "stale pickup-date recovery");
requireText("in: pickupLowerBound...", "stable pickup-date range");

const clearDraft = section("private func clearDraft()", "// MARK: - TopBar", "clear draft");
if (clearDraft.includes("synchronize()")) {
  throw new Error("clear draft: synchronous iCloud synchronization can stall navigation");
}

const freshEntry = section("onFresh: {", "entryChoice = .fresh", "new-load entry");
if (freshEntry.includes("synchronize()")) {
  throw new Error("new-load entry: synchronous iCloud synchronization can stall navigation");
}

const syncCalls = source.match(/NSUbiquitousKeyValueStore\.default\.synchronize\(\)/g) ?? [];
if (syncCalls.length !== 1) {
  throw new Error(`draft persistence: expected one off-main synchronize call, found ${syncCalls.length}`);
}

const persistDraft = section("private func persistDraft()", "private func hydrateDraftIfPresent()", "persist draft");
const queueIndex = persistDraft.indexOf("DispatchQueue.global(qos: .utility).async");
const syncIndex = persistDraft.indexOf("NSUbiquitousKeyValueStore.default.synchronize()");
if (queueIndex < 0 || syncIndex < queueIndex) {
  throw new Error("draft persistence: iCloud synchronization is not inside the utility queue");
}

console.log(JSON.stringify({
  verified: true,
  contracts: [
    "sendable draft snapshot",
    "debounced off-main persistence",
    "nonblocking resume and new-load transitions",
    "stable pickup date restoration",
  ],
}, null, 2));
