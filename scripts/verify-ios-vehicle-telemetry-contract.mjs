#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const api = readFileSync(
  resolve(root, "EusoTrip/Services/EusoTripAPI.swift"),
  "utf8",
);
const vehicleView = readFileSync(
  resolve(root, "EusoTrip/Views/Driver/059_VehicleAndEquipment.swift"),
  "utf8",
);
const start = api.indexOf("struct VehicleAPI {");
const end = api.indexOf("// MARK: - VehiclesAPI", start);
if (start < 0 || end < 0) throw new Error("VehicleAPI section not found");
const vehicleAPI = api.slice(start, end);

const failures = [];
const requireText = (source, needle, label) => {
  if (!source.includes(needle)) failures.push(`${label}: missing ${needle}`);
};
const forbidText = (source, needle, label) => {
  if (source.includes(needle)) failures.push(`${label}: forbidden ${needle}`);
};

for (const field of ["odometer", "fuelLevel", "speed", "heading"]) {
  requireText(
    vehicleAPI,
    `let ${field}: Double?`,
    `${field} null preservation`,
  );
}
requireText(vehicleAPI, "struct MetricProvenance", "metric provenance decoder");
requireText(
  vehicleAPI,
  "struct TelemetryProvenance",
  "telemetry provenance decoder",
);
requireText(vehicleAPI, "return nil", "missing telemetry remains nil");
forbidText(
  vehicleAPI,
  "var odometer: Int       { vehicle?.odometer ?? 0 }",
  "assigned odometer zero fallback",
);
forbidText(
  vehicleAPI,
  "var fuelLevel: Double   { vehicle?.fuelLevel ?? 0 }",
  "assigned fuel zero fallback",
);
forbidText(
  vehicleView,
  "v.odometer > 0",
  "odometer presence inferred from value",
);
forbidText(vehicleView, "v.fuelLevel > 0", "fuel presence inferred from value");
requireText(vehicleView, '?? "—"', "vehicle telemetry unavailable display");
requireText(
  vehicleView,
  "metric?.tracked == true",
  "vehicle provenance display gate",
);

if (failures.length) {
  console.error(
    `iOS vehicle telemetry contract failed:\n- ${failures.join("\n- ")}`,
  );
  process.exit(1);
}

console.log("iOS vehicle telemetry null/provenance contract verified.");
