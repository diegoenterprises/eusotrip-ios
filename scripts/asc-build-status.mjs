#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

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
const keyPath = required("ASC_API_KEY_PATH", "ASC_PRIVATE_KEY_PATH");
const appId = arg("app-id", process.env.ASC_APP_ID?.trim());
const targetBuild = arg("build");
const ladderPath = arg("ladder");
const wait = process.argv.includes("--wait");
const requireGroup = process.argv.includes("--require-group");
const timeoutMs = Number(arg("timeout-seconds", "1800")) * 1000;
const intervalMs = Number(arg("interval-seconds", "20")) * 1000;

if (!appId) throw new Error("Missing --app-id or ASC_APP_ID");
if (path.basename(keyPath) !== `AuthKey_${keyId}.p8`) {
  throw new Error(`ASC key filename does not match key ID ${keyId}`);
}

const base64url = (input) => Buffer.from(input).toString("base64url");
const privateKey = fs.readFileSync(keyPath, "utf8");

function token() {
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyId, typ: "JWT" }));
  const payload = base64url(JSON.stringify({ iss: issuerId, iat: now, exp: now + 1100, aud: "appstoreconnect-v1" }));
  const unsigned = `${header}.${payload}`;
  const signature = crypto.sign("sha256", Buffer.from(unsigned), {
    key: privateKey,
    dsaEncoding: "ieee-p1363",
  });
  return `${unsigned}.${base64url(signature)}`;
}

async function api(urlPath) {
  const response = await fetch(`https://api.appstoreconnect.apple.com${urlPath}`, {
    headers: { Authorization: `Bearer ${token()}` },
  });
  const body = await response.text();
  if (!response.ok) throw new Error(`App Store Connect HTTP ${response.status}: ${body.slice(0, 500)}`);
  return JSON.parse(body);
}

async function currentStatus() {
  const query = new URLSearchParams({
    "filter[app]": appId,
    sort: "-uploadedDate",
    limit: "50",
    include: "preReleaseVersion",
  });
  const response = await api(`/v1/builds?${query}`);
  const build = targetBuild
    ? response.data.find((item) => String(item.attributes?.version) === String(targetBuild))
    : response.data[0];
  if (!build) {
    return { appId, build: targetBuild, found: false, processingState: "PENDING", betaGroups: [] };
  }
  const groupQuery = new URLSearchParams({
    "filter[builds]": build.id,
    limit: "50",
  });
  const groups = await api(`/v1/betaGroups?${groupQuery}`);
  const preReleaseId = build.relationships?.preReleaseVersion?.data?.id;
  const preRelease = response.included?.find((item) => item.id === preReleaseId);
  return {
    appId,
    id: build.id,
    build: String(build.attributes?.version ?? ""),
    version: preRelease?.attributes?.version ?? null,
    uploadedDate: build.attributes?.uploadedDate ?? null,
    processingState: build.attributes?.processingState ?? "UNKNOWN",
    expired: Boolean(build.attributes?.expired),
    betaGroups: (groups.data || []).map((group) => ({ id: group.id, name: group.attributes?.name ?? null })),
    found: true,
  };
}

function updateLadder(status) {
  if (!ladderPath || !fs.existsSync(ladderPath)) return;
  const ladder = JSON.parse(fs.readFileSync(ladderPath, "utf8"));
  if (status.processingState === "VALID") ladder.processing = "pass";
  else if (["FAILED", "INVALID"].includes(status.processingState)) ladder.processing = "fail";
  else ladder.processing = "pending";
  ladder.availableInTestFlight = status.processingState === "VALID" && status.betaGroups.length > 0 ? "pass" : "pending";
  ladder.appStoreConnectBuildId = status.id ?? null;
  ladder.betaGroups = status.betaGroups;
  fs.writeFileSync(ladderPath, `${JSON.stringify(ladder, null, 2)}\n`);
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
