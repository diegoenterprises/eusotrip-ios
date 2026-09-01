import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
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
const shipperMe = read("EusoTrip/Views/Shipper/320_MeHome.swift");
const shipper = read("EusoTrip/Views/Shipper/211_ShipperSettings.swift");
const catalyst = read("EusoTrip/Views/Catalyst/311_CatalystSettings.swift");
const dispatch = read("EusoTrip/Views/Dispatch/Dpch734_DispatcherControlQuartet.swift");
const dispatchMe = read("EusoTrip/Views/Dispatch/Dpch713_DispatchMe.swift");
const carrierMe = read("EusoTrip/Views/Carrier/350_CarrierMe.swift");
const brokerMe = read("EusoTrip/Views/Broker/404B_BrokerMe.swift");
const escortMe = read("EusoTrip/Views/Escort/620_EscortMeHome.swift");
const terminalMe = read("EusoTrip/Views/Terminal/703_TerminalMe.swift");
const adminMe = read("EusoTrip/Views/Admin/804_AdminMe.swift");
const complianceMe = read("EusoTrip/Views/Compliance/903_ComplianceMe.swift");
const railEngineer = read("EusoTrip/Views/Rail/556_RailEngineerAccount.swift");
const vesselOperator = read("EusoTrip/Views/Vessel/656_VesselOperatorAccount.swift");
const liveStores = read("EusoTrip/ViewModels/LiveDataStores.swift");
const editableAvatar = read("EusoTrip/Views/Components/EditableProfileAvatar.swift");

const roles = [
  ["driver", "DRIVER", "me", "dedicated"],
  ["shipper", "SHIPPER", "320", "dedicated"],
  ["catalyst", "CATALYST", "350", "dedicated"],
  ["broker", "BROKER", "404B", "shared"],
  ["dispatch", "DISPATCH", "Dpch713", "dedicated"],
  ["escort", "ESCORT", "620", "shared"],
  ["terminal", "TERMINAL_MANAGER", "703", "shared"],
  ["compliance", "COMPLIANCE_OFFICER", "903", "shared"],
  ["safety", "SAFETY_MANAGER", "SafetyMe", "shared"],
  ["admin", "ADMIN", "804", "shared"],
  ["superAdmin", "SUPER_ADMIN", "804", "shared"],
  ["factoring", "FACTORING", "FactoringMe", "shared"],
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
  ["serviceProvider", "SERVICE_PROVIDER", "ZeunProviderMe", "shared"],
];

