import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

const root = process.cwd();
const read = relative => fs.readFileSync(path.join(root, relative), "utf8");

const authModels = read("EusoTrip/Models/AuthModels.swift");
const router = read("EusoTrip/Views/RoleSurfaceRouter.swift");
const contentView = read("EusoTrip/ContentView.swift");
const panel = read("EusoTrip/Views/Components/EusoCardIssuePanel.swift");

const sources = new Map([
  ["driverHub", read("EusoTrip/Views/Driver/067A_DriverMeHubs.swift")],
  ["driverWallet", read("EusoTrip/Views/Driver/069_MeWallet.swift")],
  ["shipperMe", read("EusoTrip/Views/Shipper/320_MeHome.swift")],
  ["shipperWallet", read("EusoTrip/Views/Shipper/290_WalletHome.swift")],
  ["carrierMe", read("EusoTrip/Views/Carrier/350_CarrierMe.swift")],
  ["brokerMe", read("EusoTrip/Views/Broker/404B_BrokerMe.swift")],
  ["dispatchMe", read("EusoTrip/Views/Dispatch/Dpch713_DispatchMe.swift")],
  ["escortMe", read("EusoTrip/Views/Escort/620_EscortMeHome.swift")],
  ["terminalMe", read("EusoTrip/Views/Terminal/703_TerminalMe.swift")],
  ["complianceMe", read("EusoTrip/Views/Compliance/903_ComplianceMe.swift")],
  ["railEngineerMe", read("EusoTrip/Views/Rail/556_RailEngineerAccount.swift")],
  ["vesselShipperHome", read("EusoTrip/Views/Vessel/001_VesselShipperHome.swift")],
  ["vesselOperatorMe", read("EusoTrip/Views/Vessel/656_VesselOperatorAccount.swift")],
  ["adminMe", read("EusoTrip/Views/Admin/804_AdminMe.swift")],
]);

const roleEnumStart = authModels.indexOf("enum EusoRole:");
const roleEnumEnd = authModels.indexOf("// MARK: - Registration taxonomy", roleEnumStart);
assert.ok(roleEnumStart >= 0 && roleEnumEnd > roleEnumStart, "EusoRole enum boundary is missing");
const roleEnum = authModels.slice(roleEnumStart, roleEnumEnd);
const declaredRoles = [...roleEnum.matchAll(/^\s*case\s+(\w+)\s*=\s*"([A-Z_]+)"/gm)]
  .map(([, swiftCase, rawValue]) => ({ swiftCase, rawValue }));

const excludedRoles = new Set(["ADMIN", "SUPER_ADMIN", "SERVICE_PROVIDER"]);
const eligibleRoles = declaredRoles.filter(({ rawValue }) => !excludedRoles.has(rawValue));

const directReachability = new Map([
  ["DRIVER", ["driverHub", 'action: .screen("069")', "driverWallet"]],
  ["SHIPPER", ["shipperMe", 'action: .screen("290")', "shipperWallet"]],
  ["CATALYST", ["router", 'destinationId: "350"', "carrierMe"]],
  ["BROKER", ["router", 'destinationId: "404B"', "brokerMe"]],
  ["DISPATCH", ["router", 'destinationId: "Dpch713"', "dispatchMe"]],
  ["ESCORT", ["router", 'destinationId: "620"', "escortMe"]],
  ["TERMINAL_MANAGER", ["router", 'destinationId: "703"', "terminalMe"]],
  ["COMPLIANCE_OFFICER", ["router", 'destinationId: "903"', "complianceMe"]],
  ["RAIL_ENGINEER", ["router", 'destinationId: "Rail556"', "railEngineerMe"]],
  ["VESSEL_SHIPPER", ["router", 'destinationId: "Vesl001"', "vesselShipperHome"]],
  ["VESSEL_OPERATOR", ["router", 'destinationId: "Vesl656"', "vesselOperatorMe"]],
]);

const nativeModeRoles = new Map([
  ["RAIL_SHIPPER", ["railShipper", "RoleRailShipperMe"]],
  ["RAIL_CATALYST", ["railCatalyst", "RoleRailCatalystMe"]],
  ["RAIL_DISPATCHER", ["railDispatch", "RoleRailDispatchMe"]],
  ["RAIL_CONDUCTOR", ["railConductor", "RoleRailConductorMe"]],
  ["RAIL_BROKER", ["railBroker", "RoleRailBrokerMe"]],
  ["PORT_MASTER", ["portMaster", "RolePortMasterMe"]],
  ["SHIP_CAPTAIN", ["shipCaptain", "RoleShipCaptainMe"]],
  ["VESSEL_BROKER", ["vesselBroker", "RoleVesselBrokerMe"]],
  ["CUSTOMS_BROKER", ["customsBroker", "RoleCustomsBrokerMe"]],
]);

function source(name) {
  if (name === "router") return router;
  const value = sources.get(name);
  assert.ok(value, `missing verifier source ${name}`);
  return value;
}

