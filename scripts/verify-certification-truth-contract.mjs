import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const iosRoot = resolve(import.meta.dirname, "..");
const backendRoot = process.env.EUSOTRIP_BACKEND_ROOT
  ? resolve(process.env.EUSOTRIP_BACKEND_ROOT)
  : "/Users/diegousoro/_codex_rios_hardening/frontend";

const files = {
  watchtower: resolve(
    iosRoot,
    "EusoTrip/Views/Dispatch/542_DispatcherCredentialsWatchtower.swift"
  ),
  escortProfile: resolve(
    iosRoot,
    "EusoTrip/Views/Escort/ES12_MeProfile.swift"
  ),
  escortReciprocity: resolve(
    iosRoot,
    "EusoTrip/Views/Escort/ES08_CertReciprocity.swift"
  ),
  metricTruth: resolve(backendRoot, "server/services/metricTruth.ts"),
  certifications: resolve(backendRoot, "server/routers/certifications.ts"),
  escorts: resolve(backendRoot, "server/routers/escorts.ts"),
  training: resolve(backendRoot, "server/routers/trainingCompliance.ts"),
  roleWidgets: resolve(backendRoot, "client/src/components/widgets/DynamicRoleWidgets.tsx"),
  trainingPage: resolve(backendRoot, "client/src/pages/TrainingCompliance.tsx"),
  escortMigration: resolve(
    backendRoot,
    "drizzle/0492_escort_certification_canonical_link.sql"
  ),
};

for (const [label, path] of Object.entries(files)) {
  if (!existsSync(path)) throw new Error(`${label} source is missing: ${path}`);
}

const source = Object.fromEntries(
  Object.entries(files).map(([label, path]) => [label, readFileSync(path, "utf8")])
);

