#!/usr/bin/env node
/**
 * Build a sanitized TestFlight feedback regression ledger from the local
 * App Store Connect feedback summary.
 *
 * Defaults:
 *   input:  /tmp/asc/feedback/_summary.json
 *   output: docs/testflight-feedback-ledger.json
 *
 * The ledger intentionally excludes tester email/name details. It keeps ASC
 * ids, build numbers, screenshots paths, comments, severity, cluster, repro,
 * and verification placeholders so every feedback item can be closed with
 * evidence or deduplicated explicitly.
 */
import fs from "node:fs";
import path from "node:path";

const args = new Map(
  process.argv.slice(2).map((arg) => {
    const [key, ...rest] = arg.replace(/^--/, "").split("=");
    return [key, rest.join("=") || "true"];
  })
);

const inputPath = path.resolve(args.get("input") || process.env.ASC_FEEDBACK_SUMMARY || "/tmp/asc/feedback/_summary.json");
const outputPath = path.resolve(args.get("output") || "docs/testflight-feedback-ledger.json");
const markdownPath = path.resolve(args.get("markdown") || "docs/testflight-feedback-ledger.md");
const checkOnly = args.has("check");
const fromLedger = args.has("from-ledger");

const clusterRules = [
  ["crash-or-freeze", /\b(crash|crashed|freeze|froze|frozen|perpetual loop|restart)\b/i, "P0"],
  ["posting-loads-and-drafts", /\b(post a load|posting|draft|resume draft|route between|schedule|catalyst missing)\b/i, "P0"],
  ["bids-counteroffers-booking", /\b(counter|bid|book|my bids|rate suggestions|award|cannot send|can't send|can't book)\b/i, "P0"],
  ["wallet-money-apple-pay", /\b(wallet|payout|cash out|stripe|fintech|apple pay|apple wallet|pkpass|payment|settlement|money)\b/i, "P0"],
  ["documents-bol-eusoticket", /\b(pdf|bol|bill of lading|run ticket|document|expired documents|delete expired)\b/i, "P1"],
  ["compliance-safety-eld-csa", /\b(compliance|safety|eld|csa|violations|wellness|pulse|score|fmcsa)\b/i, "P1"],
  ["live-location-weather-here", /\b(location|weather|weatherkit|here|live tracking|address|coordinates|route|map)\b/i, "P1"],
  ["market-hotzones-rate-intel", /\b(hotzones?|hot zones|market intelligence|rate sheets|rate board|customizable)\b/i, "P1"],
  ["esang-brief-chat-search", /\b(esang|gemini|brief|quick response|search|chat|morning|afternoon)\b/i, "P1"],
  ["integrations-api-tokens", /\b(integration|api token|provider|docs|404|connected apps|api key)\b/i, "P1"],
  ["profile-account-export", /\b(profile|export|delete account|email was sent|invite|account)\b/i, "P2"],
  ["design-polish-dev-copy", /\b(uninspiring|boring|layout|spacing|overlapping|dev team|backend|server|cannot read|design|basic)\b/i, "P2"]
];

