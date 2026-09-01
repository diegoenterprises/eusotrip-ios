#!/usr/bin/env node

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { hashReleaseArtifact } from "./hash-release-artifact.mjs";
import { verifyExportedIPAAppBinding } from "./verify-exported-ipa-app-binding.mjs";

const root = fs.mkdtempSync(path.join(os.tmpdir(), "eusotrip-ipa-app-binding-test-"));
try {
  const payload = path.join(root, "Payload");
  const app = path.join(payload, "EusoTrip.app");
  const ipa = path.join(root, "EusoTrip.ipa");
  fs.mkdirSync(app, { recursive: true });
  fs.writeFileSync(path.join(app, "Info.plist"), "approved app");
  let result = spawnSync(
    "/usr/bin/ditto",
    ["-c", "-k", "--norsrc", "--keepParent", payload, ipa],
    { encoding: "utf8" },
  );
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);

  const expectedIPASha256 = hashReleaseArtifact(ipa);
  const expectedAppTreeSha256 = hashReleaseArtifact(app);
  assert.doesNotThrow(() => verifyExportedIPAAppBinding({
    ipaFile: ipa,
    expectedIPASha256,
    expectedAppTreeSha256,
  }));
  console.log("ok - exact app tree is derived from the recorded IPA");

  fs.writeFileSync(path.join(app, "Info.plist"), "substituted app");
  assert.throws(() => verifyExportedIPAAppBinding({
    ipaFile: ipa,
    expectedIPASha256,
    expectedAppTreeSha256: hashReleaseArtifact(app),
  }), /not derived/);
  console.log("ok - independent app-tree substitution is rejected");

  fs.appendFileSync(ipa, "trailing substitution");
  assert.throws(() => verifyExportedIPAAppBinding({
    ipaFile: ipa,
    expectedIPASha256,
    expectedAppTreeSha256,
  }), /preflight|recorded SHA-256/i);
  console.log("ok - IPA substitution is rejected before extraction");
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}

console.log("Exported IPA/app binding regression harness passed: 3 cases.");
