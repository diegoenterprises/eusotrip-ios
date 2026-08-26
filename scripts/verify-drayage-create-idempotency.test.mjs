import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

const root = process.cwd();
const source = fs.readFileSync(
  path.join(root, "EusoTrip/Views/Vessel/737_VesselDrayageOrders.swift"),
  "utf8"
);

test("native drayage creation keeps one request identity across an uncertain retry", () => {
  assert.match(
    source,
    /@State private var draftIdempotencyKey = UUID\(\)\.uuidString/
  );
  assert.match(source, /idempotencyKey: draftIdempotencyKey/);
  assert.match(
    source,
    /private func resetDraft\(\)[\s\S]*draftIdempotencyKey = UUID\(\)\.uuidString/
  );
  assert.doesNotMatch(source, /catch[\s\S]{0,240}draftIdempotencyKey = UUID/);
});

test("opening a fresh composer gets a fresh identity while a failed submit preserves it", () => {
  assert.match(
    source,
    /title: busyAction == "create" \? "Creating\.\.\." : "New drayage order"[\s\S]{0,180}resetDraft\(\)[\s\S]{0,80}showNewOrder = true/
  );
  assert.match(
    source,
    /actionBanner = "Created[\s\S]{0,240}resetDraft\(\)[\s\S]{0,120}catch/
  );
});

test("the encoded request contract includes the server idempotency field", () => {
  const inputStart = source.indexOf("private struct DrayCreateInput737: Encodable");
  assert.notEqual(inputStart, -1);
  const input = source.slice(inputStart, source.indexOf("}\n", inputStart) + 2);
  assert.match(input, /let idempotencyKey: String/);
});

