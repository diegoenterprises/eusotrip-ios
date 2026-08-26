#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const servicePath = path.join(root, "EusoTrip/Services/EusoWalletPassService.swift");
const service = fs.readFileSync(servicePath, "utf8");
const verifierStart = service.indexOf("private enum WalletPassBundleError");
const verifierEnd = service.indexOf("private enum WalletPassSelectionError");
if (verifierStart < 0 || verifierEnd <= verifierStart) {
  throw new Error("Could not locate the Wallet pass bundle verifier in EusoWalletPassService.swift");
}
const verifierSource = service.slice(verifierStart, verifierEnd);

const crcTable = Array.from({ length: 256 }, (_, value) => {
  let current = value;
  for (let bit = 0; bit < 8; bit += 1) {
    current = (current & 1) ? (0xedb88320 ^ (current >>> 1)) : (current >>> 1);
  }
  return current >>> 0;
});

function crc32(bytes) {
  let value = 0xffffffff;
  for (const byte of bytes) value = crcTable[(value ^ byte) & 0xff] ^ (value >>> 8);
  return (value ^ 0xffffffff) >>> 0;
}

function zip(entries) {
  const localParts = [];
  const centralParts = [];
  let localOffset = 0;

  for (const [name, raw] of entries) {
    const nameBytes = Buffer.from(name, "utf8");
    const compressed = zlib.deflateRawSync(raw);
    const checksum = crc32(raw);

    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0, 6);
    local.writeUInt16LE(8, 8);
    local.writeUInt32LE(checksum, 14);
    local.writeUInt32LE(compressed.length, 18);
    local.writeUInt32LE(raw.length, 22);
    local.writeUInt16LE(nameBytes.length, 26);
    local.writeUInt16LE(0, 28);
    localParts.push(local, nameBytes, compressed);

    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0, 8);
    central.writeUInt16LE(8, 10);
    central.writeUInt32LE(checksum, 16);
    central.writeUInt32LE(compressed.length, 20);
    central.writeUInt32LE(raw.length, 24);
    central.writeUInt16LE(nameBytes.length, 28);
    central.writeUInt16LE(0, 30);
    central.writeUInt16LE(0, 32);
    central.writeUInt16LE(0, 34);
    central.writeUInt16LE(0, 36);
    central.writeUInt32LE(0, 38);
    central.writeUInt32LE(localOffset, 42);
    centralParts.push(central, nameBytes);

    localOffset += local.length + nameBytes.length + compressed.length;
  }

  const centralDirectory = Buffer.concat(centralParts);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(0, 4);
  eocd.writeUInt16LE(0, 6);
  eocd.writeUInt16LE(entries.length, 8);
  eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(centralDirectory.length, 12);
  eocd.writeUInt32LE(localOffset, 16);
  eocd.writeUInt16LE(0, 20);
  return Buffer.concat([...localParts, centralDirectory, eocd]);
}

const pngSignature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const canonicalArt = Buffer.concat([pngSignature, Buffer.alloc(136, 0x41)]);
const art2x = Buffer.concat([pngSignature, Buffer.alloc(180, 0x42)]);
const art3x = Buffer.concat([pngSignature, Buffer.alloc(220, 0x43)]);

