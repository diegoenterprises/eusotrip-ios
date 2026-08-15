#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const source = fs.readFileSync(
  path.join(root, "EusoTrip/Views/Shipper/204_ShipperPostLoad.swift"),
  "utf8",
);
const sharedDraft = fs.readFileSync(
  path.join(root, "EusoTrip/Views/Shipper/PostLoadDraft.swift"),
  "utf8",
);
const stepOne = fs.readFileSync(
  path.join(root, "EusoTrip/Views/Shipper/250_PostLoadStep1Lane.swift"),
  "utf8",
);
const draftsList = fs.readFileSync(
  path.join(root, "EusoTrip/Views/Shipper/412_DraftsList.swift"),
  "utf8",
);
const serverCandidates = [
  process.env.EUSOTRIP_SERVER_ROOT,
  path.resolve(root, "../../_codex_rios_hardening/frontend"),
  path.resolve(root, "../eusoronetechnologiesinc/frontend"),
].filter(Boolean);
const serverRoot = serverCandidates.find((candidate) =>
  fs.existsSync(path.join(candidate, "server/routers/loads.ts")),
);
if (!serverRoot) throw new Error("Loads server checkout not found. Set EUSOTRIP_SERVER_ROOT.");
const loadsRouter = fs.readFileSync(path.join(serverRoot, "server/routers/loads.ts"), "utf8");

const requireText = (needle, label) => {
  if (!source.includes(needle)) throw new Error(`${label}: missing ${needle}`);
};

const section = (start, end, label) => {
  const startIndex = source.indexOf(start);
  const endIndex = source.indexOf(end, startIndex + start.length);
  if (startIndex < 0 || endIndex < 0) throw new Error(`${label}: section not found`);
  return source.slice(startIndex, endIndex);
};

const requireIn = (target, needle, label) => {
  if (!target.includes(needle)) throw new Error(`${label}: missing ${needle}`);
};

const forbidIn = (target, needle, label) => {
  if (target.includes(needle)) throw new Error(`${label}: forbidden ${needle}`);
};

requireText("private struct PostLoadDraftSnapshot: Codable, Sendable", "draft snapshot concurrency");
requireText("draftPersistWork?.cancel()", "debounced draft persistence");
requireText("pickupDate = max(restored, pickupLowerBound)", "stale pickup-date recovery");
requireText("in: pickupLowerBound...", "stable pickup-date range");
requireText("private enum PostLoadDraftPersistence", "shared draft storage ordering");
requireText("\"\\(draftKey).clearedAt\"", "persisted draft-clear tombstone");

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
requireIn(persistDraft, "snap.savedAt > PostLoadDraftPersistence.clearedAt(for: key)", "stale write rejection");
requireIn(persistDraft, "snap.savedAt <= PostLoadDraftPersistence.clearedAt(for: key)", "post-write clear reconciliation");

const localHydration = section("private func hydrateDraftIfPresent()", "private func clearDraft()", "local draft hydration");
requireIn(localHydration, "draftHydrationGeneration &+= 1", "local stale-result generation");
requireIn(localHydration, "Task.detached(priority: .utility)", "local off-main storage read");
requireIn(localHydration, "generation == draftHydrationGeneration", "local stale-result rejection");
requireIn(localHydration, "private func cancelDraftHydration()", "local cancellation");
forbidIn(localHydration, "await draftHydrationTask", "local self-await prevention");
requireIn(source, ".allowsHitTesting(!isHydratingStoredDraft)", "local hydration edit gate");
requireIn(source, "cancelDraftHydration()\n            NotificationCenter.default.post", "back cancellation");
requireIn(source, "nonisolated private static func readStoredDraft", "off-main local decoder");
requireIn(source, "draft.savedAt > clearedAt", "tombstone-aware draft hydration");
requireIn(source, "DraftSummary: Codable, Sendable", "entry summary sendability");
requireIn(source, "summary.savedAt > clearedAt", "tombstone-aware draft list");
requireIn(source, "private func closeTapped() {\n        clearDraft()", "explicit discard behavior");
requireIn(source, "PostLoadDraftPersistence.clear(draftStorageKey)\n                        entryChoice = .fresh", "new-load stale write barrier");

requireIn(sharedDraft, "private var serverDraftHydrationTask: Task<ServerDraft, Error>?", "server hydration ownership");
requireIn(sharedDraft, "serverDraftHydrationId == canonicalId", "same-id request coalescing");
requireIn(sharedDraft, "generation == serverDraftHydrationGeneration", "server stale-result rejection");
requireIn(sharedDraft, "guard row.id == canonicalId", "server draft identity validation");
requireIn(sharedDraft, "try validateSupportedValues(in: row)", "atomic server draft compatibility gate");
requireIn(sharedDraft, "func cancelServerDraftHydration(for draftId: String? = nil)", "server hydration cancellation");
requireIn(sharedDraft, "let row = try await request.value", "single request await");
forbidIn(sharedDraft, "await serverDraftHydrationTask", "server self-await prevention");

requireIn(stepOne, ".task(id: resumeDraftId ?? \"\")", "resume identity task");
requireIn(stepOne, "draft.cancelServerDraftHydration(for: resumeDraftId)", "step dismissal cancellation");
requireIn(stepOne, ".disabled(!canAdvance)", "unresolved hydration navigation gate");
requireIn(stepOne, "draft.hydratedDraftId == resumeDraftId.trimmingCharacters", "exact resumed identity gate");

requireIn(draftsList, "private struct DraftLocation: Decodable", "JSON location contract");
requireIn(draftsList, "let origin: DraftLocation?", "structured origin decoder");
requireIn(draftsList, "let destination: DraftLocation?", "structured destination decoder");
requireIn(draftsList, "userInfo: [\"screenId\": \"250\", \"draftId\": row.id]", "exact resume identity handoff");
requireIn(draftsList, "let acknowledgement: Out", "delete acknowledgement retention");
requireIn(draftsList, "!refreshed.contains(where: { $0.id == id })", "delete readback");

requireIn(loadsRouter, "id: `load_${l.id}`", "server list draft string identity");
requireIn(loadsRouter, "origin: l.pickupLocation", "server list draft JSON origin");
requireIn(loadsRouter, "destination: l.deliveryLocation", "server list draft JSON destination");
requireIn(loadsRouter, "id: `load_${draft.id}`", "server get draft string identity");
requireIn(loadsRouter, "origin: location(draft.pickupLocation)", "server get draft structured origin");

console.log(JSON.stringify({
  verified: true,
  contracts: [
    "sendable draft snapshot",
    "debounced off-main persistence",
    "clear-tombstone stale-write rejection",
    "cancellable generation-scoped local hydration",
    "coalesced exact-ID server hydration",
    "structured draft-list locations",
    "resume/back navigation coherence",
    "stable pickup date restoration",
  ],
}, null, 2));
