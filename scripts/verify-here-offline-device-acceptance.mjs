#!/usr/bin/env node

import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { hashReleaseArtifact } from "./hash-release-artifact.mjs";

const sha256Pattern = /^[a-f0-9]{64}$/;
const gitObjectPattern = /^[a-f0-9]{40}$/;
const maximumClockSkewMilliseconds = 5 * 60 * 1000;
const requiredChecks = [
  "regionInstalledOnline",
  "forceQuit",
  "airplaneModeEnabled",
  "rebootedAfterAirplaneMode",
  "coldLaunchSucceeded",
  "nativeVectorPanZoom",
  "offlinePlaceAddressCategorySearch",
  "dimensionedTruckRoute",
  "visualGuidance",
  "installedTTSVoice",
  "gpsProgression",
  "deviationDetected",
  "localReroute",
  "approachingBoundary",
  "outsideCoverage",
  "pauseResumeCancel",
  "interruptedInstallRecovery",
  "catalogUpdate",
  "corruptionRepair",
  "deleteRedownload",
  "accountSwitchPurge",
  "staleCanonicalRouteRejected",
  "crossRebootRouteCacheFailsClosed",
  "audioInterruptionRecovery",
];
const forbiddenSummaryKeys = /(?:udid|serial|cookie|authorization|header|payload|packetbytes|rawaddress)/i;

function argument(name, argv = process.argv.slice(2)) {
  const prefix = `--${name}=`;
  return argv.find(value => value.startsWith(prefix))?.slice(prefix.length) ?? null;
}

function assertOwnerPrivate(metadata, label) {
  const currentUserID = typeof process.getuid === "function" ? process.getuid() : null;
  if ((metadata.mode & 0o077) !== 0 || (currentUserID != null && metadata.uid !== currentUserID)) {
    throw new Error(`${label} must be owner-private and owned by the release user`);
  }
}

function openSecureFile(file, label, maximumBytes) {
  if (!path.isAbsolute(file)) throw new Error(`${label} path must be absolute`);
  const directory = path.dirname(file);
  const directoryMetadata = fs.lstatSync(directory, { throwIfNoEntry: false });
  if (!directoryMetadata?.isDirectory() || directoryMetadata.isSymbolicLink()) {
    throw new Error(`${label} directory must be one real directory`);
  }
  assertOwnerPrivate(directoryMetadata, `${label} directory`);
  const metadata = fs.lstatSync(file, { throwIfNoEntry: false });
  if (!metadata?.isFile() || metadata.isSymbolicLink()) {
    throw new Error(`${label} must be one regular non-symlink file`);
  }
  assertOwnerPrivate(metadata, label);
  if (metadata.size > maximumBytes) throw new Error(`${label} exceeds its safety limit`);
  const descriptor = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
  const opened = fs.fstatSync(descriptor);
  if (!opened.isFile() || opened.dev !== metadata.dev || opened.ino !== metadata.ino) {
    fs.closeSync(descriptor);
    throw new Error(`${label} changed while it was opened`);
  }
  return { descriptor, opened };
}

function readSecureFile(file, label, maximumBytes = 1024 * 1024) {
  const { descriptor, opened } = openSecureFile(file, label, maximumBytes);
  try {
    const bytes = fs.readFileSync(descriptor);
    const final = fs.fstatSync(descriptor);
    if (final.size !== opened.size || final.mtimeMs !== opened.mtimeMs || final.ctimeMs !== opened.ctimeMs) {
      throw new Error(`${label} changed while it was read`);
    }
    return bytes;
  } finally {
    fs.closeSync(descriptor);
  }
}

