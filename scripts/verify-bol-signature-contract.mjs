import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const driver = readFileSync(
  new URL("../EusoTrip/Views/Driver/DL120_DriverBackhaulCloseSextet.swift", import.meta.url),
  "utf8"
);
const shipper = readFileSync(
  new URL("../EusoTrip/Views/Shipper/306_BolCounterSign.swift", import.meta.url),
  "utf8"
);

for (const [name, source] of [["driver", driver], ["shipper", shipper]]) {
  assert.match(source, /loads\.getBOLForSigning/, `${name} must resolve the exact signable BOL`);
  assert.match(source, /EusoPDFViewer\(/, `${name} must review the authenticated PDF in-app`);
  assert.match(source, /checksumSha256/, `${name} must bind review state to the source checksum`);
  assert.match(source, /EusoGradientInkCanvas\.renderPNGBase64/, `${name} must submit real signature ink`);
  assert.match(source, /consentAccepted:\s*true/, `${name} must submit explicit e-sign consent`);
  assert.doesNotMatch(source, /signatureHash:\s*String\(sigHash\)/, `${name} must not mint a client signature hash`);
  assert.doesNotMatch(source, /\?\?\s*0\b/, `${name} must not collapse an invalid load ID to zero`);
}

assert.match(driver, /reviewedChecksum\s*!=\s*source\.checksumSha256/);
assert.match(shipper, /reviewedChecksum\s*!=\s*bolReview\?\.checksumSha256/);
assert.doesNotMatch(shipper, /role:\s*"shipper"/, "server must derive shipper capacity from live tenancy");

console.log("BOL signature contract verified for driver and shipper surfaces.");