const reproByCluster = {
  "crash-or-freeze": "Reproduce from the submitted build and symbolicated crash log; focus on back/resume navigation and article presentation.",
  "posting-loads-and-drafts": "Open Shipper post-load flow, create or resume a draft, go back, resume, and submit with route/schedule/catalyst combinations.",
  "bids-counteroffers-booking": "Open bidding/counter-offer/book-load surfaces, submit the action, then back-navigate and confirm counterpart state updates.",
  "wallet-money-apple-pay": "Open EusoWallet cash-out, payment methods, Apple Pay, and Apple Wallet pass flows; change amount and complete external handoff.",
  "documents-bol-eusoticket": "Open EusoTicket, run-ticket, BOL, and document center rows; tap PDFs/delete actions and confirm generated documents contain load data.",
  "compliance-safety-eld-csa": "Open compliance, ELD, CSA, violations, wellness, safety score, and Pulse screens for each allowed role and confirm live data or role-correct denial.",
  "live-location-weather-here": "Toggle location permissions, reload HERE/WeatherKit/live tracking, and verify degraded provider states are explicit.",
  "market-hotzones-rate-intel": "Open market intelligence and hot zones from the role surface; verify nonblank first load, tile flip/drilldown, and live rate data.",
  "esang-brief-chat-search": "Open ESANG chat/search/quick responses and time-of-day briefs; confirm Gemini-backed response and contextual actions.",
  "integrations-api-tokens": "Open Connected Apps/API Tokens; validate provider docs links and connect/disconnect flows against the web integration system.",
  "profile-account-export": "Open profile/account/export/delete/invite surfaces; save or submit and confirm persisted result and visible completion state.",
  "design-polish-dev-copy": "Render the affected screen and compare against design-authority anchors; remove dev-facing copy and text overlap."
};

const ownerAreaByCluster = {
  "crash-or-freeze": "ios-stability-navigation",
  "posting-loads-and-drafts": "freight-posting-drafts",
  "bids-counteroffers-booking": "freight-bidding-booking",
  "wallet-money-apple-pay": "wallet-payments-apple",
  "documents-bol-eusoticket": "documents-bol-eusoticket",
  "compliance-safety-eld-csa": "compliance-safety-eld",
  "live-location-weather-here": "here-weather-location",
  "market-hotzones-rate-intel": "market-intelligence-hotzones",
  "esang-brief-chat-search": "esang-ai",
  "integrations-api-tokens": "integrations-connected-apps",
  "profile-account-export": "profile-account-data",
  "design-polish-dev-copy": "design-authority-copy",
  "unclassified-feedback": "triage"
};

function readExistingLedger(filePath) {
  if (!fs.existsSync(filePath)) return new Map();
  try {
    const existing = JSON.parse(fs.readFileSync(filePath, "utf8"));
    return new Map((existing.items || []).map((item) => [item.ascId, item]));
  } catch {
    return new Map();
  }
}

function readJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    throw new Error(`Unable to read ASC feedback summary at ${filePath}: ${error.message}`);
  }
}

function classify(record, isCrash) {
  if (isCrash) return { cluster: "crash-or-freeze", severity: "P0" };
  const text = `${record.comment || ""} ${record.id || ""}`;
  for (const [cluster, pattern, severity] of clusterRules) {
    if (pattern.test(text)) return { cluster, severity };
  }
  return { cluster: "unclassified-feedback", severity: "P2" };
}

function normalizeRecord(record, isCrash, existingById) {
  const { cluster, severity } = classify(record, isCrash);
  const prior = existingById.get(record.id) || {};
  const effectiveCluster = prior.cluster || cluster;
  const effectiveSeverity = prior.severity || severity;
  const base = {
    ascId: record.id,
    kind: isCrash ? "crash" : "screenshot",
    build: record.buildVersion || null,
    affectedBuild: record.buildVersion || null,
    createdDate: record.createdDate || null,
    app: record.app || null,
    comment: record.comment || "",
    screenshots: Array.isArray(record.screenshots) ? record.screenshots : [],
    crashLogFile: record.crashLogFile || null,
    cluster: effectiveCluster,
    severity: effectiveSeverity,
    ownerArea: prior.ownerArea || ownerAreaByCluster[effectiveCluster] || "triage",
    repro: prior.repro || reproByCluster[effectiveCluster] || "Reproduce from the submitted screenshot/comment and confirm the user-visible path.",
    status: "open",
    fixPR: null,
    verification: null,
    duplicateOf: null,
    verificationArtifacts: []
  };
  return {
    ...base,
    status: prior.status || base.status,
    fixPR: prior.fixPR ?? base.fixPR,
    verification: prior.verification ?? base.verification,
    duplicateOf: prior.duplicateOf ?? base.duplicateOf,
    verificationArtifacts: Array.isArray(prior.verificationArtifacts)
      ? prior.verificationArtifacts
      : base.verificationArtifacts
  };
}