function hashSecureFile(file, label, maximumBytes = 8 * 1024 * 1024 * 1024) {
  const { descriptor, opened } = openSecureFile(file, label, maximumBytes);
  const hash = crypto.createHash("sha256");
  const buffer = Buffer.allocUnsafe(1024 * 1024);
  let offset = 0;
  try {
    while (offset < opened.size) {
      const bytesRead = fs.readSync(descriptor, buffer, 0, Math.min(buffer.length, opened.size - offset), offset);
      if (bytesRead <= 0) throw new Error(`${label} ended before its recorded size`);
      hash.update(buffer.subarray(0, bytesRead));
      offset += bytesRead;
    }
    const final = fs.fstatSync(descriptor);
    if (final.size !== opened.size || final.mtimeMs !== opened.mtimeMs || final.ctimeMs !== opened.ctimeMs) {
      throw new Error(`${label} changed while it was hashed`);
    }
    return hash.digest("hex");
  } finally {
    fs.closeSync(descriptor);
  }
}

function readSecureJSON(file, label, maximumBytes) {
  try {
    return JSON.parse(readSecureFile(file, label, maximumBytes).toString("utf8"));
  } catch (error) {
    if (error instanceof SyntaxError) throw new Error(`${label} is not valid JSON`);
    throw error;
  }
}

function readRepositoryFile(repositoryRoot, relativePath, label) {
  const root = fs.realpathSync(repositoryRoot);
  const file = path.resolve(root, relativePath);
  const metadata = fs.lstatSync(file, { throwIfNoEntry: false });
  if (!metadata?.isFile() || metadata.isSymbolicLink()) {
    throw new Error(`${label} must be one in-repository regular non-symlink file`);
  }
  const resolved = fs.realpathSync(file);
  if (resolved !== root && !resolved.startsWith(`${root}${path.sep}`)) {
    throw new Error(`${label} escapes the release source repository`);
  }
  const descriptor = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
  try {
    const opened = fs.fstatSync(descriptor);
    if (!opened.isFile() || opened.dev !== metadata.dev || opened.ino !== metadata.ino) {
      throw new Error(`${label} changed while it was opened`);
    }
    const bytes = fs.readFileSync(descriptor);
    const final = fs.fstatSync(descriptor);
    if (final.size !== opened.size || final.mtimeMs !== opened.mtimeMs || final.ctimeMs !== opened.ctimeMs) {
      throw new Error(`${label} changed while it was read`);
    }
    return bytes;
  } finally {
    fs.closeSync(descriptor);
  }
}

function parseTime(value, label) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/.test(value)) {
    throw new Error(`${label} must be an RFC 3339 UTC timestamp`);
  }
  const parsed = Date.parse(value);
  if (!Number.isFinite(parsed)) throw new Error(`${label} is invalid`);
  return parsed;
}

function validActor(value) {
  return typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9._:@-]{2,127}$/.test(value);
}

function inspectSummaryKeys(value, prefix = "summary") {
  if (!value || typeof value !== "object") return;
  for (const [key, child] of Object.entries(value)) {
    if (forbiddenSummaryKeys.test(key)) throw new Error(`${prefix} contains forbidden raw or identifying fields`);
    inspectSummaryKeys(child, `${prefix}.${key}`);
  }
}

