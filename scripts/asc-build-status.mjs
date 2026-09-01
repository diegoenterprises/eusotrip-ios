#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fetchJSON, mintToken } from "./asc-latest-build.mjs";

const reportFatal = error => {
  console.error(error instanceof Error ? error.message : "App Store Connect status check failed");
  process.exit(1);
};
process.on("uncaughtException", reportFatal);
process.on("unhandledRejection", reportFatal);

const value = (name, fallbackName) => process.env[name]?.trim() || process.env[fallbackName]?.trim();
const required = (name, fallbackName) => {
  const resolved = value(name, fallbackName);
  if (!resolved) throw new Error(`Missing ${name}${fallbackName ? ` (or ${fallbackName})` : ""}`);
  return resolved;
};
const arg = (name, fallback = null) => {
  const prefix = `--${name}=`;
  return process.argv.find((item) => item.startsWith(prefix))?.slice(prefix.length) ?? fallback;
};

const keyId = required("ASC_API_KEY_ID", "ASC_KEY_ID");
const issuerId = required("ASC_API_KEY_ISSUER", "ASC_ISSUER_ID");
const keyPath = path.resolve(required("ASC_API_KEY_PATH", "ASC_PRIVATE_KEY_PATH"));
const appId = arg("app-id", process.env.ASC_APP_ID?.trim());
const explicitTargetBuild = arg("build");
const ladderArgument = arg("ladder");
const ladderPath = ladderArgument ? path.resolve(ladderArgument) : null;
const wait = process.argv.includes("--wait");
const requireGroup = process.argv.includes("--require-group");
const boundedSeconds = (name, fallback, minimum, maximum) => {
  const seconds = Number(arg(name, fallback));
  if (!Number.isFinite(seconds) || seconds < minimum || seconds > maximum) {
    throw new Error(`--${name} must be between ${minimum} and ${maximum} seconds`);
  }
  return seconds * 1000;
};
const timeoutMs = boundedSeconds("timeout-seconds", "1800", 1, 86_400);
const intervalMs = boundedSeconds("interval-seconds", "20", 1, 300);
if (intervalMs > timeoutMs) throw new Error("Polling interval cannot exceed the timeout");

if (!appId) throw new Error("Missing --app-id or ASC_APP_ID");
if (!/^[1-9][0-9]*$/.test(appId)) {
  throw new Error("App Store Connect app ID must be a positive integer");
}

const keyConfiguration = { keyId, issuerId, privateKeyPath: keyPath };
// Validate the private file, identifier formats, key type, and P-256 curve
// before making any network request. mintToken repeats this check when a
// fresh short-lived token is required during a longer processing poll.
mintToken(keyConfiguration);

function assertOwnerPrivate(metadata, label) {
  const currentUserID = typeof process.getuid === "function" ? process.getuid() : null;
  if ((metadata.mode & 0o077) !== 0 || (currentUserID != null && metadata.uid !== currentUserID)) {
    throw new Error(`${label} must be owned by the release user with no group/other access`);
  }
}

function readBoundLadder() {
  if (!ladderPath) return null;
  if (!fs.existsSync(ladderPath)) throw new Error("The requested release ladder does not exist");
  const directory = path.dirname(ladderPath);
  const directoryMetadata = fs.lstatSync(directory);
  if (!directoryMetadata.isDirectory() || directoryMetadata.isSymbolicLink()) {
    throw new Error("The release ladder directory must be one real directory");
  }
  assertOwnerPrivate(directoryMetadata, "The release ladder directory");
  const metadata = fs.lstatSync(ladderPath);
  if (!metadata.isFile() || metadata.isSymbolicLink()) {
    throw new Error("The release ladder must be one owner-private regular file");
  }
  assertOwnerPrivate(metadata, "The release ladder");
  if (metadata.size > 1024 * 1024) throw new Error("The release ladder exceeds 1 MiB");
  const descriptor = fs.openSync(
    ladderPath,
    fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW,
  );
  let bytes;
  try {
    const opened = fs.fstatSync(descriptor);
    if (!opened.isFile() || opened.dev !== metadata.dev || opened.ino !== metadata.ino) {
      throw new Error("The release ladder changed while it was opened");
    }
    bytes = fs.readFileSync(descriptor);
    const final = fs.fstatSync(descriptor);
    if (final.size !== opened.size || final.mtimeMs !== opened.mtimeMs || final.ctimeMs !== opened.ctimeMs) {
      throw new Error("The release ladder changed while it was read");
    }
  } finally {
    fs.closeSync(descriptor);
  }
  const ladder = JSON.parse(bytes.toString("utf8"));
  if (
    ladder.schemaVersion !== 3 ||
    typeof ladder.build !== "string" ||
    !/^[1-9][0-9]*$/.test(ladder.build) ||
    typeof ladder.version !== "string" ||
    !/^[0-9]+(?:\.[0-9]+){1,3}$/.test(ladder.version) ||
    typeof ladder.bundleId !== "string" ||
    !/^[A-Za-z0-9.-]{3,255}$/.test(ladder.bundleId) ||
    !/^[a-f0-9]{40}$/.test(String(ladder.sourceCommit ?? "")) ||
    !/^[a-f0-9]{40}$/.test(String(ladder.sourceTree ?? ""))
  ) {
    throw new Error("The release ladder identity is invalid");
  }
  return ladder;
}

const initialLadder = readBoundLadder();
if (initialLadder && explicitTargetBuild && explicitTargetBuild !== initialLadder.build) {
  throw new Error("--build does not match the exact build recorded by --ladder");
}
const targetBuild = explicitTargetBuild ?? initialLadder?.build ?? null;
const targetVersion = initialLadder?.version ?? null;

