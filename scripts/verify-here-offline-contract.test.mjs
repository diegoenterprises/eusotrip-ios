#!/usr/bin/env node

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";

const repositoryRoot = path.resolve(import.meta.dirname, "..");
const verifierRelativePath = "scripts/verify-here-offline-contract.mjs";
const projectRelativePath = "EusoTrip.xcodeproj/project.pbxproj";
const sdkManifestRelativePath =
  "EusoTrip/Services/HereMaps/Offline/HERE_SDK_SUPPLY_CHAIN.json";
const styleManifestRelativePath =
  "EusoTrip/Services/HereMaps/Offline/HERE_NATIVE_STYLE_SUPPLY_CHAIN.json";
const credentialAttestationRelativePath =
  "security/HERE_CREDENTIAL_REMEDIATION.json";
const survivingIncidentRelativePath = "mapping_audit/risks.md";
const deployScriptRelativePath = "scripts/deploy-testflight.sh";
const exportOptionsRelativePath = "scripts/exportOptions.testflight.plist";

const temporaryRoot = fs.mkdtempSync(
  path.join(os.tmpdir(), "eusotrip-here-verifier-tests-"),
);

function absolute(root, relativePath) {
  return path.join(root, relativePath);
}

function ensureParent(file) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
}

function writeFile(file, contents) {
  ensureParent(file);
  fs.writeFileSync(file, contents);
}

function writeJSON(file, value) {
  writeFile(file, `${JSON.stringify(value, null, 2)}\n`);
}

function readJSON(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function sha256(file) {
  return crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
}

function canonicalTreeHash(directory) {
  const hash = crypto.createHash("sha256");
  const rootMetadata = fs.lstatSync(directory, { bigint: true });
  const mode = metadata => (Number(metadata.mode) & 0o7777).toString(8).padStart(4, "0");
  const entries = [];
  const visit = current => {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const entryPath = path.join(current, entry.name);
      entries.push(entryPath);
      if (entry.isDirectory()) visit(entryPath);
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
      hash.update(fs.readFileSync(entryPath));
    }
  }
  return hash.digest("hex");
}

function run(command, arguments_, options = {}) {
  return spawnSync(command, arguments_, {
    encoding: "utf8",
    ...options,
  });
}

function requireCommandSuccess(command, arguments_, options = {}) {
  const result = run(command, arguments_, options);
  assert.equal(
    result.status,
    0,
    [
      `${command} ${arguments_.join(" ")} failed`,
      result.stdout,
      result.stderr,
    ].filter(Boolean).join("\n"),
  );
}

function copyRepositoryEntry(relativePath, destinationRoot) {
  const source = absolute(repositoryRoot, relativePath);
  const destination = absolute(destinationRoot, relativePath);
  ensureParent(destination);
  fs.cpSync(source, destination, { recursive: true });
}

function writeSanitizedCredentialInventoryFixtures(fixture) {
  writeFile(
    absolute(fixture, "EusoTripTests/HereMaps/HEREAuthServiceTests.swift"),
    [
      "import XCTest",
      "",
      "final class HEREAuthServiceTests: XCTestCase {",
      "    func testSanitizedFixture() {",
      "        XCTAssertEqual(\"fixture-secret_with-unreserved-characters\",",
      "                       \"fixture-secret_with-unreserved-characters\")",
      "    }",
      "}",
      "",
    ].join("\n"),
  );
  writeFile(
    absolute(fixture, "mapping_audit/here_integration_plan.md"),
    "HERE credentials: [REMOVED: revoke and inject via untracked configuration]\n",
  );
  writeFile(
    absolute(fixture, "mapping_audit/here_current_state.md"),
    [
      "HERE_API_KEY = [REMOVED: revoke in HERE portal]",
      "**`[REMOVED: revoke in HERE portal]`**",
      "",
    ].join("\n"),
  );
  writeFile(
    absolute(fixture, "mapping_audit/risks.md"),
    [
      "[REMOVED: revoke in HERE portal]",
      "[REMOVED: rotate and reinject]",
      "",
    ].join("\n"),
  );
  writeFile(
    absolute(fixture, "EUSOTRIP2027GOLD/06_Third_Party_Integrations.md"),
    [
      "Identifier removed; rotate and inject through untracked configuration.",
      "credential inventory must be verified in the HERE portal",
      "",
    ].join("\n"),
  );
}

function createBaselineFixture() {
  const fixture = path.join(temporaryRoot, "baseline");
  fs.mkdirSync(fixture, { recursive: true });
  for (const relativePath of [
    verifierRelativePath,
    "EusoTrip/Services/HereMaps/Offline",
    "EusoTrip/Views/Maps/Offline",
    "EusoTrip/EusoTripApp.swift",
    "EusoTrip/Views/Catalyst/311_CatalystSettings.swift",
    "EusoTrip/Services/HereMaps/HereMapWebView.swift",
    "EusoTrip/Info.plist",
    "EusoTrip.xcconfig.sample",
    "EusoTripTests/HereMaps/HEREAuthServiceTests.swift",
    "mapping_audit/here_integration_plan.md",
    "mapping_audit/here_current_state.md",
    "mapping_audit/risks.md",
    "EUSOTRIP2027GOLD/06_Third_Party_Integrations.md",
    credentialAttestationRelativePath,
    projectRelativePath,
    "EusoTrip.xcodeproj/xcshareddata/xcschemes/EusoTrip.xcscheme",
    deployScriptRelativePath,
    exportOptionsRelativePath,
    "scripts/preflight-exported-ipa.mjs",
    "scripts/preflight-exported-ipa.test.mjs",
    "scripts/select-available-ios-simulator.mjs",
    "scripts/select-available-ios-simulator.test.mjs",
    "scripts/here-production-gate.mjs",
    "scripts/hash-release-artifact.mjs",
    "scripts/hash-release-artifact.test.mjs",
    "scripts/release-ladder-status.mjs",
    "scripts/release-ladder-status.test.mjs",
    "scripts/asc-build-status.mjs",
    "scripts/asc-build-status.test.mjs",
  ]) {
    copyRepositoryEntry(relativePath, fixture);
  }
  writeSanitizedCredentialInventoryFixtures(fixture);

  requireCommandSuccess("/usr/bin/git", ["init", "-q"], { cwd: fixture });
  requireCommandSuccess(
    "/usr/bin/git",
    ["config", "user.name", "Verifier Regression Harness"],
    { cwd: fixture },
  );
  requireCommandSuccess(
    "/usr/bin/git",
    ["config", "user.email", "verifier-regression@example.invalid"],
    { cwd: fixture },
  );
  requireCommandSuccess("/usr/bin/git", ["add", "--all"], { cwd: fixture });
  requireCommandSuccess(
    "/usr/bin/git",
    ["commit", "-q", "-m", "fixture baseline"],
    { cwd: fixture },
  );
  return fixture;
}

