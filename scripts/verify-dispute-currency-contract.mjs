#!/usr/bin/env node

import { existsSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const repoRoot = fileURLToPath(new URL("..", import.meta.url));
const read = (relativePath) => readFileSync(`${repoRoot}/${relativePath}`, "utf8");
const api = read("EusoTrip/Services/EusoTripAPI.swift");
const shipper = read("EusoTrip/Views/Shipper/219_ShipperFreightClaims.swift");
const vessel = read("EusoTrip/Views/Vessel/809_VesselDisputeResolution.swift");
const rail = read("EusoTrip/Views/Rail/594_RailCostBreakdown.swift");

const shipperStart = shipper.indexOf("private struct OpenDisputeSheet");
const shipperEnd = shipper.indexOf("private enum FormalDisputeConfirmationError", shipperStart);
const formalDispute = shipper.slice(shipperStart, shipperEnd);
const apiStart = api.indexOf("struct ShipperFreightClaimsAPI");
const apiEnd = api.indexOf("// MARK: - ShipperRatesAPI", apiStart);
const disputeApi = api.slice(apiStart, apiEnd);

const checks = [
  [shipperStart >= 0 && shipperEnd > shipperStart, "Shipper formal-dispute surface is discoverable"],
  [disputeApi.includes("let currency: FreightClaimsAPI.CurrencyCode"), "shared Shipper dispute API requires a typed ISO currency"],
  [disputeApi.includes("let amount: Double"), "shared Shipper dispute acknowledgement retains its amount"],
  [formalDispute.includes("@State private var currencyText"), "Shipper filing owns explicit currency input state"],
  [formalDispute.includes("FreightClaimsAPI.CurrencyCode(rawValue: currencyText)"), "Shipper validates currency through the canonical type"],
  [formalDispute.includes("resp.currency == currency"), "Shipper verifies acknowledgement currency"],
  [formalDispute.includes("$0.metricStates.amount.valueState == .measured"), "Shipper requires measured readback state"],
  [formalDispute.includes("$0.metricStates.amount.trackingState == .tracked"), "Shipper requires tracked readback state"],
  [formalDispute.includes("$0.metricStates.amount.provenance.source == \"disputes.amountInDispute+baseCurrency\""), "Shipper requires exact money provenance"],
  [!formalDispute.includes("?? 0"), "Shipper does not collapse missing dispute money to zero"],
  [vessel.includes("let currency: FreightClaimsAPI.CurrencyCode"), "Vessel counter mutation sends typed currency"],
  [vessel.includes("let acceptedCurrency: FreightClaimsAPI.CurrencyCode?"), "Vessel acceptance decodes confirmed currency"],
  [vessel.includes("truth.valueState == .measured"), "Vessel actions require measured money"],
  [vessel.includes("truth.trackingState == .tracked"), "Vessel actions require tracked money"],
  [vessel.includes("latestLedgerOfferAmount.map"), "Vessel counter derives only from qualified ledger money"],
  [vessel.includes("counterReadbackMismatch"), "Vessel counter requires ledger readback"],
  [vessel.includes("acceptanceReadbackMismatch"), "Vessel acceptance requires resolution readback"],
  [!vessel.includes("gapAmount = \"$0\""), "Vessel never renders missing dispute money as zero dollars"],
  [!vessel.includes("latestOfferAmount ?? 0"), "Vessel never converts a missing offer into zero"],
  [rail.includes("coherentDisputeMoney"), "Rail intermodal dispute validates its money truth envelope"],
  [rail.includes("freightClaims.getDisputeResolution"), "Rail intermodal dispute verifies ledger readback"],
  [rail.includes("dispute acknowledgement did not preserve its amount, currency, and provenance state"), "Rail exposes an honest acknowledgement mismatch"],
];

const backendPath = process.env.EUSOTRIP_FREIGHT_CLAIMS_CONTRACT;
if (backendPath) {
  if (!existsSync(backendPath)) {
    checks.push([false, `backend contract path does not exist: ${backendPath}`]);
  } else {
    const backend = readFileSync(backendPath, "utf8");
    checks.push(
      [backend.includes("currency: isoCurrencySchema"), "backend validates ISO currency on dispute writes"],
      [backend.includes("baseCurrency: input.currency"), "backend persists filing currency beside filing amount"],
      [backend.includes("offerAmount: moneyString(input.amount)"), "backend persists typed offer amount"],
      [backend.includes("offerCurrency: input.currency"), "backend persists typed offer currency"],
      [backend.includes("resolvedAmount: moneyString(acceptedAmount)"), "backend persists accepted amount"],
      [backend.includes("resolvedCurrency: baseCurrency"), "backend persists accepted currency"],
      [backend.includes("canAccept: isAdmin || event.actorUserId !== userId"), "backend exposes actionable counterparty offers"],
      [backend.includes("Intermodal dispute readback did not match"), "backend confirms intermodal dispute persistence"],
      [!backend.includes("extractOfferAmount"), "backend never parses offer money from prose"],
      [!backend.includes("createDispute event insert failed"), "intermodal event failure is not swallowed"],
    );
  }
}

const webPath = process.env.EUSOTRIP_FREIGHT_CLAIMS_WEB;
if (webPath) {
  if (!existsSync(webPath)) {
    checks.push([false, `web consumer path does not exist: ${webPath}`]);
  } else {
    const web = readFileSync(webPath, "utf8");
    checks.push(
      [web.includes('currency: ""'), "web dispute form has no default currency"],
      [web.includes("!/^[A-Z]{3}$/.test(currency)"), "web validates explicit ISO currency"],
      [web.includes("row.metricStates?.amount?.valueState === \"measured\""), "web verifies measured readback"],
      [web.includes("row.metricStates?.amount?.trackingState === \"tracked\""), "web verifies tracked readback"],
      [web.includes("row.metricStates?.amount?.provenance?.source === \"disputes.amountInDispute+baseCurrency\""), "web verifies money provenance"],
    );
  }
}

const parse = spawnSync("xcrun", [
  "swiftc",
  "-parse",
  `${repoRoot}/EusoTrip/Services/EusoTripAPI.swift`,
  `${repoRoot}/EusoTrip/Views/Shipper/219_ShipperFreightClaims.swift`,
  `${repoRoot}/EusoTrip/Views/Vessel/809_VesselDisputeResolution.swift`,
  `${repoRoot}/EusoTrip/Views/Rail/594_RailCostBreakdown.swift`,
], { encoding: "utf8" });
checks.push([
  parse.status === 0,
  `Swift parser accepts every dispute consumer${parse.stderr ? `: ${parse.stderr.trim()}` : ""}`,
]);

const failures = checks.filter(([passed]) => !passed).map(([, message]) => message);
if (failures.length > 0) {
  console.error(`Dispute currency contract verification failed:\n- ${failures.join("\n- ")}`);
  process.exit(1);
}

console.log(`Dispute currency contract verification passed (${checks.length}/${checks.length}).`);
