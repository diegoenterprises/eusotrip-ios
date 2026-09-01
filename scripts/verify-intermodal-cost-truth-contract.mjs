#!/usr/bin/env node

import { existsSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const iosPath = `${repoRoot}/EusoTrip/Views/Rail/594_RailCostBreakdown.swift`;
const ios = readFileSync(iosPath, "utf8");
const checks = [
  [ios.includes("let currency: FreightClaimsAPI.CurrencyCode?"), "Rail cost rows retain typed persisted currency"],
  [ios.includes("let metricStates: MetricStates?"), "Rail cost rows retain metric truth"],
  [ios.includes("truth.valueState == .measured"), "Rail money requires measured state"],
  [ios.includes("truth.accessState == .granted"), "Rail money requires granted access"],
  [ios.includes("truth.trackingState == .tracked"), "Rail money requires tracked state"],
  [ios.includes('source: "intermodal_segments.rate+intermodal_shipments.currency"'), "Rail segment money requires exact provenance"],
  [ios.includes('source: "intermodal_transfers.transferCost+intermodal_shipments.currency"'), "Rail transfer money requires exact provenance"],
  [ios.includes('source: "intermodal_segments.rate+intermodal_transfers.transferCost+intermodal_shipments.currency"'), "Rail landed money requires exact provenance"],
  [ios.includes("return qualifiedMoney("), "Rail landed total is server-qualified"],
  [!ios.includes("private func usd("), "Rail has no USD-only formatter"],
  [!ios.includes('return "$" +'), "Rail never inserts a dollar symbol without currency"],
  [!ios.includes("(b.totalSegmentCost ?? 0) + (b.totalTransferCost ?? 0)"), "Rail never manufactures a landed total from nullable subtotals"],
  [!ios.includes("amountUsd"), "Rail ledger amount naming is currency-neutral"],
];

const backendPath = process.env.EUSOTRIP_INTERMODAL_CONTRACT;
if (!backendPath || !existsSync(backendPath)) {
  checks.push([false, "EUSOTRIP_INTERMODAL_CONTRACT must name the live intermodal router source"]);
} else {
  const backend = readFileSync(backendPath, "utf8");
  checks.push(
    [backend.includes("const segmentTruth = qualifyIntermodalCosts({"), "Router qualifies segment costs"],
    [backend.includes("const transferTruth = qualifyIntermodalCosts({"), "Router qualifies transfer costs"],
    [backend.includes("const grandTotal = combineIntermodalCostTotals("), "Router qualifies landed cost"],
    [backend.includes("metricStates: { rate: segmentTruth.rows[index].truth }"), "Router returns segment truth"],
    [backend.includes("metricStates: { cost: transferTruth.rows[index].truth }"), "Router returns transfer truth"],
    [backend.includes("totalSegmentCost: segmentTruth.total.truth"), "Router returns segment subtotal truth"],
    [backend.includes("totalTransferCost: transferTruth.total.truth"), "Router returns transfer subtotal truth"],
    [backend.includes("grandTotal: grandTotal.truth"), "Router returns landed total truth"],
    [!backend.includes("const segmentRatesComplete = segmentCosts.every"), "Router does not classify an empty array as a complete cost ledger"],
  );
}

const parse = spawnSync("xcrun", ["swiftc", "-parse", iosPath], { encoding: "utf8" });
checks.push([
  parse.status === 0,
  `Swift parser accepts Rail 594${parse.stderr ? `: ${parse.stderr.trim()}` : ""}`,
]);

const failures = checks.filter(([passed]) => !passed).map(([, message]) => message);
if (failures.length > 0) {
  console.error(`Intermodal cost truth verification failed:\n- ${failures.join("\n- ")}`);
  process.exit(1);
}

console.log(`Intermodal cost truth verification passed (${checks.length}/${checks.length}).`);
