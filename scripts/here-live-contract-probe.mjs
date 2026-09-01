#!/usr/bin/env node

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const config = readFileSync(resolve(root, "EusoTrip.xcconfig"), "utf8");
const apiKey = config.match(/^\s*HERE_JS_API_KEY\s*=\s*(\S+)\s*$/m)?.[1];
assert.ok(apiKey, "HERE live probe skipped: HERE_JS_API_KEY is not configured");

const passed = [];

async function request(
  name,
  input,
  {
    status = 200,
    json = true,
    withKey = true,
    method = "GET",
    body,
    headers,
  } = {},
) {
  const url = new URL(input);
  if (withKey) url.searchParams.set("apikey", apiKey);
  let response;
  try {
    response = await fetch(url, {
      method,
      body,
      headers,
      signal: AbortSignal.timeout(20_000),
    });
  } catch {
    throw new Error(`${name}: request failed`);
  }
  assert.equal(response.status, status, `${name}: expected HTTP ${status}, got ${response.status}`);
  passed.push(name);
  return json ? response.json() : response.arrayBuffer();
}

for (const asset of [
  "mapsjs-core.js",
  "mapsjs-service.js",
  "mapsjs-ui.js",
  "mapsjs-data.js",
  "mapsjs-mapevents.js",
]) {
  await request(
    `Maps JS 3.2.8.0 ${asset}`,
    `https://js.api.here.com/v3/3.2.8.0/${asset}`,
    { json: false, withKey: false },
  );
}

const dayTile = await request(
  "supported stock fallback day raster ppi=200",
  "https://maps.hereapi.com/v3/base/mc/12/1204/1540/png?style=explore.day&size=512&ppi=200&lang=en",
  { json: false },
);
assert.ok(dayTile.byteLength > 10_000, "Day raster tile is unexpectedly empty");
const nightTile = await request(
  "supported stock fallback night raster ppi=200",
  "https://maps.hereapi.com/v3/base/mc/12/1204/1540/png?style=explore.night&size=512&ppi=200&lang=en",
  { json: false },
);
assert.ok(nightTile.byteLength > 10_000, "Night raster tile is unexpectedly empty");
await request(
  "raster rejects ppi=250",
  "https://maps.hereapi.com/v3/base/mc/12/1204/1540/png?style=explore.day&size=512&ppi=250&lang=en",
  { status: 400 },
);

const geocode = await request(
  "forward geocode",
  "https://geocode.search.hereapi.com/v1/geocode?q=1600%20Pennsylvania%20Avenue%20NW%2C%20Washington%2C%20DC&limit=1",
);
assert.ok(geocode.items?.[0]?.position, "Forward geocode returned no coordinate");
assert.ok(geocode.items?.[0]?.address?.city, "Forward geocode returned no city");
assert.ok(geocode.items?.[0]?.address?.stateCode, "Forward geocode returned no state");
assert.ok(geocode.items?.[0]?.address?.countryName, "Forward geocode returned no country");

const reverse = await request(
  "reverse geocode",
  "https://revgeocode.search.hereapi.com/v1/revgeocode?at=38.8977%2C-77.0365&limit=1",
);
assert.ok(reverse.items?.[0]?.address?.street, "Reverse geocode returned no street");
const reverseZero = await request(
  "provider envelope at null island",
  "https://revgeocode.search.hereapi.com/v1/revgeocode?at=0%2C0&limit=1",
);
assert.ok(Array.isArray(reverseZero.items), "Null-island reverse geocode returned an invalid envelope");

const truckRoute = await request(
  "truck route polyline spans tolls",
  "https://router.hereapi.com/v8/routes?transportMode=truck&origin=32.7767%2C-96.7970&destination=33.7490%2C-84.3880&return=polyline%2Csummary%2Cactions%2Ctolls&spans=maxSpeed%2CfunctionalClass%2CtruckAttributes&vehicle%5BgrossWeight%5D=36287",
);
const truckSection = truckRoute.routes?.[0]?.sections?.[0];
assert.equal(typeof truckSection?.polyline, "string", "Truck route returned no polyline");
assert.ok(truckSection?.spans?.length, "Truck route returned no spans");
assert.ok("maxSpeed" in truckSection.spans[0], "Truck spans omitted maxSpeed");
assert.ok("functionalClass" in truckSection.spans[0], "Truck spans omitted functionalClass");
assert.ok("truckAttributes" in truckSection.spans[0], "Truck spans omitted truckAttributes");

