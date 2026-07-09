#!/usr/bin/env node
/**
 * Validate and print the release ladder used by TestFlight deployments.
 * A build is not "shipped" until upload is complete and App Store Connect
 * processing/availability are reported explicitly.
 */
import fs from "node:fs";
import path from "node:path";

const file = path.resolve(process.argv.find((arg) => arg.startsWith("--file="))?.slice(7) || "/tmp/eusotrip-release-ladder.json");
const required = ["compiled", "archived", "exported", "uploaded", "processing", "availableInTestFlight"];
const allowed = new Set(["pass", "fail", "pending", "manual_confirm_required", "not_run"]);

if (!fs.existsSync(file)) {
  console.error(`Release ladder file not found: ${file}`);
  console.error("Expected JSON keys: " + required.join(", "));
  process.exit(2);
}

let data;
try {
  data = JSON.parse(fs.readFileSync(file, "utf8"));
} catch (error) {
  console.error(`Unable to parse release ladder JSON: ${error.message}`);
  process.exit(2);
}

const errors = [];
for (const key of required) {
  if (!(key in data)) errors.push(`missing key ${key}`);
  else if (!allowed.has(String(data[key]))) errors.push(`invalid ${key}: ${data[key]}`);
}

console.log("Release ladder");
for (const key of required) {
  console.log(`- ${key}: ${data[key] ?? "missing"}`);
}

if (errors.length) {
  console.error(errors.join("\n"));
  process.exit(1);
}

const fullyAvailable = data.compiled === "pass"
  && data.archived === "pass"
  && data.exported === "pass"
  && data.uploaded === "pass"
  && data.processing === "pass"
  && data.availableInTestFlight === "pass";

if (!fullyAvailable) {
  console.error("Release is not TestFlight-available yet. Do not describe it as shipped.");
  process.exit(1);
}

console.log("Release is available in TestFlight.");
