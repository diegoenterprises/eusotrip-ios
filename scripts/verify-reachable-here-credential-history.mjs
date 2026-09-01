#!/usr/bin/env node

import { spawn, spawnSync } from "node:child_process";
import crypto from "node:crypto";
import { once } from "node:events";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

const GIT = "/usr/bin/git";
const DEFAULT_CHUNK_BYTES = 64 * 1024;
const MATCH_OVERLAP_BYTES = 4 * 1024;
const MINIMUM_CHUNK_BYTES = MATCH_OVERLAP_BYTES;
const MAXIMUM_CHUNK_BYTES = 1024 * 1024;
const OBJECT_BATCH_SIZE = 256;
const MAX_REV_LIST_LINE_BYTES = 16 * 1024;
const MAX_METADATA_BYTES = 16 * 1024;
const MAX_PROTOCOL_LINE_BYTES = 512;
const MAX_STDERR_BYTES = 64 * 1024;
const MAX_REPORTED_FINDINGS = 100;

const namedKey = [
  "HERE_API_KEY",
  "HERE_APIKEY",
  "HERE_MAPS_API_KEY",
  "HERE_ACCESS_KEY_ID",
  "HERE_ACCESS_KEY_SECRET",
  "HERE_SDK_ACCESS_KEY_ID",
  "HERE_SDK_ACCESS_KEY_SECRET",
  "HERE_OAUTH_ACCESS_KEY_ID",
  "HERE_OAUTH_ACCESS_KEY_SECRET",
  "HERE_CLIENT_ID",
  "HERE_CLIENT_SECRET",
  "HERE_USER_ID",
  "HERE_APP_ID",
  "HERE_APP_CODE",
  "HERESDKAccessKeyID",
  "HERESDKAccessKeySecret",
  "hereApiKey",
  "hereAccessKeyId",
  "hereAccessKeySecret",
  "hereClientId",
  "hereClientSecret",
  "hereUserId",
].join("|");

const namedKeyIdentifier =
  `(?<![A-Za-z0-9_])(?:[A-Za-z][A-Za-z0-9]{0,63}_){0,8}(?:${namedKey})(?:_[A-Za-z][A-Za-z0-9]{0,63}){0,8}(?![A-Za-z0-9_])`;
const tokenCapture = "([A-Za-z0-9_./+~=-]{16,192})";
const patterns = [
  {
    id: "here-named-assignment",
    valueGroup: 1,
    expression: new RegExp(
      `${namedKeyIdentifier}(?:[\\\"'\\x60])?[\\t ]{0,64}(?:=|:)[\\t ]{0,64}(?:[\\\"'\\x60])?${tokenCapture}`,
      "gi",
    ),
  },
  {
    id: "here-plist-string",
    valueGroup: 1,
    expression: new RegExp(
      `<key>[\\t\\r\\n ]{0,128}${namedKeyIdentifier}[\\t\\r\\n ]{0,128}<\\/key>[\\t\\r\\n ]{0,128}<string>[\\t\\r\\n ]{0,128}${tokenCapture}`,
      "gi",
    ),
  },
  {
    id: "here-human-readable-assignment",
    valueGroup: 1,
    expression: new RegExp(
      `\\bHERE[\\t ]{1,16}(?:(?:SDK|OAUTH|MAPS)[\\t ]{1,16})?(?:API[\\t ]{1,16}KEY|ACCESS[\\t ]{1,16}KEY[\\t ]{1,16}(?:ID|SECRET)|CLIENT[\\t ]{1,16}(?:ID|SECRET)|USER[\\t ]{1,16}ID|APP[\\t ]{1,16}(?:ID|CODE))[\\t ]{0,64}(?:=|:)[\\t ]{0,64}(?:[\\\"'\\x60])?${tokenCapture}`,
      "gi",
    ),
  },
  {
    id: "here-api-query-credential",
    valueGroup: 1,
    expression: new RegExp(
      `(?<![A-Za-z0-9.-])(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.){0,32}(?:hereapi\\.com|here\\.com)(?::[0-9]{1,5})?(?=[/?#])[^\\s\\\"'<>]{0,1024}?[?&](?:apiKey|apikey|app_id|app_code)=${tokenCapture}`,
      "gi",
    ),
  },
  {
    id: "here-oauth-bearer",
    valueGroup: 1,
    expression: new RegExp(
      `(?<![A-Za-z0-9.-])(?:account\\.api\\.here\\.com|(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\\.){1,32}hereapi\\.com)(?::[0-9]{1,5})?(?=[/\\s])[\\s\\S]{0,1024}?\\bBearer[\\t ]{1,16}${tokenCapture}`,
      "gi",
    ),
  },
];

