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

export function verifyReleaseConfigAttestation({ file, expectedTeamID }) {
  if (!path.isAbsolute(file)) throw new Error("Release config attestation path must be absolute");
  if (!/^[A-Z0-9]{10}$/.test(expectedTeamID ?? "")) {
    throw new Error("Expected Apple team ID must be 10 uppercase alphanumeric characters");
  }
  const metadata = fs.lstatSync(file, { throwIfNoEntry: false });
  if (!metadata?.isFile() || metadata.isSymbolicLink()) {
    throw new Error("Release config attestation must be one regular non-symlink file");
  }
  const currentUserID = typeof process.getuid === "function" ? process.getuid() : null;
  if ((metadata.mode & 0o077) !== 0 || (currentUserID != null && metadata.uid !== currentUserID)) {
    throw new Error("Release config attestation must be owner-private and owned by the release user");
  }
  if (metadata.size > 64 * 1024) throw new Error("Release config attestation exceeds 64 KiB");

  const descriptor = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
  let bytes;
  try {
    const opened = fs.fstatSync(descriptor);
    if (!opened.isFile() || opened.dev !== metadata.dev || opened.ino !== metadata.ino) {
      throw new Error("Release config attestation changed while it was opened");
    }
    bytes = fs.readFileSync(descriptor);
    const final = fs.fstatSync(descriptor);
    if (final.size !== opened.size || final.mtimeMs !== opened.mtimeMs) {
      throw new Error("Release config attestation changed while it was read");
    }
  } finally {
    fs.closeSync(descriptor);
  }

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
  if (rotatedAt > generatedAt || generatedAt > approvedAt) {
    throw new Error("Release config attestation chronology is invalid");
  }
  if (approvedAt > Date.now() + maximumClockSkewMilliseconds) {
    throw new Error("Release config attestation cannot be future-dated");
  }
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function main() {
  const file = argument("file");
  const expectedTeamID = argument("expected-team");
  if (!file || !expectedTeamID) {
    throw new Error("Usage: verify-release-config-attestation.mjs --file=/absolute/path --expected-team=TEAMID");
  }
  process.stdout.write(`${verifyReleaseConfigAttestation({ file, expectedTeamID })}\n`);
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  try {
    main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : "Release config attestation verification failed");
    process.exitCode = 1;
  }
}
