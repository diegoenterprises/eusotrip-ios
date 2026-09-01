#!/usr/bin/env node

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { hashReleaseArtifact } from "./hash-release-artifact.mjs";
import { verifyAndRecordDeviceAcceptance } from "./verify-here-offline-device-acceptance.mjs";

const root = fs.mkdtempSync(path.join(os.tmpdir(), "eusotrip-device-acceptance-"));
const repository = path.join(root, "repository");
const privateEvidence = path.join(root, "private-evidence");
fs.mkdirSync(path.join(repository, "EusoTrip/Services/HereMaps/Offline"), { recursive: true });
fs.mkdirSync(privateEvidence, { recursive: true });
fs.chmodSync(root, 0o700);
fs.chmodSync(privateEvidence, 0o700);

const run = (command, arguments_, options = {}) =>
  spawnSync(command, arguments_, { encoding: "utf8", ...options });
const requireSuccess = (command, arguments_, options = {}) => {
  const result = run(command, arguments_, options);
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  return result;
};
const writePrivate = (file, contents) => {
  fs.writeFileSync(file, contents, { mode: 0o600 });
  fs.chmodSync(file, 0o600);
};
const hashBytes = bytes => crypto.createHash("sha256").update(bytes).digest("hex");

try {
  const sdkManifestFile = path.join(repository, "EusoTrip/Services/HereMaps/Offline/HERE_SDK_SUPPLY_CHAIN.json");
  const styleManifestFile = path.join(repository, "EusoTrip/Services/HereMaps/Offline/HERE_NATIVE_STYLE_SUPPLY_CHAIN.json");
  fs.writeFileSync(sdkManifestFile, `${JSON.stringify({
    approvedVersion: "4.27.2.0",
    archiveSHA256: "a".repeat(64),
    frameworkTreeSHA256: "b".repeat(64),
    legalNoticeSHA256: "c".repeat(64),
    status: "approved",
  })}\n`);
  fs.writeFileSync(styleManifestFile, `${JSON.stringify({
    status: "approved",
    entries: Array.from({ length: 18 }, (_, index) => ({
      relativePath: `style-${index}.zip`,
      sha256: "d".repeat(64),
    })),
  })}\n`);
  requireSuccess("/usr/bin/git", ["init", "-q"], { cwd: repository });
  requireSuccess("/usr/bin/git", ["config", "user.name", "Device Acceptance Tests"], { cwd: repository });
  requireSuccess("/usr/bin/git", ["config", "user.email", "device-acceptance@example.invalid"], { cwd: repository });
  requireSuccess("/usr/bin/git", ["add", "--all"], { cwd: repository });
  requireSuccess("/usr/bin/git", ["commit", "-q", "-m", "fixture"], { cwd: repository });
  const sourceCommit = requireSuccess("/usr/bin/git", ["rev-parse", "HEAD"], { cwd: repository }).stdout.trim();
  const sourceTree = requireSuccess("/usr/bin/git", ["rev-parse", "HEAD^{tree}"], { cwd: repository }).stdout.trim();

  const archiveApp = path.join(privateEvidence, "archive", "EusoTrip.app");
  const exportedApp = path.join(privateEvidence, "exported", "Payload", "EusoTrip.app");
  fs.mkdirSync(archiveApp, { recursive: true });
  fs.mkdirSync(exportedApp, { recursive: true });
  fs.writeFileSync(path.join(archiveApp, "Info.plist"), "archive");
  fs.writeFileSync(path.join(exportedApp, "Info.plist"), "exported");
  const ipa = path.join(privateEvidence, "EusoTrip.ipa");
  writePrivate(ipa, "exact ipa bytes");
  const ladderFile = path.join(privateEvidence, "release-ladder.json");
  const captureFile = path.join(privateEvidence, "radio-silent.pcap");
  const summaryFile = path.join(privateEvidence, "network-summary.json");
  const evidenceFile = path.join(privateEvidence, "device-acceptance.json");

  const baselineLadder = {
    schemaVersion: 3,
    version: "9.1.0",
    build: "901",
    bundleId: "com.app.eusotrip",
    sourceCommit,
    sourceTree,
    releaseXcconfigSha256: "f".repeat(64),
    releaseStartedAt: "2026-09-01T01:00:00Z",
    githubRepository: "diegoenterprises/eusotrip-ios",
    githubBranch: "main",
    githubRequiredCheck: "HERE Offline Source Contract",
    githubReleaseEnvironment: "here-offline-release",
    githubGovernanceVerifiedAt: "2026-09-01T01:00:00Z",
    githubEnvironmentDeploymentId: 4242,
    githubEnvironmentDeploymentStatusId: 4343,
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
    exported: "pass",
    uploaded: "pass",
    processing: "pass",
    appStoreConnectAppId: "123456789",
    appStoreConnectBuildId: "asc-build-901",
    deviceAcceptance: "pending",
    availableInTestFlight: "pass",
  };
  const requiredChecks = {
    regionInstalledOnline: true,
    forceQuit: true,
    airplaneModeEnabled: true,
    rebootedAfterAirplaneMode: true,
    coldLaunchSucceeded: true,
    nativeVectorPanZoom: true,
    offlinePlaceAddressCategorySearch: true,
    dimensionedTruckRoute: true,
    visualGuidance: true,
    installedTTSVoice: true,
    gpsProgression: true,
    deviationDetected: true,
    localReroute: true,
    approachingBoundary: true,
    outsideCoverage: true,
    pauseResumeCancel: true,
    interruptedInstallRecovery: true,
    catalogUpdate: true,
    corruptionRepair: true,
    deleteRedownload: true,
    accountSwitchPurge: true,
    staleCanonicalRouteRejected: true,
    crossRebootRouteCacheFailsClosed: true,
    audioInterruptionRecovery: true,
  };

  const reset = ({ evidenceMutation = value => value, summaryMutation = value => value } = {}) => {
    writePrivate(ladderFile, `${JSON.stringify(baselineLadder)}\n`);
    writePrivate(captureFile, "sanitized fixture capture bytes");
    const captureSHA256 = hashReleaseArtifact(captureFile);
    const summary = summaryMutation({
      schemaVersion: 1,
      captureSHA256,
      hereSDKRequestCount: 0,
      unrelatedEusoTripRequestCount: 0,
      sanitizedBy: "network-reviewer-2",
    });
    const summaryBytes = Buffer.from(`${JSON.stringify(summary)}\n`);
    writePrivate(summaryFile, summaryBytes);
    const evidence = evidenceMutation({
      schemaVersion: 1,
      status: "approved",
      sourceCommit,
      sourceTree,
      version: baselineLadder.version,
      build: baselineLadder.build,
      bundleId: baselineLadder.bundleId,
      appStoreConnectAppId: baselineLadder.appStoreConnectAppId,
      appStoreConnectBuildId: baselineLadder.appStoreConnectBuildId,
      githubEnvironmentDeploymentId: baselineLadder.githubEnvironmentDeploymentId,
      githubEnvironmentDeploymentStatusId: baselineLadder.githubEnvironmentDeploymentStatusId,
      exportedIPASha256: baselineLadder.exportedIPASha256,
      exportedAppTreeSha256: baselineLadder.exportedAppTreeSha256,
      hereSDK: {
        version: "4.27.2.0",
        archiveSHA256: "a".repeat(64),
        frameworkTreeSHA256: "b".repeat(64),
        legalNoticeSHA256: "c".repeat(64),
        styleManifestSHA256: hashReleaseArtifact(styleManifestFile),
      },
      device: { modelIdentifier: "iPhone18,1", osVersion: "27.0" },
      region: { regionID: "here-region-illinois", catalogVersion: "catalog-2026-09", installedBytes: 1048576 },
      runStartedAt: "2026-09-01T01:20:00Z",
      runEndedAt: "2026-09-01T01:40:00Z",
      checks: requiredChecks,
      network: {
        captureSHA256,
        summarySHA256: hashBytes(summaryBytes),
        hereSDKRequestCount: 0,
        captureStartedAt: "2026-09-01T01:15:00Z",
        captureEndedAt: "2026-09-01T01:45:00Z",
      },
      performedBy: "device-operator-1",
      approvedBy: "independent-approver-2",
      approvedAt: "2026-09-01T01:50:00Z",
    });
    writePrivate(evidenceFile, `${JSON.stringify(evidence)}\n`);
  };
  const verify = () => verifyAndRecordDeviceAcceptance({
    evidenceFile,
    ladderFile,
    captureFile,
    networkSummaryFile: summaryFile,
    repositoryRoot: repository,
  });

  reset();
  const hashes = verify();
  assert.match(hashes.evidenceSha256, /^[a-f0-9]{64}$/);
  assert.equal(JSON.parse(fs.readFileSync(ladderFile, "utf8")).deviceAcceptance, "pass");
  console.log("ok - exact processed build records complete independent device acceptance");

  reset({ evidenceMutation: value => ({ ...value, approvedBy: value.performedBy }) });
  assert.throws(verify, /independently approved/);
  console.log("ok - device operator cannot self-approve");

  reset({ evidenceMutation: value => ({ ...value, checks: { ...value.checks, gpsProgression: false } }) });
  assert.throws(verify, /incomplete/);
  console.log("ok - one missing physical-device check fails closed");

  reset();
  fs.appendFileSync(captureFile, "tamper");
  assert.throws(verify, /incomplete/);
  console.log("ok - capture substitution is rejected");

  reset({ summaryMutation: value => ({ ...value, authorizationHeaders: ["forbidden"] }) });
  assert.throws(verify, /forbidden raw or identifying fields/);
  console.log("ok - unsanitized network summary fields are rejected");

  reset({ evidenceMutation: value => ({ ...value, approvedAt: "2099-01-01T00:00:00Z" }) });
  assert.throws(verify, /future-dated/);
  console.log("ok - future-dated device approval is rejected");

  reset();
  const lateGovernance = {
    ...baselineLadder,
    githubGovernanceVerifiedAt: "2026-09-01T01:16:00Z",
  };
  writePrivate(ladderFile, `${JSON.stringify(lateGovernance)}\n`);
  assert.throws(verify, /chronology/);
  console.log("ok - capture cannot precede release governance verification");
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}

console.log("HERE offline device acceptance regression harness passed: 7 cases.");
