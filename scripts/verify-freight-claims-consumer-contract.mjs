import { existsSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));

const read = (path) => readFileSync(`${repoRoot}/${path}`, "utf8");
const api = read("EusoTrip/Services/EusoTripAPI.swift");
const store = read("EusoTrip/ViewModels/LiveDataStores.swift");
const driver = read("EusoTrip/Views/Driver/099_MeFreightClaims.swift");
const shipper = read("EusoTrip/Views/Shipper/219_ShipperFreightClaims.swift");
const composer = read("EusoTrip/Views/Shipper/386_FreightClaimComposer.swift");
const settlement = read("EusoTrip/Views/Shipper/294_DisputeSettlement.swift");
const catalyst = read("EusoTrip/Views/Catalyst/389_CatalystCargoClaim.swift");

const apiStart = api.indexOf("struct FreightClaimsAPI {");
const apiEnd = api.indexOf("// MARK: - trackingRouter geofences", apiStart);
if (apiStart < 0 || apiEnd < 0) {
  console.error("Freight-claims consumer verification failed: shared API boundary was not found.");
  process.exit(1);
}

const apiSection = api.slice(apiStart, apiEnd);
const storeStart = store.indexOf("final class FreightClaimsStore");
const storeEnd = store.indexOf("final class", storeStart + 1);
const storeSection = store.slice(storeStart, storeEnd > storeStart ? storeEnd : undefined);
const visibleConsumers = [driver, shipper, composer, settlement, catalyst].join("\n");

