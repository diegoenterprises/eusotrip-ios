#!/usr/bin/env node

import { readFileSync, existsSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const metricFiles = [
  "EusoTrip/Views/Rail/655_RailLossPrevention.swift",
  "EusoTrip/Views/Vessel/805_VesselLossPrevention.swift",
  "EusoTrip/Views/Rail/659_RailClaimsAnalytics.swift",
  "EusoTrip/Views/Vessel/811_VesselClaimsAnalytics.swift",
  "EusoTrip/Views/Rail/656_RailClaimPayments.swift",
  "EusoTrip/Views/Vessel/802_VesselClaimPayments.swift",
  "EusoTrip/Views/Rail/669_RailOverchargeRecovery.swift",
  "EusoTrip/Views/Vessel/804_VesselOverchargeRecovery.swift",
  "EusoTrip/Views/Rail/670_RailShortageClaims.swift",
];
const lifecycleFiles = [
  "EusoTrip/Services/EusoTripAPI.swift",
  "EusoTrip/Views/Rail/605_RailCargoClaim.swift",
  "EusoTrip/Views/Rail/654_RailClaimWorkflow.swift",
  "EusoTrip/Views/Vessel/808_VesselClaimWorkflow.swift",
];
const files = [...metricFiles, ...lifecycleFiles];

const sources = new Map();
const failures = [];

for (const relativePath of files) {
  const absolutePath = resolve(repoRoot, relativePath);
  if (!existsSync(absolutePath)) {
    failures.push(`${relativePath}: missing owned consumer`);
    continue;
  }
  sources.set(relativePath, readFileSync(absolutePath, "utf8"));
}

const observedAt = "2026-08-21T12:00:00.000Z";
const computedAt = "2026-08-21T12:01:00.000Z";
const measuredTruth = {
  valueState: "measured",
  accessState: "granted",
  trackingState: "tracked",
  provenance: { source: "incidents", observedAt, computedAt, basis: "fixture measurement" },
  reason: null,
};
const noObservationsTruth = {
  valueState: "no_observations",
  accessState: "granted",
  trackingState: "tracked",
  provenance: { source: "incidents", observedAt: null, computedAt, basis: "fixture scope" },
  reason: "No scoped observations were recorded",
};
const notModeledTruth = {
  valueState: "not_modeled",
  accessState: "granted",
  trackingState: "not_tracked",
  provenance: { source: null, observedAt: null, computedAt, basis: null },
  reason: "No modeled source exists",
};

function lossDashboardFixture(mode) {
  return {
    transportMode: mode,
    metrics: {
      totalLosses: 1,
      lossValue: 1250,
      lossValueCurrency: "USD",
      totalsByCurrency: [{ currency: "USD", amount: 1250 }],
      unvaluedLossCount: 0,
      preventedLosses: null,
      preventionSavings: null,
      preventionSavingsCurrency: null,
      lossRatio: 0.25,
      lossRatioBasis: "physical_loss_claims_divided_by_all_claims",
      trendDirection: "stable",
    },
    alerts: [],
    topRiskLanes: [],
    metricStates: {
      totalLosses: measuredTruth,
      lossValue: measuredTruth,
      preventedLosses: notModeledTruth,
      preventionSavings: notModeledTruth,
      lossRatio: measuredTruth,
      trendDirection: measuredTruth,
    },
    provenance: {
      source: "incidents",
      recordKind: "freight_claim",
      scope: "transaction_party_company",
      transportMode: mode,
      observedAt,
      computedAt,
    },
  };
}

function lossAnalysisFixture(mode) {
  return {
    groupBy: mode === "RAIL" ? "lane" : "commodity",
    period: "year",
    transportMode: mode,
    periodStart: "2025-08-21T00:00:00.000Z",
    data: [],
    recommendations: [],
    unclassifiedCount: 0,
    provenance: {
      source: "incidents",
      recordKind: "freight_claim",
      derivation: "tenant-scoped physical-loss claims",
      transportMode: mode,
      observedAt: null,
      computedAt,
    },
  };
}

function analyticsFixture(mode) {
  return {
    period: "year",
    transportMode: mode,
    periodStart: "2025-08-21T00:00:00.000Z",
    frequency: 1,
    avgCost: 1250,
    avgCostCurrency: "USD",
    totalsByCurrency: [{ currency: "USD", amount: 1250 }],
    unvaluedCount: 0,
    avgResolutionDays: 2.5,
    avgCostByCurrency: [{ currency: "USD", amount: 1250, count: 1 }],
    byType: [],
    byMonth: [],
    byStatus: [],
    topCarriers: [],
    recoveryRate: 1,
    recoveryRateBasis: "paid_claim_status_count_divided_by_all_scoped_claim_records",
    metricStates: {
      frequency: measuredTruth,
      avgCost: measuredTruth,
      unvaluedCount: measuredTruth,
      avgResolutionDays: measuredTruth,
      recoveryRate: measuredTruth,
    },
    provenance: {
      source: "incidents",
      recordKind: "freight_claim",
      scope: "transaction_party_company",
      transportMode: mode,
      observedAt,
      computedAt,
    },
  };
}

const runtimeFixtures = [
  {
    path: files[0],
    screenMarker: "struct RailLossPreventionScreen",
    decodes: [
      ["LossPreventionDashboard655", lossDashboardFixture("RAIL")],
      ["LossPreventionAnalysis655", lossAnalysisFixture("RAIL")],
    ],
  },
  {
    path: files[1],
    screenMarker: "struct VesselLossPreventionScreen",
    decodes: [
      ["LossDashboard805", lossDashboardFixture("VESSEL")],
      ["LossAnalysis805", lossAnalysisFixture("VESSEL")],
    ],
  },
  {
    path: files[2],
    screenMarker: "private struct RailClaimsAnalyticsBody",
    decodes: [["ClaimsAnalytics659", analyticsFixture("RAIL")]],
  },
  {
    path: files[3],
    screenMarker: "struct VesselClaimsAnalyticsScreen",
    decodes: [["Analytics811", analyticsFixture("VESSEL")]],
  },
  {
    path: files[8],
    screenMarker: "struct RailShortageClaimsScreen",
    decodes: [["ShortageClaimsResp670", {
      transportMode: "RAIL",
      claims: [],
      total: 0,
      summary: {
        totalShortages: 0,
        totalMatchingClaims: 0,
        scope: { kind: "current_page", offset: 0, limit: 20, returnedCount: 0 },
        totalValue: null,
        totalValueCurrency: null,
        totalsByCurrency: [],
        unvaluedCount: 0,
        avgShortagePercent: null,
        unreconciledCount: 0,
        topCommodities: [],
        metricStates: {
          totalShortages: noObservationsTruth,
          totalValue: noObservationsTruth,
          avgShortagePercent: noObservationsTruth,
        },
      },
      provenance: {
        source: "incidents expectedQuantity+receivedQuantity+quantityUnit+claimDetails",
        recordKind: "freight_claim",
        scope: "current_page",
        transportMode: "RAIL",
        observedAt: null,
        computedAt,
      },
    }]],
  },
];

const runtimeDirectory = mkdtempSync(join(tmpdir(), "eusotrip-claim-decoders-"));
try {
  for (const fixture of runtimeFixtures) {
    const source = sources.get(fixture.path);
    if (!source) continue;
    const modelStart = source.indexOf("private struct");
    const modelEnd = source.indexOf(fixture.screenMarker);
    if (modelStart < 0 || modelEnd <= modelStart) {
      failures.push(`${fixture.path}: could not isolate runtime decoder models`);
      continue;
    }
    const decodeStatements = fixture.decodes.map(([typeName, payload], index) => {
      const json = JSON.stringify(payload);
      const swiftStringLiteral = JSON.stringify(json);
      return `let payload${index} = ${swiftStringLiteral}.data(using: .utf8)!\n` +
        `_ = try! JSONDecoder().decode(${typeName}.self, from: payload${index})`;
    }).join("\n");
    const swiftSource = `import Foundation\n\n${source.slice(modelStart, modelEnd)}\n${decodeStatements}\n`;
    const swiftPath = join(runtimeDirectory, "main.swift");
    const binaryPath = join(runtimeDirectory, "decoder-check");
    writeFileSync(swiftPath, swiftSource);
    const compile = spawnSync("xcrun", ["swiftc", swiftPath, "-o", binaryPath], { encoding: "utf8" });
    if (compile.status !== 0) {
      failures.push(`${fixture.path}: runtime decoder compile failed: ${(compile.stderr || compile.stdout).trim()}`);
      continue;
    }
    const execute = spawnSync(binaryPath, [], { encoding: "utf8" });
    if (execute.status !== 0) {
      failures.push(`${fixture.path}: live-shaped JSON decoder failed: ${(execute.stderr || execute.stdout).trim()}`);
    }
  }
} finally {
  rmSync(runtimeDirectory, { recursive: true, force: true });
}

const forbidden = [
  [/\?\?\s*0(?:\.0)?\b/g, "unknown numeric value collapses to zero"],
  [/currencyCode\s*=\s*"USD"/g, "hard-coded USD formatter"],
  [/trendDirection\s*\?\?\s*"stable"/g, "missing trend collapses to stable"],
  [/\brecoveredExposure\b|\btotalExposure\b/g, "fabricated recovered-dollar exposure"],
  [/\bclaimed\s*\*\s*(?:r|recoveryRate)\b/g, "recovered money derived from claim value and rate"],
  [/\brecoveryRate\s*\*\s*\w+/g, "recovered money derived from recovery rate"],
  [/\bmeasuredAt\b/g, "stale metric provenance field measuredAt"],
  [/\bgeneratedAt\b/g, "stale metric provenance field generatedAt"],
  [/Transport-mode dimension unavailable/g, "false all-mode aggregation copy"],
];

for (const relativePath of metricFiles) {
  const source = sources.get(relativePath);
  if (!source) continue;
  for (const [pattern, label] of forbidden) {
    pattern.lastIndex = 0;
    if (pattern.test(source)) failures.push(`${relativePath}: ${label}`);
  }
}

const requirements = new Map([
  [files[0], ["metricStates", "totalsByCurrency", "preventionSavings", "computedAt", "accessState", "trackingState", "metricUnavailableLabel", "Not modeled", 'transportMode: "RAIL"']],
  [files[1], ["metricStates", "totalsByCurrency", "preventionSavings", "computedAt", "accessState", "trackingState", "metricUnavailableLabel", "Not modeled", 'transportMode: "VESSEL"']],
  [files[2], ["metricStates", "avgCostByCurrency", "totalsByCurrency", "computedAt", "accessState", "trackingState", "metricUnavailableLabel", "PAID STATUS / ALL SCOPED CLAIMS", 'transportMode: "RAIL"']],
  [files[3], ["metricStates", "avgCostByCurrency", "totalsByCurrency", "computedAt", "accessState", "trackingState", "metricUnavailableLabel", "PAID CLAIM STATUS / ALL SCOPED CLAIMS", 'transportMode: "VESSEL"']],
  [files[4], ["currency", "totalCurrency", "totalsByCurrency", "metricStates", "pageScope", "provenance", 'transportMode: "RAIL"']],
  [files[5], ["currency", "totalCurrency", "totalsByCurrency", "metricStates", "pageScope", "provenance", 'transportMode: "VESSEL"']],
  [files[6], ["Double?", "tracking", "metricStates", "pageScope", "provenance", "NOT MODELED FOR RAIL", 'transportMode: "RAIL"']],
  [files[7], ["Double?", "tracking", "metricStates", "pageScope", "provenance", "NOT MODELED FOR VESSEL", 'transportMode: "VESSEL"']],
  [files[8], ["metricStates", "quantityUnit", "transportMode", "totalMatchingClaims", "totalsByCurrency", "scope", "computedAt", "accessState", "trackingState", "metricUnavailableLabel", 'transportMode: "RAIL"']],
  [lifecycleFiles[0], [
    "struct CurrencyCode",
    "Locale.Currency.isoCurrencies",
    "Self.recognizedCodes.contains(canonical)",
    "enum ClaimAssetType",
    "enum ClaimAssetProvenance",
    "enum ClaimDeadlineType",
    "enum ClaimDeadlineAuthority",
    "enum ClaimReserveStatus",
    "struct ClaimAssignmentJurisdiction",
    "struct ClaimAssignmentVerification",
    "let specialistProfileId: String?",
    "let conflictAttestation: String?",
    "let assignmentStatus: String",
    "func recordClaimAsset(",
    '"freightClaims.recordClaimAsset"',
    "func recordClaimDeadline(",
    '"freightClaims.recordClaimDeadline"',
    "func setClaimReserve(",
    '"freightClaims.setClaimReserve"',
    "requestKey.uuidString.lowercased()",
    "ISO8601DateFormatter().string(from: dueAt)",
  ]],
  [lifecycleFiles[1], [
    "struct FreightClaimLifecycleRecorder",
    "requiresCompanySelection",
    "ClaimAssetProvenance.allCases",
    "ClaimDeadlineAuthority.allCases",
    "ClaimReserveStatus.allCases",
    "case .rail:",
    "case .vessel:",
    ".railcar",
    ".container",
    ".parcel",
    "requiresSourceReference",
    "requiresSourceProvider",
    "requiresObservedAt",
    "authorityType.requiresCitation",
    "requestFingerprint",
    "recordClaimAsset(",
    "recordClaimDeadline(",
    "setClaimReserve(",
    'refreshed.assetLedger.provenance.source == "freight_claim_assets"',
    'refreshed.deadlineLedger.provenance.source == "freight_claim_deadlines"',
    'refreshed.reserveLedger.provenance.source == "freight_claim_reserves"',
    "persisted.assetType == assetType.rawValue",
    "persisted.deadlineType == deadlineType.rawValue",
  ]],
  [lifecycleFiles[2], [
    "FreightClaimLifecycleRecorder(",
    "claim: $claim",
    "error: $transitionError",
    "mode: .rail",
    'directory.state.provenance.scope == "verified_specialist_directory"',
    'identity.hasPrefix("specialist_profile_")',
    "jurisdiction: directory.jurisdiction",
    'acknowledgement.assignmentStatus == "invited"',
    'record.status == "invited"',
    'record.verification.snapshotState == "recorded"',
    'conflictAttestation: "no_known_conflict"',
    "I attest that I have no known personal, financial, professional, or organizational conflict affecting this claim.",
  ]],
  [lifecycleFiles[3], [
    "FreightClaimLifecycleRecorder(",
    "claim: $claim",
    "error: $transitionError",
    "mode: .vessel",
    'directory.state.provenance.scope == "verified_specialist_directory"',
    'opaqueId.hasPrefix("specialist_profile_")',
    "jurisdiction: directory.jurisdiction",
    'result.assignmentStatus == "invited"',
    'record.status == "invited"',
    'record.verification.snapshotState == "recorded"',
    'conflictAttestation: "no_known_conflict"',
    "I attest that I have no known personal, financial, professional, or organizational conflict affecting this claim.",
  ]],
]);

for (const [relativePath, tokens] of requirements) {
  const source = sources.get(relativePath);
  if (!source) continue;
  for (const token of tokens) {
    if (!source.includes(token)) failures.push(`${relativePath}: missing required contract token ${JSON.stringify(token)}`);
  }
}

for (const relativePath of lifecycleFiles) {
  const source = sources.get(relativePath);
  if (!source) continue;
  const lifecycleForbidden = [
    [/try\?\s+await\s+.*(?:recordClaim(?:Asset|Deadline)|setClaimReserve)/g, "swallows a claim lifecycle write failure"],
    [/(?:recordClaim(?:Asset|Deadline)|setClaimReserve)[\s\S]{0,500}success\s*:\s*true/g, "synthesizes claim lifecycle success"],
    [/claim_respondent_company/g, "uses the retired same-company specialist directory"],
    [/provenance\.source\s*==\s*"users"/g, "trusts an unverified user directory for claim assignment"],
    [/hasPrefix\("user_"\)/g, "accepts a raw user identity as a verified specialist profile"],
  ];
  for (const [pattern, label] of lifecycleForbidden) {
    pattern.lastIndex = 0;
    if (pattern.test(source)) failures.push(`${relativePath}: ${label}`);
  }
}

for (const relativePath of [files[6], files[7]]) {
  const source = sources.get(relativePath);
  if (!source) continue;
  for (const forbiddenAction of ["runFreightAudit", "exportOverchargeRecovery", "Export nominal rows"]) {
    if (source.includes(forbiddenAction)) {
      failures.push(`${relativePath}: exposes truck-only recovery action ${JSON.stringify(forbiddenAction)}`);
    }
  }
}

const vesselDirectory = resolve(repoRoot, "EusoTrip/Views/Vessel");
const vesselShortageCandidates = readdirSync(vesselDirectory)
  .filter((name) => name.endsWith(".swift") && name.toLowerCase().includes("shortage"));
if (vesselShortageCandidates.length > 0) {
  failures.push("A vessel shortage screen exists but is not included in this focused ownership gate");
}

for (const relativePath of files) {
  if (!sources.has(relativePath)) continue;
  const result = spawnSync("xcrun", ["swiftc", "-parse", relativePath], {
    cwd: repoRoot,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    const detail = (result.stderr || result.stdout || "Swift parse failed").trim();
    failures.push(`${relativePath}: ${detail}`);
  }
}

if (failures.length > 0) {
  console.error("Freight-claim iOS truth contract gate failed:\n");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(`Freight-claim iOS truth contract gate passed for ${files.length} owned sources.`);
console.log("Verified metric state retention, live-shaped JSON decoding, ISO currency dimensions, page scope, native rail/vessel lifecycle writes, readback confirmation, forbidden fallbacks, and Swift parse.");
