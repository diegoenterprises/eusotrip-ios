#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const ledgerPath =
  process.env.ASC_CRASH_LEDGER ??
  path.join(root, "docs/testflight-feedback-ledger.json");

const readJSON = (file) => JSON.parse(fs.readFileSync(file, "utf8"));
const sha256 = (file) =>
  crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
const ledger = readJSON(ledgerPath);
const cachePath = process.env.ASC_FEEDBACK_SUMMARY ?? ledger.source;

const assert = (condition, message) => {
  if (!condition) throw new Error(message);
};
const requireText = (target, needle, label) => {
  assert(target.includes(needle), `${label}: missing ${needle}`);
};
const forbidText = (target, needle, label) => {
  assert(!target.includes(needle), `${label}: forbidden ${needle}`);
};

assert(
  typeof cachePath === "string" && fs.existsSync(cachePath),
  "current ASC cache is unavailable",
);
const cache = readJSON(cachePath);
const ascRows = cache.crashFeedback;
const ledgerRows = ledger.items?.filter((row) => row.kind === "crash");

assert(
  Array.isArray(ascRows) && ascRows.length === 10,
  "current ASC cache must contain 10 crash submissions",
);
assert(
  Array.isArray(ledgerRows) && ledgerRows.length === 10,
  "current ledger must contain 10 crash rows",
);
assert(
  ledger.counts?.crashes === 10,
  "ledger crash count must match the current cache",
);

const source = {
  api: fs.readFileSync(
    path.join(root, "EusoTrip/Services/EusoTripAPI.swift"),
    "utf8",
  ),
  erg: fs.readFileSync(
    path.join(root, "EusoTrip/Views/Driver/096_MeErg.swift"),
    "utf8",
  ),
  postLoad: fs.readFileSync(
    path.join(root, "EusoTrip/Views/Shipper/204_ShipperPostLoad.swift"),
    "utf8",
  ),
  project: fs.readFileSync(
    path.join(root, "EusoTrip.xcodeproj/project.pbxproj"),
    "utf8",
  ),
};

const projectBuilds = [
  ...source.project.matchAll(/CURRENT_PROJECT_VERSION = (\d+);/g),
].map((match) => match[1]);
assert(projectBuilds.length > 0, "project build settings not found");
assert(
  projectBuilds.every((build) => build === "850"),
  "project build settings changed from 850",
);

const expected = new Map(ascRows.map((row) => [row.id, row.buildVersion]));
const actual = new Map(ledgerRows.map((row) => [row.ascId, row.build]));
assert(actual.size === 10, "ledger crash IDs must be unique");
for (const [id, build] of expected) {
  assert(actual.get(id) === build, `ledger row mismatch for ${id}`);
}

const downloadedRows = ascRows.filter(
  (row) =>
    typeof row.crashLogFile === "string" && fs.existsSync(row.crashLogFile),
);
const metadataOnlyRows = ascRows.filter((row) => row.crashLogFile == null);
assert(
  downloadedRows.length === 6,
  "current ASC cache must retain 6 persistent crash logs",
);
assert(
  metadataOnlyRows.length === 4,
  "current ASC cache must retain 4 metadata-only crashes",
);

for (const row of ledgerRows) {
  const cached = ascRows.find((candidate) => candidate.id === row.ascId);
  assert(cached != null, `${row.ascId}: cache row missing`);
  assert(
    typeof row.status === "string" && row.status.length > 0,
    `${row.ascId}: status missing`,
  );
  const hasVerification =
    (typeof row.verification === "string" && row.verification.length > 0) ||
    (Array.isArray(row.verification) && row.verification.length > 0);
  assert(hasVerification, `${row.ascId}: verification missing`);
  assert(
    Array.isArray(row.verificationArtifacts) &&
      row.verificationArtifacts.length > 0,
    `${row.ascId}: verification artifacts missing`,
  );
  assert(
    Object.hasOwn(row, "duplicateOf"),
    `${row.ascId}: duplicateOf missing`,
  );
  if (cached.crashLogFile == null) {
    assert(
      row.crashLogFile == null,
      `${row.ascId}: metadata-only crash claims a downloaded log`,
    );
  } else {
    assert(
      row.crashLogFile === cached.crashLogFile,
      `${row.ascId}: persistent crash-log path drift`,
    );
    assert(
      fs.existsSync(row.crashLogFile),
      `${row.ascId}: persistent crash log is missing`,
    );
  }
  if (row.duplicateOf) {
    assert(
      actual.has(row.duplicateOf),
      `${row.ascId}: duplicate target is not in this ledger`,
    );
    assert(row.duplicateOf !== row.ascId, `${row.ascId}: self-duplicate`);
  }
  assert(
    row.status === "fixed-pending-testflight" ||
      row.status === "blocked-missing-crash-log",
    `${row.ascId}: crash row claims unsupported closure state ${row.status}`,
  );
}

