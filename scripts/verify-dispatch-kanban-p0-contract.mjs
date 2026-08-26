#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const clientPath = path.join(
  root,
  "EusoTrip/Views/Dispatch/401_DispatcherKanban.swift",
);
const liveOpsPath = path.join(
  root,
  "EusoTrip/Views/Dispatch/Dpch714_DispatchTrio.swift",
);
const detailPath = path.join(
  root,
  "EusoTrip/Views/Dispatch/Dpch820_DispatcherM04KanbanQuintet.swift",
);
const realtimePath = path.join(root, "EusoTrip/Services/RealtimeService.swift");
const serverCandidates = [
  process.env.EUSOTRIP_SERVER_ROOT,
  path.resolve(root, "../../_codex_rios_hardening/frontend"),
  path.resolve(root, "../eusoronetechnologiesinc/frontend"),
].filter(Boolean);
const serverRoot = serverCandidates.find((candidate) =>
  fs.existsSync(path.join(candidate, "server/routers/dispatch.ts")),
);

if (!serverRoot) {
  throw new Error(
    "Dispatch server checkout not found. Set EUSOTRIP_SERVER_ROOT.",
  );
}

const client = fs.readFileSync(clientPath, "utf8");
const liveOps = fs.readFileSync(liveOpsPath, "utf8");
const detail = fs.readFileSync(detailPath, "utf8");
const realtime = fs.readFileSync(realtimePath, "utf8");
const server = fs.readFileSync(
  path.join(serverRoot, "server/routers/dispatch.ts"),
  "utf8",
);
const websocket = fs.readFileSync(
  path.join(serverRoot, "server/_core/websocket.ts"),
  "utf8",
);
const socketService = fs.readFileSync(
  path.join(serverRoot, "server/services/socketService.ts"),
  "utf8",
);
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

const unified = section(
  server,
  "unifiedLoads: protectedProcedure",
  "Get dispatch board data",
  "server unifiedLoads",
);
const unassign = section(
  server,
  "unassignDriver: protectedProcedure",
  "Update load status",
  "server unassignDriver",
);
const update = section(
  server,
  "updateLoadStatus: protectedProcedure",
  "Get real-time fleet locations",
  "server updateLoadStatus",
);
const statusFanout = section(
  websocket,
  "export function emitLoadStatusChange(a:",
  "Emit new bid received event",
  "server load-status fan-out",
);
const loadStateFanout = section(
  socketService,
  "export function emitLoadStateChange(event:",
  "Broadcast a financial timer",
  "server Socket.IO load-state fan-out",
);

requireText(unified, "id: String(r.id)", "server canonical load identity");
requireText(
  unified,
  "driverId: r.driverId != null ? String(r.driverId) : null",
  "server canonical driver identity",
);
requireText(
  unified,
  'consistency: z.enum(["eventual", "strong"])',
  "server read consistency contract",
);
requireText(
  unified,
  'input.consistency === "strong" ? await getDb() : await getReadDb()',
  "server primary readback",
);
requireText(
  unified,
  "version: Number(r.version) || 1",
  "server committed revision readback",
);
requireText(
  unified,
  "plannerStatus: r.plannerStatus || null",
  "server planner readback",
);
requireText(
  unassign,
  "loadId: canonicalDispatchLoadIdSchema",
  "server unassign input identity",
);
requireText(
  unassign,
  "loadId: input.loadId",
  "server unassign acknowledgement identity",
);
requireText(
  unassign,
  "await enqueueAuditEvent(tx",
  "server unassign durable audit intent",
);
requireText(
  unassign,
  "version: result.version",
  "server unassign revision acknowledgement",
);
requireText(
  update,
  ".input(dispatchStatusUpdateSchema)",
  "server update input contract",
);
requireText(
  update,
  "loadId: input.loadId",
  "server update acknowledgement identity",
);
requireText(
  update,
  "newStatus: input.status",
  "server update acknowledgement status",
);
requireText(
  update,
  "String(locked.status) !== input.expectedStatus",
  "server optimistic source-stage gate",
);
requireText(
  update,
  "(locked.version ?? 1) !== input.expectedVersion",
  "server optimistic source-revision gate",
);
requireText(
  update,
  "assertDispatchKanbanMove",
  "server one-stage lifecycle gate",
);
requireText(
  update,
  "await enqueueAuditEvent(tx",
  "server status durable audit intent",
);
requireText(
  update,
  "version: commit.version",
  "server status revision acknowledgement",
);
requireText(unassign, "emitLoadStatusChange({", "server unassign fan-out call");
requireText(update, "emitLoadStatusChange({", "server status fan-out call");

const statusReachesDispatcherBoard =
  statusFanout.includes("sioDispatchBoardUpdate") ||
  update.includes("emitDispatchEvent(") ||
  update.includes("emitDispatchBoardUpdate(") ||
  (loadStateFanout.includes('io.to("role:dispatch").emit("load:stateChange"') &&
    realtime.includes('case "load:stateChange"'));
if (!statusReachesDispatcherBoard) {
  failures.push(
    "realtime dispatcher board return path: the status mutation bridges only to load:stateChange; " +
      "that event is neither emitted to role:dispatch nor routed by RealtimeService to eusoDispatchBoardUpdated",
  );
}

