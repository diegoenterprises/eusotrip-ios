import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const source = fs.readFileSync(
  path.join(root, "EusoTrip/Views/Shipper/204_ShipperPostLoad.swift"),
  "utf8",
);
const crashPath = process.env.ASC_BUILD_850_CRASH;
const expectedCrashSha256 =
  "e379c7d27569b9ca3ad1a506ed7f0ad09f85bd830536f1c17e775f0350be90cf";

function section(start, end) {
  const startIndex = source.indexOf(start);
  assert.notEqual(startIndex, -1, `missing ${start}`);
  const endIndex = source.indexOf(end, startIndex + start.length);
  assert.notEqual(endIndex, -1, `missing ${end}`);
  return source.slice(startIndex, endIndex);
}

const stepSwitch = section(
  "private var stepBody: AnyView",
  "// MARK: - Step 1: LANE",
);
const equipmentStep = section(
  "private var equipmentStepBody: AnyView",
  "private var overweightComplianceCard",
);
const subform = section(
  "private var equipmentSubform: AnyView",
  "private var equipmentSpecificSubform: AnyView",
);
const equipmentSpecificSubform = section(
  "private var equipmentSpecificSubform: AnyView",
  "private var equipmentCargoIdentityCard: AnyView",
);
const equipmentCargoIdentityCard = section(
  "private var equipmentCargoIdentityCard: AnyView",
  "private var cargoClassificationCard",
);

assert.match(stepSwitch, /case \.lane:\s+return AnyView\(laneStepBody\)/);
assert.match(stepSwitch, /case \.equipment:\s+return equipmentStepBody/);
assert.match(stepSwitch, /case \.pricing:\s+return AnyView\(pricingStepBody\)/);
assert.match(stepSwitch, /case \.review:\s+return AnyView\(reviewStepBody\)/);
assert.doesNotMatch(stepSwitch, /@ViewBuilder\s+private var stepBody/);

assert.match(equipmentStep, /AnyView\(VStack/);
assert.match(equipmentStep, /AnyView\(cargoTypePicker\)/);
assert.match(equipmentStep, /AnyView\(equipmentTypePicker\)/);
assert.match(equipmentStep, /AnyView\(weightField\)/);
assert.match(equipmentStep, /AnyView\(equipmentPreviewSection\)/);
assert.match(equipmentStep, /^\s*equipmentSubform\s*$/m);
assert.match(equipmentStep, /AnyView\(hazmatComplianceCard\)/);
assert.match(equipmentStep, /AnyView\(overweightComplianceCard\)/);
assert.doesNotMatch(equipmentStep, /@ViewBuilder\s+private var equipmentStepBody/);

assert.match(subform, /AnyView\(VStack/);
assert.match(subform, /AnyView\(equipmentAnimation\)/);
assert.match(subform, /AnyView\(catalogRequirementsSection\)/);
assert.match(subform, /^\s*equipmentSpecificSubform\s*$/m);
assert.match(subform, /^\s*equipmentCargoIdentityCard\s*$/m);
assert.match(subform, /AnyView\(cargoClassificationCard\)/);
assert.doesNotMatch(subform, /@ViewBuilder\s+private var equipmentSubform/);

assert.match(equipmentSpecificSubform, /return AnyView\(reeferSubform\)/);
assert.match(equipmentSpecificSubform, /return AnyView\(EmptyView\(\)\)/);
assert.doesNotMatch(
  equipmentSpecificSubform,
  /@ViewBuilder\s+private var equipmentSpecificSubform/,
);

assert.match(equipmentCargoIdentityCard, /return AnyView\(dangerousGoodsCard\)/);
assert.match(equipmentCargoIdentityCard, /return AnyView\(commodityLookupCard\)/);
assert.doesNotMatch(
  equipmentCargoIdentityCard,
  /@ViewBuilder\s+private var equipmentCargoIdentityCard/,
);

let crashSha256 = null;
if (crashPath) {
  const crashBytes = fs.readFileSync(crashPath);
  crashSha256 = crypto.createHash("sha256").update(crashBytes).digest("hex");
  assert.equal(
    crashSha256,
    expectedCrashSha256,
    "ASC_BUILD_850_CRASH is not the canonical build-850 Post-a-Load crash artifact",
  );
  const crash = crashBytes.toString("utf8");
  const orderedStackMarkers = [
    "__swift_instantiateConcreteTypeFromMangledNameV2",
    "ShipperPostLoad.equipmentSubform.getter",
    "closure #1 in ShipperPostLoad.equipmentStepBody.getter",
    "ShipperPostLoad.stepBody.getter",
  ];
  let previousIndex = -1;
  for (const marker of orderedStackMarkers) {
    const markerIndex = crash.indexOf(marker, previousIndex + 1);
    assert.ok(markerIndex > previousIndex, `missing or out-of-order crash frame: ${marker}`);
    previousIndex = markerIndex;
  }
  for (const marker of [
    "Version:             1.0 (850)",
    "Exception Type:  EXC_BAD_ACCESS (SIGSEGV)",
    "STACK GUARD",
    "204_ShipperPostLoad.swift:4086",
  ]) {
    assert.match(crash, new RegExp(marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  }
}

console.log(JSON.stringify({
  verified: true,
  boundaries: [
    "stepBody",
    "equipmentStepBody",
    "equipmentSubform",
    "equipmentSpecificSubform",
    "equipmentCargoIdentityCard",
  ],
  crashEvidenceValidated: Boolean(crashPath),
  crashSha256,
}, null, 2));
