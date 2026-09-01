#!/usr/bin/env node

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  IPAPreflightError,
  inspectExportedIPA,
  preflightExportedIPAFile,
} from "./preflight-exported-ipa.mjs";

const LOCAL_FILE_SIGNATURE = 0x04034b50;
const CENTRAL_DIRECTORY_SIGNATURE = 0x02014b50;
const EOCD_SIGNATURE = 0x06054b50;

function zip(entries, prefix = Buffer.alloc(0)) {
  const locals = [];
  const centrals = [];
  let localOffset = prefix.length;
  for (const entry of entries) {
    const name = Buffer.from(entry.path, "utf8");
    const data = Buffer.from(entry.data ?? "", "utf8");
    const expandedBytes = entry.expandedBytes ?? data.length;
    const local = Buffer.alloc(30 + name.length + data.length);
    local.writeUInt32LE(LOCAL_FILE_SIGNATURE, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0x800, 6);
    local.writeUInt16LE(0, 8);
    local.writeUInt32LE(0, 14);
    local.writeUInt32LE(data.length, 18);
    local.writeUInt32LE(expandedBytes >>> 0, 22);
    local.writeUInt16LE(name.length, 26);
    local.writeUInt16LE(0, 28);
    name.copy(local, 30);
    data.copy(local, 30 + name.length);
    locals.push(local);

    const central = Buffer.alloc(46 + name.length);
    central.writeUInt32LE(CENTRAL_DIRECTORY_SIGNATURE, 0);
    central.writeUInt16LE((3 << 8) | 20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0x800, 8);
    central.writeUInt16LE(0, 10);
    central.writeUInt32LE(0, 16);
    central.writeUInt32LE(data.length, 20);
    central.writeUInt32LE(expandedBytes >>> 0, 24);
    central.writeUInt16LE(name.length, 28);
    central.writeUInt16LE(0, 30);
    central.writeUInt16LE(0, 32);
    central.writeUInt16LE(0, 34);
    central.writeUInt16LE(0, 36);
    central.writeUInt32LE(((entry.mode ?? 0o100644) << 16) >>> 0, 38);
    central.writeUInt32LE(localOffset, 42);
    name.copy(central, 46);
    centrals.push(central);
    localOffset += local.length;
  }
  const centralDirectory = Buffer.concat(centrals);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(EOCD_SIGNATURE, 0);
  eocd.writeUInt16LE(entries.length, 8);
  eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(centralDirectory.length, 12);
  eocd.writeUInt32LE(localOffset, 16);
  return Buffer.concat([prefix, ...locals, centralDirectory, eocd]);
}

const info = {
  path: "Payload/EusoTrip.app/Info.plist",
  data: "fixture plist",
};

function rejects(name, archive, pattern) {
  assert.throws(
    () => inspectExportedIPA(archive),
    error => error instanceof IPAPreflightError && pattern.test(error.message),
    name
  );
  console.log(`ok - ${name}`);
}

const valid = inspectExportedIPA(zip([info]));
assert.deepEqual(valid, {
  entryCount: 1,
  expandedBytes: 13,
  appRelativePath: "Payload/EusoTrip.app",
});
console.log("ok - one exact EusoTrip app");

rejects(
  "path traversal",
  zip([info, { path: "Payload/EusoTrip.app/../../escape", data: "x" }]),
  /traversal/
);
rejects(
  "absolute path",
  zip([info, { path: "/tmp/escape", data: "x" }]),
  /absolute, malformed, or unsafe/
);
rejects(
  "symbolic link",
  zip([
    info,
    {
      path: "Payload/EusoTrip.app/Frameworks/escape",
      data: "../../outside",
      mode: 0o120777,
    },
  ]),
  /symbolic-link/
);
rejects(
  "case-colliding extraction paths",
  zip([info, { path: "payload/eusotrip.app/info.plist", data: "other" }]),
  /colliding path/
);
rejects(
  "multiple app products",
  zip([
    info,
    { path: "Payload/Substitute.app/Info.plist", data: "other" },
  ]),
  /exactly Payload\/EusoTrip\.app/
);
rejects(
  "missing root Info.plist",
  zip([{ path: "Payload/EusoTrip.app/EusoTrip", data: "binary" }]),
  /Info\.plist is missing/
);
rejects(
  "expanded-size bomb",
  zip([{ ...info, expandedBytes: 0xffffff00 }]),
  /expanded-size limit/
);
rejects("truncated archive", Buffer.from("not a zip"), /empty or truncated/);

const mismatchedLocalMethod = zip([info]);
mismatchedLocalMethod.writeUInt16LE(8, 8);
rejects(
  "central and local metadata mismatch",
  mismatchedLocalMethod,
  /local and central entry metadata disagree/
);
rejects(
  "hidden local bytes",
  zip([info], Buffer.from("hidden")),
  /hidden bytes/
);

const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "eusotrip-ipa-size-"));
try {
  const oversized = path.join(temporaryRoot, "oversized.ipa");
  fs.writeFileSync(oversized, "");
  fs.truncateSync(oversized, 2 * 1_024 * 1_024 * 1_024 + 1);
  assert.throws(
    () => preflightExportedIPAFile(oversized),
    error => error instanceof IPAPreflightError && /regular file/.test(error.message)
  );
  console.log("ok - oversized IPA rejected before read");
} finally {
  fs.rmSync(temporaryRoot, { recursive: true, force: true });
}

console.log("Exported IPA preflight regression harness passed: 12 cases.");
