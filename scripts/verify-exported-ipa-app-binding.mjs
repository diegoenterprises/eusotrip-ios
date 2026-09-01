#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { hashReleaseArtifact } from "./hash-release-artifact.mjs";
import { preflightExportedIPAFile } from "./preflight-exported-ipa.mjs";

const sha256Pattern = /^[a-f0-9]{64}$/;

export function verifyExportedIPAAppBinding({
  ipaFile,
  expectedIPASha256,
  expectedAppTreeSha256,
}) {
  if (!path.isAbsolute(ipaFile ?? "") ||
      !sha256Pattern.test(expectedIPASha256 ?? "") ||
      !sha256Pattern.test(expectedAppTreeSha256 ?? "")) {
    throw new Error("Exact absolute IPA and artifact hashes are required");
  }
  const inspection = preflightExportedIPAFile(ipaFile);
  const initialIPASha256 = hashReleaseArtifact(ipaFile);
  if (initialIPASha256 !== expectedIPASha256) {
    throw new Error("Exported IPA no longer matches its recorded SHA-256");
  }

  const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "eusotrip-ipa-binding-"));
  fs.chmodSync(temporaryRoot, 0o700);
  try {
    const extraction = spawnSync("/usr/bin/ditto", ["-x", "-k", ipaFile, temporaryRoot], {
      encoding: "utf8",
      maxBuffer: 1024 * 1024,
    });
    if (extraction.status !== 0) {
      throw new Error("Exported IPA could not be safely re-extracted");
    }
    const appPath = path.join(temporaryRoot, inspection.appRelativePath);
    const payloadPath = path.join(temporaryRoot, "Payload");
    const payloadMetadata = fs.lstatSync(payloadPath, { throwIfNoEntry: false });
    const appMetadata = fs.lstatSync(appPath, { throwIfNoEntry: false });
    if (!payloadMetadata?.isDirectory() || payloadMetadata.isSymbolicLink() ||
        !appMetadata?.isDirectory() || appMetadata.isSymbolicLink() ||
        fs.realpathSync(appPath) !== path.join(fs.realpathSync(payloadPath), "EusoTrip.app")) {
      throw new Error("Re-extracted IPA does not contain one exact EusoTrip app root");
    }
    if (hashReleaseArtifact(appPath) !== expectedAppTreeSha256) {
      throw new Error("Recorded exported app tree was not derived from the recorded IPA");
    }
    if (hashReleaseArtifact(ipaFile) !== initialIPASha256) {
      throw new Error("Exported IPA changed during app-binding verification");
    }
    return { ipaSha256: initialIPASha256, appTreeSha256: expectedAppTreeSha256 };
  } finally {
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
  }
}

function argument(name) {
  const prefix = `--${name}=`;
  return process.argv.find(value => value.startsWith(prefix))?.slice(prefix.length) ?? null;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  try {
    verifyExportedIPAAppBinding({
      ipaFile: argument("ipa"),
      expectedIPASha256: argument("ipa-sha256"),
      expectedAppTreeSha256: argument("app-tree-sha256"),
    });
    console.log("Exported IPA and EusoTrip app tree are cryptographically bound.");
  } catch (error) {
    console.error(error instanceof Error ? error.message : "Exported IPA/app binding failed");
    process.exitCode = 1;
  }
}
