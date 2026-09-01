#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const REQUIRED_CREDENTIAL_CLASSES = [
  "here_maps_js_api_key",
  "here_sdk_navigate_access_key_id",
  "here_sdk_navigate_access_key_secret",
];
const maximumClockSkewMilliseconds = 5 * 60 * 1000;
const maximumApprovalLifetimeMilliseconds = 24 * 60 * 60 * 1000;

function argument(name, argv = process.argv.slice(2)) {
  const prefix = `--${name}=`;
  return argv.find(value => value.startsWith(prefix))?.slice(prefix.length) ?? null;
}

function validIdentifier(value) {
  return typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9._:-]{2,127}$/.test(value);
}

function parseTime(value, label) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/.test(value)) {
    throw new Error(`${label} must be an RFC 3339 UTC timestamp`);
  }
  const parsed = Date.parse(value);
  if (!Number.isFinite(parsed)) throw new Error(`${label} is invalid`);
  return parsed;
}

function readOwnerPrivateFile(file, label, maximumBytes) {
  if (!path.isAbsolute(file)) throw new Error(`${label} path must be absolute`);
  const directory = path.dirname(file);
  const directoryMetadata = fs.lstatSync(directory, { throwIfNoEntry: false });
  const currentUserID = typeof process.getuid === "function" ? process.getuid() : null;
  if (!directoryMetadata?.isDirectory() || directoryMetadata.isSymbolicLink() ||
      (directoryMetadata.mode & 0o077) !== 0 ||
      (currentUserID != null && directoryMetadata.uid !== currentUserID)) {
    throw new Error(`${label} directory must be release-user-owned and owner-private`);
  }
  const metadata = fs.lstatSync(file, { throwIfNoEntry: false });
  if (!metadata?.isFile() || metadata.isSymbolicLink()) {
    throw new Error(`${label} must be one regular non-symlink file`);
  }
  if ((metadata.mode & 0o077) !== 0 || (currentUserID != null && metadata.uid !== currentUserID)) {
    throw new Error(`${label} must be owner-private and owned by the release user`);
  }
  if (metadata.size > maximumBytes) throw new Error(`${label} exceeds its safety limit`);

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

function xcconfigValue(bytes, name) {
  const source = bytes.toString("utf8");
  const matches = source.split(/\r?\n/).flatMap(line => {
    const match = line.match(new RegExp(`^\\s*${name}\\s*=\\s*(.*?)\\s*$`));
    return match ? [match[1]] : [];
  });
  if (matches.length !== 1 || matches[0].length < 3 || matches[0].includes("$(") ||
      /^(?:REPLACE_WITH_|CHANGE_?ME)/i.test(matches[0])) {
    throw new Error(`Release xcconfig must contain one resolved ${name}`);
  }
  return matches[0];
}

export function verifyReleaseConfigAttestation({ file, expectedTeamID, xcconfigFile }) {
  if (!/^[A-Z0-9]{10}$/.test(expectedTeamID ?? "")) {
    throw new Error("Expected Apple team ID must be 10 uppercase alphanumeric characters");
  }
  const bytes = readOwnerPrivateFile(file, "Release config attestation", 64 * 1024);
  const xcconfigBytes = readOwnerPrivateFile(xcconfigFile, "Release xcconfig", 64 * 1024);
  const xcconfigSHA256 = crypto.createHash("sha256").update(xcconfigBytes).digest("hex");
  const routePlanIssuer = xcconfigValue(xcconfigBytes, "EUSOTRIP_ROUTE_PLAN_ISSUER");
  const routePlanAudience = xcconfigValue(xcconfigBytes, "EUSOTRIP_ROUTE_PLAN_AUDIENCE");
  const routePlanKeyID = xcconfigValue(xcconfigBytes, "EUSOTRIP_ROUTE_PLAN_KEY_ID");
  const routePlanPublicKeyBase64 = xcconfigValue(
    xcconfigBytes,
    "EUSOTRIP_ROUTE_PLAN_PUBLIC_KEY_BASE64",
  );
  const routePlanPublicKey = Buffer.from(routePlanPublicKeyBase64, "base64");
  if (routePlanPublicKey.length !== 32 || routePlanPublicKey.toString("base64") !== routePlanPublicKeyBase64) {
    throw new Error("Release xcconfig route-plan public key must be canonical Ed25519 raw Base64");
  }
  const routePlanPublicKeySHA256 = crypto
    .createHash("sha256")
    .update(routePlanPublicKey)
    .digest("hex");

  let attestation;
  try {
    attestation = JSON.parse(bytes.toString("utf8"));
  } catch {
    throw new Error("Release config attestation is not valid JSON");
  }
  if (
    attestation.schemaVersion !== 1 ||
    attestation.status !== "approved" ||
    attestation.source !== "protected_secret_store" ||
    attestation.appleTeamID !== expectedTeamID ||
    attestation.releaseXcconfigSHA256 !== xcconfigSHA256 ||
    attestation.routePlanIssuer !== routePlanIssuer ||
    attestation.routePlanAudience !== routePlanAudience ||
    attestation.routePlanKeyID !== routePlanKeyID ||
    attestation.routePlanPublicKeySHA256 !== routePlanPublicKeySHA256 ||
    !validIdentifier(attestation.routePlanIssuer) ||
    !validIdentifier(attestation.routePlanAudience) ||
    !validIdentifier(attestation.routePlanKeyID) ||
    !validIdentifier(attestation.incidentID) ||
    !validIdentifier(attestation.configGenerationID) ||
    !validIdentifier(attestation.generatedBy) ||
    !validIdentifier(attestation.approvedBy) ||
    attestation.generatedBy === attestation.approvedBy ||
    attestation.containsDedicatedNavigateCredentials !== true ||
    attestation.containsNoIncidentCredentialMaterial !== true ||
    !Array.isArray(attestation.credentialClasses) ||
    JSON.stringify([...attestation.credentialClasses].sort()) !==
      JSON.stringify([...REQUIRED_CREDENTIAL_CLASSES].sort())
  ) {
    throw new Error("Release config attestation is incomplete, unapproved, or not independently approved");
  }
  const rotatedAt = parseTime(attestation.credentialsRotatedAt, "credentialsRotatedAt");
  const generatedAt = parseTime(attestation.generatedAt, "generatedAt");
  const approvedAt = parseTime(attestation.approvedAt, "approvedAt");
  const expiresAt = parseTime(attestation.expiresAt, "expiresAt");
  if (rotatedAt > generatedAt || generatedAt > approvedAt) {
    throw new Error("Release config attestation chronology is invalid");
  }
  if (approvedAt > Date.now() + maximumClockSkewMilliseconds) {
    throw new Error("Release config attestation cannot be future-dated");
  }
  if (expiresAt < Date.now() || expiresAt < approvedAt ||
      expiresAt > approvedAt + maximumApprovalLifetimeMilliseconds) {
    throw new Error("Release config attestation is stale or has an excessive approval lifetime");
  }
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function main() {
  const file = argument("file");
  const expectedTeamID = argument("expected-team");
  const xcconfigFile = argument("xcconfig");
  if (!file || !expectedTeamID || !xcconfigFile) {
    throw new Error("Usage: verify-release-config-attestation.mjs --file=/absolute/path --xcconfig=/absolute/path --expected-team=TEAMID");
  }
  process.stdout.write(`${verifyReleaseConfigAttestation({ file, expectedTeamID, xcconfigFile })}\n`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  try {
    main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : "Release config attestation verification failed");
    process.exitCode = 1;
  }
}
