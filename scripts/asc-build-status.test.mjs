#!/usr/bin/env node

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "eusotrip-asc-status-"));
try {
  const keyID = "FIXTUREKEY";
  const keyPath = path.join(temporaryRoot, `AuthKey_${keyID}.p8`);
  const { privateKey } = crypto.generateKeyPairSync("ec", { namedCurve: "P-256" });
  fs.writeFileSync(
    keyPath,
    privateKey.export({ format: "pem", type: "pkcs8" }),
    { mode: 0o600 }
  );
  const ladderPath = path.join(temporaryRoot, "release-ladder.json");
  const baseline = {
    schemaVersion: 3,
    version: "9.1.0",
    build: "901",
    bundleId: "com.app.eusotrip",
    sourceCommit: "a".repeat(40),
    sourceTree: "b".repeat(40),
    processing: "pending",
    availableInTestFlight: "pending",
    deviceAcceptance: "pending",
  };
  const writeLadder = value => {
    fs.writeFileSync(ladderPath, `${JSON.stringify(value)}\n`, { mode: 0o600 });
    fs.chmodSync(ladderPath, 0o600);
  };
  const mockPath = path.join(temporaryRoot, "mock-fetch.mjs");
  fs.writeFileSync(
    mockPath,
    [
      "const response = value => new Response(JSON.stringify(value), { status: 200 });",
      "globalThis.fetch = async url => {",
      "  const value = String(url);",
      "  if (value.includes('/v1/apps/')) return response({ data: { attributes: { bundleId: process.env.FIXTURE_BUNDLE_ID || 'com.app.eusotrip' } } });",
      "  if (value.includes('/v1/builds?')) return response({",
      "    data: [{ id: 'build-901', attributes: { version: '901', uploadedDate: '2026-09-01T00:00:00Z', processingState: 'VALID', expired: false }, relationships: { preReleaseVersion: { data: { id: 'train-910' } } } }],",
      "    included: [{ id: 'train-910', attributes: { version: process.env.FIXTURE_VERSION || '9.1.0' } }],",
      "  });",
      "  if (value.includes('/v1/betaGroups?')) return response({ data: [{ id: 'group-1', attributes: { name: 'Internal' } }] });",
      "  return new Response('{}', { status: 404 });",
      "};",
      "",
    ].join("\n")
  );
  const script = path.join(import.meta.dirname, "asc-build-status.mjs");
  const baseEnvironment = {
    ...process.env,
    ASC_API_KEY_ID: keyID,
    ASC_API_KEY_ISSUER: "00000000-0000-0000-0000-000000000001",
    ASC_API_KEY_PATH: keyPath,
  };
  const run = (extraArguments = [], extraEnvironment = {}) =>
    spawnSync(
      process.execPath,
      [
        `--import=${mockPath}`,
        script,
        "--app-id=123456789",
        `--ladder=${ladderPath}`,
        ...extraArguments,
      ],
      { encoding: "utf8", env: { ...baseEnvironment, ...extraEnvironment } }
    );

  writeLadder(baseline);
  let result = run();
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  let updated = JSON.parse(fs.readFileSync(ladderPath, "utf8"));
  assert.equal(updated.processing, "pass");
  assert.equal(updated.availableInTestFlight, "pass");
  assert.equal(updated.appStoreConnectBuildId, "build-901");
  assert.equal(updated.build, "901");
  assert.equal(updated.version, "9.1.0");
  assert.equal(fs.statSync(ladderPath).mode & 0o077, 0);
  console.log("ok - ladder derives and updates only its exact build and version");

  writeLadder(baseline);
  result = run(["--build=902"]);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /--build does not match/);
  console.log("ok - explicit build cannot disagree with the ladder");

  writeLadder(baseline);
  result = run([], { FIXTURE_VERSION: "9.2.0" });
  assert.equal(result.status, 0);
  updated = JSON.parse(fs.readFileSync(ladderPath, "utf8"));
  assert.equal(updated.processing, "pending");
  assert.equal(updated.availableInTestFlight, "pending");
  assert.equal(updated.appStoreConnectBuildId, null);
  console.log("ok - a same-number build in another version cannot satisfy the ladder");

  writeLadder(baseline);
  result = run([], { FIXTURE_BUNDLE_ID: "com.example.substitute" });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /does not match the ladder bundle identifier/);
  console.log("ok - App Store app identity is bundle-bound");

  fs.chmodSync(keyPath, 0o644);
  writeLadder(baseline);
  result = run();
  assert.equal(result.status, 1);
  assert.match(result.stderr, /permissions must be 0600 or stricter/);
  fs.chmodSync(keyPath, 0o600);
  console.log("ok - status polling rejects a group-readable API private key");

  const rsaKeyID = "RSAFIXTURE";
  const rsaKeyPath = path.join(temporaryRoot, `AuthKey_${rsaKeyID}.p8`);
  const { privateKey: rsaPrivateKey } = crypto.generateKeyPairSync("rsa", { modulusLength: 2048 });
  fs.writeFileSync(
    rsaKeyPath,
    rsaPrivateKey.export({ format: "pem", type: "pkcs8" }),
    { mode: 0o600 }
  );
  writeLadder(baseline);
  result = spawnSync(
    process.execPath,
    [`--import=${mockPath}`, script, "--app-id=123456789", `--ladder=${ladderPath}`],
    {
      encoding: "utf8",
      env: {
        ...baseEnvironment,
        ASC_API_KEY_ID: rsaKeyID,
        ASC_API_KEY_PATH: rsaKeyPath,
      },
    }
  );
  assert.equal(result.status, 1);
  assert.match(result.stderr, /must contain an EC private key/);
  console.log("ok - status polling rejects a non-EC API private key");
} finally {
  fs.rmSync(temporaryRoot, { recursive: true, force: true });
}

console.log("ASC build status regression harness passed: 6 cases.");
