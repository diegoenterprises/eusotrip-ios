import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

const root = process.cwd();
const read = relative => fs.readFileSync(path.join(root, relative), "utf8");

const authModels = read("EusoTrip/Models/AuthModels.swift");
const router = read("EusoTrip/Views/RoleSurfaceRouter.swift");
const shell = read("EusoTrip/Theme/DesignSystem.swift");
const shared = read("EusoTrip/Views/Settings/VoiceDialectPicker.swift");
const driverHub = read("EusoTrip/Views/Driver/067A_DriverMeHubs.swift");
const driverLegacy = read("EusoTrip/Views/Driver/MeDetailScreens.swift");
const shipper = read("EusoTrip/Views/Shipper/211_ShipperSettings.swift");
const catalyst = read("EusoTrip/Views/Catalyst/311_CatalystSettings.swift");
const dispatch = read("EusoTrip/Views/Dispatch/Dpch734_DispatcherControlQuartet.swift");
const railEngineer = read("EusoTrip/Views/Rail/556_RailEngineerAccount.swift");
const vesselOperator = read("EusoTrip/Views/Vessel/656_VesselOperatorAccount.swift");
const liveStores = read("EusoTrip/ViewModels/LiveDataStores.swift");

const roles = [
  ["driver", "DRIVER", "me", "dedicated"],
  ["shipper", "SHIPPER", "320", "dedicated"],
  ["catalyst", "CATALYST", "350", "dedicated"],
  ["broker", "BROKER", "404B", "shared"],
  ["dispatch", "DISPATCH", "Dpch713", "dedicated"],
  ["escort", "ESCORT", "620", "shared"],
  ["terminal", "TERMINAL_MANAGER", "703", "shared"],
  ["compliance", "COMPLIANCE_OFFICER", "903", "shared"],
  ["safety", "SAFETY_MANAGER", "/settings", "web"],
  ["admin", "ADMIN", "804", "shared"],
  ["superAdmin", "SUPER_ADMIN", "804", "shared"],
  ["factoring", "FACTORING", "/factoring/settings", "web"],
  ["railShipper", "RAIL_SHIPPER", "RoleRailShipperMe", "shared"],
  ["railCatalyst", "RAIL_CATALYST", "RoleRailCatalystMe", "shared"],
  ["railDispatch", "RAIL_DISPATCHER", "RoleRailDispatchMe", "shared"],
  ["railEngineer", "RAIL_ENGINEER", "Rail556", "dedicated"],
  ["railConductor", "RAIL_CONDUCTOR", "RoleRailConductorMe", "shared"],
  ["railBroker", "RAIL_BROKER", "RoleRailBrokerMe", "shared"],
  ["vesselShipper", "VESSEL_SHIPPER", "320", "dedicated"],
  ["vesselOperator", "VESSEL_OPERATOR", "Vesl656", "dedicated"],
  ["portMaster", "PORT_MASTER", "RolePortMasterMe", "shared"],
  ["shipCaptain", "SHIP_CAPTAIN", "RoleShipCaptainMe", "shared"],
  ["vesselBroker", "VESSEL_BROKER", "RoleVesselBrokerMe", "shared"],
  ["customsBroker", "CUSTOMS_BROKER", "RoleCustomsBrokerMe", "shared"],
  ["serviceProvider", "SERVICE_PROVIDER", "/settings", "web"],
];

test("all 25 authenticated roles have an explicit Me/settings journey", () => {
  assert.equal(roles.length, 25);
  assert.equal(new Set(roles.map(([, raw]) => raw)).size, 25);
  assert.equal(roles.filter(([, , , kind]) => kind === "dedicated").length, 7);
  assert.equal(roles.filter(([, , , kind]) => kind === "shared").length, 15);
  assert.equal(roles.filter(([, , , kind]) => kind === "web").length, 3);

  for (const [swiftCase, rawRole, destination] of roles) {
    assert.match(authModels, new RegExp(`case\\s+${swiftCase}\\s*=\\s*"${rawRole}"`), rawRole);
    assert.ok(router.includes(`destinationId: "${destination}"`) || router.includes(`item("${destination}", "Me"`), `${rawRole} Me destination ${destination}`);
    assert.ok(shared.includes(`.${swiftCase}`), `${rawRole} is absent from RoleSettingsCatalog`);
  }
});