test("all 25 authenticated roles have an explicit Me/settings journey", () => {
  assert.equal(roles.length, 25);
  assert.equal(new Set(roles.map(([, raw]) => raw)).size, 25);
  assert.equal(roles.filter(([, , , kind]) => kind === "dedicated").length, 7);
  assert.equal(roles.filter(([, , , kind]) => kind === "shared").length, 18);
  assert.equal(roles.filter(([, , , kind]) => kind === "web").length, 0);

  for (const [swiftCase, rawRole, destination] of roles) {
    assert.match(authModels, new RegExp(`case\\s+${swiftCase}\\s*=\\s*"${rawRole}"`), rawRole);
    assert.ok(router.includes(`destinationId: "${destination}"`), `${rawRole} Me destination ${destination}`);
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
  assert.match(shared, /@SceneStorage\("euso\.role\.settings\.returnAnchor"\)/);
  assert.match(shared, /@SceneStorage\("euso\.role\.settings\.ownerRole"\)/);
  assert.match(shared, /storageOwnerRole != role\.rawValue/);
  assert.match(shared, /expandedID = willOpen \? id : ""/);
  assert.match(shared, /@SceneStorage\("euso\.role\.settings\.expandedCategory"\) private var expandedCategory = ""/);
  assert.match(shared, /\.eusoRefreshable\s*\{\s*await store\.load\(\)\s*\}/);
  assert.match(shared, /\.eusoRefreshSurface\("role-settings:\\\(role\.rawValue\)"\)/);
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
  for (const destination of ["me", "320", "350", "Dpch713", "Rail556", "Vesl656"]) {
    assert.ok(shared.includes(`"${destination}"`), `dedicated destination ${destination} must not receive a duplicate shared card`);
  }
  for (const destination of ["SafetyMe", "FactoringMe", "ZeunProviderMe"]) {
    assert.ok(!shared.includes(`"${destination}"`), `${destination} must receive the shared settings entry from Shell`);
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
  const driverSettingsHub = driverHub.slice(driverHub.indexOf("private struct DriverMeSettingsHubBody"));
  assert.ok(driverSettingsHub.includes("RoleSettingsAccessCard()"));
  for (const removedDeadControl of ["Push notifications", "In-app sounds", "\"Haptics\"", "Face ID unlock", "Change password", "Sessions + devices"]) {
    assert.ok(!driverSettingsHub.includes(removedDeadControl), `${removedDeadControl} remains reachable in Driver settings`);
  }
  const legacySettings = driverLegacy.slice(driverLegacy.indexOf("struct MeSettingsView"));
  assert.ok(legacySettings.includes("RoleSettingsAccessCard()"));
  assert.ok(legacySettings.includes("PasskeysManagementView"), "real passkey management must remain reachable");
});

test("Me and settings categories are collapsed until the user opens one", () => {
  const collapsed = [
    [driverHub, "driver.me.child.expandedSection"],
    [driverHub, "driver.me.settings.expandedSection"],
    [shipperMe, "shipper.me.child.expandedSection"],
    [shipperMe, "shipper.me.settings.expandedSection"],
    [shipper, "shipper.settings.expandedSection"],
    [carrierMe, "carrier.me.expandedHub"],
    [brokerMe, "broker.me.expandedCategory"],
    [dispatchMe, "dispatch.me.expandedHub"],
    [dispatch, "dispatch.settings.expandedSection"],
    [escortMe, "escort.me.expandedCategory"],
    [terminalMe, "terminal.me.expandedCategory"],
    [adminMe, "admin.me.expandedCategory"],
    [complianceMe, "compliance.me.expandedCategory"],
    [railEngineer, "rail.engineer.me.expandedHub"],
    [vesselOperator, "vessel.operator.me.expandedHub"],
    [catalyst, "catalyst.settings.expandedSection"],
    [shared, "euso.role.settings.expandedCategory"],
  ];
  for (const [source, key] of collapsed) {
    const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    assert.match(
      source,
      new RegExp(`@SceneStorage\\("${escapedKey}"\\)\\s+private var [^=\\n]+=[ \\t]*""`),
      `${key} must start collapsed`,
    );
  }
});

test("Me and settings disclosures share one persisted behavior", () => {
  assert.match(shared, /struct RoleDisclosureSection<Content: View>: View/);
  assert.match(shared, /RoleDisclosureSection\(/);
  assert.match(dispatch, /RoleDisclosureSection\(/);
  assert.match(dispatchMe, /RoleDisclosureSection\(/);
  assert.match(dispatchMe, /eusoRestoreScrollPosition\s*\(/);
});

test("dispatcher settings use canonical dock destinations and verified server readback", () => {
  const settingsNav = dispatch.slice(
    dispatch.indexOf("private struct ShellNav"),
    dispatch.indexOf("private struct DispatcherSettingsPayload"),
  );
  assert.match(dispatch, /DispatchNavRoute\.leading\(current:\s*\.me\)/);
  assert.match(dispatch, /DispatchNavRoute\.trailing\(current:\s*\.me\)/);
  assert.doesNotMatch(settingsNav, /NavSlot\(label:\s*"Drivers"/);
  assert.doesNotMatch(settingsNav, /NavSlot\(label:\s*"Loads"/);
  assert.match(dispatch, /case readbackMismatch/);
  assert.ok((dispatch.match(/"settings\.getSettings"/g) ?? []).length >= 3);
  assert.match(dispatch, /notifications == intendedNotifications/);
  assert.match(dispatch, /board == intendedBoard/);
  assert.match(dispatch, /canonical\.display\?\.theme == newTheme/);
});

test("shared Me avatar is tappable and verifies the authoritative profile write", () => {
  assert.match(dispatchMe, /EditableProfileAvatar\(size:\s*56\)/);
  assert.match(editableAvatar, /PhotosPicker\s*\(/);
  assert.match(editableAvatar, /"profile\.updateAvatar"/);
  assert.match(editableAvatar, /"profile\.getMyProfile"/);
  assert.match(editableAvatar, /authoritative\.avatar == dataURL/);
  assert.match(editableAvatar, /accessibilityLabel\("Change profile photo"\)/);
  assert.match(editableAvatar, /struct RoleProfileAvatarCard: View/);
  assert.match(editableAvatar, /\.eusoRefreshHandler\s*\{\s*await loadProfile\(\)\s*\}/);
  assert.match(shared, /static func needsSharedAvatar\(for contract: RoleDockContract\)/);
  for (const destination of ["me", "320", "350", "404B", "Dpch713", "620", "703", "804", "903", "Rail556", "Vesl656"]) {
    assert.ok(shared.includes(`"${destination}"`), `${destination} must not receive a duplicate avatar`);
  }
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

test("central settings and Me Swift sources pass the parser gate", () => {
  for (const sourcePath of [
    "EusoTrip/ViewModels/DynamicStore.swift",
    "EusoTrip/Theme/DesignSystem.swift",
    "EusoTrip/Views/Components/EditableProfileAvatar.swift",
    "EusoTrip/Views/Settings/VoiceDialectPicker.swift",
    "EusoTrip/Views/Driver/067A_DriverMeHubs.swift",
    "EusoTrip/Views/Shipper/320_MeHome.swift",
    "EusoTrip/Views/Carrier/350_CarrierMe.swift",
    "EusoTrip/Views/Broker/404B_BrokerMe.swift",
    "EusoTrip/Views/Dispatch/Dpch713_DispatchMe.swift",
    "EusoTrip/Views/Dispatch/Dpch734_DispatcherControlQuartet.swift",
    "EusoTrip/Views/Escort/620_EscortMeHome.swift",
    "EusoTrip/Views/Terminal/703_TerminalMe.swift",
    "EusoTrip/Views/Admin/804_AdminMe.swift",
    "EusoTrip/Views/Compliance/903_ComplianceMe.swift",
    "EusoTrip/Views/Rail/556_RailEngineerAccount.swift",
    "EusoTrip/Views/Vessel/656_VesselOperatorAccount.swift",
    "EusoTrip/Views/Shipper/211_ShipperSettings.swift",
    "EusoTrip/Views/Catalyst/311_CatalystSettings.swift",
    "EusoTrip/Views/Shipper/433_RecurringLoadsComposer.swift",
  ]) {
    const result = spawnSync("xcrun", ["swiftc", "-parse", sourcePath], {
      cwd: root,
      encoding: "utf8",
    });
    assert.equal(
      result.status,
      0,
      `${sourcePath} failed Swift parse:\n${result.stderr || result.stdout}`,
    );
  }
});
