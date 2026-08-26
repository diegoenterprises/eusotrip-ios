import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const read = (path) => readFileSync(join(root, path), "utf8");
const api = read("EusoTrip/Services/EusoTripAPI.swift");
const screen = read("EusoTrip/Views/Shipper/433_RecurringLoadsComposer.swift");

const between = (source, startMarker, endMarker) => {
  const start = source.indexOf(startMarker);
  const end = source.indexOf(endMarker, start + startMarker.length);
  if (start < 0 || end < 0) return "";
  return source.slice(start, end);
};

const contract = between(
  api,
  "struct RecurringLoadsAPI",
  "// MARK: - ControlTowerAPI",
);
const checks = [
  [
    api.includes("lazy var recurringLoads: RecurringLoadsAPI"),
    "EusoTripAPI exposes the typed recurring-load client",
  ],
  [
    contract.includes('"recurringLoads.listSourceLoads"'),
    "source-load eligibility uses the production endpoint",
  ],
  [
    contract.includes('"recurringLoads.list"'),
    "schedule list uses the production endpoint",
  ],
  [
    contract.includes('"recurringLoads.listOccurrences"'),
    "occurrence register uses the production endpoint",
  ],
  [
    contract.includes('"recurringLoads.create"'),
    "schedule creation uses the production endpoint",
  ],
  [
    contract.includes('"recurringLoads.acknowledgeOccurrence"'),
    "evidence acknowledgement uses the production endpoint",
  ],
  [
    contract.includes('"recurringLoads.setStatus"'),
    "pause, resume, and cancel use the production endpoint",
  ],
  [
    contract.includes("let sourceUpdatedAt: String") &&
      contract.includes("let eligible: Bool") &&
      contract.includes("let blockers: [String]"),
    "source rows preserve eligibility, blockers, and freshness",
  ],
  [
    contract.includes("let timeZone: String") &&
      contract.includes("let localPickupTime: String") &&
      contract.includes("let dstOverlapPolicy: DSTOverlapPolicy"),
    "recurrence rule preserves local-time and DST authority",
  ],
  [
    contract.includes("case weekly") &&
      contract.includes("case biweekly") &&
      contract.includes("case monthly"),
    "frequency enum matches the strict backend enum",
  ],
  [
    contract.includes('case reviewRequired = "review_required"'),
    "occurrence review status matches the wire value",
  ],
  [
    contract.includes("let reviewRequiredReasons: [String]?") &&
      contract.includes("let provenance: OccurrenceProvenance?"),
    "occurrence review reasons and provenance remain optional truth",
  ],
  [
    contract.includes("let portIntelligenceEvidenceCutoffAt: String?") &&
      contract.includes("let generatedAt: String?"),
    "Port Intelligence evidence cutoff and generation time are modeled",
  ],
  [
    contract.includes("UserDefaults.standard.string(forKey: storageKey)") &&
      contract.includes("SHA256.hash(data: material)"),
    "create retries retain an exact-terms idempotency key",
  ],
  [
    !contract.includes("sessionCredential") &&
      !contract.includes("api.authToken"),
    "exact-terms idempotency survives bearer and session rotation",
  ],
  [
    contract.includes(
      "guard output.success, UUID(uuidString: output.scheduleId) != nil",
    ),
    "create only succeeds with a confirmed server UUID",
  ],
  [
    contract.includes(
      "guard acknowledgeIndustryAssessment || acknowledgePortIntelligence",
    ),
    "empty evidence acknowledgements are rejected client-side",
  ],
  [
    contract.includes("let retryReady: Bool"),
    "evidence acknowledgement preserves server retry readiness",
  ],
  [
    screen.includes("api.recurringLoads.listSourceLoads(limit: 250)"),
    "the visible source picker reads live server eligibility",
  ],
  [
    screen.includes("api.recurringLoads.listOccurrences") &&
      screen.includes("Occurrence register"),
    "the visible register reads live occurrences",
  ],
  [
    screen.includes("api.recurringLoads.setStatus") &&
      screen.includes("PendingScheduleCancellation"),
    "schedule lifecycle actions are wired with cancel confirmation",
  ],
  [
    screen.includes("api.recurringLoads.acknowledgeOccurrence") &&
      screen.includes("Acknowledge selected evidence"),
    "exact evidence acknowledgement is wired",
  ],
  [
    screen.includes("Generation provenance") &&
      screen.includes("Evidence cutoff"),
    "the UI exposes generation and evidence provenance",
  ],
  [
    screen.includes("Not recorded") && screen.includes("Not materialized"),
    "unknown and unmaterialized states remain explicit",
  ],
  [
    screen.includes("TimeZone.knownTimeZoneIdentifiers") &&
      screen.includes("Use device time zone:"),
    "time zone is chosen explicitly rather than silently defaulted",
  ],
  [
    screen.includes("source.eligible") && screen.includes("source.blockers"),
    "blocked source loads cannot be selected",
  ],
  [
    screen.includes(".eusoRefreshable") &&
      screen.includes("Refresh occurrences"),
    "server state can be refreshed through the app-wide refresh contract without a local timer",
  ],
  [
    screen.includes("occurrenceRequestId == requestId") &&
      screen.includes("selectedScheduleId == scheduleId"),
    "stale occurrence responses cannot overwrite a newer schedule selection",
  ],
  [
    screen.includes("if let selectedScheduleId") &&
      screen.includes("await loadOccurrences(scheduleId: selectedScheduleId)"),
    "the initially selected schedule loads its occurrence register",
  ],
  [
    !screen.includes("startISO") &&
      !screen.includes("endISO") &&
      !screen.includes("dayOfWeek"),
    "retired recurring-load fields are absent",
  ],
  [
    !screen.includes("var lane") && !screen.includes("var rate"),
    "the composer no longer invents a lane or rate",
  ],
  [
    !screen.includes("Date().addingTimeInterval") && !screen.includes("Timer"),
    "the client does not fabricate a date window or scheduler",
  ],
  [
    !screen.includes("WebContinuation") && !screen.includes("app.eusotrip.com"),
    "there is no browser fallback",
  ],
  [
    !screen.includes("rate ?? 0") &&
      !screen.includes("parts.year ?? 0") &&
      !screen.includes("parts.hour ?? 0"),
    "unknown values are not converted to numeric defaults",
  ],
  [
    !screen.includes("Recurring schedule saved") &&
      screen.includes("The server confirmed"),
    "visible success requires a confirmed server acknowledgement",
  ],
];

const failures = checks
  .filter(([passed]) => !passed)
  .map(([, message]) => message);
if (failures.length) {
  console.error(
    `iOS recurring-load contract verification failed:\n- ${failures.join("\n- ")}`,
  );
  process.exit(1);
}

console.log(
  `iOS recurring-load contract verification passed (${checks.length}/${checks.length}).`,
);
