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
const coverageTrustRelativePath =
  "EusoTrip/Services/HereMaps/Offline/HERE_INSTALLED_COVERAGE_TRUST.json";
const coverageManifestRelativePath =
  "EusoTrip/Services/HereMaps/Offline/HERE_INSTALLED_COVERAGE_MANIFEST.json";
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
    "EusoTrip/Services/HereMaps/HereMapWebView.swift",
    "EusoTrip/Views/Components/AppRadioSilenceAsyncImage.swift",
    "EusoTrip/Views/Maps/Offline",
    "EusoTrip/EusoTripApp.swift",
    "EusoTrip/Views/Catalyst/311_CatalystSettings.swift",
    "EusoTrip/Views/Rail/697_RailInterlineRoutePlan.swift",
    "EusoTrip/Views/Vessel/002_VesselBookingDetail.swift",
    "EusoTrip/Views/Driver/022_DockAssigned.swift",
    "EusoTrip/Views/Driver/035_EnRouteDrive.swift",
    "EusoTripOfflineTests/SignedInstalledCoverageResolverTests.swift",
    "EusoTripOfflineTests/AppRadioSilenceLeaseStateTests.swift",
    "EusoTripOfflineTests/HereFiniteCallbackWatchdogTests.swift",
    "EusoTripOfflineTests/HereNavigationInterruptionBoundaryTests.swift",
    "EusoTripOfflineTests/OfflineMapSurfaceLeaseStateTests.swift",
    "EusoTrip/Services/EusoTripAPI.swift",
    "EusoTrip/Services/PushService.swift",
    "EusoTrip/Features/Wallet/EusoTripAPI+Wallet.swift",
    "EusoTrip/Services/WeatherService.swift",
    "EusoTrip/Services/NewsOGImageCache.swift",
    "EusoTrip/Services/PTChannelManager.swift",
    "EusoTrip/Services/WatchAuthBridge.swift",
    "EusoTrip/Services/EusoTripApp+WatchBridge.swift",
    "EusoTrip/Services/AppAttestClient.swift",
    "EusoTrip/Services/AppleAuthProvider.swift",
    "EusoTrip/Services/EusoWalletApplePayProvider.swift",
    "EusoTrip/Services/EusoWalletPassService.swift",
    "EusoTrip/Services/ShipperAppIntents.swift",
    "EusoTrip/Services/RealtimeService.swift",
    "EusoTrip/Services/DriverGPSPushService.swift",
    "EusoTrip/Services/HOSClockService.swift",
    "EusoTrip/Services/ReminderSyncService.swift",
    "EusoTrip/Services/OfflineQueue.swift",
    "EusoTrip/Services/GeofenceService.swift",
    "EusoTrip Pulse Watch App/Services/AppRadioSilenceWatchState.swift",
    "EusoTrip Pulse Watch App/Services/AppRadioSilenceWatchPolicy.swift",
    "EusoTrip Pulse Watch App/WatchConnectivityManager.swift",
    "EusoTrip Pulse Watch App/EusoTripWatchApp.swift",
    "EusoTrip Pulse Watch App/EsangClient.swift",
    "EusoTrip Pulse Watch App/Services/OfflineQueue.swift",
    "EusoTrip Pulse Watch App/WatchAudioRecorder.swift",
    "EusoTrip Pulse Watch AppTests/AppRadioSilenceWatchStateTests.swift",
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
    "scripts/verify-exported-ipa-app-binding.mjs",
    "scripts/verify-exported-ipa-app-binding.test.mjs",
    "scripts/select-available-ios-simulator.mjs",
    "scripts/select-available-ios-simulator.test.mjs",
    "scripts/here-production-gate.mjs",
    "scripts/hash-release-artifact.mjs",
    "scripts/hash-release-artifact.test.mjs",
    "scripts/release-ladder-status.mjs",
    "scripts/release-ladder-status.test.mjs",
    "scripts/asc-build-status.mjs",
    "scripts/asc-build-status.test.mjs",
    "scripts/asc-latest-build.mjs",
    "scripts/asc-latest-build.test.mjs",
    "scripts/verify-release-config-attestation.mjs",
    "scripts/verify-release-config-attestation.test.mjs",
    "scripts/verify-here-offline-device-acceptance.mjs",
    "scripts/verify-here-offline-device-acceptance.test.mjs",
    "scripts/verify-github-release-governance.mjs",
    "scripts/verify-github-release-governance.test.mjs",
    "scripts/verify-reachable-here-credential-history.mjs",
    "scripts/verify-reachable-here-credential-history.test.mjs",
    "scripts/verify-canonical-route-trusted-clock.swift",
    ".github/workflows/here-offline-source-contract.yml",
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