const heavyHazmatRoute = await request(
  "heavy hazmat truck dimensions and axle contract",
  "https://router.hereapi.com/v8/routes?transportMode=truck&origin=32.7767%2C-96.7970&destination=32.7555%2C-97.3308&return=polyline%2Csummary%2Cactions%2Ctolls&spans=maxSpeed%2CfunctionalClass%2CtruckAttributes&vehicle%5Btype%5D=Tractor&vehicle%5BgrossWeight%5D=36287&vehicle%5BcurrentWeight%5D=34000&vehicle%5BweightPerAxle%5D=7250&vehicle%5Bheight%5D=411&vehicle%5Bwidth%5D=259&vehicle%5Blength%5D=2200&vehicle%5BaxleCount%5D=5&vehicle%5BtrailerCount%5D=1&vehicle%5BtrailerAxleCount%5D=2&vehicle%5BtrailerLength%5D=1600&vehicle%5BshippedHazardousGoods%5D=flammable%2Cgas&vehicle%5BtunnelCategory%5D=D",
);
const heavyHazmatSection = heavyHazmatRoute.routes?.[0]?.sections?.[0];
assert.equal(
  typeof heavyHazmatSection?.polyline,
  "string",
  "Heavy hazmat route returned no flexible polyline",
);
assert.ok(heavyHazmatSection?.spans?.length, "Heavy hazmat route returned no spans");

const mapAttributePathQuery = new URLSearchParams({
  attributes: "APPLICABLE_SPEED_LIMIT(*),ROAD_GEOM_FCn(LAT,LON)",
  transportMode: "truck",
  commercial: "1",
  vehicleWeightClass: "36287kg",
  vehicleNumberAxles: "5",
  trailersCount: "1",
  length: "2200cm",
  width: "259cm",
  height: "411cm",
  shippedHazardousGoods: "flammable,gas",
});
const pathAttributes = await request(
  "vehicle-aware Map Attributes path",
  `https://smap.hereapi.com/v8/maps/attributes/path?${mapAttributePathQuery.toString()}`,
  {
    method: "POST",
    body: new URLSearchParams({ flexiblePolyline: heavyHazmatSection.polyline }).toString(),
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
  },
);
assert.ok(Array.isArray(pathAttributes.segments), "Map Attributes path returned an invalid envelope");
assert.ok(pathAttributes.segments.length, "Map Attributes path returned no road segments");

await request(
  "routing rejects spans inside return",
  "https://router.hereapi.com/v8/routes?transportMode=truck&origin=32.7767%2C-96.7970&destination=33.7490%2C-84.3880&return=polyline%2Csummary%2Cspans%3DmaxSpeed",
  { status: 400 },
);

const tollRoute = await request(
  "truck toll fares",
  "https://router.hereapi.com/v8/routes?transportMode=truck&origin=40.7128%2C-74.0060&destination=40.7357%2C-74.1724&return=polyline%2Csummary%2Ctolls",
);
const fares = tollRoute.routes?.flatMap((route) => route.sections ?? [])
  .flatMap((section) => section.tolls ?? [])
  .flatMap((toll) => toll.fares ?? []);
assert.ok(fares?.some((fare) => Number.isFinite(fare.price?.value) && fare.price?.currency), "Tolls returned no priced fare");

const isoline = await request(
  "truck isoline",
  "https://isoline.router.hereapi.com/v8/isolines?transportMode=truck&origin=32.7767%2C-96.7970&range%5Btype%5D=time&range%5Bvalues%5D=1800",
);
assert.equal(typeof isoline.isolines?.[0]?.polygons?.[0]?.outer, "string", "Isoline returned no outer polyline");

const evRoute = await request(
  "EV route consumption contract",
  "https://router.hereapi.com/v8/routes?transportMode=car&origin=32.7767%2C-96.7970&destination=32.9500%2C-96.8300&return=polyline%2Csummary%2Cactions%2Cinstructions%2Ctolls&ev%5BfreeFlowSpeedTable%5D=0%2C0.2%2C50%2C0.2%2C100%2C0.25&ev%5Bascent%5D=0.1&ev%5Bdescent%5D=0.1&ev%5BauxiliaryConsumption%5D=1.0&ev%5BinitialCharge%5D=50&ev%5BmaxCharge%5D=80&ev%5BminChargeAtDestination%5D=5&ev%5BchargingCurve%5D=0%2C100%2C80%2C20&ev%5BconnectorTypes%5D=iec62196Type2Combo",
);
assert.equal(typeof evRoute.routes?.[0]?.sections?.[0]?.polyline, "string", "EV route returned no polyline");

