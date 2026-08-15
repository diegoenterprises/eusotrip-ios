import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

const root = process.cwd();
const read = relative => fs.readFileSync(path.join(root, relative), "utf8");

const api = read("EusoTrip/Services/EusoTripAPI+VesselWrites.swift");
const view = read("EusoTrip/Views/Vessel/822_VesselWriteCenter.swift");
const registry = read("EusoTrip/ContentView.swift");
const router = read("EusoTrip/Views/RoleSurfaceRouter.swift");
const operatorMe = read("EusoTrip/Views/Vessel/656_VesselOperatorAccount.swift");
const terminalMe = read("EusoTrip/Views/Terminal/703_TerminalMe.swift");
const adminMe = read("EusoTrip/Views/Admin/804_AdminMe.swift");
const project = read("EusoTrip.xcodeproj/project.pbxproj");

const procedures = {
  publishFreightRate: {
    swiftMethod: "publishVesselFreightRate",
    input: "PublishVesselFreightRateInput",
    fields: [
      "requestKey", "originPortId", "destinationPortId", "containerSize",
      "ratePerUnit", "currency", "bafSurcharge", "thcOrigin",
      "thcDestination", "peakSeasonSurcharge", "effectiveDate",
      "expirationDate", "transitDays", "serviceRoute",
    ],
  },
  createVoyage: {
    swiftMethod: "createVesselVoyage",
    input: "CreateVesselVoyageInput",
    fields: [
      "requestKey", "vesselId", "voyageNumber", "serviceRoute",
      "departurePortId", "arrivalPortId", "scheduledDeparture",
      "scheduledArrival", "captainId",
    ],
  },
  createCargoManifest: {
    swiftMethod: "createVesselCargoManifest",
    input: "CreateVesselCargoManifestInput",
    fields: [
      "requestKey", "voyageId", "shipmentId", "containerNumber",
      "sealNumber", "cargoDescription", "packageCount", "grossWeightKg",
      "volumeCBM", "loadPortId", "dischargePortId", "hazmatClass",
      "temperatureRequired", "stowagePosition",
    ],
  },
  recordBunkerDelivery: {
    swiftMethod: "recordVesselBunkerDelivery",
    input: "RecordVesselBunkerDeliveryInput",
    fields: [
      "requestKey", "vesselId", "voyageId", "portId", "fuelType",
      "quantityMT", "pricePerMT", "currency", "supplier", "deliveryDate",
      "bunkerDeliveryNote", "sulphurContent",
    ],
  },
  registerContainer: {
    swiftMethod: "registerIntermodalContainer",
    input: "RegisterIntermodalContainerInput",
    fields: [
      "requestKey", "containerNumber", "size", "type", "status",
      "chassisId", "locationId", "spotId", "steamshipLine",
      "bookingNumber", "sealNumber", "weight", "lastFreeDay",
      "demurrageRate", "arrivalTime", "departureTime", "notes",
    ],
  },
};

function balancedBlock(source, marker, opening = "{", closing = "}") {
  const markerIndex = source.indexOf(marker);
  assert.notEqual(markerIndex, -1, `missing ${marker}`);
  const openingIndex = source.indexOf(opening, markerIndex + marker.length);
  assert.notEqual(openingIndex, -1, `missing ${opening} after ${marker}`);
  let depth = 0;
  let string = false;
  let escaped = false;
  for (let index = openingIndex; index < source.length; index += 1) {
    const character = source[index];
    if (string) {
      if (escaped) escaped = false;
      else if (character === "\\") escaped = true;
      else if (character === '"') string = false;
      continue;
    }
    if (character === '"') {
      string = true;
      continue;
    }
    if (character === opening) depth += 1;
    if (character === closing) {
      depth -= 1;
      if (depth === 0) return source.slice(openingIndex + 1, index);
    }
  }
  assert.fail(`unterminated ${marker}`);
}

