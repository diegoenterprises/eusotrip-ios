#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const root = process.cwd();
const read = (relativePath) => fs.readFileSync(path.join(root, relativePath), "utf8");
const stripComments = (source) => source
  .replace(/\/\*[\s\S]*?\*\//g, "")
  .replace(/\/\/.*$/gm, "");
const section = (source, start, end) => {
  const startIndex = source.indexOf(start);
  if (startIndex < 0) return "";
  const endIndex = source.indexOf(end, startIndex + start.length);
  return source.slice(startIndex, endIndex < 0 ? source.length : endIndex);
};

const service = read("EusoTrip/Services/WeatherService.swift");
const snapshot = read("EusoTrip/Models/WeatherSnapshot.swift");
const hereClient = read("EusoTrip/Services/HereMaps/HereWeatherClient.swift");
const adapter = read("EusoTrip/Services/HereMaps/HereWeatherAdapter.swift");
const store = read("EusoTrip/ViewModels/WeatherCardStore.swift");
const widget = read("EusoTrip/Views/Components/HomeWeatherWidget.swift");
const card = read("EusoTrip/Views/Components/WeatherCard.swift");
const perLoad = read("EusoTrip/Views/Components/PerLoadWeatherCard.swift");
const sky = read("EusoTrip/Views/Components/WeatherSkyEngine.swift");
const driverStore = read("EusoTrip/ViewModels/DriverHomeViewModel.swift");
const driverHome = read("EusoTrip/Views/Driver/010_DriverHome.swift");
const railRoute = read("EusoTrip/Views/Rail/578_RailRouteWeather.swift");
const railDisruption = read("EusoTrip/Views/Rail/579_RailNetworkDisruption.swift");
const app = read("EusoTrip/EusoTripApp.swift");

const weatherHomeHosts = [
  "EusoTrip/Views/Admin/800_AdminHome.swift",
  "EusoTrip/Views/Broker/400_BrokerHome.swift",
  "EusoTrip/Views/Carrier/300_CarrierHome.swift",
  "EusoTrip/Views/Catalyst/300_CatalystHome.swift",
  "EusoTrip/Views/Catalyst/500_CatalystHome.swift",
  "EusoTrip/Views/Compliance/900_ComplianceOfficerHome.swift",
  "EusoTrip/Views/Dispatch/400_DispatcherHome.swift",
  "EusoTrip/Views/Driver/010_DriverHome.swift",
  "EusoTrip/Views/Escort/600_EscortHome.swift",
  "EusoTrip/Views/Rail/001_RailShipperHome.swift",
  "EusoTrip/Views/Rail/550_RailEngineerHome.swift",
  "EusoTrip/Views/Shipper/200_ShipperHome.swift",
  "EusoTrip/Views/Terminal/700_TerminalHome.swift",
  "EusoTrip/Views/Vessel/001_VesselShipperHome.swift",
  "EusoTrip/Views/Vessel/650_VesselOperatorHome.swift",
].map((relativePath) => [relativePath, read(relativePath)]);

const ambientChain = stripComments(section(
  service,
  "private func fetchCurrentUncached(",
  "// MARK: - Server weather"
));
const serverAmbient = stripComments(section(
  service,
  "private func fetchServerWeather(",
  "// Wire types for the tRPC `weather.laneImpact`"
));
const celestial = stripComments(section(
  sky,
  "private var celestialLayer: some View",
  "// MARK: 3"
));
const nightCelestial = section(celestial, "case .night:", "case .daylight:");
const daylightCelestial = section(celestial, "case .daylight:", "case .unknown:");

const failures = [];
const deny = [
  ["server wind default", service, /cur\.windKph\s*\?\?\s*0/],
  ["HERE temperature default", adapter, /return\s+0|temperature[^\n]*\?\?\s*0/],
  ["HERE wind default", adapter, /wind(?:Mph|Speed)[^\n]*\?\?\s*0/],
  ["unsafe HERE integer conversion", adapter, /Int\([^\n]*\.rounded\(\)\)/],
  ["unsafe per-load integer conversion", perLoad, /Int\([^\n]*\.rounded\(\)\)/],
  ["fabricated per-load hourly temperature", perLoad, /tempF:\s*hp\.tempF\s*\?\?\s*0/],
  ["fabricated per-load hourly timestamp", perLoad, /date:\s*hp\.time\s*\?\?\s*\.distantPast/],
  ["destination snapshot hook on ambient hero", widget, /preferredSnapshot/],
  ["driver HERE snapshot replacing ambient state", driverStore, /self\.weather\s*=\s*(?:destSnap|originSnap|snap)/],
  ["HERE in active ambient chain", ambientChain, /HereWeather|fromHereWeather|\.here/],
  ["NWS in active ambient chain", ambientChain, /fetchNWS\s*\(/],
  ["Open-Meteo in active ambient chain", ambientChain, /fetchOpenMeteo\s*\(/],
  ["unapproved HERE ambient source", serverAmbient, /case\s+"here"|dataSource\s*=\s*\.here/],
  ["unapproved NWS ambient source", serverAmbient, /case\s+"nws"|dataSource\s*=\s*\.nws/],
  ["unapproved Open-Meteo ambient source", serverAmbient, /case\s+"openmeteo"|dataSource\s*=\s*\.openMeteo/],
  ["sun rendered in night branch", nightCelestial, /SunBody/],
  ["moon rendered in daylight branch", daylightCelestial, /MoonPhaseView|StarField/],
  ["stale WeatherKit-only rail doctrine", railRoute, /Apple WeatherKit-sourced|Apple WeatherKit per-segment/],
];

for (const [label, source, pattern] of deny) {
  if (pattern.test(source)) failures.push(`forbidden ${label}`);
}

const approvedAmbientCases = new Set(["weatherkit", "openweather"]);
const decodedAmbientCases = [...serverAmbient.matchAll(/case\s+"([^"]+)":/g)]
  .map((match) => match[1]);
for (const source of decodedAmbientCases) {
  if (!approvedAmbientCases.has(source)) {
    failures.push(`forbidden ambient source alias ${source}`);
  }
}
for (const source of approvedAmbientCases) {
  if (!decodedAmbientCases.includes(source)) {
    failures.push(`missing ambient source alias ${source}`);
  }
}

for (const [relativePath, source] of weatherHomeHosts) {
  if (!source.includes(".eusoRefreshable")) {
    failures.push(`missing native weather pull refresh on ${relativePath}`);
  }
}

const requireText = [
  ["finite-number boundary", service, "guard let value, value.isFinite else { return nil }"],
  ["WeatherKit ambient primary", ambientChain, "weatherService.weather(for: location)"],
  ["attributed server ambient fallback", ambientChain, "fetchServerWeather("],
  ["WeatherKit ambient allowlist", serverAmbient, 'case "weatherkit":'],
  ["OpenWeather ambient allowlist", serverAmbient, 'case "openweather":'],
  ["missing freshness remains missing", serverAmbient, "snap.observedAt = parseDate(server.fetchedAt)"],
  ["unknown source is honest", snapshot, 'case .unknown:    return "source unavailable"'],
  ["HERE attribution is explicit", snapshot, 'case .here:       return "HERE route weather"'],
  ["HERE route provenance", adapter, "snap.dataSource = .here"],
  ["HERE provider timestamp", hereClient, "let utcTime: String?"],
  ["HERE timestamp decoding", adapter, "snap.observedAt = Self.providerDate(obs.utcTime)"],
  ["approved per-load forecast source", store, "AmbientWeatherSourcePolicy.attribution(for: source)"],
  ["approved per-load alert source", store, "rows.filter { AmbientWeatherSourcePolicy.attribution(for: $0.source) != nil }"],
  ["ambient hero remains local", widget, "WeatherCard(snapshot: displaySnapshot(snap), lane: lane)"],
  ["HERE route strip remains wired", driverHome, "lane: vm.laneWeather"],
  ["ambient callback remains authoritative", driverStore, "if weather != snapshot { weather = snapshot }"],
  ["per-load forecast attribution", perLoad, "Forecast · \\(forecastSource)"],
  ["per-load real hourly filtering", perLoad, "guard let time = hp.time, let tempF = hp.tempF else { return nil }"],
  ["rail HERE attribution", railRoute, 'return "HERE ROUTE WEATHER"'],
  ["rail WeatherKit fallback attribution", railRoute, 'return "APPLE WEATHERKIT FALLBACK"'],
  ["rail route source gate", railRoute, "guard routeSourceAttribution != nil else { return false }"],
  ["rail alert source gate", railRoute, "approvedAmbientAlertSource($0.source)"],
  ["rail disruption alert source gate", railDisruption, "approvedAmbientAlertSource($0.source)"],
  ["canonical solar state", snapshot, "func displaySolarState(at displayDate: Date = Date())"],
  ["fresh hint ceiling", snapshot, "abs(displayDate.timeIntervalSince($0)) <= 20 * 60"],
  ["exclusive night branch", celestial, "case .night:"],
  ["exclusive daylight branch", celestial, "case .daylight:"],
  ["neutral unknown solar branch", celestial, "case .unknown:"],
  ["card presentation clock", card, "snapshot.displaySolarState(at: displayDate)"],
  ["weather pull refresh handler", widget, ".eusoRefreshHandler(domains: [.weather])"],
  ["forced pull refresh", widget, "await refresh(force: true)"],
  ["refresh advances solar clock", widget, "NotificationCenter.default.post(name: .eusoWeatherDisplayClockChanged"],
  ["foreground staleness refresh", app, "reason: .staleForeground"],
  ["foreground solar refresh", app, "name: .eusoWeatherDisplayClockChanged"],
  ["clock transition weather invalidation", app, "invalidateVisibleDomain(.weather)"],
  ["lane rows default collapsed", card, "@State private var expandedLaneIDs: Set<String> = []"],
  ["lane list defaults bounded", card, "@State private var showAllLaneImpacts = false"],
  ["lane list initial cap", card, "min(3, ranked.count)"],
  ["lane details render on disclosure", card, "if isOpen {"],
  ["ESANG analysis remains on demand", card, "Ask ESANG about this load"],
];

for (const [label, source, needle] of requireText) {
  if (!source.includes(needle)) failures.push(`missing ${label}`);
}

if (failures.length) {
  console.error("Weather production gate failed:");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log("Weather production gate passed: authority, provenance, numerics, solar exclusivity, and refresh contracts verified.");