const blockedRows = ledgerRows.filter(
  (row) => row.status === "blocked-missing-crash-log",
);
assert(
  blockedRows.length === 1,
  "exactly one crash must remain blocked for a missing log",
);
assert(
  blockedRows[0].ascId === "AERc3OG10dy54nLjdVli9yE",
  "blocked crash identity changed",
);

const build850Cache = ascRows.find(
  (row) => row.id === "AEIVDhm-Gp1_qpFZtIdNZPY",
);
const build850Ledger = ledgerRows.find(
  (row) => row.ascId === "AEIVDhm-Gp1_qpFZtIdNZPY",
);
assert(build850Cache?.buildVersion === "850", "build-850 ASC crash is missing");
assert(
  build850Ledger?.status === "fixed-pending-testflight",
  "build-850 crash must remain pending device proof",
);
const build850Log = fs.readFileSync(build850Cache.crashLogFile, "utf8");
requireText(build850Log, "EXC_BAD_ACCESS", "build-850 exception evidence");
requireText(
  build850Log,
  "ShipperPostLoad.equipmentSubform",
  "build-850 stack evidence",
);
requireText(
  source.postLoad,
  "private var equipmentSubform: AnyView",
  "post-load equipment boundary",
);
requireText(
  source.postLoad,
  "private var equipmentStepBody: AnyView",
  "post-load step boundary",
);
if (process.env.ASC_BUILD_850_CRASH) {
  assert(
    fs.existsSync(process.env.ASC_BUILD_850_CRASH),
    "supplied build-850 crash is unavailable",
  );
  assert(
    sha256(process.env.ASC_BUILD_850_CRASH) ===
      sha256(build850Cache.crashLogFile),
    "supplied build-850 crash does not match the authorized ASC artifact",
  );
}

const serialized = JSON.stringify(ledgerRows);
for (const secretMarker of [
  "BEGIN PRIVATE KEY",
  "ASC_KEY_ID",
  "ASC_ISSUER_ID",
  "sk_live_",
]) {
  forbidText(serialized, secretMarker, "secret hygiene");
}

requireText(
  source.api,
  "URLSessionConfiguration.ephemeral",
  "API private transport",
);
requireText(source.api, "config.urlCache = nil", "API cache isolation");
requireText(
  source.api,
  "try Task.checkCancellation()",
  "API cancellation boundary",
);
requireText(
  source.api,
  "private func transportData(for original: URLRequest)",
  "API shared transport",
);
requireText(
  source.erg,
  ".task(id: retryAttempt)",
  "ERG structured request ownership",
);
requireText(
  source.erg,
  "let response = try await EusoTripAPI.shared.erg.searchByUN(unNumber)",
  "ERG real request",
);
forbidText(source.erg, "while store.detail == nil", "ERG retry loop removal");
requireText(
  source.postLoad,
  "draftPersistWork?.cancel()",
  "post-load teardown",
);
requireText(
  source.postLoad,
  "DispatchQueue.global(qos: .utility).async",
  "post-load off-main persistence",
);
requireText(
  source.postLoad,
  "generation == draftHydrationGeneration",
  "post-load stale hydration rejection",
);

console.log(
  JSON.stringify(
    {
      verified: true,
      cache: cachePath,
      ascRows: ascRows.length,
      downloadedLogs: downloadedRows.length,
      metadataOnly: metadataOnlyRows.length,
      blockedMissingLog: blockedRows[0].ascId,
      currentBuild: "850",
      build850CrashSha256: sha256(build850Cache.crashLogFile),
      duplicateRows: ledgerRows.filter((row) => row.duplicateOf != null).length,
      closure:
        "all crash rows remain pending TestFlight/device evidence or blocked",
      privacy: "secret markers absent",
    },
    null,
    2,
  ),
);
