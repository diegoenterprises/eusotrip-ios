#!/usr/bin/env node

import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";

const root = path.resolve(import.meta.dirname, "..");
const releaseMode = process.argv.includes("--release");
const builtAppArgument = process.argv.find(value => value.startsWith("--built-app="));
const builtAppPath = builtAppArgument
  ? path.resolve(builtAppArgument.slice("--built-app=".length))
  : null;
const expectedSigningTeam = process.env.HERE_OFFLINE_EXPECTED_TEAM_ID?.trim() ?? "";
const expectedSigningAuthority = process.env.HERE_OFFLINE_EXPECTED_SIGNING_AUTHORITY?.trim() ?? "";
const failures = [];
const blockers = [];

const relative = {
  verifier: "scripts/verify-here-offline-contract.mjs",
  offlineRoot: "EusoTrip/Services/HereMaps/Offline",
  offlineUIRoot: "EusoTrip/Views/Maps/Offline",
  runtime: "EusoTrip/Services/HereMaps/Offline/SDK/HereSDKRuntime.swift",
  engine: "EusoTrip/Services/HereMaps/Offline/Core/OfflineMapEngine.swift",
  coordinator: "EusoTrip/Services/HereMaps/Offline/Core/OfflineMapCoordinator.swift",
  mapModels: "EusoTrip/Services/HereMaps/Offline/Core/OfflineMapModels.swift",
  routeModels: "EusoTrip/Services/HereMaps/Offline/Core/OfflineRouteModels.swift",
  routeStore: "EusoTrip/Services/HereMaps/Offline/Core/CanonicalRoutePackageStore.swift",
  trustedRouteClock: "EusoTrip/Services/HereMaps/Offline/Core/CanonicalRouteTrustedClock.swift",
  coverageResolver: "EusoTrip/Services/HereMaps/Offline/Core/SignedInstalledCoverageResolver.swift",
  navigation: "EusoTrip/Services/HereMaps/Offline/SDK/HereNavigateNavigationSession.swift",
  surface: "EusoTrip/Services/HereMaps/Offline/SDK/HereNavigateOfflineMapSurface.swift",
  productionComposition: "EusoTrip/Services/HereMaps/Offline/OfflineMapProductionComposition.swift",
  appEntry: "EusoTrip/EusoTripApp.swift",
  settingsHost: "EusoTrip/Views/Catalyst/311_CatalystSettings.swift",
  mapHost: "EusoTrip/Services/HereMaps/HereMapWebView.swift",
  info: "EusoTrip/Info.plist",
  sampleConfig: "EusoTrip.xcconfig.sample",
  project: "EusoTrip.xcodeproj/project.pbxproj",
  scheme: "EusoTrip.xcodeproj/xcshareddata/xcschemes/EusoTrip.xcscheme",
  deployScript: "scripts/deploy-testflight.sh",
  exportOptions: "scripts/exportOptions.testflight.plist",
  ipaPreflight: "scripts/preflight-exported-ipa.mjs",
  ipaPreflightTests: "scripts/preflight-exported-ipa.test.mjs",
  ipaAppBinding: "scripts/verify-exported-ipa-app-binding.mjs",
  ipaAppBindingTests: "scripts/verify-exported-ipa-app-binding.test.mjs",
  simulatorSelector: "scripts/select-available-ios-simulator.mjs",
  simulatorSelectorTests: "scripts/select-available-ios-simulator.test.mjs",
  productionGate: "scripts/here-production-gate.mjs",
  artifactHasher: "scripts/hash-release-artifact.mjs",
  artifactHasherTests: "scripts/hash-release-artifact.test.mjs",
  ladderStatus: "scripts/release-ladder-status.mjs",
  ladderStatusTests: "scripts/release-ladder-status.test.mjs",
  ascBuildStatus: "scripts/asc-build-status.mjs",
  ascBuildStatusTests: "scripts/asc-build-status.test.mjs",
  ascLatestBuild: "scripts/asc-latest-build.mjs",
  ascLatestBuildTests: "scripts/asc-latest-build.test.mjs",
  configAttestationVerifier: "scripts/verify-release-config-attestation.mjs",
  configAttestationVerifierTests: "scripts/verify-release-config-attestation.test.mjs",
  deviceAcceptanceVerifier: "scripts/verify-here-offline-device-acceptance.mjs",
  deviceAcceptanceVerifierTests: "scripts/verify-here-offline-device-acceptance.test.mjs",
  githubGovernanceVerifier: "scripts/verify-github-release-governance.mjs",
  githubGovernanceVerifierTests: "scripts/verify-github-release-governance.test.mjs",
  reachableCredentialHistoryVerifier: "scripts/verify-reachable-here-credential-history.mjs",
  reachableCredentialHistoryVerifierTests: "scripts/verify-reachable-here-credential-history.test.mjs",
  sourceContractWorkflow: ".github/workflows/here-offline-source-contract.yml",
  manifest: "EusoTrip/Services/HereMaps/Offline/HERE_SDK_SUPPLY_CHAIN.json",
  styleManifest: "EusoTrip/Services/HereMaps/Offline/HERE_NATIVE_STYLE_SUPPLY_CHAIN.json",
  credentialAttestation: "security/HERE_CREDENTIAL_REMEDIATION.json",
  legacyCredentialTest: "EusoTripTests/HereMaps/HEREAuthServiceTests.swift",
  integrationCredentialInventory: "mapping_audit/here_integration_plan.md",
  integrationCurrentState: "mapping_audit/here_current_state.md",
  integrationRiskRegister: "mapping_audit/risks.md",
  goldIntegrationInventory: "EUSOTRIP2027GOLD/06_Third_Party_Integrations.md",
};
const retainedCredentialExposurePaths = [
  relative.goldIntegrationInventory,
  relative.legacyCredentialTest,
  relative.integrationCurrentState,
  relative.integrationCredentialInventory,
  relative.integrationRiskRegister,
];

const releaseInputPaths = [
  relative.deployScript,
  relative.exportOptions,
  relative.ipaPreflight,
  relative.ipaPreflightTests,
  relative.ipaAppBinding,
  relative.ipaAppBindingTests,
  relative.simulatorSelector,
  relative.simulatorSelectorTests,
  relative.productionGate,
  relative.artifactHasher,
  relative.artifactHasherTests,
  relative.ladderStatus,
  relative.ladderStatusTests,
  relative.ascBuildStatus,
  relative.ascBuildStatusTests,
  relative.ascLatestBuild,
  relative.ascLatestBuildTests,
  relative.configAttestationVerifier,
  relative.configAttestationVerifierTests,
  relative.deviceAcceptanceVerifier,
  relative.deviceAcceptanceVerifierTests,
  relative.githubGovernanceVerifier,
  relative.githubGovernanceVerifierTests,
  relative.reachableCredentialHistoryVerifier,
  relative.reachableCredentialHistoryVerifierTests,
  relative.sourceContractWorkflow,
];

const absolute = value => path.join(root, value);
const resolvedRoot = fs.realpathSync(root);
const reportedUnsafeInputs = new Set();
const committedInputBytes = new Map();

function pathIsWithin(candidate, directory, allowSame = false) {
  const relativePath = path.relative(directory, candidate);
  return (allowSame && relativePath === "") || (
    relativePath !== "" &&
    relativePath !== ".." &&
    !relativePath.startsWith(`..${path.sep}`) &&
    !path.isAbsolute(relativePath)
  );
}

function reportUnsafeRepositoryInput(value, context = "repository input") {
  const key = `${context}\0${value}`;
  if (reportedUnsafeInputs.has(key)) return;
  reportedUnsafeInputs.add(key);
  failures.push(`${value}: ${context} must be a regular non-symlink file within the repository root`);
}

function repositoryEntryStatus(value, expectedKind = "file", context = "repository input") {
  if (!safeRepositoryRelativePath(value)) {
    reportUnsafeRepositoryInput(value, context);
    return { status: "unsafe" };
  }
  const candidate = absolute(value);
  if (!fs.existsSync(candidate)) return { status: "missing" };

  let cursor = root;
  const components = value.split("/");
  try {
    for (let index = 0; index < components.length; index += 1) {
      cursor = path.join(cursor, components[index]);
      const metadata = fs.lstatSync(cursor, { bigint: true });
      if (metadata.isSymbolicLink()) {
        reportUnsafeRepositoryInput(value, context);
        return { status: "unsafe" };
      }
      const isLast = index === components.length - 1;
      if (!isLast && !metadata.isDirectory()) {
        reportUnsafeRepositoryInput(value, context);
        return { status: "unsafe" };
      }
      if (isLast && ((expectedKind === "file" && !metadata.isFile()) ||
          (expectedKind === "directory" && !metadata.isDirectory()))) {
        reportUnsafeRepositoryInput(value, context);
        return { status: "unsafe" };
      }
    }
    const realPath = fs.realpathSync(candidate);
    if (!pathIsWithin(realPath, resolvedRoot)) {
      reportUnsafeRepositoryInput(value, context);
      return { status: "unsafe" };
    }
    return {
      status: "ok",
      path: candidate,
      realPath,
      metadata: fs.lstatSync(candidate, { bigint: true }),
    };
  } catch {
    reportUnsafeRepositoryInput(value, context);
    return { status: "unsafe" };
  }
}

function statIdentity(metadata) {
  return [
    metadata.dev,
    metadata.ino,
    metadata.mode,
    metadata.size,
    metadata.mtimeNs,
    metadata.ctimeNs,
  ].map(value => String(value)).join(":");
}

function withPinnedRegularFile(file, allowedRoot, callback, expectedPathMetadata = null) {
  const resolvedAllowedRoot = fs.realpathSync(allowedRoot);
  const beforePath = fs.lstatSync(file, { bigint: true });
  if (!beforePath.isFile() || beforePath.isSymbolicLink()) throw new Error("UnsafeRegularFile");
  if (expectedPathMetadata && statIdentity(beforePath) !== statIdentity(expectedPathMetadata)) {
    throw new Error("ChangedBeforeOpen");
  }
  const beforeRealPath = fs.realpathSync(file);
  if (!pathIsWithin(beforeRealPath, resolvedAllowedRoot)) throw new Error("OutOfRootFile");

  const noFollow = fs.constants.O_NOFOLLOW ?? 0;
  const descriptor = fs.openSync(file, fs.constants.O_RDONLY | noFollow);
  try {
    const beforeDescriptor = fs.fstatSync(descriptor, { bigint: true });
    if (!beforeDescriptor.isFile() ||
        beforeDescriptor.dev !== beforePath.dev ||
        beforeDescriptor.ino !== beforePath.ino) {
      throw new Error("ChangedBeforeOpen");
    }
    const value = callback(descriptor, beforeDescriptor);
    const afterDescriptor = fs.fstatSync(descriptor, { bigint: true });
    const afterPath = fs.lstatSync(file, { bigint: true });
    const afterRealPath = fs.realpathSync(file);
    if (statIdentity(afterDescriptor) !== statIdentity(beforeDescriptor) ||
        afterPath.isSymbolicLink() ||
        statIdentity(afterPath) !== statIdentity(afterDescriptor) ||
        afterRealPath !== beforeRealPath ||
        !pathIsWithin(afterRealPath, resolvedAllowedRoot)) {
      throw new Error("ChangedDuringRead");
    }
    return value;
  } finally {
    fs.closeSync(descriptor);
  }
}

function readRepositoryBytesUncached(value, context = "repository input") {
  const entry = repositoryEntryStatus(value, "file", context);
  if (entry.status !== "ok") return null;
  try {
    return withPinnedRegularFile(entry.path, root, descriptor => fs.readFileSync(descriptor));
  } catch {
    reportUnsafeRepositoryInput(value, context);
    return null;
  }
}

function readRepositoryBytes(value, context = "repository input") {
  const committed = committedInputBytes.get(value);
  return committed ? Buffer.from(committed) : readRepositoryBytesUncached(value, context);
}

const exists = value => repositoryEntryStatus(value).status === "ok";
const read = value => readRepositoryBytes(value)?.toString("utf8") ?? "";

function sha256PinnedFile(file, allowedRoot) {
  return withPinnedRegularFile(file, allowedRoot, descriptor => {
    const hash = crypto.createHash("sha256");
    const chunk = Buffer.allocUnsafe(1024 * 1024);
    while (true) {
      const bytesRead = fs.readSync(descriptor, chunk, 0, chunk.length, null);
      if (bytesRead === 0) break;
      hash.update(chunk.subarray(0, bytesRead));
    }
    return hash.digest("hex");
  });
}

