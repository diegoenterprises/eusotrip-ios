import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = (relativePath) =>
  fs.readFileSync(path.join(root, relativePath), "utf8");
const occurrences = (source, needle) => source.split(needle).length - 1;

const swiftFiles = [];
const collectSwift = (directory) => {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      if (entry.name.startsWith(".pre-")) continue;
      collectSwift(absolute);
    } else if (entry.isFile() && entry.name.endsWith(".swift")) {
      const relative = path.relative(root, absolute);
      if (/ELD|Eld/.test(relative)) continue;
      swiftFiles.push(relative);
    }
  }
};
collectSwift(path.join(root, "EusoTrip"));

const parser = read("EusoTrip/Utilities/LatLongParser.swift");
const eusoAddress = read("EusoTrip/Theme/Components/EusoAddressField.swift");
const hereAddress = read("EusoTrip/Views/Components/HereAddressField.swift");
const driverHome = read("EusoTrip/ViewModels/DriverHomeViewModel.swift");
const traffic = read("EusoTrip/Services/HereMaps/HereTrafficClient.swift");
const geocoding = read("EusoTrip/Services/HereMaps/HereGeocodingClient.swift");
const routeModels = read("EusoTrip/Services/HereMaps/HereRouteModels.swift");
const hereRenderer = read("EusoTrip/Services/HereMaps/HereMapWebView.swift");
const lifecycleGeocode = read(
  "EusoTrip/Services/HereMaps/LifecycleGeocodeStore.swift",
);
const geofences = read("EusoTrip/Services/GeofenceService.swift");
const watchCommands = read("EusoTrip/Services/WatchCommandHandler.swift");
const carrierActiveLoad = read(
  "EusoTrip/Views/Carrier/311_CarrierActiveLoad.swift",
);
const carrierDrivers = read(
  "EusoTrip/Views/Carrier/319_CarrierDriversList.swift",
);
const catalystAwarded = read(
  "EusoTrip/Views/Catalyst/373_CatalystAwardedCelM04.swift",
);
const catalystTransit = read(
  "EusoTrip/Views/Catalyst/375_CatalystInTransitFleetTrackCelM04.swift",
);
const catalystDelivery = read(
  "EusoTrip/Views/Catalyst/376_CatalystAtDeliveryFleetTrackCelM04.swift",
);
const catalystCapacity = read(
  "EusoTrip/Views/Catalyst/402_CatalystCapacityPlanner.swift",
);
const zeun = read("EusoTrip/Views/Driver/ZeunMechanicsScreens.swift");
const pickupBoard = read(
  "EusoTrip/Views/Dispatch/517_DispatcherBhPickupBoardFired.swift",
);
const transitCard = read(
  "EusoTrip/Views/Dispatch/518_DispatcherBhInTransitCard.swift",
);
const activeEnroute = read("EusoTrip/Views/Driver/013_ActiveEnroute.swift");
const approachingPickup = read(
  "EusoTrip/Views/Driver/014_ApproachingPickup.swift",
);
const railYards = read("EusoTrip/Views/Rail/628_RailYardMap.swift");
const terminalYards = read("EusoTrip/Views/Terminal/700_TerminalHome.swift");
const convoy = read("EusoTrip/Views/Components/ConvoyAnimationStrip.swift");
const portCalls = read("EusoTrip/Views/Vessel/661_VesselPortCalls.swift");
const marineWeather = read(
  "EusoTrip/Views/Vessel/671_VesselMarineWeatherRouting.swift",
);
const sosEmergency = read("EusoTrip/Views/Components/SOSEmergencySheet.swift");
const axleScale = read("EusoTrip/Views/Driver/170B_DriverAxleScaleWeigh.swift");
const loadModel = read("EusoTrip/Models/Load.swift");
const routingClient = read(
  "EusoTrip/Services/HereMaps/HereRoutingClient.swift",
);
const mapView = read("EusoTrip/Views/Components/HereMapView.swift");
const driverTabs = read("EusoTrip/Views/Driver/DriverTabPanes.swift");
const boardAdapter = read("EusoTrip/Views/Driver/108_MeLoadBoard.swift");
const loadAdapters = read(
  "EusoTrip/Views/Components/LoadDetailSheet+Adapters.swift",
);
const loadDetail = read("EusoTrip/Views/Components/LoadDetailSheet.swift");
const vesselCrossBorder = read(
  "EusoTrip/Views/Vessel/750_VesselCrossBorderPorts.swift",
);
const apiModels = read("EusoTrip/Services/EusoTripAPI.swift");
const hotZonesWidget = read("EusoTrip/Views/Driver/HotZonesWidget.swift");
const driverResolver = read("EusoTrip/Services/DriverLocationResolver.swift");
const gpsPush = read("EusoTrip/Services/DriverGPSPushService.swift");
const weatherService = read("EusoTrip/Services/WeatherService.swift");
const turnNavigator = read(
  "EusoTrip/Services/HereMaps/TurnByTurnNavigator.swift",
);
const hereAddOns = read("EusoTrip/Services/HereMaps/HereAddOns.swift");
const hereEV = read("EusoTrip/Services/HereMaps/HereEVClient.swift");
const hereParking = read("EusoTrip/Services/HereMaps/HereParkingClient.swift");
const hereFuel = read("EusoTrip/Services/HereMaps/HereFuelPricesClient.swift");
const hereCameras = read(
  "EusoTrip/Services/HereMaps/HereSafetyCamerasClient.swift",
);
const railYardOperations = read(
  "EusoTrip/Views/Rail/559_RailYardOperations.swift",
);
const dispatchTrio = read("EusoTrip/Views/Dispatch/Dpch714_DispatchTrio.swift");
const vesselLive = read("EusoTrip/Views/Vessel/003_VesselLiveTracking.swift");
const vesselOceanTrack = read(
  "EusoTrip/Views/Vessel/VesselOceanTrackMap.swift",
);
const multimodalCore = read("EusoTrip/Models/Multimodal/MultiModalCore.swift");
const mapProjection = read(
  "EusoTrip/Views/Components/Map/BespokeMapProjection.swift",
);
const bespokeMap = read("EusoTrip/Views/Components/Map/BespokeMapCanvas.swift");
const mapGeography = read(
  "EusoTrip/Views/Components/Map/BespokeMapGeography.swift",
);

