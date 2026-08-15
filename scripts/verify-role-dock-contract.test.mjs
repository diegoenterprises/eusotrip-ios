import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const authModelsPath = new URL("../EusoTrip/Models/AuthModels.swift", import.meta.url);
const routerPath = new URL("../EusoTrip/Views/RoleSurfaceRouter.swift", import.meta.url);
const registryPath = new URL("../EusoTrip/ContentView.swift", import.meta.url);
const designSystemPath = new URL("../EusoTrip/Theme/DesignSystem.swift", import.meta.url);
const detailNavigationPath = new URL(
  "../EusoTrip/Theme/Components/RoleDetailPush.swift",
  import.meta.url,
);

const authModels = fs.readFileSync(authModelsPath, "utf8");
const router = fs.readFileSync(routerPath, "utf8");
const registry = fs.readFileSync(registryPath, "utf8");
const designSystem = fs.readFileSync(designSystemPath, "utf8");
const detailNavigation = fs.readFileSync(detailNavigationPath, "utf8");

const expectedMatrix = {
  driver: "DriverSurfaceHost",
  shipper: "ShipperSurface",
  catalyst: "CarrierSurface",
  broker: "BrokerSurface",
  dispatch: "DispatchSurface",
  escort: "EscortSurface",
  terminal: "TerminalSurface",
  compliance: "ComplianceSurface",
  safety: "WebContinuationSurface.SAFETY_MANAGER",
  admin: "AdminSurface.ADMIN",
  superAdmin: "AdminSurface.SUPER_ADMIN",
  factoring: "WebContinuationSurface.FACTORING",
  railShipper: "NativeModeRoleSurface.RAIL_SHIPPER",
  railCatalyst: "NativeModeRoleSurface.RAIL_CATALYST",
  railDispatch: "NativeModeRoleSurface.RAIL_DISPATCHER",
  railEngineer: "RailEngineerSurface",
  railConductor: "NativeModeRoleSurface.RAIL_CONDUCTOR",
  railBroker: "NativeModeRoleSurface.RAIL_BROKER",
  vesselShipper: "VesselShipperSurface",
  vesselOperator: "VesselOperatorSurface",
  portMaster: "NativeModeRoleSurface.PORT_MASTER",
  shipCaptain: "NativeModeRoleSurface.SHIP_CAPTAIN",
  vesselBroker: "NativeModeRoleSurface.VESSEL_BROKER",
  customsBroker: "NativeModeRoleSurface.CUSTOMS_BROKER",
  serviceProvider: "WebContinuationSurface.SERVICE_PROVIDER",
};