requireText(client, "let id: String", "iOS lossless load identity");
requireText(
  client,
  "let driverId: String?",
  "iOS authoritative assignment identity",
);
requireText(client, "let version: Int", "iOS committed revision identity");
forbidText(client, "let id: Int", "iOS load identity");
forbidText(
  client,
  "LosslessStringIdentifier",
  "iOS implicit identifier coercion",
);
requireText(
  client,
  "let committedVersion = try response.validateStatus(",
  "status acknowledgement gate",
);
requireText(
  client,
  "try response.validateUnassignment(loadId: l.id)",
  "unassign acknowledgement gate",
);
requireText(
  client,
  "guard loadId == expectedId",
  "exact acknowledgement round trip",
);
requireText(
  client,
  "guard newStatus == expectedStatus",
  "exact status acknowledgement",
);
requireText(client, "let previousBoard = byLane", "pre-drop rollback snapshot");
requireText(client, "byLane = previousBoard", "failure rollback");
requireText(client, "let confirmed = try await readBack(", "durable readback");
requireText(client, 'source: "dispatcher_kanban"', "iOS mutation source");
requireText(client, "expectedStatus: l.status", "iOS optimistic source stage");
requireText(
  client,
  "expectedVersion: l.version",
  "iOS optimistic source revision",
);
requireText(
  client,
  'next == "delivered" && l.plannerStatus != nil',
  "iOS expected planner transition",
);
requireText(
  client,
  "idempotencyKey: UUID().uuidString.lowercased()",
  "iOS mutation idempotency",
);
requireText(
  client,
  'fetchBoard(consistency: "strong")',
  "iOS primary readback request",
);
requireText(
  client,
  "response.loads.first(where: { $0.id == loadId })",
  "exact readback identity",
);
requireText(client, "row.status == expectedStatus", "exact readback stage");
requireText(
  client,
  "row.version == expectedVersion",
  "exact readback revision",
);
requireText(client, "row.driverId != nil", "unassignment readback");
requireText(client, "requiresNoPlanner: true", "planner clear readback");
requireText(
  client,
  'lane.id == "assigned", load.driverId == nil',
  "authoritative assignment gate",
);
requireText(
  client,
  "guard shifting == nil else { return false }",
  "duplicate drop gate",
);
forbidText(
  client,
  'laneId(for: load.status) ?? "tender"',
  "unknown status lane fallback",
);
requireText(
  client,
  "dynamicTypeSize.isAccessibilitySize ? 1 : 2",
  "accessibility-size single-column layout",
);
requireText(
  client,
  ".accessibilityAction { handleCardTap",
  "VoiceOver default card action",
);
requireText(
  client,
  ".accessibilityAction(named:",
  "VoiceOver named move action",
);
requireText(client, "if reduceMotion", "reduced-motion drag feedback");

requireText(
  liveOps,
  'id = Self.flexString(c, .id) ?? ""',
  "Live Ops flexible load identity",
);
requireText(
  liveOps,
  "c.decode(Int.self, forKey: key)",
  "Live Ops numeric identity compatibility",
);
forbidText(liveOps, "let id: Int", "Live Ops narrowed load identity");

requireText(detail, "let id: String?", "M04 canonical getById identity");
requireText(detail, "if loading {", "M04 loading return state");
requireText(detail, "else if let loadError", "M04 error return state");
requireText(detail, "loadError = error.eusoUserCopy", "M04 surfaced API error");
requireText(
  detail,
  "if error is CancellationError",
  "M04 cancellation is not presented as a failed read",
);
forbidText(
  detail,
  "catch { /* read-only screen, tolerate */ }",
  "M04 swallowed read failure",
);

// Prove the contract fixture itself keeps identity as an opaque string even
// beyond JavaScript's safe integer range. The iOS source gate above forbids an
// Int decoder or compatibility wrapper from narrowing it later.
const opaqueId = "900719925474099312345";
const fixture = JSON.parse(
  JSON.stringify({
    loads: [
      {
        id: opaqueId,
        loadNumber: "LD-CONTRACT",
        status: "posted",
        driverId: null,
      },
    ],
  }),
);
if (
  fixture.loads[0].id !== opaqueId ||
  typeof fixture.loads[0].id !== "string"
) {
  failures.push("opaque identifier fixture did not round-trip exactly");
}

const parser = spawnSync(
  "swift",
  [path.join(root, "scripts/verify-dispatch-kanban-decoder.swift")],
  { encoding: "utf8" },
);
if (parser.status !== 0) {
  failures.push(
    `Swift decoder reproduction failed: ${(parser.stderr || parser.stdout).trim()}`,
  );
}

if (failures.length) {
  console.error(
    `Dispatcher Kanban P0 verification failed:\n- ${failures.join("\n- ")}`,
  );
  process.exit(1);
}

console.log(
  JSON.stringify(
    {
      verified: true,
      serverRoot,
      contracts: [
        "server emits canonical string IDs",
        "iOS preserves opaque IDs without numeric coercion",
        "Live Ops accepts the historical numeric ID payload without narrowing canonical string IDs",
        "mutation acknowledgement matches exact ID and stage",
        "committed primary revision is read back before UI movement",
        "planner state and durable audit intent commit with the stage",
        "failed confirmation restores the pre-drop board",
        "Kanban cards expose VoiceOver move actions and accessibility-size layout",
        "M04 Kanban details distinguish loading and failed reads from honest empty fields",
      ],
    },
    null,
    2,
  ),
);