const flow = await request(
  "traffic flow shape",
  "https://data.traffic.hereapi.com/v7/flow?in=bbox%3A-97.1%2C32.6%2C-96.5%2C33.0&locationReferencing=shape&functionalClasses=1%2C2%2C3",
);
assert.ok(flow.results?.some((row) => row.location?.shape?.links?.[0]?.points?.length), "Traffic flow returned no shape");
assert.ok(flow.results?.some((row) => Number.isFinite(row.currentFlow?.jamFactor)), "Traffic flow returned no jam factor");

const incidents = await request(
  "traffic incidents live envelope",
  "https://data.traffic.hereapi.com/v7/incidents?in=bbox%3A-97.1%2C32.6%2C-96.5%2C33.0&locationReferencing=shape",
);
assert.ok(Array.isArray(incidents.results), "Traffic incidents returned an invalid envelope");
if (incidents.results.length) {
  assert.equal(typeof incidents.results[0].incidentDetails?.criticality, "string");
}

const destinationWeather = await request(
  "Destination Weather observation forecast and alerts",
  "https://weather.hereapi.com/v3/report?products=observation%2CforecastHourly%2Cforecast7days%2CforecastAstronomy%2CnwsAlerts&location=32.7767%2C-96.7970&units=imperial",
);
assert.ok(Array.isArray(destinationWeather.places), "Destination Weather returned an invalid envelope");
assert.ok(destinationWeather.places.length, "Destination Weather returned no place products");
assert.ok(
  destinationWeather.places.some((place) =>
    place?.observations?.length
    || place?.hourlyForecasts?.length
    || place?.dailyForecasts?.length
    || place?.extendedDailyForecasts?.length
    || place?.astronomyForecasts?.length
    || place?.nwsAlerts?.length),
  "Destination Weather returned no observation, forecast, astronomy, or alert product",
);

const safetyAlerts = await request(
  "Map Attributes safety-alert coverage envelope",
  "https://smap.hereapi.com/v8/maps/attributes?layers=SAFETY_ALERTS&in=proximity%3A32.7767%2C-96.7970%3Br%3D9000",
);
assert.ok(Array.isArray(safetyAlerts.geometries), "Safety Alerts returned an invalid envelope");

const adasAttributes = await request(
  "Map Attributes ADAS lane sign and roughness coverage",
  "https://smap.hereapi.com/v8/maps/attributes?layers=ADAS_ATTRIB_FCN%2CLINK_ATTRIBUTE_FCN%2CTRAFFIC_SIGN_FCN%2CROAD_ROUGHNESS_FCN%2CLANE_FCN&in=proximity%3A32.7767%2C-96.7970%3Br%3D9000",
);
assert.ok(Array.isArray(adasAttributes.geometries), "ADAS Map Attributes returned an invalid envelope");
assert.ok(adasAttributes.geometries.length, "ADAS Map Attributes returned no road coverage");

const chargers = await request(
  "EV Browse connectors",
  "https://browse.search.hereapi.com/v1/browse?at=32.7767%2C-96.7970&in=circle%3A32.7767%2C-96.7970%3Br%3D25000&categories=700-7600-0322&show=ev&limit=10",
);
assert.ok(chargers.items?.some((item) => item.position && item.extended?.evStation), "EV Browse returned no station metadata");

const parking = await request(
  "truck parking Browse",
  "https://browse.search.hereapi.com/v1/browse?at=32.7767%2C-96.7970&in=circle%3A32.7767%2C-96.7970%3Br%3D40000&categories=700-7900-0131%2C700-7900-0132&limit=30",
);
assert.ok(parking.items?.some((item) => item.position), "Truck parking returned no positioned POI");

const fuel = await request(
  "Fuel Prices v3 circle",
  "https://fuel.hereapi.com/v3/stations?in=circle%3A32.7767%2C-96.7970%3Br%3D40000&fuelType=1%2C11&limit=20",
);
assert.ok(fuel.stations?.some((station) => station.position), "Fuel Prices returned no positioned station");

console.log(`HERE live contracts passed (${passed.length} secret-safe probes).`);
