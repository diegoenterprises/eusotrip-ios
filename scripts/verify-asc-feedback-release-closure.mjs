#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const defaultLedgerPath = path.join(root, "docs/testflight-feedback-ledger.json");

const VERIFIED_STATUSES = new Set(["verified", "verified-fixed"]);
const DEDUPLICATED_STATUSES = new Set(["deduplicated", "duplicate"]);

function normalizeStatus(status) {
  return typeof status === "string"
    ? status.trim().toLowerCase().replaceAll("_", "-")
    : "";
}

function hasEvidence(value) {
  if (typeof value === "string") return value.trim().length > 0;
  if (Array.isArray(value)) return value.some(hasEvidence);
  return Boolean(value && typeof value === "object" && Object.keys(value).length > 0);
}

function statusCategory(status) {
  const normalized = normalizeStatus(status);
  if (VERIFIED_STATUSES.has(normalized)) return "verified";
  if (DEDUPLICATED_STATUSES.has(normalized)) return "deduplicated";
  return null;
}

function sourceRows(summary) {
  if (!summary || typeof summary !== "object") return null;
  const screenshots = Array.isArray(summary.screenshotFeedback)
    ? summary.screenshotFeedback.map((row) => ({ ...row, ledgerKind: "screenshot" }))
    : null;
  const crashes = Array.isArray(summary.crashFeedback)
    ? summary.crashFeedback.map((row) => ({ ...row, ledgerKind: "crash" }))
    : null;
  return screenshots && crashes ? [...crashes, ...screenshots] : null;
}

export function evaluateReleaseClosure(ledger, { sourceSummary = null } = {}) {
  const failures = [];
  const addFailure = (item, reason) => {
    failures.push({
      ascId: item?.ascId || "(ledger)",
      build: item?.build ?? null,
      status: item?.status ?? null,
      reason,
    });
  };

  if (!ledger || typeof ledger !== "object") {
    addFailure(null, "ledger is not a JSON object");
    return { ok: false, total: 0, verified: 0, deduplicated: 0, statusCounts: {}, failures };
  }

  const items = Array.isArray(ledger.items) ? ledger.items : [];
  if (items.length === 0) addFailure(null, "ledger contains no feedback items");

  const byId = new Map();
  const statusCounts = {};
  const rawStatusCounts = {};
  const itemFailureIds = new Set();
  let verified = 0;
  let deduplicated = 0;

  const failItem = (item, reason) => {
    itemFailureIds.add(item?.ascId || "(ledger)");
    addFailure(item, reason);
  };

  for (const item of items) {
    if (!item || typeof item !== "object") {
      addFailure(null, "ledger contains a non-object item");
      continue;
    }
    if (typeof item.ascId !== "string" || !item.ascId.trim()) {
      failItem(item, "ASC ID is missing");
      continue;
    }
    if (byId.has(item.ascId)) failItem(item, "ASC ID is duplicated in the ledger");
    byId.set(item.ascId, item);

    const rawStatus = typeof item.status === "string" && item.status.trim()
      ? item.status.trim()
      : "(missing)";
    const normalized = normalizeStatus(item.status) || "(missing)";
    rawStatusCounts[rawStatus] = (rawStatusCounts[rawStatus] || 0) + 1;
    statusCounts[normalized] = (statusCounts[normalized] || 0) + 1;
    const category = statusCategory(item.status);
    if (!category) {
      failItem(item, `status ${JSON.stringify(item.status ?? null)} is not release-closed`);
      continue;
    }

    if (!hasEvidence(item.verification)) {
      failItem(item, `${category} item has no verification evidence`);
    }
    if (!Array.isArray(item.verificationArtifacts) || !item.verificationArtifacts.some(hasEvidence)) {
      failItem(item, `${category} item has no verification artifact`);
    }

    if (category === "verified") {
      verified += 1;
      if (item.duplicateOf != null) {
        failItem(item, "verified item must not also claim duplicateOf");
      }
    } else {
      deduplicated += 1;
    }
  }

  for (const item of items) {
    if (!item || statusCategory(item.status) !== "deduplicated") continue;
    if (typeof item.duplicateOf !== "string" || !item.duplicateOf.trim()) {
      failItem(item, "deduplicated item is missing duplicateOf");
      continue;
    }
    if (item.duplicateOf === item.ascId) {
      failItem(item, "deduplicated item points to itself");
      continue;
    }
    const target = byId.get(item.duplicateOf);
    if (!target) {
      failItem(item, "deduplicated item points outside the ledger");
    } else if (statusCategory(target.status) !== "verified") {
      failItem(item, "deduplicated item must point directly to a verified item");
    }
  }

  const computedCounts = {
    total: items.length,
    screenshots: items.filter((item) => item?.kind === "screenshot").length,
    crashes: items.filter((item) => item?.kind === "crash").length,
  };
  for (const [key, value] of Object.entries(computedCounts)) {
    if (ledger.counts?.[key] !== value) {
      addFailure(null, `counts.${key} is ${ledger.counts?.[key] ?? "missing"}; expected ${value}`);
    }
  }

  const recordedStatusCounts = ledger.counts?.byStatus;
  const allStatuses = new Set([
    ...Object.keys(rawStatusCounts),
    ...Object.keys(recordedStatusCounts && typeof recordedStatusCounts === "object" ? recordedStatusCounts : {}),
  ]);
  for (const status of allStatuses) {
    const recorded = recordedStatusCounts?.[status] || 0;
    const computed = rawStatusCounts[status] || 0;
    if (recorded !== computed) {
      addFailure(null, `counts.byStatus.${status} is ${recorded}; expected ${computed}`);
    }
  }

  const records = sourceRows(sourceSummary);
  if (!records) {
    addFailure(null, "ledger source summary is missing or has an invalid feedback schema");
  } else {
    const sourceById = new Map();
    for (const record of records) {
      if (typeof record.id !== "string" || !record.id.trim()) {
        addFailure(null, "source summary contains a record without an ID");
        continue;
      }
      if (sourceById.has(record.id)) {
        addFailure(null, `source summary contains duplicate ASC ID ${record.id}`);
      }
      sourceById.set(record.id, record);
    }
    for (const [id, record] of sourceById) {
      const item = byId.get(id);
      if (!item) {
        addFailure({ ascId: id, build: record.buildVersion }, "source summary item is absent from the ledger");
        continue;
      }
      if (item.kind !== record.ledgerKind) {
        failItem(item, `kind does not match source summary ${record.ledgerKind}`);
      }
      if (`${item.build ?? ""}` !== `${record.buildVersion ?? ""}`) {
        failItem(item, `build does not match source summary ${record.buildVersion ?? "null"}`);
      }
    }
    for (const item of items) {
      if (item?.ascId && !sourceById.has(item.ascId)) {
        failItem(item, "ledger item is absent from its source summary");
      }
    }
  }

  const releaseClosed = items.filter(
    (item) => item?.ascId && statusCategory(item.status) && !itemFailureIds.has(item.ascId),
  ).length;

  return {
    ok: failures.length === 0 && releaseClosed === items.length && items.length > 0,
    total: items.length,
    releaseClosed,
    verified,
    deduplicated,
    statusCounts,
    failures,
  };
}

