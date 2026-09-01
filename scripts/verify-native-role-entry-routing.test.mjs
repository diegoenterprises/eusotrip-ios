import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = (relativePath) =>
  fs.readFileSync(path.join(root, relativePath), "utf8");

const auth = read("EusoTrip/Models/AuthModels.swift");
const contentView = read("EusoTrip/ContentView.swift");
const router = read("EusoTrip/Views/RoleSurfaceRouter.swift");
const railShipperHome = read("EusoTrip/Views/Rail/001_RailShipperHome.swift");
const railCarrierHome = read(
  "EusoTrip/Views/Rail/559_RailYardOperations.swift",
);

const expectedAssignments = [
  ["driver", "ContentView.driverSurface", "driverContent()"],
  ["shipper", "ShipperSurface", "ShipperSurface(palette: palette)"],
  ["catalyst", "CarrierSurface", "CarrierSurface(palette: palette)"],
  ["broker", "BrokerSurface", "BrokerSurface(palette: palette)"],
  ["dispatch", "DispatchSurface", "DispatchSurface(palette: palette)"],
  ["escort", "EscortSurface", "EscortSurface(palette: palette)"],
  ["terminal", "TerminalSurface", "TerminalSurface(palette: palette)"],
  ["compliance", "ComplianceSurface", "ComplianceSurface(palette: palette)"],
  [
    "safety",
    "NativeSpecialistRoleSurface.SAFETY_MANAGER",
    "NativeSpecialistRoleSurface(definition: .safety",
  ],
  ["admin", "AdminSurface.ADMIN", "AdminSurface(role: role"],
  ["superAdmin", "AdminSurface.SUPER_ADMIN", "AdminSurface(role: role"],
  [
    "factoring",
    "NativeSpecialistRoleSurface.FACTORING",
    "NativeSpecialistRoleSurface(definition: .factoring",
  ],
  [
    "railShipper",
    "NativeModeRoleSurface.RAIL_SHIPPER",
    "NativeModeRoleSurface(definition: .railShipper",
  ],
  [
    "railCatalyst",
    "NativeModeRoleSurface.RAIL_CATALYST",
    "NativeModeRoleSurface(definition: .railCatalyst",
  ],
  [
    "railDispatch",
    "NativeModeRoleSurface.RAIL_DISPATCHER",
    "NativeModeRoleSurface(definition: .railDispatch",
  ],
  [
    "railEngineer",
    "RailEngineerSurface",
    "RailEngineerSurface(palette: palette)",
  ],
  [
    "railConductor",
    "NativeModeRoleSurface.RAIL_CONDUCTOR",
    "NativeModeRoleSurface(definition: .railConductor",
  ],
  [
    "railBroker",
    "NativeModeRoleSurface.RAIL_BROKER",
    "NativeModeRoleSurface(definition: .railBroker",
  ],
  [
    "vesselShipper",
    "VesselShipperSurface",
    "VesselShipperSurface(palette: palette)",
  ],
  [
    "vesselOperator",
    "VesselOperatorSurface",
    "VesselOperatorSurface(palette: palette)",
  ],
  [
    "portMaster",
    "NativeModeRoleSurface.PORT_MASTER",
    "NativeModeRoleSurface(definition: .portMaster",
  ],
  [
    "shipCaptain",
    "NativeModeRoleSurface.SHIP_CAPTAIN",
    "NativeModeRoleSurface(definition: .shipCaptain",
  ],
  [
    "vesselBroker",
    "NativeModeRoleSurface.VESSEL_BROKER",
    "NativeModeRoleSurface(definition: .vesselBroker",
  ],
  [
    "customsBroker",
    "NativeModeRoleSurface.CUSTOMS_BROKER",
    "NativeModeRoleSurface(definition: .customsBroker",
  ],
  [
    "serviceProvider",
    "NativeSpecialistRoleSurface.SERVICE_PROVIDER",
    "NativeSpecialistRoleSurface(definition: .serviceProvider",
  ],
];

function balancedBlock(source, marker) {
  const markerIndex = source.indexOf(marker);
  assert.notEqual(markerIndex, -1, `missing ${marker}`);
  const openIndex = source.indexOf("{", markerIndex + marker.length);
  assert.notEqual(openIndex, -1, `missing body for ${marker}`);

  let depth = 0;
  let inString = false;
  let escaped = false;
  let lineComment = false;
  for (let index = openIndex; index < source.length; index += 1) {
    const char = source[index];
    const next = source[index + 1];
    if (lineComment) {
      if (char === "\n") lineComment = false;
      continue;
    }
    if (inString) {
      if (escaped) escaped = false;
      else if (char === "\\") escaped = true;
      else if (char === '"') inString = false;
      continue;
    }
    if (char === "/" && next === "/") {
      lineComment = true;
      index += 1;
      continue;
    }
    if (char === '"') {
      inString = true;
      continue;
    }
    if (char === "{") depth += 1;
    if (char === "}") {
      depth -= 1;
      if (depth === 0) return source.slice(openIndex + 1, index);
    }
  }
  assert.fail(`unterminated ${marker}`);
}

function switchCaseBody(block, role) {
  const expression = new RegExp(
    `(?:^|\\n)\\s*case \\.${role}:([\\s\\S]*?)(?=\\n\\s*case \\.|$)`,
  );
  const match = block.match(expression);
  assert.ok(match, `missing router case for ${role}`);
  return match[1];
}

function swiftFiles(directory) {
  const files = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...swiftFiles(absolute));
    else if (entry.isFile() && entry.name.endsWith(".swift"))
      files.push(absolute);
  }
  return files;
}

