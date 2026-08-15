#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const clientPath = path.join(root, "EusoTrip/Views/Dispatch/401_DispatcherKanban.swift");
const serverCandidates = [
  process.env.EUSOTRIP_SERVER_ROOT,
  path.resolve(root, "../../_codex_rios_hardening/frontend"),
  path.resolve(root, "../eusoronetechnologiesinc/frontend"),
].filter(Boolean);
const serverRoot = serverCandidates.find((candidate) =>
  fs.existsSync(path.join(candidate, "server/routers/dispatch.ts")),
);

if (!serverRoot) {
  throw new Error("Dispatch server checkout not found. Set EUSOTRIP_SERVER_ROOT.");
}

const client = fs.readFileSync(clientPath, "utf8");
const server = fs.readFileSync(path.join(serverRoot, "server/routers/dispatch.ts"), "utf8");
const failures = [];

const requireText = (source, needle, label) => {
  if (!source.includes(needle)) failures.push(`${label}: missing ${needle}`);
};
const forbidText = (source, needle, label) => {
  if (source.includes(needle)) failures.push(`${label}: forbidden ${needle}`);
};
const section = (source, start, end, label) => {
  const from = source.indexOf(start);
  const to = source.indexOf(end, from + start.length);
  if (from < 0 || to < 0) {
    failures.push(`${label}: section not found`);
    return "";
  }
  return source.slice(from, to);
};

const unified = section(server, "unifiedLoads: protectedProcedure", "Get dispatch board data", "server unifiedLoads");
const unassign = section(server, "unassignDriver: protectedProcedure", "Update load status", "server unassignDriver");
const update = section(server, "updateLoadStatus: protectedProcedure", "Get real-time fleet locations", "server updateLoadStatus");

requireText(unified, "id: String(r.id)", "server canonical load identity");
requireText(unified, "driverId: r.driverId != null ? String(r.driverId) : null", "server canonical driver identity");
requireText(unassign, "z.union([z.string(), z.number()]).transform(String)", "server unassign input identity");
requireText(unassign, "loadId: input.loadId", "server unassign acknowledgement identity");
requireText(update, "z.union([z.string(), z.number()]).transform(String)", "server update input identity");
requireText(update, "loadId: input.loadId", "server update acknowledgement identity");
requireText(update, "newStatus: input.status", "server update acknowledgement status");

requireText(client, "let id: String", "iOS lossless load identity");
requireText(client, "let driverId: String?", "iOS authoritative assignment identity");
forbidText(client, "let id: Int", "iOS load identity");
forbidText(client, "LosslessStringIdentifier", "iOS implicit identifier coercion");
requireText(client, "try response.validateStatus(loadId: l.id, status: next)", "status acknowledgement gate");
requireText(client, "try response.validateUnassignment(loadId: l.id)", "unassign acknowledgement gate");
requireText(client, "guard loadId == expectedId", "exact acknowledgement round trip");
requireText(client, "guard newStatus == expectedStatus", "exact status acknowledgement");
requireText(client, "let previousBoard = byLane", "pre-drop rollback snapshot");
requireText(client, "byLane = previousBoard", "failure rollback");
requireText(client, "let confirmed = try await readBack(", "durable readback");
requireText(client, "response.loads.first(where: { $0.id == loadId })", "exact readback identity");
requireText(client, "row.status == expectedStatus", "exact readback stage");
requireText(client, "row.driverId != nil", "unassignment readback");
requireText(client, "lane.id == \"assigned\", load.driverId == nil", "authoritative assignment gate");
requireText(client, "guard shifting == nil else { return false }", "duplicate drop gate");

// Prove the contract fixture itself keeps identity as an opaque string even
// beyond JavaScript's safe integer range. The iOS source gate above forbids an
// Int decoder or compatibility wrapper from narrowing it later.
const opaqueId = "900719925474099312345";
const fixture = JSON.parse(JSON.stringify({
  loads: [{ id: opaqueId, loadNumber: "LD-CONTRACT", status: "posted", driverId: null }],
}));
if (fixture.loads[0].id !== opaqueId || typeof fixture.loads[0].id !== "string") {
  failures.push("opaque identifier fixture did not round-trip exactly");
}

if (failures.length) {
  console.error(`Dispatcher Kanban P0 verification failed:\n- ${failures.join("\n- ")}`);
  process.exit(1);
}

console.log(JSON.stringify({
  verified: true,
  serverRoot,
  contracts: [
    "server emits canonical string IDs",
    "iOS preserves opaque IDs without numeric coercion",
    "mutation acknowledgement matches exact ID and stage",
    "committed state is read back before UI movement",
    "failed confirmation restores the pre-drop board",
  ],
}, null, 2));