class ScannerIntegrityError extends Error {
  constructor(code) {
    super(code);
    this.name = "ScannerIntegrityError";
    this.code = code;
  }
}

class BoundedByteReader {
  constructor(stream, codePrefix) {
    this.iterator = stream[Symbol.asyncIterator]();
    this.pending = Buffer.alloc(0);
    this.done = false;
    this.codePrefix = codePrefix;
  }

  async pull() {
    if (this.done) return false;
    const next = await this.iterator.next();
    if (next.done) {
      this.done = true;
      return false;
    }
    if (!Buffer.isBuffer(next.value)) {
      throw new ScannerIntegrityError(`${this.codePrefix}-non-buffer-output`);
    }
    this.pending = this.pending.length === 0
      ? next.value
      : Buffer.concat([this.pending, next.value]);
    return true;
  }

  async readLine(maximumBytes, allowCleanEOF = false) {
    while (true) {
      const newline = this.pending.indexOf(0x0a);
      if (newline >= 0) {
        if (newline > maximumBytes) {
          throw new ScannerIntegrityError(`${this.codePrefix}-line-too-long`);
        }
        const line = this.pending.subarray(0, newline).toString("utf8");
        this.pending = this.pending.subarray(newline + 1);
        return line.endsWith("\r") ? line.slice(0, -1) : line;
      }
      if (this.pending.length > maximumBytes) {
        throw new ScannerIntegrityError(`${this.codePrefix}-line-too-long`);
      }
      if (!(await this.pull())) {
        if (this.pending.length !== 0) {
          throw new ScannerIntegrityError(`${this.codePrefix}-incomplete-line`);
        }
        if (allowCleanEOF) return null;
        throw new ScannerIntegrityError(`${this.codePrefix}-unexpected-eof`);
      }
    }
  }

  async readAtMost(maximumBytes) {
    if (!Number.isSafeInteger(maximumBytes) || maximumBytes <= 0) {
      throw new ScannerIntegrityError(`${this.codePrefix}-invalid-read-size`);
    }
    if (this.pending.length === 0 && !(await this.pull())) {
      return null;
    }
    const count = Math.min(maximumBytes, this.pending.length);
    const bytes = this.pending.subarray(0, count);
    this.pending = this.pending.subarray(count);
    return bytes;
  }

  async expectByte(expected) {
    const byte = await this.readAtMost(1);
    if (!byte || byte.length !== 1 || byte[0] !== expected) {
      throw new ScannerIntegrityError(`${this.codePrefix}-invalid-delimiter`);
    }
  }

  async expectEOF() {
    if (this.pending.length !== 0 || await this.pull()) {
      throw new ScannerIntegrityError(`${this.codePrefix}-unexpected-output`);
    }
  }
}

function scrubbedGitEnvironment() {
  const environment = {};
  for (const [key, value] of Object.entries(process.env)) {
    if (!/^GIT_/i.test(key) && value !== undefined) environment[key] = value;
  }
  return {
    ...environment,
    GIT_CONFIG_GLOBAL: "/dev/null",
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_NO_LAZY_FETCH: "1",
    GIT_NO_REPLACE_OBJECTS: "1",
    GIT_OPTIONAL_LOCKS: "0",
    GIT_PAGER: "cat",
    GIT_TERMINAL_PROMPT: "0",
    LC_ALL: "C",
  };
}

function pinnedGitArguments(repository, arguments_) {
  return [
    "--no-replace-objects",
    `--git-dir=${repository.gitDirectory}`,
    `--work-tree=${repository.root}`,
    ...arguments_,
  ];
}

