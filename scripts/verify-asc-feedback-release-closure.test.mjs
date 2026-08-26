import assert from "node:assert/strict";
import test from "node:test";

import { evaluateReleaseClosure } from "./verify-asc-feedback-release-closure.mjs";

function feedbackItem(overrides = {}) {
  return {
    ascId: "ASC-1",
    kind: "screenshot",
    build: "900",
    status: "verified",
    verification: "TestFlight reproduction passed on the affected path.",
    verificationArtifacts: ["device-run-900.json"],
    duplicateOf: null,
    ...overrides,
  };
}

function sourceSummary(items) {
  return {
    screenshotFeedback: items
      .filter((item) => item.kind === "screenshot")
      .map((item) => ({ id: item.ascId, buildVersion: item.build })),
    crashFeedback: items
      .filter((item) => item.kind === "crash")
      .map((item) => ({ id: item.ascId, buildVersion: item.build })),
  };
}

function ledger(items) {
  const byStatus = {};
  for (const item of items) byStatus[item.status] = (byStatus[item.status] || 0) + 1;
  return {
    source: "/fixture/_summary.json",
    counts: {
      total: items.length,
      screenshots: items.filter((item) => item.kind === "screenshot").length,
      crashes: items.filter((item) => item.kind === "crash").length,
      byStatus,
    },
    items,
  };
}

test("release closure accepts verified rows and evidence-backed deduplication", () => {
  const items = [
    feedbackItem({ status: "verified_fixed" }),
    feedbackItem({
      ascId: "ASC-2",
      status: "duplicate",
      duplicateOf: "ASC-1",
      verification: "Same submitted build and proven crash signature as ASC-1.",
      verificationArtifacts: ["dedupe-signature.json"],
    }),
  ];
  const result = evaluateReleaseClosure(ledger(items), { sourceSummary: sourceSummary(items) });
  assert.equal(result.ok, true);
  assert.equal(result.releaseClosed, 2);
  assert.equal(result.verified, 1);
  assert.equal(result.deduplicated, 1);
});

test("release closure rejects pending, blocked, and unknown statuses", () => {
  const items = [
    feedbackItem({ ascId: "ASC-PENDING", status: "fixed-pending-testflight" }),
    feedbackItem({ ascId: "ASC-BLOCKED", status: "blocked-missing-crash-log" }),
    feedbackItem({ ascId: "ASC-OPEN", status: "open" }),
  ];
  const result = evaluateReleaseClosure(ledger(items), { sourceSummary: sourceSummary(items) });
  assert.equal(result.ok, false);
  assert.equal(result.releaseClosed, 0);
  assert.deepEqual(result.statusCounts, {
    "fixed-pending-testflight": 1,
    "blocked-missing-crash-log": 1,
    open: 1,
  });
});

test("release closure rejects unsupported deduplication and missing evidence", () => {
  const items = [
    feedbackItem({ verificationArtifacts: [] }),
    feedbackItem({
      ascId: "ASC-2",
      status: "duplicate",
      duplicateOf: "ASC-MISSING",
    }),
  ];
  const result = evaluateReleaseClosure(ledger(items), { sourceSummary: sourceSummary(items) });
  assert.equal(result.ok, false);
  assert.equal(result.failures.some((failure) => failure.reason.includes("no verification artifact")), true);
  assert.equal(result.failures.some((failure) => failure.reason.includes("outside the ledger")), true);
});

test("release closure reconciles every ledger row against its source summary", () => {
  const items = [feedbackItem()];
  const source = sourceSummary([
    ...items,
    feedbackItem({ ascId: "ASC-NEW", build: "901", kind: "crash" }),
  ]);
  const result = evaluateReleaseClosure(ledger(items), { sourceSummary: source });
  assert.equal(result.ok, false);
  assert.equal(
    result.failures.some(
      (failure) => failure.ascId === "ASC-NEW" && failure.reason.includes("absent from the ledger"),
    ),
    true,
  );
});