function validateLadder(ladder) {
  if (
    ladder.schemaVersion !== 3 ||
    typeof ladder.version !== "string" ||
    !/^[0-9]+(?:\.[0-9]+){1,3}$/.test(ladder.version) ||
    typeof ladder.build !== "string" ||
    !/^[1-9][0-9]*$/.test(ladder.build) ||
    ladder.bundleId !== "com.app.eusotrip" ||
    ladder.githubRepository !== "diegoenterprises/eusotrip-ios" ||
    ladder.githubBranch !== "main" ||
    ladder.githubRequiredCheck !== "HERE Offline Source Contract" ||
    ladder.githubReleaseEnvironment !== "here-offline-release" ||
    !gitObjectPattern.test(String(ladder.sourceCommit ?? "")) ||
    !gitObjectPattern.test(String(ladder.sourceTree ?? "")) ||
    ladder.compiled !== "pass" ||
    ladder.archived !== "pass" ||
    ladder.tested !== "pass" ||
    ladder.hereOfflineContract !== "pass" ||
    ladder.exported !== "pass" ||
    ladder.uploaded !== "pass" ||
    ladder.processing !== "pass" ||
    !["pending", "pass"].includes(ladder.deviceAcceptance)
  ) {
    throw new Error("Release ladder is not an exact processed schema-3 HERE release");
  }
  for (const [pathField, hashField] of [
    ["exportedIPAPath", "exportedIPASha256"],
    ["exportedAppPath", "exportedAppTreeSha256"],
  ]) {
    if (!path.isAbsolute(ladder[pathField] ?? "") || !sha256Pattern.test(ladder[hashField] ?? "")) {
      throw new Error("Release ladder artifact identity is incomplete");
    }
    const artifactMetadata = fs.lstatSync(ladder[pathField], { throwIfNoEntry: false });
    const correctType = pathField === "exportedIPAPath"
      ? artifactMetadata?.isFile()
      : artifactMetadata?.isDirectory();
    if (!correctType || artifactMetadata.isSymbolicLink()) {
      throw new Error("Release ladder artifact is not the expected regular file or app directory");
    }
    if (hashReleaseArtifact(ladder[pathField]) !== ladder[hashField]) {
      throw new Error("Release ladder artifact no longer matches its recorded SHA-256");
    }
  }
}

function atomicWriteLadder(file, ladder) {
  const directory = path.dirname(file);
  const temporaryDirectory = fs.mkdtempSync(path.join(directory, ".device-acceptance-"));
  fs.chmodSync(temporaryDirectory, 0o700);
  const temporary = path.join(temporaryDirectory, path.basename(file));
  let descriptor = null;
  try {
    descriptor = fs.openSync(temporary, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL, 0o600);
    fs.writeFileSync(descriptor, `${JSON.stringify(ladder, null, 2)}\n`);
    fs.fsyncSync(descriptor);
    fs.closeSync(descriptor);
    descriptor = null;
    fs.renameSync(temporary, file);
    const directoryDescriptor = fs.openSync(directory, fs.constants.O_RDONLY);
    try {
      fs.fsyncSync(directoryDescriptor);
    } finally {
      fs.closeSync(directoryDescriptor);
    }
  } finally {
    if (descriptor != null) fs.closeSync(descriptor);
    fs.rmSync(temporaryDirectory, { recursive: true, force: true });
  }
}

