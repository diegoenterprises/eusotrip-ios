#!/usr/bin/env node

import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { verifyReleaseConfigAttestation } from "./verify-release-config-attestation.mjs";

const root = fs.mkdtempSync(path.join(os.tmpdir(), "eusotrip-release-config-attestation-"));
fs.chmodSync(root, 0o700);
try {
  const file = path.join(root, "attestation.json");
  const xcconfigFile = path.join(root, "EusoTrip.release.xcconfig");
  const routePublicKey = Buffer.alloc(32, 7);
  const routePublicKeyBase64 = routePublicKey.toString("base64");
  const routePublicKeySHA256 = crypto.createHash("sha256").update(routePublicKey).digest("hex");
  const xcconfigContents = [
    "HERE_SDK_ACCESS_KEY_ID = protected",
    "EUSOTRIP_ROUTE_PLAN_ISSUER = eusotrip-route-authority",
    "EUSOTRIP_ROUTE_PLAN_AUDIENCE = eusotrip-ios",
    "EUSOTRIP_ROUTE_PLAN_KEY_ID = route-key-2026-09",
    `EUSOTRIP_ROUTE_PLAN_PUBLIC_KEY_BASE64 = ${routePublicKeyBase64}`,
    "",
  ].join("\n");
  fs.writeFileSync(xcconfigFile, xcconfigContents, { mode: 0o600 });
  fs.chmodSync(xcconfigFile, 0o600);
  const xcconfigSHA256 = crypto.createHash("sha256")
    .update(fs.readFileSync(xcconfigFile))
    .digest("hex");
  const baseline = {
    schemaVersion: 1,
    status: "approved",
    source: "protected_secret_store",
    incidentID: "HERE-2026-08-31-01",
    configGenerationID: "release-config-generation-2",
    appleTeamID: "665Z3ZBZS2",
    releaseXcconfigSHA256: xcconfigSHA256,
    routePlanIssuer: "eusotrip-route-authority",
    routePlanAudience: "eusotrip-ios",
    routePlanKeyID: "route-key-2026-09",
    routePlanPublicKeySHA256: routePublicKeySHA256,
    credentialClasses: [
      "here_maps_js_api_key",
      "here_sdk_navigate_access_key_id",
      "here_sdk_navigate_access_key_secret",
    ],
    credentialsRotatedAt: "2026-09-01T01:00:00Z",
    generatedAt: "2026-09-01T01:05:00Z",
    generatedBy: "release-operator-1",
    approvedAt: "2026-09-01T01:10:00Z",
    expiresAt: "2026-09-02T01:10:00Z",
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
    verifyReleaseConfigAttestation({ file, expectedTeamID: "665Z3ZBZS2", xcconfigFile }),
    /^[a-f0-9]{64}$/,
  );
  console.log("ok - independently approved redacted release config attestation");

  write({ ...baseline, approvedBy: baseline.generatedBy });
  assert.throws(
    () => verifyReleaseConfigAttestation({ file, expectedTeamID: "665Z3ZBZS2", xcconfigFile }),
    /independently approved/,
  );
  console.log("ok - self-approval is rejected");

  write({ ...baseline, appleTeamID: "ABCDEFGHIJ" });
  assert.throws(
    () => verifyReleaseConfigAttestation({ file, expectedTeamID: "665Z3ZBZS2", xcconfigFile }),
    /incomplete/,
  );
  console.log("ok - Apple team substitution is rejected");

  write({ ...baseline, generatedAt: "2026-08-31T23:00:00Z" });
  assert.throws(
    () => verifyReleaseConfigAttestation({ file, expectedTeamID: "665Z3ZBZS2", xcconfigFile }),
    /chronology/,
  );
  console.log("ok - pre-rotation config generation is rejected");

  write(baseline);
  fs.chmodSync(file, 0o644);
  assert.throws(
    () => verifyReleaseConfigAttestation({ file, expectedTeamID: "665Z3ZBZS2", xcconfigFile }),
    /owner-private/,
  );
  console.log("ok - permissive attestation file is rejected");

  write({ ...baseline, approvedAt: "2099-01-01T00:00:00Z" });
  assert.throws(
    () => verifyReleaseConfigAttestation({ file, expectedTeamID: "665Z3ZBZS2", xcconfigFile }),
    /future-dated/,
  );
  console.log("ok - future-dated config approval is rejected");

  write({ ...baseline, expiresAt: "2026-09-01T01:11:00Z" });
  assert.throws(
    () => verifyReleaseConfigAttestation({ file, expectedTeamID: "665Z3ZBZS2", xcconfigFile }),
    /stale/,
  );
  console.log("ok - expired config approval is rejected");

  write(baseline);
  fs.appendFileSync(xcconfigFile, "HERE_SDK_ACCESS_KEY_SECRET = rotated\n");
  assert.throws(
    () => verifyReleaseConfigAttestation({ file, expectedTeamID: "665Z3ZBZS2", xcconfigFile }),
    /incomplete/,
  );
  console.log("ok - xcconfig bytes cannot diverge from the approved digest");

  fs.writeFileSync(
    xcconfigFile,
    xcconfigContents.replace(routePublicKeyBase64, Buffer.alloc(32, 8).toString("base64")),
    { mode: 0o600 },
  );
  assert.throws(
    () => verifyReleaseConfigAttestation({ file, expectedTeamID: "665Z3ZBZS2", xcconfigFile }),
    /incomplete/,
  );
  console.log("ok - route-plan verification key substitution is rejected");
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}

console.log("Release config attestation regression harness passed: 9 cases.");