function isoSeconds(milliseconds) {
  return new Date(Math.floor(milliseconds / 1_000) * 1_000)
    .toISOString()
    .replace(".000Z", "Z");
}

function installApprovedCoverageManifest(
  fixture,
  { mutatePayload = null } = {},
) {
  const now = Date.now();
  const catalogVersion = "here-catalog-regression-2026-09";
  const rightsID = "here-rights-regression-2026-09";
  const issuer = "https://coverage.eusotrip.test";
  const audience = "com.app.eusotrip";
  const rightsHolder = "HERE Global B.V.";
  const keyID = "here-coverage-regression-key";
  const payload = {
    schemaVersion: 1,
    issuer,
    audience,
    manifestID: "here-coverage-regression-manifest",
    sequence: 1,
    issuedAt: isoSeconds(now - 60_000),
    validFrom: isoSeconds(now - 3_600_000),
    validUntil: isoSeconds(now + 7 * 24 * 60 * 60 * 1_000),
    catalogVersion,
    source: {
      vendor: "HERE",
      product: "HERE_SDK_NAVIGATE_IOS",
      sdkVersion: "4.27.2.0",
      rightsID,
      rightsHolder,
      rightsValidFrom: isoSeconds(now - 24 * 60 * 60 * 1_000),
      rightsValidUntil: isoSeconds(now + 30 * 24 * 60 * 60 * 1_000),
    },
    regions: [
      {
        regionID: "here:region:regression",
        catalogVersion,
        status: "active",
        validFrom: isoSeconds(now - 1_800_000),
        validUntil: isoSeconds(now + 6 * 24 * 60 * 60 * 1_000),
        rightsID,
        boundary: {
          polygons: [
            {
              exterior: {
                coordinates: [
                  { latitude: 0, longitude: 0 },
                  { latitude: 0, longitude: 10 },
                  { latitude: 10, longitude: 10 },
                  { latitude: 10, longitude: 0 },
                  { latitude: 0, longitude: 0 },
                ],
              },
              holes: [],
            },
          ],
        },
      },
    ],
  };
  mutatePayload?.(payload);
  const { publicKey, privateKey } = crypto.generateKeyPairSync("ed25519");
  const publicKeyDER = publicKey.export({ format: "der", type: "spki" });
  assert.equal(publicKeyDER.subarray(0, -32).toString("hex"), "302a300506032b6570032100");
  const rawPublicKey = publicKeyDER.subarray(-32);
  const payloadBytes = Buffer.from(JSON.stringify(payload), "utf8");
  const envelope = {
    keyID,
    algorithm: "ed25519",
    payload: payloadBytes.toString("base64"),
    signature: crypto.sign(null, payloadBytes, privateKey).toString("base64"),
  };
  const trust = {
    schemaVersion: 1,
    status: "approved",
    issuer,
    audience,
    expectedSDKVersion: "4.27.2.0",
    expectedRightsHolder: rightsHolder,
    verificationKeyID: keyID,
    ed25519PublicKeyBase64: rawPublicKey.toString("base64"),
    initialSignedManifestResource: path.basename(coverageManifestRelativePath),
    routeCorridorHalfWidthMeters: 75,
    approvedBy: "coverage-regression-approver",
    approvedAt: isoSeconds(now - 30_000),
  };
  writeJSON(absolute(fixture, coverageManifestRelativePath), envelope);
  writeJSON(absolute(fixture, coverageTrustRelativePath), trust);
  commitFixturePaths(
    fixture,
    [coverageManifestRelativePath, coverageTrustRelativePath],
    "approved synthetic signed coverage fixture",
  );
  return { envelope, payload, trust };
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
    routePlanIssuer = "eusotrip-route-authority",
    routePlanAudience = "eusotrip-ios",
    routePlanKeyID = "route-key-2026-09",
    routePlanPublicKey = Buffer.alloc(32, 7).toString("base64"),
    additionalHEREValues = {},
  } = {},
) {
  const credentialEntries = [
    ["HERESDKAccessKeyID", accessKeyID],
    ["HERESDKAccessKeySecret", accessKeySecret],
    ["EusoRoutePlanIssuer", routePlanIssuer],
    ["EusoRoutePlanAudience", routePlanAudience],
    ["EusoRoutePlanKeyID", routePlanKeyID],
    ["EusoRoutePlanPublicKey", routePlanPublicKey],
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
  fs.copyFileSync(
    absolute(fixture, coverageTrustRelativePath),
    path.join(appPath, path.basename(coverageTrustRelativePath)),
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

const approvedCoverageBaseline = cloneFixture(
  baseline,
  "valid approved signed coverage baseline",
);
installApprovedCoverageManifest(approvedCoverageBaseline);
const approvedCoverageBaselineResult = runVerifier(approvedCoverageBaseline);
assert.equal(
  approvedCoverageBaselineResult.status,
  0,
  `valid approved signed coverage must satisfy the source verifier\n${combinedOutput(approvedCoverageBaselineResult)}`,
);
console.log("ok - valid approved signed coverage baseline");

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
    name: "malformed installed-coverage trust document is sanitized",
    expected: "EusoTrip/Services/HereMaps/Offline/HERE_INSTALLED_COVERAGE_TRUST.json: invalid installed-coverage trust document (SyntaxError)",
    forbidden: ["at JSON.parse", "verify-here-offline-contract.mjs:"],
    mutate(fixture) {
      writeFile(absolute(fixture, coverageTrustRelativePath), "{\n");
    },
  },
  {
    name: "installed-coverage manifest resource cannot traverse the bundle",
    expected: "EusoTrip/Services/HereMaps/Offline/HERE_INSTALLED_COVERAGE_TRUST.json: invalid installed-coverage trust document (AssertionError)",
    forbidden: ["at createBaselineFixture", "verify-here-offline-contract.mjs:"],
    mutate(fixture) {
      const trust = readJSON(absolute(fixture, coverageTrustRelativePath));
      trust.initialSignedManifestResource = "../../outside-coverage.json";
      writeJSON(absolute(fixture, coverageTrustRelativePath), trust);
    },
  },
  {
    name: "approved installed-coverage manifest requires a valid Ed25519 signature",
    expected: "approved signed installed-region coverage manifest failed Ed25519, pinned-claim, validity, or geometry verification",
    mutate(fixture) {
      installApprovedCoverageManifest(fixture);
      const manifestPath = absolute(fixture, coverageManifestRelativePath);
      const envelope = readJSON(manifestPath);
      const signature = Buffer.from(envelope.signature, "base64");
      signature[0] ^= 0x01;
      envelope.signature = signature.toString("base64");
      writeJSON(manifestPath, envelope);
    },
  },
  {
    name: "approved installed-coverage manifest pins signed issuer claims",
    expected: "approved signed installed-region coverage manifest failed Ed25519, pinned-claim, validity, or geometry verification",
    mutate(fixture) {
      installApprovedCoverageManifest(fixture, {
        mutatePayload(payload) {
          payload.issuer = "https://untrusted-coverage.example.invalid";
        },
      });
    },
  },
  {
    name: "approved installed-coverage manifest pins the signed payload schema",
    expected: "approved signed installed-region coverage manifest failed Ed25519, pinned-claim, validity, or geometry verification",
    mutate(fixture) {
      installApprovedCoverageManifest(fixture, {
        mutatePayload(payload) {
          payload.schemaVersion = 2;
        },
      });
    },
  },
  {
    name: "approved installed-coverage manifest must be currently valid",
    expected: "approved signed installed-region coverage manifest failed Ed25519, pinned-claim, validity, or geometry verification",
    mutate(fixture) {
      installApprovedCoverageManifest(fixture, {
        mutatePayload(payload) {
          const now = Date.now();
          payload.issuedAt = isoSeconds(now - 24 * 60 * 60 * 1_000);
          payload.validFrom = isoSeconds(now - 2 * 24 * 60 * 60 * 1_000);
          payload.validUntil = isoSeconds(now - 10 * 60 * 1_000);
          payload.source.rightsValidFrom = isoSeconds(now - 3 * 24 * 60 * 60 * 1_000);
          payload.source.rightsValidUntil = isoSeconds(now - 10 * 60 * 1_000);
          payload.regions[0].validFrom = isoSeconds(now - 24 * 60 * 60 * 1_000);
          payload.regions[0].validUntil = isoSeconds(now - 10 * 60 * 1_000);
        },
      });
    },
  },
  {
    name: "approved installed-coverage manifest rejects invalid signed geometry",
    expected: "approved signed installed-region coverage manifest failed Ed25519, pinned-claim, validity, or geometry verification",
    mutate(fixture) {
      installApprovedCoverageManifest(fixture, {
        mutatePayload(payload) {
          payload.regions[0].boundary.polygons[0].exterior.coordinates.pop();
        },
      });
    },
  },
  {
    name: "approved installed-coverage manifest must remain committed unchanged",
    expected: "release blocker: approved signed installed-region coverage manifest is not committed unchanged in HEAD",
    mutate(fixture) {
      installApprovedCoverageManifest(fixture);
      fs.appendFileSync(absolute(fixture, coverageManifestRelativePath), "\n");
      this.arguments = ["--release"];
    },
  },
  {
    name: "production road journey cannot omit its local search caller",
    expected: "EusoTrip/Views/Maps/Offline/OfflineRoadJourneyView.swift: missing \"composition.searchOffline(\"",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTrip/Views/Maps/Offline/OfflineRoadJourneyView.swift",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          "composition.searchOffline(",
          "composition.searchUnavailableForMutationTest(",
        ),
      );
    },
  },
  {
    name: "installed-coverage trusted-time verifier cannot be removed",
    expected: "EusoTripOfflineTests/SignedInstalledCoverageResolverTests.swift: missing \"Signed installed-coverage trusted-time verification passed: 5 cases\"",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTripOfflineTests/SignedInstalledCoverageResolverTests.swift",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          "Signed installed-coverage trusted-time verification passed: 5 cases",
          "coverage verification removed by mutation test",
        ),
      );
    },
  },
  {
    name: "canonical trusted-clock harness cannot print success without running cases",
    expected: "canonical route trusted-clock source harness main no longer executes all five cases before reporting success",
    mutate(fixture) {
      const file = absolute(fixture, "scripts/verify-canonical-route-trusted-clock.swift");
      const source = fs.readFileSync(file, "utf8");
      writeFile(
        file,
        source.replace(
          [
            "        try verifySameBootRelaunch()",
            "        try verifyRebootFailsClosed()",
            "        try verifyUptimeRollbackFailsClosed()",
            "        try verifyMalformedPersistenceFailsClosed()",
            "        try verifyInvalidationPreventsReuse()",
          ].join("\n"),
          "        // Mutation fixture intentionally skips every case.",
        ),
      );
    },
  },
  {
    name: "coverage trusted-time harness cannot print success without running cases",
    expected: "signed installed-coverage trusted-time source harness main no longer executes all five cases before reporting success",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTripOfflineTests/SignedInstalledCoverageResolverTests.swift",
      );
      const source = fs.readFileSync(file, "utf8");
      writeFile(
        file,
        source.replace(
          [
            "        try await verifySameBootRelaunch()",
            "        try await verifyRebootFailsClosed()",
            "        try await verifyUptimeRollbackFailsClosed()",
            "        try await verifyAnchorTamperFailsClosed()",
            "        try await verifyExpiryCannotBeRevivedByWallClockRollback()",
          ].join("\n"),
          "        // Mutation fixture intentionally skips every case.",
        ),
      );
    },
  },
  {
    name: "lease XCTest names cannot hide empty test bodies",
    expected: "EusoTripOfflineTests/OfflineMapSurfaceLeaseStateTests.swift: testSecondWindowCannotEnterWhileFirstOwnsSurface no longer exercises the lease transition with meaningful assertions",
    mutate(fixture) {
      writeFile(
        absolute(fixture, "EusoTripOfflineTests/OfflineMapSurfaceLeaseStateTests.swift"),
        [
          "import XCTest",
          "@testable import EusoTrip",
          "final class OfflineMapSurfaceLeaseStateTests: XCTestCase {",
          "    func testSecondWindowCannotEnterWhileFirstOwnsSurface() {}",
          "    func testSameOwnerReservationIsIdempotentDuringLoading() {}",
          "    func testReleaseHandsSurfaceToWaitingWindow() {}",
          "    func testOpaqueFailureForceReleaseWakesWaiters() {}",
          "}",
          "",
        ].join("\n"),
      );
    },
  },
  {
    name: "source CI cannot omit installed-coverage trusted-time verification",
    expected: "release blocker: committed source-only HERE CI does not compile tests and inspect every public incident-relevant ref",
    mutate(fixture) {
      const file = absolute(
        fixture,
        ".github/workflows/here-offline-source-contract.yml",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replaceAll(
          "SIGNED_COVERAGE_SOURCE_VERIFICATION",
          "COVERAGE_VERIFICATION_REMOVED",
        ),
      );
      this.arguments = ["--release"];
    },
  },
  {
    name: "source CI must execute the compiled coverage clock binary",
    expected: "release blocker: committed source-only HERE CI does not compile tests and inspect every public incident-relevant ref",
    mutate(fixture) {
      const file = absolute(
        fixture,
        ".github/workflows/here-offline-source-contract.yml",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          '          "$coverage_clock_binary"\n',
          "          : # compiled coverage clock binary invocation removed\n",
        ),
      );
      this.arguments = ["--release"];
    },
  },
  {
    name: "TestFlight preflight cannot omit installed-coverage trusted-time verification",
    expected: "release blocker: TestFlight automation can upload before the final exported app passes HERE production and offline release gates",
    mutate(fixture) {
      const file = absolute(fixture, deployScriptRelativePath);
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replaceAll(
          "SIGNED_COVERAGE_SOURCE_VERIFICATION",
          "COVERAGE_VERIFICATION_REMOVED",
        ),
      );
      this.arguments = ["--release"];
    },
  },
  {
    name: "TestFlight preflight must execute the compiled canonical clock binary",
    expected: "release blocker: TestFlight automation can upload before the final exported app passes HERE production and offline release gates",
    mutate(fixture) {
      const file = absolute(fixture, deployScriptRelativePath);
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          '"$TRUSTED_CLOCK_VERIFY_BINARY"\n',
          ": # compiled canonical clock binary invocation removed\n",
        ),
      );
      this.arguments = ["--release"];
    },
  },
  {
    name: "canonical route download cannot omit signed payload validation",
    expected: "canonical route download no longer validates the signed payload against the authenticated principal scope and freight mode",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTrip/Services/HereMaps/Offline/Core/CanonicalRoutePlanClient.swift",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          "Self.validateSignedPayload(",
          "Self.acceptUncheckedPayloadForMutation(",
        ),
      );
    },
  },
  {
    name: "truck route calculation cannot replace explicit constraints with nil",
    expected: "offline road/truck routing no longer binds explicit constraints, fresh origin, selected destination, and input generation",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTrip/Views/Maps/Offline/OfflineRoadJourneyView.swift",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          "truckConstraints: constraints",
          "truckConstraints: nil",
        ),
      );
    },
  },
  {
    name: "Rail signed download cannot omit an authenticated account recheck",
    expected: "Rail offline route caller no longer preserves account rechecks around signed download, ingest, and restore",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTrip/Views/Rail/697_RailInterlineRoutePlan.swift",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          "session.user?.id == authenticatedUser.id",
          'session.user?.id == "mutation-user"',
        ),
      );
    },
  },
  {
    name: "app radio-silence harness cannot print success without lease transitions",
    expected: "app radio-silence source harness main no longer exercises lease ownership and atomic phone-mirror restart/corruption semantics before completion",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTripOfflineTests/AppRadioSilenceLeaseStateTests.swift",
      );
      const source = fs.readFileSync(file, "utf8");
      writeFile(
        file,
        source.replace(
          /(@main\s+enum AppRadioSilenceLeaseStateSourceVerification\s*\{\s*static func main\(\)\s*\{)[\s\S]*?(\n\s*\}\s*\}\s*#endif)/,
          '$1\n        print("mutation reports success without verification")$2',
        ),
      );
    },
  },
  {
    name: "app radio-silence XCTest names cannot hide empty bodies",
    expected: "EusoTripOfflineTests/AppRadioSilenceLeaseStateTests.swift: XCTest bodies no longer assert reference-counted and idempotent lease ownership",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTripOfflineTests/AppRadioSilenceLeaseStateTests.swift",
      );
      const source = fs.readFileSync(file, "utf8");
      writeFile(
        file,
        source.replace(
          /func testFirstAndNestedLeasesRequireFinalRelease\(\)\s*\{[\s\S]*?\n\s*\}\n\n\s*func testDuplicate/,
          "func testFirstAndNestedLeasesRequireFinalRelease() {}\n\n    func testDuplicate",
        ),
      );
    },
  },
  {
    name: "source CI must execute the compiled app radio-silence binary",
    expected: "release blocker: committed source-only HERE CI does not compile tests and inspect every public incident-relevant ref",
    mutate(fixture) {
      const file = absolute(
        fixture,
        ".github/workflows/here-offline-source-contract.yml",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          '          "$app_radio_silence_binary"\n',
          "          : # compiled app radio-silence binary invocation removed\n",
        ),
      );
      this.arguments = ["--release"];
    },
  },
  {
    name: "TestFlight preflight must execute the compiled app radio-silence binary",
    expected: "release blocker: TestFlight automation can upload before the final exported app passes HERE production and offline release gates",
    mutate(fixture) {
      const file = absolute(fixture, deployScriptRelativePath);
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          '"$APP_RADIO_SILENCE_VERIFY_BINARY"\n',
          ": # compiled app radio-silence binary invocation removed\n",
        ),
      );
      this.arguments = ["--release"];
    },
  },
  {
    name: "radio-silence acquisition cannot omit a required producer suspension",
    expected: "app radio-silence acquisition no longer retries durable ENFORCED propagation on every lease, withholds readiness on failure, and closes all in-process transports on the first lease",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTrip/Services/HereMaps/Offline/Core/AppRadioSilenceCoordinator.swift",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          "HOSClockService.shared.suspendForAppRadioSilence()",
          "_ = HOSClockService.shared",
        ),
      );
    },
  },
  {
    name: "Driver offline journey cannot omit dismissal lease release",
    expected: "Driver offline journey no longer acquires before presentation and releases its app radio-silence lease on every controlled dismissal path",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTrip/Views/Driver/035_EnRouteDrive.swift",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          "onDismiss: releaseAppRadioSilenceLease",
          "onDismiss: {}",
        ),
      );
    },
  },
  {
    name: "API radio-silence gate cannot preserve in-flight URLSession work",
    expected: "EusoTripAPI radio-silence boundary no longer combines the in-process/app-group gate or invalidates and pre/post-gates every main and auxiliary URLSession transport",
    mutate(fixture) {
      const file = absolute(fixture, "EusoTrip/Services/EusoTripAPI.swift");
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          "session.invalidateAndCancel()",
          "session.finishTasksAndInvalidate()",
        ),
      );
    },
  },
  {
    name: "online HERE WebView cannot weaken the active radio-silence guard",
    expected: "HereMapWebView no longer synchronously stops and blanks active JS maps, guards make/update while enforced, and rebuilds on both policy edges",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTrip/Services/HereMaps/HereMapWebView.swift",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          "guard !EusoTripAPI.shared.isAppRadioSilenceEnforced else {",
          "guard EusoTripAPI.shared.isAppRadioSilenceEnforced else {",
        ),
      );
    },
  },
  {
    name: "finite callback watchdog cannot accept a second terminal result",
    expected: "HERE finite callback watchdog no longer guarantees a bounded, cancellation-aware, exactly-once terminal result with harmless late callbacks",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTrip/Services/HereMaps/Offline/SDK/HereFiniteCallbackWatchdog.swift",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          "guard terminalResult == nil else {",
          "guard terminalResult != nil else {",
        ),
      );
    },
  },
  {
    name: "finite callback watchdog cancellation must interrupt native work",
    expected: "HERE finite callback watchdog no longer guarantees a bounded, cancellation-aware, exactly-once terminal result with harmless late callbacks",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTrip/Services/HereMaps/Offline/SDK/HereFiniteCallbackWatchdog.swift",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          "self?.interrupt()",
          "_ = self",
        ),
      );
    },
  },
  {
    name: "finite callback timeout XCTest cannot be empty",
    expected: "EusoTripOfflineTests/HereFiniteCallbackWatchdogTests.swift: testTimeoutInterruptsNativeOperationAndRejectsLateCallback no longer proves its finite callback boundary with meaningful operations and assertions",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTripOfflineTests/HereFiniteCallbackWatchdogTests.swift",
      );
      const source = fs.readFileSync(file, "utf8");
      writeFile(
        file,
        source.replace(
          /func testTimeoutInterruptsNativeOperationAndRejectsLateCallback\(\) async\s*\{[\s\S]*?\n\s*\}\n\n\s*func testTaskCancellation/,
          "func testTimeoutInterruptsNativeOperationAndRejectsLateCallback() async {}\n\n    func testTaskCancellation",
        ),
      );
    },
  },
  {
    name: "offline search callback must cancel its native task",
    expected: "HERE offline search and route calculation no longer bound native one-shot callbacks with typed timeouts, native cancellation, and late-result rejection",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTrip/Services/HereMaps/Offline/SDK/HereNavigateOfflineEngine.swift",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          "searchTask.cancel()",
          "_ = searchTask",
        ),
      );
    },
  },
  {
    name: "map-transfer progress must heartbeat the inactivity watchdog",
    expected: "HERE download and catalog-update bridges no longer heartbeat finite completion waits, suspend inactivity while paused, bound control callbacks, and cancel native work exactly through the owned bridge",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTrip/Services/HereMaps/Offline/SDK/HereNavigateOfflineEngine.swift",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          "completionWatchdog.heartbeat()",
          "_ = completionWatchdog",
        ),
      );
    },
  },
  {
    name: "paused map transfer must suspend completion inactivity timeout",
    expected: "HERE download and catalog-update bridges no longer heartbeat finite completion waits, suspend inactivity while paused, bound control callbacks, and cancel native work exactly through the owned bridge",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTrip/Services/HereMaps/Offline/SDK/HereNavigateOfflineEngine.swift",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          "completionWatchdog.suspendTimeout()",
          "completionWatchdog.resumeTimeout()",
        ),
      );
    },
  },
  {
    name: "audio interruption resume requires a not-before fresh fix",
    expected: "HERE navigation interruption boundary no longer mutes native callbacks until the system authorizes resume and a not-before fresh location is accepted",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTrip/Services/HereMaps/Offline/SDK/HereNavigateNavigationSession.swift",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          "observedAt >= notBefore else { return false }",
          "observedAt < notBefore else { return false }",
        ),
      );
    },
  },
  {
    name: "audio interruption must mute prepared voice output",
    expected: "HERE navigation audio interruption handling no longer cancels reroute, removes delegates, mutes voice, and requires generation-bound audio recovery before awaiting a fresh fix",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTrip/Services/HereMaps/Offline/SDK/HereNavigateNavigationSession.swift",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          [
            "            if let navigator {",
            "                invalidateNativeDelegates(on: navigator)",
            "            }",
            "            await stopPreparedVoiceOutput()",
          ].join("\n"),
          [
            "            if let navigator {",
            "                invalidateNativeDelegates(on: navigator)",
            "            }",
            "            // mutation leaves prepared voice output active",
          ].join("\n"),
        ),
      );
    },
  },
  {
    name: "background resume must match the operation paused by this owner",
    expected: "offline production background handling no longer pauses only an owned running transfer and resumes only the same paused operation after a foreground edge",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTrip/Services/HereMaps/Offline/OfflineMapProductionComposition.swift",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          "operation.id == operationID",
          "operation.id != operationID",
        ),
      );
    },
  },
  {
    name: "native route projection cannot omit local HERE provenance",
    expected: "HERE native journey projection no longer enforces mutually exclusive verified local-road/server-canonical Rail-or-Vessel geometry or renders route and live location with follow camera",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTrip/Services/HereMaps/Offline/SDK/HereNavigateOfflineMapSurface.swift",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          "route.provenance == .hereOfflineLocal",
          "route.provenance == .serverCanonical",
        ),
      );
    },
  },
  {
    name: "server-canonical projection requires every segment mode to match",
    expected: "HERE native journey projection no longer enforces mutually exclusive verified local-road/server-canonical Rail-or-Vessel geometry or renders route and live location with follow camera",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTrip/Services/HereMaps/Offline/SDK/HereNavigateOfflineMapSurface.swift",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          "route.segments.allSatisfy({ $0.mode == route.mode })",
          "!route.segments.isEmpty",
        ),
      );
    },
  },
  {
    name: "native style cannot reveal before pending journey projection applies",
    expected: "HERE native map-style loading no longer has a finite callback boundary or atomically applies pending journey projection before revealing the rendered scene",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTrip/Services/HereMaps/Offline/SDK/HereNavigateOfflineMapSurface.swift",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          "try self.applyJourneyProjection(self.journeyProjection)",
          "_ = self.journeyProjection",
        ),
      );
    },
  },
  {
    name: "opaque native map failure must remove journey artifacts",
    expected: "HERE native map clear and opaque failure no longer remove projection artifacts before discarding the native surface",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTrip/Services/HereMaps/Offline/SDK/HereNavigateOfflineMapSurface.swift",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          [
            "        nativeSceneLoadTask?.cancel()",
            "        nativeSceneLoadTask = nil",
            "        removeNativeJourneyProjection()",
            "        releaseRuntimeRenderingLease()",
          ].join("\n"),
          [
            "        nativeSceneLoadTask?.cancel()",
            "        nativeSceneLoadTask = nil",
            "        releaseRuntimeRenderingLease()",
          ].join("\n"),
        ),
      );
    },
  },
  {
    name: "native map host lease cannot start before native radio silence",
    expected: "reusable native map host no longer keeps lease ownership opt-in, restricts nested acquisition to an already enforced radio-silent snapshot, and blocks rendering until app/native enforcement are proven",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTrip/Views/Maps/Offline/OfflineMapLibraryView.swift",
      );
      writeFile(
        file,
        fs.readFileSync(file, "utf8").replace(
          [
            "    private var appRadioSilenceEligibility: Bool {",
            "        acquiresAppRadioSilenceLease",
            "            && offlineSnapshot.connectivityPolicy == .radioSilent",
            "            && offlineSnapshot.radioSilenceState == .enforced",
          ].join("\n"),
          [
            "    private var appRadioSilenceEligibility: Bool {",
            "        acquiresAppRadioSilenceLease",
            "            && offlineSnapshot.connectivityPolicy == .radioSilent",
            "            && offlineSnapshot.radioSilenceState != .enforced",
          ].join("\n"),
        ),
      );
    },
  },
  {
    name: "passive canonical fallback cannot own app radio silence",
    expected: "EusoTrip/Views/Maps/Offline/CanonicalOfflineRouteItineraryView.swift: forbidden \"AppRadioSilenceCoordinator\"",
    mutate(fixture) {
      const file = absolute(
        fixture,
        "EusoTrip/Views/Maps/Offline/CanonicalOfflineRouteItineraryView.swift",
      );
      writeFile(
        file,
        `${fs.readFileSync(file, "utf8")}\nprivate let mutationLeaseOwner = AppRadioSilenceCoordinator.shared\n`,
      );
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
    name: "dirty installed-coverage trust document in release mode",
    expected: "release blocker: HERE signed installed-coverage trust document is not committed unchanged in HEAD",
    mutate(fixture) {
      fs.appendFileSync(absolute(fixture, coverageTrustRelativePath), "\n");
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
    name: "built app route trust requires an Ed25519 public key",
    expected: "built EusoTrip.app has invalid or unresolved signed route-plan trust configuration",
    mutate(fixture) {
      const { appPath } = prepareBuiltAppStyles(fixture);
      writeAppInfoPlist(appPath, { routePlanPublicKey: "not-an-ed25519-key" });
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
  console.log(`HERE offline verifier regression harness passed: ${cases.length + 2} cases.`);
} finally {
  fs.rmSync(temporaryRoot, { recursive: true, force: true });
}