function cloneFixture(baseline, name) {
  const fixture = path.join(
    temporaryRoot,
    name.toLowerCase().replace(/[^a-z0-9]+/g, "-"),
  );
  fs.cpSync(baseline, fixture, { recursive: true });
  return fixture;
}

function runVerifier(fixture, arguments_ = []) {
  return run(
    process.execPath,
    [absolute(fixture, verifierRelativePath), ...arguments_],
    { cwd: fixture },
  );
}

function combinedOutput(result) {
  return `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
}

function requireVerifierFailure(
  fixture,
  expectedDiagnostic,
  arguments_ = [],
  forbiddenOutput = [],
) {
  const result = runVerifier(fixture, arguments_);
  const output = combinedOutput(result);
  assert.equal(
    result.status,
    1,
    `verifier did not fail closed for ${JSON.stringify(expectedDiagnostic)}\n${output}`,
  );
  assert.ok(
    output.includes(expectedDiagnostic),
    `missing diagnostic ${JSON.stringify(expectedDiagnostic)}\n${output}`,
  );
  for (const sensitiveValue of forbiddenOutput) {
    assert.ok(
      !output.includes(sensitiveValue),
      `verifier disclosed fixture credential ${JSON.stringify(sensitiveValue)}\n${output}`,
    );
  }
}

function mutateManifest(fixture, mutate) {
  const manifestPath = absolute(fixture, sdkManifestRelativePath);
  const manifest = readJSON(manifestPath);
  mutate(manifest);
  writeJSON(manifestPath, manifest);
}

function commitFixturePaths(fixture, relativePaths, message) {
  requireCommandSuccess(
    "/usr/bin/git",
    ["add", "--", ...relativePaths],
    { cwd: fixture },
  );
  requireCommandSuccess(
    "/usr/bin/git",
    ["commit", "-q", "-m", message],
    { cwd: fixture },
  );
}

function gitOutput(fixture, arguments_) {
  const result = run("/usr/bin/git", arguments_, { cwd: fixture });
  assert.equal(
    result.status,
    0,
    `git ${arguments_.join(" ")} failed\n${combinedOutput(result)}`,
  );
  return result.stdout.trim();
}

function installApprovedCredentialAttestation(
  fixture,
  { scannedTreeOverride = null } = {},
) {
  const scannedCommit = gitOutput(fixture, ["rev-parse", "HEAD"]);
  const scannedTree = gitOutput(fixture, [
    "rev-parse",
    `${scannedCommit}^{tree}`,
  ]);
  const attestation = {
    incidentID: "HERE-2026-08-31-99",
    status: "approved",
    exposedPaths: [
      ".build_copy.log",
      ".build_copy2.log",
      "EUSOTRIP2027GOLD/06_Third_Party_Integrations.md",
      "EusoTripTests/HereMaps/HEREAuthServiceTests.swift",
      "mapping_audit/here_current_state.md",
      "mapping_audit/here_integration_plan.md",
      "mapping_audit/risks.md",
    ],
    affectedCredentialClasses: [
      "here_maps_js_api_key",
      "here_oauth_access_key_id",
      "here_oauth_access_key_secret",
      "here_oauth_client_identifier",
      "here_user_identifier",
    ],
    credentialsRevokedAt: "2025-01-01T00:00:00Z",
    credentialsRotatedAt: "2025-01-02T00:00:00Z",
    revocationScope: "all_affected_here_credentials_including_js",
    rotationScope: "all_affected_here_credentials_including_js",
    historyRemediationCommit: scannedCommit,
    historyScan: {
      completedAt: "2025-01-03T00:00:00Z",
      tool: "synthetic-regression-scanner",
      scope: "all_git_refs_and_worktree",
      scannedCommit,
      scannedTree: scannedTreeOverride ?? scannedTree,
      result: "no_active_here_credentials_detected",
    },
    approvedBy: "synthetic-regression-approver",
    approvedAt: "2025-01-04T00:00:00Z",
  };
  writeJSON(
    absolute(fixture, credentialAttestationRelativePath),
    attestation,
  );
  commitFixturePaths(
    fixture,
    [credentialAttestationRelativePath],
    "approved synthetic credential attestation fixture",
  );
  return { scannedCommit, scannedTree };
}

function createMaliciousArchive(fixture, kind) {
  const manifest = readJSON(absolute(fixture, sdkManifestRelativePath));
  const archivePath = absolute(fixture, manifest.archiveRelativePath);
  ensureParent(archivePath);
  const python = String.raw`
import stat
import sys
import zipfile

archive_path = sys.argv[1]
kind = sys.argv[2]
with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    archive.writestr("heresdk.xcframework/Info.plist", "fixture")
    if kind == "traversal":
        archive.writestr("../outside.txt", "must not escape")
    elif kind == "symlink":
        link = zipfile.ZipInfo("heresdk.xcframework/unsafe-link")
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        archive.writestr(link, "Info.plist")
    else:
        raise ValueError("unknown archive fixture")
`;
  requireCommandSuccess(
    "/usr/bin/python3",
    ["-c", python, archivePath, kind],
  );
  mutateManifest(fixture, value => {
    value.archiveSHA256 = sha256(archivePath);
  });
  return manifest.archiveRelativePath;
}

function xmlEscape(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

function writeAppInfoPlist(
  appPath,
  {
    accessKeyID = "fixture-access-key-id",
    accessKeySecret = "fixture-access-key-secret",
    additionalHEREValues = {},
  } = {},
) {
  const credentialEntries = [
    ["HERESDKAccessKeyID", accessKeyID],
    ["HERESDKAccessKeySecret", accessKeySecret],
    ...Object.entries(additionalHEREValues),
  ].filter(([, value]) => typeof value === "string");
  const credentialXML = credentialEntries
    .map(([key, value]) => `  <key>${xmlEscape(key)}</key>\n  <string>${xmlEscape(value)}</string>`)
    .join("\n");
  writeFile(
    path.join(appPath, "Info.plist"),
    `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.app.eusotrip</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
${credentialXML}
</dict>
</plist>
`,
  );
}

function prepareBuiltAppStyles(fixture) {
  const appPath = absolute(fixture, "Artifacts/EusoTrip.app");
  fs.mkdirSync(appPath, { recursive: true });
  writeAppInfoPlist(appPath);
  writeFile(path.join(appPath, "HERE_NOTICE"), "fixture legal notice\n");

  const manifestPath = absolute(fixture, styleManifestRelativePath);
  const manifest = readJSON(manifestPath);
  manifest.status = "approved";
  manifest.provenance = {
    source: "HERE Style Editor",
    projectID: "fixture-project",
    exportedAt: "2026-08-31T00:00:00Z",
    approvedBy: "fixture-approver",
    approvedAt: "2026-08-31T00:00:00Z",
  };
  for (const entry of manifest.entries) {
    const contents = `fixture style ${entry.mode}/${entry.family}/${entry.theme}\n`;
    const sourceStyle = absolute(fixture, entry.relativePath);
    writeFile(sourceStyle, contents);
    entry.sha256 = sha256(sourceStyle);
    writeFile(path.join(appPath, path.basename(entry.relativePath)), contents);
  }
  writeJSON(manifestPath, manifest);
  fs.copyFileSync(
    manifestPath,
    path.join(appPath, path.basename(styleManifestRelativePath)),
  );
  return { appPath, manifest };
}

function writeFrameworkInfoPlist(frameworkPath, executable = "heresdk") {
  writeFile(
    path.join(frameworkPath, "Info.plist"),
    `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>${xmlEscape(executable)}</string>
  <key>CFBundleIdentifier</key>
  <string>com.here.sdk.fixture</string>
  <key>CFBundleShortVersionString</key>
  <string>4.27.2.0</string>
</dict>
</plist>
`,
  );
}

function writeXCFrameworkInfoPlist(frameworkPath, libraries) {
  const libraryXML = libraries.map(library => `
    <dict>
      <key>LibraryIdentifier</key>
      <string>${xmlEscape(library.identifier)}</string>
      <key>LibraryPath</key>
      <string>${xmlEscape(library.libraryPath)}</string>
      <key>SupportedPlatform</key>
      <string>ios</string>${library.variant ? `
      <key>SupportedPlatformVariant</key>
      <string>${xmlEscape(library.variant)}</string>` : ""}
    </dict>`).join("");
  writeFile(
    path.join(frameworkPath, "Info.plist"),
    `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>AvailableLibraries</key>
  <array>${libraryXML}
  </array>
</dict>
</plist>
`,
  );
}

function writeFixtureFramework(frameworkPath, executable = "heresdk") {
  fs.mkdirSync(frameworkPath, { recursive: true });
  writeFrameworkInfoPlist(frameworkPath, executable);
  writeFile(path.join(frameworkPath, "heresdk"), "synthetic unsigned framework bytes\n");
}

function prepareXCFramework(
  fixture,
  {
    deviceIdentifier = "ios-arm64",
    deviceLibraryPath = "heresdk.framework",
    deviceIdentifierSymlink = false,
  } = {},
) {
  const manifest = readJSON(absolute(fixture, sdkManifestRelativePath));
  const frameworkPath = absolute(fixture, manifest.frameworkRelativePath);
  fs.mkdirSync(frameworkPath, { recursive: true });
  const simulatorIdentifier = "ios-arm64_x86_64-simulator";
  const simulatorFramework = path.join(
    frameworkPath,
    simulatorIdentifier,
    "heresdk.framework",
  );
  writeFixtureFramework(simulatorFramework);

  if (deviceIdentifierSymlink) {
    const outsideIdentifier = absolute(fixture, "Artifacts/outside-device-slice");
    writeFixtureFramework(path.join(outsideIdentifier, deviceLibraryPath));
    fs.symlinkSync(outsideIdentifier, path.join(frameworkPath, deviceIdentifier), "dir");
  } else if (!deviceIdentifier.includes("/") && !deviceIdentifier.includes("\\")) {
    writeFixtureFramework(path.join(frameworkPath, deviceIdentifier, deviceLibraryPath));
  }

  writeXCFrameworkInfoPlist(frameworkPath, [
    { identifier: deviceIdentifier, libraryPath: deviceLibraryPath },
    {
      identifier: simulatorIdentifier,
      libraryPath: "heresdk.framework",
      variant: "simulator",
    },
  ]);
  return { frameworkPath };
}

function prepareEmbeddedFramework(fixture, executable = "heresdk") {
  const { appPath } = prepareBuiltAppStyles(fixture);
  const embeddedFramework = path.join(appPath, "Frameworks", "heresdk.framework");
  fs.mkdirSync(embeddedFramework, { recursive: true });
  writeFrameworkInfoPlist(embeddedFramework, executable);
  return { appPath, embeddedFramework };
}

function injectIntoEusoTripAppInit(fixture, source) {
  const appEntry = absolute(fixture, "EusoTrip/EusoTripApp.swift");
  const appSource = fs.readFileSync(appEntry, "utf8");
  const marker = "    init() {\n";
  assert.ok(appSource.includes(marker), "fixture EusoTripApp.init() marker is missing");
  writeFile(appEntry, appSource.replace(marker, `${marker}${source}\n`));
}

const baseline = createBaselineFixture();
const baselineResult = runVerifier(baseline);
assert.equal(
  baselineResult.status,
  0,
  `minimal baseline must satisfy the source verifier\n${combinedOutput(baselineResult)}`,
);
console.log("ok - minimal source-contract baseline");

const cases = [
  {
    name: "committed trusted input cannot be an external symbolic link",
    expected: "security/HERE_CREDENTIAL_REMEDIATION.json: repository input must be a regular non-symlink file within the repository root",
    forbidden: ["external-attestation-canary-must-not-be-read"],
    mutate(fixture) {
      const outside = path.join(
        temporaryRoot,
        "external-attestation-canary.json",
      );
      writeFile(outside, "external-attestation-canary-must-not-be-read\n");
      const attestation = absolute(fixture, credentialAttestationRelativePath);
      fs.rmSync(attestation, { force: true });
      fs.symlinkSync(outside, attestation);
      commitFixturePaths(
        fixture,
        [credentialAttestationRelativePath],
        "synthetic committed external attestation symlink",
      );
    },
  },
  {
    name: "native style cannot be an out-of-root symbolic link",
    expected: "approved HERE-native style must be a regular non-symlink file within the repository root",
    forbidden: ["external-style-canary-must-not-be-hashed"],
    mutate(fixture) {
      const manifest = readJSON(absolute(fixture, styleManifestRelativePath));
      const stylePath = absolute(fixture, manifest.entries[0].relativePath);
      const outside = path.join(temporaryRoot, "external-style-canary.zip");
      writeFile(outside, "external-style-canary-must-not-be-hashed\n");
      ensureParent(stylePath);
      fs.rmSync(stylePath, { force: true });
      fs.symlinkSync(outside, stylePath);
    },
  },
  {
    name: "offline source enumeration rejects symbolic links",
    expected: "repository source tree entry must be a regular non-symlink file within the repository root",
    forbidden: ["external-source-canary-must-not-be-compiled"],
    mutate(fixture) {
      const sourceRelativePath =
        "EusoTrip/Services/HereMaps/Offline/Core/OfflineNavigationModels.swift";
      const sourcePath = absolute(fixture, sourceRelativePath);
      const outside = path.join(temporaryRoot, "external-source-canary.swift");
      writeFile(outside, "external-source-canary-must-not-be-compiled\n");
      fs.rmSync(sourcePath, { force: true });
      fs.symlinkSync(outside, sourcePath);
    },
  },
  {
    name: "release entrypoint executable mode is sealed",
    expected: "scripts/deploy-testflight.sh: release entrypoint must retain an executable POSIX mode",
    mutate(fixture) {
      fs.chmodSync(absolute(fixture, deployScriptRelativePath), 0o644);
    },
  },
  {
    name: "XCFramework canonical tree hash includes executable mode",
    expected: "Vendor/HERE/heresdk.xcframework: canonical tree SHA-256 does not match the approved manifest",
    mutate(fixture) {
      const { frameworkPath } = prepareXCFramework(fixture);
      mutateManifest(fixture, manifest => {
        manifest.frameworkTreeSHA256 = canonicalTreeHash(frameworkPath);
      });
      fs.chmodSync(
        path.join(frameworkPath, "ios-arm64", "heresdk.framework", "heresdk"),
        0o755,
      );
    },
  },
  {
    name: "TestFlight export destination cannot upload implicitly",
    expected: "release blocker: TestFlight automation can upload before the final exported app passes HERE production and offline release gates",
    mutate(fixture) {
      const file = absolute(fixture, exportOptionsRelativePath);
      writeFile(file, fs.readFileSync(file, "utf8").replace(
        "<string>export</string>",
        "<string>upload</string>",
      ));
      this.arguments = ["--release"];
    },
  },
  {
    name: "exported app cannot bypass the final release gate",
    expected: "release blocker: TestFlight automation can upload before the final exported app passes HERE production and offline release gates",
    mutate(fixture) {
      const file = absolute(fixture, deployScriptRelativePath);
      writeFile(file, fs.readFileSync(file, "utf8").replace(
        '--built-app="${EXPORTED_APP_PATH}"',
        '--built-app="${ARCHIVED_APP_PATH}"',
      ));
      this.arguments = ["--release"];
    },
  },
  {
    name: "TestFlight automation has one explicit upload",
    expected: "release blocker: TestFlight automation can upload before the final exported app passes HERE production and offline release gates",
    mutate(fixture) {
      const file = absolute(fixture, deployScriptRelativePath);
      fs.appendFileSync(file, "\nxcrun altool \\\n  --upload-app \\\n  --file synthetic.ipa\n");
      this.arguments = ["--release"];
    },
  },
  {
    name: "upload cannot move before exported product verification",
    expected: "release blocker: TestFlight automation can upload before the final exported app passes HERE production and offline release gates",
    mutate(fixture) {
      const file = absolute(fixture, deployScriptRelativePath);
      const source = fs.readFileSync(file, "utf8");
      const uploadStart = source.indexOf("trap 'mark_failed_step upload' ERR");
      const uploadEnd = source.indexOf('LADDER_UPLOADED="pass"', uploadStart);
      const gateStart = source.indexOf("trap 'mark_failed_step offline_contract' ERR", source.indexOf("EXPORTED_APP_PATH="));
      assert.ok(uploadStart >= 0 && uploadEnd > uploadStart && gateStart >= 0 && gateStart < uploadStart);
      const uploadBlock = source.slice(uploadStart, uploadEnd);
      const withoutUpload = source.slice(0, uploadStart) + source.slice(uploadEnd);
      writeFile(file, withoutUpload.slice(0, gateStart) + uploadBlock + withoutUpload.slice(gateStart));
      this.arguments = ["--release"];
    },
  },
  {
    name: "malformed export options are sanitized",
    expected: "scripts/exportOptions.testflight.plist: plist could not be parsed safely",
    forbidden: ["at parsePlist", "verify-here-offline-contract.mjs:"],
    mutate(fixture) {
      writeFile(absolute(fixture, exportOptionsRelativePath), "not a plist\n");
    },
  },
  {
    name: "release automation cannot omit offline XCTest",
    expected: "release blocker: TestFlight automation can upload before the final exported app passes HERE production and offline release gates",
    mutate(fixture) {
      const file = absolute(fixture, deployScriptRelativePath);
      writeFile(file, fs.readFileSync(file, "utf8").replace(
        "-only-testing:EusoTripOfflineTests",
        "-only-testing:EusoTripTests",
      ));
      this.arguments = ["--release"];
    },
  },
  {
    name: "malformed SDK manifest is sanitized",
    expected: "EusoTrip/Services/HereMaps/Offline/HERE_SDK_SUPPLY_CHAIN.json: invalid supply-chain manifest (SyntaxError)",
    forbidden: ["at JSON.parse", "verify-here-offline-contract.mjs:"],
    mutate(fixture) {
      writeFile(absolute(fixture, sdkManifestRelativePath), "{\n");
    },
  },
  {
    name: "malformed native-style manifest is sanitized",
    expected: "EusoTrip/Services/HereMaps/Offline/HERE_NATIVE_STYLE_SUPPLY_CHAIN.json: invalid native-style manifest (SyntaxError)",
    forbidden: ["at JSON.parse", "verify-here-offline-contract.mjs:"],
    mutate(fixture) {
      writeFile(absolute(fixture, styleManifestRelativePath), "{\n");
    },
  },
  {
    name: "dead wiring helper cannot satisfy production composition",
    expected: "release blocker: signed canonical route store has no approved production route.plan decoder/use-site caller",
    mutate(fixture) {
      const composition = "EusoTrip/Services/HereMaps/Offline/OfflineMapProductionComposition.swift";
      const deadHelper = "EusoTrip/Services/HereMaps/Offline/DeadOfflineWiringHelper.swift";
      writeFile(
        absolute(fixture, composition),
        "enum OfflineMapProductionComposition { static func install() { _ = 1 } }\n",
      );
      writeFile(
        absolute(fixture, deadHelper),
        [
          "CanonicalRoutePackageStore(",
          "purgeAllCachedRoutes(",
          "OfflineSearchRequest(",
          ".searchOffline(",
          "OfflineRouteRequest(",
          ".calculateOfflineRoute(",
          "makeNavigationSession(",
          ".start(route:",
          ".stop(",
          "OfflineDeviceLocationSample(",
          ".feed(location:",
          ".coverageChanged(",
          ".outsideInstalledCoverage(",
          "HereNavigationVoicePolicy(",
          "HereNavigateOfflineMapSurface",
          "",
        ].join("\n"),
      );
      injectIntoEusoTripAppInit(
        fixture,
        "        OfflineMapProductionComposition.install()",
      );
      commitFixturePaths(
        fixture,
        [composition, deadHelper, "EusoTrip/EusoTripApp.swift"],
        "synthetic dead production wiring fixture",
      );
      this.arguments = ["--release"];
    },
  },
  {
    name: "inactive compiler branches cannot satisfy production wiring",
    expected: "release blocker: approved offline production composition is not target-bound and installed from the app entry point",
    mutate(fixture) {
      const composition = "EusoTrip/Services/HereMaps/Offline/OfflineMapProductionComposition.swift";
      writeFile(
        absolute(fixture, composition),
        [
          "#if false",
          "enum OfflineMapProductionComposition {",
          "  static func install() {",
          "    CanonicalRoutePackageStore(",
          "    purgeAllCachedRoutes(",
          "    OfflineSearchRequest(",
          "    .searchOffline(",
          "    OfflineRouteRequest(",
          "    .calculateOfflineRoute(",
          "    makeNavigationSession(",
          "    .start(route:",
          "    .stop(",
          "    OfflineDeviceLocationSample(",
          "    .feed(location:",
          "    .coverageChanged(",
          "    .outsideInstalledCoverage(",
          "    HereNavigationVoicePolicy(",
          "    HereNavigateOfflineMapSurface",
          "  }",
          "}",
          "#endif",
          "",
        ].join("\n"),
      );
      fs.appendFileSync(
        absolute(fixture, "EusoTrip/EusoTripApp.swift"),
        "\n#if false\nOfflineMapProductionComposition.install()\n#endif\n",
      );
      commitFixturePaths(
        fixture,
        [composition, "EusoTrip/EusoTripApp.swift"],
        "synthetic inactive production wiring fixture",
      );
      this.arguments = ["--release"];
    },
  },
  {
    name: "DEBUG-only wiring cannot satisfy release composition",
    expected: "release blocker: approved offline production composition is not target-bound and installed from the app entry point",
    mutate(fixture) {
      const composition = "EusoTrip/Services/HereMaps/Offline/OfflineMapProductionComposition.swift";
      writeFile(
        absolute(fixture, composition),
        [
          "#if DEBUG",
          "enum OfflineMapProductionComposition {",
          "  static func install() { CanonicalRoutePackageStore( }",
          "}",
          "#endif",
          "",
        ].join("\n"),
      );
      injectIntoEusoTripAppInit(
        fixture,
        [
          "        #if DEBUG",
          "        OfflineMapProductionComposition.install()",
          "        #endif",
        ].join("\n"),
      );
      commitFixturePaths(
        fixture,
        [composition, "EusoTrip/EusoTripApp.swift"],
        "synthetic DEBUG-only production wiring fixture",
      );
      this.arguments = ["--release"];
    },
  },
  {
    name: "same-file dead helpers cannot satisfy install body",
    expected: "release blocker: signed canonical route store has no approved production route.plan decoder/use-site caller",
    mutate(fixture) {
      const composition = "EusoTrip/Services/HereMaps/Offline/OfflineMapProductionComposition.swift";
      writeFile(
        absolute(fixture, composition),
        [
          "enum OfflineMapProductionComposition {",
          "  static func install() { _ = 1 }",
          "  static func neverCalled() {",
          "    CanonicalRoutePackageStore(",
          "    purgeAllCachedRoutes(",
          "    OfflineSearchRequest(",
          "    .searchOffline(",
          "    OfflineRouteRequest(",
          "    .calculateOfflineRoute(",
          "    makeNavigationSession(",
          "    .start(route:",
          "    .stop(",
          "    OfflineDeviceLocationSample(",
          "    .feed(location:",
          "    .coverageChanged(",
          "    .outsideInstalledCoverage(",
          "    HereNavigationVoicePolicy(",
          "    HereNavigateOfflineMapSurface",
          "  }",
          "}",
          "",
        ].join("\n"),
      );
      injectIntoEusoTripAppInit(
        fixture,
        "        OfflineMapProductionComposition.install()",
      );
      commitFixturePaths(
        fixture,
        [composition, "EusoTrip/EusoTripApp.swift"],
        "synthetic same-file dead production wiring fixture",
      );
      this.arguments = ["--release"];
    },
  },
  {
    name: "PBX synchronized source exclusion",
    expected: "EusoTrip/Services/HereMaps/Offline/Core/OfflineMapEngine.swift: not registered in the EusoTrip application target",
    mutate(fixture) {
      const projectPath = absolute(fixture, projectRelativePath);
      const source = fs.readFileSync(projectPath, "utf8");
      const marker = "\t\t\tmembershipExceptions = (\n";
      assert.ok(source.includes(marker), "fixture PBX exception set is missing");
      writeFile(
        projectPath,
        source.replace(marker, `${marker}\t\t\t\tCore/OfflineMapEngine.swift,\n`),
      );
    },
  },
  {
    name: "archive wrong filesystem type",
    expected: "Vendor/HERE/heresdk-4.27.2.0-ios.zip: vendor HERE archive must be a non-empty regular file",
    mutate(fixture) {
      const archive = absolute(fixture, readJSON(
        absolute(fixture, sdkManifestRelativePath),
      ).archiveRelativePath);
      fs.mkdirSync(archive, { recursive: true });
    },
  },
  {
    name: "framework wrong filesystem type",
    expected: "Vendor/HERE/heresdk.xcframework: licensed HERE framework must be a real directory",
    mutate(fixture) {
      const framework = absolute(fixture, readJSON(
        absolute(fixture, sdkManifestRelativePath),
      ).frameworkRelativePath);
      writeFile(framework, "not a framework directory\n");
    },
  },
  {
    name: "XCFramework device identifier traversal",
    expected: "Vendor/HERE/heresdk.xcframework: declared library paths must be real directories within the approved xcframework",
    mutate(fixture) {
      prepareXCFramework(fixture, { deviceIdentifier: "../../outside-device-slice" });
    },
  },
  {
    name: "XCFramework device identifier symbolic link",
    expected: "Vendor/HERE/heresdk.xcframework: declared library paths must be real directories within the approved xcframework",
    mutate(fixture) {
      prepareXCFramework(fixture, { deviceIdentifierSymlink: true });
    },
  },
  {
    name: "legal notice wrong filesystem type",
    expected: "EusoTrip/Resources/HERE_NOTICE: vendor HERE_NOTICE must be a non-empty regular file",
    mutate(fixture) {
      const notice = absolute(fixture, readJSON(
        absolute(fixture, sdkManifestRelativePath),
      ).legalNoticeResource);
      fs.mkdirSync(notice, { recursive: true });
    },
  },
  {
    name: "dirty SDK supply-chain manifest in release mode",
    expected: "release blocker: HERE SDK supply-chain manifest is not committed unchanged in HEAD",
    mutate(fixture) {
      fs.appendFileSync(absolute(fixture, sdkManifestRelativePath), "\n");
      this.arguments = ["--release"];
    },
  },
  {
    name: "untracked SDK supply-chain manifest in release mode",
    expected: "release blocker: HERE SDK supply-chain manifest is not committed unchanged in HEAD",
    mutate(fixture) {
      requireCommandSuccess(
        "/usr/bin/git",
        ["rm", "--cached", "--", sdkManifestRelativePath],
        { cwd: fixture },
      );
      this.arguments = ["--release"];
    },
  },
  {
    name: "dirty native-style manifest in release mode",
    expected: "release blocker: HERE native-style supply-chain manifest is not committed unchanged in HEAD",
    mutate(fixture) {
      fs.appendFileSync(absolute(fixture, styleManifestRelativePath), "\n");
      this.arguments = ["--release"];
    },
  },
  {
    name: "dirty credential-remediation attestation in release mode",
    expected: "release blocker: HERE credential-remediation attestation is not committed unchanged in HEAD",
    mutate(fixture) {
      fs.appendFileSync(
        absolute(fixture, credentialAttestationRelativePath),
        "\n",
      );
      this.arguments = ["--release"];
    },
  },
  {
    name: "untracked credential-remediation attestation in release mode",
    expected: "release blocker: HERE credential-remediation attestation is not committed unchanged in HEAD",
    mutate(fixture) {
      requireCommandSuccess(
        "/usr/bin/git",
        ["rm", "--cached", "--", credentialAttestationRelativePath],
        { cwd: fixture },
      );
      this.arguments = ["--release"];
    },
  },
  {
    name: "dirty surviving credential-incident file in release mode",
    expected: "release blocker: sanitized credential-incident file mapping_audit/risks.md is not committed unchanged in HEAD",
    mutate(fixture) {
      fs.appendFileSync(
        absolute(fixture, survivingIncidentRelativePath),
        "\n",
      );
      this.arguments = ["--release"];
    },
  },
  {
    name: "placeholder plus production-shaped surviving credential literal",
    expected: "mapping_audit/risks.md: production-shaped HERE credential literal remains in a sanitized incident file",
    forbidden: [
      "REPLACE_WITH_SYNTHETIC_HERE_API_KEY",
      "syntheticProductionShape_1234567890",
    ],
    mutate(fixture) {
      fs.appendFileSync(
        absolute(fixture, survivingIncidentRelativePath),
        [
          "",
          "Synthetic placeholder: `REPLACE_WITH_SYNTHETIC_HERE_API_KEY`.",
          "Synthetic production-shaped canary: `syntheticProductionShape_1234567890`.",
          "",
        ].join("\n"),
      );
      commitFixturePaths(
        fixture,
        [survivingIncidentRelativePath],
        "synthetic surviving credential literal fixture",
      );
      this.arguments = ["--release"];
    },
  },
  {
    name: "approved attestation with stale scanned tree",
    expected: "release blocker: HERE credential scan tree does not match the attested scanned commit",
    mutate(fixture) {
      installApprovedCredentialAttestation(fixture, {
        scannedTreeOverride: "0".repeat(40),
      });
      this.arguments = ["--release"];
    },
  },
  {
    name: "approved attestation cannot add a post-scan credential literal",
    expected: "security/HERE_CREDENTIAL_REMEDIATION.json: production-shaped HERE credential literal remains in a sanitized incident file",
    forbidden: ["SyntheticPostScanCredential12345"],
    mutate(fixture) {
      installApprovedCredentialAttestation(fixture);
      const attestationPath = absolute(fixture, credentialAttestationRelativePath);
      const attestation = readJSON(attestationPath);
      attestation.notes = "SyntheticPostScanCredential12345";
      writeJSON(attestationPath, attestation);
      commitFixturePaths(
        fixture,
        [credentialAttestationRelativePath],
        "synthetic post-scan attestation credential fixture",
      );
      this.arguments = ["--release"];
    },
  },
  {
    name: "credential scan cannot precede rotation",
    expected: "release blocker: HERE credential remediation attestation is incomplete or unapproved",
    mutate(fixture) {
      installApprovedCredentialAttestation(fixture);
      const attestationPath = absolute(fixture, credentialAttestationRelativePath);
      const attestation = readJSON(attestationPath);
      attestation.credentialsRevokedAt = "2025-01-03T00:00:00Z";
      attestation.credentialsRotatedAt = "2025-01-04T00:00:00Z";
      attestation.historyScan.completedAt = "2025-01-02T00:00:00Z";
      attestation.approvedAt = "2025-01-05T00:00:00Z";
      writeJSON(attestationPath, attestation);
      commitFixturePaths(
        fixture,
        [credentialAttestationRelativePath],
        "synthetic pre-rotation credential scan fixture",
      );
      this.arguments = ["--release"];
    },
  },
  {
    name: "approved attestation with post-scan source change",
    expected: "release blocker: release source changed after the attested credential scan",
    mutate(fixture) {
      installApprovedCredentialAttestation(fixture);
      fs.appendFileSync(
        absolute(fixture, "EusoTrip.xcconfig.sample"),
        "\nSYNTHETIC_POST_SCAN_MARKER = YES\n",
      );
      commitFixturePaths(
        fixture,
        ["EusoTrip.xcconfig.sample"],
        "synthetic post-scan source change fixture",
      );
      this.arguments = ["--release"];
    },
  },
  {
    name: "dirty release verifier self-check",
    expected: "release blocker: HERE offline release verifier is not committed unchanged in HEAD",
    mutate(fixture) {
      fs.appendFileSync(absolute(fixture, verifierRelativePath), "\n");
      this.arguments = ["--release"];
    },
  },
  {
    name: "future native-style approval chronology",
    expected: "release blocker: HERE-native style export and approval provenance is incomplete",
    mutate(fixture) {
      const manifestPath = absolute(fixture, styleManifestRelativePath);
      const manifest = readJSON(manifestPath);
      manifest.status = "approved";
      manifest.provenance = {
        source: "HERE Style Editor",
        projectID: "future-style-fixture",
        exportedAt: "2099-01-01T00:00:00Z",
        approvedBy: "fixture-approver",
        approvedAt: "2099-01-02T00:00:00Z",
      };
      writeJSON(manifestPath, manifest);
      commitFixturePaths(
        fixture,
        [styleManifestRelativePath],
        "future style chronology fixture",
      );
      this.arguments = ["--release"];
    },
  },
  {
    name: "native-style approval before export",
    expected: "release blocker: HERE-native style export and approval provenance is incomplete",
    mutate(fixture) {
      const manifestPath = absolute(fixture, styleManifestRelativePath);
      const manifest = readJSON(manifestPath);
      manifest.status = "approved";
      manifest.provenance = {
        source: "HERE Style Editor",
        projectID: "reversed-style-fixture",
        exportedAt: "2025-01-02T00:00:00Z",
        approvedBy: "fixture-approver",
        approvedAt: "2025-01-01T00:00:00Z",
      };
      writeJSON(manifestPath, manifest);
      commitFixturePaths(
        fixture,
        [styleManifestRelativePath],
        "reversed style chronology fixture",
      );
      this.arguments = ["--release"];
    },
  },
  {
    name: "future SDK approval chronology",
    expected: "release blocker: HERE SDK vendor receipt and approval provenance is incomplete",
    mutate(fixture) {
      mutateManifest(fixture, manifest => {
        manifest.status = "approved";
        manifest.provenance = {
          sourceURL: "https://here.com/fixture-sdk",
          receivedAt: "2099-01-01T00:00:00Z",
          approvedBy: "fixture-approver",
          approvedAt: "2099-01-02T00:00:00Z",
        };
      });
      commitFixturePaths(
        fixture,
        [sdkManifestRelativePath],
        "future SDK chronology fixture",
      );
      this.arguments = ["--release"];
    },
  },
  {
    name: "SDK approval before vendor receipt",
    expected: "release blocker: HERE SDK vendor receipt and approval provenance is incomplete",
    mutate(fixture) {
      mutateManifest(fixture, manifest => {
        manifest.status = "approved";
        manifest.provenance = {
          sourceURL: "https://here.com/fixture-sdk",
          receivedAt: "2025-01-02T00:00:00Z",
          approvedBy: "fixture-approver",
          approvedAt: "2025-01-01T00:00:00Z",
        };
      });
      commitFixturePaths(
        fixture,
        [sdkManifestRelativePath],
        "reversed SDK chronology fixture",
      );
      this.arguments = ["--release"];
    },
  },
  {
    name: "runtime style at wrong bundle location",
    expected: "truck-operational-light.zip: signed app must contain exactly one approved native style artifact at a runtime-resolvable bundle path",
    mutate(fixture) {
      const { appPath, manifest } = prepareBuiltAppStyles(fixture);
      const basename = path.basename(manifest.entries[0].relativePath);
      const approvedLocation = path.join(appPath, basename);
      const wrongLocation = path.join(appPath, "WrongLocation", basename);
      ensureParent(wrongLocation);
      fs.renameSync(approvedLocation, wrongLocation);
      this.arguments = [`--built-app=${appPath}`];
    },
  },
  {
    name: "runtime style duplicate basename",
    expected: "truck-operational-light.zip: signed app must contain exactly one approved native style artifact at a runtime-resolvable bundle path",
    mutate(fixture) {
      const { appPath, manifest } = prepareBuiltAppStyles(fixture);
      const basename = path.basename(manifest.entries[0].relativePath);
      const duplicate = path.join(appPath, "Duplicate", basename);
      ensureParent(duplicate);
      fs.copyFileSync(path.join(appPath, basename), duplicate);
      this.arguments = [`--built-app=${appPath}`];
    },
  },
  {
    name: "built app missing HERE Navigate credentials",
    expected: "built EusoTrip.app has missing, unresolved, or placeholder HERE Navigate credentials",
    mutate(fixture) {
      const { appPath } = prepareBuiltAppStyles(fixture);
      writeAppInfoPlist(appPath, {
        accessKeyID: null,
        accessKeySecret: null,
      });
      this.arguments = [`--built-app=${appPath}`];
    },
  },
  {
    name: "built app unresolved HERE Navigate credentials",
    expected: "built EusoTrip.app has missing, unresolved, or placeholder HERE Navigate credentials",
    forbidden: ["$(HERE_SDK_ACCESS_KEY_ID)", "$(HERE_SDK_ACCESS_KEY_SECRET)"],
    mutate(fixture) {
      const { appPath } = prepareBuiltAppStyles(fixture);
      writeAppInfoPlist(appPath, {
        accessKeyID: "$(HERE_SDK_ACCESS_KEY_ID)",
        accessKeySecret: "$(HERE_SDK_ACCESS_KEY_SECRET)",
      });
      this.arguments = [`--built-app=${appPath}`];
    },
  },
  {
    name: "built app placeholder HERE Navigate credentials",
    expected: "built EusoTrip.app has missing, unresolved, or placeholder HERE Navigate credentials",
    forbidden: [
      "REPLACE_WITH_NAVIGATE_ACCESS_KEY_ID",
      "REPLACE_WITH_NAVIGATE_ACCESS_KEY_SECRET",
    ],
    mutate(fixture) {
      const { appPath } = prepareBuiltAppStyles(fixture);
      writeAppInfoPlist(appPath, {
        accessKeyID: "REPLACE_WITH_NAVIGATE_ACCESS_KEY_ID",
        accessKeySecret: "REPLACE_WITH_NAVIGATE_ACCESS_KEY_SECRET",
      });
      this.arguments = [`--built-app=${appPath}`];
    },
  },
  {
    name: "built app reuses HEREJSApiKey",
    expected: "built EusoTrip.app reuses a HERE Navigate credential in a disallowed online/backend field",
    forbidden: ["credential-reuse-canary-must-not-print"],
    mutate(fixture) {
      const { appPath } = prepareBuiltAppStyles(fixture);
      const reusedCredential = "credential-reuse-canary-must-not-print";
      writeAppInfoPlist(appPath, {
        accessKeyID: reusedCredential,
        accessKeySecret: "different-fixture-secret-must-not-print",
        additionalHEREValues: { HEREJSApiKey: reusedCredential },
      });
      this.forbidden.push("different-fixture-secret-must-not-print");
      this.arguments = [`--built-app=${appPath}`];
    },
  },
  {
    name: "built app resource cannot duplicate Navigate credential",
    expected: "built EusoTrip.app contains a HERE Navigate credential outside the root Info.plist",
    forbidden: ["fixture-access-key-id", "fixture-access-key-secret"],
    mutate(fixture) {
      const { appPath } = prepareBuiltAppStyles(fixture);
      writeJSON(path.join(appPath, "Bundled", "configuration.json"), {
        unrelatedField: "fixture-access-key-secret",
      });
      this.arguments = [`--built-app=${appPath}`];
    },
  },
  {
    name: "framework executable traversal metadata",
    expected: "built HERE framework executable metadata is unsafe or incomplete",
    mutate(fixture) {
      prepareXCFramework(fixture);
      const { appPath, embeddedFramework } = prepareEmbeddedFramework(
        fixture,
        "../../outside-framework-executable",
      );
      writeFile(
        absolute(fixture, "Artifacts/outside-framework-executable"),
        "must never be passed to codesign\n",
      );
      this.arguments = [`--built-app=${appPath}`];
    },
  },
  {
    name: "framework executable symbolic link",
    expected: "built HERE framework executable metadata is unsafe or incomplete",
    mutate(fixture) {
      prepareXCFramework(fixture);
      const { appPath, embeddedFramework } = prepareEmbeddedFramework(fixture);
      const outsideExecutable = absolute(
        fixture,
        "Artifacts/outside-framework-executable-symlink-target",
      );
      writeFile(outsideExecutable, "must never be passed to codesign\n");
      fs.symlinkSync(outsideExecutable, path.join(embeddedFramework, "heresdk"));
      this.arguments = [`--built-app=${appPath}`];
    },
  },
  {
    name: "HERE_NOTICE at non-root bundle location",
    expected: "built EusoTrip.app must contain exactly one non-empty HERE_NOTICE at the runtime-resolvable bundle root",
    mutate(fixture) {
      const { appPath } = prepareBuiltAppStyles(fixture);
      const rootNotice = path.join(appPath, "HERE_NOTICE");
      const wrongLocation = path.join(appPath, "Nested", "HERE_NOTICE");
      ensureParent(wrongLocation);
      fs.renameSync(rootNotice, wrongLocation);
      this.arguments = [`--built-app=${appPath}`];
    },
  },
  {
    name: "duplicate HERE_NOTICE basename",
    expected: "built EusoTrip.app must contain exactly one non-empty HERE_NOTICE at the runtime-resolvable bundle root",
    mutate(fixture) {
      const { appPath } = prepareBuiltAppStyles(fixture);
      const duplicate = path.join(appPath, "Duplicate", "HERE_NOTICE");
      ensureParent(duplicate);
      fs.copyFileSync(path.join(appPath, "HERE_NOTICE"), duplicate);
      this.arguments = [`--built-app=${appPath}`];
    },
  },
  {
    name: "ZIP traversal entry",
    expected: "Vendor/HERE/heresdk-4.27.2.0-ios.zip: archive contains an unsafe path",
    mutate(fixture) {
      createMaliciousArchive(fixture, "traversal");
    },
  },
  {
    name: "ZIP symbolic-link entry",
    expected: "Vendor/HERE/heresdk-4.27.2.0-ios.zip: archive must not contain symbolic links",
    mutate(fixture) {
      createMaliciousArchive(fixture, "symlink");
    },
  },
];

try {
  for (const testCase of cases) {
    const fixture = cloneFixture(baseline, testCase.name);
    testCase.arguments = [];
    testCase.mutate(fixture);
    requireVerifierFailure(
      fixture,
      testCase.expected,
      testCase.arguments,
      testCase.forbidden ?? [],
    );
    console.log(`ok - ${testCase.name}`);
  }
  console.log(`HERE offline verifier regression harness passed: ${cases.length + 1} cases.`);
} finally {
  fs.rmSync(temporaryRoot, { recursive: true, force: true });
}