function startGit(repository, arguments_, codePrefix) {
  const child = spawn(GIT, pinnedGitArguments(repository, arguments_), {
    cwd: repository.root,
    env: scrubbedGitEnvironment(),
    stdio: ["pipe", "pipe", "pipe"],
  });
  let stderrBytes = 0;
  let stderrOverflow = false;
  child.stderr.on("data", chunk => {
    stderrBytes += chunk.length;
    if (stderrBytes > MAX_STDERR_BYTES) {
      stderrOverflow = true;
      child.kill("SIGKILL");
    }
  });
  const exit = new Promise((resolve, reject) => {
    child.once("error", () => {
      reject(new ScannerIntegrityError(`${codePrefix}-spawn-failed`));
    });
    child.once("close", (code, signal) => {
      resolve({ code, signal, stderrOverflow });
    });
  });
  return { child, exit, codePrefix };
}

async function requireCleanExit(processState) {
  const result = await processState.exit;
  if (result.code !== 0 || result.signal !== null || result.stderrOverflow) {
    throw new ScannerIntegrityError(`${processState.codePrefix}-failed`);
  }
}

async function writeRequest(stream, value, code) {
  if (stream.destroyed || stream.writableEnded) {
    throw new ScannerIntegrityError(`${code}-closed-input`);
  }
  if (!stream.write(`${value}\n`, "ascii")) {
    try {
      await once(stream, "drain");
    } catch {
      throw new ScannerIntegrityError(`${code}-write-failed`);
    }
  }
}

function runGitProbe(arguments_, cwd) {
  return spawnSync(GIT, arguments_, {
    cwd,
    encoding: "utf8",
    env: scrubbedGitEnvironment(),
    maxBuffer: 1024 * 1024,
  });
}

function requireSingleLine(result, code) {
  if (result.error || result.signal !== null || result.status !== 0 ||
      typeof result.stdout !== "string" || !result.stdout.endsWith("\n")) {
    throw new ScannerIntegrityError(code);
  }
  const value = result.stdout.slice(0, -1);
  if (value.length === 0 || /[\0\r\n]/.test(value)) {
    throw new ScannerIntegrityError(code);
  }
  return value;
}

function exactRepositoryContext(candidate) {
  try {
    const resolved = fs.realpathSync(path.resolve(candidate));
    if (!fs.statSync(resolved).isDirectory()) {
      throw new ScannerIntegrityError("repository-not-directory");
    }
    const root = fs.realpathSync(requireSingleLine(
      runGitProbe(
        ["--no-replace-objects", "-C", resolved, "rev-parse", "--show-toplevel"],
        resolved,
      ),
      "repository-root-probe-failed",
    ));
    const gitDirectory = fs.realpathSync(requireSingleLine(
      runGitProbe(
        ["--no-replace-objects", "-C", root, "rev-parse", "--absolute-git-dir"],
        root,
      ),
      "repository-git-dir-probe-failed",
    ));
    const commonDirectoryValue = requireSingleLine(
      runGitProbe(
        ["--no-replace-objects", "-C", root, "rev-parse", "--git-common-dir"],
        root,
      ),
      "repository-common-dir-probe-failed",
    );
    const commonDirectory = fs.realpathSync(
      path.resolve(root, commonDirectoryValue),
    );
    const repository = { root, gitDirectory, commonDirectory };
    const worktreeProbe = runGitProbe(
      pinnedGitArguments(
        repository,
        ["rev-parse", "--is-inside-work-tree", "--is-shallow-repository"],
      ),
      root,
    );
    if (worktreeProbe.error || worktreeProbe.signal !== null ||
        worktreeProbe.status !== 0 || worktreeProbe.stdout !== "true\nfalse\n") {
      throw new ScannerIntegrityError("repository-not-git-worktree");
    }
    const partialProbe = runGitProbe(
      pinnedGitArguments(
        repository,
        [
          "config",
          "--local",
          "--get-regexp",
          "^(extensions\\.partialclone|remote\\..*\\.(promisor|partialclonefilter))$",
        ],
      ),
      root,
    );
    if (partialProbe.error || partialProbe.signal !== null ||
        ![0, 1].includes(partialProbe.status)) {
      throw new ScannerIntegrityError("repository-partial-clone-probe-failed");
    }
    if (partialProbe.status === 0 || partialProbe.stdout.length !== 0) {
      throw new ScannerIntegrityError("repository-partial-or-promisor");
    }
    const packDirectory = path.join(commonDirectory, "objects", "pack");
    if (fs.existsSync(packDirectory) &&
        fs.readdirSync(packDirectory).some(name => name.endsWith(".promisor"))) {
      throw new ScannerIntegrityError("repository-partial-or-promisor");
    }
    return repository;
  } catch (error) {
    if (error instanceof ScannerIntegrityError) throw error;
    throw new ScannerIntegrityError("repository-unavailable");
  }
}

