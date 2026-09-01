#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const EOCD_SIGNATURE = 0x06054b50;
const CENTRAL_DIRECTORY_SIGNATURE = 0x02014b50;
const LOCAL_FILE_SIGNATURE = 0x04034b50;
const ZIP64_U16 = 0xffff;
const ZIP64_U32 = 0xffffffff;
const DATA_DESCRIPTOR_SIGNATURE = 0x08074b50;
const MAX_ENTRIES = 100_000;
const MAX_ARCHIVE_BYTES = 2 * 1_024 * 1_024 * 1_024;
const MAX_TOTAL_EXPANDED_BYTES = 2 * 1_024 * 1_024 * 1_024;
const MAX_ENTRY_EXPANDED_BYTES = 1 * 1_024 * 1_024 * 1_024;
const MAX_PATH_BYTES = 1_024;
const MAX_COMPONENT_BYTES = 255;
const CONTROL_CHARACTER_PATTERN = /[\u0000-\u001f\u007f]/;

export class IPAPreflightError extends Error {
  constructor(message) {
    super(`Exported IPA preflight refused: ${message}`);
    this.name = "IPAPreflightError";
  }
}

function fail(message) {
  throw new IPAPreflightError(message);
}

function findEndOfCentralDirectory(archive) {
  const minimumOffset = Math.max(0, archive.length - (ZIP64_U16 + 22));
  for (let offset = archive.length - 22; offset >= minimumOffset; offset -= 1) {
    if (archive.readUInt32LE(offset) !== EOCD_SIGNATURE) continue;
    const commentLength = archive.readUInt16LE(offset + 20);
    if (offset + 22 + commentLength === archive.length) return offset;
  }
  fail("end-of-central-directory record is missing or has trailing bytes");
}

function decodedPath(bytes) {
  let value;
  try {
    value = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    fail("an entry path is not valid UTF-8");
  }
  if (
    value.length === 0 ||
    bytes.length > MAX_PATH_BYTES ||
    CONTROL_CHARACTER_PATTERN.test(value) ||
    value.includes("\\") ||
    value.startsWith("/") ||
    /^[A-Za-z]:/.test(value)
  ) {
    fail("an entry path is absolute, malformed, or unsafe");
  }
  const withoutDirectorySuffix = value.endsWith("/") ? value.slice(0, -1) : value;
  const components = withoutDirectorySuffix.split("/");
  if (
    components.length === 0 ||
    components.some(
      component =>
        component.length === 0 ||
        component === "." ||
        component === ".." ||
        Buffer.byteLength(component, "utf8") > MAX_COMPONENT_BYTES
    )
  ) {
    fail("an entry path contains traversal, an empty component, or an oversized component");
  }
  return value;
}

function requireSafeUnixType(versionMadeBy, externalAttributes, entryPath) {
  const creatorSystem = versionMadeBy >>> 8;
  if (creatorSystem !== 3) return;
  const unixMode = externalAttributes >>> 16;
  const type = unixMode & 0o170000;
  if (type === 0 || type === 0o100000 || type === 0o040000) return;
  if (type === 0o120000) {
    fail(`symbolic-link entry is forbidden (${entryPath})`);
  }
  fail(`non-file archive entry type is forbidden (${entryPath})`);
}

