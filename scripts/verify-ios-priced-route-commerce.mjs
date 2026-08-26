#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const root = process.cwd();
const read = relative => fs.readFileSync(path.join(root, relative), "utf8");
const failures = [];

function requireText(file, pattern, reason) {
  const source = read(file);
  if (!pattern.test(source)) failures.push(`${file}: ${reason}`);
}

function forbidText(file, pattern, reason) {
  const source = read(file);
  if (pattern.test(source)) failures.push(`${file}: ${reason}`);
}

const client = "EusoTrip/Services/PricedRouteCommerceClient.swift";
const quotePanel =
  "EusoTrip/Views/Components/PricedRouteQuoteAuthorityPanel.swift";
const sheetPanel =
  "EusoTrip/Views/Components/PricedRouteRateSheetAuthorityPanel.swift";

for (const endpoint of [
  "pricedRoute.price",
  "pricedRoute.getCurrent",
  "pricedRouteRateSheet.ingest",
  "pricedRouteRateSheet.list",
  "pricedRouteRateSheet.confirm",
  "modeAssetAvailability.publish",
  "modeAssetAvailability.listMine",
  "modeAssetAvailability.withdraw",
]) {
  requireText(client, new RegExp(`\"${endpoint.replaceAll(".", "\\.")}\"`), `missing typed ${endpoint} boundary`);
}

// The price mutation must remain identity + replay intent only. Inputs named
// for route distance, rates, fees, progress, tax, or payout are a P0 breach.
const priceInput = read(client).match(
  /private struct PriceInput: Encodable \{([\s\S]*?)\n    \}/
)?.[1] ?? "";
if (!priceInput.includes("let subject: Subject") || !priceInput.includes("let requestId: String")) {
  failures.push(`${client}: price input is not subject + request identity`);
}
if (/mile|distance|rate|fee|progress|tax|payout/i.test(priceInput)) {
  failures.push(`${client}: price input accepts client-authored commercial or route arithmetic`);
}

requireText(
  sheetPanel,
  /Upload creates a proposal, never a live price/,
  "proposal-only truth copy is missing"
);
requireText(
  sheetPanel,
  /requires an exact-hash human confirmation/,
  "exact draft confirmation gate is missing"
);
requireText(
  quotePanel,
  /platformFeeMinor/,
  "immutable server platform-fee readback is missing"
);
requireText(
  quotePanel,
  /routePlanVersion/,
  "exact route-plan version receipt is missing"
);
requireText(
  quotePanel,
  /allocationVersion/,
  "committed availability allocation receipt is missing"
);

const integrations = [
  ["EusoTrip/Views/Driver/104_MeRateSheet.swift", /PricedRouteRateSheetAuthorityPanel\(mode: \.truck\)/],
  ["EusoTrip/Views/Rail/580_RailTariffRateLookup.swift", /PricedRouteRateSheetAuthorityPanel\(mode: \.rail\)/],
  ["EusoTrip/Views/Vessel/687_VesselOceanRateLookup.swift", /PricedRouteRateSheetAuthorityPanel\(mode: \.vessel\)/],
  ["EusoTrip/Views/Rail/580_RailTariffRateLookup.swift", /subjectType: \.railShipment/],
  ["EusoTrip/Views/Vessel/687_VesselOceanRateLookup.swift", /subjectType: \.vesselShipment/],
  ["EusoTrip/Views/Carrier/311_CarrierActiveLoad.swift", /subjectType: \.load/],
  ["EusoTrip/Views/Catalyst/373_CatalystAwardedCelM04.swift", /subjectType: \.load/],
];
for (const [file, pattern] of integrations) {
  requireText(file, pattern, "canonical priced-route commerce surface is not wired");
}

forbidText(
  "EusoTrip/Views/Rail/580_RailTariffRateLookup.swift",
  /Task\.sleep\([\s\S]{0,200}requestQuote|private func requestQuote/,
  "fake quote animation remains"
);
forbidText(
  "EusoTrip/Views/Vessel/687_VesselOceanRateLookup.swift",
  /createVesselBooking|rate:\s*best\.allIn|Save quote to booking/,
  "client-calculated vessel rate can still write a booking"
);
forbidText(
  "EusoTrip/Views/Carrier/311_CarrierActiveLoad.swift",
  /LifecycleRow\(label:\s*\"Rate\"[\s\S]{0,100}live\.load\.rate/,
  "mutable load rate is still presented as active-load money truth"
);

if (failures.length) {
  console.error("iOS priced-route commerce contract failed:");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(
  "iOS priced-route commerce contract passed: tri-modal immutable intake, exact quote readback, and no client-authored award pricing"
);