function parseArguments(arguments_) {
  let repository = process.cwd();
  let chunkBytes = DEFAULT_CHUNK_BYTES;
  for (const argument of arguments_) {
    if (argument.startsWith("--repository=")) {
      repository = argument.slice("--repository=".length);
    } else if (argument.startsWith("--chunk-bytes=")) {
      chunkBytes = Number(argument.slice("--chunk-bytes=".length));
    } else {
      throw new ScannerIntegrityError("unsupported-argument");
    }
  }
  if (!Number.isSafeInteger(chunkBytes) ||
      chunkBytes < MINIMUM_CHUNK_BYTES ||
      chunkBytes > MAXIMUM_CHUNK_BYTES) {
    throw new ScannerIntegrityError("invalid-chunk-size");
  }
  return { repository, chunkBytes };
}

function parseRevListLine(line) {
  const separator = line.indexOf(" ");
  const objectID = separator < 0 ? line : line.slice(0, separator);
  const objectPath = separator < 0 ? null : line.slice(separator + 1);
  if (!/^[a-f0-9]{40}(?:[a-f0-9]{24})?$/.test(objectID) ||
      (objectPath !== null && Buffer.byteLength(objectPath, "utf8") > MAX_REV_LIST_LINE_BYTES)) {
    throw new ScannerIntegrityError("rev-list-malformed-entry");
  }
  return { objectID, objectPath };
}

function parseRefLine(line) {
  const separator = line.indexOf(" ");
  const objectID = separator < 0 ? "" : line.slice(0, separator);
  const refName = separator < 0 ? "" : line.slice(separator + 1);
  if (!/^[a-f0-9]{40}(?:[a-f0-9]{24})?$/.test(objectID) ||
      refName.length === 0 ||
      Buffer.byteLength(refName, "utf8") > MAX_METADATA_BYTES) {
    throw new ScannerIntegrityError("for-each-ref-malformed-entry");
  }
  return { objectID, refName };
}

function parseObjectHeader(line, expectedObjectID, expectedSize = null) {
  const match = line.match(/^([a-f0-9]{40}(?:[a-f0-9]{24})?) (blob|tree|commit|tag) ([0-9]+)$/);
  if (!match || match[1] !== expectedObjectID) {
    throw new ScannerIntegrityError("cat-file-malformed-header");
  }
  let size;
  try {
    size = BigInt(match[3]);
  } catch {
    throw new ScannerIntegrityError("cat-file-invalid-size");
  }
  if (size < 0n || (expectedSize !== null && size !== expectedSize)) {
    throw new ScannerIntegrityError("cat-file-size-mismatch");
  }
  return { objectID: match[1], type: match[2], size };
}

function explicitPlaceholder(value) {
  const normalized = value.toUpperCase();
  if (normalized.startsWith("REPLACE_WITH_")) return true;
  if (normalized === "NOT_CONFIGURED" ||
    normalized === "CHANGEME" ||
    /^X{16,}$/.test(normalized) ||
    /^0{16,}$/.test(normalized) ||
    value.includes("$(") ||
    value.includes("${") ||
    value.includes("[REMOVED")) {
    return true;
  }
  const sentinelWords = new Set([
    "A", "ACCESS", "API", "APP", "CHARACTER", "CHARACTERS", "CLIENT",
    "CODE", "CREDENTIAL", "DUMMY", "EXAMPLE", "FIXTURE", "FOR", "HERE",
    "ID", "KEY", "MAPS", "NOT", "OAUTH", "ONLY", "PLACEHOLDER",
    "PRODUCTION", "REMOVED", "SAMPLE", "SDK", "SECRET", "TEST", "TESTS",
    "TOKEN", "UNRESERVED", "USER", "VALUE", "WITH", "YOUR",
  ]);
  const words = normalized.split(/[-_./+~=]+/).filter(Boolean);
  return words.length >= 2 &&
    new Set([
      "DUMMY", "EXAMPLE", "FIXTURE", "PLACEHOLDER", "REMOVED", "SAMPLE",
      "TEST", "YOUR",
    ]).has(words[0]) &&
    words.every(word => sentinelWords.has(word));
}