test("all 25 canonical roles resolve through one explicit native assignment", () => {
  const roleEnum = balancedBlock(auth, "enum EusoRole:");
  const roles = [...roleEnum.matchAll(/^\s*case\s+(\w+)\s*=/gm)].map(
    (match) => match[1],
  );
  assert.deepEqual(
    roles,
    expectedAssignments.map(([role]) => role),
  );

  const assignment = balancedBlock(router, "enum RoleSurfaceAssignment:");
  const rawValues = Object.fromEntries(
    [...assignment.matchAll(/^\s*case\s+(\w+)\s*=\s*"([^"]+)"/gm)].map(
      (match) => [match[1], match[2]],
    ),
  );
  assert.deepEqual(
    rawValues,
    Object.fromEntries(
      expectedAssignments.map(([role, rawValue]) => [role, rawValue]),
    ),
  );
  assert.equal(new Set(Object.values(rawValues)).size, 25);
  for (const rawValue of Object.values(rawValues)) {
    assert.doesNotMatch(rawValue, /https?:|safari|webcontinuation/i);
  }

  const mapping = balancedBlock(
    router,
    "static func forRole(_ role: EusoRole) -> RoleSurfaceAssignment",
  );
  for (const [role] of expectedAssignments) {
    assert.match(mapping, new RegExp(`case \\.${role}: return \\.${role}\\b`));
  }
  assert.doesNotMatch(mapping, /^\s*default\s*:/m);
});

test("the signed-in entry switch renders every assignment without a family fallback", () => {
  const roleSurface = balancedBlock(
    router,
    "private func roleSurface(for role: EusoRole) -> some View",
  );
  for (const [role, , constructor] of expectedAssignments) {
    assert.ok(
      switchCaseBody(roleSurface, role).includes(constructor),
      `${role} does not render ${constructor}`,
    );
  }
  assert.doesNotMatch(roleSurface, /^\s*default\s*:/m);
  assert.doesNotMatch(
    roleSurface,
    /URL\s*\(|Safari|WebContinuationSurface\s*\(/i,
  );

  const content = balancedBlock(contentView, "struct ContentView: View");
  assert.match(content, /if let role = session\.user\?\.roleEnum/);
  assert.match(
    content,
    /RoleSurfaceRouter\(role:\s*role,\s*palette:\s*register\.palette\)/,
  );
  assert.doesNotMatch(content, /roleEnum\s*\?\?\s*\./);
});

test("Rail Shipper and Rail Carrier enter their purpose-built native workspaces", () => {
  const dedicated = balancedBlock(
    router,
    "private var dedicatedHomeView: AnyView?",
  );
  assert.match(
    dedicated,
    /case \.railShipper:[\s\S]*RailShipperHomeScreen\(theme:\s*palette\)/,
  );
  assert.doesNotMatch(dedicated, /case \.railCatalyst:/);

  const currentView = balancedBlock(router, "private var currentView: AnyView");
  const dedicatedIndex = currentView.indexOf("if let dedicatedHomeView");
  const registryIndex = currentView.indexOf(
    "registeredScreen(definition.nativeHomeScreenId)",
  );
  assert.ok(dedicatedIndex >= 0 && registryIndex > dedicatedIndex);

  const carrierStart = router.indexOf("static let railCatalyst = Self(");
  const carrierEnd = router.indexOf(
    "static let railDispatch = Self(",
    carrierStart,
  );
  assert.ok(carrierStart >= 0 && carrierEnd > carrierStart);
  const carrierDefinition = router.slice(carrierStart, carrierEnd);
  assert.match(carrierDefinition, /nativeHomeScreenId:\s*"Rail559"/);
  assert.match(
    carrierDefinition,
    /workOne:\s*\.init\(destinationId:\s*"Rail559",\s*label:\s*"Yards"/,
  );
  assert.match(
    contentView,
    /id:\s*"Rail559"[\s\S]*RailYardOperationsScreen\(theme:\s*p\)/,
  );
  assert.match(railCarrierHome, /struct RailYardOperationsScreen:\s*View/);
  assert.match(railCarrierHome, /railShipments\.getRailYards/);
});

test("the Rail Shipper entry preserves unknown values instead of design-time examples", () => {
  assert.match(
    railShipperHome,
    /@EnvironmentObject private var session:\s*EusoTripSession/,
  );
  assert.match(railShipperHome, /statsError != nil/);
  assert.match(
    railShipperHome,
    /return facts\.isEmpty \? "RAIL FLEET · NOT REPORTED"/,
  );
  assert.match(railShipperHome, /Text\(shipmentsLoading \? "Updating"/);
  assert.match(railShipperHome, /if let progress = s\.progress/);

  for (const forbidden of [
    "STUB",
    "Hey, Diego",
    "Eusorone Technologies · 8 rail shipments",
    "RAIL-260519 dwell trips demurrage in 4h",
    "Request early release at BNSF interchange",
    "stats?.activeShipments ?? 8",
    "stats?.carsRolling ?? 23",
    "stats?.avgTransitDays ?? 4.2",
    "stats?.monthlySpend ?? 214_000",
    "s.progress ?? 0.5",
  ]) {
    assert.ok(
      !railShipperHome.includes(forbidden),
      `synthetic Rail Shipper value returned: ${forbidden}`,
    );
  }
});

test("the removed web-login continuation cannot reappear in any Swift surface", () => {
  const forbidden = [
    "Open the full role workspace on app.eusotrip.com",
    "Continue on app.eusotrip.com",
    "Web sign-in may be required",
    "struct WebContinuationSurface",
  ];
  for (const file of swiftFiles(path.join(root, "EusoTrip"))) {
    const source = fs.readFileSync(file, "utf8");
    for (const copy of forbidden) {
      assert.ok(
        !source.includes(copy),
        `${path.relative(root, file)} restored forbidden copy: ${copy}`,
      );
    }
  }
});
