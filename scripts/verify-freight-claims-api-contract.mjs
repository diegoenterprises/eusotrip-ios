import { existsSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const swiftPath = `${repoRoot}/EusoTrip/Services/EusoTripAPI.swift`;
const swift = readFileSync(swiftPath, "utf8");
const start = swift.indexOf("struct FreightClaimsAPI {");
const end = swift.indexOf("// MARK: - trackingRouter geofences", start);

if (start < 0 || end < 0) {
  console.error("Freight-claims contract verification failed: shared API boundary was not found.");
  process.exit(1);
}

const section = swift.slice(start, end);
const checks = [
  [section.includes("case truck = \"TRUCK\""), "TRUCK mode is explicit"],
  [section.includes("case rail = \"RAIL\""), "RAIL mode is explicit"],
  [section.includes("case vessel = \"VESSEL\""), "VESSEL mode is explicit"],
  [section.includes("let totalValue: Double?"), "mixed-currency total remains nullable"],
  [section.includes("let totalValueCurrency: CurrencyCode?"), "aggregate currency remains nullable"],
  [section.includes("let totalsByCurrency: [CurrencyTotal]"), "per-currency totals are preserved"],
  [section.includes("let avgResolutionDays: Double?"), "unknown resolution average remains nullable"],
  [section.includes('case notModeled = "not_modeled"'), "unmodeled metric state is decoded explicitly"],
  [section.includes('case notTracked = "not_tracked"'), "untracked metric state is decoded explicitly"],
  [section.includes("enum MetricAccessState"), "metric access state is decoded explicitly"],
  [section.includes("let accessState: MetricAccessState?"), "each metric retains access without treating rollout absence as granted"],
  [section.includes("let metricStates: DashboardMetricStates?"), "dashboard preserves per-metric truth states"],
  [section.includes("let provenance: DashboardProvenance?"), "dashboard preserves metric provenance"],
  [section.includes("let observedAt: String?"), "source observation time remains nullable"],
  [section.includes("let computedAt: String?"), "calculation time is decoded separately from source freshness"],
  [section.includes("let amount: Double?"), "unknown claim amount remains nullable on reads"],
  [section.includes("let currency: CurrencyCode?"), "read currency remains nullable rather than defaulting to USD"],
  [section.includes("let transportMode: TransportMode?"), "read mode remains nullable rather than defaulting to truck"],
  [section.includes("let referenceNumber: String?"), "read transaction reference remains nullable"],
  [section.includes("let id: Int\n        let claimId: String"), "file acknowledgement preserves numeric id and canonical claimId"],
  [section.includes("let requestKey: UUID"), "mutation request owns an explicit UUID"],
  [section.includes("requestKey.uuidString.lowercased()"), "request UUID is encoded canonically"],
  [!section.includes("requestKey: UUID = UUID()"), "shared claim mutations never regenerate a retry key implicitly"],
  [section.includes("case transportMode, referenceId"), "file request encodes one generic transaction reference"],
  [section.includes("try container.encode(referenceId, forKey: .referenceId)"), "transaction reference is sent once"],
  [section.includes("let idempotent: Bool"), "mutation acknowledgement exposes replay state"],
  [swift.includes("typealias ClaimRow = FreightClaimsAPI.Claim"), "shipper and driver decode one shared claim shape"],
  [!section.includes("totalValue: Double\n"), "dashboard does not force totalValue non-null"],
  [!section.includes("avgResolutionDays: Double\n"), "dashboard does not force average non-null"],
  [!section.includes("?? 0"), "shared claim boundary does not coerce unknown numerics to zero"],
  [!section.includes("?? \"USD\""), "shared claim boundary does not invent USD"],
  [!section.includes("transportMode ??"), "shared claim boundary does not invent a freight mode"],
];

const backendPath = process.env.EUSOTRIP_FREIGHT_CLAIMS_CONTRACT;
if (backendPath) {
  if (!existsSync(backendPath)) {
    checks.push([false, `backend contract path does not exist: ${backendPath}`]);
  } else {
    const backend = readFileSync(backendPath, "utf8");
    checks.push(
      [backend.includes('const claimModeSchema = z.enum(["TRUCK", "RAIL", "VESSEL"])'), "backend exposes the same three claim modes"],
      [backend.includes("totalValueCurrency"), "backend exposes aggregate currency"],
      [backend.includes("totalsByCurrency"), "backend exposes per-currency totals"],
      [backend.includes("avgResolutionDays: resolutionDays.length") && backend.includes(": null,"), "backend preserves unknown resolution average"],
      [backend.includes("metricStates:"), "backend exposes per-metric truth states"],
      [backend.includes("latestSourceObservedAt"), "backend derives freshness from persisted timestamps"],
      [backend.includes("observedAt: null") && backend.includes("computedAt,"), "backend separates no-observation truth from calculation time"],
      [backend.includes("notModeledReading"), "backend atomically binds metrics without modeled sources to null values"],
      [backend.includes("claimId: normalizedClaimId(outcome.id)"), "backend returns canonical claimId"],
      [backend.includes("id: outcome.id"), "backend returns numeric claim id"],
      [backend.includes("requestKey: z.string().uuid()"), "backend validates UUID request keys"],
      [backend.includes("referenceNumber: outcome.reference.referenceNumber"), "backend returns the locked transaction reference"],
    );
  }
}

const parse = spawnSync("xcrun", ["swiftc", "-parse", swiftPath], {
  encoding: "utf8",
});
checks.push([
  parse.status === 0,
  `Swift parser accepts EusoTripAPI.swift${parse.stderr ? `: ${parse.stderr.trim()}` : ""}`,
]);

const failures = checks.filter(([passed]) => !passed).map(([, message]) => message);
if (failures.length) {
  console.error(`Freight-claims contract verification failed:\n- ${failures.join("\n- ")}`);
  process.exit(1);
}

console.log(`Freight-claims contract verification passed (${checks.length}/${checks.length}).`);
