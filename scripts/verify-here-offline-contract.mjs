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
  navigateEngine: "EusoTrip/Services/HereMaps/Offline/SDK/HereNavigateOfflineEngine.swift",
  coordinator: "EusoTrip/Services/HereMaps/Offline/Core/OfflineMapCoordinator.swift",
  mapModels: "EusoTrip/Services/HereMaps/Offline/Core/OfflineMapModels.swift",
  routeModels: "EusoTrip/Services/HereMaps/Offline/Core/OfflineRouteModels.swift",
  navigationModels: "EusoTrip/Services/HereMaps/Offline/Core/OfflineNavigationModels.swift",
  routeStore: "EusoTrip/Services/HereMaps/Offline/Core/CanonicalRoutePackageStore.swift",
  routeClient: "EusoTrip/Services/HereMaps/Offline/Core/CanonicalRoutePlanClient.swift",
  routeReader: "EusoTrip/Services/HereMaps/Offline/Core/CanonicalRouteOfflineReader.swift",
  trustedRouteClock: "EusoTrip/Services/HereMaps/Offline/Core/CanonicalRouteTrustedClock.swift",
  appRadioSilenceLeaseState: "EusoTrip/Services/HereMaps/Offline/Core/AppRadioSilenceLeaseState.swift",
  appRadioSilenceCoordinator: "EusoTrip/Services/HereMaps/Offline/Core/AppRadioSilenceCoordinator.swift",
  appRadioSilenceSharedState: "EusoTrip/Services/HereMaps/Offline/Core/AppRadioSilenceSharedState.swift",
  appRadioSilenceDirectTransport: "EusoTrip/Services/HereMaps/Offline/Core/AppRadioSilenceDirectTransportController.swift",
  appRadioSilenceAsyncImage: "EusoTrip/Views/Components/AppRadioSilenceAsyncImage.swift",
  coverageResolver: "EusoTrip/Services/HereMaps/Offline/Core/SignedInstalledCoverageResolver.swift",
  coverageAdapter: "EusoTrip/Services/HereMaps/Offline/SDK/HereNavigateInstalledCoverageAdapter.swift",
  finiteCallbackWatchdog: "EusoTrip/Services/HereMaps/Offline/SDK/HereFiniteCallbackWatchdog.swift",
  locationSource: "EusoTrip/Services/HereMaps/Offline/SDK/HereNavigationLocationSource.swift",
  navigation: "EusoTrip/Services/HereMaps/Offline/SDK/HereNavigateNavigationSession.swift",
  surface: "EusoTrip/Services/HereMaps/Offline/SDK/HereNavigateOfflineMapSurface.swift",
  onlineMapWebView: "EusoTrip/Services/HereMaps/HereMapWebView.swift",
  productionComposition: "EusoTrip/Services/HereMaps/Offline/OfflineMapProductionComposition.swift",
  mapLibraryView: "EusoTrip/Views/Maps/Offline/OfflineMapLibraryView.swift",
  roadJourneyView: "EusoTrip/Views/Maps/Offline/OfflineRoadJourneyView.swift",
  driverEnRouteView: "EusoTrip/Views/Driver/035_EnRouteDrive.swift",
  canonicalItineraryView: "EusoTrip/Views/Maps/Offline/CanonicalOfflineRouteItineraryView.swift",
  railRouteCaller: "EusoTrip/Views/Rail/697_RailInterlineRoutePlan.swift",
  vesselRouteCaller: "EusoTrip/Views/Vessel/002_VesselBookingDetail.swift",
  appEntry: "EusoTrip/EusoTripApp.swift",
  pushService: "EusoTrip/Services/PushService.swift",
  settingsHost: "EusoTrip/Views/Catalyst/311_CatalystSettings.swift",
  api: "EusoTrip/Services/EusoTripAPI.swift",
  walletAPI: "EusoTrip/Features/Wallet/EusoTripAPI+Wallet.swift",
  realtimeService: "EusoTrip/Services/RealtimeService.swift",
  driverGPSPushService: "EusoTrip/Services/DriverGPSPushService.swift",
  hosClockService: "EusoTrip/Services/HOSClockService.swift",
  reminderSyncService: "EusoTrip/Services/ReminderSyncService.swift",
  offlineQueue: "EusoTrip/Services/OfflineQueue.swift",
  geofenceService: "EusoTrip/Services/GeofenceService.swift",
  weatherService: "EusoTrip/Services/WeatherService.swift",
  newsImageCache: "EusoTrip/Services/NewsOGImageCache.swift",
  ptChannelManager: "EusoTrip/Services/PTChannelManager.swift",
  watchAuthBridge: "EusoTrip/Services/WatchAuthBridge.swift",
  phoneWatchBridge: "EusoTrip/Services/EusoTripApp+WatchBridge.swift",
  appAttestClient: "EusoTrip/Services/AppAttestClient.swift",
  appleAuthProvider: "EusoTrip/Services/AppleAuthProvider.swift",
  walletApplePayProvider: "EusoTrip/Services/EusoWalletApplePayProvider.swift",
  walletPassService: "EusoTrip/Services/EusoWalletPassService.swift",
  shipperAppIntents: "EusoTrip/Services/ShipperAppIntents.swift",
  dockAssignedView: "EusoTrip/Views/Driver/022_DockAssigned.swift",
  watchRadioSilenceState: "EusoTrip Pulse Watch App/Services/AppRadioSilenceWatchState.swift",
  watchRadioSilencePolicy: "EusoTrip Pulse Watch App/Services/AppRadioSilenceWatchPolicy.swift",
  watchConnectivityManager: "EusoTrip Pulse Watch App/WatchConnectivityManager.swift",
  watchAppEntry: "EusoTrip Pulse Watch App/EusoTripWatchApp.swift",
  watchEsangClient: "EusoTrip Pulse Watch App/EsangClient.swift",
  watchOfflineQueue: "EusoTrip Pulse Watch App/Services/OfflineQueue.swift",
  watchAudioRecorder: "EusoTrip Pulse Watch App/WatchAudioRecorder.swift",
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
  coverageTrust: "EusoTrip/Services/HereMaps/Offline/HERE_INSTALLED_COVERAGE_TRUST.json",
  trustedClockVerifier: "scripts/verify-canonical-route-trusted-clock.swift",
  coverageResolverTests: "EusoTripOfflineTests/SignedInstalledCoverageResolverTests.swift",
  appRadioSilenceLeaseTests: "EusoTripOfflineTests/AppRadioSilenceLeaseStateTests.swift",
  watchRadioSilenceTests: "EusoTrip Pulse Watch AppTests/AppRadioSilenceWatchStateTests.swift",
  finiteCallbackWatchdogTests: "EusoTripOfflineTests/HereFiniteCallbackWatchdogTests.swift",
  navigationInterruptionTests: "EusoTripOfflineTests/HereNavigationInterruptionBoundaryTests.swift",
  surfaceLeaseTests: "EusoTripOfflineTests/OfflineMapSurfaceLeaseStateTests.swift",
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
  relative.trustedClockVerifier,
  relative.coverageResolverTests,
  relative.appRadioSilenceLeaseState,
  relative.appRadioSilenceCoordinator,
  relative.appRadioSilenceSharedState,
  relative.appRadioSilenceDirectTransport,
  relative.appRadioSilenceAsyncImage,
  relative.appRadioSilenceLeaseTests,
  relative.watchRadioSilenceState,
  relative.watchRadioSilencePolicy,
  relative.watchRadioSilenceTests,
  relative.finiteCallbackWatchdog,
  relative.finiteCallbackWatchdogTests,
  relative.navigationInterruptionTests,
  relative.navigateEngine,
  relative.navigationModels,
  relative.navigation,
  relative.surface,
  relative.productionComposition,
  relative.mapLibraryView,
  relative.roadJourneyView,
  relative.canonicalItineraryView,
  relative.api,
  relative.walletAPI,
  relative.realtimeService,
  relative.driverGPSPushService,
  relative.hosClockService,
  relative.reminderSyncService,
  relative.offlineQueue,
  relative.geofenceService,
  relative.weatherService,
  relative.newsImageCache,
  relative.ptChannelManager,
  relative.watchAuthBridge,
  relative.phoneWatchBridge,
  relative.appAttestClient,
  relative.appleAuthProvider,
  relative.walletApplePayProvider,
  relative.walletPassService,
  relative.shipperAppIntents,
  relative.pushService,
  relative.watchConnectivityManager,
  relative.watchAppEntry,
  relative.watchEsangClient,
  relative.watchOfflineQueue,
  relative.watchAudioRecorder,
  relative.dockAssignedView,
  relative.surfaceLeaseTests,
  relative.driverEnRouteView,
  relative.onlineMapWebView,
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
    if ([
      "true",
      "!DEBUG",
      "canImport(UIKit)",
      "canImport(CoreLocation)",
      "canImport(Security)",
      "canImport(AVFoundation)",
      "canImport(heresdk)",
      "os(iOS)&&canImport(AVFoundation)",
      "os(iOS)",
    ].includes(compact)) return true;
    if ([
      "false",
      "DEBUG",
      "canImport(AppKit)",
      "os(macOS)",
      "os(tvOS)",
      "os(watchOS)",
      "targetEnvironment(simulator)",
      "targetEnvironment(macCatalyst)",
    ].includes(compact)) return false;
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

function swiftDeclarationOriginalBody(source, declarationPattern, startIndex = 0) {
  const code = swiftCodeOnly(source);
  const tail = code.slice(startIndex);
  const match = tail.match(declarationPattern);
  if (!match || match.index === undefined) return "";
  const declarationStart = startIndex + match.index;
  const openingBrace = code.indexOf("{", declarationStart + match[0].length - 1);
  if (openingBrace < 0) return "";
  let depth = 0;
  for (let index = openingBrace; index < code.length; index += 1) {
    if (code[index] === "{") depth += 1;
    else if (code[index] === "}") {
      depth -= 1;
      if (depth === 0) return source.slice(openingBrace + 1, index);
    }
  }
  return "";
}

function containsInOrder(source, snippets) {
  let cursor = 0;
  for (const snippet of snippets) {
    const index = source.indexOf(snippet, cursor);
    if (index < 0) return false;
    cursor = index + snippet.length;
  }
  return true;
}

function canonicalBase64(value, expectedBytes = null, maximumBytes = null) {
  if (typeof value !== "string" || value.length === 0 || value.length % 4 !== 0 ||
      !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) {
    return null;
  }
  const decoded = Buffer.from(value, "base64");
  if (decoded.toString("base64") !== value ||
      (expectedBytes !== null && decoded.length !== expectedBytes) ||
      (maximumBytes !== null && decoded.length > maximumBytes)) {
    return null;
  }
  return decoded;
}

function normalizedCoverageIdentifier(value, maximumBytes = 256) {
  assert.equal(typeof value, "string");
  const normalized = value.trim();
  assert.ok(normalized.length > 0);
  assert.ok(Buffer.byteLength(normalized, "utf8") <= maximumBytes);
  return normalized;
}

function normalizedCoverageCatalogVersion(value) {
  const normalized = normalizedCoverageIdentifier(value, 128);
  assert.ok(!/[\u0000-\u001f\u007f-\u009f]/u.test(normalized));
  return normalized;
}

function coverageDate(value) {
  assert.equal(typeof value, "string");
  assert.match(value, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/);
  const milliseconds = Date.parse(value);
  assert.ok(Number.isFinite(milliseconds));
  return milliseconds;
}

function normalizedLongitudeDelta(value) {
  let result = value % 360;
  if (result > 180) result -= 360;
  if (result < -180) result += 360;
  return result;
}

function unwrapCoverageCoordinates(coordinates) {
  const result = [{ x: coordinates[0].longitude, y: coordinates[0].latitude }];
  let priorLongitude = coordinates[0].longitude;
  for (const coordinate of coordinates.slice(1)) {
    const longitude = priorLongitude +
      normalizedLongitudeDelta(coordinate.longitude - priorLongitude);
    result.push({ x: longitude, y: coordinate.latitude });
    priorLongitude = longitude;
  }
  return result;
}

const coverageGeometryEpsilon = 1e-10;