function sha256RepositoryFile(value, context = "repository input") {
  const entry = repositoryEntryStatus(value, "file", context);
  if (entry.status !== "ok") return null;
  try {
    return sha256PinnedFile(entry.path, root);
  } catch {
    reportUnsafeRepositoryInput(value, context);
    return null;
  }
}

const sha256 = file => sha256PinnedFile(file, path.dirname(file));

function parsePlist(file) {
  return JSON.parse(execFileSync(
    "/usr/bin/plutil",
    ["-convert", "json", "-o", "-", file],
    { encoding: "utf8" },
  ));
}

function parseRepositoryPlist(value) {
  const contents = readRepositoryBytes(value);
  if (!contents) throw new Error("UnsafeRepositoryPlist");
  return JSON.parse(execFileSync(
    "/usr/bin/plutil",
    ["-convert", "json", "-o", "-", "-"],
    { encoding: "utf8", input: contents },
  ));
}

function walkAbsolute(directory) {
  if (!fs.existsSync(directory)) return [];
  const files = [];
  const queue = [directory];
  while (queue.length) {
    const current = queue.pop();
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const entryPath = path.join(current, entry.name);
      if (entry.isDirectory()) queue.push(entryPath);
      else files.push(entryPath);
    }
  }
  return files;
}

function canonicalTreeHash(directory) {
  const hash = crypto.createHash("sha256");
  const entries = [];
  const rootMetadata = fs.lstatSync(directory, { bigint: true });
  if (!rootMetadata.isDirectory() || rootMetadata.isSymbolicLink()) {
    throw new Error("UnsafeTreeRoot");
  }
  const resolvedTreeRoot = fs.realpathSync(directory);
  const mode = metadata => (Number(metadata.mode) & 0o7777).toString(8).padStart(4, "0");
  const seals = [];
  const visit = current => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const entryPath = path.join(current, entry.name);
      const metadata = fs.lstatSync(entryPath, { bigint: true });
      if (metadata.isSymbolicLink() || (!metadata.isDirectory() && !metadata.isFile())) {
        throw new Error("UnsafeTreeEntry");
      }
      const resolvedEntry = fs.realpathSync(entryPath);
      if (!pathIsWithin(resolvedEntry, resolvedTreeRoot)) throw new Error("OutOfRootTreeEntry");
      entries.push(entryPath);
      if (metadata.isDirectory()) visit(entryPath);
    }
  };
  visit(directory);
  hash.update(`R\0${mode(rootMetadata)}\0`);
  for (const entryPath of entries.sort((left, right) => left.localeCompare(right))) {
    const relativePath = path.relative(directory, entryPath).split(path.sep).join("/");
    const metadata = fs.lstatSync(entryPath, { bigint: true });
    if (metadata.isDirectory()) {
      hash.update(`D\0${relativePath}\0${mode(metadata)}\0`);
    } else if (metadata.isFile()) {
      hash.update(`F\0${relativePath}\0${mode(metadata)}\0${metadata.size}\0`);
      hash.update(withPinnedRegularFile(
        entryPath,
        directory,
        descriptor => fs.readFileSync(descriptor),
        metadata,
      ));
    }
    seals.push({ entryPath, identity: statIdentity(metadata), realPath: fs.realpathSync(entryPath) });
  }
  if (statIdentity(fs.lstatSync(directory, { bigint: true })) !== statIdentity(rootMetadata) ||
      fs.realpathSync(directory) !== resolvedTreeRoot) {
    throw new Error("ChangedTreeRoot");
  }
  for (const seal of seals) {
    if (statIdentity(fs.lstatSync(seal.entryPath, { bigint: true })) !== seal.identity ||
        fs.realpathSync(seal.entryPath) !== seal.realPath) {
      throw new Error("ChangedTreeEntry");
    }
  }
  return hash.digest("hex");
}

function normalizedFrameworkHash(frameworkDirectory) {
  if (!fs.existsSync(frameworkDirectory)) return null;
  const sourceMetadata = fs.lstatSync(frameworkDirectory);
  if (!sourceMetadata.isDirectory() || sourceMetadata.isSymbolicLink()) return null;
  const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "eusotrip-here-framework-"));
  const copy = path.join(temporaryRoot, path.basename(frameworkDirectory));
  try {
    fs.cpSync(frameworkDirectory, copy, { recursive: true });
    for (const file of walkAbsolute(copy)) {
      if (file.includes(`${path.sep}_CodeSignature${path.sep}`) || path.basename(file) === "CodeResources") {
        fs.rmSync(file, { force: true });
      }
    }
    for (const directory of [
      ...walkAbsoluteDirectories(copy).filter(value => path.basename(value) === "_CodeSignature"),
    ]) {
      fs.rmSync(directory, { recursive: true, force: true });
    }
    const infoPath = path.join(copy, "Info.plist");
    if (fs.existsSync(infoPath)) {
      const executable = parsePlist(infoPath).CFBundleExecutable;
      if (!safePathComponent(executable)) return null;
      const binary = path.join(copy, executable);
      if (!fs.existsSync(binary)) return null;
      const binaryMetadata = fs.lstatSync(binary);
      if (!binaryMetadata.isFile() || binaryMetadata.isSymbolicLink()) return null;
      const resolvedCopy = fs.realpathSync(copy);
      const resolvedBinary = fs.realpathSync(binary);
      if (!isDescendantPath(resolvedBinary, resolvedCopy)) return null;
      try {
        execFileSync("/usr/bin/codesign", ["--remove-signature", resolvedBinary], { stdio: "ignore" });
      } catch {
        // Vendor binaries may already be unsigned; their bytes remain valid input.
      }
    } else return null;
    return canonicalTreeHash(copy);
  } catch {
    return null;
  } finally {
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
  }
}

function walkAbsoluteDirectories(directory) {
  if (!fs.existsSync(directory)) return [];
  const directories = [];
  const queue = [directory];
  while (queue.length) {
    const current = queue.pop();
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const entryPath = path.join(current, entry.name);
      directories.push(entryPath);
      queue.push(entryPath);
    }
  }
  return directories;
}

function safeRepositoryRelativePath(value) {
  if (typeof value !== "string" || value.length === 0 || value.includes("\\") || value.includes("\0")) {
    return false;
  }
  if (path.posix.isAbsolute(value)) return false;
  const normalized = path.posix.normalize(value);
  return normalized === value && normalized !== ".." && !normalized.startsWith("../");
}

function safePathComponent(value) {
  return typeof value === "string" &&
    value.length > 0 &&
    value !== "." &&
    value !== ".." &&
    !value.includes("/") &&
    !value.includes("\\") &&
    !value.includes("\0") &&
    path.posix.basename(value) === value;
}

function resolveRealXCFrameworkLibrary(frameworkDirectory, library) {
  if (!safePathComponent(library?.LibraryIdentifier) ||
      !safePathComponent(library?.LibraryPath)) return null;
  const identifierDirectory = path.join(frameworkDirectory, library.LibraryIdentifier);
  const candidate = path.join(identifierDirectory, library.LibraryPath);
  if (!fs.existsSync(identifierDirectory) || !fs.existsSync(candidate)) return null;
  const identifierMetadata = fs.lstatSync(identifierDirectory);
  const candidateMetadata = fs.lstatSync(candidate);
  if (!identifierMetadata.isDirectory() || identifierMetadata.isSymbolicLink() ||
      !candidateMetadata.isDirectory() || candidateMetadata.isSymbolicLink()) return null;
  const resolvedRoot = fs.realpathSync(frameworkDirectory);
  const resolvedIdentifier = fs.realpathSync(identifierDirectory);
  const resolvedCandidate = fs.realpathSync(candidate);
  if (!isDescendantPath(resolvedIdentifier, resolvedRoot) ||
      !isDescendantPath(resolvedCandidate, resolvedRoot)) return null;
  return resolvedCandidate;
}

function isDescendantPath(candidate, directory) {
  const relativePath = path.relative(directory, candidate);
  return relativePath !== "" &&
    relativePath !== ".." &&
    !relativePath.startsWith(`..${path.sep}`) &&
    !path.isAbsolute(relativePath);
}

function swiftCodeOnly(source) {
  let result = "";
  let index = 0;
  let blockDepth = 0;
  let inLineComment = false;
  let stringDelimiter = null;
  while (index < source.length) {
    if (inLineComment) {
      if (source[index] === "\n") {
        inLineComment = false;
        result += "\n";
      } else result += " ";
      index += 1;
      continue;
    }
    if (blockDepth > 0) {
      if (source.startsWith("/*", index)) {
        blockDepth += 1;
        result += "  ";
        index += 2;
      } else if (source.startsWith("*/", index)) {
        blockDepth -= 1;
        result += "  ";
        index += 2;
      } else {
        result += source[index] === "\n" ? "\n" : " ";
        index += 1;
      }
      continue;
    }
    if (stringDelimiter) {
      if (source.startsWith(stringDelimiter, index)) {
        result += " ".repeat(stringDelimiter.length);
        index += stringDelimiter.length;
        stringDelimiter = null;
      } else if (source[index] === "\\" && stringDelimiter === '"') {
        result += "  ";
        index += Math.min(2, source.length - index);
      } else {
        result += source[index] === "\n" ? "\n" : " ";
        index += 1;
      }
      continue;
    }
    if (source.startsWith("//", index)) {
      inLineComment = true;
      result += "  ";
      index += 2;
    } else if (source.startsWith("/*", index)) {
      blockDepth = 1;
      result += "  ";
      index += 2;
    } else if (source.startsWith('"""', index)) {
      stringDelimiter = '"""';
      result += "   ";
      index += 3;
    } else if (source[index] === '"') {
      stringDelimiter = '"';
      result += " ";
      index += 1;
    } else {
      result += source[index];
      index += 1;
    }
  }
  return result;
}

function compiledSwiftCodeOnly(source) {
  const lines = swiftCodeOnly(source).split(/\r?\n/);
  const stack = [];
  let active = true;
  const output = [];
  const releaseCondition = condition => {
    const compact = condition.replace(/\s+/g, "");
    if (compact === "true" || compact === "!DEBUG") return true;
    if (compact === "false" || compact === "DEBUG") return false;
    return null;
  };
  for (const line of lines) {
    const directive = line.trim();
    if (directive.startsWith("#if ")) {
      const condition = releaseCondition(directive.slice(4).trim());
      const branchActive = condition === true;
      stack.push({
        parentActive: active,
        anyTaken: branchActive,
        unknown: condition === null,
      });
      active = active && branchActive;
      output.push("");
      continue;
    }
    if (directive.startsWith("#elseif ") && stack.length) {
      const frame = stack[stack.length - 1];
      const condition = releaseCondition(directive.slice(8).trim());
      frame.unknown ||= condition === null;
      const branchActive = !frame.unknown && !frame.anyTaken && condition === true;
      frame.anyTaken ||= branchActive;
      active = frame.parentActive && branchActive;
      output.push("");
      continue;
    }
    if (directive === "#else" && stack.length) {
      const frame = stack[stack.length - 1];
      const branchActive = !frame.unknown && !frame.anyTaken;
      frame.anyTaken = true;
      active = frame.parentActive && branchActive;
      output.push("");
      continue;
    }
    if (directive === "#endif" && stack.length) {
      const frame = stack.pop();
      active = frame.parentActive;
      output.push("");
      continue;
    }
    output.push(active ? line : "");
  }
  return output.join("\n");
}

function swiftDeclarationBody(source, declarationPattern, startIndex = 0) {
  const tail = source.slice(startIndex);
  const match = tail.match(declarationPattern);
  if (!match || match.index === undefined) return "";
  const declarationStart = startIndex + match.index;
  const openingBrace = source.indexOf("{", declarationStart + match[0].length - 1);
  if (openingBrace < 0) return "";
  let depth = 0;
  for (let index = openingBrace; index < source.length; index += 1) {
    if (source[index] === "{") depth += 1;
    else if (source[index] === "}") {
      depth -= 1;
      if (depth === 0) return source.slice(openingBrace + 1, index);
    }
  }
  return "";
}

