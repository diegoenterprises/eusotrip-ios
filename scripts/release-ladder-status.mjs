#!/usr/bin/env node
/**
 * Validate the exact, build-bound TestFlight release ladder. A collection of
 * green rung strings is insufficient: source identity and both distributable
 * artifacts must still match the hashes recorded before upload.
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { hashReleaseArtifact } from "./hash-release-artifact.mjs";

const fileArgument = process.argv.find(argument => argument.startsWith("--file="));
if (!fileArgument) {
  console.error("An exact release ladder is required: --file=/absolute/release-ladder.json");
  process.exit(2);
}
const file = path.resolve(fileArgument.slice("--file=".length));
const expectedArgument = name =>
  process.argv.find(argument => argument.startsWith(`--${name}=`))?.slice(name.length + 3);
const requiredRungs = [
  "compiled",
  "archived",
  "tested",
  "hereOfflineContract",
  "deviceAcceptance",
  "exported",
  "uploaded",
  "processing",
  "availableInTestFlight",
];
const allowed = new Set(["pass", "fail", "pending", "manual_confirm_required", "not_run"]);
const sha256Pattern = /^[a-f0-9]{64}$/;
const gitObjectPattern = /^[a-f0-9]{40}$/;
const maximumClockSkewMilliseconds = 5 * 60 * 1000;

if (!fs.existsSync(file)) {
  console.error(`Release ladder file not found: ${file}`);
  process.exit(2);
}
const ladderMetadata = fs.lstatSync(file);
const currentUserID = typeof process.getuid === "function" ? process.getuid() : null;
if (!ladderMetadata.isFile() || ladderMetadata.isSymbolicLink() ||
    (ladderMetadata.mode & 0o077) !== 0 ||
    (currentUserID != null && ladderMetadata.uid !== currentUserID) ||
    ladderMetadata.size > 1024 * 1024) {
  console.error("Release ladder must be one owner-private regular file.");
  process.exit(2);
}

let data;
let ladderDescriptor;
try {
  ladderDescriptor = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
  const opened = fs.fstatSync(ladderDescriptor);
  if (!opened.isFile() || opened.dev !== ladderMetadata.dev || opened.ino !== ladderMetadata.ino) {
    throw new Error("Release ladder changed while it was opened.");
  }
  const bytes = fs.readFileSync(ladderDescriptor);
  const final = fs.fstatSync(ladderDescriptor);
  if (final.size !== opened.size || final.mtimeMs !== opened.mtimeMs || final.ctimeMs !== opened.ctimeMs) {
    throw new Error("Release ladder changed while it was read.");
  }
  data = JSON.parse(bytes.toString("utf8"));
} catch {
  console.error("Unable to parse release ladder JSON.");
  process.exit(2);
} finally {
  if (ladderDescriptor != null) fs.closeSync(ladderDescriptor);
}

const errors = [];
if (data.schemaVersion !== 3) errors.push("unsupported release ladder schema");
if (typeof data.version !== "string" || !/^[0-9]+(?:\.[0-9]+){1,3}$/.test(data.version)) {
  errors.push("invalid release version");
}
if (typeof data.build !== "string" || !/^[1-9][0-9]*$/.test(data.build)) {
  errors.push("invalid release build");
}
if (typeof data.bundleId !== "string" || !/^[A-Za-z0-9.-]{3,255}$/.test(data.bundleId)) {
  errors.push("invalid release bundle identifier");
}
if (!gitObjectPattern.test(String(data.sourceCommit ?? ""))) errors.push("invalid source commit");
if (!gitObjectPattern.test(String(data.sourceTree ?? ""))) errors.push("invalid source tree");
if (
  typeof data.releaseConfigAttestationPath !== "string" ||
  !path.isAbsolute(data.releaseConfigAttestationPath) ||
  !sha256Pattern.test(String(data.releaseConfigAttestationSha256 ?? ""))
) {
  errors.push("invalid release config attestation identity");
}
const releaseStartedAt = Date.parse(String(data.releaseStartedAt ?? ""));
const githubGovernanceVerifiedAt = Date.parse(String(data.githubGovernanceVerifiedAt ?? ""));
if (!Number.isFinite(releaseStartedAt)) {
  errors.push("invalid release start time");
}
if (data.githubRepository !== "diegoenterprises/eusotrip-ios" ||
    data.githubBranch !== "main" ||
    data.githubRequiredCheck !== "HERE Offline Source Contract" ||
    data.githubReleaseEnvironment !== "here-offline-release" ||
    !Number.isFinite(githubGovernanceVerifiedAt)) {
  errors.push("invalid GitHub release-governance identity");
}
if (Number.isFinite(releaseStartedAt) && Number.isFinite(githubGovernanceVerifiedAt) &&
    (releaseStartedAt > githubGovernanceVerifiedAt ||
     githubGovernanceVerifiedAt > Date.now() + maximumClockSkewMilliseconds)) {
  errors.push("invalid GitHub release-governance chronology");
}
for (const key of requiredRungs) {
  if (!(key in data)) errors.push(`missing key ${key}`);
  else if (!allowed.has(String(data[key]))) errors.push(`invalid ${key}: ${data[key]}`);
}

for (const [argumentName, field] of [
  ["version", "version"],
  ["build", "build"],
  ["commit", "sourceCommit"],
]) {
  const expected = expectedArgument(argumentName);
  if (expected && String(data[field]) !== expected) {
    errors.push(`${field} does not match the requested release identity`);
  }
}

const repositoryRoot = path.resolve(import.meta.dirname, "..");
const git = arguments_ => spawnSync("/usr/bin/git", ["-C", repositoryRoot, ...arguments_], {
  encoding: "utf8",
});
const head = git(["rev-parse", "HEAD"]);
const tree = git(["rev-parse", "HEAD^{tree}"]);
const status = git(["status", "--porcelain", "--untracked-files=normal"]);
if (
  head.status !== 0 ||
  tree.status !== 0 ||
  status.status !== 0 ||
  head.stdout.trim() !== data.sourceCommit ||
  tree.stdout.trim() !== data.sourceTree ||
  status.stdout.length !== 0
) {
  errors.push("current source worktree does not exactly match the recorded release commit and tree");
}

function verifyArtifact(pathField, hashField, label) {
  const artifactPath = data[pathField];
  const expectedHash = data[hashField];
  if (
    typeof artifactPath !== "string" ||
    !path.isAbsolute(artifactPath) ||
    !sha256Pattern.test(String(expectedHash ?? "")) ||
    !fs.existsSync(artifactPath)
  ) {
    errors.push(`${label} path or SHA-256 is missing`);
    return;
  }
  try {
    if (hashReleaseArtifact(artifactPath) !== expectedHash) {
      errors.push(`${label} no longer matches its recorded SHA-256`);
    }
  } catch {
    errors.push(`${label} could not be hashed safely`);
  }
}

function verifyPrivateEvidence(pathField, hashField, label) {
  const evidencePath = data[pathField];
  const expectedHash = data[hashField];
  if (typeof evidencePath !== "string" || !path.isAbsolute(evidencePath) ||
      !sha256Pattern.test(String(expectedHash ?? ""))) {
    errors.push(`${label} path or SHA-256 is missing`);
    return;
  }
  try {
    const metadata = fs.lstatSync(evidencePath);
    const currentUserID = typeof process.getuid === "function" ? process.getuid() : null;
    if (!metadata.isFile() || metadata.isSymbolicLink() || (metadata.mode & 0o077) !== 0 ||
        (currentUserID != null && metadata.uid !== currentUserID) ||
        hashReleaseArtifact(evidencePath) !== expectedHash) {
      errors.push(`${label} no longer matches its owner-private recorded SHA-256`);
    }
  } catch {
    errors.push(`${label} could not be verified safely`);
  }
}

if (data.archived === "pass" || data.hereOfflineContract === "pass") {
  verifyArtifact("archiveAppPath", "archiveAppTreeSha256", "archived app");
}
if (data.exported === "pass" || data.hereOfflineContract === "pass") {
  verifyArtifact("exportedIPAPath", "exportedIPASha256", "exported IPA");
  verifyArtifact("exportedAppPath", "exportedAppTreeSha256", "exported app");
}
if (typeof data.releaseConfigAttestationPath === "string" &&
    sha256Pattern.test(String(data.releaseConfigAttestationSha256 ?? ""))) {
  try {
    const attestationMetadata = fs.lstatSync(data.releaseConfigAttestationPath);
    const currentUserID = typeof process.getuid === "function" ? process.getuid() : null;
    if (!attestationMetadata.isFile() || attestationMetadata.isSymbolicLink() ||
        (attestationMetadata.mode & 0o077) !== 0 ||
        (currentUserID != null && attestationMetadata.uid !== currentUserID) ||
        hashReleaseArtifact(data.releaseConfigAttestationPath) !== data.releaseConfigAttestationSha256) {
      errors.push("release config attestation no longer matches its recorded SHA-256");
    }
  } catch {
    errors.push("release config attestation could not be verified");
  }
}
if (data.deviceAcceptance === "pass") {
  verifyPrivateEvidence(
    "deviceAcceptanceEvidencePath",
    "deviceAcceptanceEvidenceSha256",
    "device acceptance evidence",
  );
  verifyPrivateEvidence("networkCapturePath", "networkCaptureSha256", "private network capture");
  verifyPrivateEvidence("networkSummaryPath", "networkSummarySha256", "sanitized network summary");
  const deviceAcceptanceApprovedAt = Date.parse(String(data.deviceAcceptanceApprovedAt ?? ""));
  if (!/^iPhone[0-9]+,[0-9]+$/.test(String(data.deviceModelIdentifier ?? "")) ||
      !/^\d+(?:\.\d+){1,2}$/.test(String(data.deviceOSVersion ?? "")) ||
      !Number.isFinite(deviceAcceptanceApprovedAt) ||
      typeof data.deviceAcceptanceApprovedBy !== "string" ||
      data.deviceAcceptanceApprovedBy.length < 3) {
    errors.push("device acceptance approval metadata is incomplete");
  }
  if (Number.isFinite(deviceAcceptanceApprovedAt) &&
      (!Number.isFinite(releaseStartedAt) || !Number.isFinite(githubGovernanceVerifiedAt) ||
       deviceAcceptanceApprovedAt < githubGovernanceVerifiedAt ||
       deviceAcceptanceApprovedAt > Date.now() + maximumClockSkewMilliseconds)) {
    errors.push("device acceptance approval chronology is invalid");
  }
}

console.log(
  `Release ${data.version ?? "invalid"} (${data.build ?? "invalid"}); bundle=${data.bundleId ?? "invalid"}; commit=${String(data.sourceCommit ?? "invalid").slice(0, 12)}`
);
console.log("Release ladder");
for (const key of requiredRungs) {
  console.log(`- ${key}: ${data[key] ?? "missing"}`);
}

if (errors.length > 0) {
  console.error(errors.join("\n"));
  process.exit(1);
}

const fullyAvailable = requiredRungs.every(key => data[key] === "pass");
if (!fullyAvailable) {
  console.error("Release is not TestFlight-available yet. Do not describe it as shipped.");
  process.exit(1);
}

console.log("This exact source and exported artifact are available in TestFlight.");