export function inspectExportedIPA(archive, expectedAppName = "EusoTrip.app") {
  if (
    !Buffer.isBuffer(archive) ||
    archive.length < 22 ||
    archive.length > MAX_ARCHIVE_BYTES
  ) {
    fail("archive is empty or truncated");
  }
  const eocd = findEndOfCentralDirectory(archive);
  const diskNumber = archive.readUInt16LE(eocd + 4);
  const centralDirectoryDisk = archive.readUInt16LE(eocd + 6);
  const diskEntries = archive.readUInt16LE(eocd + 8);
  const totalEntries = archive.readUInt16LE(eocd + 10);
  const centralDirectoryBytes = archive.readUInt32LE(eocd + 12);
  const centralDirectoryOffset = archive.readUInt32LE(eocd + 16);
  if (
    diskNumber !== 0 ||
    centralDirectoryDisk !== 0 ||
    diskEntries !== totalEntries ||
    totalEntries === ZIP64_U16 ||
    centralDirectoryBytes === ZIP64_U32 ||
    centralDirectoryOffset === ZIP64_U32
  ) {
    fail("multi-disk and ZIP64 archives are not accepted for release inspection");
  }
  if (totalEntries < 1 || totalEntries > MAX_ENTRIES) {
    fail("archive file count is empty or exceeds the release limit");
  }
  if (
    centralDirectoryOffset + centralDirectoryBytes !== eocd ||
    centralDirectoryOffset > archive.length ||
    centralDirectoryBytes > archive.length
  ) {
    fail("central-directory bounds are inconsistent");
  }

  const exactPaths = new Set();
  const filesystemPaths = new Set();
  const appNames = new Set();
  const localRecordRanges = [];
  let totalExpandedBytes = 0;
  let cursor = centralDirectoryOffset;
  for (let index = 0; index < totalEntries; index += 1) {
    if (
      cursor + 46 > eocd ||
      archive.readUInt32LE(cursor) !== CENTRAL_DIRECTORY_SIGNATURE
    ) {
      fail("central-directory entry is truncated or malformed");
    }
    const versionMadeBy = archive.readUInt16LE(cursor + 4);
    const flags = archive.readUInt16LE(cursor + 8);
    const method = archive.readUInt16LE(cursor + 10);
    const crc32 = archive.readUInt32LE(cursor + 16);
    const compressedBytes = archive.readUInt32LE(cursor + 20);
    const expandedBytes = archive.readUInt32LE(cursor + 24);
    const nameBytes = archive.readUInt16LE(cursor + 28);
    const extraBytes = archive.readUInt16LE(cursor + 30);
    const commentBytes = archive.readUInt16LE(cursor + 32);
    const diskStart = archive.readUInt16LE(cursor + 34);
    const externalAttributes = archive.readUInt32LE(cursor + 38);
    const localOffset = archive.readUInt32LE(cursor + 42);
    const entryEnd = cursor + 46 + nameBytes + extraBytes + commentBytes;
    if (
      entryEnd > eocd ||
      diskStart !== 0 ||
      compressedBytes === ZIP64_U32 ||
      expandedBytes === ZIP64_U32 ||
      localOffset === ZIP64_U32 ||
      (flags & ~(0x0006 | 0x0008 | 0x0800)) !== 0 ||
      (method !== 0 && method !== 8)
    ) {
      fail("an entry uses unsupported encryption, compression, disk, or ZIP64 metadata");
    }
    const centralName = archive.subarray(cursor + 46, cursor + 46 + nameBytes);
    const entryPath = decodedPath(centralName);
    requireSafeUnixType(versionMadeBy, externalAttributes, entryPath);
    if (exactPaths.has(entryPath)) fail(`duplicate entry path is forbidden (${entryPath})`);
    exactPaths.add(entryPath);
    const filesystemKey = entryPath.normalize("NFC").toLowerCase();
    if (filesystemPaths.has(filesystemKey)) {
      fail(`case- or normalization-colliding path is forbidden (${entryPath})`);
    }
    filesystemPaths.add(filesystemKey);

    if (expandedBytes > MAX_ENTRY_EXPANDED_BYTES) {
      fail(`an entry exceeds the expanded-size limit (${entryPath})`);
    }
    totalExpandedBytes += expandedBytes;
    if (totalExpandedBytes > MAX_TOTAL_EXPANDED_BYTES) {
      fail("archive exceeds the total expanded-size limit");
    }

    if (
      localOffset + 30 > centralDirectoryOffset ||
      archive.readUInt32LE(localOffset) !== LOCAL_FILE_SIGNATURE
    ) {
      fail(`local header is missing or out of bounds (${entryPath})`);
    }
    const localNameBytes = archive.readUInt16LE(localOffset + 26);
    const localExtraBytes = archive.readUInt16LE(localOffset + 28);
    const localFlags = archive.readUInt16LE(localOffset + 6);
    const localMethod = archive.readUInt16LE(localOffset + 8);
    const localCRC32 = archive.readUInt32LE(localOffset + 14);
    const localCompressedBytes = archive.readUInt32LE(localOffset + 18);
    const localExpandedBytes = archive.readUInt32LE(localOffset + 22);
    const localName = archive.subarray(
      localOffset + 30,
      localOffset + 30 + localNameBytes
    );
    const dataOffset = localOffset + 30 + localNameBytes + localExtraBytes;
    if (
      !centralName.equals(localName) ||
      localFlags !== flags ||
      localMethod !== method ||
      dataOffset > centralDirectoryOffset ||
      compressedBytes > centralDirectoryOffset - dataOffset
    ) {
      fail(`local and central entry metadata disagree (${entryPath})`);
    }
    const dataEnd = dataOffset + compressedBytes;
    let recordEnd = dataEnd;
    if ((flags & 0x0008) !== 0) {
      const hasSignature =
        dataEnd + 4 <= centralDirectoryOffset &&
        archive.readUInt32LE(dataEnd) === DATA_DESCRIPTOR_SIGNATURE;
      const descriptor = dataEnd + (hasSignature ? 4 : 0);
      if (descriptor + 12 > centralDirectoryOffset) {
        fail(`data descriptor is truncated (${entryPath})`);
      }
      if (
        archive.readUInt32LE(descriptor) !== crc32 ||
        archive.readUInt32LE(descriptor + 4) !== compressedBytes ||
        archive.readUInt32LE(descriptor + 8) !== expandedBytes
      ) {
        fail(`data descriptor disagrees with the central entry (${entryPath})`);
      }
      recordEnd = descriptor + 12;
    } else if (
      localCRC32 !== crc32 ||
      localCompressedBytes !== compressedBytes ||
      localExpandedBytes !== expandedBytes
    ) {
      fail(`local sizes or checksum disagree with the central entry (${entryPath})`);
    }
    localRecordRanges.push({ start: localOffset, end: recordEnd, entryPath });

    const appMatch = entryPath.match(/^Payload\/([^/]+\.app)(?:\/|$)/);
    if (appMatch) appNames.add(appMatch[1]);
    cursor = entryEnd;
  }
  if (cursor !== eocd) fail("central-directory byte count does not match its entries");
  localRecordRanges.sort((left, right) => left.start - right.start);
  let expectedLocalOffset = 0;
  for (const range of localRecordRanges) {
    if (range.start !== expectedLocalOffset || range.end < range.start) {
      fail(`local records overlap or leave hidden bytes (${range.entryPath})`);
    }
    expectedLocalOffset = range.end;
  }
  if (expectedLocalOffset !== centralDirectoryOffset) {
    fail("local records do not exactly cover the archive before its central directory");
  }
  if (appNames.size !== 1 || !appNames.has(expectedAppName)) {
    fail(`archive must contain exactly Payload/${expectedAppName}`);
  }
  if (!exactPaths.has(`Payload/${expectedAppName}/Info.plist`)) {
    fail(`Payload/${expectedAppName}/Info.plist is missing`);
  }
  return {
    entryCount: totalEntries,
    expandedBytes: totalExpandedBytes,
    appRelativePath: `Payload/${expectedAppName}`,
  };
}

export function preflightExportedIPAFile(file) {
  const absoluteFile = path.resolve(file);
  const metadata = fs.lstatSync(absoluteFile);
  if (
    !metadata.isFile() ||
    metadata.isSymbolicLink() ||
    metadata.size > MAX_ARCHIVE_BYTES
  ) {
    fail("IPA path must be one regular file");
  }
  return inspectExportedIPA(fs.readFileSync(absoluteFile));
}

const isMain = process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const argument = process.argv.find(value => value.startsWith("--ipa="));
  if (!argument) {
    console.error("Usage: preflight-exported-ipa.mjs --ipa=/absolute/path/EusoTrip.ipa");
    process.exit(2);
  }
  try {
    const result = preflightExportedIPAFile(argument.slice("--ipa=".length));
    console.log(
      `Exported IPA preflight passed: ${result.entryCount} entries, ${result.expandedBytes} expanded bytes, ${result.appRelativePath}.`
    );
  } catch (error) {
    console.error(
      error instanceof IPAPreflightError
        ? error.message
        : "Exported IPA preflight failed without exposing archive contents."
    );
    process.exit(1);
  }
}