const checks = [
  [!visibleConsumers.includes("settlement_dispute"), "unsupported settlement_dispute claim type is absent"],
  [!visibleConsumers.includes("?? 0"), "visible consumers do not coerce unknown numbers to zero"],
  [!visibleConsumers.includes('?? "USD"'), "visible consumers do not invent USD"],
  [!visibleConsumers.includes("try?"), "visible consumers do not swallow claim errors with try?"],
  [driver.includes("@State private var requestKey = UUID()"), "driver filing owns one stable retry key"],
  [driver.includes("FreightClaimsAPI.FileClaimRequest("), "driver filing uses the shared request contract"],
  [driver.includes("reference: .truck("), "driver filing sends one typed TRUCK reference"],
  [driver.includes("requestKey: requestKey"), "driver filing passes its stable retry key"],
  [composer.includes("@State private var fileRequestKey = UUID()"), "shipper composer owns one stable filing key"],
  [composer.includes("@State private var weatherRequestKey = UUID()"), "weather evidence owns a separate stable key"],
  [composer.includes("FreightClaimsAPI.FileClaimRequest("), "shipper composer uses the shared request contract"],
  [composer.includes("reference: .truck(canonicalLoadId)"), "shipper composer sends one typed TRUCK reference"],
  [composer.includes("getClaimById(id: result.claimId)"), "shipper composer reads the filed claim back before confirmation"],
  [!composer.includes("PhotosUI"), "shipper composer does not simulate local evidence upload"],
  [!composer.includes("evidenceBase64"), "shipper composer does not embed an obsolete evidence payload"],
  [shipper.includes("@State private var requestKey = UUID()"), "evidence mutation owns one stable retry key"],
  [shipper.includes("addClaimEvidence("), "evidence uses the canonical mutation"],
  [shipper.includes("requestKey: requestKey"), "evidence mutation passes its stable retry key"],
  [shipper.includes("getClaimById(id: claim.id)"), "evidence mutation verifies canonical claim readback"],
  [shipper.includes('"freightClaims.getDisputeResolution"'), "formal dispute verifies server readback"],
  [settlement.includes("shipperSettlements.dispute("), "settlement dispute uses the settlement domain"],
  [settlement.includes("shipperSettlements.getDetail("), "settlement dispute verifies server readback"],
  [catalyst.includes("@State private var requestKey = UUID()"), "claim decision owns one stable retry key"],
  [catalyst.includes("idempotencyKey: requestKey.uuidString.lowercased()"), "claim decision passes its stable retry key"],
  [catalyst.includes('"freightClaims.submitClaimDecision"'), "claim decision calls the server mutation"],
  [catalyst.includes("getClaimById(id: claim.claimId)"), "claim decision verifies canonical claim readback"],
  [storeSection.includes("fileClaim(_ request: FreightClaimsAPI.FileClaimRequest)"), "shared store accepts the canonical filing request"],
  [storeSection.includes("getClaimById(id: result.claimId)"), "shared store verifies canonical claim readback"],
  [!storeSection.includes("try?"), "shared store does not swallow claim errors"],
  [!storeSection.includes("?? 0"), "shared store does not coerce unknown claim numbers to zero"],
  [apiSection.includes("let amount: Double?"), "claim read amount remains nullable"],
  [apiSection.includes("let currency: CurrencyCode?"), "claim read currency remains nullable"],
  [apiSection.includes("struct FileClaimRequest: Encodable"), "shared filing request remains typed"],
  [apiSection.includes("let amount: Double\n"), "filing amount must be explicit"],
  [apiSection.includes("let currency: CurrencyCode?\n"), "filing currency is explicit and nullable"],
  [apiSection.includes("let type: String?\n"), "evidence type preserves unknown as null"],
  [apiSection.includes("let name: String?\n"), "evidence name preserves unknown as null"],
  [apiSection.includes("let uploadedBy: Int?\n"), "evidence uploader remains a numeric server identity"],
  [!apiSection.includes('?? "USD"'), "shared API does not default filing currency"],
  [apiSection.includes('case measuredByDimension = "measured_by_dimension"'), "shared API exposes measured-by-dimension truth"],
  [apiSection.includes("case partial"), "shared API exposes partial truth"],
  [apiSection.includes('case noObservations = "no_observations"'), "shared API exposes no-observations truth"],
  [apiSection.includes('case notModeled = "not_modeled"'), "shared API exposes not-modeled truth"],
  [apiSection.includes("enum MetricAccessState"), "shared API exposes metric access truth"],
  [apiSection.includes("let accessState: MetricAccessState?"), "shared API retains access while preserving rollout absence as unknown"],
  [apiSection.includes("let metricStates: DashboardMetricStates?"), "dashboard metric truth remains explicit and rollout-compatible"],
  [apiSection.includes("let provenance: DashboardProvenance?"), "dashboard provenance remains explicit and rollout-compatible"],
  [apiSection.includes("let observedAt: String?"), "source observation time remains nullable"],
  [apiSection.includes("let computedAt: String?"), "calculation time remains separate from source freshness"],
  [driver.includes('return measuredZero ? "Measured zero" : "Measured"'), "driver presentation distinguishes measured zero"],
  [driver.includes('"Measured by currency"'), "driver presentation distinguishes dimensioned money"],
  [driver.includes('var parts = ["Partial"]'), "driver presentation preserves partial state"],
  [driver.includes('return "No observations"'), "driver presentation distinguishes no observations"],
  [driver.includes('return "Not modeled"'), "driver presentation distinguishes not modeled"],
  [driver.includes('return "Not tracked"'), "driver presentation distinguishes an untracked metric"],
  [driver.includes("guard truth.accessState == .granted else { return false }"), "driver never displays a restricted metric value"],
  [driver.includes('truth.accessState == .restricted ? "Restricted" : "Access unknown"'), "driver distinguishes restricted access from rollout-unknown access"],
  [driver.includes("Metric access restricted") && driver.includes("Metric access unknown"), "driver proof row preserves restricted and unknown access truth"],
  [driver.includes("d?.metricStates?.open"), "driver open count consumes metric truth"],
  [driver.includes("d?.metricStates?.pending"), "driver pending count consumes metric truth"],
  [driver.includes("d?.metricStates?.resolved"), "driver resolved count consumes metric truth"],
  [driver.includes("d?.metricStates?.denied"), "driver denied count consumes metric truth"],
  [driver.includes("d?.metricStates?.totalValue"), "driver claim value consumes metric truth"],
  [driver.includes("dashboard?.metricStates?.avgResolutionDays"), "driver resolution average consumes metric truth"],
  [driver.includes("dashboard.metricStates?.aging"), "driver aging consumes its truth state"],
  [driver.includes("metric.displaysMeasurement\n                    ?"), "driver hides aging bucket narration when truth is unavailable"],
  [driver.includes("dashboardProofRow(d)"), "driver exposes concise dashboard provenance"],
  [driver.includes("No source observation"), "driver does not borrow a broader timestamp for an empty metric"],
  [driver.includes("calculationLabel(truth.provenance.computedAt)"), "driver exposes metric calculation time"],
  [!driver.includes("truth.provenance.observedAt ?? dashboardProvenance?.observedAt"), "driver never substitutes dashboard freshness for metric freshness"],
  [!driver.includes("truth.provenance.source"), "driver does not expose internal provenance source identifiers"],
  [!driver.includes("truth.provenance.basis"), "driver does not expose internal provenance basis identifiers"],
  [driver.includes(".accessibilityLabel(metric.accessibilityLabel)"), "driver KPI tiles expose metric truth to VoiceOver"],
  [!driver.includes("dashboardMoney("), "driver no longer renders money without metric truth"],
  [!shipper.includes("case empty"), "shipper does not discard a successful no-observations dashboard"],
  [shipper.includes("let openMetric = openClaimsMetric(dashboard)"), "shipper gates empty-state copy on metric truth"],
  [shipper.includes("openMetric.valueState == .measured && dashboard.open == 0"), "shipper reserves zero-state copy for measured zero"],
  [shipper.includes("openClaimsTruthCard(openMetric)"), "shipper renders non-measured truth honestly"],
  [shipper.includes("dashboard.metricStates?.open"), "shipper open count consumes metric truth"],
  [shipper.includes("dashboard.metricStates?.resolved"), "shipper resolved count consumes metric truth"],
  [shipper.includes("d?.metricStates?.totalValue"), "shipper claim value consumes metric truth"],
  [shipper.includes("d.metricStates?.aging"), "shipper aging consumes its truth state"],
  [shipper.includes('Text("\\(metric.value) open")'), "shipper aging header cannot bypass metric truth"],
  [!shipper.includes("CLAIM HISTORY · \\(dashboard.resolved)"), "shipper history count cannot bypass metric truth"],
  [shipper.includes("dashboardProofRow(d)"), "shipper exposes concise dashboard provenance"],
  [shipper.includes("average.accessibilityLabel"), "shipper exposes average-resolution truth to VoiceOver"],
  [!shipper.includes('return "MULTI"'), "shipper does not hide mixed currency behind an opaque label"],
  [!shipper.includes("dashboardMoney("), "shipper no longer renders money without metric truth"],
];