test("canonical role roster contains 25 roles and exactly 22 EusoCard-eligible roles", () => {
  assert.equal(declaredRoles.length, 25);
  assert.equal(new Set(declaredRoles.map(({ rawValue }) => rawValue)).size, 25);
  assert.equal(eligibleRoles.length, 22);
  assert.deepEqual(
    declaredRoles.filter(({ rawValue }) => excludedRoles.has(rawValue)).map(({ rawValue }) => rawValue).sort(),
    ["ADMIN", "SERVICE_PROVIDER", "SUPER_ADMIN"],
  );
});

test("every eligible direct role reaches the shared EusoCard panel through a real Home, Me, or Wallet route", () => {
  assert.equal(directReachability.size, 11);
  for (const [role, [routeSource, routeNeedle, panelSource]] of directReachability) {
    assert.ok(eligibleRoles.some(({ rawValue }) => rawValue === role), `${role} is not eligible`);
    assert.ok(source(routeSource).includes(routeNeedle), `${role} route is not reachable`);
    assert.ok(source(panelSource).includes("EusoCardIssuePanel("), `${role} does not mount the shared panel`);
  }
});

test("all nine native rail and vessel role Me destinations mount one shared server-backed panel", () => {
  const nativeMeStart = router.indexOf("private struct NativeModeRoleMe: View");
  const nativeMeEnd = router.indexOf("private struct NativeModeRouteUnavailable", nativeMeStart);
  assert.ok(nativeMeStart >= 0 && nativeMeEnd > nativeMeStart, "NativeModeRoleMe body is missing");
  const nativeMe = router.slice(nativeMeStart, nativeMeEnd);
  assert.equal((nativeMe.match(/EusoCardIssuePanel\(/g) ?? []).length, 1);

  for (const [role, [definition, meDestination]] of nativeModeRoles) {
    assert.ok(eligibleRoles.some(({ rawValue }) => rawValue === role), `${role} is not eligible`);
    assert.ok(router.includes(`static let ${definition} = Self(`), `${role} definition is missing`);
    assert.ok(router.includes(`me: .init(destinationId: "${meDestination}", label: "Me"`), `${role} Me route is missing`);
  }
});

test("Safety and Factoring native specialist Me routes expose EusoCard while excluded roles remain server-authoritative", () => {
  for (const [role, assignment, definition, meDestination] of [
    ["SAFETY_MANAGER", "NativeSpecialistRoleSurface.SAFETY_MANAGER", "safety", "SafetyMe"],
    ["FACTORING", "NativeSpecialistRoleSurface.FACTORING", "factoring", "FactoringMe"],
  ]) {
    assert.ok(eligibleRoles.some(({ rawValue }) => rawValue === role), `${role} is not eligible`);
    assert.ok(router.includes(assignment), `${role} native assignment is missing`);
    assert.ok(router.includes(`static let ${definition} = Self(`), `${role} specialist definition is missing`);
    assert.ok(router.includes(`me: .init(destinationId: "${meDestination}", label: "Me"`), `${role} Me route is missing`);
  }

  const meStart = router.indexOf("private var specialistMe: some View");
  const meEnd = router.indexOf("private func selectDestination", meStart);
  assert.ok(meStart >= 0 && meEnd > meStart, "native specialist Me body is missing");
  assert.equal((router.slice(meStart, meEnd).match(/EusoCardIssuePanel\(/g) ?? []).length, 1);
  assert.ok(!router.includes("struct WebContinuationSurface: View"));

  assert.ok(!sources.get("adminMe").includes("EusoCardIssuePanel("));
  assert.ok(!eligibleRoles.some(({ rawValue }) => excludedRoles.has(rawValue)));
  assert.ok(router.includes('case admin = "AdminSurface.ADMIN"'));
  assert.ok(router.includes('case superAdmin = "AdminSurface.SUPER_ADMIN"'));
});

test("the shared panel keeps server RBAC authoritative and never creates a client-side admin exception", () => {
  assert.ok(panel.includes("if let status, status.qualifying"));
  assert.ok(panel.includes('queryNoInput("wallet.getEusoCardStatus")') || contentView.includes('queryNoInput("wallet.getEusoCardStatus")') || read("EusoTrip/Services/EusoTripAPI.swift").includes('queryNoInput("wallet.getEusoCardStatus")'));
  assert.ok(!panel.includes("EusoRole.admin"));
  assert.ok(!panel.includes("EusoRole.superAdmin"));
  assert.ok(!panel.includes("ADMIN"));
  assert.ok(!panel.includes("SUPER_ADMIN"));
});

test("the complete reachability matrix covers every one of the 22 eligible roles exactly once", () => {
  const reached = new Set([
    ...directReachability.keys(),
    ...nativeModeRoles.keys(),
    "SAFETY_MANAGER",
    "FACTORING",
  ]);
  assert.equal(reached.size, 22);
  assert.deepEqual(
    [...reached].sort(),
    eligibleRoles.map(({ rawValue }) => rawValue).sort(),
  );
});