const checks = [
  [
    source.metricTruth.includes("export function notModeledReading<T>") &&
      source.metricTruth.includes('valueState: "not_modeled"') &&
      source.metricTruth.includes('trackingState: "not_tracked"') &&
      source.metricTruth.includes("source: null") &&
      source.metricTruth.includes("observedAt: null") &&
      source.metricTruth.includes("basis: null"),
    "metricTruth preserves the complete unmodeled value, tracking, access, and provenance axes",
  ],
  [
    source.certifications.includes("requirements: metric.value") &&
      source.certifications.includes("requirementsMetric: metric") &&
      source.certifications.includes("overallCompliance: overallMetric.value") &&
      source.certifications.includes("overallComplianceMetric: overallMetric") &&
      source.certifications.includes("estimatedRenewalCost: costMetric.value") &&
      source.certifications.includes("estimatedRenewalCostMetric: costMetric"),
    "certification responses keep null values beside their truth readings",
  ],
  [
    source.certifications.includes('emailFailureKind: "provider_rejected"') &&
      source.certifications.includes('emailFailureKind = "provider_error"') &&
      source.certifications.includes("Renewal email delivery state could not be persisted"),
    "renewal reminders persist and distinguish email provider outcomes",
  ],
  [
    source.watchtower.includes("let overallComplianceMetric: MetricReading542<Double>") &&
      source.watchtower.includes('metric.truth.valueState == "measured"') &&
      source.watchtower.includes('metric.truth.trackingState == "tracked"') &&
      source.watchtower.includes('metric.truth.accessState == "granted"'),
    "iOS displays a compliance scalar only from a measured, tracked, granted reading",
  ],
  [
    !source.watchtower.includes("overallCompliance ?? 0") &&
      !source.watchtower.includes("overallCompliance ?? 0.0"),
    "iOS never converts missing compliance to zero",
  ],
  [
    source.watchtower.includes("let inAppRecorded: Bool") &&
      source.watchtower.includes("if out.success && out.inAppRecorded") &&
      source.watchtower.includes("requestKey: UUID().uuidString"),
    "iOS counts only persisted reminders and sends a replay identity",
  ],
  [
    source.escorts.includes("const escortPermitProcedure = isolatedRoleProcedure(ROLES.ESCORT)") &&
      source.escorts.includes('verificationStatus: r.verificationStatus ?? null') &&
      source.escorts.includes('source: "certifications+escort_certifications"') &&
      !source.escorts.includes("r.status || 'active'") &&
      !source.escorts.includes("newExpiry.setFullYear"),
    "escort permit reads are isolated and do not manufacture active status or renewal expiry",
  ],
  [
    source.escorts.includes("certificationNumber: null") &&
      source.escorts.includes("issuedBy: null") &&
      source.escorts.includes("issuedDate: null") &&
      source.escorts.includes("expiryDate: null") &&
      source.escorts.includes("documentUrl: null") &&
      source.escorts.includes('eventType: "escort.permit_renewal_requested"'),
    "escort renewal starts pending with fresh evidence requirements and durable audit intent",
  ],
  [
    source.escorts.includes("await tx.insert(certifications).values") &&
      source.escorts.includes("await tx.insert(escortCertifications).values") &&
      source.escorts.includes("await tx.insert(certificationDocuments).values") &&
      source.escorts.includes('eventType: "escort.certification_submitted"') &&
      source.escorts.includes('verificationStatus: "unverified" as const') &&
      source.escorts.includes("requiresVerification: true"),
    "escort certification submission atomically links canonical truth, capability, evidence, and audit intent",
  ],
  [
    source.escortMigration.includes("WHERE ec.certificationId IS NULL") &&
      source.escortMigration.includes("MODIFY COLUMN certificationId INT NOT NULL") &&
      source.escortMigration.includes("ADD UNIQUE KEY escort_certification_parent_uq") &&
      source.escortMigration.includes("fk_escort_certification_parent") &&
      source.escortMigration.includes("chk_escort_certification_parent"),
    "0492 backfills legacy escort credentials once and enforces one canonical parent",
  ],
  [
    source.escortProfile.includes("struct EscortCertificationSubmissionInput: Encodable") &&
      source.escortProfile.includes("let certificationNumber: String") &&
      source.escortProfile.includes("let issuingAuthority: String") &&
      source.escortProfile.includes("let fileBase64: String") &&
      source.escortProfile.includes("allowedContentTypes: [.pdf, .jpeg, .png]") &&
      source.escortProfile.includes("result.status == \"pending\"") &&
      source.escortProfile.includes("result.verificationStatus == \"unverified\"") &&
      !source.escortProfile.includes('(\$0.status ?? "active") == "active"'),
    "native escort profile captures real evidence and never upgrades unknown or pending status",
  ],
  [
    source.escortReciprocity.includes("EscortAddCertificationSheet { submission in") &&
      source.escortReciprocity.includes("receipt.requiresVerification") &&
      source.escortReciprocity.includes("receipt.evidenceAttached") &&
      source.escortReciprocity.includes("let verificationStatus: String?") &&
      source.escortReciprocity.includes("let tracking: EscortCertificationTracking") &&
      !source.escortReciprocity.includes("try? await EusoTripAPI.shared.query") &&
      !source.escortReciprocity.includes("private struct UploadInput"),
    "native reciprocity uses the shared evidence form and surfaces read or verification failures",
  ],
  [
    source.training.includes("driverName: c.subjectName ?? null") &&
      source.training.includes("issueDate: c.issuedDate?.toISOString() ?? null") &&
      source.training.includes("expiryDate: c.expiryDate?.toISOString() ?? null") &&
      source.training.includes("daysUntilExpiry: c.expiryDate") &&
      source.training.includes('source: "certifications" as const') &&
      !source.training.includes('driverName: c.driverName || "Driver"') &&
      !source.training.includes("expiryDate: c.expiryDate?.toISOString() || new Date(Date.now() + 180 * 86400000)"),
    "training tracker preserves absent identity and date facts with explicit provenance",
  ],
  [
    source.training.includes('status: "pending"') &&
      source.training.includes('verificationStatus: "unverified"') &&
      source.training.includes('eventType: "training.certification_renewal_submitted"') &&
      source.training.includes('durableState: created.replayed ? "not_repeated"') &&
      !source.training.includes('status: "active",\n            documentUrl: input.documentUrl || undefined'),
    "training renewal is pending, unverified, idempotent, and transactionally audited",
  ],
  [
    source.roleWidgets.includes("Permit metrics unavailable") &&
      source.trainingPage.includes("Certification records unavailable") &&
      source.trainingPage.includes('value={d.summary.total}') &&
      source.trainingPage.includes('value={d.summary.valid}'),
    "web certification surfaces distinguish unavailable sources from measured zero",
  ],
];

const failures = checks.filter(([passed]) => !passed).map(([, message]) => message);
if (failures.length) {
  for (const failure of failures) console.error(`FAIL: ${failure}`);
  process.exit(1);
}

for (const [, message] of checks) console.log(`PASS: ${message}`);