function buildLedger(summary) {
  const existingById = readExistingLedger(outputPath);
  const screenshots = (summary.screenshotFeedback || []).map((record) => normalizeRecord(record, false, existingById));
  const crashes = (summary.crashFeedback || []).map((record) => normalizeRecord(record, true, existingById));
  const items = [...crashes, ...screenshots].sort((a, b) => {
    const dateA = Date.parse(a.createdDate || "") || 0;
    const dateB = Date.parse(b.createdDate || "") || 0;
    return dateB - dateA;
  });

  const byCluster = {};
  const bySeverity = {};
  const byStatus = {};
  for (const item of items) {
    byCluster[item.cluster] = (byCluster[item.cluster] || 0) + 1;
    bySeverity[item.severity] = (bySeverity[item.severity] || 0) + 1;
    byStatus[item.status] = (byStatus[item.status] || 0) + 1;
  }

  return {
    generatedAt: new Date().toISOString(),
    source: inputPath,
    counts: {
      screenshots: screenshots.length,
      crashes: crashes.length,
      total: items.length,
      bySeverity,
      byCluster,
      byStatus
    },
    items
  };
}

function writeMarkdown(ledger) {
  const lines = [
    "# TestFlight Feedback Ledger",
    "",
    `Generated: ${ledger.generatedAt}`,
    `Source: ${ledger.source}`,
    "",
    `Total: ${ledger.counts.total}`,
    `Screenshots: ${ledger.counts.screenshots}`,
    `Crashes: ${ledger.counts.crashes}`,
    "",
    "## Status Counts",
    "",
    "| Status | Count |",
    "| --- | ---: |",
    ...Object.entries(ledger.counts.byStatus)
      .sort((a, b) => b[1] - a[1])
      .map(([status, count]) => `| ${status} | ${count} |`),
    "",
    "## Cluster Counts",
    "",
    "| Cluster | Count |",
    "| --- | ---: |",
    ...Object.entries(ledger.counts.byCluster)
      .sort((a, b) => b[1] - a[1])
      .map(([cluster, count]) => `| ${cluster} | ${count} |`),
    "",
    "## Open Items",
    "",
    "| Severity | Status | Kind | Build | ASC ID | Owner Area | Cluster | Comment |",
    "| --- | --- | --- | --- | --- | --- | --- | --- |",
    ...ledger.items.map((item) => {
      const comment = (item.comment || "").replace(/\s+/g, " ").replace(/\|/g, "/").slice(0, 180);
      return `| ${item.severity} | ${item.status} | ${item.kind} | ${item.build || ""} | ${item.ascId || ""} | ${item.ownerArea || ""} | ${item.cluster} | ${comment} |`;
    })
  ];
  fs.writeFileSync(markdownPath, `${lines.join("\n")}\n`);
}

const ledger = fromLedger ? readJson(outputPath) : buildLedger(readJson(inputPath));

if ((ledger.counts.total || ledger.items?.length || 0) === 0) {
  throw new Error("ASC feedback summary produced zero ledger items");
}

if (!checkOnly) {
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.mkdirSync(path.dirname(markdownPath), { recursive: true });
  fs.writeFileSync(outputPath, `${JSON.stringify(ledger, null, 2)}\n`);
  writeMarkdown(ledger);
}

console.log(`ASC feedback ledger: ${ledger.counts.total} items (${ledger.counts.screenshots} screenshots, ${ledger.counts.crashes} crashes)`);
console.log(`P0: ${ledger.counts.bySeverity.P0 || 0}, P1: ${ledger.counts.bySeverity.P1 || 0}, P2: ${ledger.counts.bySeverity.P2 || 0}`);
if (!checkOnly) {
  console.log(`Wrote ${outputPath}`);
  console.log(`Wrote ${markdownPath}`);
}