test("shared settings are progressive, server-owned, and read back after writes", () => {
  const requiredCategories = ["notifications", "operations", "privacy", "appearance"];
  for (const category of requiredCategories) {
    assert.ok(shared.includes(`case ${category}`), `missing ${category} category`);
  }

  for (const endpoint of [
    "settings.getSettings",
    "users.getNotificationPreferences",
    "users.updateNotificationPreferences",
    "settings.updateDisplaySettings",
    "settings.updateOperationalPreferences",
    "settings.updatePrivacySettings",
  ]) {
    assert.ok(shared.includes(endpoint), `missing ${endpoint}`);
  }

  assert.match(shared, /@SceneStorage\("euso\.role\.settings\.expandedCategory"\)/);
  assert.match(shared, /expandedCategory = isOpen \? "" : category\.id\.rawValue/);
  assert.match(shared, /do \{[\s\S]*catch \{/);
  assert.match(shared, /readbackMismatch/);
  assert.match(shared, /contractMismatch/);
  assert.match(shared, /storageScopes\.common == "user"/);
  assert.ok(shared.indexOf("settings.updateDisplaySettings") < shared.indexOf("UserDefaults.standard.set(theme"), "theme must reach the server before its device cache is mirrored");
});

test("Shell exposes shared settings only from eligible active Me destinations", () => {
  assert.match(shell, /RoleSettingsCatalog\.needsSharedEntry\(for: roleDockContract\)/);
  assert.match(shell, /RoleSettingsAccessCard\(\)/);
  assert.match(shared, /me\.destinationId == contract\.activeDestinationId/);
  for (const destination of ["me", "320", "350", "Dpch713", "Rail556", "Vesl656", "/settings", "/factoring/settings"]) {
    assert.ok(shared.includes(`"${destination}"`), `dedicated destination ${destination} must not receive a duplicate shared card`);
  }
});

test("dedicated native journeys keep role controls progressive and persisted", () => {
  const contracts = [
    [shipper, "shipper.settings.expandedSection", "NotificationPreferencesStore"],
    [catalyst, "catalyst.settings.expandedSection", "settings.updateNotificationSettings"],
    [dispatch, "dispatch.settings.expandedSection", "settings.updateDispatcherSettings"],
    [railEngineer, "rail.engineer.me.expandedHub", "settings.updateOperationalPreferences"],
    [vesselOperator, "vessel.operator.me.expandedHub", "settings.updateOperationalPreferences"],
  ];
  for (const [source, disclosureKey, endpoint] of contracts) {
    assert.ok(source.includes(disclosureKey), disclosureKey);
    assert.ok(source.includes(endpoint), endpoint);
  }
  for (const source of [catalyst, dispatch, railEngineer, vesselOperator]) {
    assert.match(source, /do \{[\s\S]*catch \{/);
  }
  assert.match(liveStores, /final class NotificationPreferencesStore[\s\S]*do \{[\s\S]*updateNotificationPreferences[\s\S]*catch \{/);

  assert.ok(driverHub.includes("RoleSettingsAccessCard()"));
  const legacyBody = driverLegacy.slice(
    driverLegacy.indexOf("struct MeSettingsView"),
    driverLegacy.indexOf("private func toggleRow", driverLegacy.indexOf("struct MeSettingsView"))
  );
  assert.ok(legacyBody.includes("RoleSettingsAccessCard()"));
  for (const removedDeadControl of ["Push notifications", "In-app sounds", "\"Haptics\"", "Face ID unlock", "Change password", "Sessions + devices"]) {
    assert.ok(!legacyBody.includes(removedDeadControl), `${removedDeadControl} remains reachable in legacy Driver settings`);
  }
  assert.ok(legacyBody.includes("PasskeysManagementView"), "real passkey management must remain reachable");
});

test("role extensions remain explicit instead of leaking across industries", () => {
  for (const extension of ["driver_pulse", "dispatch_board", "catalyst_alerts", "rail_units", "vessel_units"]) {
    assert.ok(shared.includes(`"${extension}"`), extension);
  }
  for (const pulseControl of ["turnByTurn", "voiceWakeWord", "drivingAutoDetect", "hapticsIntensity", "complicationStyle"]) {
    assert.ok(shared.includes(pulseControl), `missing account-backed Pulse control ${pulseControl}`);
  }
  assert.match(shared, /if role == \.driver/);
});
