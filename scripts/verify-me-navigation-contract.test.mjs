import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const nativeMeSurfaces = [
  ["carrier", "../EusoTrip/Views/Carrier/350_CarrierMe.swift"],
  ["broker", "../EusoTrip/Views/Broker/404B_BrokerMe.swift"],
  ["escort", "../EusoTrip/Views/Escort/620_EscortMeHome.swift"],
  ["terminal", "../EusoTrip/Views/Terminal/703_TerminalMe.swift"],
  ["admin", "../EusoTrip/Views/Admin/804_AdminMe.swift"],
  ["dispatch", "../EusoTrip/Views/Dispatch/Dpch713_DispatchMe.swift"],
  ["compliance", "../EusoTrip/Views/Compliance/903_ComplianceMe.swift"],
  ["rail engineer", "../EusoTrip/Views/Rail/556_RailEngineerAccount.swift"],
  ["vessel operator", "../EusoTrip/Views/Vessel/656_VesselOperatorAccount.swift"],
];

const exactRoleMePolicy = {
  driver: "persisted-driver",
  shipper: "persisted-shipper",
  catalyst: "persisted-carrier",
  broker: "persisted-broker",
  dispatch: "persisted-dispatch",
  escort: "persisted-escort",
  terminal: "persisted-terminal",
  compliance: "persisted-compliance",
  safety: "web-continuation-no-native-child",
  admin: "persisted-admin",
  superAdmin: "persisted-admin",
  factoring: "web-continuation-no-native-child",
  railShipper: "native-mode-session-only",
  railCatalyst: "native-mode-session-only",
  railDispatch: "native-mode-session-only",
  railEngineer: "persisted-rail-engineer",
  railConductor: "native-mode-session-only",
  railBroker: "native-mode-session-only",
  vesselShipper: "persisted-shipper",
  vesselOperator: "persisted-vessel-operator",
  portMaster: "native-mode-session-only",
  shipCaptain: "native-mode-session-only",
  vesselBroker: "native-mode-session-only",
  customsBroker: "native-mode-session-only",
  serviceProvider: "web-continuation-no-native-child",
};

function source(relativePath) {
  return fs.readFileSync(new URL(relativePath, import.meta.url), "utf8");
}

test("all 25 roles have an explicit Me restoration policy", () => {
  const auth = source("../EusoTrip/Models/AuthModels.swift");
  const router = source("../EusoTrip/Views/RoleSurfaceRouter.swift");
  const enumBlock = auth.match(/enum EusoRole:[\s\S]*?var id:/)?.[0] ?? "";
  const declaredRoles = [...enumBlock.matchAll(/^\s*case\s+(\w+)\s*=/gm)]
    .map((match) => match[1]);

  assert.equal(declaredRoles.length, 25);
  assert.deepEqual(
    Object.keys(exactRoleMePolicy).sort(),
    declaredRoles.sort(),
  );
  assert.match(router, /case \.safety:[\s\S]{0,100}WebContinuationSurface/);
  assert.match(router, /case \.factoring:[\s\S]{0,100}WebContinuationSurface/);
  assert.match(router, /case \.serviceProvider:[\s\S]{0,100}WebContinuationSurface/);
  assert.equal(
    Object.values(exactRoleMePolicy).filter((policy) => policy === "native-mode-session-only").length,
    9,
  );

  const nativeModeMe = router.match(/private struct NativeModeRoleMe:[\s\S]*?private struct NativeModeRouteUnavailable/)?.[0] ?? "";
  assert.match(nativeModeMe, /session\.user\?\.name/);
  assert.doesNotMatch(nativeModeMe, /rolePushDetail|NavSwap|expandedHub|returnAnchor/);
});

for (const [role, relativePath] of nativeMeSurfaces) {
  test(`${role} Me surface persists disclosure and return position`, () => {
    const swift = source(relativePath);
    assert.match(swift, /@SceneStorage\([^\n]+expanded(?:Hub|Category)/);
    assert.match(swift, /@SceneStorage\([^\n]+returnAnchor/);
    assert.match(swift, /ScrollViewReader\s*\{/);
    assert.match(swift, /expanded(?:HubId|Category)\s*==/);
    assert.match(swift, /returnAnchor\s*=\s*(?:"row-|rowAnchor\()/);
    assert.match(swift, /eusoRestoreScrollPosition\s*\(/);
  });
}

test("driver Me and settings hubs persist disclosure and return position", () => {
  const swift = source("../EusoTrip/Views/Driver/067A_DriverMeHubs.swift");
  assert.match(swift, /@SceneStorage\("driver\.me\.child\.expandedSection"\)/);
  assert.match(swift, /@SceneStorage\("driver\.me\.child\.returnAnchor"\)/);
  assert.match(swift, /@SceneStorage\("driver\.me\.settings\.expandedSection"\)/);
  assert.match(swift, /@SceneStorage\("driver\.me\.settings\.returnAnchor"\)/);
  assert.ok((swift.match(/ScrollViewReader\s*\{/g) ?? []).length >= 2);
  assert.ok((swift.match(/eusoRestoreScrollPosition\s*\(/g) ?? []).length >= 2);
});

test("shipper Me and settings hubs persist disclosure and return position", () => {
  const me = source("../EusoTrip/Views/Shipper/320_MeHome.swift");
  const settings = source("../EusoTrip/Views/Shipper/211_ShipperSettings.swift");

  assert.match(me, /@SceneStorage\("shipper\.me\.child\.expandedSection"\)/);
  assert.match(me, /@SceneStorage\("shipper\.me\.child\.returnAnchor"\)/);
  assert.match(me, /@SceneStorage\("shipper\.me\.settings\.expandedSection"\)/);
  assert.match(me, /@SceneStorage\("shipper\.me\.settings\.returnAnchor"\)/);
  assert.ok((me.match(/eusoRestoreScrollPosition\s*\(/g) ?? []).length >= 2);
  assert.match(me, /\.task\s*\{\s*await refreshMeData\(\)\s*\}/);
  assert.match(me, /\.eusoRefreshable\s*\{\s*await refreshMeData\(\)\s*\}/);
  assert.equal(
    (me.match(/private func refreshMeData\(\) async/g) ?? []).length,
    1,
    "Shipper Me must share one real initial/pull loader without duplicate owner callbacks",
  );

  assert.match(settings, /@SceneStorage\("shipper\.settings\.expandedSection"\)/);
  assert.match(settings, /@SceneStorage\("shipper\.settings\.returnAnchor"\)/);
  assert.match(settings, /ScrollViewReader\s*\{/);
  assert.match(settings, /eusoRestoreScrollPosition\s*\(/);
  assert.equal(
    (settings.match(/settingsCategory\(\s*\n\s*id:/g) ?? []).length,
    5,
    "Shipper settings must remain grouped into five disclosure categories",
  );
  for (const anchor of ["account", "templates", "security", "about"]) {
    assert.match(settings, new RegExp(`returnAnchor\\s*=\\s*"section-${anchor}"`));
  }
});