const parse = spawnSync(
  "xcrun",
  [
    "swiftc",
    "-frontend",
    "-parse",
    `${repoRoot}/EusoTrip/Views/Driver/099_MeFreightClaims.swift`,
    `${repoRoot}/EusoTrip/Views/Shipper/219_ShipperFreightClaims.swift`,
  ],
  { encoding: "utf8" },
);
checks.push([
  parse.status === 0,
  `Swift parser accepts both dashboard consumers${parse.stderr ? `: ${parse.stderr.trim()}` : ""}`,
]);

const failures = checks.filter(([passed]) => !passed).map(([, message]) => message);
if (failures.length) {
  console.error(`Freight-claims consumer verification failed:\n- ${failures.join("\n- ")}`);
  process.exit(1);
}

const shortageFields = ["expectedQuantity", "receivedQuantity", "quantityUnit"];
const missingShortageFields = shortageFields.filter((field) => !apiSection.includes(field));

console.log(`Freight-claims consumer verification passed (${checks.length}/${checks.length}).`);
if (missingShortageFields.length) {
  console.log(
    `COORDINATED CONTRACT GAP: shared filing API does not expose ${missingShortageFields.join(", ")}.`,
  );
} else {
  console.log("Typed shortage quantity evidence is exposed by the shared filing API.");
}

const backendPath = process.env.EUSOTRIP_FREIGHT_CLAIMS_CONTRACT;
if (backendPath) {
  if (!existsSync(backendPath)) {
    console.error(`Freight-claims consumer verification failed: backend path does not exist: ${backendPath}`);
    process.exit(1);
  }

  const backend = readFileSync(backendPath, "utf8");
  const dashboardStart = backend.indexOf("getClaimsDashboard:");
  const dashboardEnd = backend.indexOf("getClaims:", dashboardStart);
  const dashboardSection = backend.slice(dashboardStart, dashboardEnd);
  const fileStart = backend.indexOf("fileClaim:");
  const fileEnd = backend.indexOf("updateClaimStatus:", fileStart);
  const fileSection = backend.slice(fileStart, fileEnd);
  const detailStart = backend.indexOf("getClaimById:");
  const detailEnd = backend.indexOf("fileClaim:", detailStart);
  const detailSection = backend.slice(detailStart, detailEnd);
  const decisionStart = backend.indexOf("submitClaimDecision:");
  const decisionEnd = backend.indexOf("// PAYMENTS", decisionStart);
  const decisionSection = backend.slice(decisionStart, decisionEnd);

  const backendChecks = [
    [
      dashboardSection.includes("const avgResolutionDays = resolutionDays.length")
        && dashboardSection.includes(": null;"),
      "backend preserves an unknown resolution average as null",
    ],
    [fileSection.includes("amount: z.number().positive()"), "backend requires an explicit positive filing amount"],
    [fileSection.includes("currency:") && fileSection.includes(".optional()"), "backend keeps filing currency optional"],
    [!fileSection.includes('default("USD")'), "backend does not invent a filing currency"],
    [detailSection.includes("uploadedBy: e.userId ?? null"), "backend evidence uploader matches the numeric iOS contract"],
    [decisionSection.includes("idempotencyKey: z.string().uuid().transform((key) => key.toLowerCase())"), "every claim decision requires a caller UUID"],
    [decisionSection.includes("idempotencyKey: auditIdempotencyKey"), "non-money decisions persist the caller-owned audit identity"],
    [decisionSection.includes("requestFingerprint: decisionFingerprint"), "non-money decision replay validates an immutable request fingerprint"],
    [!decisionSection.includes("freight-claim-decision:${numId}:${input.decision}:${randomUUID()}"), "non-money decisions never regenerate retry identity"],
  ];
  const backendFailures = backendChecks.filter(([passed]) => !passed).map(([, message]) => message);
  if (backendFailures.length) {
    console.error(`Freight-claims backend verification failed:\n- ${backendFailures.join("\n- ")}`);
    process.exit(1);
  }

  const missingBackendShortageFields = shortageFields.filter((field) => !fileSection.includes(field));
  if (missingBackendShortageFields.length) {
    console.log(
      `COORDINATED BACKEND GAP: fileClaim does not accept ${missingBackendShortageFields.join(", ")}.`,
    );
  }
}