function swiftStoredProperties(typeName) {
  const block = balancedBlock(api, `struct ${typeName}: Encodable`);
  return [...block.matchAll(/^\s*(?:let|var)\s+([A-Za-z][A-Za-z0-9]*):/gm)]
    .map(match => match[1]);
}

test("all five native mutation bindings use the exact tRPC procedure and a verified persisted ID", () => {
  for (const [procedure, contract] of Object.entries(procedures)) {
    assert.match(api, new RegExp(`func ${contract.swiftMethod}\\(`));
    assert.match(api, new RegExp(`"vesselShipments\\.${procedure}"`));
    const method = balancedBlock(api, `func ${contract.swiftMethod}(`);
    assert.match(method, /try await mutation\(/);
    assert.match(method, /acknowledgement\.id > 0|verifiedVesselWriteAcknowledgement/);
  }
  assert.doesNotMatch(api, /try\?/);
  assert.doesNotMatch(api, /success\s*:\s*false/);
});

test("Swift Encodable payloads preserve every server field name exactly", () => {
  for (const contract of Object.values(procedures)) {
    assert.deepEqual(swiftStoredProperties(contract.input), contract.fields, contract.input);
  }
});

test("server enum literals are mirrored without aliases or display substitutions", () => {
  for (const value of [
    "20ft", "40ft", "40ft_hc", "45ft", "20ft_reefer", "40ft_reefer",
    "53ft", "standard", "high_cube", "reefer", "open_top", "flat_rack",
    "tank", "on_chassis", "grounded", "loaded", "empty", "in_transit",
    "at_port", "hfo", "vlsfo", "mgo", "lng",
  ]) {
    assert.ok(api.includes(`"${value}"`) || api.includes(`case ${value}`), `missing enum literal ${value}`);
  }
});

test("client role policy is exact and excludes adjacent maritime roles", () => {
  const policy = balancedBlock(view, "static func allowedActions(for role: EusoRole)");
  assert.match(policy, /case \.vesselOperator, \.admin, \.superAdmin:[\s\S]*return VesselWriteAction\.allCases/);
  assert.match(policy, /case \.shipCaptain:[\s\S]*return \[\.recordBunkerDelivery\]/);
  assert.match(policy, /case \.portMaster, \.terminal:[\s\S]*return \[\.registerContainer\]/);
  assert.doesNotMatch(policy, /\.vesselBroker|\.customsBroker|\.vesselShipper/);
  assert.match(policy, /default:[\s\S]*return \[\]/);
});

test("every eligible role has a reachable registered screen without widening shared role access", () => {
  assert.match(registry, /id: "Vesl822"[\s\S]{0,140}role: \.vesselOperator[\s\S]{0,140}VesselWriteCenterScreen/);
  assert.match(registry, /id: "TerminalVesselWrites"[\s\S]{0,160}role: \.terminal[\s\S]{0,140}VesselWriteCenterScreen/);
  assert.match(registry, /id: "AdminVesselWrites"[\s\S]{0,160}role: \.admin[\s\S]{0,140}VesselWriteCenterScreen/);
  assert.match(operatorMe, /"Vesl822"[\s\S]{0,160}"Operations ledger"/);
  assert.match(terminalMe, /to: "TerminalVesselWrites"/);
  assert.match(adminMe, /to: "AdminVesselWrites"/);
  assert.match(router, /static let portMaster = Self\([\s\S]*detailRoutes: \["Vesl661", "Vesl822"\]/);
  assert.match(router, /static let shipCaptain = Self\([\s\S]*detailRoutes: \["Vesl654", "Vesl822"\]/);
  assert.doesNotMatch(registry, /id: "Vesl822"[\s\S]{0,140}role: \.(?:shipper|carrier|broker|dispatch)/);
});

test("both new Swift files belong to the explicit EusoTrip app target", () => {
  const services = balancedBlock(project, "A1000000000000000000AAD3 /* Services */ =");
  const vesselViews = balancedBlock(project, "FD97CEC32FC1D4AC0016DF5F /* Vessel */ =");
  const appSources = balancedBlock(project, "A1000000000000000000AAAF /* Sources */ =");

  assert.match(services, /VWRIT202608140000000002 \/\* EusoTripAPI\+VesselWrites\.swift \*\//);
  assert.match(vesselViews, /VWRIT202608140000000004 \/\* 822_VesselWriteCenter\.swift \*\//);
  assert.match(appSources, /VWRIT202608140000000001 \/\* EusoTripAPI\+VesselWrites\.swift in Sources \*\//);
  assert.match(appSources, /VWRIT202608140000000003 \/\* 822_VesselWriteCenter\.swift in Sources \*\//);
});

test("forms source selectors from scoped live readers and keep a request key stable across retry", () => {
  for (const reader of [
    "vesselShipments.getPorts",
    "vesselShipments.getVesselFleet",
    "vesselShipments.getVesselSchedules",
    "vesselShipments.getVesselShipments",
    "vesselShipments.getContainerInventory",
  ]) assert.ok(api.includes(`"${reader}"`), `missing reader ${reader}`);

  const attempt = balancedBlock(view, "private struct VesselWriteAttempt");
  assert.match(attempt, /private var requestKey = Self\.makeRequestKey\(\)/);
  assert.match(attempt, /if let fingerprint, fingerprint != nextFingerprint[\s\S]*requestKey = Self\.makeRequestKey\(\)/);
  assert.match(attempt, /mutating func completed\(\)/);
  assert.match(view, /input\.requestKey = try attempt\.key\(for: input\)/);
  assert.equal((view.match(/input\.requestKey = try attempt\.key\(for: input\)/g) ?? []).length, 5);
  assert.equal((view.match(/attempt\.completed\(\)/g) ?? []).length, 5);
  assert.doesNotMatch(view, /try\?/);
});

test("the current lane did not bump build 850", () => {
  const versions = [...project.matchAll(/CURRENT_PROJECT_VERSION = (\d+);/g)].map(match => Number(match[1]));
  assert.ok(versions.length > 0, "no CURRENT_PROJECT_VERSION values found");
  assert.deepEqual([...new Set(versions)], [850]);
});

const backendRoot = process.env.EUSOTRIP_BACKEND_ROOT;
test("live backend source exposes the same fields and exact writer role gates", { skip: !backendRoot }, () => {
  const backend = fs.readFileSync(path.join(backendRoot, "server/routers/vesselWrites.ts"), "utf8");
  const roleNeedles = {
    publishFreightRate: '["VESSEL_OPERATOR"]',
    createVoyage: '["VESSEL_OPERATOR"]',
    createCargoManifest: '["VESSEL_OPERATOR"]',
    recordBunkerDelivery: '["VESSEL_OPERATOR", "SHIP_CAPTAIN"]',
    registerContainer: '["VESSEL_OPERATOR", "PORT_MASTER", "TERMINAL_MANAGER"]',
  };

  const entries = Object.entries(procedures);
  for (const [index, [procedure, contract]] of entries.entries()) {
    const start = backend.indexOf(`${procedure}: isolatedApprovedVesselProcedure`);
    assert.notEqual(start, -1, `backend missing ${procedure}`);
    const nextProcedure = entries[index + 1]?.[0];
    const end = nextProcedure
      ? backend.indexOf(`${nextProcedure}: isolatedApprovedVesselProcedure`, start + 1)
      : backend.indexOf("\n};", start + 1);
    const section = backend.slice(start, end === -1 ? backend.length : end);
    for (const field of contract.fields) {
      assert.match(section, new RegExp(`\\b${field}:`), `${procedure} missing backend field ${field}`);
    }
    assert.ok(section.includes(roleNeedles[procedure]), `${procedure} role gate drifted`);
    assert.match(section, /return outcome;/);
  }
});
