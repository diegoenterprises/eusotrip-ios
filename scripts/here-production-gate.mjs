#!/usr/bin/env node

import { existsSync, readFileSync, readdirSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const read = (path) => readFileSync(resolve(root, path), "utf8");
const failures = [];

function requireText(path, snippets) {
  const source = read(path);
  for (const snippet of snippets) {
    if (!source.includes(snippet)) {
      failures.push(`${path}: missing ${JSON.stringify(snippet)}`);
    }
  }
}

function denyText(path, snippets) {
  const source = read(path);
  for (const snippet of snippets) {
    if (source.includes(snippet)) {
      failures.push(`${path}: forbidden ${JSON.stringify(snippet)}`);
    }
  }
}

for (const path of [
  "EusoTrip/Services/HereMaps/HEREAuthService.swift",
  "EusoTrip/Services/HereMaps/HereBearerFetch.swift",
  "EusoTrip/Services/HereMaps/HereTileOverlay.swift",
]) {
  if (existsSync(resolve(root, path))) {
    failures.push(`${path}: obsolete mobile OAuth transport must not exist`);
  }
}

for (const path of [
  "EusoTrip/Info.plist",
  "EusoTrip.xcodeproj/project.pbxproj",
]) {
  denyText(path, [
    "HEREAccessKeyId",
    "HEREAccessKeySecret",
    "HERE_ACCESS_KEY_ID",
    "HERE_ACCESS_KEY_SECRET",
    "HERETokenEndpointURL",
    "HERE_TOKEN_ENDPOINT_URL",
  ]);
}

const proxyContracts = new Map([
  ["EusoTrip/Services/HereMaps/HereRoutingClient.swift", "hereMaps.route"],
  ["EusoTrip/Services/HereMaps/HereGeocodingClient.swift", "hereMaps.geocode"],
  ["EusoTrip/Services/HereMaps/HereMatrixClient.swift", "hereMaps.matrix"],
  ["EusoTrip/Services/HereMaps/HereFuelPricesClient.swift", "hereMaps.fuelPricesNearby"],
  ["EusoTrip/Services/HereMaps/HereWeatherClient.swift", "hereMaps.weatherAt"],
  ["EusoTrip/Services/HereMaps/HereTrafficClient.swift", "hereMaps.trafficFlow"],
  ["EusoTrip/Services/HereMaps/HereEVClient.swift", "hereMaps.evChargers"],
  ["EusoTrip/Services/HereMaps/HereParkingClient.swift", "hereMaps.parkingNearby"],
  ["EusoTrip/Services/HereMaps/HereSafetyCamerasClient.swift", "hereMaps.safetyCamerasAt"],
]);

for (const [path, procedure] of proxyContracts) {
  requireText(path, [procedure]);
  denyText(path, [
    "requireBearerToken",
    "HEREAuthService",
    "HereBearerFetch",
  ]);
}

requireText("EusoTrip/Services/HereMaps/HereMapWebView.swift", [
  "createDefaultLayers({tileSize:512,ppi:200})",
  "dl.vector.normal.map",
  "dl.raster.normal.mapnight",
  "jsTrustedReferrerOrigin",
  "var isUsableCoordinate: Bool",
  ".filter(\\.isUsableCoordinate)",
]);

requireText("EusoTrip/Views/Components/HereMapView.swift", [
  "drawing a straight segment through land or water fabricates",
  "HereRoutingClient.polyline(for: route)",
]);

for (const area of ["EusoTrip/Views", "EusoTrip/Services", "EusoTrip/ViewModels"]) {
  const areaRoot = resolve(root, area);
  for (const entry of readdirSync(areaRoot, { recursive: true, withFileTypes: true })) {
    if (!entry.isFile() || !entry.name.endsWith(".swift")) continue;
    const path = resolve(entry.parentPath, entry.name);
    const source = readFileSync(path, "utf8");
    const nullFirst = /HereLatLng\(\s*[^,\n]*\?\?\s*0(?:\.0+)?(?![\d.])\s*,/;
    const nullSecond = /HereLatLng\(\s*[^,\n]+,\s*[^,\n]*\?\?\s*0(?:\.0+)?(?![\d.])(?:\s*,|\s*\))/;
    if (nullFirst.test(source) || nullSecond.test(source)) {
      failures.push(`${path}: HERE layer coordinate may manufacture null-island data`);
    }
  }
}

if (failures.length) {
  console.error("HERE production gate failed:");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(
  `HERE production gate passed: ${proxyContracts.size} native clients use typed backend procedures; labeled ppi=200 basemaps and no mobile REST secret path.`,
);
