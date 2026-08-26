#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const read = path => readFileSync(resolve(root, path), "utf8");
const client = read("EusoTrip/Services/PricedRouteCommerceClient.swift");
const panel = read(
  "EusoTrip/Views/Components/ModeAssetAvailabilityAuthorityPanel.swift"
);

const hosts = [
  ["EusoTrip/Views/Carrier/321_CarrierTruckPosting.swift", ".truck"],
  ["EusoTrip/Views/Rail/550_RailEngineerHome.swift", ".rail"],
  ["EusoTrip/Views/Rail/634_RailRailcarInventory.swift", ".rail"],
  ["EusoTrip/Views/Rail/688_RailConsistBoard.swift", ".rail"],
  ["EusoTrip/Views/Vessel/650_VesselOperatorHome.swift", ".vessel"],
  ["EusoTrip/Views/Vessel/683_VesselFleetHealth.swift", ".vessel"],
];

function requireText(source, token, label) {
  if (!source.includes(token)) {
    throw new Error(`${label}: missing ${JSON.stringify(token)}`);
  }
}

requireText(
  client,
  '"modeAssetAvailability.listPublishPrerequisites"',
  "typed prerequisite read"
);
for (const endpoint of ["publish", "listMine", "withdraw"]) {
  requireText(
    client,
    `"modeAssetAvailability.${endpoint}"`,
    `typed ${endpoint} boundary`
  );
}

for (const token of [
  "deadheadResponsibility",
  "positioningResponsibility",
  "emptyReturnResponsibility",
  "interchangePoints",
  "laycanStart",
  "laycanEnd",
  "portRangeUnlocodes",
  "maximumDraughtMillimeters",
  "availableDeadweightTonnage",
  "ballastResponsibility",
  "portApproachResponsibility",
]) {
  requireText(client + panel, token, "mode-native commercial terms");
}

requireText(panel, "prerequisite.asset.asset", "server-discovered asset identity");
requireText(
  panel,
  "observation.liveObservationId",
  "server-discovered observation identity"
);
requireText(
  panel,
  "routeProfileVersionID(covering: availableUntil)",
  "validity-aware optional route profile"
);
requireText(panel, "currentAllocation", "allocation truth");
requireText(panel, "blockers", "truthful prerequisite blockers");
requireText(
  panel,
  "I confirm this exact availability window",
  "explicit availability-window authorship"
);
requireText(
  panel,
  "I confirm this exact laycan",
  "explicit vessel laycan authorship"
);
requireText(panel, 'Text("Select payer")', "explicit responsibility authorship");

for (const assumedDefault of [
  '@State private var truckEquipmentTypes = "dry_van"',
  '@State private var truckPayloadKg = "20000"',
  '@State private var railCapacityKg = "90000"',
  '@State private var vesselMaximumDraughtMeters = "12"',
  '@State private var vesselAvailableDWT = "40000"',
]) {
  if (panel.includes(assumedDefault)) {
    throw new Error(`generic commercial default is forbidden: ${assumedDefault}`);
  }
}

for (const forbidden of [
  'TextField("Vehicle ID"',
  'TextField("Railcar ID"',
  'TextField("Consist ID"',
  'TextField("Vessel ID"',
  'TextField("Observation ID"',
  'TextField("Profile ID"',
]) {
  if (panel.includes(forbidden)) {
    throw new Error(`hidden identifier entry is forbidden: ${forbidden}`);
  }
}

for (const [path, mode] of hosts) {
  requireText(
    read(path),
    `ModeAssetAvailabilityLaunchCard(mode: ${mode})`,
    `${path} canonical capacity wiring`
  );
}

console.log(
  `PASS iOS mode-native availability: ${hosts.length} canonical host surfaces, server-discovered prerequisites, no manual hidden IDs`
);