function makeCase({
  background = "rgb(10,10,15)",
  qr = true,
  art = canonicalArt,
  style = "eventTicket",
  splitArtLane = false,
  includeTransit = style === "boardingPass",
} = {}) {
  const isSolid = style === "boardingPass";
  const themeId = isSolid ? "aurora-classic" : "aurora-ribbon";
  const artSlot = isSolid ? null : "strip";
  const primaryFields = isSolid || splitArtLane
    ? [{ key: "origin", value: "Austin" }, { key: "destination", value: "Houston" }]
    : [{ key: "lane", value: "Austin -> Houston" }];
  const passFields = {
    headerFields: [{ key: "loadId", value: "LD-9001" }],
    primaryFields,
    secondaryFields: [{ key: "eta", value: "2026-08-20T18:00:00Z" }, { key: "shortCode", value: "12345" }],
    auxiliaryFields: [{ key: "equipment", value: "TANKER" }, { key: "carrier", value: "Carrier" }],
    backFields: [{ key: "escrow", value: "Funded" }, { key: "token", value: "token" }, { key: "support", value: "support" }],
    ...(includeTransit ? { transitType: "PKTransitTypeGeneric" } : {}),
  };
  const pass = {
    formatVersion: 1,
    passTypeIdentifier: "pass.com.app.eusotrip.pickup",
    teamIdentifier: "TEAM123456",
    organizationName: "Eusorone Technologies, Inc.",
    serialNumber: "LD-9001",
    backgroundColor: background,
    foregroundColor: "rgb(255,255,255)",
    labelColor: "rgb(205,188,255)",
    userInfo: {
      walletThemeId: themeId,
      walletThemeRevision: "rev-7",
      walletThemeDigest: "theme-digest-7",
      walletThemeManifestVersion: "wallet-theme-v1",
      walletThemePassStyle: style,
      walletThemeArtSlot: artSlot,
    },
    [style]: passFields,
    ...(qr ? { barcodes: [{ format: "PKBarcodeFormatQR", message: "live-server-token" }] } : {}),
  };

  const signedFiles = new Map([
    ["pass.json", Buffer.from(JSON.stringify(pass))],
    ["icon.png", Buffer.from("icon")],
  ]);
  if (!isSolid) {
    signedFiles.set("strip.png", art);
    signedFiles.set("strip@2x.png", art2x);
    signedFiles.set("strip@3x.png", art3x);
  }
  const manifest = Object.fromEntries(
    [...signedFiles].map(([name, bytes]) => [name, crypto.createHash("sha1").update(bytes).digest("hex")]),
  );
  const manifestBytes = Buffer.from(JSON.stringify(manifest));
  const bundle = zip([
    ...signedFiles,
    ["manifest.json", manifestBytes],
    ["signature", Buffer.from("test-signature")],
  ]);
  return {
    bundle: bundle.toString("base64"),
    digest: crypto.createHash("sha256").update(manifestBytes).digest("hex"),
  };
}

const fixtures = {
  expectedArtworkSHA256: [canonicalArt, art2x, art3x]
    .map(bytes => crypto.createHash("sha256").update(bytes).digest("hex")),
  valid: makeCase(),
  solidValid: makeCase({
    background: "rgb(20,115,255)",
    style: "boardingPass",
  }),
  wrongColor: makeCase({ background: "rgb(20,115,255)" }),
  wrongArt: makeCase({ art: Buffer.concat([pngSignature, Buffer.alloc(136, 0x7f)]) }),
  missingQR: makeCase({ qr: false }),
  splitArtLane: makeCase({ splitArtLane: true }),
  solidMissingTransit: makeCase({
    background: "rgb(20,115,255)",
    style: "boardingPass",
    includeTransit: false,
  }),
};