async function api(urlPath) {
  return fetchJSON(fetch, mintToken(keyConfiguration), urlPath);
}

let appIdentityVerified = false;
async function verifyAppIdentity() {
  if (!initialLadder || appIdentityVerified) return;
  const response = await api(`/v1/apps/${encodeURIComponent(appId)}`);
  if (response.data?.attributes?.bundleId !== initialLadder.bundleId) {
    throw new Error("App Store Connect app does not match the ladder bundle identifier");
  }
  appIdentityVerified = true;
}

async function currentStatus() {
  await verifyAppIdentity();
  const query = new URLSearchParams({
    "filter[app]": appId,
    sort: "-uploadedDate",
    limit: "200",
    include: "preReleaseVersion",
  });
  const buildRows = [];
  const includedRows = [];
  let nextBuildPage = `/v1/builds?${query}`;
  let buildPageCount = 0;
  while (nextBuildPage) {
    if (++buildPageCount > 1_000) throw new Error("App Store Connect build pagination exceeded 1,000 pages");
    const page = await api(nextBuildPage);
    buildRows.push(...(page.data ?? []));
    includedRows.push(...(page.included ?? []));
    nextBuildPage = page.links?.next ?? null;
  }
  const build = targetBuild
    ? buildRows.find(item => {
        if (String(item.attributes?.version) !== String(targetBuild)) return false;
        if (!targetVersion) return true;
        const preReleaseId = item.relationships?.preReleaseVersion?.data?.id;
        const preRelease = includedRows.find(candidate => candidate.id === preReleaseId);
        return preRelease?.attributes?.version === targetVersion;
      })
    : buildRows[0];
  if (!build) {
    return { appId, build: targetBuild, found: false, processingState: "PENDING", betaGroups: [] };
  }
  const groupQuery = new URLSearchParams({
    "filter[builds]": build.id,
    limit: "50",
  });
  const groupRows = [];
  let nextGroupPage = `/v1/betaGroups?${groupQuery}`;
  let groupPageCount = 0;
  while (nextGroupPage) {
    if (++groupPageCount > 1_000) throw new Error("App Store Connect group pagination exceeded 1,000 pages");
    const page = await api(nextGroupPage);
    groupRows.push(...(page.data ?? []));
    nextGroupPage = page.links?.next ?? null;
  }
  const preReleaseId = build.relationships?.preReleaseVersion?.data?.id;
  const preRelease = includedRows.find((item) => item.id === preReleaseId);
  const status = {
    appId,
    id: build.id,
    build: String(build.attributes?.version ?? ""),
    version: preRelease?.attributes?.version ?? null,
    uploadedDate: build.attributes?.uploadedDate ?? null,
    processingState: build.attributes?.processingState ?? "UNKNOWN",
    expired: Boolean(build.attributes?.expired),
    betaGroups: groupRows.map((group) => ({ id: group.id, name: group.attributes?.name ?? null })),
    found: true,
  };
  if (
    initialLadder &&
    (status.build !== initialLadder.build || status.version !== targetVersion)
  ) {
    throw new Error(
      "App Store Connect returned a build that does not match the exact ladder build and version"
    );
  }
  return status;
}

function updateLadder(status) {
  if (!ladderPath) return;
  const ladder = readBoundLadder();
  if (
    !initialLadder ||
    ladder.build !== initialLadder.build ||
    ladder.version !== initialLadder.version ||
    ladder.sourceCommit !== initialLadder.sourceCommit ||
    ladder.sourceTree !== initialLadder.sourceTree ||
    ladder.bundleId !== initialLadder.bundleId ||
    (ladder.appStoreConnectAppId && ladder.appStoreConnectAppId !== appId)
  ) {
    throw new Error("The release ladder identity changed while App Store Connect was polled");
  }
  if (status.found && (status.build !== ladder.build || status.version !== ladder.version)) {
    throw new Error("App Store Connect status cannot update a different ladder build");
  }
  if (status.processingState === "VALID") ladder.processing = "pass";
  else if (["FAILED", "INVALID"].includes(status.processingState)) ladder.processing = "fail";
  else ladder.processing = "pending";
  ladder.availableInTestFlight = status.processingState === "VALID" && status.betaGroups.length > 0 ? "pass" : "pending";
  ladder.appStoreConnectAppId = appId;
  ladder.appStoreConnectBuildId = status.id ?? null;
  ladder.betaGroups = status.betaGroups;
  const ladderDirectory = path.dirname(ladderPath);
  const temporaryDirectory = fs.mkdtempSync(path.join(ladderDirectory, ".asc-ladder-"));
  fs.chmodSync(temporaryDirectory, 0o700);
  const temporary = path.join(temporaryDirectory, path.basename(ladderPath));
  let descriptor = null;
  try {
    descriptor = fs.openSync(
      temporary,
      fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL,
      0o600,
    );
    fs.writeFileSync(descriptor, `${JSON.stringify(ladder, null, 2)}\n`);
    fs.fsyncSync(descriptor);
    fs.closeSync(descriptor);
    descriptor = null;
    fs.renameSync(temporary, ladderPath);
    const directoryDescriptor = fs.openSync(ladderDirectory, fs.constants.O_RDONLY);
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

const startedAt = Date.now();
while (true) {
  const status = await currentStatus();
  updateLadder(status);
  console.log(JSON.stringify(status));

  if (["FAILED", "INVALID"].includes(status.processingState)) process.exit(1);
  const ready = status.processingState === "VALID" && (!requireGroup || status.betaGroups.length > 0);
  if (ready || !wait) process.exit(0);
  if (Date.now() - startedAt >= timeoutMs) process.exit(2);
  await new Promise((resolve) => setTimeout(resolve, intervalMs));
}
