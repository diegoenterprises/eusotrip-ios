import { readFileSync } from "node:fs";

const targets = [
  {
    path: "EusoTrip/Views/Dispatch/401_DispatcherKanban.swift",
    mutations: 2,
    resultType: "DispatcherMutationResult",
    dropGuard: "guard shifting == nil else { return false }",
    validationCalls: [
      "try response.validateStatus(loadId: l.id, status: next)",
      "try response.validateUnassignment(loadId: l.id)",
    ],
  },
  {
    path: "EusoTrip/Views/Components/AppointmentSchedulerSheet.swift",
    mutations: 1,
    resultType: "AppointmentMutationResult",
    dropGuard: "guard actingId == nil else { return false }",
    clears: ["actionAck = nil", "lastAdvance = nil"],
  },
  {
    path: "EusoTrip/Views/Catalyst/301_CatalystDispatchBoard.swift",
    mutations: 2,
    resultType: "CatalystMutationResult",
    dropGuard: "guard advancing == nil else { return false }",
    clears: ["lastAdvance = nil"],
  },
  {
    path: "EusoTrip/Views/Carrier/320_CarrierVehiclesList.swift",
    mutations: 1,
    resultType: "VehicleMutationResult",
    dropGuard: "guard flipping == nil else { return false }",
    clears: ["lastFlip = nil"],
  },
  {
    path: "EusoTrip/Views/Shipper/426_DemurrageCharges.swift",
    mutations: 1,
    resultType: "DemurrageMutationResult",
    dropGuard: "guard processing == nil else { return false }",
    clears: ["lastAction = nil"],
  },
  {
    path: "EusoTrip/Views/Dispatch/709_DispatchBulkUploadKanban.swift",
    mutations: 3,
    resultType: "BulkMutationResult",
    dropGuard: "guard workingId == nil else { return false }",
    clears: ["lastAction = nil"],
    requires: ["BulkActionErrorCard(message: $actionError)"],
  },
];

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const count = (source, needle) => source.split(needle).length - 1;
const failures = [];
let mutationTotal = 0;

for (const target of targets) {
  const source = read(target.path);
  const mutationNeedle = "EusoTripAPI.shared.mutation(";
  const typedMutationNeedle = `: ${target.resultType} = try await ${mutationNeedle}`;
  const mutationCount = count(source, mutationNeedle);
  mutationTotal += mutationCount;

  if (mutationCount !== target.mutations) {
    failures.push(`${target.path}: expected ${target.mutations} mutation call(s), found ${mutationCount}`);
  }
  if (source.includes("let _: Out = try await EusoTripAPI.shared.mutation(")) {
    failures.push(`${target.path}: still discards a mutation response`);
  }
  if (count(source, typedMutationNeedle) !== target.mutations) {
    failures.push(`${target.path}: every mutation must retain its ${target.resultType} response`);
  }
  if (!source.includes(`private struct ${target.resultType}: Decodable`)) {
    failures.push(`${target.path}: missing ${target.resultType}`);
  }
  for (const field of ["let success: Bool?", "let message: String?", "let error: String?"]) {
    if (!source.includes(field)) failures.push(`${target.path}: response contract missing ${field}`);
  }
  if (!source.includes("guard success == false else { return nil }")) {
    failures.push(`${target.path}: application-level success=false is not classified as failure`);
  }
  if (!source.includes("return [message, error]")) {
    failures.push(`${target.path}: server message/error is not used for the surfaced failure`);
  }
  if (!source.includes(target.dropGuard)) {
    failures.push(`${target.path}: missing duplicate in-flight drop guard`);
  }
  for (const staleSuccess of target.clears ?? []) {
    if (!source.includes(staleSuccess)) {
      failures.push(`${target.path}: does not clear stale success UI (${staleSuccess})`);
    }
  }
  for (const requiredSource of target.requires ?? []) {
    if (!source.includes(requiredSource)) {
      failures.push(`${target.path}: missing required rejection surface (${requiredSource})`);
    }
  }

  let cursor = 0;
  for (let index = 0; index < mutationCount; index += 1) {
    const mutationAt = source.indexOf(mutationNeedle, cursor);
    const catchAt = source.indexOf("} catch", mutationAt);
    const nextMutationAt = source.indexOf(mutationNeedle, mutationAt + mutationNeedle.length);
    const guardAt = target.validationCalls
      ? source.indexOf("try response.validate", mutationAt)
      : source.indexOf(".failureMessage(", mutationAt);
    if (catchAt < 0 || guardAt < 0 || guardAt > catchAt || (nextMutationAt >= 0 && guardAt > nextMutationAt)) {
      failures.push(`${target.path}: mutation ${index + 1} is not guarded before its success path`);
    }
    cursor = mutationAt + mutationNeedle.length;
  }

  if (target.validationCalls) {
    for (const validation of target.validationCalls) {
      if (!source.includes(validation)) {
        failures.push(`${target.path}: missing typed acknowledgement validation (${validation})`);
      }
    }
  } else {
    const falseBranches = [...source.matchAll(
      /if let failure = [A-Za-z0-9_.]+\.failureMessage\([\s\S]*?\n\s*\) \{([\s\S]*?)\n\s*\} else \{/g,
    )];
    if (falseBranches.length !== target.mutations) {
      failures.push(`${target.path}: expected ${target.mutations} explicit false branch(es), found ${falseBranches.length}`);
    }
    for (const [index, match] of falseBranches.entries()) {
      const branch = match[1];
      if (!branch.includes("actionError = failure")) {
        failures.push(`${target.path}: false branch ${index + 1} does not surface the server failure`);
      }
      if (!/await load(?:All)?\(\)/.test(branch)) {
        failures.push(`${target.path}: false branch ${index + 1} does not reload authoritative state`);
      }
    }
  }
}

if (failures.length) {
  console.error(`iOS mutation false-success verification failed:\n- ${failures.join("\n- ")}`);
  process.exit(1);
}

console.log(
  `iOS mutation false-success verification passed: ${mutationTotal} mutation paths across ${targets.length} Swift files.`,
);
