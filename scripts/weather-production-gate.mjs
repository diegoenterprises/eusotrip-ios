#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const root = process.cwd();
const servicePath = path.join(root, "EusoTrip/Services/WeatherService.swift");
const widgetPath = path.join(root, "EusoTrip/Views/Components/HomeWeatherWidget.swift");
const adapterPath = path.join(root, "EusoTrip/Services/HereMaps/HereWeatherAdapter.swift");
const cardPath = path.join(root, "EusoTrip/Views/Components/PerLoadWeatherCard.swift");

const service = fs.readFileSync(servicePath, "utf8");
const widget = fs.readFileSync(widgetPath, "utf8");
const adapter = fs.readFileSync(adapterPath, "utf8");
const card = fs.readFileSync(cardPath, "utf8");
const all = [service, widget, adapter, card].join("\n");

const failures = [];
const deny = [
  ["server wind default", /cur\.windKph\s*\?\?\s*0/],
  ["NWS wind default", /p\.windSpeed\?\.value\s*\?\?\s*0/],
  ["HERE temperature default", /rt\?\.temperature\s*\?\?\s*0/],
  ["HERE wind default", /rt\?\.windSpeedMph\s*\?\?\s*0/],
  ["duplicate NWS location parameter", /private func fetchNWS\(\s*location:\s*CLLocation,\s*location:/s],
  ["duplicate adjacent lane-impact request", /(snap\.laneImpact\s*=\s*await fetchLaneImpact\(\)\s*){2}/],
];

for (const [label, pattern] of deny) {
  if (pattern.test(all)) failures.push(`forbidden ${label}`);
}

const requireText = [
  ["HERE provenance", service, 'case "here":        snap.dataSource = .here'],
  ["unknown provenance", service, "default:            snap.dataSource = .unknown"],
  ["real NWS wind requirement", service, "let windKmh = p.windSpeed?.value, windKmh.isFinite"],
  ["real server wind requirement", service, "let windKph = cur.windKph"],
  ["recoverable weather card", widget, "Tap to retry live local conditions."],
  ["HERE weather coordinates", adapter, "snap.latitude = latitude"],
  ["optional animated sky", card, "private func heroSkySnapshot(_ card: WeatherForLoad) -> WeatherSnapshot?"],
];

for (const [label, source, needle] of requireText) {
  if (!source.includes(needle)) failures.push(`missing ${label}`);
}

if (failures.length) {
  console.error("Weather production gate failed:");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log("Weather production gate passed.");
