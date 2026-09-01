import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const iosRoot = resolve(import.meta.dirname, "..");
const backendRoot = process.env.EUSOTRIP_BACKEND_ROOT
  ? resolve(process.env.EUSOTRIP_BACKEND_ROOT)
  : "/Users/diegousoro/_codex_rios_hardening/frontend";

const files = {
  api: resolve(iosRoot, "EusoTrip/Services/EusoTripAPI.swift"),
  rail: resolve(iosRoot, "EusoTrip/Views/Rail/654_RailClaimWorkflow.swift"),
  vessel: resolve(iosRoot, "EusoTrip/Views/Vessel/808_VesselClaimWorkflow.swift"),
  router: resolve(backendRoot, "server/routers/freightClaims.ts"),
  web: resolve(backendRoot, "client/src/pages/FreightClaims.tsx"),
};

for (const [label, path] of Object.entries(files)) {
  if (!existsSync(path)) throw new Error(`${label} source is missing: ${path}`);
}

const source = Object.fromEntries(
  Object.entries(files).map(([label, path]) => [label, readFileSync(path, "utf8")])
);

const modes = [
  ["rail", source.rail],
  ["vessel", source.vessel],
];

const checks = [
  [
    source.router.includes("getClaimSpecialistCandidates: protectedProcedure") &&
      source.router.includes("specialty: claimAssignmentTypeSchema") &&
      source.router.includes("jurisdiction: claimAssignmentJurisdictionSchema.optional()") &&
      source.router.includes("requestedJurisdiction: jurisdiction") &&
      source.router.includes("input.requestedJurisdiction ?? await defaultClaimAssignmentJurisdiction(tx, claim, mode)"),
    "server derives an omitted specialist jurisdiction from the locked claim and mode",
  ],
  [
    source.router.includes("assignClaimSpecialist: protectedProcedure") &&
      source.router.includes("assignmentType: claimAssignmentTypeSchema") &&
      source.router.includes("db.transaction(tx => assignClaimSpecialistRecord(tx") &&
      source.router.includes("specialty: input.assignmentType") &&
      source.router.includes("assignmentType: input.assignmentType") &&
      source.router.includes("idempotent: outcome.idempotent"),
    "server atomically records and returns the requested specialist type with replay state",
  ],
  [
    source.api.includes("enum ClaimAssignmentType: String, CaseIterable, Identifiable, Codable, Hashable") &&
      ["investigator", "surveyor", "adjuster", "counsel"].every(value =>
        source.api.includes(`case ${value}`)
      ) &&
      source.api.includes("func getClaimSpecialistCandidates(") &&
      source.api.includes('"freightClaims.getClaimSpecialistCandidates"') &&
      source.api.includes("func assignClaimSpecialist(") &&
      source.api.includes('"freightClaims.assignClaimSpecialist"') &&
      source.api.includes("let assignmentType: ClaimAssignmentType"),
    "native API models and calls all four typed specialist responsibilities",
  ],
  [
    source.web.includes('(["investigator", "surveyor", "adjuster", "counsel"] as const)') &&
      source.web.includes("freightClaims.getClaimSpecialistCandidates.useQuery") &&
      source.web.includes("freightClaims.assignClaimSpecialist.useMutation") &&
      source.web.includes("result.assignmentType === input.assignmentType") &&
      source.web.includes("record.assignmentType === input.assignmentType"),
    "web lets the reviewer choose a responsibility and verifies acknowledgment plus readback",
  ],
  ...modes.flatMap(([label, modeSource]) => [
    [
      modeSource.includes("Picker(\"Responsibility\", selection: $selectedAssignmentType)") &&
        modeSource.includes("ForEach(FreightClaimsAPI.ClaimAssignmentType.allCases)") &&
        modeSource.includes(".getClaimSpecialistCandidates(") &&
        modeSource.includes("specialty: selectedAssignmentType") &&
        modeSource.includes(".assignClaimSpecialist(") &&
        modeSource.includes("assignmentType: selectedAssignmentType"),
      `${label} workflow selects and records every typed specialist responsibility`,
    ],
    [
      modeSource.includes("result.assignmentType == selectedAssignmentType") ||
        modeSource.includes("acknowledgement.assignmentType == selectedAssignmentType"),
      `${label} workflow verifies the acknowledged specialist type`,
    ],
    [
      modeSource.includes("record.assignmentType == assignmentType.rawValue") &&
        modeSource.includes("record.scope.jurisdictionScope == jurisdiction.scope") &&
        modeSource.includes("record.scope.jurisdictionCode == jurisdiction.code"),
      `${label} workflow verifies typed assignment and jurisdiction in refreshed claim truth`,
    ],
    [
      !modeSource.includes(".getClaimInvestigatorCandidates(") &&
        !modeSource.includes(".assignClaimInvestigator("),
      `${label} active workflow does not use investigator-only compatibility routes`,
    ],
  ]),
];

const failures = checks.filter(([passed]) => !passed).map(([, message]) => message);
if (failures.length) {
  for (const failure of failures) console.error(`FAIL: ${failure}`);
  process.exit(1);
}

for (const [, message] of checks) console.log(`PASS: ${message}`);