function productionShaped(value, patternID) {
  if (value.length < 16 || value.length > 192 || explicitPlaceholder(value)) {
    return false;
  }
  if (!/^[A-Za-z0-9_./+~=-]+$/.test(value)) return false;
  const classes = [/[A-Z]/, /[a-z]/, /[0-9]/, /[_./+~=-]/]
    .filter(expression => expression.test(value)).length;
  return classes >= 2 && new Set(value).size >= 8;
}

function scanWindow(window, previousByteCount, windowStart, report) {
  const source = window.toString("latin1");
  for (const pattern of patterns) {
    pattern.expression.lastIndex = 0;
    for (let match = pattern.expression.exec(source);
      match !== null;
      match = pattern.expression.exec(source)) {
      const absoluteEnd = windowStart + BigInt(match.index + match[0].length);
      if (absoluteEnd <= previousByteCount) continue;
      const candidate = match[pattern.valueGroup];
      if (typeof candidate === "string" && productionShaped(candidate, pattern.id)) {
        report(pattern.id);
      }
      if (match[0].length === 0) pattern.expression.lastIndex += 1;
    }
  }
}

function safeMetadata(value) {
  const bytes = Buffer.isBuffer(value) ? value : Buffer.from(value, "utf8");
  return {
    sha256: crypto.createHash("sha256").update(bytes).digest("hex"),
    bytes: bytes.length,
  };
}

class TreeMetadataScanner {
  constructor(objectIDBytes, report) {
    this.objectIDBytes = objectIDBytes;
    this.report = report;
    this.prefix = Buffer.alloc(0);
    this.objectBytesRemaining = 0;
  }

  feed(chunk) {
    let offset = 0;
    while (offset < chunk.length) {
      if (this.objectBytesRemaining > 0) {
        const count = Math.min(
          this.objectBytesRemaining,
          chunk.length - offset,
        );
        this.objectBytesRemaining -= count;
        offset += count;
        continue;
      }
      const nul = chunk.indexOf(0, offset);
      if (nul < 0) {
        const suffix = chunk.subarray(offset);
        if (this.prefix.length + suffix.length > MAX_METADATA_BYTES) {
          throw new ScannerIntegrityError("tree-entry-metadata-too-long");
        }
        this.prefix = this.prefix.length === 0
          ? Buffer.from(suffix)
          : Buffer.concat([this.prefix, suffix]);
        return;
      }
      const suffix = chunk.subarray(offset, nul);
      if (this.prefix.length + suffix.length > MAX_METADATA_BYTES) {
        throw new ScannerIntegrityError("tree-entry-metadata-too-long");
      }
      const prefix = this.prefix.length === 0
        ? suffix
        : Buffer.concat([this.prefix, suffix]);
      this.prefix = Buffer.alloc(0);
      const separator = prefix.indexOf(0x20);
      if (separator < 1 || separator === prefix.length - 1 ||
          !/^[0-7]{5,6}$/.test(prefix.subarray(0, separator).toString("ascii"))) {
        throw new ScannerIntegrityError("tree-entry-malformed");
      }
      const name = prefix.subarray(separator + 1);
      scanWindow(name, 0n, 0n, patternID => {
        this.report(patternID, "tree-entry", name);
      });
      this.objectBytesRemaining = this.objectIDBytes;
      offset = nul + 1;
    }
  }

  finish() {
    if (this.prefix.length !== 0 || this.objectBytesRemaining !== 0) {
      throw new ScannerIntegrityError("tree-entry-incomplete");
    }
  }
}