const expectedNativeModeDefinitions = {
  railShipper: {
    role: "railShipper",
    mode: "rail",
    registryRole: "railEngineer",
    dock: [
      ["home", "RoleRailShipperHome", "Home"],
      ["workOne", "Rail551", "Shipments"],
      ["workTwo", "Rail639", "Network"],
      ["me", "RoleRailShipperMe", "Me"],
    ],
    detailRoutes: [],
  },
  railCatalyst: {
    role: "railCatalyst",
    mode: "rail",
    registryRole: "railEngineer",
    dock: [
      ["home", "RoleRailCatalystHome", "Home"],
      ["workOne", "Rail559", "Yards"],
      ["workTwo", "Rail552", "Compliance"],
      ["me", "RoleRailCatalystMe", "Me"],
    ],
    detailRoutes: [],
  },
  railDispatch: {
    role: "railDispatch",
    mode: "rail",
    registryRole: "railEngineer",
    dock: [
      ["home", "RoleRailDispatchHome", "Home"],
      ["workOne", "Rail555", "Consists"],
      ["workTwo", "Rail559", "Yards"],
      ["me", "RoleRailDispatchMe", "Me"],
    ],
    detailRoutes: [],
  },
  railConductor: {
    role: "railConductor",
    mode: "rail",
    registryRole: "railEngineer",
    dock: [
      ["home", "RoleRailConductorHome", "Home"],
      ["workOne", "Rail554", "Duty"],
      ["workTwo", "Rail595", "Credentials"],
      ["me", "RoleRailConductorMe", "Me"],
    ],
    detailRoutes: [],
  },
  railBroker: {
    role: "railBroker",
    mode: "rail",
    registryRole: "railEngineer",
    dock: [
      ["home", "RoleRailBrokerHome", "Home"],
      ["workOne", "Rail551", "Shipments"],
      ["workTwo", "Rail639", "Network"],
      ["me", "RoleRailBrokerMe", "Me"],
    ],
    detailRoutes: [],
  },
  portMaster: {
    role: "portMaster",
    mode: "vessel",
    registryRole: "vesselOperator",
    dock: [
      ["home", "RolePortMasterHome", "Home"],
      ["workOne", "Vesl697", "Port Ops"],
      ["workTwo", "Vesl686", "Directory"],
      ["me", "RolePortMasterMe", "Me"],
    ],
    detailRoutes: ["Vesl661", "Vesl822"],
  },
  shipCaptain: {
    role: "shipCaptain",
    mode: "vessel",
    registryRole: "vesselOperator",
    dock: [
      ["home", "RoleShipCaptainHome", "Home"],
      ["workOne", "Vesl660", "Position"],
      ["workTwo", "Vesl711", "Crew"],
      ["me", "RoleShipCaptainMe", "Me"],
    ],
    detailRoutes: ["Vesl654", "Vesl822"],
  },
  vesselBroker: {
    role: "vesselBroker",
    mode: "vessel",
    registryRole: "vesselOperator",
    dock: [
      ["home", "RoleVesselBrokerHome", "Home"],
      ["workOne", "Vesl651", "Bookings"],
      ["workTwo", "Vesl686", "Ports"],
      ["me", "RoleVesselBrokerMe", "Me"],
    ],
    detailRoutes: [],
  },
  customsBroker: {
    role: "customsBroker",
    mode: "vessel",
    registryRole: "vesselOperator",
    dock: [
      ["home", "RoleCustomsBrokerHome", "Home"],
      ["workOne", "Vesl789", "Entries"],
      ["workTwo", "Vesl814", "Filing"],
      ["me", "RoleCustomsBrokerMe", "Me"],
    ],
    detailRoutes: [],
  },
};

const directNativeSurfaces = [
  ["shipper", "ShipperSurface"],
  ["catalyst", "CarrierSurface"],
  ["broker", "BrokerSurface"],
  ["escort", "EscortSurface"],
  ["terminal", "TerminalSurface"],
  ["admin", "AdminSurface"],
  ["dispatch", "DispatchSurface"],
  ["compliance", "ComplianceSurface"],
  ["railEngineer", "RailEngineerSurface"],
  ["vesselShipper", "VesselShipperSurface"],
  ["vesselOperator", "VesselOperatorSurface"],
];

const directDockByRole = {
  driver: "driver",
  shipper: "shipper",
  catalyst: "catalyst",
  broker: "broker",
  dispatch: "dispatch",
  escort: "escort",
  terminal: "terminal",
  compliance: "compliance",
  admin: "admin",
  superAdmin: "admin",
  railEngineer: "railEngineer",
  vesselShipper: "vesselShipper",
  vesselOperator: "vesselOperator",
};