for (const relative of swiftFiles) {
  const source = read(relative)
    .replace(/\/\/.*$/gm, "")
    .replace(/\/\*[\s\S]*?\*\//g, "");
  assert.doesNotMatch(
    source,
    /\b(?:lat|lng|lon|latitude|longitude)\??\s*\?\?\s*0(?:\.0+)?\b/,
    `${relative} fabricates a missing coordinate axis as zero`,
  );
  assert.doesNotMatch(
    source,
    /\b(?:lat|latitude)\b\s*!=\s*0(?:\.0+)?\b\s*&&\s*\b(?:lng|lon|longitude)\b\s*!=\s*0(?:\.0+)?\b/,
    `${relative} rejects a legitimate zero coordinate axis with a truthiness pair`,
  );
  assert.doesNotMatch(
    source,
    /\b(?:lng|lon|longitude)\b\s*!=\s*0(?:\.0+)?\b\s*&&\s*\b(?:lat|latitude)\b\s*!=\s*0(?:\.0+)?\b/,
    `${relative} rejects a legitimate zero coordinate axis with a truthiness pair`,
  );
}

for (const seam of [
  "parseDMSPair",
  "parseGeoURI",
  "parseKnownMapURL",
  "validatedCoordinate",
  "displayString",
  "hasCoordinateIntent",
]) {
  assert.ok(parser.includes(seam), `LatLongParser is missing ${seam}`);
}
assert.ok(
  !parser.includes("!(latitude == 0 && longitude == 0)"),
  "The canonical validity gate must preserve the valid WGS-84 coordinate 0,0",
);
assert.ok(
  !parser.includes("latitude != 0 && longitude != 0"),
  "A legitimate zero on one coordinate axis must not be rejected",
);

assert.ok(eusoAddress.includes("LatLongParser.parseDetailed(cleaned)"));
assert.ok(eusoAddress.includes("text: parsed.originalText"));
assert.ok(eusoAddress.includes("coordinate: parsed.coordinate"));
const reverseEnrichment = eusoAddress.slice(
  eusoAddress.indexOf("private func reverseResolve"),
  eusoAddress.indexOf("private func subtitle"),
);
assert.ok(reverseEnrichment.includes("hit.formattedAddress("));
assert.ok(reverseEnrichment.includes("HereAddressFormatter.unknownLabel"));
assert.ok(
  !reverseEnrichment.includes("self.value ="),
  "Reverse geocoding must never replace the user's exact coordinate or input text",
);

assert.ok(hereAddress.includes("LatLongParser.parse(newValue)"));
assert.ok(hereAddress.includes("LatLongParser.displayString(coordinate)"));
assert.ok(
  !hereAddress.includes("private func parseCoords"),
  "HereAddressField must not drift back to a second coordinate parser",
);
const handleChange = hereAddress.slice(
  hereAddress.indexOf("private func handleTextChange"),
  hereAddress.indexOf("private func fetchAutosuggest"),
);
assert.ok(
  handleChange.indexOf("if suppressNextSuggest") <
    handleChange.indexOf("if lat != nil || lng != nil"),
  "Assigning a confirmed HERE label must not clear its coordinate",
);

assert.ok(driverHome.includes("LatLongParser.validatedCoordinate"));
assert.ok(!driverHome.includes("pu.lat != 0, pu.lng != 0"));
assert.ok(!driverHome.includes("drop.lat != 0, drop.lng != 0"));

assert.ok(!traffic.includes("points?.first?.lat ?? 0"));
assert.ok(!traffic.includes("points?.first?.lng ?? 0"));
assert.ok(traffic.includes("unlocated-"));
assert.ok(
  geocoding.includes(
    "LatLongParser.validatedCoordinate(latitude: lat, longitude: lng)",
  ),
);
assert.ok(!geocoding.includes("abs(lat) > 0.0001"));
assert.ok(routeModels.includes("enum HereAddressProvenance"));
assert.ok(routeModels.includes("case hereReverseGeocode"));
assert.ok(routeModels.includes("country: country"));
assert.ok(routeModels.includes('static let unknownLabel = "Unknown address"'));
assert.ok(
  eusoAddress.includes("provenance: resolved.formattedAddress.provenance"),
);
assert.ok(
  hereRenderer.includes(
    "LatLongParser.validatedCoordinate(latitude: lat, longitude: lng)",
  ),
);
assert.ok(
  hereRenderer.includes('"coordinateLabel": LatLongParser.displayString'),
);
assert.ok(hereRenderer.includes('endpointLabelToggle && m.kind==="delivery"'));
assert.ok(!hereRenderer.includes("HERE JS apiKey not configured"));
assert.ok(lifecycleGeocode.includes("LatLongParser.validatedCoordinate"));
assert.ok(!lifecycleGeocode.includes("lat != 0 || lng != 0"));
assert.ok(geofences.includes("LatLongParser.validatedCoordinate"));
assert.ok(
  occurrences(
    geofences,
    "let eventCoordinate = LatLongParser.validatedCoordinate",
  ) === 3,
);
assert.ok(watchCommands.includes("LatLongParser.validatedCoordinate"));
assert.ok(!watchCommands.includes('payload["latitude"] = lat'));

assert.ok(carrierActiveLoad.includes("LatLongParser.displayString"));
assert.ok(carrierActiveLoad.includes("LatLongParser.validatedCoordinate"));
assert.ok(
  !carrierActiveLoad.includes(
    'String(format: "%.4f, %.4f", g.latitude, g.longitude)',
  ),
);

for (const [name, source] of [
  ["carrier driver roster", carrierDrivers],
  ["catalyst awarded load", catalystAwarded],
  ["catalyst in-transit fleet", catalystTransit],
  ["catalyst delivery fleet", catalystDelivery],
]) {
  assert.ok(
    source.includes("LatLongParser.parse(") ||
      source.includes("LatLongParser.validatedCoordinate("),
    `${name} bypasses the canonical parser`,
  );
  assert.ok(
    !/split\(separator:\s*","\)[\s\S]{0,300}Double\(/.test(source),
    `${name} contains a second coordinate parser`,
  );
}
assert.ok(catalystCapacity.includes("LatLongParser.validatedCoordinate"));
assert.ok(!catalystCapacity.includes("abs(lat) < 0.000001"));
assert.ok(zeun.includes("LatLongParser.validatedCoordinate"));
assert.ok(!zeun.includes("coord?.latitude ?? 0"));
assert.ok(!zeun.includes("coord?.longitude ?? 0"));

for (const [name, source] of [
  ["active enroute", activeEnroute],
  ["rail yard map", railYards],
  ["terminal yard map", terminalYards],
  ["convoy composition", convoy],
  ["marine weather routing", marineWeather],
]) {
  assert.ok(
    source.includes("LatLongParser.validatedCoordinate"),
    `${name} lacks canonical validation`,
  );
}
assert.ok(
  !approachingPickup.includes("HereRoutingClient"),
  "approaching pickup must not author a client-side route",
);
assert.ok(!railYards.includes("coordinates?.lat ?? 0"));
assert.ok(!railYards.includes("coordinates?.lng ?? 0"));
assert.ok(!terminalYards.includes("y.lat ?? 0"));
assert.ok(!terminalYards.includes("y.lng ?? 0"));
assert.ok(!convoy.includes("pickupLocation?.lat ?? 0"));
assert.ok(!convoy.includes("deliveryLocation?.lat ?? 0"));
assert.ok(!portCalls.includes("pts.map(\\.lat).max() ?? 0"));

assert.ok(
  sosEmergency.includes("LatLongParser.parseDetailed(trimmedLocation)"),
);
assert.ok(
  sosEmergency.includes("LatLongParser.hasCoordinateIntent(trimmedLocation)"),
);
assert.ok(
  sosEmergency.includes(
    "let submittedCoordinate = manualCoordinate ?? deviceCoordinate",
  ),
);
assert.ok(sosEmergency.includes('"manual_coordinates"'));
assert.ok(sosEmergency.includes("addressHint: manualLocation?.originalText"));
assert.ok(!sosEmergency.includes("latitude: location?.coordinate.latitude"));
assert.ok(!sosEmergency.includes("longitude: location?.coordinate.longitude"));

assert.ok(axleScale.includes("LatLongParser.validatedCoordinate"));
assert.ok(
  axleScale.includes("DriverLocationResolver.shared.currentLocation()"),
);
assert.ok(
  axleScale.includes(
    "capturedAt: ISO8601DateFormatter().string(from: location.timestamp)",
  ),
);
assert.ok(axleScale.includes('else { return "Not recorded" }'));
assert.ok(
  axleScale.includes("Location is unavailable, so the weigh was not recorded."),
);
assert.ok(!axleScale.includes("coord?.latitude ?? 0"));
assert.ok(!axleScale.includes("coord?.longitude ?? 0"));

assert.ok(loadModel.includes("let lat: Double?"));
assert.ok(loadModel.includes("let lng: Double?"));
assert.ok(loadModel.includes("static let empty = LoadLocation"));
assert.ok(loadModel.includes("lat: nil, lng: nil"));
assert.ok(
  loadModel.includes("var coordinatePair: (lat: Double, lng: Double)?"),
);
assert.ok(loadModel.includes("LatLongParser.validatedCoordinate"));
assert.ok(loadModel.includes("LatLongParser.displayString"));
assert.ok(!loadModel.includes("lat: lat ?? 0"));
assert.ok(!loadModel.includes("lng: lng ?? 0"));
assert.ok(loadModel.includes("try c.encodeNil(forKey: .pickupCoord)"));
assert.ok(loadModel.includes("try c.encodeNil(forKey: .deliveryCoord)"));

assert.ok(
  routingClient.includes(
    "let pickupCoordinate = LatLongParser.validatedCoordinate",
  ),
);
assert.ok(
  routingClient.includes(
    "let deliveryCoordinate = LatLongParser.validatedCoordinate",
  ),
);
assert.ok(routingClient.includes('"\\(c.latitude),\\(c.longitude)"'));
assert.ok(!routingClient.includes('String(format: "%.'));
assert.ok(mapView.includes("guard let lat = stop.lat, let lng = stop.lng"));
assert.ok(mapView.includes("isInvalidCoordinate"));
assert.ok(!mapView.includes("isNullIsland"));
assert.ok(driverTabs.includes("let originLat: Double?"));
assert.ok(driverTabs.includes("let destLat: Double?"));
assert.ok(driverTabs.includes("var originCoordinate: CLLocationCoordinate2D?"));
assert.ok(
  driverTabs.includes("var destinationCoordinate: CLLocationCoordinate2D?"),
);
assert.ok(boardAdapter.includes("originLat: nil"));
assert.ok(boardAdapter.includes("destLat: nil"));
assert.ok(!boardAdapter.includes("originLat: 0"));
assert.ok(!boardAdapter.includes("destLat: 0"));
assert.ok(
  loadAdapters.includes("let hasCoordinatePair = oReal != nil && dReal != nil"),
);
assert.ok(!loadAdapters.includes("(oLat, oLng) = (0, 0)"));
assert.ok(loadDetail.includes("routeCoordinates(for: detail)"));
assert.ok(!loadDetail.includes("latitude: detail.originLat"));
assert.ok(!loadDetail.includes("longitude: detail.destLng"));
assert.ok(!loadDetail.includes("abs(c.latitude - 39.8283)"));
assert.ok(!driverTabs.includes("abs(coordinate.latitude - conusLat)"));
assert.ok(!vesselCrossBorder.includes("lng ?? 0"));
assert.ok(apiModels.includes("let center: HotZoneCenter?"));
assert.ok(
  apiModels.includes(
    "Hot-zone center must be a complete, valid coordinate pair",
  ),
);
assert.ok(!apiModels.includes("HotZoneCenter(lat: 0, lng: 0)"));
assert.ok(
  !apiModels.includes(
    "private static func coord(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double {",
  ),
);
assert.ok(hotZonesWidget.includes("private var locatedHotZones"));
assert.ok(!hotZonesWidget.includes("z.center.lat == 0"));
assert.ok(
  !hotZonesWidget.includes(
    "guard let s = c.liveSurge, s > 0 else { return 0.6 }",
  ),
);

const resolverIngest = driverResolver.slice(
  driverResolver.indexOf("func ingest(externalFix"),
  driverResolver.indexOf("private func drainPending"),
);
assert.ok(resolverIngest.includes("LatLongParser.validatedCoordinate"));
assert.ok(!resolverIngest.includes("lastCoordinate = loc.coordinate"));
const resolverDelegate = driverResolver.slice(
  driverResolver.lastIndexOf("didUpdateLocations"),
);
assert.ok(resolverDelegate.includes("LatLongParser.validatedCoordinate"));
assert.ok(driverResolver.includes("private func discardLocationEvidence"));
assert.ok(driverResolver.includes("lastLocation = nil"));

assert.ok(gpsPush.includes("age < 60, LatLongParser.isValid(fix.coordinate)"));
const weatherDelegate = weatherService.slice(
  weatherService.lastIndexOf("didUpdateLocations"),
);
assert.ok(weatherDelegate.includes("LatLongParser.isValid(s.coordinate)"));
assert.ok(turnNavigator.includes("coords.allSatisfy(LatLongParser.isValid)"));
assert.ok(turnNavigator.includes("LatLongParser.isValid(fix.coordinate)"));

for (const [name, source] of [
  ["HERE EV", hereEV],
  ["HERE parking", hereParking],
  ["HERE fuel", hereFuel],
  ["HERE cameras", hereCameras],
]) {
  assert.ok(
    source.includes("latitude: center.latitude") &&
      source.includes("longitude: center.longitude"),
    `${name} does not validate its query coordinate`,
  );
  assert.ok(
    source.includes("Location is unavailable."),
    `${name} lacks an honest invalid-location result`,
  );
}
const hereEVResultDecoder = hereEV.slice(
  hereEV.indexOf("private struct BackendRow"),
);
const hereParkingResultDecoder = hereParking.slice(
  hereParking.indexOf("private struct BackendRow"),
);
assert.ok(hereEVResultDecoder.includes("LatLongParser.validatedCoordinate"));
assert.ok(
  hereParkingResultDecoder.includes("LatLongParser.validatedCoordinate"),
);
assert.ok(hereCameras.includes("compactMap { row in"));
assert.ok(hereAddOns.includes("item.position?.coordinate"));
assert.ok(
  hereAddOns.includes("let coordinate = LatLongParser.validatedCoordinate"),
);

assert.ok(
  railYardOperations.includes("var coordinate: CLLocationCoordinate2D?"),
);
assert.ok(
  railYardOperations.includes(
    "yards.filter { $0.coordinates?.coordinate != nil }",
  ),
);
assert.ok(!railYardOperations.includes("HereLatLng(39.0, -98.0)"));
assert.ok(
  dispatchTrio.includes(
    "let pts: [HereLatLng] = (link.points ?? []).compactMap",
  ),
);
assert.ok(
  activeEnroute.includes(
    "let coordinates: [HereLatLng] = rawPolygon.compactMap",
  ),
);
assert.ok(vesselLive.includes("private var livePositionCoord: HereLatLng?"));
assert.ok(vesselLive.includes("latitude: p.lat"));
assert.ok(vesselOceanTrack.includes("LatLongParser.displayString(coordinate)"));
assert.ok(!vesselOceanTrack.includes("Self.formatLat"));
assert.ok(multimodalCore.includes("guard LatLongParser.isValid(coord)"));
assert.ok(multimodalCore.includes("truck uses HERE Routing v8"));
assert.ok(multimodalCore.includes("vessel uses the"));
assert.ok(multimodalCore.includes("rail uses the AAR transit-time table"));
assert.ok(vesselOceanTrack.includes("canonicalRoute?.rendererPayload"));
assert.ok(vesselOceanTrack.includes(".eusoRoute("));
assert.ok(
  !vesselOceanTrack.includes(
    "ordered historical AIS positions as the only route geometry",
  ),
);
assert.ok(mapProjection.includes("public init?("));
assert.ok(
  mapProjection.includes("guard !validCoords.isEmpty else { return nil }"),
);
assert.ok(!mapProjection.includes("HereLatLng(0, 0)"));
assert.ok(bespokeMap.includes("if let fitted = BespokeMapViewport("));
assert.ok(occurrences(mapGeography, "LatLongParser.validatedCoordinate") === 2);

for (const [name, source] of [
  ["pickup board", pickupBoard],
  ["in-transit card", transitCard],
]) {
  assert.ok(
    source.includes("LatLongParser.validatedCoordinate"),
    `${name} lacks canonical validation`,
  );
  assert.ok(
    source.includes('row("GPS", "Not recorded")'),
    `${name} lacks an honest missing-GPS state`,
  );
  assert.ok(
    !source.includes("p.lat ?? 0"),
    `${name} fabricates a missing latitude`,
  );
  assert.ok(
    !source.includes("p.lng ?? 0"),
    `${name} fabricates a missing longitude`,
  );
}

console.log(
  `iOS coordinate integration verified across ${swiftFiles.length} Swift files: one parser, exact input retention, canonical HERE provenance, full zero-coordinate support, and mode-honest provider geometry.`,
);