export async function scanReachableHERECredentialHistory({
  repository,
  chunkBytes = DEFAULT_CHUNK_BYTES,
  onFinding = () => {},
}) {
  const resolvedRepository = exactRepositoryContext(repository);
  if (!Number.isSafeInteger(chunkBytes) ||
      chunkBytes < MINIMUM_CHUNK_BYTES ||
      chunkBytes > MAXIMUM_CHUNK_BYTES) {
    throw new ScannerIntegrityError("invalid-chunk-size");
  }

  let reachableRefs = 0n;
  let reachableObjects = 0n;
  let reachableBlobs = 0n;
  let scannedBytes = 0n;
  let findings = 0n;

  const recordFinding = ({
    objectID,
    patternID,
    locationKind,
    metadataValue = null,
  }) => {
    findings += 1n;
    const metadata = metadataValue === null ? null : safeMetadata(metadataValue);
    onFinding({
      objectID,
      patternID,
      locationKind,
      metadataSHA256: metadata?.sha256 ?? null,
      metadataBytes: metadata?.bytes ?? null,
      findingNumber: findings,
    });
  };

  const refs = startGit(
    resolvedRepository,
    ["for-each-ref", "--format=%(objectname) %(refname)"],
    "for-each-ref",
  );
  refs.child.stdin.end();
  const refReader = new BoundedByteReader(refs.child.stdout, "for-each-ref");
  try {
    while (true) {
      const line = await refReader.readLine(MAX_METADATA_BYTES, true);
      if (line === null) break;
      if (line.length === 0) {
        throw new ScannerIntegrityError("for-each-ref-empty-entry");
      }
      const ref = parseRefLine(line);
      reachableRefs += 1n;
      const reportedPatterns = new Set();
      scanWindow(Buffer.from(ref.refName, "utf8"), 0n, 0n, patternID => {
        if (reportedPatterns.has(patternID)) return;
        reportedPatterns.add(patternID);
        recordFinding({
          objectID: ref.objectID,
          patternID,
          locationKind: "ref",
          metadataValue: ref.refName,
        });
      });
    }
    await requireCleanExit(refs);
  } catch (error) {
    if (!refs.child.killed) refs.child.kill("SIGKILL");
    await Promise.allSettled([refs.exit]);
    if (error instanceof ScannerIntegrityError) throw error;
    throw new ScannerIntegrityError("unexpected-reference-scan-failure");
  }

  const revList = startGit(
    resolvedRepository,
    ["-c", "core.quotePath=true", "rev-list", "--objects", "--all"],
    "rev-list",
  );
  revList.child.stdin.end();
  const batchCheck = startGit(
    resolvedRepository,
    ["cat-file", "--batch-check=%(objectname) %(objecttype) %(objectsize)"],
    "batch-check",
  );
  const batchContent = startGit(
    resolvedRepository,
    ["cat-file", "--batch"],
    "batch-content",
  );
  const processStates = [revList, batchCheck, batchContent];
  const revReader = new BoundedByteReader(revList.child.stdout, "rev-list");
  const checkReader = new BoundedByteReader(batchCheck.child.stdout, "batch-check");
  const contentReader = new BoundedByteReader(batchContent.child.stdout, "batch-content");

  const scanObject = async (entry, checked) => {
    await writeRequest(batchContent.child.stdin, entry.objectID, "batch-content");
    const headerLine = await contentReader.readLine(MAX_PROTOCOL_LINE_BYTES);
    const header = parseObjectHeader(headerLine, entry.objectID, checked.size);
    if (header.type !== checked.type) {
      throw new ScannerIntegrityError("batch-content-type-mismatch");
    }
    if (header.type === "blob") reachableBlobs += 1n;
    scannedBytes += header.size;
    let remaining = header.size;
    let consumed = 0n;
    let overlap = Buffer.alloc(0);
    const reportedPatterns = new Set();
    const report = (patternID, locationKind, metadataValue = null) => {
      const metadataKey = metadataValue === null
        ? ""
        : safeMetadata(metadataValue).sha256;
      const key = `${locationKind}:${patternID}:${metadataKey}`;
      if (reportedPatterns.has(key)) return;
      reportedPatterns.add(key);
      recordFinding({
        objectID: entry.objectID,
        patternID,
        locationKind,
        metadataValue,
      });
    };

    if (entry.objectPath !== null) {
      scanWindow(
        Buffer.from(entry.objectPath, "utf8"),
        0n,
        0n,
        patternID => report(patternID, "path", entry.objectPath),
      );
    }
    const treeScanner = header.type === "tree"
      ? new TreeMetadataScanner(entry.objectID.length / 2, report)
      : null;
    const contentLocation = `${header.type}-content`;

    while (remaining > 0n) {
      const requested = Number(
        remaining > BigInt(chunkBytes) ? BigInt(chunkBytes) : remaining,
      );
      const chunk = await contentReader.readAtMost(requested);
      if (!chunk || chunk.length === 0 || BigInt(chunk.length) > remaining) {
        throw new ScannerIntegrityError("batch-content-incomplete-object");
      }
      if (treeScanner) {
        treeScanner.feed(chunk);
      } else {
        const previousByteCount = consumed;
        const windowStart = consumed - BigInt(overlap.length);
        const window = overlap.length === 0
          ? chunk
          : Buffer.concat([overlap, chunk]);
        scanWindow(window, previousByteCount, windowStart, patternID => {
          report(
            patternID,
            contentLocation,
            header.type === "blob" ? entry.objectPath : null,
          );
        });
        overlap = Buffer.from(
          window.subarray(Math.max(0, window.length - MATCH_OVERLAP_BYTES)),
        );
      }
      consumed += BigInt(chunk.length);
      remaining -= BigInt(chunk.length);
    }
    treeScanner?.finish();
    await contentReader.expectByte(0x0a);
  };

  const processBatch = async entries => {
    for (const entry of entries) {
      await writeRequest(batchCheck.child.stdin, entry.objectID, "batch-check");
    }
    for (const entry of entries) {
      const line = await checkReader.readLine(MAX_PROTOCOL_LINE_BYTES);
      const checked = parseObjectHeader(line, entry.objectID);
      reachableObjects += 1n;
      await scanObject(entry, checked);
    }
  };

  try {
    let entries = [];
    while (true) {
      const line = await revReader.readLine(MAX_REV_LIST_LINE_BYTES, true);
      if (line === null) break;
      if (line.length === 0) {
        throw new ScannerIntegrityError("rev-list-empty-entry");
      }
      entries.push(parseRevListLine(line));
      if (entries.length === OBJECT_BATCH_SIZE) {
        await processBatch(entries);
        entries = [];
      }
    }
    if (entries.length > 0) await processBatch(entries);
    batchCheck.child.stdin.end();
    batchContent.child.stdin.end();
    await checkReader.expectEOF();
    await contentReader.expectEOF();
    await Promise.all(processStates.map(requireCleanExit));
  } catch (error) {
    for (const state of processStates) {
      if (!state.child.killed) state.child.kill("SIGKILL");
      if (!state.child.stdin.destroyed) state.child.stdin.destroy();
    }
    await Promise.allSettled(processStates.map(state => state.exit));
    if (error instanceof ScannerIntegrityError) throw error;
    throw new ScannerIntegrityError("unexpected-scanner-failure");
  }

  return {
    reachableRefs,
    reachableObjects,
    reachableBlobs,
    scannedBytes,
    findings,
  };
}