function argumentValue(name) {
  const prefix = `--${name}=`;
  return process.argv.find((argument) => argument.startsWith(prefix))?.slice(prefix.length) || null;
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function printFailure(result) {
  console.error(`ASC release closure: FAIL (${result.releaseClosed}/${result.total} release-closed)`);
  console.error(
    `Statuses: ${Object.entries(result.statusCounts)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([status, count]) => `${status}=${count}`)
      .join(", ") || "none"}`,
  );
  console.error(`Closure failures: ${result.failures.length}`);
  for (const failure of result.failures.slice(0, 12)) {
    const build = failure.build == null ? "" : ` build=${failure.build}`;
    console.error(`- ${failure.ascId}${build}: ${failure.reason}`);
  }
  if (result.failures.length > 12) {
    console.error(`- ... ${result.failures.length - 12} additional failures omitted`);
  }
}

function main() {
  const ledgerPath = path.resolve(
    argumentValue("ledger") || process.env.ASC_FEEDBACK_LEDGER || defaultLedgerPath,
  );
  const ledger = readJson(ledgerPath);
  const sourceCandidate = argumentValue("source") || process.env.ASC_FEEDBACK_SUMMARY || ledger.source;
  if (typeof sourceCandidate !== "string" || !sourceCandidate.trim()) {
    throw new Error("ASC ledger source summary path is missing");
  }
  const sourcePath = path.resolve(sourceCandidate);
  if (!fs.existsSync(sourcePath)) {
    throw new Error(`ASC ledger source summary is unavailable: ${sourcePath}`);
  }
  const result = evaluateReleaseClosure(ledger, { sourceSummary: readJson(sourcePath) });
  if (!result.ok) {
    printFailure(result);
    process.exitCode = 1;
    return;
  }
  console.log(
    `ASC release closure: PASS (${result.total}/${result.total}; verified=${result.verified}, deduplicated=${result.deduplicated})`,
  );
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  try {
    main();
  } catch (error) {
    console.error(`ASC release closure: ERROR (${error instanceof Error ? error.message : "unknown error"})`);
    process.exitCode = 1;
  }
}