const queryBackedNativeRoots = {
  Rail551: ["../EusoTrip/Views/Rail/551_RailShipments.swift", "railShipments.getRailShipments"],
  Rail552: ["../EusoTrip/Views/Rail/552_RailCompliance.swift", "railShipments.getRailInspections"],
  Rail554: ["../EusoTrip/Views/Rail/554_RailCrewHOSRoster.swift", "railShipments.getRailCrewHOS"],
  Rail555: ["../EusoTrip/Views/Rail/555_RailConsistBoard.swift", "railShipments.getTrainConsists"],
  Rail559: ["../EusoTrip/Views/Rail/559_RailYardOperations.swift", "railShipments.getRailYards"],
  Rail595: ["../EusoTrip/Views/Rail/595_RailCrewCertifications.swift", "railShipments.getRailCrew"],
  Rail639: ["../EusoTrip/Views/Rail/639_RailYardDirectory.swift", "railShipments.getRailYards"],
  Vesl651: ["../EusoTrip/Views/Vessel/651_VesselShipments.swift", "vesselShipments.getVesselShipments"],
  Vesl654: ["../EusoTrip/Views/Vessel/654_VesselCrewCertifications.swift", "vesselShipments.getVesselCrew"],
  Vesl660: ["../EusoTrip/Views/Vessel/660_VesselLivePosition.swift", "vesselShipments.getVesselTrack"],
  Vesl661: ["../EusoTrip/Views/Vessel/661_VesselPortCalls.swift", "vesselShipments.getVesselPortCalls"],
  Vesl686: ["../EusoTrip/Views/Vessel/686_VesselPortDirectory.swift", "vesselShipments.getPorts"],
  Vesl697: ["../EusoTrip/Views/Vessel/697_VesselPortOperations.swift", "vesselShipments.getPortConditions"],
  Vesl711: ["../EusoTrip/Views/Vessel/711_VesselCrewRestHours.swift", "vesselShipments.getVesselCrew"],
  Vesl789: ["../EusoTrip/Views/Vessel/789_VesselCustomsStatusUpdate.swift", "vesselShipments.getCustomsEntries"],
  Vesl814: ["../EusoTrip/Views/Vessel/814_VesselCustomsEntryFiling.swift", "vesselShipments.updateCustomsStatus"],
  Vesl822: ["../EusoTrip/Views/Vessel/822_VesselWriteCenter.swift", "publishVesselFreightRate"],
};

function balancedDelimited(source, marker, opening = "{", closing = "}") {
  const markerIndex = source.indexOf(marker);
  assert.notEqual(markerIndex, -1, `missing ${marker}`);
  const openIndex = source.indexOf(opening, markerIndex + marker.length);
  assert.notEqual(openIndex, -1, `missing ${opening} for ${marker}`);

  let depth = 0;
  let stringDelimiter = null;
  let escaped = false;
  let lineComment = false;
  let blockCommentDepth = 0;

  for (let index = openIndex; index < source.length; index += 1) {
    const char = source[index];
    const next = source[index + 1];

    if (lineComment) {
      if (char === "\n") lineComment = false;
      continue;
    }
    if (blockCommentDepth > 0) {
      if (char === "/" && next === "*") {
        blockCommentDepth += 1;
        index += 1;
      } else if (char === "*" && next === "/") {
        blockCommentDepth -= 1;
        index += 1;
      }
      continue;
    }
    if (stringDelimiter !== null) {
      if (escaped) escaped = false;
      else if (char === "\\") escaped = true;
      else if (char === stringDelimiter) stringDelimiter = null;
      continue;
    }
    if (char === "/" && next === "/") {
      lineComment = true;
      index += 1;
      continue;
    }
    if (char === "/" && next === "*") {
      blockCommentDepth = 1;
      index += 1;
      continue;
    }
    if (char === '"' || char === "'") {
      stringDelimiter = char;
      continue;
    }
    if (char === opening) depth += 1;
    if (char === closing) {
      depth -= 1;
      if (depth === 0) return source.slice(openIndex + 1, index);
    }
  }
  assert.fail(`unterminated ${opening}${closing} block for ${marker}`);
}

function balancedBlock(source, marker) {
  return balancedDelimited(source, marker, "{", "}");
}