async function main() {
  try {
    const options = parseArguments(process.argv.slice(2));
    let suppressedFindings = 0n;
    const result = await scanReachableHERECredentialHistory({
      ...options,
      onFinding(finding) {
        if (finding.findingNumber <= BigInt(MAX_REPORTED_FINDINGS)) {
          const metadata = finding.metadataSHA256 === null
            ? ""
            : ` metadata_sha256=${finding.metadataSHA256} metadata_bytes=${finding.metadataBytes}`;
          console.error(
            `HERE credential metadata: object=${finding.objectID} location=${finding.locationKind}${metadata} pattern=${finding.patternID}`,
          );
        } else {
          suppressedFindings += 1n;
        }
      },
    });
    if (suppressedFindings > 0n) {
      console.error(
        `HERE credential metadata: ${suppressedFindings} additional finding(s) suppressed.`,
      );
    }
    if (result.findings > 0n) {
      console.error(
        `HERE credential history scan failed: ${result.findings} production-shaped credential pattern(s) remain in reachable Git objects or metadata.`,
      );
      process.exitCode = 1;
      return;
    }
    console.log(
      `HERE credential history scan passed: ${result.reachableRefs} refs and ${result.reachableObjects} reachable objects (${result.reachableBlobs} blobs), ${result.scannedBytes} bytes inspected.`,
    );
  } catch (error) {
    const code = error instanceof ScannerIntegrityError
      ? error.code
      : "unexpected-scanner-failure";
    console.error(
      `HERE credential history scan failed closed: scanner integrity error (${code}).`,
    );
    process.exitCode = 2;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await main();
}