const swiftHarness = `
import Foundation
import CryptoKit
import zlib

struct WalletCardTheme {
    let id: String
    let revision: String?
    let digest: String?
    let manifestVersion: String?
    let passStyle: String
    let artSlot: String?
    let background: String
    let foreground: String
    let label: String
    let expectedPassArtworkSHA256: [String]?
    var normalizedArtSlot: String? {
        let value = artSlot?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return value.isEmpty ? nil : value
    }
}

enum EusoTripAPI {
    struct WalletThemeMetadata {
        let id: String
        let revision: String
        let digest: String
        let manifestVersion: String
        let passStyle: String
        let artSlot: String?
    }
}

enum EusoWalletCredentialKind {
    case pickup
    case staffAccess
    func requiredFieldKeys(passStyle: String) -> Set<String> {
        switch self {
        case .pickup:
            let laneKeys: Set<String> = passStyle == "boardingPass"
                ? ["origin", "destination"]
                : ["lane"]
            return Set(["loadId", "eta", "shortCode", "equipment", "carrier", "escrow", "token", "support"]).union(laneKeys)
        case .staffAccess:
            return ["role", "staff", "facility", "accessCode", "expires", "token", "support"]
        }
    }
}

${verifierSource}

struct FixtureCase: Decodable { let bundle: String; let digest: String }
struct Fixtures: Decodable {
    let expectedArtworkSHA256: [String]
    let valid: FixtureCase
    let solidValid: FixtureCase
    let wrongColor: FixtureCase
    let wrongArt: FixtureCase
    let missingQR: FixtureCase
    let splitArtLane: FixtureCase
    let solidMissingTransit: FixtureCase
}

func bytes(_ value: String) -> Data { Data(base64Encoded: value)! }
private func errorName(_ error: WalletPassBundleError) -> String {
    switch error {
    case .malformedPackage: return "malformed"
    case .manifestMismatch: return "manifest"
    case .visualMismatch: return "visual"
    }
}

let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
let fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: fixtureURL))
let metadata = EusoTripAPI.WalletThemeMetadata(
    id: "aurora-ribbon", revision: "rev-7", digest: "theme-digest-7",
    manifestVersion: "wallet-theme-v1", passStyle: "eventTicket", artSlot: "strip"
)
let visual = WalletCardTheme(
    id: "aurora-ribbon", revision: "rev-7", digest: "theme-digest-7",
    manifestVersion: "wallet-theme-v1", passStyle: "eventTicket", artSlot: "strip",
    background: "rgb(10,10,15)", foreground: "rgb(255,255,255)",
    label: "rgb(205,188,255)", expectedPassArtworkSHA256: fixtures.expectedArtworkSHA256
)

func verifyArt(_ value: FixtureCase, digest: String? = nil) throws {
    try WalletPassBundleVerifier.verify(
        bytes(value.bundle), expectedTheme: metadata, expectedVisualTheme: visual,
        expectedManifestDigest: digest ?? value.digest,
        expectedPassTypeIdentifier: "pass.com.app.eusotrip.pickup",
        expectedSerialNumber: "LD-9001", credentialKind: .pickup
    )
}

let solidMetadata = EusoTripAPI.WalletThemeMetadata(
    id: "aurora-classic", revision: "rev-7", digest: "theme-digest-7",
    manifestVersion: "wallet-theme-v1", passStyle: "boardingPass", artSlot: nil
)
let solidVisual = WalletCardTheme(
    id: "aurora-classic", revision: "rev-7", digest: "theme-digest-7",
    manifestVersion: "wallet-theme-v1", passStyle: "boardingPass", artSlot: nil,
    background: "rgb(20,115,255)", foreground: "rgb(255,255,255)",
    label: "rgb(205,188,255)", expectedPassArtworkSHA256: nil
)
func verifySolid(_ value: FixtureCase) throws {
    try WalletPassBundleVerifier.verify(
        bytes(value.bundle), expectedTheme: solidMetadata, expectedVisualTheme: solidVisual,
        expectedManifestDigest: value.digest,
        expectedPassTypeIdentifier: "pass.com.app.eusotrip.pickup",
        expectedSerialNumber: "LD-9001", credentialKind: .pickup
    )
}

try verifyArt(fixtures.valid)
try verifySolid(fixtures.solidValid)
for (name, value, expected) in [
    ("wrongColor", fixtures.wrongColor, "visual"),
    ("wrongArt", fixtures.wrongArt, "visual"),
    ("missingQR", fixtures.missingQR, "visual"),
    ("splitArtLane", fixtures.splitArtLane, "visual"),
] {
    do {
        try verifyArt(value)
        fatalError("\\(name) unexpectedly passed")
    } catch let error as WalletPassBundleError {
        guard errorName(error) == expected else { fatalError("\\(name) failed as \\(errorName(error))") }
    }
}
do {
    try verifySolid(fixtures.solidMissingTransit)
    fatalError("solidMissingTransit unexpectedly passed")
} catch let error as WalletPassBundleError {
    guard errorName(error) == "visual" else { fatalError("solidMissingTransit failed as \\(errorName(error))") }
}
do {
    try verifyArt(fixtures.valid, digest: String(repeating: "0", count: 64))
    fatalError("wrongDigest unexpectedly passed")
} catch let error as WalletPassBundleError {
    guard errorName(error) == "manifest" else { fatalError("wrongDigest failed as \\(errorName(error))") }
}
print("wallet pass bundle verifier: 8/8 contract cases passed")
`;

const temp = fs.mkdtempSync(path.join(os.tmpdir(), "eusotrip-wallet-pass-"));
const swiftPath = path.join(temp, "WalletPassBundleVerifierTests.swift");
const fixturesPath = path.join(temp, "fixtures.json");
try {
  fs.writeFileSync(swiftPath, swiftHarness);
  fs.writeFileSync(fixturesPath, JSON.stringify(fixtures));
  const result = spawnSync("xcrun", ["swift", swiftPath, fixturesPath], {
    cwd: root,
    encoding: "utf8",
    maxBuffer: 10 * 1024 * 1024,
  });
  if (result.status !== 0) {
    process.stderr.write(result.stdout || "");
    process.stderr.write(result.stderr || "");
    process.exit(result.status ?? 1);
  }
  process.stdout.write(result.stdout);
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