function coverageOrientation(a, b, c) {
  return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

function coveragePointOnSegment(point, start, end) {
  if (Math.abs(coverageOrientation(start, end, point)) > coverageGeometryEpsilon) return false;
  return point.x >= Math.min(start.x, end.x) - coverageGeometryEpsilon &&
    point.x <= Math.max(start.x, end.x) + coverageGeometryEpsilon &&
    point.y >= Math.min(start.y, end.y) - coverageGeometryEpsilon &&
    point.y <= Math.max(start.y, end.y) + coverageGeometryEpsilon;
}

function coverageSegmentsIntersect(a, b, c, d) {
  const first = coverageOrientation(a, b, c);
  const second = coverageOrientation(a, b, d);
  const third = coverageOrientation(c, d, a);
  const fourth = coverageOrientation(c, d, b);
  if (((first > 0 && second < 0) || (first < 0 && second > 0)) &&
      ((third > 0 && fourth < 0) || (third < 0 && fourth > 0))) {
    return true;
  }
  return (Math.abs(first) <= coverageGeometryEpsilon && coveragePointOnSegment(c, a, b)) ||
    (Math.abs(second) <= coverageGeometryEpsilon && coveragePointOnSegment(d, a, b)) ||
    (Math.abs(third) <= coverageGeometryEpsilon && coveragePointOnSegment(a, c, d)) ||
    (Math.abs(fourth) <= coverageGeometryEpsilon && coveragePointOnSegment(b, c, d));
}

function coverageCoordinatesEqual(left, right) {
  return left.latitude === right.latitude && left.longitude === right.longitude;
}

function validateCoverageCoordinate(value) {
  assert.ok(value && typeof value === "object" && !Array.isArray(value));
  assert.ok(Number.isFinite(value.latitude) && value.latitude >= -90 && value.latitude <= 90);
  assert.ok(Number.isFinite(value.longitude) && value.longitude >= -180 && value.longitude <= 180);
  return { latitude: value.latitude, longitude: value.longitude };
}

function validateCoverageRing(value) {
  assert.ok(value && typeof value === "object" && !Array.isArray(value));
  assert.ok(Array.isArray(value.coordinates));
  assert.ok(value.coordinates.length >= 4 && value.coordinates.length <= 100_000);
  const coordinates = value.coordinates.map(validateCoverageCoordinate);
  assert.ok(coverageCoordinatesEqual(coordinates[0], coordinates.at(-1)));
  for (let index = 0; index < coordinates.length - 1; index += 1) {
    assert.ok(!coverageCoordinatesEqual(coordinates[index], coordinates[index + 1]));
  }
  const points = unwrapCoverageCoordinates(coordinates);
  let twiceArea = 0;
  for (let index = 0; index < points.length - 1; index += 1) {
    twiceArea += points[index].x * points[index + 1].y -
      points[index + 1].x * points[index].y;
  }
  assert.ok(Math.abs(twiceArea) / 2 > coverageGeometryEpsilon);
  const edgeCount = points.length - 1;
  for (let firstIndex = 0; firstIndex < edgeCount; firstIndex += 1) {
    for (let secondIndex = firstIndex + 1; secondIndex < edgeCount; secondIndex += 1) {
      const adjacent = secondIndex === firstIndex + 1 ||
        (firstIndex === 0 && secondIndex === edgeCount - 1);
      if (!adjacent) {
        assert.ok(!coverageSegmentsIntersect(
          points[firstIndex], points[firstIndex + 1],
          points[secondIndex], points[secondIndex + 1],
        ));
      }
    }
  }
  return coordinates;
}

function coveragePointDisposition(coordinate, ring) {
  const points = unwrapCoverageCoordinates(ring);
  const averageLongitude = points.reduce((sum, point) => sum + point.x, 0) / points.length;
  const query = {
    x: coordinate.longitude + 360 * Math.round((averageLongitude - coordinate.longitude) / 360),
    y: coordinate.latitude,
  };
  let inside = false;
  for (let index = 0; index < points.length - 1; index += 1) {
    const start = points[index];
    const end = points[index + 1];
    if (coveragePointOnSegment(query, start, end)) return "boundary";
    const crosses = (start.y > query.y) !== (end.y > query.y);
    if (crosses) {
      const crossingX = start.x +
        (query.y - start.y) * (end.x - start.x) / (end.y - start.y);
      if (crossingX > query.x) inside = !inside;
    }
  }
  return inside ? "inside" : "outside";
}

function coverageGeographicSegmentsIntersect(a, b, c, d) {
  const firstStart = { x: a.longitude, y: a.latitude };
  const firstEnd = {
    x: a.longitude + normalizedLongitudeDelta(b.longitude - a.longitude),
    y: b.latitude,
  };
  const secondStartLongitude = a.longitude + normalizedLongitudeDelta(c.longitude - a.longitude);
  const secondStart = { x: secondStartLongitude, y: c.latitude };
  const secondEnd = {
    x: secondStartLongitude + normalizedLongitudeDelta(d.longitude - c.longitude),
    y: d.latitude,
  };
  return coverageSegmentsIntersect(firstStart, firstEnd, secondStart, secondEnd);
}

function coverageRingsIntersect(first, second) {
  for (let firstIndex = 0; firstIndex < first.length - 1; firstIndex += 1) {
    for (let secondIndex = 0; secondIndex < second.length - 1; secondIndex += 1) {
      if (coverageGeographicSegmentsIntersect(
        first[firstIndex], first[firstIndex + 1],
        second[secondIndex], second[secondIndex + 1],
      )) return true;
    }
  }
  return false;
}

function validateCoverageBoundary(value) {
  assert.ok(value && typeof value === "object" && !Array.isArray(value));
  assert.ok(Array.isArray(value.polygons));
  assert.ok(value.polygons.length > 0 && value.polygons.length <= 4_096);
  let coordinateCount = 0;
  for (const polygon of value.polygons) {
    assert.ok(polygon && typeof polygon === "object" && !Array.isArray(polygon));
    const exterior = validateCoverageRing(polygon.exterior);
    assert.ok(Array.isArray(polygon.holes) && polygon.holes.length <= 1_024);
    const holes = polygon.holes.map(validateCoverageRing);
    coordinateCount += exterior.length + holes.reduce((sum, ring) => sum + ring.length, 0);
    for (const hole of holes) {
      assert.equal(coveragePointDisposition(hole[0], exterior), "inside");
      assert.ok(!coverageRingsIntersect(exterior, hole));
    }
    for (let firstIndex = 0; firstIndex < holes.length; firstIndex += 1) {
      for (let secondIndex = firstIndex + 1; secondIndex < holes.length; secondIndex += 1) {
        assert.ok(!coverageRingsIntersect(holes[firstIndex], holes[secondIndex]));
        assert.equal(coveragePointDisposition(holes[firstIndex][0], holes[secondIndex]), "outside");
        assert.equal(coveragePointDisposition(holes[secondIndex][0], holes[firstIndex]), "outside");
      }
    }
  }
  return coordinateCount;
}

function verifyApprovedCoverageEnvelope(envelopeBytes, trust, now = Date.now()) {
  assert.ok(Buffer.isBuffer(envelopeBytes));
  assert.ok(envelopeBytes.length > 0 && envelopeBytes.length <= 24 * 1_024 * 1_024);
  const envelope = JSON.parse(envelopeBytes.toString("utf8"));
  assert.ok(envelope && typeof envelope === "object" && !Array.isArray(envelope));
  assert.equal(normalizedCoverageIdentifier(envelope.keyID), trust.verificationKeyID.trim());
  assert.equal(envelope.algorithm, "ed25519");
  const payloadBytes = canonicalBase64(envelope.payload, null, 16 * 1_024 * 1_024);
  const signature = canonicalBase64(envelope.signature, 64);
  const rawPublicKey = canonicalBase64(trust.ed25519PublicKeyBase64, 32);
  assert.ok(payloadBytes && payloadBytes.length > 0 && signature && rawPublicKey);
  const publicKey = crypto.createPublicKey({
    key: Buffer.concat([
      Buffer.from("302a300506032b6570032100", "hex"),
      rawPublicKey,
    ]),
    format: "der",
    type: "spki",
  });
  assert.ok(crypto.verify(null, payloadBytes, publicKey, signature));

  const payload = JSON.parse(payloadBytes.toString("utf8"));
  assert.ok(payload && typeof payload === "object" && !Array.isArray(payload));
  assert.equal(payload.schemaVersion, 1);
  assert.equal(normalizedCoverageIdentifier(payload.issuer), trust.issuer.trim());
  assert.equal(normalizedCoverageIdentifier(payload.audience), trust.audience.trim());
  normalizedCoverageIdentifier(payload.manifestID);
  assert.ok(Number.isSafeInteger(payload.sequence) && payload.sequence > 0);
  const issuedAt = coverageDate(payload.issuedAt);
  const validFrom = coverageDate(payload.validFrom);
  const validUntil = coverageDate(payload.validUntil);
  assert.ok(validUntil > validFrom && issuedAt <= validUntil);
  const catalogVersion = normalizedCoverageCatalogVersion(payload.catalogVersion);

  const source = payload.source;
  assert.ok(source && typeof source === "object" && !Array.isArray(source));
  assert.equal(source.vendor, "HERE");
  assert.equal(source.product, "HERE_SDK_NAVIGATE_IOS");
  assert.equal(normalizedCoverageIdentifier(source.sdkVersion), trust.expectedSDKVersion.trim());
  const rightsID = normalizedCoverageIdentifier(source.rightsID);
  assert.equal(
    normalizedCoverageIdentifier(source.rightsHolder),
    trust.expectedRightsHolder.trim(),
  );
  const rightsValidFrom = coverageDate(source.rightsValidFrom);
  const rightsValidUntil = coverageDate(source.rightsValidUntil);
  assert.ok(rightsValidUntil > rightsValidFrom);

  assert.ok(Array.isArray(payload.regions));
  assert.ok(payload.regions.length > 0 && payload.regions.length <= 4_096);
  const regionIDs = new Set();
  let coordinateCount = 0;
  for (const region of payload.regions) {
    assert.ok(region && typeof region === "object" && !Array.isArray(region));
    const regionID = normalizedCoverageIdentifier(region.regionID, 16 * 1_024 * 1_024);
    assert.ok(!regionIDs.has(regionID));
    regionIDs.add(regionID);
    assert.equal(normalizedCoverageCatalogVersion(region.catalogVersion), catalogVersion);
    assert.ok(["active", "revoked"].includes(region.status));
    const regionValidFrom = coverageDate(region.validFrom);
    const regionValidUntil = coverageDate(region.validUntil);
    assert.ok(regionValidUntil > regionValidFrom);
    assert.equal(normalizedCoverageIdentifier(region.rightsID), rightsID);
    assert.ok(regionValidFrom >= validFrom && regionValidUntil <= validUntil);
    assert.ok(regionValidFrom >= rightsValidFrom && regionValidUntil <= rightsValidUntil);
    coordinateCount += validateCoverageBoundary(region.boundary);
    assert.ok(coordinateCount <= 2_000_000);
  }

  const allowedClockSkew = 300_000;
  assert.ok(issuedAt <= now + allowedClockSkew);
  assert.ok(validFrom <= now + allowedClockSkew);
  assert.ok(rightsValidFrom <= now + allowedClockSkew);
  assert.ok(validUntil >= now - allowedClockSkew);
  assert.ok(rightsValidUntil >= now - allowedClockSkew);
  assert.ok(now - issuedAt <= 35 * 24 * 60 * 60 * 1_000 + allowedClockSkew);
  return payload;
}

function parsePBXObjects(source) {
  const lines = source.split(/\r?\n/);
  const objects = new Map();
  for (let index = 0; index < lines.length; index += 1) {
    const start = lines[index].match(/^\s*([A-Za-z0-9]{12,32})(?: \/\*.*\*\/)? = \{.*$/);
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
  return match ? [...match[1].matchAll(/\b([A-Za-z0-9]{12,32})\b/g)].map(item => item[1]) : [];
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
  const escapedTargetName = targetName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const target = [...objects.values()].find(object =>
    object.isa === "PBXNativeTarget" &&
    new RegExp(`\\bname\\s*=\\s*(?:"${escapedTargetName}"|${escapedTargetName});`).test(object.text));
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
  relative.navigateEngine,
  relative.coordinator,
  relative.mapModels,
  relative.routeModels,
  relative.navigationModels,
  relative.routeStore,
  relative.routeClient,
  relative.routeReader,
  relative.trustedRouteClock,
  relative.appRadioSilenceLeaseState,
  relative.appRadioSilenceCoordinator,
  relative.appRadioSilenceSharedState,
  relative.appRadioSilenceDirectTransport,
  relative.appRadioSilenceAsyncImage,
  relative.coverageResolver,
  relative.coverageAdapter,
  relative.locationSource,
  relative.navigation,
  relative.surface,
  relative.onlineMapWebView,
  relative.productionComposition,
  relative.mapLibraryView,
  relative.roadJourneyView,
  relative.driverEnRouteView,
  relative.canonicalItineraryView,
  relative.railRouteCaller,
  relative.vesselRouteCaller,
  relative.appEntry,
  relative.pushService,
  relative.settingsHost,
  relative.api,
  relative.walletAPI,
  relative.realtimeService,
  relative.driverGPSPushService,
  relative.hosClockService,
  relative.reminderSyncService,
  relative.offlineQueue,
  relative.geofenceService,
  relative.weatherService,
  relative.newsImageCache,
  relative.ptChannelManager,
  relative.watchAuthBridge,
  relative.phoneWatchBridge,
  relative.appAttestClient,
  relative.appleAuthProvider,
  relative.walletApplePayProvider,
  relative.walletPassService,
  relative.shipperAppIntents,
  relative.watchRadioSilenceState,
  relative.watchRadioSilencePolicy,
  relative.watchConnectivityManager,
  relative.watchAppEntry,
  relative.watchEsangClient,
  relative.watchOfflineQueue,
  relative.watchAudioRecorder,
  relative.dockAssignedView,
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
  relative.coverageTrust,
  relative.trustedClockVerifier,
  relative.coverageResolverTests,
  relative.appRadioSilenceLeaseTests,
  relative.watchRadioSilenceTests,
  relative.finiteCallbackWatchdog,
  relative.finiteCallbackWatchdogTests,
  relative.navigationInterruptionTests,
  relative.surfaceLeaseTests,
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
  [relative.coverageTrust, "HERE signed installed-coverage trust document"],
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
requireText(relative.routeClient, [
  "route.getOfflinePackage",
  "enum CanonicalRouteFreightSubject",
  "CanonicalRouteAuthenticatedPrincipal",
  "authenticatedUser: AuthUser",
  "signedScopeMismatch",
  "signedModeMismatch",
]);
requireText(relative.routeReader, [
  "maximumServerObservationAge: TimeInterval = 24 * 60 * 60",
  "composition.observeCanonicalRoute",
  "package.scope == scope",
  "package.mode == subject.expectedRouteMode",
]);
requireText(relative.trustedRouteClock, [
  "import Security",
  "kSecClassGenericPassword",
  "ProcessInfo.processInfo.systemUptime",
  "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly",
  "kern.bootsessionuuid",
  "KeychainCanonicalRouteTrustedAnchorPersistence()",
  "case monotonicUptimeRegressed",
  "case bootSessionChanged",
  "case persistedAnchorInvalid",
  "case authenticatedAnchorUnavailable",
  "func establishAuthenticatedAnchor",
  "func invalidateAll() throws",
]);
requireText(relative.trustedClockVerifier, [
  "Canonical route trusted-clock verification passed: 5 cases",
  "verifySameBootRelaunch",
  "verifyRebootFailsClosed",
  "verifyUptimeRollbackFailsClosed",
]);
const trustedClockVerifierSource = exists(relative.trustedClockVerifier)
  ? read(relative.trustedClockVerifier)
  : "";
const trustedClockHarnessStart = swiftCodeOnly(trustedClockVerifierSource).indexOf("@main");
const trustedClockHarnessMain = trustedClockHarnessStart >= 0
  ? swiftDeclarationOriginalBody(
      trustedClockVerifierSource,
      /\bstatic\s+func\s+main\s*\(\s*\)\s*throws\s*\{/,
      trustedClockHarnessStart,
    )
  : "";
if (!containsInOrder(trustedClockHarnessMain, [
  "try verifySameBootRelaunch()",
  "try verifyRebootFailsClosed()",
  "try verifyUptimeRollbackFailsClosed()",
  "try verifyMalformedPersistenceFailsClosed()",
  "try verifyInvalidationPreventsReuse()",
  'print("Canonical route trusted-clock verification passed: 5 cases")',
])) {
  failures.push("canonical route trusted-clock source harness main no longer executes all five cases before reporting success");
}
requireText(relative.appRadioSilenceLeaseState, [
  "enum AppRadioSilenceTransportError",
  "struct AppRadioSilenceLease",
  "struct AppRadioSilenceLeaseState",
  "case firstLease",
  "case nestedLease",
  "case unknownLease",
  "case stillEnforced",
  "case finalLeaseReleased",
  "private var leases: Set<AppRadioSilenceLease>",
  "struct AppRadioSilencePhoneMirrorState",
  "enum AppRadioSilencePhoneMirrorPersistence",
  "restoreForProcessRestart",
]);
requireText(relative.appRadioSilenceCoordinator, [
  "final class AppRadioSilenceCoordinator",
  "static let shared = AppRadioSilenceCoordinator()",
  "case offlineRoadJourney",
  "case offlineMapLibrary",
  "This policy does",
  "not and cannot disable OS-managed radios or APNs delivery",
  "static let eusoAppRadioSilenceWillEngage",
  "static let eusoAppRadioSilenceDidRelease",
]);
requireText(relative.appRadioSilenceSharedState, [
  "group.com.app.eusotrip",
  "EUSOTRIP_APP_RADIO_SILENCE_V1:ENFORCED",
  "EUSOTRIP_APP_RADIO_SILENCE_V1:RELEASED",
  "static var isEnforced: Bool",
  "static func prepareMainAppLaunch() -> Bool",
  "static func setEnforced(_ enforced: Bool) -> Bool",
  "options: .atomic",
]);
requireText(relative.appRadioSilenceLeaseTests, [
  "APP_RADIO_SILENCE_SOURCE_VERIFICATION",
  "testFirstAndNestedLeasesRequireFinalRelease",
  "testDuplicateAndForeignReleaseAreIdempotent",
  "AppRadioSilenceLeaseStateSourceVerification",
]);
const appRadioSilenceLeaseTestSource = exists(relative.appRadioSilenceLeaseTests)
  ? read(relative.appRadioSilenceLeaseTests)
  : "";
const appRadioSilenceHarnessStart = swiftCodeOnly(appRadioSilenceLeaseTestSource).indexOf("@main");
const appRadioSilenceHarnessMain = appRadioSilenceHarnessStart >= 0
  ? swiftDeclarationOriginalBody(
      appRadioSilenceLeaseTestSource,
      /\bstatic\s+func\s+main\s*\(\s*\)\s*\{/,
      appRadioSilenceHarnessStart,
    )
  : "";
const compactAppRadioSilenceHarnessMain = appRadioSilenceHarnessMain.replace(/\s+/g, "");
if (!containsInOrder(compactAppRadioSilenceHarnessMain, [
  "AppRadioSilenceLeaseState()",
  "precondition(!state.isEnforced)",
  "letfirst=state.acquire()",
  "precondition(first.transition==.firstLease)",
  "letnested=state.acquire()",
  "precondition(nested.transition==.nestedLease)",
  "precondition(first.lease!=nested.lease)",
  "precondition(state.activeLeaseCount==2)",
  "precondition(state.release(AppRadioSilenceLease())==.unknownLease)",
  "precondition(state.release(first.lease)==.stillEnforced)",
  "precondition(state.release(first.lease)==.unknownLease)",
  "precondition(state.release(nested.lease)==.finalLeaseReleased)",
  "precondition(!state.isEnforced)",
  "AppRadioSilencePhoneMirrorState(",
  "AppRadioSilencePhoneMirrorPersistence.encode(priorPhoneState)",
  "restoreForProcessRestart(",
  "sharedStateIsEnforced:false",
  "precondition(!restartedPhoneState.isEnforced)",
  "precondition(restartedPhoneState.revision==8)",
  "precondition(restartedPhoneState.epoch==\"phone-install\")",
  "snapshotData:Data(\"corrupt\".utf8)",
  "sharedStateIsEnforced:true",
  "precondition(recoveredPhoneState.isEnforced)",
  "precondition(recoveredPhoneState.revision==0)",
  "precondition(recoveredPhoneState.epoch==\"replacement-epoch\")",
])) {
  failures.push("app radio-silence source harness main no longer exercises lease ownership and atomic phone-mirror restart/corruption semantics before completion");
}
const appRadioSilenceLeaseTestCode = swiftCodeOnly(appRadioSilenceLeaseTestSource);
const compactAppRadioSilenceLeaseTestBody = testName => swiftDeclarationOriginalBody(
  appRadioSilenceLeaseTestSource,
  new RegExp(`\\bfunc\\s+${testName}\\s*\\(\\s*\\)(?:\\s+throws)?\\s*\\{`),
).replace(/\s+/g, "");
if (!containsInOrder(
  compactAppRadioSilenceLeaseTestBody("testFirstAndNestedLeasesRequireFinalRelease"),
  [
    "letfirst=state.acquire()",
    "XCTAssertEqual(first.transition,.firstLease)",
    "letnested=state.acquire()",
    "XCTAssertEqual(nested.transition,.nestedLease)",
    "XCTAssertEqual(state.release(first.lease),.stillEnforced)",
    "XCTAssertEqual(state.release(nested.lease),.finalLeaseReleased)",
    "XCTAssertFalse(state.isEnforced)",
  ],
) || !containsInOrder(
  compactAppRadioSilenceLeaseTestBody("testDuplicateAndForeignReleaseAreIdempotent"),
  [
    "letowned=state.acquire().lease",
    "XCTAssertEqual(state.release(AppRadioSilenceLease()),.unknownLease)",
    "XCTAssertEqual(state.release(owned),.finalLeaseReleased)",
    "XCTAssertEqual(state.release(owned),.unknownLease)",
    "XCTAssertEqual(state.activeLeaseCount,0)",
  ],
)) {
  failures.push(`${relative.appRadioSilenceLeaseTests}: XCTest bodies no longer assert reference-counted and idempotent lease ownership`);
}
for (const [testName, requiredOperations] of [
  [
    "testPhoneRestartPublishesStrictlyNewerSharedMarkerState",
    [
      "forpreviousEnforcedin[false,true]",
      "forsharedStateIsEnforcedin[false,true]",
      "AppRadioSilencePhoneMirrorPersistence.encode(previous)",
      "restoreForProcessRestart(",
      "XCTAssertEqual(restarted.isEnforced,sharedStateIsEnforced)",
      "XCTAssertEqual(restarted.revision,8)",
      "XCTAssertEqual(restarted.epoch,\"phone-install\")",
    ],
  ],
  [
    "testCorruptPhoneSnapshotStartsFreshFailClosedEpoch",
    [
      "snapshotData:Data(\"corrupt\".utf8)",
      "legacy:.init(",
      "sharedStateIsEnforced:true",
      "XCTAssertTrue(restarted.isEnforced)",
      "XCTAssertEqual(restarted.revision,0)",
      "XCTAssertEqual(restarted.epoch,\"replacement-epoch\")",
    ],
  ],
  [
    "testCompletePhoneLegacyTupleMigratesThenAdvances",
    [
      "snapshotData:nil",
      "legacy:.init(",
      "sharedStateIsEnforced:false",
      "XCTAssertFalse(restarted.isEnforced)",
      "XCTAssertEqual(restarted.revision,6)",
      "XCTAssertEqual(restarted.epoch,\"legacy-phone\")",
    ],
  ],
]) {
  if (!containsInOrder(compactAppRadioSilenceLeaseTestBody(testName), requiredOperations)) {
    failures.push(`${relative.appRadioSilenceLeaseTests}: ${testName} no longer proves atomic phone-mirror restart authority`);
  }
}
const appRadioSilenceCoordinatorCode = exists(relative.appRadioSilenceCoordinator)
  ? compiledSwiftCodeOnly(read(relative.appRadioSilenceCoordinator))
  : "";
const appRadioSilenceSharedStateCode = exists(relative.appRadioSilenceSharedState)
  ? compiledSwiftCodeOnly(read(relative.appRadioSilenceSharedState))
  : "";
const appRadioSilenceAcquireCode = swiftDeclarationBody(
  appRadioSilenceCoordinatorCode,
  /\bfunc\s+acquire\s*\(\s*reason:\s*Reason\s*\)\s*->\s*AppRadioSilenceLease\s*\{/,
);
const appRadioSilenceReleaseCode = swiftDeclarationBody(
  appRadioSilenceCoordinatorCode,
  /\bfunc\s+release\s*\(\s*_\s+lease:\s*AppRadioSilenceLease\s*\)\s*\{/,
);
const appRadioSilenceRecoveryCode = swiftDeclarationBody(
  appRadioSilenceCoordinatorCode,
  /\bfunc\s+recoverSharedStateOnFirstForegroundActivation\s*\(\s*\)\s*->\s*Bool\s*\{/,
);
const sharedRadioSilenceReadCode = swiftDeclarationBody(
  appRadioSilenceSharedStateCode,
  /\bstatic\s+var\s+isEnforced\s*:\s*Bool\s*\{/,
);
const sharedRadioSilenceWriteCode = swiftDeclarationBody(
  appRadioSilenceSharedStateCode,
  /\bstatic\s+func\s+setEnforced\s*\(\s*_\s+enforced:\s*Bool\s*\)\s*->\s*Bool\s*\{/,
);
if (!containsInOrder(sharedRadioSilenceReadCode, [
  "guard let url = stateFileURL",
  "let payload = try? Data(contentsOf: url)",
  "return true",
  "if payload == releasedPayload { return false }",
  "return true",
]) || !containsInOrder(sharedRadioSilenceWriteCode, [
  "guard let url = stateFileURL else { return false }",
  "let payload = enforced ? enforcedPayload : releasedPayload",
  "try payload.write(to: url, options: .atomic)",
  "if enforced",
  "try? FileManager.default.removeItem(at: url)",
  "return isEnforced == enforced",
])) {
  failures.push("app-group radio-silence marker no longer persists atomic fixed envelopes and fails closed when missing, corrupt, or unwritable");
}
if (!containsInOrder(appRadioSilenceAcquireCode, [
  "state.acquire()",
  "AppRadioSilenceSharedState.setEnforced(true)",
  "if !sharedEnforcementSucceeded",
  "AppRadioSilenceSharedState.setEnforced(true)",
  "if result.transition != .firstLease",
  "isEnforced = sharedEnforcementSucceeded",
  "return result.lease",
  "isEnforced = sharedEnforcementSucceeded",
  "EusoTripAPI.shared.setAppRadioSilenceEnforced(true)",
  "WatchAuthBridge.shared.setAppRadioSilenceEnforced(true)",
  "OfflineQueue.shared.suspendForAppRadioSilence()",
  "RealtimeService.shared.suspendForAppRadioSilence()",
  "DriverGPSPushService.shared.suspendForAppRadioSilence()",
  "HOSClockService.shared.suspendForAppRadioSilence()",
  "ReminderSyncService.shared.suspendForAppRadioSilence()",
  "GeofenceService.shared.suspendForAppRadioSilence()",
  "WeatherService.shared.suspendForAppRadioSilence()",
  "NewsOGImageCache.shared.suspendForAppRadioSilence()",
  "PTChannelManager.shared.suspendForAppRadioSilence()",
  "AppRadioSilenceDirectTransportController.shared.suspendAll()",
  "NotificationCenter.default.post(name: .eusoAppRadioSilenceWillEngage, object: nil)",
  "return result.lease",
])) {
  failures.push("app radio-silence acquisition no longer retries durable ENFORCED propagation on every lease, withholds readiness on failure, and closes all in-process transports on the first lease");
}
if (!containsInOrder(appRadioSilenceReleaseCode, [
  "state.release(lease) == .finalLeaseReleased",
  "guard AppRadioSilenceSharedState.setEnforced(false) else",
  "isEnforced = true",
  "EusoTripAPI.shared.setAppRadioSilenceEnforced(true)",
  "WatchAuthBridge.shared.setAppRadioSilenceEnforced(true)",
  "return",
  "isEnforced = false",
  "EusoTripAPI.shared.setAppRadioSilenceEnforced(false)",
  "WatchAuthBridge.shared.setAppRadioSilenceEnforced(false)",
  "GeofenceService.shared.resumeAfterAppRadioSilence()",
  "DriverGPSPushService.shared.resumeAfterAppRadioSilence()",
  "RealtimeService.shared.resumeAfterAppRadioSilence()",
  "HOSClockService.shared.resumeAfterAppRadioSilence()",
  "ReminderSyncService.shared.resumeAfterAppRadioSilence()",
  "OfflineQueue.shared.resumeAfterAppRadioSilence()",
  "WeatherService.shared.resumeAfterAppRadioSilence()",
  "NewsOGImageCache.shared.resumeAfterAppRadioSilence()",
  "PTChannelManager.shared.resumeAfterAppRadioSilence()",
  "AppRadioSilenceDirectTransportController.shared.resumeAll()",
  "NotificationCenter.default.post(name: .eusoAppRadioSilenceDidRelease, object: nil)",
])) {
  failures.push("app radio-silence release no longer waits for a durable RELEASE marker before reopening every transport after the final valid lease");
}
if (!containsInOrder(appRadioSilenceRecoveryCode, [
  "guard state.activeLeaseCount == 0 else { return false }",
  "guard AppRadioSilenceSharedState.prepareMainAppLaunch() else",
  "isEnforced = true",
  "EusoTripAPI.shared.setAppRadioSilenceEnforced(true)",
  "AppRadioSilenceDirectTransportController.shared.suspendAll()",
  "return false",
  "isEnforced = false",
  "EusoTripAPI.shared.setAppRadioSilenceEnforced(false)",
  "RealtimeService.shared.resumeAfterFirstForegroundRadioSilenceRelease()",
  "AppRadioSilenceDirectTransportController.shared.resumeAll()",
  "return true",
])) {
  failures.push("cold-process radio-silence recovery no longer preserves ENFORCED on failure and releases only after a lease-free durable foreground transition");
}

requireText(relative.watchRadioSilenceState, [
  "struct AppRadioSilenceWatchState",
  "struct AppRadioSilenceWatchLegacyState",
  "enum AppRadioSilenceWatchPersistence",
  "retiredEpochs",
  "case stale",
  "case engaged",
  "case released",
]);
requireText(relative.watchRadioSilenceTests, [
  "APP_RADIO_SILENCE_WATCH_SOURCE_VERIFICATION",
  "AppRadioSilenceWatchStateSourceVerification",
  "testAtomicSnapshotRoundTripsTrustedState",
  "testCorruptSnapshotFailsClosedWithoutLegacyFallback",
]);
const watchRadioSilenceStateCode = exists(relative.watchRadioSilenceState)
  ? compiledSwiftCodeOnly(read(relative.watchRadioSilenceState))
  : "";
const watchRadioSilenceApplyCode = swiftDeclarationBody(
  watchRadioSilenceStateCode,
  /\bmutating\s+func\s+apply[\s\S]*?\)\s*->\s*Transition\s*\{/,
);
const watchRadioSilenceRestoreCode = swiftDeclarationBody(
  watchRadioSilenceStateCode,
  /\bstatic\s+func\s+restore[\s\S]*?\)\s*->\s*AppRadioSilenceWatchState\s*\{/,
);
if (!containsInOrder(watchRadioSilenceApplyCode, [
  "guard !nextEpoch.isEmpty, nextRevision >= 0 else { return .stale }",
  "if nextEpoch != epoch",
  "guard !retiredEpochs.contains(nextEpoch) else { return .stale }",
  "if let epoch { retiredEpochs.insert(epoch) }",
  "epoch = nextEpoch",
  "revision = nextRevision",
  "guard enforced != isEnforced else { return .unchanged }",
  "isEnforced = enforced",
  "guard nextRevision >= revision else { return .stale }",
  "return enforced == isEnforced ? .unchanged : .stale",
  "revision = nextRevision",
  "isEnforced = enforced",
]) || !containsInOrder(watchRadioSilenceRestoreCode, [
  "if let snapshotData",
  "JSONDecoder().decode(",
  "snapshot.version == currentVersion",
  "return AppRadioSilenceWatchState()",
  "guard legacy.hasAnyValue else { return AppRadioSilenceWatchState() }",
  "guard let isEnforced = legacy.isEnforced",
  "return AppRadioSilenceWatchState()",
])) {
  failures.push("watch radio-silence envelope no longer rejects stale/retired epochs and restores missing, corrupt, or partial persisted state fail closed");
}
const watchRadioSilenceTestSource = exists(relative.watchRadioSilenceTests)
  ? read(relative.watchRadioSilenceTests)
  : "";
const watchRadioSilenceHarnessStart = swiftCodeOnly(watchRadioSilenceTestSource).indexOf("@main");
const watchRadioSilenceHarnessMain = watchRadioSilenceHarnessStart >= 0
  ? swiftDeclarationOriginalBody(
      watchRadioSilenceTestSource,
      /\bstatic\s+func\s+main\s*\(\s*\)\s*\{/,
      watchRadioSilenceHarnessStart,
    )
  : "";
const compactWatchRadioSilenceHarnessMain = watchRadioSilenceHarnessMain.replace(/\s+/g, "");
if (!containsInOrder(compactWatchRadioSilenceHarnessMain, [
  "AppRadioSilenceWatchState()",
  "precondition(state.isEnforced)",
  "revision:0,epoch:\"install-a\")==.released",
  "revision:1,epoch:\"install-a\")==.engaged",
  "revision:0,epoch:\"install-a\")==.stale",
  "revision:1,epoch:\"install-a\")==.stale",
  "revision:2,epoch:\"install-a\")==.released",
  "revision:1,epoch:\"install-b\")==.engaged",
  "revision:99,epoch:\"install-a\")==.stale",
  "AppRadioSilenceWatchPersistence.encode(state)",
  "restore(snapshotData:encoded)==state",
  "snapshotData:Data(\"corrupt\".utf8)",
  "precondition(corrupt.isEnforced)",
  "snapshotData:nil",
  "precondition(partial.isEnforced)",
])) {
  failures.push("watch radio-silence source harness main no longer exercises ordering, retired epochs, atomic round-trip, corrupt-state, and partial-legacy fail-closed behavior");
}
const compactWatchRadioSilenceTestBody = testName => swiftDeclarationOriginalBody(
  watchRadioSilenceTestSource,
  new RegExp(`\\bfunc\\s+${testName}\\s*\\(\\s*\\)(?:\\s+throws)?\\s*\\{`),
).replace(/\s+/g, "");
for (const [testName, requiredOperations] of [
  ["testNewerEdgesEngageAndRelease", ["state.apply(", "XCTAssertFalse(state.isEnforced)", "XCTAssertTrue(state.isEnforced)"]],
  ["testStaleOrConflictingEdgesCannotReopenPolicy", ["revision:7", ".stale", "revision:8", "XCTAssertTrue(state.isEnforced)"]],
  ["testNewInstallEpochReplacesOldButRetiredEpochCannotReturn", ["epoch:\"install-b\"", ".released", "epoch:\"install-a\"", ".stale"]],
  ["testAtomicSnapshotRoundTripsTrustedState", ["AppRadioSilenceWatchPersistence.encode(state)", "AppRadioSilenceWatchPersistence.restore(snapshotData:data)", "state"]],
  ["testCorruptSnapshotFailsClosedWithoutLegacyFallback", ["Data(\"corrupt\".utf8)", "legacy:legacy", "XCTAssertTrue(restored.isEnforced)", "XCTAssertNil(restored.epoch)"]],
  ["testPartialLegacyStateFailsClosed", ["snapshotData:nil", "revision:nil", "XCTAssertTrue(restored.isEnforced)"]],
  ["testCompleteLegacyStateMigrates", ["snapshotData:nil", "revision:8", "XCTAssertFalse(restored.isEnforced)", "Set([\"retired\"])"]],
]) {
  if (!containsInOrder(compactWatchRadioSilenceTestBody(testName), requiredOperations)) {
    failures.push(`${relative.watchRadioSilenceTests}: ${testName} no longer contains meaningful watch-envelope operations and assertions`);
  }
}

const finiteCallbackWatchdogSource = exists(relative.finiteCallbackWatchdog)
  ? read(relative.finiteCallbackWatchdog)
  : "";
const finiteCallbackWatchdogCode = swiftCodeOnly(finiteCallbackWatchdogSource);
const finiteCallbackWaitCode = swiftDeclarationBody(
  finiteCallbackWatchdogCode,
  /\bfunc\s+wait[\s\S]*?\)\s*async\s+throws\s*->\s*Value\s*\{/,
);
const finiteCallbackInstallCode = swiftDeclarationBody(
  finiteCallbackWatchdogCode,
  /\bprivate\s+func\s+install[\s\S]*?\)\s*\{/,
);
const finiteCallbackHeartbeatCode = swiftDeclarationBody(
  finiteCallbackWatchdogCode,
  /\bfunc\s+heartbeat\s*\(\s*\)\s*\{/,
);
const finiteCallbackSuspendCode = swiftDeclarationBody(
  finiteCallbackWatchdogCode,
  /\bfunc\s+suspendTimeout\s*\(\s*\)\s*\{/,
);
const finiteCallbackResumeCode = swiftDeclarationBody(
  finiteCallbackWatchdogCode,
  /\bfunc\s+resumeTimeout\s*\(\s*\)\s*\{/,
);
const finiteCallbackArmCode = swiftDeclarationBody(
  finiteCallbackWatchdogCode,
  /\bprivate\s+func\s+armTimeoutLocked\s*\(\s*\)\s*\{/,
);
const finiteCallbackFinishCode = swiftDeclarationBody(
  finiteCallbackWatchdogCode,
  /\bprivate\s+func\s+finish[\s\S]*?\)\s*->\s*Bool\s*\{/,
);
if (!containsInOrder(finiteCallbackWaitCode, [
  "if !timeoutIsValid",
  "finish(",
  "interruptNativeOperation: true",
  "withTaskCancellationHandler",
  "withCheckedThrowingContinuation",
  "install(",
  "taskAlreadyCancelled: Task.isCancelled",
  "onCancel:",
  "self?.interrupt()",
]) || !containsInOrder(finiteCallbackInstallCode, [
  "lock.lock()",
  "guard !waiterInstalled else",
  "continuation.resume(",
  "HereFiniteCallbackWatchdogMisuse.waiterAlreadyInstalled",
  "waiterInstalled = true",
  "if let terminalResult",
  "lock.unlock()",
  "action?()",
  "continuation.resume(with: terminalResult)",
  "self.continuation = continuation",
  "self.interruptionAction = interruptionAction",
  "armTimeoutLocked()",
  "lock.unlock()",
  "if taskAlreadyCancelled",
  "interrupt()",
]) || !containsInOrder(finiteCallbackArmCode, [
  "timeoutWorkItem?.cancel()",
  "let generation = UUID()",
  "self?.expire(generation: generation)",
  "timeoutGeneration = generation",
  "timeoutQueue.asyncAfter(",
]) || !containsInOrder(finiteCallbackFinishCode, [
  "lock.lock()",
  "if let expectedTimeoutGeneration",
  "timeoutGeneration != expectedTimeoutGeneration",
  "return false",
  "guard terminalResult == nil else",
  "return false",
  "terminalResult = result",
  "let continuation = continuation",
  "self.continuation = nil",
  "let workItem = timeoutWorkItem",
  "timeoutWorkItem = nil",
  "timeoutGeneration = nil",
  "interruptionAction = nil",
  "lock.unlock()",
  "workItem?.cancel()",
  "action?()",
  "continuation?.resume(with: result)",
  "return true",
])) {
  failures.push("HERE finite callback watchdog no longer guarantees a bounded, cancellation-aware, exactly-once terminal result with harmless late callbacks");
}
if (!containsInOrder(finiteCallbackHeartbeatCode, [
  "lock.lock()",
  "guard waiterInstalled",
  "terminalResult == nil",
  "!timeoutSuspended else",
  "armTimeoutLocked()",
  "lock.unlock()",
]) || !containsInOrder(finiteCallbackSuspendCode, [
  "lock.lock()",
  "timeoutSuspended = true",
  "let workItem = timeoutWorkItem",
  "timeoutWorkItem = nil",
  "timeoutGeneration = nil",
  "lock.unlock()",
  "workItem?.cancel()",
]) || !containsInOrder(finiteCallbackResumeCode, [
  "lock.lock()",
  "guard timeoutSuspended else",
  "timeoutSuspended = false",
  "if waiterInstalled, terminalResult == nil",
  "armTimeoutLocked()",
  "lock.unlock()",
])) {
  failures.push("HERE finite callback watchdog no longer extends transfer inactivity on progress or suspends and safely rearms timeouts across intentional pauses");
}

const finiteCallbackWatchdogTestSource = exists(relative.finiteCallbackWatchdogTests)
  ? swiftCodeOnly(read(relative.finiteCallbackWatchdogTests))
  : "";
const compactCallbackTestBody = testName => swiftDeclarationBody(
  finiteCallbackWatchdogTestSource,
  new RegExp(`\\bfunc\\s+${testName}\\s*\\(\\s*\\)[^{]*\\{`),
).replace(/\s+/g, "");
const callbackTestContracts = [
  ["testFirstNativeResultWinsAndLateResultIsIgnored", [
    "XCTAssertTrue(watchdog.succeed(41))",
    "XCTAssertFalse(watchdog.succeed(99))",
    "tryawaitwatchdog.wait()",
    "XCTAssertEqual(value,41)",
  ]],
  ["testTimeoutInterruptsNativeOperationAndRejectsLateCallback", [
    "tryawaitwatchdog.wait",
    "interrupted.fulfill()",
    "XCTAssertEqual(erroras?TimeoutFailure,TimeoutFailure())",
    "awaitfulfillment(of:[interrupted],timeout:1)",
    "XCTAssertFalse(watchdog.succeed(7))",
  ]],
  ["testTaskCancellationInterruptsNativeOperationExactlyOnce", [
    "tryawaitwatchdog.wait",
    "task.cancel()",
    "XCTAssertTrue(errorisCancellationError)",
    "awaitfulfillment(of:[interrupted],timeout:1)",
    "XCTAssertFalse(watchdog.fail(TimeoutFailure()))",
  ]],
  ["testInterruptionBeforeWaitStillCancelsNativeOperationExactlyOnce", [
    "XCTAssertTrue(watchdog.interrupt())",
    "tryawaitwatchdog.wait",
    "XCTAssertTrue(errorisCancellationError)",
    "XCTAssertFalse(watchdog.interrupt())",
  ]],
  ["testSuspendedTimeoutDoesNotExpireUntilResumed", [
    "watchdog.suspendTimeout()",
    "Task.sleep",
    "watchdog.resumeTimeout()",
    "XCTAssertTrue(watchdog.succeed(12))",
    "XCTAssertEqual(value,12)",
  ]],
  ["testHeartbeatExtendsInactivityDeadline", [
    "Task.sleep",
    "watchdog.heartbeat()",
    "Task.sleep",
    "XCTAssertTrue(watchdog.succeed(23))",
    "XCTAssertEqual(value,23)",
  ]],
];
for (const [testName, steps] of callbackTestContracts) {
  if (!containsInOrder(compactCallbackTestBody(testName), steps)) {
    failures.push(`${relative.finiteCallbackWatchdogTests}: ${testName} no longer proves its finite callback boundary with meaningful operations and assertions`);
  }
}

const navigationInterruptionTestSource = exists(relative.navigationInterruptionTests)
  ? swiftCodeOnly(read(relative.navigationInterruptionTests))
  : "";
const compactInterruptionTestBody = testName => swiftDeclarationBody(
  navigationInterruptionTestSource,
  new RegExp(`\\bfunc\\s+${testName}\\s*\\(\\s*\\)[^{]*\\{`),
).replace(/\s+/g, "");
const interruptionTestContracts = [
  ["testInterruptionMutesOnceAndRequiresSystemResumePlusFreshLocation", [
    "boundary.receive(.began,sessionIsActive:true)",
    ".pauseAndMute",
    "XCTAssertTrue(boundary.blocksNativeCallbacks)",
    "boundary.receive(.ended(shouldResume:true)",
    ".prepareAudioAndAwaitFreshLocation",
    "XCTAssertFalse(boundary.acceptFreshLocation(",
    "XCTAssertTrue(boundary.acceptFreshLocation(observedAt:restoredAt))",
    "XCTAssertFalse(boundary.blocksNativeCallbacks)",
  ]],
  ["testSystemDeniedResumeRemainsPaused", [
    "boundary.receive(.began,sessionIsActive:true)",
    "boundary.receive(.ended(shouldResume:false),sessionIsActive:true)",
    ".remainPaused",
    "XCTAssertTrue(boundary.blocksNativeCallbacks)",
    "XCTAssertFalse(boundary.acceptFreshLocation(observedAt:Date()))",
  ]],
  ["testFailedAudioPreparationCannotBeClearedByLocation", [
    "boundary.receive(.ended(shouldResume:true),sessionIsActive:true)",
    "boundary.rejectResume()",
    "XCTAssertTrue(boundary.blocksNativeCallbacks)",
    "XCTAssertFalse(boundary.acceptFreshLocation(observedAt:Date()))",
  ]],
  ["testInactiveSessionClearsStaleInterruptionState", [
    "boundary.receive(.began,sessionIsActive:true)",
    "boundary.receive(.ended(shouldResume:true),sessionIsActive:false)",
    ".none",
    "XCTAssertFalse(boundary.blocksNativeCallbacks)",
  ]],
];
for (const [testName, steps] of interruptionTestContracts) {
  if (!containsInOrder(compactInterruptionTestBody(testName), steps)) {
    failures.push(`${relative.navigationInterruptionTests}: ${testName} no longer proves the audio interruption boundary with meaningful operations and assertions`);
  }
}
requireText(relative.coverageResolver, [
  "import Security",
  "actor SignedInstalledCoverageResolver",
  "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly",
  "kern.bootsessionuuid",
  "SignedCoverageTrustedAnchorPersistence",
  "case bootSessionChanged",
  "case monotonicUptimeRegressed",
  "signedServerTime: verified.payload.issuedAt",
  "func resolveInstalledCoverage",
  "coordinateClassifications",
  "payload.catalogVersion",
  "options: .atomic",
]);
requireText(relative.coverageResolverTests, [
  "SIGNED_COVERAGE_SOURCE_VERIFICATION",
  "Signed installed-coverage trusted-time verification passed: 5 cases",
  "verifySameBootRelaunch",
  "verifyRebootFailsClosed",
  "verifyUptimeRollbackFailsClosed",
  "verifyAnchorTamperFailsClosed",
  "verifyExpiryCannotBeRevivedByWallClockRollback",
]);
const coverageResolverTestSource = exists(relative.coverageResolverTests)
  ? read(relative.coverageResolverTests)
  : "";
const coverageClockHarnessStart = swiftCodeOnly(coverageResolverTestSource).indexOf("@main");
const coverageClockHarnessMain = coverageClockHarnessStart >= 0
  ? swiftDeclarationOriginalBody(
      coverageResolverTestSource,
      /\bstatic\s+func\s+main\s*\(\s*\)\s*async\s+throws\s*\{/,
      coverageClockHarnessStart,
    )
  : "";
if (!containsInOrder(coverageClockHarnessMain, [
  "try await verifySameBootRelaunch()",
  "try await verifyRebootFailsClosed()",
  "try await verifyUptimeRollbackFailsClosed()",
  "try await verifyAnchorTamperFailsClosed()",
  "try await verifyExpiryCannotBeRevivedByWallClockRollback()",
  'print("Signed installed-coverage trusted-time verification passed: 5 cases")',
])) {
  failures.push("signed installed-coverage trusted-time source harness main no longer executes all five cases before reporting success");
}
requireText(relative.coverageAdapter, [
  "releaseApprovedSDKVersion = \"4.27.2.0\"",
  "HereNavigateInstalledCoverageAuthority",
  "requireCompleteEvidence",
  "initialSignedManifest",
]);
denyText(relative.coverageAdapter, [
  "expectedSDKVersion = \"latest\"",
]);
requireText(relative.locationSource, [
  "kCLLocationAccuracyBestForNavigation",
  "kCLDistanceFilterNone",
  "accuracyAuthorization == .fullAccuracy",
  "startUpdatingLocation()",
  "stopUpdatingLocation()",
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
requireText(relative.finiteCallbackWatchdog, [
  "final class HereFiniteCallbackWatchdog",
  "withTaskCancellationHandler",
  "withCheckedThrowingContinuation",
  "func heartbeat()",
  "func suspendTimeout()",
  "func resumeTimeout()",
  "case waiterAlreadyInstalled",
]);
requireText(relative.finiteCallbackWatchdogTests, [
  "testFirstNativeResultWinsAndLateResultIsIgnored",
  "testTimeoutInterruptsNativeOperationAndRejectsLateCallback",
  "testTaskCancellationInterruptsNativeOperationExactlyOnce",
  "testInterruptionBeforeWaitStillCancelsNativeOperationExactlyOnce",
  "testInvalidTimeoutFailsClosedAndInterruptsNativeOperation",
  "testSuspendedTimeoutDoesNotExpireUntilResumed",
  "testHeartbeatExtendsInactivityDeadline",
]);
requireText(relative.navigationInterruptionTests, [
  "testInterruptionMutesOnceAndRequiresSystemResumePlusFreshLocation",
  "testSystemDeniedResumeRemainsPaused",
  "testFailedAudioPreparationCannotBeClearedByLocation",
  "testInactiveSessionClearsStaleInterruptionState",
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
  "HereOfflineMapJourneyProjection",
  "CanonicalRoutePackage",
  "serverCanonical",
  "MapPolyline",
  "LocationIndicator",
]);
requireText(relative.onlineMapWebView, [
  "static func dismantleUIView",
  "webView.stopLoading()",
  "removeAllScriptMessageHandlers()",
  "coordinator.webView = nil",
]);
requireText(relative.productionComposition, [
  "struct OfflineMapSurfaceLeaseState",
  "mapSurfaceLeaseState.reserve(for: ownerToken)",
  "mapSurfaceSnapshotRevision",
  "mapSurfaceLeaseState.forceRelease()",
  "publishMapSurfaceLeaseRevision()",
  "currentNavigationManeuver = maneuver",
  "lastNavigationDeviation = deviation",
  "snapshot.radioSilenceState == .enforced",
  "snapshot.installedRegions.contains(where: { $0.state.isUsableCoverage })",
  "snapshot.availableCapabilities.contains(.detailedRendering)",
  "mapSurface.setJourneyRoute(route)",
  "mapSurface.updateLivePosition(",
]);
requireText(relative.mapLibraryView, [
  "OfflineNativeCoverageMapSurfaceHost",
  "OfflineRoadJourneyView(composition: productionComposition)",
  "ForEach(HereOfflineMapSurfaceMode.allCases",
  "ForEach(HereOfflineMapSurfaceFamily.allCases",
  "composition.installedCoverageTrustAvailable",
  "offlineSnapshot.radioSilenceState == .enforced",
  "offlineSnapshot.availableCapabilities.contains(.detailedRendering)",
  "composition.prepareMapSurface(",
  "ownerToken: ownerToken",
  "composition.clearMapSurface(ownerToken: ownerToken)",
  "journeyProjection: HereOfflineMapJourneyProjection",
  "composition.setMapJourneyProjection(journeyProjection)",
  "AppRadioSilenceCoordinator.shared.acquire(",
  "reason: .offlineMapLibrary",
  "AppRadioSilenceCoordinator.shared.release(lease)",
]);
requireText(relative.canonicalItineraryView, [
  "package.mode == .rail || package.mode == .vessel",
  "OfflineNativeCoverageMapSurfaceHost(",
  "mode: package.mode == .rail ? .rail : .vessel",
  "family: .operational",
  "journeyProjection: .serverCanonical(package)",
]);
denyText(relative.canonicalItineraryView, [
  "AppRadioSilenceCoordinator",
  "AppRadioSilenceLease",
]);
requireText(relative.roadJourneyView, [
  "composition.searchOffline(",
  "composition.calculateOfflineRoute(",
  "composition.startNavigation(route:",
  "composition.stopNavigation()",
  "kCLLocationAccuracyBestForNavigation",
  "accuracyAuthorization == .fullAccuracy",
  "maximumAgeSeconds: TimeInterval = 15",
  "maximumHorizontalAccuracyMeters: CLLocationAccuracy = 65",
  "isSimulatedBySoftware == true",
  "truckDraft.constraints()",
  "OfflineTruckConstraints(",
  "route.sections",
  "route.notices",
  "composition.currentNavigationManeuver",
  "composition.lastNavigationDeviation",
  "OfflineNativeCoverageMapSurfaceHost(",
  "journeyProjection: journeyProjection",
]);
denyText(relative.roadJourneyView, [
  "URLSession",
  "EusoTripAPI.shared",
  "HereRoutingClient",
  "HereGeocodingClient",
  "MapKit",
  "MKMapView",
  "MKDirections",
  "MKLocalSearch",
  "CLGeocoder",
  "WKWebView",
  "HereVectorMapView",
  "HereMapWebView",
  "openURL",
]);
requireText(relative.driverEnRouteView, [
  "presentsOfflineRoadDesk = true",
  "if presentsOfflineRoadDesk",
  ".fullScreenCover(",
  "isPresented: $presentsOfflineRoadDesk",
  "OfflineRoadJourneyView(composition: composition)",
  "await OfflineMapProductionComposition.shared?",
  ".stopNavigation()",
  ".interactiveDismissDisabled()",
  "OfflineDriverTurnBanner(composition: composition)",
  "composition.currentNavigationManeuver",
  "composition.lastNavigationDeviation",
]);
requireText(relative.surfaceLeaseTests, [
  "testSecondWindowCannotEnterWhileFirstOwnsSurface",
  "testSameOwnerReservationIsIdempotentDuringLoading",
  "testReleaseHandsSurfaceToWaitingWindow",
  "testOpaqueFailureForceReleaseWakesWaiters",
]);
const surfaceLeaseTestCode = exists(relative.surfaceLeaseTests)
  ? swiftCodeOnly(read(relative.surfaceLeaseTests))
  : "";
const compactLeaseTestBody = testName => swiftDeclarationBody(
  surfaceLeaseTestCode,
  new RegExp(`\\bfunc\\s+${testName}\\s*\\(\\s*\\)\\s*\\{`),
).replace(/\s+/g, "");
const leaseTestExpectations = new Map([
  ["testSecondWindowCannotEnterWhileFirstOwnsSurface", [
    "OfflineMapSurfaceLeaseState()",
    "XCTAssertTrue(lease.reserve(for:first))",
    "XCTAssertEqual(lease.status(for:first),.ownedByCaller)",
    "XCTAssertEqual(lease.status(for:second),.ownedByAnotherSurface)",
    "XCTAssertFalse(lease.reserve(for:second))",
    "XCTAssertEqual(lease.revision,1)",
  ]],
  ["testSameOwnerReservationIsIdempotentDuringLoading", [
    "OfflineMapSurfaceLeaseState()",
    "XCTAssertTrue(lease.reserve(for:owner))",
    "XCTAssertTrue(lease.reserve(for:owner))",
    "XCTAssertEqual(lease.status(for:owner),.ownedByCaller)",
    "XCTAssertEqual(lease.revision,1)",
  ]],
  ["testReleaseHandsSurfaceToWaitingWindow", [
    "OfflineMapSurfaceLeaseState()",
    "XCTAssertTrue(lease.reserve(for:first))",
    "XCTAssertFalse(lease.release(for:second))",
    "XCTAssertTrue(lease.release(for:first))",
    "XCTAssertEqual(lease.status(for:second),.available)",
    "XCTAssertTrue(lease.reserve(for:second))",
    "XCTAssertEqual(lease.status(for:second),.ownedByCaller)",
    "XCTAssertEqual(lease.revision,3)",
  ]],
  ["testOpaqueFailureForceReleaseWakesWaiters", [
    "OfflineMapSurfaceLeaseState()",
    "XCTAssertTrue(lease.reserve(for:first))",
    "XCTAssertTrue(lease.forceRelease())",
    "XCTAssertEqual(lease.status(for:second),.available)",
    "XCTAssertEqual(lease.revision,2)",
    "XCTAssertFalse(lease.forceRelease())",
  ]],
]);
for (const [testName, expectations] of leaseTestExpectations) {
  if (!containsInOrder(compactLeaseTestBody(testName), expectations)) {
    failures.push(`${relative.surfaceLeaseTests}: ${testName} no longer exercises the lease transition with meaningful assertions`);
  }
}
requireText(relative.canonicalItineraryView, [
  "CanonicalRoutePackage",
  "Verified offline",
]);
requireText(relative.railRouteCaller, [
  "CanonicalRoutePlanClient().download",
  "subject: .railShipment",
  "composition.ingestCanonicalRoutePlan",
  "CanonicalRouteOfflineReader",
  "CanonicalOfflineRouteItineraryView",
]);
requireText(relative.vesselRouteCaller, [
  "CanonicalRoutePlanClient().download",
  "subject: .vesselShipment",
  "composition.ingestCanonicalRoutePlan",
  "CanonicalRouteOfflineReader",
  "CanonicalOfflineRouteItineraryView",
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

let coverageTrust;
if (exists(relative.coverageTrust)) {
  try {
    const parsedCoverageTrust = JSON.parse(read(relative.coverageTrust));
    assert.equal(parsedCoverageTrust.schemaVersion, 1);
    assert.ok(["awaiting_signed_catalog", "approved"].includes(parsedCoverageTrust.status));
    assert.equal(parsedCoverageTrust.expectedSDKVersion, "4.27.2.0");
    assert.equal(typeof parsedCoverageTrust.initialSignedManifestResource, "string");
    assert.equal(
      parsedCoverageTrust.initialSignedManifestResource,
      path.basename(parsedCoverageTrust.initialSignedManifestResource),
    );
    assert.match(parsedCoverageTrust.initialSignedManifestResource, /^[A-Za-z0-9._-]+\.json$/);
    assert.ok(
      Number.isFinite(parsedCoverageTrust.routeCorridorHalfWidthMeters) &&
      parsedCoverageTrust.routeCorridorHalfWidthMeters > 0 &&
      parsedCoverageTrust.routeCorridorHalfWidthMeters <= 5_000,
    );
    coverageTrust = parsedCoverageTrust;
  } catch (error) {
    coverageTrust = undefined;
    failures.push(`${relative.coverageTrust}: invalid installed-coverage trust document (${error.name})`);
  }
}

let approvedCoverageManifestRelative = null;
let approvedCoveragePayload = null;
if (coverageTrust?.status !== "approved") {
  blockers.push("signed installed-region coverage trust and catalog are not release-approved");
} else {
  const coveragePublicKey = canonicalBase64(coverageTrust.ed25519PublicKeyBase64, 32);
  const coverageApprovedAt = Date.parse(coverageTrust.approvedAt ?? "");
  const coverageApprovalIsComplete =
    typeof coverageTrust.issuer === "string" && coverageTrust.issuer.trim() !== "" &&
    typeof coverageTrust.audience === "string" && coverageTrust.audience.trim() !== "" &&
    typeof coverageTrust.expectedRightsHolder === "string" &&
      coverageTrust.expectedRightsHolder.trim() !== "" &&
    typeof coverageTrust.verificationKeyID === "string" &&
      coverageTrust.verificationKeyID.trim() !== "" &&
    Buffer.byteLength(coverageTrust.verificationKeyID.trim(), "utf8") <= 128 &&
    Buffer.isBuffer(coveragePublicKey) && coveragePublicKey.length === 32 &&
    typeof coverageTrust.approvedBy === "string" && coverageTrust.approvedBy.trim() !== "" &&
    Number.isFinite(coverageApprovedAt) && coverageApprovedAt <= Date.now() + 300_000;
  if (!coverageApprovalIsComplete) {
    blockers.push("signed installed-region coverage trust approval is incomplete or invalid");
  }
  approvedCoverageManifestRelative =
    `${relative.offlineRoot}/${coverageTrust.initialSignedManifestResource}`;
  const coverageManifestEntry = repositoryEntryStatus(
    approvedCoverageManifestRelative,
    "file",
    "approved signed installed-region coverage manifest",
  );
  if (coverageManifestEntry.status === "missing") {
    blockers.push("approved signed installed-region coverage manifest is absent");
  } else if (coverageManifestEntry.status === "ok") {
    if (!gitPathIsTrackedAndUnchanged(approvedCoverageManifestRelative)) {
      blockers.push("approved signed installed-region coverage manifest is not committed unchanged in HEAD");
    }
    try {
      const envelopeBytes = readRepositoryBytes(
        approvedCoverageManifestRelative,
        "approved signed installed-region coverage manifest",
      );
      assert.ok(envelopeBytes);
      approvedCoveragePayload = verifyApprovedCoverageEnvelope(envelopeBytes, coverageTrust);
    } catch {
      failures.push("approved signed installed-region coverage manifest failed Ed25519, pinned-claim, validity, or geometry verification");
    }
  }
}
if (coverageTrust && manifest &&
    coverageTrust.expectedSDKVersion !== manifest.approvedVersion) {
  failures.push("installed-coverage trust SDK version differs from the approved HERE SDK supply chain");
}

const projectSource = exists(relative.project) ? read(relative.project) : "";
const projectInspector = makeProjectInspector(projectSource, "EusoTrip");
const testProjectInspector = makeProjectInspector(projectSource, "EusoTripOfflineTests");
const watchProjectInspector = makeProjectInspector(projectSource, "EusoTrip Pulse Watch App");
const watchTestProjectInspector = makeProjectInspector(
  projectSource,
  "EusoTrip Pulse Watch AppTests",
);
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
for (const sourceFile of [
  relative.appRadioSilenceLeaseState,
  relative.appRadioSilenceCoordinator,
  relative.appRadioSilenceSharedState,
  relative.appRadioSilenceDirectTransport,
  relative.appRadioSilenceAsyncImage,
  relative.api,
  relative.walletAPI,
  relative.realtimeService,
  relative.driverGPSPushService,
  relative.hosClockService,
  relative.reminderSyncService,
  relative.offlineQueue,
  relative.geofenceService,
  relative.onlineMapWebView,
  relative.driverEnRouteView,
  relative.roadJourneyView,
  relative.pushService,
  relative.weatherService,
  relative.newsImageCache,
  relative.ptChannelManager,
  relative.watchAuthBridge,
  relative.phoneWatchBridge,
  relative.appAttestClient,
  relative.appleAuthProvider,
  relative.walletApplePayProvider,
  relative.walletPassService,
  relative.shipperAppIntents,
  relative.dockAssignedView,
]) {
  if (!projectInspector.sourceRegistered(sourceFile)) {
    failures.push(`${sourceFile}: app radio-silence source is not registered in the EusoTrip application target`);
  }
}
if (!watchProjectInspector.targetExists) {
  failures.push(`${relative.project}: EusoTrip Pulse Watch App target could not be structurally resolved`);
} else {
  for (const watchSourceFile of [
    relative.watchRadioSilenceState,
    relative.watchRadioSilencePolicy,
    relative.watchConnectivityManager,
    relative.watchAppEntry,
    relative.watchEsangClient,
    relative.watchOfflineQueue,
    relative.watchAudioRecorder,
  ]) {
    if (!watchProjectInspector.sourceRegistered(watchSourceFile)) {
      failures.push(`${watchSourceFile}: watch radio-silence source is not registered in the EusoTrip Pulse Watch App target`);
    }
  }
}
if (!watchTestProjectInspector.targetExists ||
    !watchTestProjectInspector.sourceRegistered(relative.watchRadioSilenceTests)) {
  failures.push(`${relative.watchRadioSilenceTests}: not registered in the EusoTrip Pulse Watch AppTests target`);
}
for (const testFile of [
  relative.appRadioSilenceLeaseTests,
  relative.finiteCallbackWatchdogTests,
  relative.navigationInterruptionTests,
]) {
  if (!testProjectInspector.sourceRegistered(testFile)) {
    failures.push(`${testFile}: not registered in the EusoTripOfflineTests target`);
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
if (!projectInspector.resourceRegistered(relative.coverageTrust)) {
  failures.push(`${relative.project}: installed-coverage trust document is not registered in the EusoTrip app resources`);
}
if (coverageTrust?.status === "approved") {
  if (approvedCoverageManifestRelative && exists(approvedCoverageManifestRelative) &&
      !projectInspector.resourceRegistered(approvedCoverageManifestRelative)) {
    blockers.push("approved signed installed-region coverage manifest is not registered in app resources");
  }
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
const sourceWorkflowExecutable = sourceWorkflowSource
  .split("\n")
  .filter(line => !line.trimStart().startsWith("#"))
  .join("\n");
const sourceWorkflowRunsTrustedClockBinary = containsInOrder(sourceWorkflowExecutable, [
  '-o "$trusted_clock_binary"',
  '"$trusted_clock_binary"',
]);
const sourceWorkflowRunsCoverageClockBinary = containsInOrder(sourceWorkflowExecutable, [
  '-o "$coverage_clock_binary"',
  '"$coverage_clock_binary"',
]);
const sourceWorkflowRunsAppRadioSilenceBinary = containsInOrder(sourceWorkflowExecutable, [
  '-o "$app_radio_silence_binary"',
  '"$app_radio_silence_binary"',
]);
const sourceWorkflowRunsWatchRadioSilenceBinary = containsInOrder(sourceWorkflowExecutable, [
  "swiftc -DAPP_RADIO_SILENCE_WATCH_SOURCE_VERIFICATION",
  '"EusoTrip Pulse Watch App/Services/AppRadioSilenceWatchState.swift"',
  '"EusoTrip Pulse Watch AppTests/AppRadioSilenceWatchStateTests.swift"',
  '-o "$watch_radio_silence_binary"',
  '"$watch_radio_silence_binary"',
]);
const sourceCIIsWired =
  sourceWorkflowSource.includes("name: HERE Offline Source Contract") &&
  sourceWorkflowSource.includes("verify-here-offline-contract.test.mjs") &&
  sourceWorkflowSource.includes("verify-here-offline-contract.mjs") &&
  sourceWorkflowSource.includes("verify-reachable-here-credential-history.test.mjs") &&
  sourceWorkflowSource.includes("verify-reachable-here-credential-history.mjs") &&
  sourceWorkflowSource.includes("verify-canonical-route-trusted-clock.swift") &&
  sourceWorkflowSource.includes("swiftc -swift-version 5 -parse-as-library") &&
  sourceWorkflowSource.includes("SIGNED_COVERAGE_SOURCE_VERIFICATION") &&
  sourceWorkflowSource.includes("SignedInstalledCoverageResolverTests.swift") &&
  sourceWorkflowSource.includes("APP_RADIO_SILENCE_SOURCE_VERIFICATION") &&
  sourceWorkflowSource.includes("AppRadioSilenceLeaseState.swift") &&
  sourceWorkflowSource.includes("AppRadioSilenceLeaseStateTests.swift") &&
  sourceWorkflowSource.includes("APP_RADIO_SILENCE_WATCH_SOURCE_VERIFICATION") &&
  sourceWorkflowSource.includes("AppRadioSilenceWatchState.swift") &&
  sourceWorkflowSource.includes("AppRadioSilenceWatchStateTests.swift") &&
  sourceWorkflowRunsTrustedClockBinary &&
  sourceWorkflowRunsCoverageClockBinary &&
  sourceWorkflowRunsAppRadioSilenceBinary &&
  sourceWorkflowRunsWatchRadioSilenceBinary &&
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
const deployRunsTrustedClockBinary = containsInOrder(deployExecutableSource, [
  '-o "$TRUSTED_CLOCK_VERIFY_BINARY"',
  '"$TRUSTED_CLOCK_VERIFY_BINARY"',
]);
const deployRunsCoverageClockBinary = containsInOrder(deployExecutableSource, [
  '-o "$COVERAGE_CLOCK_VERIFY_BINARY"',
  '"$COVERAGE_CLOCK_VERIFY_BINARY"',
]);
const deployRunsAppRadioSilenceBinary = containsInOrder(deployExecutableSource, [
  '-o "$APP_RADIO_SILENCE_VERIFY_BINARY"',
  '"$APP_RADIO_SILENCE_VERIFY_BINARY"',
]);
const deployRunsWatchRadioSilenceBinary = containsInOrder(deployExecutableSource, [
  "swiftc -DAPP_RADIO_SILENCE_WATCH_SOURCE_VERIFICATION",
  '"${PROJECT_ROOT}/EusoTrip Pulse Watch App/Services/AppRadioSilenceWatchState.swift"',
  '"${PROJECT_ROOT}/EusoTrip Pulse Watch AppTests/AppRadioSilenceWatchStateTests.swift"',
  '-o "$WATCH_RADIO_SILENCE_VERIFY_BINARY"',
  '"$WATCH_RADIO_SILENCE_VERIFY_BINARY"',
]);
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
  deployExecutableSource.includes("verify-canonical-route-trusted-clock.swift") &&
  deployExecutableSource.includes("swiftc -swift-version 5 -parse-as-library") &&
  deployExecutableSource.includes("SIGNED_COVERAGE_SOURCE_VERIFICATION") &&
  deployExecutableSource.includes("SignedInstalledCoverageResolverTests.swift") &&
  deployExecutableSource.includes("APP_RADIO_SILENCE_SOURCE_VERIFICATION") &&
  deployExecutableSource.includes("AppRadioSilenceLeaseState.swift") &&
  deployExecutableSource.includes("AppRadioSilenceLeaseStateTests.swift") &&
  deployExecutableSource.includes("APP_RADIO_SILENCE_WATCH_SOURCE_VERIFICATION") &&
  deployExecutableSource.includes("AppRadioSilenceWatchState.swift") &&
  deployExecutableSource.includes("AppRadioSilenceWatchStateTests.swift") &&
  deployRunsTrustedClockBinary &&
  deployRunsCoverageClockBinary &&
  deployRunsAppRadioSilenceBinary &&
  deployRunsWatchRadioSilenceBinary &&
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
const mapLibraryCode = exists(relative.mapLibraryView)
  ? compiledSwiftCodeOnly(read(relative.mapLibraryView))
  : "";
const roadJourneyCode = exists(relative.roadJourneyView)
  ? compiledSwiftCodeOnly(read(relative.roadJourneyView))
  : "";
const driverEnRouteCode = exists(relative.driverEnRouteView)
  ? compiledSwiftCodeOnly(read(relative.driverEnRouteView))
  : "";
const routeClientCode = exists(relative.routeClient)
  ? compiledSwiftCodeOnly(read(relative.routeClient))
  : "";
const routeReaderCode = exists(relative.routeReader)
  ? compiledSwiftCodeOnly(read(relative.routeReader))
  : "";
const railRouteCallerCode = exists(relative.railRouteCaller)
  ? compiledSwiftCodeOnly(read(relative.railRouteCaller))
  : "";
const vesselRouteCallerCode = exists(relative.vesselRouteCaller)
  ? compiledSwiftCodeOnly(read(relative.vesselRouteCaller))
  : "";
const canonicalItineraryCode = exists(relative.canonicalItineraryView)
  ? compiledSwiftCodeOnly(read(relative.canonicalItineraryView))
  : "";
const productionCompositionCode = exists(relative.productionComposition)
  ? compiledSwiftCodeOnly(read(relative.productionComposition))
  : "";
const navigateEngineCode = exists(relative.navigateEngine)
  ? compiledSwiftCodeOnly(read(relative.navigateEngine))
  : "";
const navigationCode = exists(relative.navigation)
  ? compiledSwiftCodeOnly(read(relative.navigation))
  : "";
const nativeMapSurfaceCode = exists(relative.surface)
  ? compiledSwiftCodeOnly(read(relative.surface))
  : "";
const onlineMapWebViewCode = exists(relative.onlineMapWebView)
  ? compiledSwiftCodeOnly(read(relative.onlineMapWebView))
  : "";
const apiCode = exists(relative.api) ? compiledSwiftCodeOnly(read(relative.api)) : "";
const realtimeServiceCode = exists(relative.realtimeService)
  ? compiledSwiftCodeOnly(read(relative.realtimeService))
  : "";
const driverGPSPushServiceCode = exists(relative.driverGPSPushService)
  ? compiledSwiftCodeOnly(read(relative.driverGPSPushService))
  : "";
const hosClockServiceCode = exists(relative.hosClockService)
  ? compiledSwiftCodeOnly(read(relative.hosClockService))
  : "";
const reminderSyncServiceCode = exists(relative.reminderSyncService)
  ? compiledSwiftCodeOnly(read(relative.reminderSyncService))
  : "";
const offlineQueueCode = exists(relative.offlineQueue)
  ? compiledSwiftCodeOnly(read(relative.offlineQueue))
  : "";
const geofenceServiceCode = exists(relative.geofenceService)
  ? compiledSwiftCodeOnly(read(relative.geofenceService))
  : "";
const appRadioSilenceDirectTransportCode = exists(relative.appRadioSilenceDirectTransport)
  ? swiftCodeOnly(read(relative.appRadioSilenceDirectTransport))
  : "";
const appRadioSilenceAsyncImageCode = exists(relative.appRadioSilenceAsyncImage)
  ? swiftCodeOnly(read(relative.appRadioSilenceAsyncImage))
  : "";
const pushServiceCode = exists(relative.pushService)
  ? compiledSwiftCodeOnly(read(relative.pushService))
  : "";
const weatherServiceCode = exists(relative.weatherService)
  ? swiftCodeOnly(read(relative.weatherService))
  : "";
const newsImageCacheCode = exists(relative.newsImageCache)
  ? swiftCodeOnly(read(relative.newsImageCache))
  : "";
const ptChannelManagerCode = exists(relative.ptChannelManager)
  ? swiftCodeOnly(read(relative.ptChannelManager))
  : "";
const watchAuthBridgeCode = exists(relative.watchAuthBridge)
  ? swiftCodeOnly(read(relative.watchAuthBridge))
  : "";
const phoneWatchBridgeCode = exists(relative.phoneWatchBridge)
  ? swiftCodeOnly(read(relative.phoneWatchBridge))
  : "";
const appAttestClientCode = exists(relative.appAttestClient)
  ? swiftCodeOnly(read(relative.appAttestClient))
  : "";
const appleAuthProviderCode = exists(relative.appleAuthProvider)
  ? swiftCodeOnly(read(relative.appleAuthProvider))
  : "";
const walletApplePayProviderCode = exists(relative.walletApplePayProvider)
  ? swiftCodeOnly(read(relative.walletApplePayProvider))
  : "";
const walletPassServiceCode = exists(relative.walletPassService)
  ? swiftCodeOnly(read(relative.walletPassService))
  : "";
const shipperAppIntentsCode = exists(relative.shipperAppIntents)
  ? swiftCodeOnly(read(relative.shipperAppIntents))
  : "";
const dockAssignedViewCode = exists(relative.dockAssignedView)
  ? swiftCodeOnly(read(relative.dockAssignedView))
  : "";
const watchRadioSilencePolicyCode = exists(relative.watchRadioSilencePolicy)
  ? swiftCodeOnly(read(relative.watchRadioSilencePolicy))
  : "";
const watchConnectivityCode = exists(relative.watchConnectivityManager)
  ? swiftCodeOnly(read(relative.watchConnectivityManager))
  : "";
const watchAppEntryCode = exists(relative.watchAppEntry)
  ? swiftCodeOnly(read(relative.watchAppEntry))
  : "";
const watchEsangClientCode = exists(relative.watchEsangClient)
  ? swiftCodeOnly(read(relative.watchEsangClient))
  : "";
const watchOfflineQueueCode = exists(relative.watchOfflineQueue)
  ? swiftCodeOnly(read(relative.watchOfflineQueue))
  : "";
const watchAudioRecorderCode = exists(relative.watchAudioRecorder)
  ? swiftCodeOnly(read(relative.watchAudioRecorder))
  : "";
const navigationModelsCode = exists(relative.navigationModels)
  ? compiledSwiftCodeOnly(read(relative.navigationModels))
  : "";
const appTypeStart = appEntryCode.search(/@main\s+struct\s+EusoTripApp\b/);
const appLifecycleCode = appTypeStart >= 0
  ? swiftDeclarationBody(appEntryCode, /\binit\s*\(\s*\)\s*\{/, appTypeStart)
  : "";
const productionInstallCode = swiftDeclarationBody(
  productionCompositionCode,
  /\bstatic\s+func\s+install\s*\([^)]*\)\s*(?:async\s*)?(?:throws\s*)?\{/,
);
const mapSurfacePrepareCode = swiftDeclarationBody(
  productionCompositionCode,
  /\bfunc\s+prepareMapSurface\s*\([^)]*\)\s*->\s*AnyObject\?\s*\{/,
);
const canonicalDownloadCode = swiftDeclarationBody(
  routeClientCode,
  /\bfunc\s+download\s*\(\s*subject:\s*CanonicalRouteFreightSubject,\s*principal:\s*CanonicalRouteAuthenticatedPrincipal\s*\)\s*async\s*throws\s*->\s*CanonicalRoutePlanDelivery\s*\{/,
);
const canonicalReadCode = swiftDeclarationBody(
  routeReaderCode,
  /\bfunc\s+freshPackage\s*\([^)]*\)\s*async\s*throws\s*->\s*CanonicalRoutePackage\s*\{/,
);
const railSecureCode = swiftDeclarationBody(
  railRouteCallerCode,
  /\bprivate\s+func\s+secureOfflineCanonicalRoute\s*\([^)]*\)\s*async\s*\{/,
);
const railRestoreCode = swiftDeclarationBody(
  railRouteCallerCode,
  /\bprivate\s+func\s+restoreOfflineCanonicalRoute\s*\([^)]*\)\s*async\s*->\s*Bool\s*\{/,
);
const vesselSecureCode = swiftDeclarationBody(
  vesselRouteCallerCode,
  /\bprivate\s+func\s+secureOfflineRoute\s*\([^)]*\)\s*async\s*\{/,
);
const vesselRestoreCode = swiftDeclarationBody(
  vesselRouteCallerCode,
  /\bprivate\s+func\s+restoreOfflineRoute\s*\([^)]*\)\s*async\s*->\s*Bool\s*\{/,
);
const roadBindPrincipalCode = swiftDeclarationBody(
  roadJourneyCode,
  /\bfunc\s+bindPrincipal\s*\([^)]*\)\s*async\s*\{/,
);
const roadSearchCode = swiftDeclarationBody(
  roadJourneyCode,
  /\bfunc\s+search\s*\(\s*\)\s*\{/,
);
const roadCalculateCode = swiftDeclarationBody(
  roadJourneyCode,
  /\bfunc\s+calculateRoute\s*\(\s*\)\s*\{/,
);
const roadStartGuidanceCode = swiftDeclarationBody(
  roadJourneyCode,
  /\bfunc\s+startGuidance\s*\(\s*\)\s*\{/,
);
const driverPresentOfflineRoadDeskCode = swiftDeclarationBody(
  driverEnRouteCode,
  /\bprivate\s+func\s+presentOfflineRoadDesk\s*\(\s*\)\s*\{/,
);
const driverReleaseAppRadioSilenceCode = swiftDeclarationBody(
  driverEnRouteCode,
  /\bprivate\s+func\s+releaseAppRadioSilenceLease\s*\(\s*\)\s*\{/,
);
const driverBodyCode = swiftDeclarationBody(
  driverEnRouteCode,
  /\bvar\s+body\s*:\s*some\s+View\s*\{/,
);
const roadEnsureAppRadioSilenceCode = swiftDeclarationBody(
  roadJourneyCode,
  /\bprivate\s+func\s+ensureAppRadioSilenceLease\s*\(\s*\)\s*\{/,
);
const roadReleaseAppRadioSilenceCode = swiftDeclarationBody(
  roadJourneyCode,
  /\bprivate\s+func\s+releaseAppRadioSilenceLease\s*\(\s*\)\s*\{/,
);
const roadBodyCode = swiftDeclarationBody(
  roadJourneyCode,
  /\bvar\s+body\s*:\s*some\s+View\s*\{/,
);
const roadReadinessBlockersCode = swiftDeclarationBody(
  roadJourneyCode,
  /\bstatic\s+func\s+blockers\s*\([^)]*\)\s*->\s*\[String\]\s*\{/,
);
const nativeSearchCode = swiftDeclarationBody(
  navigateEngineCode,
  /\bfunc\s+searchOffline\s*\([^)]*\)\s*async\s+throws\s*->\s*OfflineSearchResponse\s*\{/,
);
const nativeRouteCalculationCode = swiftDeclarationBody(
  navigateEngineCode,
  /\bfunc\s+calculateOfflineRoute\s*\([^)]*\)\s*async\s+throws\s*->\s*OfflineRouteResponse\s*\{/,
);
const nativeDownloadRegionsCode = swiftDeclarationBody(
  navigateEngineCode,
  /\bfunc\s+downloadRegions[\s\S]*?\)\s*async\s+throws\s*\{/,
);
const nativeUpdatePersistentMapCode = swiftDeclarationBody(
  navigateEngineCode,
  /\bfunc\s+updatePersistentMap[\s\S]*?\)\s*async\s+throws\s*\{/,
);
const nativePauseTransferCode = swiftDeclarationBody(
  navigateEngineCode,
  /\bfunc\s+pauseActiveTransfer\s*\(\s*\)\s*async\s+throws\s*\{/,
);
const nativeResumeTransferCode = swiftDeclarationBody(
  navigateEngineCode,
  /\bfunc\s+resumeActiveTransfer\s*\(\s*\)\s*async\s+throws\s*\{/,
);
const nativeCancelTransferCode = swiftDeclarationBody(
  navigateEngineCode,
  /\bfunc\s+cancelActiveTransfer\s*\(\s*\)\s*async\s+throws\s*\{/,
);
const downloadBridgeCode = swiftDeclarationBody(
  navigateEngineCode,
  /\bprivate\s+final\s+class\s+HereDownloadProgressBridge\b[^\{]*\{/,
);
const catalogUpdateBridgeStart = navigateEngineCode.indexOf(
  "private final class HereCatalogUpdateProgressBridge",
);
const catalogUpdateBridgeCode = catalogUpdateBridgeStart >= 0
  ? swiftDeclarationBody(
      navigateEngineCode,
      /\bprivate\s+final\s+class\s+HereCatalogUpdateProgressBridge\b[^\{]*\{/,
      catalogUpdateBridgeStart,
    )
  : "";
const bridgeFunctionBody = (bridgeCode, name) => swiftDeclarationBody(
  bridgeCode,
  new RegExp(`\\bfunc\\s+${name}[\\s\\S]*?\\)\\s*(?:async\\s*)?(?:throws\\s*)?(?:->\\s*[^\\{]+)?\\{`),
);
const navigationInterruptionReceiveCode = swiftDeclarationBody(
  navigationCode,
  /\bmutating\s+func\s+receive[\s\S]*?\)\s*->\s*HereNavigationInterruptionAction\s*\{/,
);
const navigationAcceptFreshLocationCode = swiftDeclarationBody(
  navigationCode,
  /\bmutating\s+func\s+acceptFreshLocation\s*\([^)]*\)\s*->\s*Bool\s*\{/,
);
const navigationFeedCode = swiftDeclarationBody(
  navigationCode,
  /\bfunc\s+feed\s*\(\s*location:\s*OfflineDeviceLocationSample\s*\)\s*async\s+throws\s*\{/,
);
const navigationAudioInterruptionCode = swiftDeclarationBody(
  navigationCode,
  /\bfunc\s+handleAudioInterruption[\s\S]*?\)\s*async\s*\{/,
);
const navigationPermitsCallbackCode = swiftDeclarationBody(
  navigationCode,
  /\bprivate\s+func\s+permitsNativeCallback[\s\S]*?\)\s*->\s*Bool\s*\{/,
);
const navigationRerouteCode = swiftDeclarationBody(
  navigationCode,
  /\bprivate\s+func\s+returnToRoute[\s\S]*?\)\s*async\s*\{/,
);
const nativeMapPrepareCode = swiftDeclarationBody(
  nativeMapSurfaceCode,
  /\bfunc\s+prepareNative[\s\S]*?\)\s*->\s*AnyObject\?\s*\{/,
);
const nativeMapSetProjectionCode = swiftDeclarationBody(
  nativeMapSurfaceCode,
  /\bfunc\s+setJourneyProjection\s*\([^)]*\)\s*\{/,
);
const nativeMapApplyProjectionCode = swiftDeclarationBody(
  nativeMapSurfaceCode,
  /\bfunc\s+applyJourneyProjection[\s\S]*?\)\s*throws\s*\{/,
);
const nativeMapRemoveProjectionCode = swiftDeclarationBody(
  nativeMapSurfaceCode,
  /\bfunc\s+removeNativeJourneyProjection\s*\(\s*\)\s*\{/,
);
const nativeMapOpaqueFailureCode = swiftDeclarationBody(
  nativeMapSurfaceCode,
  /\bprivate\s+func\s+replaceWithOpaqueFailure\s*\([^)]*\)\s*\{/,
);
const nativeMapClearCode = swiftDeclarationBody(
  nativeMapSurfaceCode,
  /\bfunc\s+clear\s*\(\s*\)\s*\{/,
);
const productionStartNavigationCode = swiftDeclarationBody(
  productionCompositionCode,
  /\bfunc\s+startNavigation\s*\([^)]*\)\s*async\s+throws\s*\{/,
);
const productionAcceptDeviceLocationCode = swiftDeclarationBody(
  productionCompositionCode,
  /\bprivate\s+func\s+acceptDeviceLocation\s*\([^)]*\)\s*async\s*\{/,
);
const productionStopNavigationCode = swiftDeclarationBody(
  productionCompositionCode,
  /\bprivate\s+func\s+stopNavigationAndLocationSource\s*\(\s*\)\s*async\s*\{/,
);
const productionApplicationPhaseCode = swiftDeclarationBody(
  productionCompositionCode,
  /\bfunc\s+handleApplicationPhase\s*\([^)]*\)\s*async\s*\{/,
);
const roadNativeJourneyMapCode = swiftDeclarationBody(
  roadJourneyCode,
  /\bprivate\s+var\s+nativeJourneyMap\s*:\s*some\s+View\s*\{/,
);
const roadJourneyProjectionCode = swiftDeclarationBody(
  roadJourneyCode,
  /\bprivate\s+var\s+journeyProjection\s*:\s*HereOfflineMapJourneyProjection\s*\{/,
);
const nativeSurfaceHostStart = mapLibraryCode.indexOf(
  "struct OfflineNativeCoverageMapSurfaceHost",
);
const nativeSurfaceHostCode = nativeSurfaceHostStart >= 0
  ? swiftDeclarationBody(
      mapLibraryCode,
      /\bstruct\s+OfflineNativeCoverageMapSurfaceHost\b[^\{]*\{/,
      nativeSurfaceHostStart,
    )
  : "";
const nativeSurfaceHostBodyCode = swiftDeclarationBody(
  nativeSurfaceHostCode,
  /\bvar\s+body\s*:\s*some\s+View\s*\{/,
);
const nativeSurfaceHostBlockingCode = swiftDeclarationBody(
  nativeSurfaceHostCode,
  /\bprivate\s+var\s+blockingReason\s*:\s*String\?\s*\{/,
);
const nativeSurfaceHostLeaseEligibilityCode = swiftDeclarationBody(
  nativeSurfaceHostCode,
  /\bprivate\s+var\s+appRadioSilenceEligibility\s*:\s*Bool\s*\{/,
);
const nativeSurfaceHostReconcileLeaseCode = swiftDeclarationBody(
  nativeSurfaceHostCode,
  /\bprivate\s+func\s+reconcileAppRadioSilenceLease\s*\(\s*\)\s*\{/,
);
const nativeSurfaceHostReleaseLeaseCode = swiftDeclarationBody(
  nativeSurfaceHostCode,
  /\bprivate\s+func\s+releaseAppRadioSilenceLease\s*\(\s*\)\s*\{/,
);
const canonicalItineraryBodyCode = swiftDeclarationBody(
  canonicalItineraryCode,
  /\bvar\s+body\s*:\s*some\s+View\s*\{/,
);
const nativeMapHostStart = mapLibraryCode.indexOf(
  "private final class OfflineNativeCoverageMapMountModel",
);
const nativeMapHostCode = nativeMapHostStart >= 0
  ? swiftDeclarationBody(
      mapLibraryCode,
      /\bprivate\s+final\s+class\s+OfflineNativeCoverageMapMountModel\b[^\{]*\{/,
      nativeMapHostStart,
    )
  : "";
const nativeMapHostReconcileCode = swiftDeclarationBody(
  nativeMapHostCode,
  /\bfunc\s+reconcile[\s\S]*?\)\s*\{/,
);
const apiRadioSilenceGateCode = swiftDeclarationBody(
  apiCode,
  /\bfunc\s+setAppRadioSilenceEnforced\s*\(\s*_\s+enforced:\s*Bool\s*\)\s*\{/,
);
const apiCombinedRadioSilenceGateCode = swiftDeclarationBody(
  apiCode,
  /\bvar\s+isAppRadioSilenceEnforced\s*:\s*Bool\s*\{/,
);
const apiGatedDataCode = swiftDeclarationBody(
  apiCode,
  /\bfunc\s+appRadioSilenceGatedData[\s\S]*?\)\s*async\s+throws\s*->\s*\(Data,\s*URLResponse\)\s*\{/,
);
const apiTransportDataCode = swiftDeclarationBody(
  apiCode,
  /\bprivate\s+func\s+transportData\s*\(\s*for\s+original:\s*URLRequest\s*\)\s*async\s+throws\s*->\s*\(Data,\s*URLResponse\)\s*\{/,
);
const serviceFunctionBody = (source, name) => swiftDeclarationBody(
  source,
  new RegExp(`\\bfunc\\s+${name}\\s*\\(\\s*\\)\\s*\\{`),
);
const realtimeSuspendCode = serviceFunctionBody(realtimeServiceCode, "suspendForAppRadioSilence");
const realtimeResumeCode = serviceFunctionBody(realtimeServiceCode, "resumeAfterAppRadioSilence");
const driverGPSSuspendCode = serviceFunctionBody(driverGPSPushServiceCode, "suspendForAppRadioSilence");
const driverGPSResumeCode = serviceFunctionBody(driverGPSPushServiceCode, "resumeAfterAppRadioSilence");
const hosSuspendCode = serviceFunctionBody(hosClockServiceCode, "suspendForAppRadioSilence");
const hosResumeCode = serviceFunctionBody(hosClockServiceCode, "resumeAfterAppRadioSilence");
const reminderSuspendCode = serviceFunctionBody(reminderSyncServiceCode, "suspendForAppRadioSilence");
const reminderResumeCode = serviceFunctionBody(reminderSyncServiceCode, "resumeAfterAppRadioSilence");
const queueSuspendCode = serviceFunctionBody(offlineQueueCode, "suspendForAppRadioSilence");
const queueResumeCode = serviceFunctionBody(offlineQueueCode, "resumeAfterAppRadioSilence");
const geofenceSuspendCode = serviceFunctionBody(geofenceServiceCode, "suspendForAppRadioSilence");
const geofenceResumeCode = serviceFunctionBody(geofenceServiceCode, "resumeAfterAppRadioSilence");
const firstForegroundRecoveryCode = swiftDeclarationBody(
  pushServiceCode,
  /\bfunc\s+applicationDidBecomeActive\s*\(\s*_\s+application:\s*UIApplication\s*\)\s*\{/,
);
const weatherSuspendCode = serviceFunctionBody(weatherServiceCode, "suspendForAppRadioSilence");
const weatherResumeCode = serviceFunctionBody(weatherServiceCode, "resumeAfterAppRadioSilence");
const newsSuspendCode = serviceFunctionBody(newsImageCacheCode, "suspendForAppRadioSilence");
const newsResumeCode = serviceFunctionBody(newsImageCacheCode, "resumeAfterAppRadioSilence");
const ptSuspendCode = serviceFunctionBody(ptChannelManagerCode, "suspendForAppRadioSilence");
const ptResumeCode = serviceFunctionBody(ptChannelManagerCode, "resumeAfterAppRadioSilence");
const watchPolicyApplyCode = swiftDeclarationBody(
  watchRadioSilencePolicyCode,
  /\bfunc\s+apply\s*\(\s*enforced:\s*Bool,\s*revision:\s*Int,\s*epoch:\s*String\s*\)\s*\{/,
);
const watchPolicyBootstrapCode = serviceFunctionBody(watchRadioSilencePolicyCode, "bootstrap");
const watchPolicyDataCode = swiftDeclarationBody(
  watchRadioSilencePolicyCode,
  /\bfunc\s+data\s*\(\s*for\s+original:\s*URLRequest\s*\)\s*async\s+throws\s*->\s*\(Data,\s*URLResponse\)\s*\{/,
);
const hosPollOnceCode = swiftDeclarationBody(
  hosClockServiceCode,
  /\bprivate\s+func\s+pollOnce\s*\(\s*\)\s*async\s*\{/,
);
const reminderSyncCode = swiftDeclarationBody(
  reminderSyncServiceCode,
  /\bfunc\s+sync\s*\([^)]*\)\s*async\s*\{/,
);
const queueFlushCode = swiftDeclarationBody(
  offlineQueueCode,
  /\bfunc\s+flush\s*\(\s*\)\s*async\s*\{/,
);
const geofencePostCode = swiftDeclarationBody(
  geofenceServiceCode,
  /\bprivate\s+func\s+postServerFence\s*\([^)]*\)\s*\{/,
);
const onlineMapBodyCode = swiftDeclarationBody(
  onlineMapWebViewCode,
  /\bpublic\s+var\s+body\s*:\s*some\s+View\s*\{/,
);
const onlineMapMakeCode = swiftDeclarationBody(
  onlineMapWebViewCode,
  /\bfunc\s+makeUIView\s*\(\s*context:\s*Context\s*\)\s*->\s*WKWebView\s*\{/,
);
const onlineMapUpdateCode = swiftDeclarationBody(
  onlineMapWebViewCode,
  /\bfunc\s+updateUIView\s*\(\s*_\s+webView:\s*WKWebView,\s*context:\s*Context\s*\)\s*\{/,
);
const onlineMapDismantleCode = swiftDeclarationBody(
  onlineMapWebViewCode,
  /\bstatic\s+func\s+dismantleUIView\s*\([^)]*\)\s*\{/,
);
const onlineMapDisposeCode = swiftDeclarationBody(
  onlineMapWebViewCode,
  /\bfunc\s+disposeForAppRadioSilence\s*\(\s*\)\s*\{/,
);
const onlineMapNotificationCode = swiftDeclarationBody(
  onlineMapWebViewCode,
  /\bprivate\s+func\s+appRadioSilenceWillEngage\s*\(\s*\)\s*\{/,
);
const driverGPSStopCode = swiftDeclarationBody(
  driverGPSPushServiceCode,
  /\bfunc\s+stop\s*\(\s*\)\s*\{/,
);
const driverGPSFlushCode = swiftDeclarationBody(
  driverGPSPushServiceCode,
  /\bprivate\s+func\s+flushCrumbs\s*\(\s*\)\s*\{/,
);
const navigationReplacementInitCode = swiftDeclarationBody(
  navigationModelsCode,
  /\binit\s*\(\s*route:\s*OfflineLocalRoute,[\s\S]*?admittedCoverage:\s*OfflineInstalledCoverageEvidence\s*\)\s*throws\s*\{/,
);
const navigationProjectionAcceptCode = swiftDeclarationBody(
  navigationModelsCode,
  /\bmutating\s+func\s+accept\s*\(\s*_\s+replacement:\s*OfflineNavigationRouteReplacement\s*\)\s*->\s*Bool\s*\{/,
);
const navigationProjectionResolveCode = swiftDeclarationBody(
  navigationModelsCode,
  /\bfunc\s+resolveHostRoute[\s\S]*?\)\s*->\s*OfflineLocalRoute\?\s*\{/,
);
const nativeRouteMapperCode = swiftDeclarationBody(
  navigateEngineCode,
  /\benum\s+HereNativeRouteMapper\s*\{/,
);
const productionAcceptNavigationEventCode = swiftDeclarationBody(
  productionCompositionCode,
  /\bprivate\s+func\s+acceptNavigationEvent\s*\(\s*_\s+event:\s*OfflineNavigationEvent\s*\)\s*\{/,
);
const productionSetMapProjectionCode = swiftDeclarationBody(
  productionCompositionCode,
  /\bfunc\s+setMapJourneyProjection\s*\([^)]*\)\s*\{/,
);
if (!containsInOrder(apiRadioSilenceGateCode, [
  "guard isAppRadioSilenceEnforcedInProcess != enforced else { return }",
  "isAppRadioSilenceEnforcedInProcess = enforced",
  "guard enforced else { return }",
  "inFlightRefresh?.cancel()",
  "inFlightRefresh = nil",
  "isRefreshing = false",
  "session.invalidateAndCancel()",
  "session = Self.makeSession()",
  "let auxiliary = Array(appRadioSilenceAuxiliarySessions.values)",
  "appRadioSilenceAuxiliarySessions.removeAll()",
  "for session in auxiliary",
  "session.invalidateAndCancel()",
]) || !containsInOrder(apiCombinedRadioSilenceGateCode, [
  "isAppRadioSilenceEnforcedInProcess",
  "|| AppRadioSilenceSharedState.isEnforced",
]) || !containsInOrder(apiGatedDataCode, [
  "try Task.checkCancellation()",
  "try requireAppRadioSilenceTransportAllowed()",
  "let auxiliarySession = Self.makeAuxiliarySession()",
  "let registration = try registerAppRadioSilenceAuxiliarySession(auxiliarySession)",
  "defer",
  "unregisterAppRadioSilenceAuxiliarySession(registration)",
  "auxiliarySession.invalidateAndCancel()",
  "response = try await auxiliarySession.data(for: request)",
  "if isAppRadioSilenceEnforced",
  "try Task.checkCancellation()",
  "try requireAppRadioSilenceTransportAllowed()",
  "return response",
])) {
  failures.push("EusoTripAPI radio-silence boundary no longer combines the in-process/app-group gate or invalidates and pre/post-gates every main and auxiliary URLSession transport");
}
const apiSessionDataCallCount = (apiCode.match(/\bsession\.data\s*\(\s*for:/g) ?? []).length;
if (apiSessionDataCallCount !== 1 || !containsInOrder(apiTransportDataCode, [
  "try Task.checkCancellation()",
  "guard !isAppRadioSilenceEnforced else",
  "response = try await session.data(for: request)",
  "if isAppRadioSilenceEnforced",
  "try Task.checkCancellation()",
  "guard !isAppRadioSilenceEnforced else",
  "return response",
])) {
  failures.push("EusoTripAPI transport no longer routes its sole URLSession data call through cancellation-aware preflight and postflight radio-silence gates");
}
const requiredServiceLifecycleChecks = [
  {
    name: "RealtimeService",
    suspend: realtimeSuspendCode,
    suspendSteps: [
      "guard !isRadioSilenceSuspended else { return }",
      "isRadioSilenceSuspended = true",
      "tearDownConnection(reason:",
    ],
    resume: realtimeResumeCode,
    resumeSteps: [
      "guard isRadioSilenceSuspended else { return }",
      "isRadioSilenceSuspended = false",
      "guard wantsConnection",
      "!EusoTripAPI.shared.isAppRadioSilenceEnforced else { return }",
      "beginConnectionIfNeeded()",
    ],
  },
  {
    name: "DriverGPSPushService",
    suspend: driverGPSSuspendCode,
    suspendSteps: [
      "guard !isRadioSilenceSuspended else { return }",
      "isRadioSilenceSuspended = true",
      "manager.stopUpdatingLocation()",
      "isStreaming = false",
      "locationPushTask?.cancel()",
      "crumbFlushTask?.cancel()",
    ],
    resume: driverGPSResumeCode,
    resumeSteps: [
      "guard isRadioSilenceSuspended else { return }",
      "isRadioSilenceSuspended = false",
      "guard activeLoadId != nil else { return }",
      "manager.startUpdatingLocation()",
      "isStreaming = true",
    ],
  },
  {
    name: "HOSClockService",
    suspend: hosSuspendCode,
    suspendSteps: [
      "guard !isRadioSilenceSuspended else { return }",
      "isRadioSilenceSuspended = true",
      "cancelPolling()",
    ],
    resume: hosResumeCode,
    resumeSteps: [
      "guard isRadioSilenceSuspended else { return }",
      "isRadioSilenceSuspended = false",
      "guard wantsPolling else { return }",
      "beginPollingIfNeeded()",
    ],
  },
  {
    name: "ReminderSyncService",
    suspend: reminderSuspendCode,
    suspendSteps: [
      "guard !isRadioSilenceSuspended else { return }",
      "isRadioSilenceSuspended = true",
      "cancelNetworkWork()",
    ],
    resume: reminderResumeCode,
    resumeSteps: [
      "guard isRadioSilenceSuspended else { return }",
      "isRadioSilenceSuspended = false",
      "guard isActive else { return }",
      "scheduleSync(",
      "startPollingIfNeeded()",
    ],
  },
  {
    name: "OfflineQueue",
    suspend: queueSuspendCode,
    suspendSteps: [
      "guard !isRadioSilenceSuspended else { return }",
      "isRadioSilenceSuspended = true",
      "scheduledRetry?.cancel()",
      "scheduledRetry = nil",
    ],
    resume: queueResumeCode,
    resumeSteps: [
      "guard isRadioSilenceSuspended else { return }",
      "isRadioSilenceSuspended = false",
      "guard !pending.isEmpty",
      "scheduleReplay(after: 1)",
    ],
  },
  {
    name: "GeofenceService",
    suspend: geofenceSuspendCode,
    suspendSteps: [
      "guard !isRadioSilenceSuspended else { return }",
      "isRadioSilenceSuspended = true",
      "serverFenceResolutionTask?.cancel()",
      "serverFenceResolutionTask = nil",
      "serverFenceEventTasks.removeAll()",
      "for task in tasks { task.cancel() }",
    ],
    resume: geofenceResumeCode,
    resumeSteps: [
      "guard isRadioSilenceSuspended else { return }",
      "isRadioSilenceSuspended = false",
      "if let load = monitoredLoad",
      "scheduleServerFenceResolution(for: load)",
    ],
  },
];
for (const service of requiredServiceLifecycleChecks) {
  if (!containsInOrder(service.suspend, service.suspendSteps) ||
      !containsInOrder(service.resume, service.resumeSteps)) {
    failures.push(`${service.name} no longer has a stateful app radio-silence suspend/resume lifecycle`);
  }
}
if (!containsInOrder(hosPollOnceCode, [
  "guard !isRadioSilenceSuspended, !Task.isCancelled else { return }",
  "EusoTripAPI.shared.hos.getStatus()",
  "guard !isRadioSilenceSuspended, !Task.isCancelled else { return }",
  "self.status = fresh",
  "pushToWatch(fresh)",
])) {
  failures.push("HOSClockService no longer gates both sides of its API poll before publishing or sending watch context during app radio silence");
}
if (!containsInOrder(reminderSyncCode, [
  "guard isActive, !isRadioSilenceSuspended, !Task.isCancelled else { return }",
  "EusoTripAPI.shared.upcomingReminderDeadlines(",
  "guard generation == syncGeneration",
  "!isRadioSilenceSuspended",
  "!Task.isCancelled else { return }",
  "apply(plan)",
])) {
  failures.push("ReminderSyncService no longer gates server reconciliation before and after suspension-sensitive awaits");
}
if (!containsInOrder(queueFlushCode, [
  "guard !isRadioSilenceSuspended, !Task.isCancelled else { return }",
  "try await replay(action)",
  "guard !isRadioSilenceSuspended, !Task.isCancelled else { break }",
  "remove(key: action.key)",
])) {
  failures.push("OfflineQueue replay no longer checks app radio silence before transport and before removing durable actions");
}
if (!containsInOrder(geofencePostCode, [
  "guard !isRadioSilenceSuspended else",
  "enqueueLocally()",
  "return",
  "serverFenceEventTasks[taskId] = Task",
  "postGeofenceEvent(",
  "catch is AppRadioSilenceTransportError",
  "enqueueLocally()",
])) {
  failures.push("GeofenceService no longer preserves local fence events when app radio silence prevents transport");
}
if (!containsInOrder(driverPresentOfflineRoadDeskCode, [
  "if appRadioSilenceLease == nil",
  "AppRadioSilenceCoordinator.shared.acquire(",
  "reason: .offlineRoadJourney",
  "presentsOfflineRoadDesk = true",
]) || !containsInOrder(driverReleaseAppRadioSilenceCode, [
  "guard let lease = appRadioSilenceLease else { return }",
  "AppRadioSilenceCoordinator.shared.release(lease)",
  "appRadioSilenceLease = nil",
]) || !containsInOrder(driverBodyCode, [
  ".fullScreenCover(",
  "onDismiss: releaseAppRadioSilenceLease",
  "OfflineRoadJourneyView(composition: composition)",
  "await OfflineMapProductionComposition.shared?",
  ".stopNavigation()",
  "releaseAppRadioSilenceLease()",
  "presentsOfflineRoadDesk = false",
  ".interactiveDismissDisabled()",
])) {
  failures.push("Driver offline journey no longer acquires before presentation and releases its app radio-silence lease on every controlled dismissal path");
}
if (!containsInOrder(roadEnsureAppRadioSilenceCode, [
  "guard appRadioSilenceLease == nil else { return }",
  "AppRadioSilenceCoordinator.shared.acquire(",
  "reason: .offlineRoadJourney",
]) || !containsInOrder(roadReleaseAppRadioSilenceCode, [
  "guard let lease = appRadioSilenceLease else { return }",
  "AppRadioSilenceCoordinator.shared.release(lease)",
  "appRadioSilenceLease = nil",
]) || !containsInOrder(roadBodyCode, [
  ".onAppear",
  "ensureAppRadioSilenceLease()",
  ".task(id: sessionScope)",
  "ensureAppRadioSilenceLease()",
  ".onDisappear",
  "model.cancelPendingOperation()",
  "releaseAppRadioSilenceLease()",
])) {
  failures.push("OfflineRoadJourneyView no longer owns an idempotent app radio-silence lease across appearance, task startup, cancellation, and disappearance");
}
if (!containsInOrder(roadReadinessBlockersCode, [
  "if !hasBoundPrincipal",
  "if !AppRadioSilenceCoordinator.shared.isEnforced",
  "if !composition.installedCoverageTrustAvailable",
  "snapshot.connectivityPolicy != .radioSilent",
  "snapshot.radioSilenceState != .enforced",
])) {
  failures.push("offline road journey readiness no longer requires both app-wide transport suspension and native HERE Radio Silent enforcement");
}
if (!containsInOrder(onlineMapBodyCode, [
  ".id(appRadioSilenceRevision)",
  ".eusoAppRadioSilenceWillEngage",
  "appRadioSilenceRevision &+= 1",
  ".eusoAppRadioSilenceDidRelease",
  "appRadioSilenceRevision &+= 1",
]) || !containsInOrder(onlineMapMakeCode, [
  "if EusoTripAPI.shared.isAppRadioSilenceEnforced",
  "webView.loadHTMLString(",
  "baseURL: nil",
  "else",
  "webView.loadHTMLString(html",
  "HereMapsConfig.jsTrustedReferrerOrigin",
]) || !containsInOrder(onlineMapUpdateCode, [
  "guard !EusoTripAPI.shared.isAppRadioSilenceEnforced else",
  "context.coordinator.disposeForAppRadioSilence()",
  "return",
  "context.coordinator.onSelectMarker = onSelectMarker",
]) || !containsInOrder(onlineMapDismantleCode, [
  "webView.stopLoading()",
  "removeAllScriptMessageHandlers()",
  "webView.navigationDelegate = nil",
  "webView.uiDelegate = nil",
  "coordinator.webView = nil",
]) || !containsInOrder(onlineMapNotificationCode, [
  "disposeForAppRadioSilence()",
]) || !containsInOrder(onlineMapDisposeCode, [
  "webView.stopLoading()",
  "removeAllScriptMessageHandlers()",
  "webView.loadHTMLString(",
  "baseURL: nil",
  "mapReady = false",
  "pendingCameraJS = nil",
  "pendingLayerJSON =",
  "onSelectMarker = nil",
]) || !containsInOrder(onlineMapWebViewCode, [
  "selector: #selector(appRadioSilenceWillEngage)",
  "name: .eusoAppRadioSilenceWillEngage",
])) {
  failures.push("HereMapWebView no longer synchronously stops and blanks active JS maps, guards make/update while enforced, and rebuilds on both policy edges");
}

const allAppSwiftSources = walkFiles("EusoTrip", ".swift").map(file => ({
  file,
  relativePath: path.relative(root, file).split(path.sep).join("/"),
  code: swiftCodeOnly(readWalkedRepositoryFile(file)),
}));
const builtInAsyncImageSources = allAppSwiftSources.filter(({ code }) =>
  /\bAsyncImage\s*\(/.test(code));
if (builtInAsyncImageSources.length !== 0 || !containsInOrder(appRadioSilenceAsyncImageCode, [
  "switch url.scheme?.lowercased()",
  "var request = URLRequest(url: url)",
  "appRadioSilenceGatedData(for: request)",
  "try Task.checkCancellation()",
  "guard revision == policyRevision else { return }",
])) {
  failures.push("remote image loading no longer has zero built-in AsyncImage sinks and one cancellation-aware EusoTripAPI radio-silence loader");
}

const directProviderSinkFiles = new Set();
for (const source of allAppSwiftSources) {
  const webViewConstructorCount = (source.code.match(/\bWKWebView\s*\(/g) ?? []).length;
  if (webViewConstructorCount > 0) {
    directProviderSinkFiles.add(source.relativePath);
    if (source.relativePath !== relative.onlineMapWebView) {
      const registrations = (source.code.match(/\.register\s*\(\s*webView:/g) ?? []).length;
      const gatedLoads = (source.code.match(/\.loadRemote(?:HTML)?\s*\(/g) ?? []).length;
      if (registrations < webViewConstructorCount || gatedLoads < webViewConstructorCount) {
        failures.push(`${source.relativePath}: direct WebKit construction is not registered and loaded through the app radio-silence controller`);
      }
    }
  }
  const safariConstructorCount = (source.code.match(/\bSFSafariViewController\s*\(/g) ?? []).length;
  if (safariConstructorCount > 0) {
    directProviderSinkFiles.add(source.relativePath);
    const gatedURLs = (source.code.match(/\.gatedRemoteURL\s*\(/g) ?? []).length;
    const trackedControllers = (source.code.match(/\.track\s*\(\s*safariController:/g) ?? []).length;
    if (gatedURLs < safariConstructorCount || trackedControllers < safariConstructorCount) {
      failures.push(`${source.relativePath}: Safari construction is not fail-closed and tracked from construction time`);
    }
  }
  if (/\bAVPlayer\s*\(\s*url:/.test(source.code)) {
    directProviderSinkFiles.add(source.relativePath);
  }
}
for (const sinkFile of directProviderSinkFiles) {
  if (!projectInspector.sourceRegistered(sinkFile)) {
    failures.push(`${sinkFile}: direct provider sink is not registered in the EusoTrip application target`);
  }
}
const directTransportRawSource = exists(relative.appRadioSilenceDirectTransport)
  ? read(relative.appRadioSilenceDirectTransport)
  : "";
if (!containsInOrder(appRadioSilenceDirectTransportCode, [
  "var transportAllowed: Bool",
  "!EusoTripAPI.shared.isAppRadioSilenceEnforced",
  "transports[registration] = RegisteredTransport(stop: stop, resume: resume)",
  "if isSuspended || EusoTripAPI.shared.isAppRadioSilenceEnforced",
  "stop()",
  "webView.stopLoading()",
  "webView.loadHTMLString(",
  "guard transportAllowed else",
  "webView.stopLoading()",
  "webView.loadHTMLString(",
  "webView.load(request)",
  "func track(safariController: SFSafariViewController)",
  "guard transportAllowed, !isSuspended else",
  "safariController.dismiss(animated: false)",
  "playerController?.player?.pause()",
  "playerController?.player?.replaceCurrentItem(with: nil)",
  "func suspendAll()",
  "for transport in registered { transport.stop() }",
  "func resumeAll()",
  "guard !EusoTripAPI.shared.isAppRadioSilenceEnforced else { return }",
  "for transport in registered { transport.resume?() }",
]) || !directTransportRawSource.includes('URL(string: "about:blank")!') ||
    !containsInOrder(dockAssignedViewCode, [
      "register(",
      "playerController: vc",
      "AppRadioSilenceDirectTransportController.shared.transportAllowed",
      "AVPlayer(url: url)",
      "guard AppRadioSilenceDirectTransportController.shared.transportAllowed else",
      "vc.player?.pause()",
      "vc.player?.replaceCurrentItem(with: nil)",
      "dismantleUIViewController",
      "vc.player?.pause()",
      "vc.player?.replaceCurrentItem(with: nil)",
      "unregister(",
    ])) {
  failures.push("direct WebKit, HLS, and Safari transports no longer stop synchronously, fail closed before start/update, and resume only through retained mounted ownership");
}

const foregroundRecoveryCallCount = allAppSwiftSources.reduce(
  (count, source) => count + (source.code.match(/\.recoverSharedStateOnFirstForegroundActivation\s*\(/g) ?? []).length,
  0,
);
if (foregroundRecoveryCallCount !== 1 || !containsInOrder(firstForegroundRecoveryCode, [
  "guard !preparedRadioSilenceForForeground else { return }",
  "preparedRadioSilenceForForeground = true",
  "MainActor.assumeIsolated",
  "AppRadioSilenceCoordinator.shared",
  ".recoverSharedStateOnFirstForegroundActivation()",
])) {
  failures.push("durable app-group RELEASE recovery no longer occurs exactly once at a real foreground activation while background wakes preserve ENFORCED");
}

if (!containsInOrder(weatherSuspendCode, [
  "guard !isAppRadioSilenceSuspended else { return }",
  "isAppRadioSilenceSuspended = true",
  "weatherFlights.cancelAll(returning: nil)",
  "locationFlights.cancelAll(returning: nil)",
  "finishPendingLocation(nil)",
]) || !weatherResumeCode.includes("isAppRadioSilenceSuspended = false") ||
    !containsInOrder(weatherServiceCode, [
      "try EusoTripAPI.shared.requireAppRadioSilenceTransportAllowed()",
      "weatherService.weather(for: location)",
      "try EusoTripAPI.shared.requireAppRadioSilenceTransportAllowed()",
    ]) || !newsSuspendCode.includes("for task in tasks { task.cancel() }") ||
    !newsResumeCode.includes("isRadioSilenceSuspended = false") ||
    !newsImageCacheCode.includes("appRadioSilenceGatedData(for: req)")) {
  failures.push("WeatherKit, geocoding, and news metadata providers no longer cancel owned work and enforce pre/post or gated transport boundaries");
}
if (!containsInOrder(ptSuspendCode, [
  "suspendedMembership =",
  "if isTransmitting",
  "manager.stopTransmitting(channelUUID: uuid)",
  "manager.leaveChannel(channelUUID: uuid)",
  "activeChannelUUID = nil",
  "joinedChainGroupId = nil",
  "isTransmitting = false",
]) || !containsInOrder(ptResumeCode, [
  "guard let membership = suspendedMembership else { return }",
  "suspendedMembership = nil",
  "await self?.join(",
]) || !containsInOrder(ptChannelManagerCode, [
  "guard !EusoTripAPI.shared.isAppRadioSilenceEnforced else { return }",
  "PTChannelManager_Apple.channelManager(",
  "guard !EusoTripAPI.shared.isAppRadioSilenceEnforced else { return }",
]) || (ptChannelManagerCode.match(/AppRadioSilenceSharedState\.isEnforced/g) ?? []).length < 2) {
  failures.push("Push-to-Talk no longer blocks creation/transmit, leaves synchronously, and rejects Apple callbacks while shared radio silence is enforced");
}
if (!containsInOrder(realtimeServiceCode, [
  "private func beginConnectionIfNeeded()",
  "guard !EusoTripAPI.shared.isAppRadioSilenceEnforced else { return }",
  "while !Task.isCancelled",
  "!isRadioSilenceSuspended",
  "!EusoTripAPI.shared.isAppRadioSilenceEnforced",
  "let ws = session.webSocketTask(with: req)",
  "guard !EusoTripAPI.shared.isAppRadioSilenceEnforced else",
  "ws.cancel(with: .goingAway, reason: nil)",
  "ws.resume()",
  "let message = try await ws.receive()",
  "guard !EusoTripAPI.shared.isAppRadioSilenceEnforced else",
]) || !containsInOrder(realtimeResumeCode, [
  "guard isRadioSilenceSuspended else { return }",
  "isRadioSilenceSuspended = false",
  "guard wantsConnection",
  "!EusoTripAPI.shared.isAppRadioSilenceEnforced else { return }",
  "beginConnectionIfNeeded()",
])) {
  failures.push("RealtimeService no longer gates socket creation, resume, receive, and send against the combined radio-silence authority");
}

const appAttestBuildCode = swiftDeclarationBody(
  appAttestClientCode,
  /\bprivate\s+static\s+func\s+buildAttestation[\s\S]*?\)\s*async\s*->\s*AttestEnvelope\?\s*\{/,
);
const appAttestEnsureKeyCode = swiftDeclarationBody(
  appAttestClientCode,
  /\bprivate\s+static\s+func\s+ensureAttestedKey[\s\S]*?\)\s*async\s*throws\s*->\s*String\s*\{/,
);
if (!containsInOrder(appAttestBuildCode, [
  "guard !AppRadioSilenceSharedState.isEnforced",
  "ensureAttestedKey(service: service)",
  "guard !AppRadioSilenceSharedState.isEnforced else { return nil }",
  "fetchChallenge()",
  "guard !AppRadioSilenceSharedState.isEnforced else { return nil }",
  "service.generateAssertion(",
  "guard !AppRadioSilenceSharedState.isEnforced else { return nil }",
]) || !containsInOrder(appAttestEnsureKeyCode, [
  "guard !AppRadioSilenceSharedState.isEnforced else",
  "service.generateKey()",
  "guard !AppRadioSilenceSharedState.isEnforced else",
  "fetchChallenge()",
  "guard !AppRadioSilenceSharedState.isEnforced else",
  "service.attestKey(",
  "guard !AppRadioSilenceSharedState.isEnforced else",
  "registerKey(",
  "storeKeyId(keyId)",
])) {
  failures.push("App Attest no longer checks the cross-process marker around key generation, challenge, attestation, assertion, and registration awaits");
}

const appleAuthorizationPerformCode = swiftDeclarationBody(
  appleAuthProviderCode,
  /\bprivate\s+func\s+perform[\s\S]*?\)\s*async\s*throws\s*->\s*ASAuthorization\s*\{/,
);
if (!containsInOrder(appleAuthorizationPerformCode, [
  "guard !EusoTripAPI.shared.isAppRadioSilenceEnforced else",
  "ASAuthorizationController(authorizationRequests: requests)",
  "activeAuthorizationController = controller",
  "AppRadioSilenceDirectTransportController.shared.register(",
  "controller?.cancel()",
  "cancelForAppRadioSilence(controller)",
  "controller.performRequests",
]) || !containsInOrder(appleAuthProviderCode, [
  "didCompleteWithAuthorization authorization: ASAuthorization",
  "finishAuthorizationController(controller)",
  "if EusoTripAPI.shared.isAppRadioSilenceEnforced",
  "cont?.resume(throwing:",
])) {
  failures.push("Apple authentication/passkey controllers no longer have combined preflight, registered cancellation, and postflight rejection");
}
if (!containsInOrder(walletApplePayProviderCode, [
  "guard !EusoTripAPI.shared.isAppRadioSilenceEnforced else",
  "createStripeSetupIntent()",
  "guard !EusoTripAPI.shared.isAppRadioSilenceEnforced else",
  "PKPaymentAuthorizationController(paymentRequest: request)",
  "AppRadioSilenceDirectTransportController.shared.register(",
  "controller?.dismiss",
  "controller.present",
]) || !containsInOrder(walletApplePayProviderCode, [
  "didAuthorizePayment payment: PKPayment",
  "guard !EusoTripAPI.shared.isAppRadioSilenceEnforced else",
  "createStripePaymentMethod(",
  "attachStripePaymentMethod(",
  "guard !EusoTripAPI.shared.isAppRadioSilenceEnforced else",
]) || !containsInOrder(walletPassServiceCode, [
  "guard !EusoTripAPI.shared.isAppRadioSilenceEnforced else",
  "fetchBoundedWalletPassData(url)",
  "guard !EusoTripAPI.shared.isAppRadioSilenceEnforced else",
  "PKPass(data: data)",
  "PKAddPassesViewController(pass: pkpass)",
  "guard activeAddPassController == nil",
  "!EusoTripAPI.shared.isAppRadioSilenceEnforced else",
  "AppRadioSilenceDirectTransportController.shared.register(",
  "addVC?.dismiss(animated: false)",
  "presenter.present(addVC",
])) {
  failures.push("Apple Pay and Wallet no longer gate provider/network awaits and register active PassKit presentation cancellation");
}

const phoneMapSearchCode = swiftDeclarationBody(
  phoneWatchBridgeCode,
  /\bprivate\s+func\s+openMaps\s*\(\s*query:\s*String\s*\)\s*\{/,
);
if (!containsInOrder(phoneMapSearchCode, [
  "guard AppRadioSilenceDirectTransportController.shared.transportAllowed else { return }",
  "mapSearch?.cancel()",
  "unregister(mapSearchRegistration)",
  "let search = MKLocalSearch(request: request)",
  "let registration = AppRadioSilenceDirectTransportController.shared.register",
  "search?.cancel()",
  "search.start",
  "unregister(registration)",
  "guard AppRadioSilenceDirectTransportController.shared.transportAllowed else",
  "destination.openInMaps",
])) {
  failures.push("MapKit local search no longer registers cancellation before start and rechecks policy before opening Maps");
}
const appIntentBackgroundTransportCount = (shipperAppIntentsCode.match(/openAppWhenRun:\s*Bool\s*=\s*false/g) ?? []).length;
if (appIntentBackgroundTransportCount < 5 ||
    (shipperAppIntentsCode.match(/EusoTripAPI\.shared\.esang\.chat/g) ?? []).length < 5 ||
    !containsInOrder(appEntryCode, [
      ".environment(\\.openURL, OpenURLAction",
      "scheme ==",
      "EusoTripAPI.shared.isAppRadioSilenceEnforced",
      "return .discarded",
      "return .systemAction(url)",
    ])) {
  failures.push("background App Intents and app-opened HTTP URLs no longer route through the combined API gate or discard web navigation while enforced");
}

const watchAuthBridgeRawSource = exists(relative.watchAuthBridge)
  ? read(relative.watchAuthBridge)
  : "";
if (!containsInOrder(watchAuthBridgeCode, [
  "AppRadioSilencePhoneMirrorPersistence",
  ".restoreForProcessRestart(",
  "snapshotData: defaults.data(",
  "sharedStateIsEnforced: AppRadioSilenceSharedState.isEnforced",
  "persistAppRadioSilenceState()",
]) || !containsInOrder(watchAuthBridgeRawSource, [
  "func setAppRadioSilenceEnforced(_ enforced: Bool)",
  "appRadioSilenceState.setEnforced(enforced)",
  "persistAppRadioSilenceState()",
  "republishAppRadioSilencePolicy()",
]) || !containsInOrder(watchAuthBridgeRawSource, [
  "AppRadioSilencePhoneMirrorPersistence.encode(",
  "defaults.set(data, forKey: Self.radioSilenceSnapshotDefaultsKey)",
  "\"op\": \"app.radioSilence\"",
  "\"enforced\": appRadioSilenceState.isEnforced",
  "\"revision\": appRadioSilenceState.revision",
  "\"epoch\": appRadioSilenceState.epoch",
  "publishContext(channel: \"radioSilence\"",
])) {
  failures.push("phone-to-watch radio-silence publication no longer restores one atomic envelope from shared authority and persists before publishing epoch/revision edges");
}
if (!containsInOrder(watchPolicyApplyCode, [
  "state.apply(",
  "guard transition != .stale else { return }",
  "persistState()",
  "if state.isEnforced",
  "OfflineQueue.shared.suspendForAppRadioSilence()",
  "sessions.removeAll()",
  "session.invalidateAndCancel()",
  "else",
  "OfflineQueue.shared.resumeAfterAppRadioSilence()",
]) || !containsInOrder(watchPolicyBootstrapCode, [
  "guard state.isEnforced else { return }",
  "OfflineQueue.shared.suspendForAppRadioSilence()",
  "sessions.removeAll()",
  "session.invalidateAndCancel()",
]) || !containsInOrder(watchPolicyDataCode, [
  "try Task.checkCancellation()",
  "try requireTransportAllowed()",
  "let session = Self.makeSession()",
  "sessions[registration] = session",
  "session.invalidateAndCancel()",
  "result = try await session.data(for: request)",
  "if state.isEnforced",
  "try Task.checkCancellation()",
  "try requireTransportAllowed()",
  "return result",
]) || !read(relative.watchConnectivityManager).includes(
  'let channelOrder = ["radioSilence", "auth", "load", "hos", "unread", "settings"]'
) || !containsInOrder(read(relative.watchConnectivityManager), [
  "case \"app.radioSilence\":",
  "AppRadioSilenceWatchPolicy.shared.apply(",
  "enforced: enforced",
  "revision: revision",
  "epoch: epoch",
]) || !containsInOrder(watchAppEntryCode, [
  "radioSilence.bootstrap()",
  "auth.restore()",
  "hos.restore()",
  "loads.restore()",
  "offline.restore()",
]) || !watchEsangClientCode.includes("AppRadioSilenceWatchPolicy.shared.data(for:") ||
    !watchAudioRecorderCode.includes("AppRadioSilenceWatchPolicy.shared.data(for:") ||
    !watchOfflineQueueCode.includes("suspendForAppRadioSilence")) {
  failures.push("watch radio-silence policy no longer persists before cancellation/resume, restores before app data, and pre/post-gates every watch-owned HTTP path");
}

const driverGPSMaybePushCode = swiftDeclarationBody(
  driverGPSPushServiceCode,
  /\bprivate\s+func\s+maybePush\s*\(\s*fix:\s*CLLocation\s*\)\s*\{/,
);
const driverGPSBufferCrumbCode = swiftDeclarationBody(
  driverGPSPushServiceCode,
  /\bprivate\s+func\s+bufferCrumb\s*\(\s*_\s+fix:\s*CLLocation\s*\)\s*\{/,
);
if (!driverGPSPushServiceCode.includes("let loadId: Int?") ||
    !containsInOrder(driverGPSMaybePushCode, [
      "guard activeLoadId != nil",
      "!isRadioSilenceSuspended",
      "locationPushTask == nil else { return }",
    ]) || !containsInOrder(driverGPSBufferCrumbCode, [
      "guard activeLoadId != nil",
      "breadcrumbsEnabled",
      "!isRadioSilenceSuspended else { return }",
      "crumbBuffer.append(Crumb(",
      "loadId: activeLoadId",
    ]) || !containsInOrder(driverGPSStopCode, [
      "pendingFinalCrumbLoadId = activeLoadId",
      "flushCrumbs()",
      "activeLoadId = nil",
    ]) || !containsInOrder(driverGPSFlushCode, [
      "guard let firstCrumb = crumbBuffer.first else { return }",
      ".prefix { $0.loadId == firstCrumb.loadId }",
      "let loadId = firstCrumb.loadId",
      "locationBatch(locations: points, loadId: loadId)",
      "pendingLoadId == loadId",
      "self.pendingFinalCrumbLoadId = nil",
      "self.crumbBuffer.insert(contentsOf: batch, at: 0)",
    ])) {
  failures.push("DriverGPS breadcrumb upload no longer preserves per-crumb load authority, pending-final ownership, and ordered rebuffer/retry semantics");
}

if (!containsInOrder(navigationReplacementInitCode, [
  "let routeID = replacingRouteID.trimmingCharacters",
  "guard !routeID.isEmpty",
  "route.id == routeID",
  "expectedMode.supportsHEREOfflineCalculation",
  "route.mode == expectedMode",
  "route.provenance == .hereOfflineLocal",
  "route.coverage == admittedCoverage else",
  "self.replacingRouteID = routeID",
  "replacingMode = expectedMode",
  "self.route = route",
]) || !containsInOrder(navigationProjectionAcceptCode, [
  "guard let current = route",
  "current.id == replacement.replacingRouteID",
  "current.mode == replacement.replacingMode else",
  "return false",
  "route = replacement.route",
  "return true",
]) || !containsInOrder(navigationProjectionResolveCode, [
  "guard let route else { return proposedRoute }",
  "if proposedRoute?.id == route.id || navigationIsActive",
  "return route",
  "return proposedRoute",
]) || !containsInOrder(nativeRouteMapperCode, [
  "for section in route.sections",
  "section.geometry.vertices.map",
  "sections.append(",
  "OfflineRouteSection(",
  "return try OfflineLocalRoute(",
  "id: routeID",
  "mode: mode",
  "sections: sections",
  "coverage: coverage",
]) || !containsInOrder(navigationRerouteCode, [
  "let mappedRoute: OfflineLocalRoute",
  "HereNativeRouteMapper.map(",
  "routeID: routeID",
  "mode: mode",
  "coverage: evidence",
  "OfflineNavigationRouteReplacement(",
  "route: mappedRoute",
  "replacingRouteID: routeID",
  "expectedMode: mode",
  "admittedCoverage: evidence",
  "eventHandler?(.routeReplaced(replacement))",
  "transition(.navigating(routeID: routeID, coverage: coverage))",
]) || !containsInOrder(productionAcceptNavigationEventCode, [
  "case .routeReplaced(let replacement):",
  "navigationRouteProjectionAuthority.accept(replacement)",
  "navigationRoute = replacement.route",
  "mapSurface.setJourneyRoute(replacement.route)",
]) || !containsInOrder(productionSetMapProjectionCode, [
  "navigationRouteProjectionAuthority.resolveHostRoute(",
  "projection.route",
  "navigationIsActive: navigationOwnsRoute",
  "mapSurface.reconcileHostJourneyProjection(",
  "route: route",
]) || !containsInOrder(productionCompositionCode, [
  "events.append((nextSequence, event))",
  "events.sorted { $0.0 < $1.0 }.map { $0.1 }",
]) || !containsInOrder(nativeMapSurfaceCode, [
  "struct HereOfflineMapProjectedRouteSignature",
  "let authority: Authority",
  "let mode: OfflineRouteMode",
  "let coordinateComponents: [[OfflineGeoCoordinate]]",
  "let distanceMeters: Int64",
  "static func local(_ route: OfflineLocalRoute)",
  "coordinateComponents: route.sections.map(\\.coordinates)",
  "static func canonical(_ route: CanonicalRoutePackage)",
  "coordinateComponents: route.segments.map(\\.coordinates)",
  "if selectedRoute?.signature != projectedRouteSignature",
  "projectedRouteSignature = route.signature",
])) {
  failures.push("typed HERE reroute replacement no longer preserves route authority/components or updates structural native geometry before navigating is published");
}

if (!containsInOrder(nativeSearchCode, [
  "let watchdog = HereFiniteCallbackWatchdog<[Place]>(",
  "timeout: 20",
  "let searchTask = searchEngine.searchByText(",
  "watchdog.fail(",
  "watchdog.succeed(places)",
  "let places = try await watchdog.wait",
  "searchTask.cancel()",
]) || !containsInOrder(nativeRouteCalculationCode, [
  "let watchdog = HereFiniteCallbackWatchdog<[Route]>(",
  "timeout: 30",
  "let routingTask = routingEngine.calculateRoute(",
  "watchdog.fail(",
  "watchdog.succeed(routes)",
  "let nativeRoutes = try await watchdog.wait",
  "routingTask.cancel()",
])) {
  failures.push("HERE offline search and route calculation no longer bound native one-shot callbacks with typed timeouts, native cancellation, and late-result rejection");
}
if (!containsInOrder(navigationRerouteCode, [
  "let commitBoundary = HereNavigationRerouteCommitBoundary(",
  "let watchdog = HereFiniteCallbackWatchdog<Route>(",
  "timeout: 30",
  "activeRerouteWatchdog = watchdog",
  "let rerouteTask = routingEngine.returnToRoute(",
  "watchdog.fail(",
  "watchdog.succeed(route)",
  "try await watchdog.wait",
  "rerouteTask.cancel()",
  "if activeRerouteWatchdog === watchdog",
  "activeRerouteWatchdog = nil",
  "guard rerouteGeneration == generation else { return }",
  "commitBoundary.permitsCommit(",
])) {
  failures.push("HERE offline rerouting no longer bounds the native callback, cancels the native task, and rejects stale commits after interruption or generation change");
}
if (!containsInOrder(nativeMapPrepareCode, [
  "nativeSceneLoadTask?.cancel()",
  "removeNativeJourneyProjection()",
  "let watchdog = HereFiniteCallbackWatchdog<Void>(",
  "timeout: 20",
  "nativeSceneLoadTask = Task",
  "try await watchdog.wait()",
  "self.loadGeneration == generation",
  "try self.applyJourneyProjection(self.journeyProjection)",
  "mapView.isHidden = false",
  "status: .rendered(configuration: configuration)",
  "mapView.mapScene.loadScene(fromFile: validatedPath)",
  "watchdog.fail(",
  "watchdog.succeed(())",
])) {
  failures.push("HERE native map-style loading no longer has a finite callback boundary or atomically applies pending journey projection before revealing the rendered scene");
}

function transferBridgePreservesFiniteLifecycle(bridgeCode) {
  const waitForCompletion = bridgeFunctionBody(bridgeCode, "waitForCompletion");
  const waitForPause = bridgeFunctionBody(bridgeCode, "waitForPause");
  const waitForResume = bridgeFunctionBody(bridgeCode, "waitForResume");
  const onProgress = bridgeFunctionBody(bridgeCode, "onProgress");
  const onPause = bridgeFunctionBody(bridgeCode, "onPause");
  const onResume = bridgeFunctionBody(bridgeCode, "onResume");
  const finish = bridgeFunctionBody(bridgeCode, "finish");
  return bridgeCode.includes("completionInactivityTimeout: TimeInterval = 120") &&
    bridgeCode.includes("controlCallbackTimeout: TimeInterval = 15") &&
    containsInOrder(waitForCompletion, [
      "completionWatchdog.wait(",
      "interruptNativeOperation: interruptNativeOperation",
      "catch",
      "finish(.failure(error))",
      "throw error",
    ]) && containsInOrder(waitForPause, [
      "guard pauseWatchdog == nil else",
      "HereFiniteCallbackWatchdog<Void>(",
      "timeout: Self.controlCallbackTimeout",
      "pauseWatchdog = watchdog",
      "try await watchdog.wait()",
    ]) && containsInOrder(waitForResume, [
      "guard resumeWatchdog == nil else",
      "HereFiniteCallbackWatchdog<Void>(",
      "timeout: Self.controlCallbackTimeout",
      "resumeWatchdog = watchdog",
      "try await watchdog.wait()",
    ]) && containsInOrder(onProgress, [
      "completionWatchdog.heartbeat()",
      "progress(update)",
    ]) && containsInOrder(onPause, [
      "lock.lock()",
      "let watchdog = pauseWatchdog",
      "pauseWatchdog = nil",
      "lock.unlock()",
      "completionWatchdog.suspendTimeout()",
      "watchdog?.resolve(result)",
    ]) && containsInOrder(onResume, [
      "lock.lock()",
      "let watchdog = resumeWatchdog",
      "resumeWatchdog = nil",
      "lock.unlock()",
      "completionWatchdog.resumeTimeout()",
      "watchdog?.succeed(())",
    ]) && containsInOrder(finish, [
      "guard terminalResult == nil else",
      "terminalResult = result",
      "pauseWatchdog = nil",
      "resumeWatchdog = nil",
      "lock.unlock()",
      "completionWatchdog.resolve(result)",
      "pause?.resolve(result)",
      "resume?.resolve(result)",
    ]);
}
if (!transferBridgePreservesFiniteLifecycle(downloadBridgeCode) ||
    !transferBridgePreservesFiniteLifecycle(catalogUpdateBridgeCode) ||
    !containsInOrder(nativeDownloadRegionsCode, [
      "let bridge = HereDownloadProgressBridge(",
      "let task = downloader.downloadRegions(",
      "try await bridge.waitForCompletion",
      "task.cancel()",
    ]) || !containsInOrder(nativeUpdatePersistentMapCode, [
      "let bridge = HereCatalogUpdateProgressBridge(",
      "let task = updater.updateCatalog(",
      "try await bridge.waitForCompletion",
      "task.cancel()",
    ]) || !containsInOrder(nativePauseTransferCode, [
      "task.pause()",
      "try await bridge.waitForPause()",
      "task.pause()",
      "try await bridge.waitForPause()",
    ]) || !containsInOrder(nativeResumeTransferCode, [
      "task.resume()",
      "try await bridge.waitForResume()",
      "task.resume()",
      "try await bridge.waitForResume()",
    ]) || !containsInOrder(nativeCancelTransferCode, [
      "task.cancel()",
      "bridge.resolveCancellation()",
      "task.cancel()",
      "bridge.resolveCancellation()",
    ])) {
  failures.push("HERE download and catalog-update bridges no longer heartbeat finite completion waits, suspend inactivity while paused, bound control callbacks, and cancel native work exactly through the owned bridge");
}

if (!containsInOrder(navigationInterruptionReceiveCode, [
  "guard sessionIsActive else",
  "state = .clear",
  "case .began:",
  "guard state != .interrupted else { return .none }",
  "state = .interrupted",
  "return .pauseAndMute",
  "case .ended(let shouldResume):",
  "guard state == .interrupted else { return .none }",
  "guard shouldResume else",
  "state = .resumeDenied",
  "return .remainPaused",
  "state = .awaitingFreshLocation(notBefore: now)",
  "return .prepareAudioAndAwaitFreshLocation",
]) || !containsInOrder(navigationAcceptFreshLocationCode, [
  "guard case .awaitingFreshLocation(let notBefore) = state",
  "observedAt >= notBefore else { return false }",
  "state = .clear",
  "return true",
]) || !containsInOrder(navigationPermitsCallbackCode, [
  "guard !interruptionBoundary.blocksNativeCallbacks else { return false }",
  "HereNavigationNativeCallbackBoundary.permits(",
])) {
  failures.push("HERE navigation interruption boundary no longer mutes native callbacks until the system authorizes resume and a not-before fresh location is accepted");
}
if (!containsInOrder(navigationAudioInterruptionCode, [
  "interruptionBoundary.receive(",
  "sessionIsActive: isActive",
  "guard let routeID = activeRouteID else { return }",
  "case .pauseAndMute:",
  "activeRerouteWatchdog?.interrupt()",
  "invalidateNativeDelegates(on: navigator)",
  "await stopPreparedVoiceOutput()",
  "transition(",
  "case .prepareAudioAndAwaitFreshLocation:",
  "let recoveryGeneration = sessionGeneration",
  "try await prepareVoiceOutputAfterInterruption(",
  "sessionGeneration == recoveryGeneration",
  "activeRouteID == routeID",
  "interruptionBoundary.isAwaitingFreshLocation",
  "interruptionBoundary.rejectResume()",
  "case .remainPaused:",
])) {
  failures.push("HERE navigation audio interruption handling no longer cancels reroute, removes delegates, mutes voice, and requires generation-bound audio recovery before awaiting a fresh fix");
}
if (!containsInOrder(navigationFeedCode, [
  "timestampBoundary.acceptDeviceLocation(",
  "resolvePointCoverage(",
  "activeRouteID == routeID",
  "let resumesAfterInterruption = interruptionBoundary.acceptFreshLocation(",
  "observedAt: location.timestamp",
  "if resumesAfterInterruption",
  "installNativeDelegates(on: navigator)",
  "transition(.navigating(routeID: routeID, coverage: currentCoverage))",
  "navigator.onLocationUpdated(nativeLocation)",
])) {
  failures.push("HERE navigation no longer resumes after interruption only from a timestamp-valid, signed-coverage-admitted fresh device fix");
}
if (!containsInOrder(productionInstallCode, [
  "AVAudioSession.interruptionNotification",
  "AVAudioSessionInterruptionTypeKey",
  "case .began:",
  "interruption = .began",
  "case .ended:",
  "AVAudioSessionInterruptionOptionKey",
  "shouldResume: options.contains(.shouldResume)",
  "await composition?.handleAudioInterruption(interruption)",
  "UIApplication.didEnterBackgroundNotification",
  "await composition?.handleApplicationPhase(.background)",
  "UIApplication.willEnterForegroundNotification",
  "await composition?.handleApplicationPhase(.active)",
])) {
  failures.push("offline production composition no longer observes typed audio interruptions and application background/foreground edges");
}
if (!containsInOrder(productionApplicationPhaseCode, [
  "applicationPhase = phase",
  "case .background:",
  "guard backgroundPausedTransferID == nil",
  "let operation = owner.snapshot.activeOperation",
  "operation.phase == .running",
  "operation.kind == .downloadRegions",
  "operation.kind == .updatePersistentMap",
  "try await owner.coordinator.pauseActiveTransfer()",
  "owner.snapshot.activeOperation?.id == operation.id",
  "owner.snapshot.activeOperation?.phase == .paused",
  "guard applicationPhase == .background else",
  "try? await owner.coordinator.resumeActiveTransfer()",
  "backgroundPausedTransferID = operation.id",
  "case .active:",
  "guard let operationID = backgroundPausedTransferID else { return }",
  "backgroundPausedTransferID = nil",
  "operation.id == operationID",
  "operation.phase == .paused",
  "try? await owner.coordinator.resumeActiveTransfer()",
  "if applicationPhase == .background",
  "await handleApplicationPhase(.background)",
])) {
  failures.push("offline production background handling no longer pauses only an owned running transfer and resumes only the same paused operation after a foreground edge");
}

if (!containsInOrder(nativeMapSetProjectionCode, [
  "journeyProjection = projection",
  "guard case .rendered = snapshot.status else { return }",
  "try applyJourneyProjection(projection)",
  "journeyProjection = .empty",
  "replaceWithOpaqueFailure(failure)",
])) {
  failures.push("HERE native journey projection no longer retains pre-render state and fails opaque when applying that state is rejected");
}
if (!containsInOrder(nativeMapApplyProjectionCode, [
  "guard projection.route == nil || projection.canonicalRoute == nil else",
  "let selectedRoute:",
  "if let route = projection.route",
  "guard route.provenance == .hereOfflineLocal",
  "route.mode.supportsHEREOfflineCalculation else",
  "let signature = HereOfflineMapProjectedRouteSignature.local(route)",
  "signature.coordinateComponents",
  "else if let route = projection.canonicalRoute",
  "guard route.provenance == .serverCanonical",
  "route.mode == .rail || route.mode == .vessel",
  "route.segments.allSatisfy({ $0.mode == route.mode }) else",
  "let signature = HereOfflineMapProjectedRouteSignature.canonical(route)",
  "signature.coordinateComponents",
  "if selectedRoute?.signature != projectedRouteSignature",
  "for polyline in nativeRoutePolylines",
  "removeMapPolyline(polyline)",
  "nativeRoutePolylines = []",
  "if let route = selectedRoute",
  "let coordinateComponents = route.coordinateComponents",
  "guard !coordinateComponents.isEmpty",
  "coordinateComponents.allSatisfy({ $0.count >= 2 }) else",
  "let nativeCoordinateComponents = coordinateComponents.map",
  "let polylines = try nativeCoordinateComponents.map",
  "try MapPolyline(",
  "geometry: GeoPolyline(vertices: coordinates)",
  "for polyline in polylines",
  "mapView.mapScene.addMapPolyline(polyline)",
  "nativeRoutePolylines = polylines",
  "projectedRouteSignature = route.signature",
  "guard let position = projection.position else",
  "nativeLocationIndicator?.disable()",
  "let indicator: LocationIndicator",
  "indicator = LocationIndicator()",
  "indicator.locationIndicatorStyle = .navigation",
  "indicator.isAccuracyVisualized = true",
  "indicator.enable(for: mapView)",
  "indicator.updateLocation(location)",
  "if projection.followsPosition",
  "mapView.camera.lookAt(",
])) {
  failures.push("HERE native journey projection no longer enforces mutually exclusive verified local-road/server-canonical Rail-or-Vessel geometry or renders route and live location with follow camera");
}
if (!containsInOrder(nativeMapRemoveProjectionCode, [
  "for polyline in nativeRoutePolylines",
  "removeMapPolyline(polyline)",
  "nativeRoutePolylines = []",
  "projectedRouteSignature = nil",
  "nativeLocationIndicator?.disable()",
  "nativeLocationIndicator = nil",
])) {
  failures.push("HERE native journey projection no longer removes both route polyline and location indicator artifacts");
}
if (!containsInOrder(nativeMapOpaqueFailureCode, [
  "nativeSceneLoadTask?.cancel()",
  "removeNativeJourneyProjection()",
  "releaseRuntimeRenderingLease()",
  "nativeMapView = nil",
  "status: .opaqueUnavailable(failure: failure)",
]) || !containsInOrder(nativeMapClearCode, [
  "journeyProjection = .empty",
  "replaceWithOpaqueFailure(failure)",
])) {
  failures.push("HERE native map clear and opaque failure no longer remove projection artifacts before discarding the native surface");
}
if (!containsInOrder(productionStartNavigationCode, [
  "try await self.startNavigationOperation(route)",
  "self.mapSurface.setJourneyRoute(route)",
  "try self.locationSource.start(",
]) || !containsInOrder(productionAcceptDeviceLocationCode, [
  "guard acceptsDeviceLocations else { return }",
  "let projectedPosition = try HereOfflineMapJourneyPosition(",
  "try await feedLocationOperation(fix)",
  "mapSurface.updateLivePosition(",
  "projectedPosition",
  "followsPosition: true",
]) || !containsInOrder(productionStopNavigationCode, [
  "locationSource.stop()",
  "await stopNavigationOperation()",
  "mapSurface.clearLivePosition()",
])) {
  failures.push("offline production composition no longer projects only a started verified route and navigation-accepted device fixes while clearing live position on stop");
}
if (!containsInOrder(roadNativeJourneyMapCode, [
  "OfflineNativeCoverageMapSurfaceHost(",
  "composition: composition",
  "offlineSnapshot: owner.snapshot",
  "family: .navigation",
  "journeyProjection: journeyProjection",
]) || !containsInOrder(roadJourneyProjectionCode, [
  "model.locationFix.flatMap",
  "HereOfflineMapJourneyPosition(",
  "composition.navigationRoute.flatMap",
  "model.selectedRoute?.id == navigationRoute.id",
  "? navigationRoute",
  "?? model.selectedRoute",
  "route: route",
  "position: position",
  "followsPosition: model.navigationIsActive",
]) || !containsInOrder(nativeMapHostReconcileCode, [
  "composition.prepareMapSurface(",
  "ownsSurface = true",
  "mountedIdentity = identity",
  "nativeView = view",
  "composition.setMapJourneyProjection(journeyProjection)",
])) {
  failures.push("OfflineRoadJourneyView no longer mounts the reusable native host with selected route/current fix, or the host no longer queues projection immediately after owning the native surface");
}
if (!containsInOrder(canonicalItineraryBodyCode, [
  "package.mode == .rail || package.mode == .vessel",
  "OfflineNativeCoverageMapSurfaceHost(",
  "mode: package.mode == .rail ? .rail : .vessel",
  "family: .operational",
  "journeyProjection: .serverCanonical(package)",
])) {
  failures.push("passive canonical offline itinerary no longer mounts signed Rail/Vessel geometry with the matching native style");
}
if (!containsInOrder(nativeSurfaceHostBodyCode, [
  ".task(id: mountRequest)",
  "mountModel.reconcile(",
  "journeyProjection: journeyProjection",
  ".task(id: appRadioSilenceEligibility)",
  "reconcileAppRadioSilenceLease()",
  ".onDisappear",
  "mountModel.unmount()",
  "releaseAppRadioSilenceLease()",
]) || !containsInOrder(nativeSurfaceHostBlockingCode, [
  "offlineSnapshot.connectivityPolicy == .radioSilent",
  "offlineSnapshot.radioSilenceState == .enforced",
  "guard AppRadioSilenceCoordinator.shared.isEnforced else",
  "composition.installedCoverageTrustAvailable",
  "offlineSnapshot.installedRegionsState.isCurrent",
  "offlineSnapshot.installedRegions.contains(where: { $0.state.isUsableCoverage })",
  "offlineSnapshot.availableCapabilities.contains(.detailedRendering)",
]) || !containsInOrder(nativeSurfaceHostReconcileLeaseCode, [
  "if appRadioSilenceEligibility",
  "guard appRadioSilenceLease == nil else { return }",
  "AppRadioSilenceCoordinator.shared.acquire(",
  "reason: .offlineMapLibrary",
  "else",
  "releaseAppRadioSilenceLease()",
]) || !containsInOrder(nativeSurfaceHostLeaseEligibilityCode, [
  "acquiresAppRadioSilenceLease",
  "offlineSnapshot.connectivityPolicy == .radioSilent",
  "offlineSnapshot.radioSilenceState == .enforced",
]) || !containsInOrder(nativeSurfaceHostReleaseLeaseCode, [
  "guard let lease = appRadioSilenceLease else { return }",
  "AppRadioSilenceCoordinator.shared.release(lease)",
  "appRadioSilenceLease = nil",
])) {
  failures.push("reusable native map host no longer keeps lease ownership opt-in, restricts nested acquisition to an already enforced radio-silent snapshot, and blocks rendering until app/native enforcement are proven");
}
if (!mapLibraryCode.includes("acquiresAppRadioSilenceLease: Bool = false") ||
    !mapLibraryCode.includes("acquiresAppRadioSilenceLease: true") ||
    roadNativeJourneyMapCode.includes("acquiresAppRadioSilenceLease: true") ||
    canonicalItineraryBodyCode.includes("acquiresAppRadioSilenceLease: true")) {
  failures.push("native map lease ownership no longer remains explicit for the library preview while Road uses its parent lease and passive canonical fallback owns no lease");
}
const compositionTargetBound = exists(relative.productionComposition) &&
  projectInspector.sourceRegistered(relative.productionComposition) &&
  gitPathIsTrackedAndUnchanged(relative.productionComposition);
const compositionInstalledAtAppEntry =
  /\bOfflineMapProductionComposition\.install\s*\(/.test(appLifecycleCode);
const approvedProductionComposition = compositionTargetBound && compositionInstalledAtAppEntry
  ? productionInstallCode
  : "";
if (!containsInOrder(mapSurfacePrepareCode, [
  "snapshot.connectivityPolicy == .radioSilent",
  "snapshot.radioSilenceState == .enforced",
  "installedCoverageTrustAvailable",
  "snapshot.installedRegionsState.isCurrent",
  "state.isUsableCoverage",
  ".detailedRendering",
  "mapSurfaceLeaseState.reserve",
  "mapSurface.prepare",
])) {
  failures.push("native map preparation does not enforce radio silence, signed usable coverage, rendering capability, and lease ownership in one function body");
}
if (!containsInOrder(canonicalDownloadCode, [
  "subject.validate()",
  "principal.scope(for: subject)",
  "transport.getOfflinePackage(subject: subject)",
  "Self.validatedEnvelope(wireEnvelope)",
  "Self.validateSignedPayload(",
  "expectedScope: expectedScope",
  "expectedMode: subject.expectedRouteMode",
])) {
  failures.push("canonical route download no longer validates the signed payload against the authenticated principal scope and freight mode");
}
if (!containsInOrder(canonicalReadCode, [
  "subject.validate()",
  "principal.scope(for: subject)",
  "maximumServerObservationAge: Self.maximumServerObservationAge",
  "composition.observeCanonicalRoute(",
  "package.scope == scope",
  "package.mode == subject.expectedRouteMode",
])) {
  failures.push("canonical offline route read no longer binds freshness, scope, and mode in its executable function body");
}
const railSecureAccountRechecks = (
  railSecureCode.match(/session\.user\?\.id\s*==\s*authenticatedUser\.id/g) ?? []
).length;
const vesselSecureAccountRechecks = (
  vesselSecureCode.match(/session\.user\?\.id\s*==\s*authenticatedUser\.id/g) ?? []
).length;
if (!containsInOrder(railSecureCode, [
  "CanonicalRoutePlanClient().download(",
  "subject: .railShipment",
  "composition.ingestCanonicalRoutePlan(",
]) || railSecureAccountRechecks < 2 ||
    !containsInOrder(railRestoreCode, [
      "CanonicalRouteOfflineReader(",
      ".freshPackage(",
      "subject: .railShipment",
      "session.user?.id == authenticatedUser.id",
    ])) {
  failures.push("Rail offline route caller no longer preserves account rechecks around signed download, ingest, and restore");
}
if (!containsInOrder(vesselSecureCode, [
  "CanonicalRoutePlanClient().download(",
  "subject: .vesselShipment",
  "composition.ingestCanonicalRoutePlan(",
]) || vesselSecureAccountRechecks < 2 ||
    !containsInOrder(vesselRestoreCode, [
      "CanonicalRouteOfflineReader(",
      ".freshPackage(",
      "subject: .vesselShipment",
      "session.user?.id == authenticatedUser.id",
    ])) {
  failures.push("Vessel offline route caller no longer preserves account rechecks around signed download, ingest, and restore");
}
if (!containsInOrder(roadBindPrincipalCode, [
  "composition.activatePrincipal(",
  "tenantID: scope?.tenantID",
  "userID: scope?.userID",
  "activePrincipal == scope",
  "composition.prepare()",
])) {
  failures.push("offline road journey no longer binds preparation to the exact signed-in tenant and user");
}
if (!containsInOrder(roadSearchCode, [
  "locationProvider.freshFix()",
  "requireCurrent(generation)",
  "composition.searchOffline(",
  "center: fix.coordinate",
  "requireCurrent(generation)",
])) {
  failures.push("offline search no longer consumes a fresh precise fix in the active principal generation");
}
if (!containsInOrder(roadCalculateCode, [
  "truckDraft.constraints()",
  "locationProvider.freshFix()",
  "requireCurrent(generation)",
  "composition.calculateOfflineRoute(",
  "coordinate: fix.coordinate",
  "coordinate: destination.coordinate",
  "mode: requestedMode",
  "truckConstraints: constraints",
  "signature == self.routeSignature",
])) {
  failures.push("offline road/truck routing no longer binds explicit constraints, fresh origin, selected destination, and input generation");
}
if (!containsInOrder(roadStartGuidanceCode, [
  "selectedRouteMatchesInputs",
  "operationBlockReason(requireGuidance: true)",
  "composition.startNavigation(route: route)",
  "requireCurrent(generation)",
])) {
  failures.push("offline guidance no longer rechecks route inputs and readiness before native start");
}
if (!compositionTargetBound || !compositionInstalledAtAppEntry || !productionInstallCode) {
  blockers.push("approved offline production composition is not target-bound and installed from the app entry point");
}
if (!projectInspector.sourceRegistered(relative.settingsHost) ||
    !/\bOfflineMapManagementView\s*\(/.test(settingsHostCode)) {
  blockers.push("offline map management has no target-bound Catalyst settings caller");
}
if (!projectInspector.sourceRegistered(relative.roadJourneyView) ||
    !projectInspector.sourceRegistered(relative.mapLibraryView) ||
    !/\bOfflineRoadJourneyView\s*\(/.test(mapLibraryCode)) {
  blockers.push("offline road/truck journey has no target-bound map-library entry point");
}
if (!projectInspector.sourceRegistered(relative.driverEnRouteView) ||
    !/\bOfflineRoadJourneyView\s*\(/.test(driverEnRouteCode) ||
    !/\bOfflineDriverTurnBanner\s*\(/.test(driverEnRouteCode) ||
    !/\.fullScreenCover\s*\(/.test(driverEnRouteCode)) {
  blockers.push("offline road/truck journey has no target-bound Driver en-route entry and live guidance surface");
}
if (!projectInspector.sourceRegistered(relative.railRouteCaller) ||
    !projectInspector.sourceRegistered(relative.vesselRouteCaller)) {
  blockers.push("signed Rail/Vessel offline callers are not both registered in the application target");
}
if (!/\bOfflineNativeCoverageMapSurfaceHost\b/.test(mapLibraryCode) ||
    !/\bprepareMapSurface\s*\(/.test(mapLibraryCode) ||
    !/\bclearMapSurface\s*\(/.test(mapLibraryCode) ||
    !/\bHereNavigateOfflineMapSurface\b/.test(approvedProductionComposition) ||
    !/\bownerToken:\s*UUID\b/.test(productionCompositionCode)) {
  blockers.push("approved native offline map surface has no target-bound production mount");
}
if (!/\bCanonicalRoutePackageStore\s*\(/.test(approvedProductionComposition)) {
  blockers.push("signed canonical route store has no approved production route.plan decoder/use-site caller");
}
if (!/\bpurgeAllCachedRoutes\s*\(/.test(approvedProductionComposition)) {
  blockers.push("canonical route cache purge is not wired through the approved production composition");
}
if (!/\bOfflineSearchRequest\s*\(/.test(approvedProductionComposition) ||
    !/\.searchOffline\s*\(/.test(approvedProductionComposition) ||
    !/\bcomposition\.searchOffline\s*\(/.test(roadJourneyCode)) {
  blockers.push("offline search has no approved target-bound request/result caller");
}
if (!/\bOfflineRouteRequest\s*\(/.test(approvedProductionComposition) ||
    !/\.calculateOfflineRoute\s*\(/.test(approvedProductionComposition) ||
    !/\bcomposition\.calculateOfflineRoute\s*\(/.test(roadJourneyCode)) {
  blockers.push("offline road/truck routing has no approved target-bound caller");
}
if (!/\bmakeNavigationSession\s*\(/.test(approvedProductionComposition) ||
    !/\.start\s*\(\s*route:/.test(approvedProductionComposition) ||
    !/\.stop\s*\(/.test(approvedProductionComposition) ||
    !/\bcomposition\.startNavigation\s*\(\s*route:/.test(roadJourneyCode) ||
    !/\bcomposition\.stopNavigation\s*\(/.test(roadJourneyCode)) {
  blockers.push("offline navigation start/stop has no approved target-bound lifecycle owner");
}
if (!/\bOfflineDeviceLocationSample\s*\(/.test(approvedProductionComposition) ||
    !/\.feed\s*\(\s*location:/.test(approvedProductionComposition) ||
    !/\bkCLLocationAccuracyBestForNavigation\b/.test(roadJourneyCode) ||
    !/\baccuracyAuthorization\s*==\s*\.fullAccuracy\b/.test(roadJourneyCode)) {
  blockers.push("device GNSS samples are not wired through the approved production composition");
}
if (!/\.coverageChanged\s*\(/.test(approvedProductionComposition) ||
    !/\.outsideInstalledCoverage\s*\(/.test(approvedProductionComposition)) {
  blockers.push("installed-region boundary events have no approved production consumer");
}
if (!/\bHereNavigationVoicePolicy\s*\(/.test(approvedProductionComposition)) {
  blockers.push("device-local offline voice policy has no approved target-bound caller");
}
const installedCoverageProductionCode = [
  approvedProductionComposition,
  exists(relative.coverageAdapter) ? swiftCodeOnly(read(relative.coverageAdapter)) : "",
  exists(relative.navigateEngine) ? swiftCodeOnly(read(relative.navigateEngine)) : "",
  exists(relative.navigation) ? swiftCodeOnly(read(relative.navigation)) : "",
].join("\n");
if (!/\bSignedInstalledCoverageResolver\s*\(/.test(approvedProductionComposition) ||
    !/\.resolveInstalledCoverage\s*\(/.test(installedCoverageProductionCode) ||
    !/\bcurrentHEREInstalledRegionInventory\s*\(/.test(installedCoverageProductionCode)) {
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
} else if (manifest && styleManifest && coverageTrust) {
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
  const expectedBundledCoverageTrust = path.join(
    builtAppPath,
    path.basename(relative.coverageTrust),
  );
  const bundledCoverageTrustDocuments = productFiles.filter(file =>
    path.basename(file) === path.basename(relative.coverageTrust));
  if (bundledCoverageTrustDocuments.length !== 1 ||
      path.resolve(bundledCoverageTrustDocuments[0]) !==
        path.resolve(expectedBundledCoverageTrust)) {
    failures.push("built EusoTrip.app must contain exactly one installed-coverage trust document at the bundle root");
  } else if (sha256(bundledCoverageTrustDocuments[0]) !==
             sha256(absolute(relative.coverageTrust))) {
    failures.push("built installed-coverage trust document differs from the approved source document");
  }
  if (coverageTrust.status === "approved") {
    const coverageManifestRelative =
      `${relative.offlineRoot}/${coverageTrust.initialSignedManifestResource}`;
    const expectedBundledCoverageManifest = path.join(
      builtAppPath,
      coverageTrust.initialSignedManifestResource,
    );
    const bundledCoverageManifests = productFiles.filter(file =>
      path.basename(file) === coverageTrust.initialSignedManifestResource);
    if (bundledCoverageManifests.length !== 1 ||
        path.resolve(bundledCoverageManifests[0]) !==
          path.resolve(expectedBundledCoverageManifest)) {
      failures.push("built EusoTrip.app must contain exactly one approved signed installed-coverage manifest at the bundle root");
    } else if (exists(coverageManifestRelative) &&
               sha256(bundledCoverageManifests[0]) !==
                 sha256(absolute(coverageManifestRelative))) {
      failures.push("built signed installed-coverage manifest differs from the approved source manifest");
    }
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
