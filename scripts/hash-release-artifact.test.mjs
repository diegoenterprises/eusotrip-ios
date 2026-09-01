#!/usr/bin/env node

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { hashReleaseArtifact } from "./hash-release-artifact.mjs";

const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "eusotrip-artifact-hash-"));
try {
  const first = path.join(temporaryRoot, "first");
  const second = path.join(temporaryRoot, "second");
  fs.mkdirSync(path.join(first, "Nested"), { recursive: true });
  fs.writeFileSync(path.join(first, "Info.plist"), "plist");
  fs.writeFileSync(path.join(first, "Nested", "binary"), "payload");
  fs.symlinkSync("Nested/binary", path.join(first, "Current"));
  fs.cpSync(first, second, { recursive: true, verbatimSymlinks: true });

  const baseline = hashReleaseArtifact(first);
  assert.match(baseline, /^[a-f0-9]{64}$/);
  assert.equal(hashReleaseArtifact(second), baseline);
  console.log("ok - identical trees hash identically");

  fs.writeFileSync(path.join(second, "Nested", "binary"), "changed");
  assert.notEqual(hashReleaseArtifact(second), baseline);
  console.log("ok - content changes alter the hash");

  fs.rmSync(second, { recursive: true, force: true });
  fs.cpSync(first, second, { recursive: true, force: true, verbatimSymlinks: true });
  fs.chmodSync(path.join(second, "Nested", "binary"), 0o755);
  assert.notEqual(hashReleaseArtifact(second), baseline);
  console.log("ok - executable-mode changes alter the hash");

  fs.rmSync(path.join(second, "Current"));
  fs.symlinkSync("Info.plist", path.join(second, "Current"));
  assert.notEqual(hashReleaseArtifact(second), baseline);
  console.log("ok - symbolic-link target changes alter the hash");

  assert.notEqual(
    hashReleaseArtifact(path.join(first, "Info.plist")),
    hashReleaseArtifact(path.join(first, "Nested", "binary"))
  );
  const knownVector = path.join(temporaryRoot, "sha256-vector");
  fs.writeFileSync(knownVector, "abc");
  assert.equal(
    hashReleaseArtifact(knownVector),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  );
  console.log("ok - regular files use conventional exact-byte SHA-256");

  const rootLink = path.join(temporaryRoot, "artifact-link");
  fs.symlinkSync(knownVector, rootLink);
  assert.throws(() => hashReleaseArtifact(rootLink), /regular file or directory/);
  console.log("ok - symbolic-link artifact roots are rejected");
} finally {
  fs.rmSync(temporaryRoot, { recursive: true, force: true });
}

console.log("Release artifact hash regression harness passed: 6 cases.");
