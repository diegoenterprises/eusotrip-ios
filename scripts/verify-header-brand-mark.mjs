#!/usr/bin/env node

import assert from "node:assert/strict";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const sourceRoot = resolve(root, "EusoTrip");
const glassPath = resolve(sourceRoot, "Theme/Glass.swift");

function swiftFiles(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = resolve(directory, entry.name);
    if (entry.isDirectory()) return swiftFiles(path);
    return entry.isFile() && entry.name.endsWith(".swift") ? [path] : [];
  });
}

const files = swiftFiles(sourceRoot);
assert(files.length > 0, "No Swift source files were found");

const glass = readFileSync(glassPath, "utf8");
assert.match(
  glass,
  /struct EusoTripBrandMark:[\s\S]*?Image\("EusoTripLogo"\)/,
  "The compact header mark must render the canonical EusoTripLogo asset",
);
assert.match(
  glass,
  /struct EusoTripEyebrow:[\s\S]*?EusoTripBrandMark\(\)/,
  "Shared eyebrow rows must include the canonical EusoTrip brand mark",
);

const roleIdentity = [
  "ADMIN", "BROKER", "CARRIER", "CATALYST", "COMPLIANCE", "CUSTOMS",
  "DISPATCH", "DISPATCHER", "DRIVER", "ESCORT", "FACTORING", "PORT",
  "RAIL", "SAFETY", "SHIP", "SHIPPER", "TERMINAL", "VESSEL",
].join("|");
const legacyRoleGlyph = new RegExp(
  `Text\\([^\\n]*[\"'](?:[^\"']*)?✦(?:[^\"']*)\\b(?:${roleIdentity})\\b`,
);
const standaloneLegacyGlyph = /Text\(\s*"✦"\s*\)/;
const violations = [];
let brandMarkUsages = 0;
let eyebrowUsages = 0;

for (const file of files) {
  assert(statSync(file).isFile());
  const source = readFileSync(file, "utf8");
  brandMarkUsages += source.match(/\bEusoTripBrandMark\b/g)?.length ?? 0;
  eyebrowUsages += source.match(/\bEusoTripEyebrow\b/g)?.length ?? 0;

  source.split("\n").forEach((line, index) => {
    const code = line.trimStart();
    if (code.startsWith("//")) return;
    if (legacyRoleGlyph.test(code) || standaloneLegacyGlyph.test(code)) {
      violations.push(`${file.slice(root.length + 1)}:${index + 1}: ${code.trim()}`);
    }
  });
}

assert.equal(
  violations.length,
  0,
  `Legacy decorative sparkle remains in a screen identity header:\n${violations.join("\n")}`,
);
assert(
  brandMarkUsages >= 200,
  `Expected app-wide EusoTrip header mark coverage; found only ${brandMarkUsages} usages`,
);
assert(
  eyebrowUsages >= 150,
  `Expected shared branded eyebrow coverage; found only ${eyebrowUsages} usages`,
);

console.log(JSON.stringify({
  swiftFiles: files.length,
  brandMarkUsages,
  eyebrowUsages,
  legacyRoleGlyphs: violations.length,
}, null, 2));