function parsePBXObjects(source) {
  const lines = source.split(/\r?\n/);
  const objects = new Map();
  for (let index = 0; index < lines.length; index += 1) {
    const start = lines[index].match(/^\s*([A-Za-z0-9]{24})(?: \/\*.*\*\/)? = \{.*$/);
    if (!start) continue;
    const body = [lines[index]];
    let cursor = index + 1;
    if (!lines[index].trim().endsWith("};")) {
      while (cursor < lines.length) {
        body.push(lines[cursor]);
        if (lines[cursor].trim() === "};") break;
        cursor += 1;
      }
    } else {
      cursor = index;
    }
    const text = body.join("\n");
    const isa = text.match(/\bisa = ([A-Za-z0-9]+);/)?.[1] ?? null;
    // TargetAttributes and other nested dictionaries can reuse a target ID
    // without an `isa`; never let those pseudo-objects replace the real PBX
    // object resolved from its section.
    if (isa) objects.set(start[1], { id: start[1], isa, text });
    index = cursor;
  }
  return objects;
}

function listObjectIDs(object, property) {
  const match = object?.text.match(new RegExp(`\\b${property} = \\(([\\s\\S]*?)\\);`));
  return match ? [...match[1].matchAll(/\b([A-Za-z0-9]{24})\b/g)].map(item => item[1]) : [];
}

function pbxPath(object) {
  const raw = object?.text.match(/\bpath = ("(?:[^"\\]|\\.)*"|[^;]+);/)?.[1]?.trim();
  if (!raw) return null;
  if (raw.startsWith('"')) {
    try { return JSON.parse(raw); } catch { return null; }
  }
  return raw;
}

function makeProjectInspector(source, targetName) {
  const objects = parsePBXObjects(source);
  const target = [...objects.values()].find(object =>
    object.isa === "PBXNativeTarget" &&
    new RegExp(`\\bname = ${targetName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")};`).test(object.text));
  const buildPhaseIDs = listObjectIDs(target, "buildPhases");
  const sources = buildPhaseIDs.map(id => objects.get(id)).find(object => object?.isa === "PBXSourcesBuildPhase");
  const resources = buildPhaseIDs.map(id => objects.get(id)).find(object => object?.isa === "PBXResourcesBuildPhase");
  const frameworks = buildPhaseIDs.map(id => objects.get(id)).find(object => object?.isa === "PBXFrameworksBuildPhase");
  const embeds = buildPhaseIDs
    .map(id => objects.get(id))
    .filter(object => object?.isa === "PBXCopyFilesBuildPhase" && /\bdstSubfolderSpec = 10;/.test(object.text));
  const synchronizedRoots = listObjectIDs(target, "fileSystemSynchronizedGroups")
    .map(id => objects.get(id))
    .filter(object => object?.isa === "PBXFileSystemSynchronizedRootGroup");

  function explicitBuildFile(relativePath, phase) {
    const basename = path.basename(relativePath);
    const refs = [...objects.values()].filter(object => {
      if (object.isa !== "PBXFileReference") return false;
      const candidate = pbxPath(object);
      return candidate === relativePath || candidate === basename;
    });
    for (const ref of refs) {
      const buildFiles = [...objects.values()].filter(object =>
        object.isa === "PBXBuildFile" && new RegExp(`\\bfileRef = ${ref.id}\\b`).test(object.text));
      const match = buildFiles.find(buildFile => new RegExp(`\\b${buildFile.id}\\b`).test(phase?.text ?? ""));
      if (match) return match;
    }
    return null;
  }

  function synchronizedRegistration(relativePath) {
    for (const group of synchronizedRoots) {
      const rootPath = pbxPath(group);
      if (!rootPath || !(relativePath === rootPath || relativePath.startsWith(`${rootPath}/`))) continue;
      const memberPath = relativePath.slice(rootPath.length + 1);
      const exceptionIDs = listObjectIDs(group, "exceptions");
      const excluded = exceptionIDs.some(id => {
        const exception = objects.get(id);
        const membership = exception?.text.match(/\bmembershipExceptions = \(([\s\S]*?)\);/)?.[1] ?? "";
        return membership.split(/\r?\n/)
          .map(line => line.trim().replace(/,$/, "").replace(/^"|"$/g, ""))
          .includes(memberPath);
      });
      return !excluded;
    }
    return false;
  }

  return {
    targetID: target?.id ?? null,
    targetExists: Boolean(target),
    sourceRegistered(relativePath) {
      return synchronizedRegistration(relativePath) || Boolean(explicitBuildFile(relativePath, sources));
    },
    resourceRegistered(relativePath) {
      return synchronizedRegistration(relativePath) || Boolean(explicitBuildFile(relativePath, resources));
    },
    frameworkLinked(relativePath) {
      return Boolean(explicitBuildFile(relativePath, frameworks));
    },
    frameworkEmbedded(relativePath) {
      return embeds.some(phase => Boolean(explicitBuildFile(relativePath, phase)));
    },
  };
}

function requireFiles(files) {
  for (const file of files) {
    if (!exists(file)) failures.push(`${file}: required file is missing`);
  }
}

function requireText(file, snippets) {
  if (!exists(file)) return;
  const source = read(file);
  for (const snippet of snippets) {
    if (!source.includes(snippet)) {
      failures.push(`${file}: missing ${JSON.stringify(snippet)}`);
    }
  }
}

function denyText(file, snippets) {
  if (!exists(file)) return;
  const source = read(file);
  for (const snippet of snippets) {
    if (source.includes(snippet)) {
      failures.push(`${file}: forbidden ${JSON.stringify(snippet)}`);
    }
  }
}

function gitPathIsTrackedAndUnchanged(file) {
  const entry = repositoryEntryStatus(file);
  if (entry.status !== "ok") return false;
  const tracked = spawnSync(
    "/usr/bin/git",
    ["ls-files", "--error-unmatch", "--", file],
    { cwd: root, stdio: "ignore" },
  );
  if (tracked.status !== 0) return false;
  const treeEntry = spawnSync(
    "/usr/bin/git",
    ["ls-tree", "HEAD", "--", file],
    { cwd: root, encoding: "utf8" },
  );
  const match = treeEntry.status === 0
    ? treeEntry.stdout.match(/^(100644|100755)\s+blob\s+[a-f0-9]+\t/m)
    : null;
  if (!match) return false;
  const headBlob = spawnSync(
    "/usr/bin/git",
    ["show", `HEAD:${file}`],
    { cwd: root, encoding: null, maxBuffer: 64 * 1024 * 1024 },
  );
  const currentBytes = readRepositoryBytesUncached(file);
  if (headBlob.status !== 0 || !Buffer.isBuffer(headBlob.stdout) || !currentBytes) return false;
  const headExecutable = match[1] === "100755";
  const currentExecutable = (Number(entry.metadata.mode) & 0o111) !== 0;
  if (headExecutable !== currentExecutable || !headBlob.stdout.equals(currentBytes)) return false;
  committedInputBytes.set(file, Buffer.from(currentBytes));
  return true;
}

function containsProductionShapedHERECredentialLiteral(source) {
  if (/HERE-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i.test(source)) {
    return true;
  }
  if (/HERE_API_KEY\s*=\s*(?!\[REMOVED)[A-Za-z0-9_-]{20,}/.test(source)) {
    return true;
  }
  for (const match of source.matchAll(/[`"]([A-Za-z0-9_-]{20,})[`"]/g)) {
    const candidate = match[1];
    if (/[A-Z]/.test(candidate) && /[a-z]/.test(candidate) && /[0-9]/.test(candidate)) {
      return true;
    }
  }
  return false;
}

function valueContainsAnyCredential(value, credentials) {
  if (typeof value === "string") return credentials.some(credential => value.includes(credential));
  if (Array.isArray(value)) return value.some(item => valueContainsAnyCredential(item, credentials));
  if (value && typeof value === "object") {
    return Object.values(value).some(item => valueContainsAnyCredential(item, credentials));
  }
  return false;
}

function credentialByteSequences(credentials) {
  return credentials.flatMap(credential => {
    const utf8 = Buffer.from(credential, "utf8");
    const utf16LittleEndian = Buffer.from(credential, "utf16le");
    const utf16BigEndian = Buffer.from(utf16LittleEndian);
    utf16BigEndian.swap16();
    return [utf8, utf16LittleEndian, utf16BigEndian];
  }).filter(sequence => sequence.length > 0);
}

function fileContainsAnyByteSequence(file, sequences) {
  if (!sequences.length) return false;
  const descriptor = fs.openSync(file, "r");
  const chunkSize = 1024 * 1024;
  const overlapSize = Math.max(...sequences.map(sequence => sequence.length)) - 1;
  let overlap = Buffer.alloc(0);
  try {
    while (true) {
      const chunk = Buffer.allocUnsafe(chunkSize);
      const bytesRead = fs.readSync(descriptor, chunk, 0, chunk.length, null);
      if (bytesRead === 0) return false;
      const window = Buffer.concat([overlap, chunk.subarray(0, bytesRead)]);
      if (sequences.some(sequence => window.indexOf(sequence) >= 0)) return true;
      overlap = overlapSize > 0
        ? Buffer.from(window.subarray(Math.max(0, window.length - overlapSize)))
        : Buffer.alloc(0);
    }
  } finally {
    fs.closeSync(descriptor);
  }
}

function walkFiles(directory, extension) {
  const rootEntry = repositoryEntryStatus(directory, "directory", "repository source tree");
  if (rootEntry.status === "missing") return [];
  if (rootEntry.status !== "ok") return [];
  const files = [];
  const queue = [rootEntry.path];
  while (queue.length) {
    const current = queue.pop();
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const entryPath = path.join(current, entry.name);
      const relativeEntryPath = path.relative(root, entryPath).split(path.sep).join("/");
      let metadata;
      try {
        metadata = fs.lstatSync(entryPath, { bigint: true });
      } catch {
        reportUnsafeRepositoryInput(relativeEntryPath, "repository source tree entry");
        continue;
      }
      if (metadata.isSymbolicLink() || (!metadata.isDirectory() && !metadata.isFile())) {
        reportUnsafeRepositoryInput(relativeEntryPath, "repository source tree entry");
        continue;
      }
      let resolvedEntry;
      try {
        resolvedEntry = fs.realpathSync(entryPath);
      } catch {
        reportUnsafeRepositoryInput(relativeEntryPath, "repository source tree entry");
        continue;
      }
      if (!pathIsWithin(resolvedEntry, resolvedRoot)) {
        reportUnsafeRepositoryInput(relativeEntryPath, "repository source tree entry");
        continue;
      }
      if (metadata.isDirectory()) queue.push(entryPath);
      else if (!extension || entry.name.endsWith(extension)) files.push(entryPath);
    }
  }
  return files;
}

function readWalkedRepositoryFile(file, context = "repository source tree entry") {
  const value = path.relative(root, file).split(path.sep).join("/");
  return readRepositoryBytes(value, context)?.toString("utf8") ?? "";
}

requireFiles([
  relative.verifier,
  relative.runtime,
  relative.engine,
  relative.coordinator,
  relative.mapModels,
  relative.routeModels,
  relative.routeStore,
  relative.trustedRouteClock,
  relative.coverageResolver,
  relative.navigation,
  relative.surface,
  relative.appEntry,
  relative.settingsHost,
  relative.mapHost,
  relative.info,
  relative.sampleConfig,
  relative.project,
  relative.scheme,
  relative.deployScript,
  relative.exportOptions,
  relative.ipaPreflight,
  relative.ipaPreflightTests,
  relative.simulatorSelector,
  relative.simulatorSelectorTests,
  relative.productionGate,
  relative.artifactHasher,
  relative.artifactHasherTests,
  relative.ladderStatus,
  relative.ladderStatusTests,
  relative.ascBuildStatus,
  relative.ascBuildStatusTests,
  relative.ascLatestBuild,
  relative.ascLatestBuildTests,
  relative.configAttestationVerifier,
  relative.configAttestationVerifierTests,
  relative.deviceAcceptanceVerifier,
  relative.deviceAcceptanceVerifierTests,
  relative.githubGovernanceVerifier,
  relative.githubGovernanceVerifierTests,
  relative.sourceContractWorkflow,
  relative.manifest,
  relative.styleManifest,
  relative.credentialAttestation,
  relative.legacyCredentialTest,
  relative.integrationCredentialInventory,
  relative.integrationCurrentState,
  relative.integrationRiskRegister,
  relative.goldIntegrationInventory,
]);

for (const [file, label] of [
  [relative.verifier, "HERE offline release verifier"],
  [relative.manifest, "HERE SDK supply-chain manifest"],
  [relative.styleManifest, "HERE native-style supply-chain manifest"],
  [relative.credentialAttestation, "HERE credential-remediation attestation"],
  ...releaseInputPaths.map(file => [file, `release input ${file}`]),
  ...retainedCredentialExposurePaths.map(file => [file, `sanitized credential-incident file ${file}`]),
]) {
  if (!gitPathIsTrackedAndUnchanged(file)) {
    blockers.push(`${label} is not committed unchanged in HEAD`);
  }
}

for (const executable of [relative.deployScript, relative.ascBuildStatus, relative.ascLatestBuild]) {
  const entry = repositoryEntryStatus(executable);
  if (entry.status === "ok" && (Number(entry.metadata.mode) & 0o111) === 0) {
    failures.push(`${executable}: release entrypoint must retain an executable POSIX mode`);
  }
}

try {
  const worktreeStatus = execFileSync(
    "/usr/bin/git",
    ["status", "--porcelain=v1", "--untracked-files=all"],
    { cwd: root, encoding: "utf8" },
  ).trim();
  if (worktreeStatus) blockers.push("release repository worktree does not exactly match HEAD");
} catch {
  failures.push("git worktree inspection failed while binding the release source tree");
}

for (const file of [...retainedCredentialExposurePaths, relative.credentialAttestation]) {
  if (exists(file) && containsProductionShapedHERECredentialLiteral(read(file))) {
    failures.push(`${file}: production-shaped HERE credential literal remains in a sanitized incident file`);
  }
}

requireText(relative.info, [
  "<key>HERESDKAccessKeyID</key>",
  "$(HERE_SDK_ACCESS_KEY_ID)",
  "<key>HERESDKAccessKeySecret</key>",
  "$(HERE_SDK_ACCESS_KEY_SECRET)",
  "<key>EusoRoutePlanIssuer</key>",
  "$(EUSOTRIP_ROUTE_PLAN_ISSUER)",
  "<key>EusoRoutePlanAudience</key>",
  "$(EUSOTRIP_ROUTE_PLAN_AUDIENCE)",
  "<key>EusoRoutePlanKeyID</key>",
  "$(EUSOTRIP_ROUTE_PLAN_KEY_ID)",
  "<key>EusoRoutePlanPublicKey</key>",
  "$(EUSOTRIP_ROUTE_PLAN_PUBLIC_KEY_BASE64)",
]);
requireText(relative.sampleConfig, [
  "HERE_SDK_ACCESS_KEY_ID",
  "HERE_SDK_ACCESS_KEY_SECRET",
  "EUSOTRIP_ROUTE_PLAN_ISSUER",
  "EUSOTRIP_ROUTE_PLAN_AUDIENCE",
  "EUSOTRIP_ROUTE_PLAN_KEY_ID",
  "EUSOTRIP_ROUTE_PLAN_PUBLIC_KEY_BASE64",
]);
requireText(relative.legacyCredentialTest, [
  "fixture-secret_with-unreserved-characters",
]);
requireText(relative.integrationCredentialInventory, [
  "[REMOVED: revoke and inject via untracked configuration]",
]);
requireText(relative.integrationCurrentState, [
  "HERE_API_KEY = [REMOVED: revoke in HERE portal]",
  "**`[REMOVED: revoke in HERE portal]`**",
]);
requireText(relative.integrationRiskRegister, [
  "[REMOVED: revoke in HERE portal]",
  "[REMOVED: rotate and reinject]",
]);
requireText(relative.goldIntegrationInventory, [
  "Identifier removed; rotate and inject through untracked configuration.",
  "credential inventory must be verified in the HERE portal",
]);

requireText(relative.runtime, [
  "#if canImport(heresdk)",
  "options.offlineMode = connectivity == .radioSilent",
  "options.persistentMapStoragePath",
  "options.layerConfiguration",
  ".detailRendering",
  ".rendering",
  ".navigation",
  ".offlineSearch",
  ".offlineRouting",
  ".truck",
  ".truckServiceAttributes",
  ".fuelStationAttributes",
  ".terrain",
  "SDKNativeEngine.makeSharedInstance(options: options)",
  "passThroughFeatures = []",
  "missingLegalNotice",
  "validateConnectivityTransition(to: connectivity)",
  "validateEngineRestart()",
]);
denyText(relative.runtime, [
  "public func start(",
  "public func stop(",
]);

const runtime = exists(relative.runtime) ? read(relative.runtime) : "";
const offlineFlag = runtime.indexOf("options.offlineMode = connectivity == .radioSilent");
const engineStart = runtime.indexOf("SDKNativeEngine.makeSharedInstance(options: options)");
if (offlineFlag < 0 || engineStart < 0 || offlineFlag > engineStart) {
  failures.push(`${relative.runtime}: radio silence must be selected before SDK initialization`);
}

requireText(relative.coordinator, [
  "downloadableCatalogState",
  "installedRegionsState",
  "storageState",
  "reloadInventory()",
  "beginOperation",
  "finishSuccessfulOperation",
]);
requireText(relative.mapModels, [
  "static let offlineVoiceGuidance",
  "static let fullRoadFreightParity",
  ".offlineVoiceGuidance",
]);
requireText(relative.routeModels, [
  "case serverCanonical",
  "case hereOfflineLocal",
  "case rail",
  "case vessel",
  "supportsHEREOfflineCalculation",
  "Truck routing requires an explicit truck profile.",
]);
requireText(relative.routeStore, [
  "tenantID",
  "userID",
  "loadID",
  "options: .atomic",
  "case stale",
  "CanonicalRouteStoreRootLeaseRegistry.shared.acquire",
  "CanonicalRouteTrustedClock",
  "trustedClock.establishAuthenticatedAnchor",
  "trustedClock.invalidateAll",
]);
requireText(relative.trustedRouteClock, [
  "ProcessInfo.processInfo.systemUptime",
  "case monotonicUptimeRegressed",
  "case authenticatedAnchorUnavailable",
  "func establishAuthenticatedAnchor",
]);
requireText(relative.coverageResolver, [
  "actor SignedInstalledCoverageResolver",
  "func resolveInstalledCoverage",
  "coordinateClassifications",
  "payload.catalogVersion",
  "options: .atomic",
]);
const routeStoreCode = exists(relative.routeStore) ? swiftCodeOnly(read(relative.routeStore)) : "";
if (/struct\s+CanonicalRoutePackage\s*:[^{]*\bCodable\b/.test(routeStoreCode)) {
  failures.push(`${relative.routeStore}: verified canonical route packages must not expose synthesized Codable construction`);
}
requireText(relative.navigation, [
  "AVSpeechSynthesizer",
  "HereNavigationLocationAcceptancePolicy",
  ".simulated",
]);
requireText(relative.surface, [
  "case truck",
  "case rail",
  "case vessel",
  "case operational",
  "case navigation",
  "case terrain",
  "case light",
  "case dark",
  "expectedSHA256",
  "nativeStyleLoadFailed",
  "opaqueUnavailable",
]);

for (const file of [
  ...walkFiles(relative.offlineRoot, ".swift"),
  ...walkFiles(relative.offlineUIRoot, ".swift"),
]) {
  const source = readWalkedRepositoryFile(file);
  const display = path.relative(root, file);
  for (const forbidden of [
    "fatalError(",
    "precondition(",
    "preconditionFailure(",
    "H.service.Platform",
    "createDefaultLayers(",
    "MKMapView",
    "MapScheme.normalDay",
    "MapScheme.normalNight",
    "loadScene(mapScheme:",
  ]) {
    if (source.includes(forbidden)) failures.push(`${display}: forbidden ${JSON.stringify(forbidden)}`);
  }
  if (source.includes("error.localizedDescription")) {
    failures.push(`${display}: arbitrary error.localizedDescription must not reach offline operator state`);
  }
}

denyText(relative.sampleConfig, [
  "REPLACE_WITH_NAVIGATE_ACCESS_KEY_ID =",
  "REPLACE_WITH_NAVIGATE_ACCESS_KEY_SECRET =",
]);

requireText(relative.project, [
  "EusoTripOfflineTests",
  "EusoTrip/Services/HereMaps/Offline",
  "EusoTrip/Views/Maps/Offline",
]);
requireText(relative.scheme, [
  "EusoTripOfflineTests.xctest",
  "BlueprintName = \"EusoTripOfflineTests\"",
]);

let manifest;
if (exists(relative.manifest)) {
  try {
    const parsedManifest = JSON.parse(read(relative.manifest));
    assert.match(parsedManifest.approvedVersion ?? "", /^4\.\d+\.\d+\.\d+$/);
    assert.equal(typeof parsedManifest.archiveRelativePath, "string");
    assert.equal(typeof parsedManifest.frameworkRelativePath, "string");
    assert.equal(parsedManifest.legalNoticeResource, "EusoTrip/Resources/HERE_NOTICE");
    assert.ok(Array.isArray(parsedManifest.vendorPrivacyManifests));
    assert.equal(typeof parsedManifest.appPrivacyManifest, "object");
    assert.equal(
      parsedManifest.appPrivacyManifest?.relativePath,
      "EusoTrip/Resources/PrivacyInfo.xcprivacy",
    );
    manifest = parsedManifest;
  } catch (error) {
    manifest = undefined;
    failures.push(`${relative.manifest}: invalid supply-chain manifest (${error.name})`);
  }
}

let styleManifest;
if (exists(relative.styleManifest)) {
  try {
    const parsedStyleManifest = JSON.parse(read(relative.styleManifest));
    assert.equal(parsedStyleManifest.format, "HERE Style Editor native JSON or ZIP");
    assert.ok(Array.isArray(parsedStyleManifest.entries));
    styleManifest = parsedStyleManifest;
  } catch (error) {
    styleManifest = undefined;
    failures.push(`${relative.styleManifest}: invalid native-style manifest (${error.name})`);
  }
}

const projectSource = exists(relative.project) ? read(relative.project) : "";
const projectInspector = makeProjectInspector(projectSource, "EusoTrip");
const testProjectInspector = makeProjectInspector(projectSource, "EusoTripOfflineTests");
if (!projectInspector.targetExists) {
  failures.push(`${relative.project}: EusoTrip application target could not be structurally resolved`);
} else {
  for (const sourceFile of [
    ...walkFiles(relative.offlineRoot, ".swift"),
    ...walkFiles(relative.offlineUIRoot, ".swift"),
  ]) {
    const relativeSourceFile = path.relative(root, sourceFile).split(path.sep).join("/");
    if (!projectInspector.sourceRegistered(relativeSourceFile)) {
      failures.push(`${relativeSourceFile}: not registered in the EusoTrip application target`);
    }
  }
}
if (!testProjectInspector.targetExists) {
  failures.push(`${relative.project}: EusoTripOfflineTests target could not be structurally resolved`);
} else {
  for (const testFile of walkFiles("EusoTripOfflineTests", ".swift")) {
    const relativeTestFile = path.relative(root, testFile).split(path.sep).join("/");
    if (!testProjectInspector.sourceRegistered(relativeTestFile)) {
      failures.push(`${relativeTestFile}: not registered in the EusoTripOfflineTests target`);
    }
  }
  const schemeSource = exists(relative.scheme) ? read(relative.scheme) : "";
  const exactBlueprint = new RegExp(
    `BlueprintIdentifier = "${testProjectInspector.targetID}"[\\s\\S]*?BlueprintName = "EusoTripOfflineTests"`,
  );
  if (!exactBlueprint.test(schemeSource)) {
    failures.push(`${relative.scheme}: test action does not reference the exact EusoTripOfflineTests target`);
  }
}
if (projectInspector.resourceRegistered(`${relative.offlineRoot}/README.md`)) {
  failures.push(`${relative.project}: offline README.md must not be copied into the app product`);
}
if (projectInspector.resourceRegistered(relative.manifest)) {
  failures.push(`${relative.project}: SDK audit manifest must not be copied into the app product`);
}
if (!projectInspector.resourceRegistered(relative.styleManifest)) {
  failures.push(`${relative.project}: runtime style manifest is not registered in the EusoTrip app resources`);
}

const deployScriptSource = exists(relative.deployScript) ? read(relative.deployScript) : "";
const archiveGateIsWired =
  deployScriptSource.includes("verify-here-offline-contract.mjs") &&
  deployScriptSource.includes("verify-reachable-here-credential-history.mjs") &&
  deployScriptSource.includes("verify-reachable-here-credential-history.test.mjs") &&
  deployScriptSource.includes("--release") &&
  deployScriptSource.includes("--built-app=") &&
  deployScriptSource.includes("HERE_OFFLINE_EXPECTED_TEAM_ID") &&
  deployScriptSource.includes("HERE_OFFLINE_EXPECTED_SIGNING_AUTHORITY");
const regressionHarnessIsWired = deployScriptSource.includes("verify-here-offline-contract.test.mjs");
if (!archiveGateIsWired || !regressionHarnessIsWired) {
  blockers.push("committed local archive automation does not enforce the HERE release gate and regression harness");
}
const sourceWorkflowSource = exists(relative.sourceContractWorkflow)
  ? read(relative.sourceContractWorkflow)
  : "";
const sourceCIIsWired =
  sourceWorkflowSource.includes("name: HERE Offline Source Contract") &&
  sourceWorkflowSource.includes("verify-here-offline-contract.test.mjs") &&
  sourceWorkflowSource.includes("verify-here-offline-contract.mjs") &&
  sourceWorkflowSource.includes("verify-reachable-here-credential-history.test.mjs") &&
  sourceWorkflowSource.includes("verify-reachable-here-credential-history.mjs") &&
  sourceWorkflowSource.includes("build-for-testing") &&
  sourceWorkflowSource.includes("generic/platform=iOS Simulator") &&
  sourceWorkflowSource.includes("refs/pull/*/head:refs/remotes/pull/*/head") &&
  sourceWorkflowSource.includes("refs/pull/*/merge:refs/remotes/pull/*/merge") &&
  sourceWorkflowSource.includes("name: HERE Offline Release Approval") &&
  sourceWorkflowSource.includes("name: here-offline-release") &&
  sourceWorkflowSource.includes("Incident build-log paths remain reachable") &&
  !sourceWorkflowSource.includes("upload-artifact");
if (!sourceCIIsWired) {
  blockers.push("committed source-only HERE CI does not compile tests and inspect every public incident-relevant ref");
}
const deployExecutableSource = deployScriptSource
  .split("\n")
  .filter(line => !line.trimStart().startsWith("#"))
  .join("\n");
let exportOptions = {};
if (exists(relative.exportOptions)) {
  try {
    exportOptions = parseRepositoryPlist(relative.exportOptions);
  } catch {
    failures.push(`${relative.exportOptions}: plist could not be parsed safely`);
  }
}
const explicitUploadCount = (deployExecutableSource.match(/^\s*--upload-app\s*\\?\s*$/gm) ?? []).length;
const archiveProductGateIndex = deployExecutableSource.indexOf(
  '--built-app="${ARCHIVED_APP_PATH}"',
);
const localExportIndex = deployExecutableSource.indexOf("-exportArchive");
const ipaPreflightIndex = deployExecutableSource.indexOf(
  'preflight-exported-ipa.mjs" --ipa="$IPA_PATH"',
);
const extractionIndex = deployExecutableSource.indexOf("/usr/bin/ditto -x -k");
const exportedProductGateIndex = deployExecutableSource.indexOf(
  '--built-app="${EXPORTED_APP_PATH}"',
);
const explicitUploadIndex = deployExecutableSource.indexOf("--upload-app");
const releaseOrderIsSafe =
  archiveProductGateIndex >= 0 &&
  archiveProductGateIndex < localExportIndex &&
  localExportIndex < ipaPreflightIndex &&
  ipaPreflightIndex < extractionIndex &&
  extractionIndex < exportedProductGateIndex &&
  exportedProductGateIndex < explicitUploadIndex;
const finalExportedProductIsGated =
  deployExecutableSource.includes("EXPORTED_APP_PATH=") &&
  deployExecutableSource.includes("preflight-exported-ipa.test.mjs") &&
  deployExecutableSource.includes("verify-exported-ipa-app-binding.test.mjs") &&
  deployExecutableSource.includes("verify-exported-ipa-app-binding.mjs") &&
  deployExecutableSource.includes("hash-release-artifact.test.mjs") &&
  deployExecutableSource.includes("select-available-ios-simulator.test.mjs") &&
  deployExecutableSource.includes("release-ladder-status.test.mjs") &&
  deployExecutableSource.includes("asc-build-status.test.mjs") &&
  deployExecutableSource.includes("asc-latest-build.test.mjs") &&
  deployExecutableSource.includes("verify-release-config-attestation.test.mjs") &&
  deployExecutableSource.includes("verify-here-offline-device-acceptance.test.mjs") &&
  deployExecutableSource.includes("verify-github-release-governance.mjs") &&
  deployExecutableSource.includes("verify-github-release-governance.test.mjs") &&
  deployExecutableSource.includes("GITHUB_ENVIRONMENT_DEPLOYMENT_ID") &&
  deployExecutableSource.includes("GITHUB_ENVIRONMENT_DEPLOYMENT_STATUS_ID") &&
  deployExecutableSource.includes("here-production-gate.mjs") &&
  deployExecutableSource.includes("EUSOTRIP_APPROVED_RELEASE_COMMIT") &&
  deployExecutableSource.includes("EUSOTRIP_RELEASE_XCCONFIG_PATH") &&
  deployExecutableSource.includes('--xcconfig="$RELEASE_XCCONFIG_PATH"') &&
  deployExecutableSource.includes("assert_source_unchanged") &&
  deployExecutableSource.includes("assert_release_config_unchanged") &&
  deployExecutableSource.includes("schemaVersion: 3") &&
  deployExecutableSource.includes("-only-testing:EusoTripOfflineTests") &&
  deployExecutableSource.includes("-parallel-testing-enabled NO") &&
  deployExecutableSource.includes('LADDER_TESTED="pass"') &&
  exportOptions.destination === "export" &&
  explicitUploadCount === 1 &&
  releaseOrderIsSafe;
if (!finalExportedProductIsGated) {
  blockers.push("TestFlight automation can upload before the final exported app passes HERE production and offline release gates");
}

const appEntryCode = exists(relative.appEntry) ? compiledSwiftCodeOnly(read(relative.appEntry)) : "";
const settingsHostCode = exists(relative.settingsHost) ? compiledSwiftCodeOnly(read(relative.settingsHost)) : "";
const mapHostCode = exists(relative.mapHost) ? compiledSwiftCodeOnly(read(relative.mapHost)) : "";
const productionCompositionCode = exists(relative.productionComposition)
  ? compiledSwiftCodeOnly(read(relative.productionComposition))
  : "";
const appTypeStart = appEntryCode.search(/@main\s+struct\s+EusoTripApp\b/);
const appLifecycleCode = appTypeStart >= 0
  ? swiftDeclarationBody(appEntryCode, /\binit\s*\(\s*\)\s*\{/, appTypeStart)
  : "";
const productionInstallCode = swiftDeclarationBody(
  productionCompositionCode,
  /\bstatic\s+func\s+install\s*\([^)]*\)\s*(?:async\s*)?(?:throws\s*)?\{/,
);
const compositionTargetBound = exists(relative.productionComposition) &&
  projectInspector.sourceRegistered(relative.productionComposition) &&
  gitPathIsTrackedAndUnchanged(relative.productionComposition);
const compositionInstalledAtAppEntry =
  /\bOfflineMapProductionComposition\.install\s*\(/.test(appLifecycleCode);
const approvedProductionComposition = compositionTargetBound && compositionInstalledAtAppEntry
  ? productionInstallCode
  : "";
if (!compositionTargetBound || !compositionInstalledAtAppEntry || !productionInstallCode) {
  blockers.push("approved offline production composition is not target-bound and installed from the app entry point");
}
if (!/\bOfflineMapManagementView\s*\(/.test(settingsHostCode)) {
  blockers.push("offline map management has no target-bound Catalyst settings caller");
}
if (!/\bHereNavigateOfflineMapSurface\b/.test(mapHostCode) ||
    !/\bHereNavigateOfflineMapSurface\b/.test(approvedProductionComposition)) {
  blockers.push("approved native offline map surface has no target-bound production mount");
}
if (!/\bCanonicalRoutePackageStore\s*\(/.test(approvedProductionComposition)) {
  blockers.push("signed canonical route store has no approved production route.plan decoder/use-site caller");
}
if (!/\bpurgeAllCachedRoutes\s*\(/.test(approvedProductionComposition)) {
  blockers.push("canonical route cache purge is not wired through the approved production composition");
}
if (!/\bOfflineSearchRequest\s*\(/.test(approvedProductionComposition) ||
    !/\.searchOffline\s*\(/.test(approvedProductionComposition)) {
  blockers.push("offline search has no approved target-bound request/result caller");
}
if (!/\bOfflineRouteRequest\s*\(/.test(approvedProductionComposition) ||
    !/\.calculateOfflineRoute\s*\(/.test(approvedProductionComposition)) {
  blockers.push("offline road/truck routing has no approved target-bound caller");
}
if (!/\bmakeNavigationSession\s*\(/.test(approvedProductionComposition) ||
    !/\.start\s*\(\s*route:/.test(approvedProductionComposition) ||
    !/\.stop\s*\(/.test(approvedProductionComposition)) {
  blockers.push("offline navigation start/stop has no approved target-bound lifecycle owner");
}
if (!/\bOfflineDeviceLocationSample\s*\(/.test(approvedProductionComposition) ||
    !/\.feed\s*\(\s*location:/.test(approvedProductionComposition)) {
  blockers.push("device GNSS samples are not wired through the approved production composition");
}
if (!/\.coverageChanged\s*\(/.test(approvedProductionComposition) ||
    !/\.outsideInstalledCoverage\s*\(/.test(approvedProductionComposition)) {
  blockers.push("installed-region boundary events have no approved production consumer");
}
if (!/\bHereNavigationVoicePolicy\s*\(/.test(approvedProductionComposition)) {
  blockers.push("device-local offline voice policy has no approved target-bound caller");
}
if (!/\bSignedInstalledCoverageResolver\s*\(/.test(approvedProductionComposition) ||
    !/\.resolveInstalledCoverage\s*\(/.test(approvedProductionComposition)) {
  blockers.push("signed installed-region coverage resolver has no approved production adapter/caller");
}

try {
  const trackedBuildLogs = execFileSync(
    "/usr/bin/git",
    ["ls-files", "--", ".build_copy.log", ".build_copy2.log"],
    { cwd: root, encoding: "utf8" },
  ).trim();
  if (trackedBuildLogs) {
    blockers.push("tracked historical build logs require credential rotation and approved history remediation");
  }
} catch {
  failures.push("git tracked-file inspection failed while checking historical build-log exposure");
}

try {
  const historicalBuildLogs = execFileSync(
    "/usr/bin/git",
    ["log", "--all", "--format=", "--name-only", "--", ".build_copy.log", ".build_copy2.log"],
    { cwd: root, encoding: "utf8" },
  ).trim();
  if (historicalBuildLogs) {
    blockers.push("historical build-log paths remain reachable in Git history");
  }
} catch {
  failures.push("git history inspection failed while checking historical build-log exposure");
}

if (!exists(relative.reachableCredentialHistoryVerifier)) {
  failures.push("reachable Git-history HERE credential scanner is absent");
} else {
  const historyCredentialScan = spawnSync(
    process.execPath,
    [
      absolute(relative.reachableCredentialHistoryVerifier),
      `--repository=${root}`,
    ],
    {
      cwd: root,
      stdio: "ignore",
      timeout: 20 * 60 * 1_000,
    },
  );
  if (historyCredentialScan.status === 1) {
    blockers.push("production-shaped HERE credentials remain in reachable Git history");
  } else if (historyCredentialScan.status !== 0) {
    failures.push("reachable Git-history HERE credential scanner failed closed");
  }
}

if (!exists(relative.credentialAttestation)) {
  blockers.push("HERE credential rotation, history remediation, and secret-scan attestation is absent");
} else {
  try {
    const attestation = JSON.parse(read(relative.credentialAttestation));
    const exactTopLevelKeys = new Set([
      "incidentID",
      "status",
      "exposedPaths",
      "affectedCredentialClasses",
      "credentialsRevokedAt",
      "credentialsRotatedAt",
      "revocationScope",
      "rotationScope",
      "historyRemediationCommit",
      "historyScan",
      "approvedBy",
      "approvedAt",
    ]);
    const exactHistoryScanKeys = new Set([
      "completedAt",
      "tool",
      "scope",
      "scannedCommit",
      "scannedTree",
      "result",
    ]);
    const attestationHasExactSchema = attestation && typeof attestation === "object" &&
      !Array.isArray(attestation) &&
      Object.keys(attestation).length === exactTopLevelKeys.size &&
      Object.keys(attestation).every(key => exactTopLevelKeys.has(key)) &&
      attestation.historyScan && typeof attestation.historyScan === "object" &&
      !Array.isArray(attestation.historyScan) &&
      Object.keys(attestation.historyScan).length === exactHistoryScanKeys.size &&
      Object.keys(attestation.historyScan).every(key => exactHistoryScanKeys.has(key));
    const expectedPaths = new Set([
      ".build_copy.log",
      ".build_copy2.log",
      "EUSOTRIP2027GOLD/06_Third_Party_Integrations.md",
      "EusoTripTests/HereMaps/HEREAuthServiceTests.swift",
      "mapping_audit/here_current_state.md",
      "mapping_audit/here_integration_plan.md",
      "mapping_audit/risks.md",
    ]);
    const attestedPaths = new Set(Array.isArray(attestation.exposedPaths) ? attestation.exposedPaths : []);
    const exactPaths = expectedPaths.size === attestedPaths.size &&
      [...expectedPaths].every(value => attestedPaths.has(value));
    const expectedCredentialClasses = new Set([
      "here_maps_js_api_key",
      "here_oauth_access_key_id",
      "here_oauth_access_key_secret",
      "here_oauth_client_identifier",
      "here_user_identifier",
    ]);
    const attestedCredentialClasses = new Set(
      Array.isArray(attestation.affectedCredentialClasses)
        ? attestation.affectedCredentialClasses
        : [],
    );
    const exactCredentialClasses = expectedCredentialClasses.size === attestedCredentialClasses.size &&
      [...expectedCredentialClasses].every(value => attestedCredentialClasses.has(value));
    const remediationCommit = attestation.historyRemediationCommit;
    const scannedCommit = attestation.historyScan?.scannedCommit;
    const scannedTree = attestation.historyScan?.scannedTree;
    const revokedAt = Date.parse(attestation.credentialsRevokedAt ?? "");
    const rotatedAt = Date.parse(attestation.credentialsRotatedAt ?? "");
    const scanCompletedAt = Date.parse(attestation.historyScan?.completedAt ?? "");
    const approvedAt = Date.parse(attestation.approvedAt ?? "");
    const latestAllowedTime = Date.now() + 5 * 60 * 1_000;
    const validTimeline = [revokedAt, rotatedAt, scanCompletedAt, approvedAt]
      .every(value => Number.isFinite(value) && value <= latestAllowedTime) &&
      scanCompletedAt >= revokedAt && scanCompletedAt >= rotatedAt &&
      approvedAt >= revokedAt && approvedAt >= rotatedAt && approvedAt >= scanCompletedAt;
    const approved = attestation.status === "approved" &&
      attestationHasExactSchema &&
      /^HERE-\d{4}-\d{2}-\d{2}-\d{2,}$/.test(attestation.incidentID ?? "") &&
      exactPaths &&
      exactCredentialClasses &&
      validTimeline &&
      attestation.revocationScope === "all_affected_here_credentials_including_js" &&
      attestation.rotationScope === "all_affected_here_credentials_including_js" &&
      typeof remediationCommit === "string" && /^[a-f0-9]{40,64}$/i.test(remediationCommit) &&
      typeof scannedCommit === "string" && /^[a-f0-9]{40,64}$/i.test(scannedCommit) &&
      scannedCommit === remediationCommit &&
      typeof scannedTree === "string" && /^[a-f0-9]{40,64}$/i.test(scannedTree) &&
      typeof attestation.historyScan?.tool === "string" &&
      attestation.historyScan.tool.trim() !== "" &&
      attestation.historyScan.scope === "all_git_refs_and_worktree" &&
      attestation.historyScan.result === "no_active_here_credentials_detected" &&
      typeof attestation.approvedBy === "string" && attestation.approvedBy.trim() !== "" &&
      Number.isFinite(approvedAt);
    if (!approved) {
      blockers.push("HERE credential remediation attestation is incomplete or unapproved");
    } else {
      const commitStatus = spawnSync(
        "/usr/bin/git",
        ["merge-base", "--is-ancestor", remediationCommit, "HEAD"],
        { cwd: root, stdio: "ignore" },
      );
      if (commitStatus.status !== 0) {
        blockers.push("attested HERE credential history-remediation commit is not in the current ancestry");
      }
      const scannedTreeResult = spawnSync(
        "/usr/bin/git",
        ["rev-parse", `${scannedCommit}^{tree}`],
        { cwd: root, encoding: "utf8" },
      );
      if (scannedTreeResult.status !== 0 || scannedTreeResult.stdout.trim() !== scannedTree) {
        blockers.push("HERE credential scan tree does not match the attested scanned commit");
      }
      const postScanDiff = spawnSync(
        "/usr/bin/git",
        ["diff", "--name-only", "--diff-filter=ACDMRTUXB", scannedCommit, "HEAD", "--"],
        { cwd: root, encoding: "utf8" },
      );
      const postScanPaths = postScanDiff.status === 0
        ? postScanDiff.stdout.split(/\r?\n/).filter(Boolean)
        : [];
      if (postScanDiff.status !== 0 ||
          postScanPaths.length !== 1 ||
          postScanPaths[0] !== relative.credentialAttestation) {
        blockers.push("release source changed after the attested credential scan");
      }
    }
  } catch (error) {
    failures.push(`${relative.credentialAttestation}: invalid credential-remediation attestation (${error.name})`);
  }
}

if (styleManifest) {
  const modes = ["truck", "rail", "vessel"];
  const families = ["operational", "navigation", "terrain"];
  const themes = ["light", "dark"];
  const expected = new Set(
    modes.flatMap(mode => families.flatMap(family => themes.map(theme => `${mode}|${family}|${theme}`))),
  );
  const observed = new Set();
  let missingStyleFiles = 0;
  let unapprovedHashes = 0;
  let unregisteredStyleFiles = 0;
  let mismatchedStyleHashes = 0;
  const uniquePaths = new Set();

  if (styleManifest.status !== "approved") {
    blockers.push("HERE-native style manifest is not approved");
  }
  const provenance = styleManifest.provenance;
  const exportedAt = Date.parse(provenance?.exportedAt ?? "");
  const styleApprovedAt = Date.parse(provenance?.approvedAt ?? "");
  const latestAllowedTime = Date.now() + 5 * 60 * 1_000;
  const validStyleTimeline = [exportedAt, styleApprovedAt]
    .every(value => Number.isFinite(value) && value <= latestAllowedTime) &&
    styleApprovedAt >= exportedAt;
  if (!provenance || provenance.source !== "HERE Style Editor" ||
      typeof provenance.projectID !== "string" || provenance.projectID.trim() === "" ||
      !validStyleTimeline ||
      typeof provenance.approvedBy !== "string" || provenance.approvedBy.trim() === "" ||
      !Number.isFinite(styleApprovedAt)) {
    blockers.push("HERE-native style export and approval provenance is incomplete");
  }

  for (const entry of styleManifest.entries) {
    const key = `${entry.mode}|${entry.family}|${entry.theme}`;
    if (!expected.has(key)) {
      failures.push(`${relative.styleManifest}: unexpected style identity ${JSON.stringify(key)}`);
      continue;
    }
    if (observed.has(key)) {
      failures.push(`${relative.styleManifest}: duplicate style identity ${JSON.stringify(key)}`);
      continue;
    }
    observed.add(key);
    if (!safeRepositoryRelativePath(entry.relativePath) ||
        !entry.relativePath.startsWith("EusoTrip/Resources/HEREStyles/") ||
        !/\.(json|zip)$/i.test(entry.relativePath)) {
      failures.push(`${relative.styleManifest}: ${key} has an invalid local native-style path`);
      continue;
    }
    if (uniquePaths.has(entry.relativePath)) {
      failures.push(`${relative.styleManifest}: duplicate style path ${JSON.stringify(entry.relativePath)}`);
      continue;
    }
    uniquePaths.add(entry.relativePath);
    const styleEntry = repositoryEntryStatus(
      entry.relativePath,
      "file",
      "approved HERE-native style",
    );
    const styleExists = styleEntry.status === "ok";
    if (!styleExists) missingStyleFiles += 1;
    if (!/^[a-f0-9]{64}$/i.test(entry.sha256 ?? "")) unapprovedHashes += 1;
    else if (styleExists) {
      const actualHash = sha256RepositoryFile(entry.relativePath, "approved HERE-native style");
      if (actualHash && actualHash.toLowerCase() !== entry.sha256.toLowerCase()) {
        mismatchedStyleHashes += 1;
      }
    }
    if (!projectInspector.resourceRegistered(entry.relativePath)) unregisteredStyleFiles += 1;
  }

  for (const key of expected) {
    if (!observed.has(key)) failures.push(`${relative.styleManifest}: missing style identity ${JSON.stringify(key)}`);
  }
  if (missingStyleFiles) blockers.push(`${missingStyleFiles} approved HERE-native style files are absent`);
  if (unapprovedHashes) blockers.push(`${unapprovedHashes} HERE-native style SHA-256 values are not approved`);
  if (mismatchedStyleHashes) failures.push(`${mismatchedStyleHashes} HERE-native style files do not match their approved SHA-256 values`);
  if (unregisteredStyleFiles) blockers.push(`${unregisteredStyleFiles} HERE-native style files are not registered in the app target`);
}

let approvedDeviceFrameworkPath = null;
if (manifest) {
  let archiveHashApprovedAndMatched = false;
  let manifestPathsAreSafe = true;
  for (const [field, value] of [
    ["archiveRelativePath", manifest.archiveRelativePath],
    ["frameworkRelativePath", manifest.frameworkRelativePath],
    ["legalNoticeResource", manifest.legalNoticeResource],
    ["appPrivacyManifest.relativePath", manifest.appPrivacyManifest?.relativePath],
  ]) {
    if (!safeRepositoryRelativePath(value)) {
      manifestPathsAreSafe = false;
      failures.push(`${relative.manifest}: ${field} must be a normalized repository-relative path`);
    }
  }
  // Unsafe manifest paths are never resolved, read, or passed to an external
  // archive tool even though their schema error is already terminal.
  const archivePath = manifestPathsAreSafe ? absolute(manifest.archiveRelativePath) : "";
  const frameworkPath = manifestPathsAreSafe ? absolute(manifest.frameworkRelativePath) : "";
  const legalNoticePath = manifestPathsAreSafe ? absolute(manifest.legalNoticeResource) : "";
  const appPrivacyManifestPath = manifestPathsAreSafe
    ? absolute(manifest.appPrivacyManifest.relativePath)
    : "";
  const archiveExists = manifestPathsAreSafe && fs.existsSync(archivePath);
  const frameworkExists = manifestPathsAreSafe && fs.existsSync(frameworkPath);
  const legalNoticeExists = manifestPathsAreSafe && fs.existsSync(legalNoticePath);
  const appPrivacyManifestExists = manifestPathsAreSafe && fs.existsSync(appPrivacyManifestPath);
  const archiveIsFile = archiveExists && fs.lstatSync(archivePath).isFile() && fs.statSync(archivePath).size > 0;
  const frameworkIsDirectory = frameworkExists && fs.lstatSync(frameworkPath).isDirectory();
  const legalNoticeIsFile = legalNoticeExists && fs.lstatSync(legalNoticePath).isFile() &&
    fs.statSync(legalNoticePath).size > 0;
  const appPrivacyManifestIsFile = appPrivacyManifestExists &&
    repositoryEntryStatus(
      manifest.appPrivacyManifest.relativePath,
      "file",
      "approved app privacy manifest",
    ).status === "ok";
  if (!frameworkExists) {
    blockers.push(`licensed HERE framework absent at ${manifest.frameworkRelativePath}`);
  } else if (!frameworkIsDirectory) {
    failures.push(`${manifest.frameworkRelativePath}: licensed HERE framework must be a real directory`);
  }
  if (!archiveExists) {
    blockers.push(`vendor HERE archive absent at ${manifest.archiveRelativePath}`);
  } else if (!archiveIsFile) {
    failures.push(`${manifest.archiveRelativePath}: vendor HERE archive must be a non-empty regular file`);
  }
  if (!legalNoticeExists) {
    blockers.push(`vendor HERE_NOTICE absent at ${manifest.legalNoticeResource}`);
  } else if (!legalNoticeIsFile) {
    failures.push(`${manifest.legalNoticeResource}: vendor HERE_NOTICE must be a non-empty regular file`);
  }
  if (!appPrivacyManifestExists) {
    blockers.push(`approved app PrivacyInfo.xcprivacy absent at ${manifest.appPrivacyManifest.relativePath}`);
  } else if (!appPrivacyManifestIsFile) {
    failures.push(`${manifest.appPrivacyManifest.relativePath}: app privacy manifest must be a real in-repository file`);
  }
  if (manifest.status !== "approved") {
    blockers.push("HERE SDK supply-chain manifest is not approved");
  }
  const provenance = manifest.provenance;
  let provenanceURL = null;
  try {
    provenanceURL = typeof provenance?.sourceURL === "string"
      ? new URL(provenance.sourceURL)
      : null;
  } catch {
    provenanceURL = null;
  }
  const trustedHEREHost = provenanceURL?.protocol === "https:" &&
    (provenanceURL.hostname === "here.com" || provenanceURL.hostname.endsWith(".here.com"));
  const receivedAt = Date.parse(provenance?.receivedAt ?? "");
  const sdkApprovedAt = Date.parse(provenance?.approvedAt ?? "");
  const latestAllowedTime = Date.now() + 5 * 60 * 1_000;
  const validSDKTimeline = [receivedAt, sdkApprovedAt]
    .every(value => Number.isFinite(value) && value <= latestAllowedTime) &&
    sdkApprovedAt >= receivedAt;
  if (!provenance || !trustedHEREHost ||
      !validSDKTimeline ||
      typeof provenance.approvedBy !== "string" || provenance.approvedBy.trim() === "" ||
      !Number.isFinite(sdkApprovedAt)) {
    blockers.push("HERE SDK vendor receipt and approval provenance is incomplete");
  }
  if (!projectInspector.frameworkLinked(manifest.frameworkRelativePath)) {
    blockers.push("heresdk.xcframework is not linked and embedded in the EusoTrip target");
  }
  if (!projectInspector.frameworkEmbedded(manifest.frameworkRelativePath)) {
    blockers.push("heresdk.xcframework has no Embed Frameworks build-phase membership");
  }
  if (!projectInspector.resourceRegistered(manifest.legalNoticeResource)) {
    blockers.push("HERE_NOTICE is not registered in Copy Bundle Resources");
  }
  if (!projectInspector.resourceRegistered(manifest.appPrivacyManifest.relativePath)) {
    blockers.push("approved app PrivacyInfo.xcprivacy is not registered in Copy Bundle Resources");
  }
  if (!/^[a-f0-9]{64}$/i.test(manifest.archiveSHA256 ?? "")) {
    blockers.push("vendor archive SHA-256 has not been approved");
  } else if (archiveIsFile) {
    const actual = sha256(archivePath);
    if (actual.toLowerCase() !== manifest.archiveSHA256.toLowerCase()) {
      failures.push(`${manifest.archiveRelativePath}: SHA-256 does not match the approved manifest`);
    } else {
      archiveHashApprovedAndMatched = true;
    }
  }
  if (!/^[a-f0-9]{64}$/i.test(manifest.frameworkTreeSHA256 ?? "")) {
    blockers.push("vendor xcframework canonical tree SHA-256 has not been approved");
  } else if (frameworkIsDirectory) {
    try {
      const actual = canonicalTreeHash(frameworkPath);
      if (actual.toLowerCase() !== manifest.frameworkTreeSHA256.toLowerCase()) {
        failures.push(`${manifest.frameworkRelativePath}: canonical tree SHA-256 does not match the approved manifest`);
      }
    } catch {
      failures.push(`${manifest.frameworkRelativePath}: canonical tree contains an unsafe or unstable filesystem entry`);
    }
  }
  if (!/^[a-f0-9]{64}$/i.test(manifest.legalNoticeSHA256 ?? "")) {
    blockers.push("vendor HERE_NOTICE SHA-256 has not been approved");
  } else if (legalNoticeIsFile) {
    if (sha256(legalNoticePath).toLowerCase() !== manifest.legalNoticeSHA256.toLowerCase()) {
      failures.push(`${manifest.legalNoticeResource}: SHA-256 does not match the approved vendor notice`);
    }
  }

  const appPrivacy = manifest.appPrivacyManifest ?? {};
  const privacyReviewedAt = Date.parse(appPrivacy.reviewedAt ?? "");
  const privacyLabelReviewedAt = Date.parse(appPrivacy.appStorePrivacyLabelReviewedAt ?? "");
  const privacyApprovedAt = Date.parse(appPrivacy.approvedAt ?? "");
  const privacyTimeline = [privacyReviewedAt, privacyLabelReviewedAt, privacyApprovedAt]
    .every(value => Number.isFinite(value) && value <= Date.now() + 5 * 60 * 1_000) &&
    privacyLabelReviewedAt >= privacyReviewedAt &&
    privacyApprovedAt >= privacyLabelReviewedAt;
  if (appPrivacy.status !== "approved" ||
      typeof appPrivacy.reviewedBy !== "string" || !appPrivacy.reviewedBy.trim() ||
      typeof appPrivacy.approvedBy !== "string" || !appPrivacy.approvedBy.trim() ||
      appPrivacy.reviewedBy === appPrivacy.approvedBy ||
      !privacyTimeline) {
    blockers.push("HERE/app privacy manifest and App Store privacy-label review are incomplete or not independently approved");
  }
  if (!/^[a-f0-9]{64}$/i.test(appPrivacy.sha256 ?? "")) {
    blockers.push("app PrivacyInfo.xcprivacy SHA-256 has not been approved");
  } else if (appPrivacyManifestIsFile) {
    const actualPrivacyHash = sha256RepositoryFile(
      appPrivacy.relativePath,
      "approved app privacy manifest",
    );
    if (!actualPrivacyHash || actualPrivacyHash.toLowerCase() !== appPrivacy.sha256.toLowerCase()) {
      failures.push(`${appPrivacy.relativePath}: SHA-256 does not match the approved privacy manifest`);
    }
    if (!gitPathIsTrackedAndUnchanged(appPrivacy.relativePath)) {
      blockers.push("approved app PrivacyInfo.xcprivacy is not committed unchanged in HEAD");
    }
    try {
      const privacyPlist = parseRepositoryPlist(appPrivacy.relativePath);
      if (typeof privacyPlist.NSPrivacyTracking !== "boolean" ||
          !Array.isArray(privacyPlist.NSPrivacyCollectedDataTypes) ||
          !Array.isArray(privacyPlist.NSPrivacyAccessedAPITypes)) {
        failures.push(`${appPrivacy.relativePath}: required privacy-manifest declarations are structurally incomplete`);
      }
    } catch {
      failures.push(`${appPrivacy.relativePath}: privacy manifest could not be parsed safely`);
    }
  }

  if (!Array.isArray(manifest.vendorPrivacyManifests) || manifest.vendorPrivacyManifests.length === 0) {
    blockers.push("licensed HERE SDK vendor privacy manifest inventory is absent");
  } else {
    const seenVendorPrivacyPaths = new Set();
    for (const entry of manifest.vendorPrivacyManifests) {
      const validPath = safeRepositoryRelativePath(entry?.relativePath) &&
        entry.relativePath.startsWith(`${manifest.frameworkRelativePath}/`) &&
        path.basename(entry.relativePath) === "PrivacyInfo.xcprivacy";
      if (!validPath || seenVendorPrivacyPaths.has(entry.relativePath)) {
        failures.push(`${relative.manifest}: vendor privacy manifest inventory contains an unsafe or duplicate path`);
        continue;
      }
      seenVendorPrivacyPaths.add(entry.relativePath);
      const vendorPrivacyEntry = repositoryEntryStatus(
        entry.relativePath,
        "file",
        "vendor HERE privacy manifest",
      );
      if (vendorPrivacyEntry.status !== "ok") {
        blockers.push(`vendor HERE PrivacyInfo.xcprivacy absent at ${entry.relativePath}`);
      } else if (!/^[a-f0-9]{64}$/i.test(entry.sha256 ?? "")) {
        blockers.push(`vendor HERE PrivacyInfo.xcprivacy SHA-256 is not approved for ${entry.relativePath}`);
      } else {
        const actual = sha256RepositoryFile(entry.relativePath, "vendor HERE privacy manifest");
        if (!actual || actual.toLowerCase() !== entry.sha256.toLowerCase()) {
          failures.push(`${entry.relativePath}: SHA-256 does not match the approved vendor privacy manifest`);
        }
      }
    }
  }

  if (frameworkIsDirectory) {
    try {
      const xcInfo = parsePlist(path.join(frameworkPath, "Info.plist"));
      const libraries = Array.isArray(xcInfo.AvailableLibraries) ? xcInfo.AvailableLibraries : [];
      const hasDevice = libraries.some(item =>
        String(item.SupportedPlatform).toLowerCase() === "ios" && !item.SupportedPlatformVariant);
      const hasSimulator = libraries.some(item =>
        String(item.SupportedPlatform).toLowerCase() === "ios" && item.SupportedPlatformVariant === "simulator");
      if (!hasDevice || !hasSimulator) {
        failures.push(`${manifest.frameworkRelativePath}: required iOS device and simulator slices are not both declared`);
      }
      const invalidLibraryPath = libraries.some(item =>
        resolveRealXCFrameworkLibrary(frameworkPath, item) === null);
      if (invalidLibraryPath) {
        failures.push(`${manifest.frameworkRelativePath}: declared library paths must be real directories within the approved xcframework`);
      }
      const deviceLibrary = libraries.find(item =>
        String(item.SupportedPlatform).toLowerCase() === "ios" && !item.SupportedPlatformVariant);
      if (deviceLibrary) approvedDeviceFrameworkPath =
        resolveRealXCFrameworkLibrary(frameworkPath, deviceLibrary);
      const frameworkInfos = walkAbsolute(frameworkPath)
        .filter(file => file.endsWith("heresdk.framework/Info.plist"));
      if (!frameworkInfos.length) {
        failures.push(`${manifest.frameworkRelativePath}: nested heresdk.framework identity is missing`);
      } else {
        const acceptedVersions = new Set([
          manifest.approvedVersion,
          manifest.approvedVersion.replace(/\.0$/, ""),
        ]);
        for (const infoPath of frameworkInfos) {
          const info = parsePlist(infoPath);
          if (!/here/i.test(info.CFBundleIdentifier ?? "") ||
              !acceptedVersions.has(info.CFBundleShortVersionString ?? info.CFBundleVersion ?? "")) {
            failures.push(`${manifest.frameworkRelativePath}: nested framework identity/version is not the approved HERE SDK`);
            break;
          }
        }
      }
    } catch (error) {
      failures.push(`${manifest.frameworkRelativePath}: xcframework metadata could not be verified (${error.name})`);
    }
  }

  if (archiveHashApprovedAndMatched) {
    let temporaryRoot = null;
    try {
      const listing = execFileSync("/usr/bin/unzip", ["-Z1", archivePath], { encoding: "utf8" });
      const archiveEntries = listing.split(/\r?\n/).filter(Boolean);
      const unsafeEntry = archiveEntries.find(entry => !safeRepositoryRelativePath(entry.replace(/\/$/, "")));
      const detailedListing = execFileSync("/usr/bin/zipinfo", ["-l", archivePath], { encoding: "utf8" });
      const containsSymlink = /^l[^\s]*\s/m.test(detailedListing);
      if (unsafeEntry) {
        failures.push(`${manifest.archiveRelativePath}: archive contains an unsafe path`);
      } else if (containsSymlink) {
        failures.push(`${manifest.archiveRelativePath}: archive must not contain symbolic links`);
      } else if (!archiveEntries.some(entry => entry.endsWith("heresdk.xcframework/Info.plist"))) {
        failures.push(`${manifest.archiveRelativePath}: archive does not contain the expected HERE xcframework`);
      } else if (/^[a-f0-9]{64}$/i.test(manifest.frameworkTreeSHA256 ?? "")) {
        const sizeListing = execFileSync("/usr/bin/unzip", ["-l", archivePath], { encoding: "utf8" });
        const totals = sizeListing.match(/^\s*(\d+)\s+\d+\s+files?\s*$/m);
        if (!totals || Number(totals[1]) > 8 * 1_024 * 1_024 * 1_024 || archiveEntries.length > 100_000) {
          failures.push(`${manifest.archiveRelativePath}: archive expansion exceeds the verification safety limit`);
        } else {
          temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "eusotrip-here-archive-"));
          execFileSync("/usr/bin/unzip", ["-q", archivePath, "-d", temporaryRoot], { stdio: "ignore" });
          const extractedFrameworks = [temporaryRoot, ...walkAbsoluteDirectories(temporaryRoot)]
            .filter(directory => path.basename(directory) === "heresdk.xcframework");
          if (extractedFrameworks.length !== 1) {
            failures.push(`${manifest.archiveRelativePath}: archive must contain exactly one HERE xcframework`);
          } else if (canonicalTreeHash(extractedFrameworks[0]).toLowerCase() !==
                     manifest.frameworkTreeSHA256.toLowerCase()) {
            failures.push(`${manifest.archiveRelativePath}: extracted xcframework differs from the approved tree hash`);
          }
        }
      }
    } catch (error) {
      failures.push(`${manifest.archiveRelativePath}: vendor archive could not be inspected (${error.name})`);
    } finally {
      if (temporaryRoot) fs.rmSync(temporaryRoot, { recursive: true, force: true });
    }
  }
}

if (!expectedSigningTeam || !expectedSigningAuthority) {
  blockers.push("expected release signing team and authority were not supplied through the verification environment");
}

const builtNavigateCredentials = [];
if (!builtAppPath || !fs.existsSync(builtAppPath) ||
    !fs.lstatSync(builtAppPath).isDirectory() || fs.lstatSync(builtAppPath).isSymbolicLink()) {
  blockers.push("built EusoTrip.app artifact was not supplied with --built-app=/absolute/path");
} else if (manifest && styleManifest) {
  try {
    const appInfoPath = path.join(builtAppPath, "Info.plist");
    const appInfoMetadata = fs.lstatSync(appInfoPath);
    const resolvedAppRoot = fs.realpathSync(builtAppPath);
    const resolvedAppInfo = fs.realpathSync(appInfoPath);
    if (!appInfoMetadata.isFile() || appInfoMetadata.isSymbolicLink() ||
        !isDescendantPath(resolvedAppInfo, resolvedAppRoot)) {
      throw new Error("UnsafeInfoPlist");
    }
    const appInfo = parsePlist(appInfoPath);
    if (appInfo.CFBundleIdentifier !== "com.app.eusotrip" || appInfo.CFBundlePackageType !== "APPL") {
      failures.push("built app identity does not match the EusoTrip application bundle contract");
    }
    const credentialValueIsUsable = value => {
      if (typeof value !== "string") return false;
      const trimmed = value.trim();
      const normalized = trimmed.toUpperCase();
      return trimmed !== "" &&
        !trimmed.startsWith("$(") &&
        !normalized.startsWith("REPLACE_WITH_") &&
        normalized !== "CHANGEME" &&
        normalized !== "CHANGE_ME";
    };
    const accessKeyID = appInfo.HERESDKAccessKeyID;
    const accessKeySecret = appInfo.HERESDKAccessKeySecret;
    const routePlanIssuer = appInfo.EusoRoutePlanIssuer;
    const routePlanAudience = appInfo.EusoRoutePlanAudience;
    const routePlanKeyID = appInfo.EusoRoutePlanKeyID;
    const routePlanPublicKeyBase64 = appInfo.EusoRoutePlanPublicKey;
    let routePlanPublicKey = null;
    if (credentialValueIsUsable(routePlanPublicKeyBase64)) {
      routePlanPublicKey = Buffer.from(routePlanPublicKeyBase64, "base64");
    }
    if (!credentialValueIsUsable(routePlanIssuer) ||
        !credentialValueIsUsable(routePlanAudience) ||
        !credentialValueIsUsable(routePlanKeyID) ||
        !/^[A-Za-z0-9][A-Za-z0-9._:-]{2,127}$/.test(routePlanIssuer ?? "") ||
        !/^[A-Za-z0-9][A-Za-z0-9._:-]{2,127}$/.test(routePlanAudience ?? "") ||
        !/^[A-Za-z0-9][A-Za-z0-9._:-]{2,127}$/.test(routePlanKeyID ?? "") ||
        routePlanPublicKey?.length !== 32 ||
        routePlanPublicKey.toString("base64") !== routePlanPublicKeyBase64) {
      failures.push("built EusoTrip.app has invalid or unresolved signed route-plan trust configuration");
    }
    if (!credentialValueIsUsable(accessKeyID) || !credentialValueIsUsable(accessKeySecret)) {
      failures.push("built EusoTrip.app has missing, unresolved, or placeholder HERE Navigate credentials");
    } else {
      const otherInfoValues = Object.fromEntries(Object.entries(appInfo).filter(([key]) =>
        !["HERESDKAccessKeyID", "HERESDKAccessKeySecret", "EusoRoutePlanPublicKey"].includes(key)));
      if (accessKeyID === accessKeySecret ||
          valueContainsAnyCredential(otherInfoValues, [accessKeyID, accessKeySecret])) {
        failures.push("built EusoTrip.app reuses a HERE Navigate credential in a disallowed online/backend field");
      } else {
        builtNavigateCredentials.push(accessKeyID, accessKeySecret);
      }
    }
  } catch (error) {
    failures.push(`built EusoTrip.app Info.plist could not be verified (${error.name})`);
  }

  const seal = spawnSync(
    "/usr/bin/codesign",
    ["--verify", "--deep", "--strict", builtAppPath],
    { encoding: "utf8" },
  );
  if (seal.status !== 0) {
    failures.push("built EusoTrip.app does not have a valid strict deep code-signing seal");
  }
  const signingDetails = spawnSync(
    "/usr/bin/codesign",
    ["-dv", "--verbose=4", builtAppPath],
    { encoding: "utf8" },
  );
  const signingMetadata = `${signingDetails.stdout ?? ""}\n${signingDetails.stderr ?? ""}`;
  const observedTeam = signingMetadata.match(/^TeamIdentifier=(.+)$/m)?.[1]?.trim() ?? "";
  const observedAuthorities = [...signingMetadata.matchAll(/^Authority=(.+)$/gm)]
    .map(match => match[1].trim());
  if (!expectedSigningTeam || observedTeam !== expectedSigningTeam) {
    failures.push("built EusoTrip.app signing team does not match the expected release configuration");
  }
  if (!expectedSigningAuthority || !observedAuthorities.includes(expectedSigningAuthority)) {
    failures.push("built EusoTrip.app signing authority does not match the expected release configuration");
  }

  const productFiles = walkAbsolute(builtAppPath);
  if (builtNavigateCredentials.length) {
    const resolvedBundleRoot = fs.realpathSync(builtAppPath);
    const allowedInfoPath = fs.realpathSync(path.join(builtAppPath, "Info.plist"));
    const credentialSequences = credentialByteSequences([...new Set(builtNavigateCredentials)]);
    const leakedCredential = productFiles.some(file => {
      const metadata = fs.lstatSync(file);
      if (!metadata.isFile() || metadata.isSymbolicLink()) return false;
      const resolved = fs.realpathSync(file);
      if (!isDescendantPath(resolved, resolvedBundleRoot) || resolved === allowedInfoPath) return false;
      return fileContainsAnyByteSequence(resolved, credentialSequences);
    });
    if (leakedCredential) {
      failures.push("built EusoTrip.app contains a HERE Navigate credential outside the root Info.plist");
    }
  }
  const expectedBundledStyleManifest = path.join(
    builtAppPath,
    path.basename(relative.styleManifest),
  );
  const bundledStyleManifests = productFiles.filter(file =>
    path.basename(file) === path.basename(relative.styleManifest));
  if (bundledStyleManifests.length !== 1 ||
      path.resolve(bundledStyleManifests[0]) !== path.resolve(expectedBundledStyleManifest)) {
    failures.push("built EusoTrip.app must contain exactly one runtime style manifest at the bundle root");
  } else if (sha256(bundledStyleManifests[0]) !== sha256(absolute(relative.styleManifest))) {
    failures.push("built runtime style manifest differs from the approved source manifest");
  }
  for (const entry of styleManifest.entries) {
    const basename = path.basename(entry.relativePath);
    const allowedCandidates = [...new Set([
      path.join(builtAppPath, entry.relativePath),
      path.join(builtAppPath, "HEREStyles", basename),
      path.join(builtAppPath, basename),
    ].map(candidate => path.resolve(candidate)))];
    const resolvedBundleRoot = fs.realpathSync(builtAppPath);
    const matches = allowedCandidates.filter(candidate => {
      if (!fs.existsSync(candidate) || !fs.statSync(candidate).isFile()) return false;
      const resolved = fs.realpathSync(candidate);
      return isDescendantPath(resolved, resolvedBundleRoot);
    });
    const sameBasenameFiles = productFiles.filter(file => path.basename(file) === basename);
    if (matches.length !== 1 || sameBasenameFiles.length !== 1 ||
        path.resolve(sameBasenameFiles[0]) !== path.resolve(matches[0])) {
      failures.push(`${basename}: signed app must contain exactly one approved native style artifact at a runtime-resolvable bundle path`);
    } else if (/^[a-f0-9]{64}$/i.test(entry.sha256 ?? "") &&
               sha256(matches[0]).toLowerCase() !== entry.sha256.toLowerCase()) {
      failures.push(`${basename}: built-product SHA-256 differs from the approved style`);
    }
  }
  const embeddedFramework = path.join(builtAppPath, "Frameworks", "heresdk.framework");
  if (!fs.existsSync(embeddedFramework)) {
    failures.push("built EusoTrip.app does not contain Frameworks/heresdk.framework");
  } else if (!approvedDeviceFrameworkPath) {
    failures.push("approved HERE device framework could not be resolved for built-product comparison");
  } else {
    const embeddedHash = normalizedFrameworkHash(embeddedFramework);
    const approvedHash = normalizedFrameworkHash(approvedDeviceFrameworkPath);
    if (!embeddedHash || !approvedHash) {
      failures.push("built HERE framework executable metadata is unsafe or incomplete");
    } else if (embeddedHash !== approvedHash) {
      failures.push("built HERE framework bytes do not match the approved vendor device framework after signature normalization");
    }
  }
  const expectedNotice = path.join(builtAppPath, "HERE_NOTICE");
  const notices = productFiles.filter(file => path.basename(file) === "HERE_NOTICE");
  if (notices.length !== 1 ||
      path.resolve(notices[0]) !== path.resolve(expectedNotice) ||
      !fs.lstatSync(notices[0]).isFile() || fs.statSync(notices[0]).size === 0) {
    failures.push("built EusoTrip.app must contain exactly one non-empty HERE_NOTICE at the runtime-resolvable bundle root");
  } else if (/^[a-f0-9]{64}$/i.test(manifest.legalNoticeSHA256 ?? "") &&
             sha256(notices[0]).toLowerCase() !== manifest.legalNoticeSHA256.toLowerCase()) {
    failures.push("built HERE_NOTICE differs from the approved vendor notice");
  }
  const expectedAppPrivacyManifest = path.join(builtAppPath, "PrivacyInfo.xcprivacy");
  if (!fs.existsSync(expectedAppPrivacyManifest) ||
      !fs.lstatSync(expectedAppPrivacyManifest).isFile() ||
      fs.lstatSync(expectedAppPrivacyManifest).isSymbolicLink()) {
    failures.push("built EusoTrip.app does not contain the approved root PrivacyInfo.xcprivacy");
  } else if (/^[a-f0-9]{64}$/i.test(manifest.appPrivacyManifest?.sha256 ?? "") &&
             sha256(expectedAppPrivacyManifest).toLowerCase() !==
               manifest.appPrivacyManifest.sha256.toLowerCase()) {
    failures.push("built root PrivacyInfo.xcprivacy differs from the approved app privacy manifest");
  }
  for (const forbidden of ["README.md", "HERE_SDK_SUPPLY_CHAIN.json"]) {
    if (productFiles.some(file => path.basename(file) === forbidden)) {
      failures.push(`built EusoTrip.app unexpectedly contains internal ${forbidden}`);
    }
  }
}

if (releaseMode && blockers.length) {
  for (const blocker of blockers) failures.push(`release blocker: ${blocker}`);
}

if (failures.length) {
  console.error(`HERE offline ${releaseMode ? "release" : "source"} contract failed:`);
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log("HERE offline source/artifact contract passed: fail-closed boundaries, independent inventory feeds, signed scoped canonical-route storage, and test membership are present.");
if (blockers.length) {
  console.log("Release remains blocked:");
  for (const blocker of blockers) console.log(`- ${blocker}`);
}
console.log("Real-device cold-launch, GPS, boundary, audio, and captured-network acceptance remain separate required evidence.");
