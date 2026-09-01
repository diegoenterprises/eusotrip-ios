#!/usr/bin/env node

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { verifyReleaseConfigAttestation } from "./verify-release-config-attestation.mjs";

const root = fs.mkdtempSync(path.join(os.tmpdir(), "eusotrip-release-config-attestation-"));
fs.chmodSync(root, 0o700);
try {
  const file = path.join(root, "attestation.json");
  const baseline = {
    schemaVersion: 1,
    status: "approved",
    source: "protected_secret_store",
    incidentID: "HERE-2026-08-31-01",
    configGenerationID: "release-config-generation-2",
    appleTeamID: "665Z3ZBZS2",
    credentialClasses: [
      "here_maps_js_api_key",
      "here_sdk_navigate_access_key_id",
      "here_sdk_navigate_access_key_secret",
    ],
    credentialsRotatedAt: "2026-09-01T01:00:00Z",
    generatedAt: "2026-09-01T01:05:00Z",
    generatedBy: "release-operator-1",
    approvedAt: "2026-09-01T01:10:00Z",
    approvedBy: "release-approver-2",
    containsDedicatedNavigateCredentials: true,
    containsNoIncidentCredentialMaterial: true,
  };
  const write = value => {
    fs.writeFileSync(file, `${JSON.stringify(value)}\n`, { mode: 0o600 });
    fs.chmodSync(file, 0o600);
  };

  write(baseline);
  assert.match(
    verifyReleaseConfigAttestation({ file, expectedTeamID: "665Z3ZBZS2" }),
    /^[a-f0-9]{64}$/,
  );
  console.log("ok - independently approved redacted release config attestation");

  write({ ...baseline, approvedBy: baseline.generatedBy });
  assert.throws(
    () => verifyReleaseConfigAttestation({ file, expectedTeamID: "665Z3ZBZS2" }),
    /independently approved/,
  );
  console.log("ok - self-approval is rejected");

  write({ ...baseline, appleTeamID: "ABCDEFGHIJ" });
  assert.throws(
    () => verifyReleaseConfigAttestation({ file, expectedTeamID: "665Z3ZBZS2" }),
    /incomplete/,
  );
  console.log("ok - Apple team substitution is rejected");

  write({ ...baseline, generatedAt: "2026-08-31T23:00:00Z" });
  assert.throws(
    () => verifyReleaseConfigAttestation({ file, expectedTeamID: "665Z3ZBZS2" }),
    /chronology/,
  );
  console.log("ok - pre-rotation config generation is rejected");

  write(baseline);
  fs.chmodSync(file, 0o644);
  assert.throws(
    () => verifyReleaseConfigAttestation({ file, expectedTeamID: "665Z3ZBZS2" }),
    /owner-private/,
  );
  console.log("ok - permissive attestation file is rejected");

  write({ ...baseline, approvedAt: "2099-01-01T00:00:00Z" });
  assert.throws(
    () => verifyReleaseConfigAttestation({ file, expectedTeamID: "665Z3ZBZS2" }),
    /future-dated/,
  );
  console.log("ok - future-dated config approval is rejected");
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}

console.log("Release config attestation regression harness passed: 6 cases.");