function dockDestinations(methodName) {
  const block = balancedBlock(router, `static func ${methodName}(`);
  const entries = [...block.matchAll(
    /(home|workOne|workTwo|me):\s*\.init\(destinationId:\s*"([^"]+)",\s*label:\s*"([^"]+)"/g,
  )].map((match) => ({ slot: match[1], id: match[2], label: match[3] }));
  assert.equal(entries.length, 4, `${methodName} must declare exactly four dock entries`);
  assert.deepEqual(entries.map(({ slot }) => slot), ["home", "workOne", "workTwo", "me"]);
  assert.equal(entries[0].label, "Home", `${methodName} first dock entry must be Home`);
  assert.equal(entries[3].label, "Me", `${methodName} last dock entry must be Me`);
  assert.equal(new Set(entries.map(({ id }) => id)).size, 4, `${methodName} dock IDs must be unique`);
  return entries.map(({ id }) => id);
}

function surfaceTabRoots(surfaceName) {
  const block = balancedBlock(router, `struct ${surfaceName}: View`);
  const declaration = block.match(/private static let tabRoots:\s*Set<String>\s*=\s*\[([\s\S]*?)\]/);
  assert.ok(declaration, `${surfaceName} is missing tabRoots`);
  return [...declaration[1].matchAll(/"([^"]+)"/g)].map((match) => match[1]);
}

function nativeModeDefinition(name) {
  const block = balancedDelimited(router, `static let ${name} = Self`, "(", ")");
  const scalar = (field) => {
    const match = block.match(new RegExp(`${field}:\\s*\\.([A-Za-z][A-Za-z0-9]*)`));
    assert.ok(match, `${name} is missing ${field}`);
    return match[1];
  };
  const dock = [...block.matchAll(
    /(home|workOne|workTwo|me):\s*\.init\(destinationId:\s*"([^"]+)",\s*label:\s*"([^"]+)"/g,
  )].map((match) => [match[1], match[2], match[3]]);
  const array = (field) => {
    const match = block.match(new RegExp(`${field}:\\s*\\[([^\\]]*)\\]`));
    assert.ok(match, `${name} is missing ${field}`);
    return [...match[1].matchAll(/"([^"]+)"/g)].map((entry) => entry[1]);
  };
  return {
    role: scalar("role"),
    mode: scalar("mode"),
    registryRole: scalar("registryRole"),
    dock,
    detailRoutes: array("detailRoutes"),
    screensWithOwnBack: array("screensWithOwnBack"),
  };
}

const roleEnumBlock = balancedBlock(authModels, "enum EusoRole:");
const canonicalRoles = [...roleEnumBlock.matchAll(/^\s*case\s+([A-Za-z][A-Za-z0-9]*)\s*=/gm)]
  .map((match) => match[1]);

const assignmentBlock = balancedBlock(router, "enum RoleSurfaceAssignment:");
const assignmentRawValues = Object.fromEntries(
  [...assignmentBlock.matchAll(/^\s*case\s+([A-Za-z][A-Za-z0-9]*)\s*=\s*"([^"]+)"/gm)]
    .map((match) => [match[1], match[2]]),
);

const assignmentFunction = balancedBlock(
  router,
  "static func forRole(_ role: EusoRole) -> RoleSurfaceAssignment",
);
const roleAssignments = Object.fromEntries(
  [...assignmentFunction.matchAll(/^\s*case\s+\.([A-Za-z][A-Za-z0-9]*)\s*:\s*return\s+\.([A-Za-z][A-Za-z0-9]*)/gm)]
    .map((match) => [match[1], match[2]]),
);

const registryIds = new Set(
  [...registry.matchAll(/\.init\(id:\s*"([^"]+)"/g)].map((match) => match[1]),
);

test("EusoRole has exactly 25 canonical roles and every role has one exact surface", () => {
  assert.equal(canonicalRoles.length, 25);
  assert.deepEqual(canonicalRoles, Object.keys(expectedMatrix));
  assert.deepEqual(Object.keys(assignmentRawValues), canonicalRoles);
  assert.deepEqual(Object.keys(roleAssignments), canonicalRoles);
  assert.deepEqual(assignmentRawValues, expectedMatrix);
  for (const role of canonicalRoles) {
    assert.equal(roleAssignments[role], role, `${role} maps through another role's assignment`);
  }
  assert.doesNotMatch(assignmentFunction, /^\s*default\s*:/m);
});

for (const role of canonicalRoles) {
  test(`${role} has an individually named surface and four-slot dock contract`, () => {
    assert.equal(assignmentRawValues[role], expectedMatrix[role]);
    assert.equal(roleAssignments[role], role);

    if (expectedNativeModeDefinitions[role]) {
      assert.equal(nativeModeDefinition(role).dock.length, 4);
      return;
    }
    if (["safety", "factoring", "serviceProvider"].includes(role)) {
      const webDefinition = balancedBlock(
        router,
        "static func forRole(_ role: EusoRole) -> WebRoleDockDefinition",
      );
      assert.match(webDefinition, new RegExp(`case \\.${role}:\\s*\\n\\s*return \\.init`));
      return;
    }
    assert.ok(directDockByRole[role], `${role} has no dock owner`);
    assert.equal(dockDestinations(directDockByRole[role]).length, 4);
  });
}

test("RoleSurfaceRouter switches all 25 assignments without a family/default branch", () => {
  const block = balancedBlock(router, "struct RoleSurfaceRouter: View");
  const cases = [...block.matchAll(/^\s*case\s+\.([A-Za-z][A-Za-z0-9]*)\s*:/gm)]
    .map((match) => match[1]);
  assert.deepEqual(cases, canonicalRoles);
  assert.equal(new Set(cases).size, 25);
  assert.doesNotMatch(block, /^\s*default\s*:/m);
  assert.match(block, /switch RoleSurfaceAssignment\.forRole\(role\)/);
});

test("only Safety Manager, Factoring and Service Provider are explicit web continuations", () => {
  const continuations = Object.entries(expectedMatrix)
    .filter(([, surface]) => surface.startsWith("WebContinuationSurface."))
    .map(([role]) => role);
  assert.deepEqual(continuations, ["safety", "factoring", "serviceProvider"]);

  const continuationFlag = balancedBlock(router, "var isContinuation: Bool");
  assert.match(continuationFlag, /case \.safety, \.factoring, \.serviceProvider:[\s\S]{0,80}return true/);
  assert.doesNotMatch(continuationFlag, /^\s*default\s*:/m);

  const routerBlock = balancedBlock(router, "struct RoleSurfaceRouter: View");
  assert.equal((routerBlock.match(/WebContinuationSurface\(role:\s*role/g) ?? []).length, 3);

  const webDefinition = balancedBlock(
    router,
    "static func forRole(_ role: EusoRole) -> WebRoleDockDefinition",
  );
  const constructible = [...webDefinition.matchAll(
    /^\s*case\s+\.([A-Za-z][A-Za-z0-9]*)\s*:\s*\n\s*return\s+\.init/gm,
  )].map((match) => match[1]);
  assert.deepEqual(constructible, ["safety", "factoring", "serviceProvider"]);
  assert.doesNotMatch(webDefinition, /^\s*default\s*:/m);
});

for (const role of ["safety", "factoring", "serviceProvider"]) {
  test(`${role} continuation has a stable four-destination production dock`, () => {
    const block = balancedBlock(
      router,
      "static func forRole(_ role: EusoRole) -> WebRoleDockDefinition",
    );
    const start = block.indexOf(`case .${role}:`);
    assert.notEqual(start, -1);
    const next = block.indexOf("\n        case .", start + 1);
    const branch = block.slice(start, next === -1 ? block.length : next);
    const entries = [...branch.matchAll(
      /(home|workOne|workTwo|me):\s*item\("([^"]+)",\s*"([^"]+)"/g,
    )].map((match) => [match[1], match[2], match[3]]);
    assert.deepEqual(entries.map((entry) => entry[0]), ["home", "workOne", "workTwo", "me"]);
    assert.equal(entries[0][2], "Home");
    assert.equal(entries[3][2], "Me");
    assert.equal(new Set(entries.map((entry) => entry[1])).size, 4);
    for (const [, path] of entries) assert.match(path, /^\//);
  });
}

for (const [name, expected] of Object.entries(expectedNativeModeDefinitions)) {
  test(`${name} native mode dock and registry assignment are exact`, () => {
    const actual = nativeModeDefinition(name);
    assert.equal(actual.role, expected.role);
    assert.equal(actual.mode, expected.mode);
    assert.equal(actual.registryRole, expected.registryRole);
    assert.deepEqual(actual.dock, expected.dock);
    assert.deepEqual(actual.detailRoutes, expected.detailRoutes);
    assert.equal(new Set(actual.dock.map((entry) => entry[1])).size, 4);
    assert.match(actual.dock[0][1], /^Role/);
    assert.match(actual.dock[3][1], /^Role/);
    for (const [, destination] of actual.dock.slice(1, 3)) {
      assert.ok(registryIds.has(destination), `${name} destination ${destination} is not registered`);
    }
    for (const destination of actual.detailRoutes) {
      assert.ok(registryIds.has(destination), `${name} detail ${destination} is not registered`);
    }
    for (const destination of actual.screensWithOwnBack) {
      assert.ok(
        actual.detailRoutes.includes(destination),
        `${name} own-back destination ${destination} is not an allowed detail`,
      );
    }
  });
}

test("every promoted registry root is backed by a real iOS API contract", () => {
  const promotedIds = new Set();
  for (const expected of Object.values(expectedNativeModeDefinitions)) {
    for (const [, destination] of expected.dock.slice(1, 3)) promotedIds.add(destination);
    for (const destination of expected.detailRoutes) promotedIds.add(destination);
  }
  assert.deepEqual([...promotedIds].sort(), Object.keys(queryBackedNativeRoots).sort());

  for (const [screenId, [path, procedure]] of Object.entries(queryBackedNativeRoots)) {
    const source = fs.readFileSync(new URL(path, import.meta.url), "utf8");
    const contractPattern = screenId === "Vesl822"
      ? new RegExp(`\\b${procedure}\\b`)
      : new RegExp(`"${procedure.replaceAll(".", "\\.")}"`);
    assert.match(source, contractPattern, `${screenId} lost ${procedure}`);
    assert.match(source, /EusoTripAPI\.shared\.[A-Za-z]/, `${screenId} has no real API call`);
  }
});

for (const [catalogMethod, surfaceName] of directNativeSurfaces) {
  test(`${catalogMethod} dock exactly matches ${surfaceName} roots and registry`, () => {
    const destinations = dockDestinations(catalogMethod);
    const roots = surfaceTabRoots(surfaceName);
    assert.deepEqual(
      [...new Set(destinations)].sort(),
      [...new Set(roots)].sort(),
      `${catalogMethod} dock and ${surfaceName}.tabRoots drifted`,
    );
    for (const destination of destinations) {
      assert.ok(registryIds.has(destination), `${catalogMethod} destination ${destination} is not registered`);
    }
  });

  test(`${surfaceName} owns a stack, edge back, and detail-first pop`, () => {
    const block = balancedBlock(router, `struct ${surfaceName}: View`);
    assert.match(block, /@State private var screenStack/, `${surfaceName} has no role-owned stack`);
    if (surfaceName === "ShipperSurface") {
      assert.match(block, /\.modifier\(ShipperBackOverlay\(/);
      assert.match(block, /\.modifier\(RoleDetailLayer\(/);
      assert.match(block, /\.eusoShipperNavBack/);
    } else {
      assert.match(block, /\.modifier\(RoleNavBackOverlay\(/);
      assert.match(block, /\.modifier\(RoleDetailLayer\(/);
      assert.match(block, /\.eusoRoleNavBack/);
    }
    const backOwner = surfaceName === "ShipperSurface"
      ? balancedBlock(router, "private struct ShipperNavReceivers")
      : block;
    assert.match(
      backOwner,
      /if pushedDetail != nil[\s\S]{0,500}else(?: if)?[\s\S]{0,250}(?:popOne\(\)|screenStack\.removeLast\(\))/,
      `${surfaceName} must dismiss its detail layer before popping the stack`,
    );
  });
}

test("driver owns the same stable four-slot and detail-first contracts", () => {
  assert.deepEqual(dockDestinations("driver"), ["home", "trips", "loads", "me"]);
  const contentView = balancedBlock(registry, "struct ContentView: View");
  assert.match(contentView, /RoleDockCatalog\.driver\(/);
  assert.match(contentView, /\.environment\(\\\.roleDockContract, driverRoleDock\)/);
  assert.match(contentView, /\.modifier\(EusoEdgeSwipeBack\(/);
  assert.match(contentView, /\.modifier\(RoleDetailLayer\(/);
  assert.match(
    contentView,
    /if driverPushedDetail != nil[\s\S]{0,500}driverPushedDetail = nil/,
  );
});

test("shared native mode host cannot swap role catalogs and pops detail first", () => {
  const block = balancedBlock(router, "struct NativeModeRoleSurface: View");
  assert.match(block, /@State private var screenStack/);
  assert.match(block, /definition\.allowedRoutes\.contains\(screenId\)/);
  assert.match(block, /ScreenRegistry\.forRole\(definition\.registryRole\)/);
  assert.match(block, /guard definition\.tabRoots\.contains\(destination\)/);
  assert.match(block, /\.environment\(\\\.roleDockContract, roleDock\)/);
  assert.match(block, /\.modifier\(RoleNavBackOverlay\(/);
  assert.match(block, /\.modifier\(RoleDetailLayer\(/);
  assert.match(
    block,
    /if pushedDetail != nil[\s\S]{0,500}else if screenStack\.count > 1[\s\S]{0,250}screenStack\.removeLast\(\)/,
  );
  assert.match(block, /role:\s*definition\.role/);
  assert.doesNotMatch(block, /RoleAccess\.canRender/);
});

test("Shell fixes Home/work/work/Me around one center ESANG orb", () => {
  const contract = balancedBlock(designSystem, "struct RoleDockContract");
  assert.match(contract, /leading:\s*\[home, workOne\]/);
  assert.match(contract, /trailing:\s*\[workTwo, me\]/);

  const shell = balancedBlock(designSystem, "struct Shell<Content: View, Nav: View>: View");
  assert.match(shell, /leading:\s*contract\.leading\.map/);
  assert.match(shell, /trailing:\s*contract\.trailing\.map/);
  assert.match(shell, /onTapOrb:\s*contract\.openESang/);
  assert.match(shell, /routesThroughEnvironment:\s*false/);

  const bottomNav = balancedBlock(designSystem, "struct BottomNav: View");
  assert.match(bottomNav, /ForEach\(leading\)/);
  assert.match(bottomNav, /Color\.clear[\s\S]{0,300}ForEach\(trailing\)/);
  assert.match(bottomNav, /OrbeSang\(state:\s*orbState/);
  assert.match(bottomNav, /\.accessibilityLabel\("ESANG"\)/);
});

test("native edge swipe and scroll-return primitives remain available app-wide", () => {
  const edgeSwipe = balancedBlock(detailNavigation, "struct EusoEdgeSwipeBack: ViewModifier");
  assert.match(edgeSwipe, /@GestureState private var dragTranslation/);
  assert.match(edgeSwipe, /\.offset\(x:\s*interactiveOffset\)/);
  assert.match(edgeSwipe, /\.updating\(\$dragTranslation\)/);
  assert.match(edgeSwipe, /value\.startLocation\.x <= 36/);
  assert.match(edgeSwipe, /horizontal >= 72/);
  assert.match(edgeSwipe, /horizontal > vertical \* 1\.25/);
  assert.match(edgeSwipe, /value\.predictedEndTranslation\.width >= 90/);
  assert.match(edgeSwipe, /\.simultaneousGesture\(/);
  assert.match(edgeSwipe, /onBack\(\)/);

  const restoration = balancedBlock(detailNavigation, "func eusoRestoreScrollPosition(");
  assert.match(restoration, /proxy\.scrollTo\(fallback, anchor:\s*\.top\)/);
  assert.match(restoration, /proxy\.scrollTo\(anchor, anchor:\s*\.center\)/);
});

test("RoleAccess maps all shared rail and vessel roles to their native registries", () => {
  const allowed = balancedBlock(router, "static func allowedScreenRoles(for role: EusoRole)");
  assert.match(
    allowed,
    /case \.railShipper, \.railCatalyst, \.railDispatch,[\s\S]{0,160}\.railBroker:[\s\S]{0,100}return \[\.railEngineer\]/,
  );
  assert.match(
    allowed,
    /case \.vesselOperator, \.portMaster, \.shipCaptain,[\s\S]{0,120}\.customsBroker:[\s\S]{0,100}return \[\.vesselOperator\]/,
  );
  assert.match(allowed, /case \.safety, \.factoring, \.serviceProvider:[\s\S]{0,80}return \[\]/);
  assert.doesNotMatch(allowed, /^\s*default\s*:/m);
});
