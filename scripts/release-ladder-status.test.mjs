#!/usr/bin/env node

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { hashReleaseArtifact } from "./hash-release-artifact.mjs";

const sourceRoot = path.resolve(import.meta.dirname, "..");
const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "eusotrip-ladder-status-"));
const repository = path.join(temporaryRoot, "repository");
const evidence = path.join(temporaryRoot, "evidence");
fs.mkdirSync(path.join(repository, "scripts"), { recursive: true });
fs.mkdirSync(evidence, { recursive: true });

function run(command, arguments_, options = {}) {
  return spawnSync(command, arguments_, { encoding: "utf8", ...options });
}

function requireSuccess(command, arguments_, options = {}) {
  const result = run(command, arguments_, options);
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  return result;
}

function writeLadder(file, value, mode = 0o600) {
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`, { mode });
  fs.chmodSync(file, mode);
}

try {
  for (const name of ["release-ladder-status.mjs", "hash-release-artifact.mjs"]) {
    fs.copyFileSync(path.join(sourceRoot, "scripts", name), path.join(repository, "scripts", name));
  }
  requireSuccess("/usr/bin/git", ["init", "-q"], { cwd: repository });
  requireSuccess("/usr/bin/git", ["config", "user.name", "Release Ladder Tests"], { cwd: repository });
  requireSuccess("/usr/bin/git", ["config", "user.email", "release-ladder@example.invalid"], { cwd: repository });
  requireSuccess("/usr/bin/git", ["add", "--all"], { cwd: repository });
  requireSuccess("/usr/bin/git", ["commit", "-q", "-m", "fixture"], { cwd: repository });
  const commit = requireSuccess("/usr/bin/git", ["rev-parse", "HEAD"], { cwd: repository }).stdout.trim();
  const tree = requireSuccess("/usr/bin/git", ["rev-parse", "HEAD^{tree}"], { cwd: repository }).stdout.trim();

  const archiveApp = path.join(evidence, "archive", "EusoTrip.app");
  const exportedApp = path.join(evidence, "exported", "Payload", "EusoTrip.app");
  const ipa = path.join(evidence, "EusoTrip.ipa");
  const releaseConfigAttestation = path.join(evidence, "release-config-attestation.json");
  const deviceAcceptanceEvidence = path.join(evidence, "device-acceptance.json");
  const networkCapture = path.join(evidence, "radio-silent.pcap");
  const networkSummary = path.join(evidence, "network-summary.json");
  fs.mkdirSync(archiveApp, { recursive: true });
  fs.mkdirSync(exportedApp, { recursive: true });
  fs.writeFileSync(path.join(archiveApp, "Info.plist"), "archive");
  fs.writeFileSync(path.join(exportedApp, "Info.plist"), "exported");
  fs.writeFileSync(ipa, "ipa bytes");
  fs.writeFileSync(releaseConfigAttestation, "approved release config identity\n", { mode: 0o600 });
  fs.chmodSync(releaseConfigAttestation, 0o600);
  for (const [file, contents] of [
    [deviceAcceptanceEvidence, "approved device evidence\n"],
    [networkCapture, "private capture bytes\n"],
    [networkSummary, "sanitized zero-HERE summary\n"],
  ]) {
    fs.writeFileSync(file, contents, { mode: 0o600 });
    fs.chmodSync(file, 0o600);
  }

  const baseline = {
    schemaVersion: 3,
    version: "9.1.0",
    build: "901",
    bundleId: "com.app.eusotrip",
    sourceCommit: commit,
    sourceTree: tree,
    releaseConfigAttestationPath: releaseConfigAttestation,
    releaseConfigAttestationSha256: hashReleaseArtifact(releaseConfigAttestation),
    releaseStartedAt: "2026-09-01T00:00:00Z",
    githubRepository: "diegoenterprises/eusotrip-ios",
    githubBranch: "main",
    githubRequiredCheck: "HERE Offline Source Contract",
    githubReleaseEnvironment: "here-offline-release",
    githubGovernanceVerifiedAt: "2026-09-01T00:00:00Z",
    archiveAppPath: archiveApp,
    archiveAppTreeSha256: hashReleaseArtifact(archiveApp),
    exportedIPAPath: ipa,
    exportedIPASha256: hashReleaseArtifact(ipa),
    exportedAppPath: exportedApp,
    exportedAppTreeSha256: hashReleaseArtifact(exportedApp),
    compiled: "pass",
    archived: "pass",
    tested: "pass",
    hereOfflineContract: "pass",
    deviceAcceptance: "pass",
    deviceAcceptanceEvidencePath: deviceAcceptanceEvidence,
    deviceAcceptanceEvidenceSha256: hashReleaseArtifact(deviceAcceptanceEvidence),
    networkCapturePath: networkCapture,
    networkCaptureSha256: hashReleaseArtifact(networkCapture),
    networkSummaryPath: networkSummary,
    networkSummarySha256: hashReleaseArtifact(networkSummary),
    deviceModelIdentifier: "iPhone18,1",
    deviceOSVersion: "27.0",
    deviceAcceptanceApprovedAt: "2026-09-01T02:00:00Z",
    deviceAcceptanceApprovedBy: "independent-approver-2",
    exported: "pass",
    uploaded: "pass",
    processing: "pass",
    availableInTestFlight: "pass",
  };
  const ladder = path.join(evidence, "release-ladder.json");
  const statusScript = path.join(repository, "scripts", "release-ladder-status.mjs");

  writeLadder(ladder, baseline);
  let result = run(process.execPath, [statusScript, `--file=${ladder}`], { cwd: repository });
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  assert.match(result.stdout, /This exact source and exported artifact are available/);
  console.log("ok - exact source and artifacts can complete the ladder");

  writeLadder(ladder, { ...baseline, hereOfflineContract: "fail" });
  result = run(process.execPath, [statusScript, `--file=${ladder}`], { cwd: repository });
  assert.equal(result.status, 1);
  console.log("ok - failed HERE rung blocks availability");

  writeLadder(ladder, baseline);
  result = run(process.execPath, [statusScript, `--file=${ladder}`, "--build=902"], { cwd: repository });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /does not match the requested release identity/);
  console.log("ok - requested build mismatch is rejected");

  fs.appendFileSync(ipa, "tamper");
  result = run(process.execPath, [statusScript, `--file=${ladder}`], { cwd: repository });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /exported IPA no longer matches/);
  console.log("ok - artifact mutation invalidates availability");
  fs.writeFileSync(ipa, "ipa bytes");

  writeLadder(ladder, baseline);
  fs.appendFileSync(networkCapture, "tamper");
  result = run(process.execPath, [statusScript, `--file=${ladder}`], { cwd: repository });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /private network capture no longer matches/);
  console.log("ok - device network evidence mutation invalidates availability");
  fs.writeFileSync(networkCapture, "private capture bytes\n");

  writeLadder(ladder, baseline, 0o644);
  result = run(process.execPath, [statusScript, `--file=${ladder}`], { cwd: repository });
  assert.equal(result.status, 2);
  assert.match(result.stderr, /owner-private/);
  console.log("ok - permissive ladder file is rejected");

  writeLadder(ladder, { ...baseline, githubGovernanceVerifiedAt: "2099-01-01T00:00:00Z" });
  result = run(process.execPath, [statusScript, `--file=${ladder}`], { cwd: repository });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /governance chronology/);
  console.log("ok - future-dated GitHub governance is rejected");

  writeLadder(ladder, { ...baseline, deviceAcceptanceApprovedAt: "2099-01-01T00:00:00Z" });
  result = run(process.execPath, [statusScript, `--file=${ladder}`], { cwd: repository });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /device acceptance approval chronology/);
  console.log("ok - future-dated device acceptance is rejected");

  result = run(process.execPath, [statusScript], { cwd: repository });
  assert.equal(result.status, 2);
  assert.match(result.stderr, /exact release ladder is required/);
  console.log("ok - implicit predictable ladder path is rejected");
} finally {
  fs.rmSync(temporaryRoot, { recursive: true, force: true });
}

console.log("Release ladder status regression harness passed: 9 cases.");