export function verifyAndRecordDeviceAcceptance({
  evidenceFile,
  ladderFile,
  captureFile,
  networkSummaryFile,
  repositoryRoot = path.resolve(import.meta.dirname, ".."),
}) {
  const ladder = readSecureJSON(ladderFile, "release ladder", 1024 * 1024);
  validateLadder(ladder);
  const initialIdentity = JSON.stringify([
    ladder.version,
    ladder.build,
    ladder.bundleId,
    ladder.sourceCommit,
    ladder.sourceTree,
    ladder.exportedIPASha256,
    ladder.exportedAppTreeSha256,
  ]);

  const git = arguments_ => spawnSync("/usr/bin/git", ["-C", repositoryRoot, ...arguments_], { encoding: "utf8" });
  const head = git(["rev-parse", "HEAD"]);
  const tree = git(["rev-parse", "HEAD^{tree}"]);
  const status = git(["status", "--porcelain", "--untracked-files=normal"]);
  if (head.status !== 0 || tree.status !== 0 || status.status !== 0 || status.stdout !== "" ||
      head.stdout.trim() !== ladder.sourceCommit || tree.stdout.trim() !== ladder.sourceTree) {
    throw new Error("Current source does not exactly match the release ladder identity");
  }

  const sdkManifestRelativePath = "EusoTrip/Services/HereMaps/Offline/HERE_SDK_SUPPLY_CHAIN.json";
  const styleManifestRelativePath = "EusoTrip/Services/HereMaps/Offline/HERE_NATIVE_STYLE_SUPPLY_CHAIN.json";
  const sdkManifestBytes = readRepositoryFile(repositoryRoot, sdkManifestRelativePath, "HERE SDK manifest");
  const styleManifestBytes = readRepositoryFile(repositoryRoot, styleManifestRelativePath, "HERE style manifest");
  const sdk = JSON.parse(sdkManifestBytes.toString("utf8"));
  const styles = JSON.parse(styleManifestBytes.toString("utf8"));
  if (
    sdk.status !== "approved" ||
    !sha256Pattern.test(sdk.archiveSHA256 ?? "") ||
    !sha256Pattern.test(sdk.frameworkTreeSHA256 ?? "") ||
    !sha256Pattern.test(sdk.legalNoticeSHA256 ?? "") ||
    styles.status !== "approved" ||
    !Array.isArray(styles.entries) ||
    styles.entries.length !== 18 ||
    styles.entries.some(entry => !sha256Pattern.test(entry.sha256 ?? ""))
  ) {
    throw new Error("Approved HERE SDK and 18-style supply-chain manifests are required");
  }

  const evidenceBytes = readSecureFile(evidenceFile, "device acceptance evidence", 1024 * 1024);
  let evidence;
  try {
    evidence = JSON.parse(evidenceBytes.toString("utf8"));
  } catch {
    throw new Error("Device acceptance evidence is not valid JSON");
  }
  const summaryBytes = readSecureFile(networkSummaryFile, "sanitized network summary", 1024 * 1024);
  let summary;
  try {
    summary = JSON.parse(summaryBytes.toString("utf8"));
  } catch {
    throw new Error("Sanitized network summary is not valid JSON");
  }
  inspectSummaryKeys(summary);
  const captureSha256 = hashSecureFile(captureFile, "private network capture");
  const summarySha256 = crypto.createHash("sha256").update(summaryBytes).digest("hex");
  const evidenceSha256 = crypto.createHash("sha256").update(evidenceBytes).digest("hex");
  const styleManifestSha256 = crypto.createHash("sha256").update(styleManifestBytes).digest("hex");

  if (
    evidence.schemaVersion !== 1 ||
    evidence.status !== "approved" ||
    evidence.sourceCommit !== ladder.sourceCommit ||
    evidence.sourceTree !== ladder.sourceTree ||
    evidence.version !== ladder.version ||
    evidence.build !== ladder.build ||
    evidence.bundleId !== ladder.bundleId ||
    evidence.exportedIPASha256 !== ladder.exportedIPASha256 ||
    evidence.exportedAppTreeSha256 !== ladder.exportedAppTreeSha256 ||
    evidence.hereSDK?.version !== sdk.approvedVersion ||
    evidence.hereSDK?.archiveSHA256 !== sdk.archiveSHA256 ||
    evidence.hereSDK?.frameworkTreeSHA256 !== sdk.frameworkTreeSHA256 ||
    evidence.hereSDK?.legalNoticeSHA256 !== sdk.legalNoticeSHA256 ||
    evidence.hereSDK?.styleManifestSHA256 !== styleManifestSha256 ||
    !/^[A-Za-z0-9._:-]{2,128}$/.test(evidence.region?.regionID ?? "") ||
    !/^[A-Za-z0-9._:-]{2,128}$/.test(evidence.region?.catalogVersion ?? "") ||
    !Number.isSafeInteger(evidence.region?.installedBytes) || evidence.region.installedBytes <= 0 ||
    !/^iPhone[0-9]+,[0-9]+$/.test(evidence.device?.modelIdentifier ?? "") ||
    !/^\d+(?:\.\d+){1,2}$/.test(evidence.device?.osVersion ?? "") ||
    !validActor(evidence.performedBy) || !validActor(evidence.approvedBy) ||
    evidence.performedBy === evidence.approvedBy ||
    requiredChecks.some(check => evidence.checks?.[check] !== true) ||
    evidence.network?.captureSHA256 !== captureSha256 ||
    evidence.network?.summarySHA256 !== summarySha256 ||
    evidence.network?.hereSDKRequestCount !== 0 ||
    summary.schemaVersion !== 1 || summary.captureSHA256 !== captureSha256 ||
    summary.hereSDKRequestCount !== 0
  ) {
    throw new Error("Device acceptance evidence is incomplete, substituted, or not independently approved");
  }
  const releaseStartedAt = parseTime(ladder.releaseStartedAt, "releaseStartedAt");
  const githubGovernanceVerifiedAt = parseTime(
    ladder.githubGovernanceVerifiedAt,
    "githubGovernanceVerifiedAt",
  );
  const captureStartedAt = parseTime(evidence.network.captureStartedAt, "network.captureStartedAt");
  const runStartedAt = parseTime(evidence.runStartedAt, "runStartedAt");
  const runEndedAt = parseTime(evidence.runEndedAt, "runEndedAt");
  const captureEndedAt = parseTime(evidence.network.captureEndedAt, "network.captureEndedAt");
  const approvedAt = parseTime(evidence.approvedAt, "approvedAt");
  if (!(releaseStartedAt <= githubGovernanceVerifiedAt &&
        githubGovernanceVerifiedAt <= captureStartedAt && captureStartedAt <= runStartedAt &&
        runStartedAt <= runEndedAt && runEndedAt <= captureEndedAt && captureEndedAt <= approvedAt)) {
    throw new Error("Device acceptance chronology is invalid");
  }
  if (approvedAt > Date.now() + maximumClockSkewMilliseconds) {
    throw new Error("Device acceptance approval cannot be future-dated");
  }

  const currentLadder = readSecureJSON(ladderFile, "release ladder", 1024 * 1024);
  validateLadder(currentLadder);
  const currentIdentity = JSON.stringify([
    currentLadder.version,
    currentLadder.build,
    currentLadder.bundleId,
    currentLadder.sourceCommit,
    currentLadder.sourceTree,
    currentLadder.exportedIPASha256,
    currentLadder.exportedAppTreeSha256,
  ]);
  if (currentIdentity !== initialIdentity) throw new Error("Release ladder changed during device verification");
  currentLadder.deviceAcceptance = "pass";
  currentLadder.deviceAcceptanceEvidencePath = evidenceFile;
  currentLadder.deviceAcceptanceEvidenceSha256 = evidenceSha256;
  currentLadder.networkCapturePath = captureFile;
  currentLadder.networkCaptureSha256 = captureSha256;
  currentLadder.networkSummaryPath = networkSummaryFile;
  currentLadder.networkSummarySha256 = summarySha256;
  currentLadder.deviceModelIdentifier = evidence.device.modelIdentifier;
  currentLadder.deviceOSVersion = evidence.device.osVersion;
  currentLadder.testedRegionID = evidence.region.regionID;
  currentLadder.testedCatalogVersion = evidence.region.catalogVersion;
  currentLadder.deviceAcceptanceApprovedAt = evidence.approvedAt;
  currentLadder.deviceAcceptanceApprovedBy = evidence.approvedBy;
  atomicWriteLadder(ladderFile, currentLadder);
  return { evidenceSha256, captureSha256, summarySha256 };
}

function main() {
  const evidenceFile = argument("evidence");
  const ladderFile = argument("ladder");
  const captureFile = argument("capture");
  const networkSummaryFile = argument("network-summary");
  if (!evidenceFile || !ladderFile || !captureFile || !networkSummaryFile) {
    throw new Error("Usage: verify-here-offline-device-acceptance.mjs --evidence=/private/evidence.json --ladder=/private/release-ladder.json --capture=/private/capture.pcap --network-summary=/private/summary.json");
  }
  verifyAndRecordDeviceAcceptance({ evidenceFile, ladderFile, captureFile, networkSummaryFile });
  console.log("Exact-build HERE offline physical-device acceptance recorded.");
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  try {
    main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : "Device acceptance verification failed");
    process.exitCode = 1;
  }
}
