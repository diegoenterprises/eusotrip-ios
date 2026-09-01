import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

const root = new URL("../", import.meta.url);
const read = (path) => fs.readFileSync(new URL(path, root), "utf8");

const router = read("EusoTrip/Views/RoleSurfaceRouter.swift");
const design = read("EusoTrip/Theme/DesignSystem.swift");
const navigation = read("EusoTrip/Theme/Components/RoleDetailPush.swift");
const auth = read("EusoTrip/Models/AuthModels.swift");
const refresh = read("EusoTrip/ViewModels/DynamicStore.swift");
const settings = read("EusoTrip/Views/Settings/VoiceDialectPicker.swift");
const avatar = read("EusoTrip/Views/Components/EditableProfileAvatar.swift");

function balancedBlock(source, marker) {
  const markerIndex = source.indexOf(marker);
  assert.notEqual(markerIndex, -1, `missing ${marker}`);
  const openIndex = source.indexOf("{", markerIndex + marker.length);
  assert.notEqual(openIndex, -1, `missing body for ${marker}`);
  let depth = 0;
  let string = false;
  let escaped = false;
  let lineComment = false;
  for (let index = openIndex; index < source.length; index += 1) {
    const char = source[index];
    const next = source[index + 1];
    if (lineComment) {
      if (char === "\n") lineComment = false;
      continue;
    }
    if (string) {
      if (escaped) escaped = false;
      else if (char === "\\") escaped = true;
      else if (char === '"') string = false;
      continue;
    }
    if (char === "/" && next === "/") {
      lineComment = true;
      index += 1;
      continue;
    }
    if (char === '"') {
      string = true;
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

const roleEnum = balancedBlock(auth, "enum EusoRole:");
const roles = [...roleEnum.matchAll(/^\s*case\s+(\w+)\s*=/gm)].map((match) => match[1]);

test("all 25 declared roles retain an explicit role-owned dock identity", () => {
  assert.equal(roles.length, 25);

  const directOwners = {
    driver: "driver",
    shipper: "shipper",
    carrier: "catalyst",
    catalyst: "catalyst",
    broker: "broker",
    escort: "escort",
    terminal: "terminal",
    compliance: "compliance",
    dispatch: "dispatch",
    railEngineer: "railEngineer",
    vesselOperator: "vesselOperator",
    vesselShipper: "vesselShipper",
  };
  for (const [method, owner] of Object.entries(directOwners)) {
    const block = balancedBlock(router, `static func ${method}(`);
    assert.match(block, new RegExp(`ownerRole:\\s*\\.${owner}\\b`), `${method} owner drifted`);
  }

  const admin = balancedBlock(router, "static func admin(");
  assert.match(admin, /ownerRole:\s*role\b/);
  assert.match(router, /RoleDockCatalog\.admin\(\s*\n\s*role:\s*role,/);

  const nativeMode = balancedBlock(router, "static func nativeModeRole(");
  assert.match(nativeMode, /ownerRole:\s*definition\.role/);
  const specialist = balancedBlock(router, "static func specialist(");
  assert.match(specialist, /ownerRole:\s*definition\.role/);
  assert.doesNotMatch(router, /static func webContinuation\(/);
  assert.doesNotMatch(router, /struct WebContinuationSurface: View/);

  const assignment = balancedBlock(router, "enum RoleSurfaceAssignment:");
  for (const role of roles) {
    assert.match(assignment, new RegExp(`^\\s*case\\s+${role}\\s*=`, "m"));
  }
});

test("BottomNav itself enforces the role contract outside Shell", () => {
  const item = balancedBlock(design, "struct RoleDockItem");
  assert.match(item, /let destinationId:\s*String/);
  assert.match(item, /let label:\s*String/);
  assert.match(item, /let systemImage:\s*String/);

  const contract = balancedBlock(design, "struct RoleDockContract");
  assert.match(contract, /let ownerRole:\s*EusoRole/);
  assert.match(contract, /let leading:\s*\[RoleDockItem\]/);
  assert.match(contract, /let trailing:\s*\[RoleDockItem\]/);
  assert.match(contract, /ownerRole:\s*EusoRole/);
  assert.match(contract, /private init\s*\(/);
  assert.match(contract, /precondition\(leading\.count == 2 && trailing\.count == 2\)/);
  assert.match(contract, /leading:\s*\[home, workOne\]/);
  assert.match(contract, /trailing:\s*\[workTwo, me\]/);

  const bottom = balancedBlock(design, "struct BottomNav: View");
  assert.match(bottom, /@Environment\(\\\.roleDockContract\) private var roleDockContract/);
  assert.match(bottom, /private var resolvedLeading/);
  assert.match(bottom, /private var resolvedTrailing/);
  assert.match(bottom, /ForEach\(resolvedLeading\)/);
  assert.match(bottom, /ForEach\(resolvedTrailing\)/);
  assert.match(bottom, /if roleDockContract != nil\s*\{\s*resolvedOrbAction\(\)/);
  assert.match(bottom, /if roleDockContract != nil\s*\{\s*s\.onTap\(\)/);

  const roleSlot = balancedBlock(design, "private func roleSlot(");
  assert.match(roleSlot, /label:\s*item\.label/);
  assert.match(roleSlot, /systemImage:\s*item\.systemImage/);
  assert.match(roleSlot, /isCurrent:\s*item\.destinationId == contract\.activeDestinationId/);
  assert.match(roleSlot, /contract\.select\(item\.destinationId\)/);
  assert.doesNotMatch(roleSlot, /switch\s+contract\.activeDestinationId|if\s+item\.destinationId/);
});

test("all routed Shells expose pull refresh without synthetic data work", () => {
  const shell = balancedBlock(design, "struct Shell<Content: View, Nav: View>: View");
  assert.match(shell, /\.eusoRefreshControl\(isEnabled:\s*roleDockContract != nil\)/);

  const control = balancedBlock(refresh, "private struct EusoRefreshControlModifier: ViewModifier");
  assert.match(control, /@Environment\(\\\.eusoRefreshSurfaceID\) private var surfaceID/);
  assert.match(control, /await refresh\(surfaceID, reason:\s*\.userPull\)/);
  assert.doesNotMatch(control, /registerHandler|session\.revalidate|NotificationCenter/);
});

test("shared Me roots receive one real editable avatar and server settings path", () => {
  const shell = balancedBlock(design, "struct Shell<Content: View, Nav: View>: View");
  assert.match(shell, /RoleSettingsCatalog\.needsSharedAvatar\(for:\s*roleDockContract\)/);
  assert.match(shell, /RoleProfileAvatarCard\(role:\s*roleDockContract\.ownerRole\)/);
  assert.match(shell, /RoleSettingsCatalog\.needsSharedEntry\(for:\s*roleDockContract\)/);

  const avatarPolicy = balancedBlock(settings, "static func needsSharedAvatar(");
  assert.match(avatarPolicy, /me\.destinationId == contract\.activeDestinationId/);
  assert.match(avatarPolicy, /destinationsWithEditableAvatar/);
  assert.match(avatar, /PhotosPicker\s*\(/);
  assert.match(avatar, /\.eusoRefreshHandler\s*\{\s*await loadProfile\(\)\s*\}/);
});

test("one path state machine owns tab, push, de-duplication, and guarded pop", () => {
  const path = balancedBlock(navigation, "enum RoleNavigationPathContract");
  assert.match(path, /tabRoots\.contains\(root\)/);
  assert.match(path, /if tabRoots\.contains\(destination\)/);
  assert.match(path, /stack = \[fallback\]/);
  assert.match(path, /guard stack\.last != destination/);
  assert.match(path, /guard stack\.count > 1 else \{ return false \}/);
  assert.match(path, /stack\.removeLast\(\)/);

  const directSurfaces = [
    "ShipperSurface",
    "CarrierSurface",
    "BrokerSurface",
    "EscortSurface",
    "TerminalSurface",
    "AdminSurface",
    "DispatchSurface",
    "ComplianceSurface",
    "RailEngineerSurface",
    "VesselShipperSurface",
    "VesselOperatorSurface",
  ];
  for (const surface of directSurfaces) {
    const block = balancedBlock(router, `struct ${surface}: View`);
    assert.match(block, /RoleNavigationPathContract\.activeTab\(/, `${surface} active tab is local`);
    assert.match(block, /RoleNavigationPathContract\.open\(/, `${surface} push is local`);
    assert.match(block, /RoleNavigationPathContract\.(?:pop|canPop)\(/, `${surface} back is local`);
  }

  const nativeMode = balancedBlock(router, "struct NativeModeRoleSurface: View");
  for (const method of ["activeTab", "open", "pop"]) {
    assert.match(nativeMode, new RegExp(`RoleNavigationPathContract\\.${method}\\(`));
  }
  assert.doesNotMatch(router, /screenStack\.append\(|screenStack\.removeLast\(\)/);
  assert.doesNotMatch(router, /active:\s*screenStack\.first/);
});

test("explicit and edge back share the same role-specific action", () => {
  for (const overlay of ["ShipperBackOverlay", "RoleNavBackOverlay"]) {
    const block = balancedBlock(router, `private struct ${overlay}: ViewModifier`);
    assert.match(block, /Button\(action:\s*sendBack\)/);
    assert.match(block, /EusoEdgeSwipeBack\([\s\S]{0,180}onBack:\s*sendBack/);
    assert.match(block, /private func sendBack\(\)/);
  }

  const edge = balancedBlock(navigation, "struct EusoEdgeSwipeBack: ViewModifier");
  assert.match(edge, /value\.startLocation\.x <= 36/);
  assert.match(edge, /horizontal >= 72/);
  assert.match(edge, /value\.predictedEndTranslation\.width >= 90/);
});

test("scroll and expanded-section return remains centrally available", () => {
  const restore = balancedBlock(navigation, "func eusoRestoreScrollPosition(");
  assert.match(restore, /proxy\.scrollTo\(fallback, anchor:\s*\.top\)/);
  assert.match(restore, /proxy\.scrollTo\(anchor, anchor:\s*\.center\)/);

  const meGate = read("scripts/verify-me-navigation-contract.test.mjs");
  assert.match(meGate, /all 25 roles have an explicit Me restoration policy/);
  assert.match(meGate, /@SceneStorage/);
  assert.match(meGate, /eusoRestoreScrollPosition/);
});
