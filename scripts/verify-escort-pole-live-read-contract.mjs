import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const iosRoot = resolve(import.meta.dirname, "..");
const backendRoot = process.env.EUSOTRIP_BACKEND_ROOT
  ? resolve(process.env.EUSOTRIP_BACKEND_ROOT)
  : "/Users/diegousoro/_codex_rios_hardening/frontend";

const iosPath = resolve(
  iosRoot,
  "EusoTrip/Views/Escort/ES16_ActiveTripConsole.swift",
);
const heightPolePath = resolve(
  iosRoot,
  "EusoTrip/Views/Escort/ES02_HeightPole.swift",
);
const routerPath = resolve(backendRoot, "server/routers/escorts.ts");
const servicePath = resolve(backendRoot, "server/services/bridgeClearance.ts");

for (const path of [iosPath, heightPolePath, routerPath, servicePath]) {
  if (!existsSync(path)) throw new Error(`Required source is missing: ${path}`);
}

const ios = readFileSync(iosPath, "utf8");
const heightPole = readFileSync(heightPolePath, "utf8");
const router = readFileSync(routerPath, "utf8");
const service = readFileSync(servicePath, "utf8");
const bridgeRead = ios.slice(
  ios.indexOf("private func readBridgeCoverage"),
  ios.indexOf("private func apply", ios.indexOf("private func readBridgeCoverage")),
);

const checks = [
  [
    router.includes("getPoleConfig: protectedProcedure") &&
      router.includes("resolveEscortUserId(ctx.user)") &&
      router.includes("escortAssignments.poleConfig"),
    "backend exposes an assignment-owned pole configuration read",
  ],
  [
    bridgeRead.includes('"escorts.getPoleConfig"') &&
      !bridgeRead.includes("try? await EusoTripAPI.shared.query") &&
      bridgeRead.includes('return (nil, "POLE STATUS UNAVAILABLE")') &&
      bridgeRead.includes('return (nil, "POLE NOT ARMED · ES-02")'),
    "native console distinguishes unavailable pole truth from a known unarmed pole",
  ],
  [
    router.includes("bridgesChecked: result.bridgesChecked") &&
      router.includes("datasetRows: dataset.datasetRows") &&
      router.includes("coverageRadiusMi: input.radiusMi") &&
      service.includes('coverage: "partial"'),
    "low-clearance response carries decodable coverage and honest dataset provenance",
  ],
  [
    bridgeRead.includes("assignmentId: assignmentId") &&
      !bridgeRead.includes("loadId: loadId") &&
      router.includes("assignmentId: z.coerce.number().int().positive()") &&
      router.includes("escortAssignments.loadId") &&
      router.includes("escortAssignments.escortUserId"),
    "native and server clearance reads bind through the authenticated assignment",
  ],
  [
    heightPole.includes("requestKey: requestKey") &&
      heightPole.includes("UserDefaults.standard.set(requestKey") &&
      heightPole.includes("UserDefaults.standard.removeObject(forKey: storageKey)") &&
      router.includes("db.transaction(async tx =>") &&
      router.includes("enqueueAuditEvent(tx") &&
      router.includes('eventType: "escort_pole_config_set"'),
    "height-pole writes retain replay identity and commit durable audit intent atomically",
  ],
  [
    heightPole.includes("required = try c.decode(Bool.self") &&
      !heightPole.includes("required = (try?") &&
      router.includes("clearances: null") &&
      service.includes("persistChecks = false"),
    "clearance refresh uses a stable truth shape and performs no hidden evidence write",
  ],
];

const failures = checks.filter(([passed]) => !passed).map(([, message]) => message);
if (failures.length) {
  for (const failure of failures) console.error(`FAIL: ${failure}`);
  process.exit(1);
}
for (const [, message] of checks) console.log(`PASS: ${message}`);
