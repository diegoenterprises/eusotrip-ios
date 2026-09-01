#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = relative => fs.readFileSync(path.join(root, relative), "utf8");
const fail = message => { throw new Error(message); };
const requireText = (source, needle, label) => {
  if (!source.includes(needle)) fail(`${label}: missing ${needle}`);
};
const forbidText = (source, needle, label) => {
  if (source.includes(needle)) fail(`${label}: forbidden ${needle}`);
};

const expectedThemeIds = [
  "aurora-classic", "synthwave-sunset", "midnight-desert", "bluemagenta",
  "frosted-glass", "flame-monolith", "neon-grid", "aurora-ribbon", "hazmat",
  "carbon-tech", "emerald-trail", "chrome-tanker", "boarding-stub", "orb-hero",
  "mono-minimal",
];
const scales = [
  { scale: "1x", suffix: "", multiplier: 1 },
  { scale: "2x", suffix: "@2x", multiplier: 2 },
  { scale: "3x", suffix: "@3x", multiplier: 3 },
];

function pngDimensions(bytes, label) {
  const signature = "89504e470d0a1a0a";
  if (bytes.length < 24 || bytes.subarray(0, 8).toString("hex") !== signature) {
    fail(`${label}: not a PNG`);
  }
  return [bytes.readUInt32BE(16), bytes.readUInt32BE(20)];
}

function verifyImageSet(assetRoot, setName, baseName, width, height) {
  const setRoot = path.join(assetRoot, `${setName}.imageset`);
  const contentsPath = path.join(setRoot, "Contents.json");
  if (!fs.existsSync(contentsPath)) fail(`${setName}: missing Contents.json`);
  const contents = JSON.parse(fs.readFileSync(contentsPath, "utf8"));
  if (!Array.isArray(contents.images) || contents.images.length !== 3) {
    fail(`${setName}: expected exactly three image scales`);
  }

  return scales.map(({ scale, suffix, multiplier }) => {
    const filename = `${baseName}${suffix}.png`;
    const row = contents.images.find(image => image.scale === scale);
    if (!row || row.idiom !== "universal" || row.filename !== filename) {
      fail(`${setName}: ${scale} does not reference ${filename}`);
    }
    const filePath = path.join(setRoot, filename);
    if (!fs.existsSync(filePath)) fail(`${setName}: missing ${filename}`);
    const bytes = fs.readFileSync(filePath);
    const [actualWidth, actualHeight] = pngDimensions(bytes, `${setName}/${filename}`);
    if (actualWidth !== width * multiplier || actualHeight !== height * multiplier) {
      fail(`${setName}/${filename}: expected ${width * multiplier}x${height * multiplier}, got ${actualWidth}x${actualHeight}`);
    }
    return crypto.createHash("sha256").update(bytes).digest("hex");
  });
}

const store = read("EusoTrip/Features/Wallet/WalletCardStore.swift");
const picker = read("EusoTrip/Features/Wallet/WalletCardPickerView.swift");
const service = read("EusoTrip/Services/EusoWalletPassService.swift");
const themes = read("EusoTrip/Features/Wallet/WalletCardTheme.swift");
const walletAPI = read("EusoTrip/Features/Wallet/EusoTripAPI+Wallet.swift");
const accessAPI = read("EusoTrip/Features/Wallet/EusoTripAPI+Access.swift");
const bolPass = read("EusoTrip/Views/Shipper/309_WalletPass.swift");
const assetRoot = path.join(
  root,
  "EusoTrip/Features/Wallet/WalletCardBackgrounds.xcassets",
);

const fallbackIds = [...themes.matchAll(/\.init\(id:\s*"([^"]+)"/g)].map(match => match[1]);
if (JSON.stringify(fallbackIds) !== JSON.stringify(expectedThemeIds)) {
  fail(`WalletCardTheme: expected exact 15-design catalog, got ${fallbackIds.join(", ")}`);
}
if (new Set(fallbackIds).size !== expectedThemeIds.length) {
  fail("WalletCardTheme: duplicate design id");
}

const imageSets = fs.readdirSync(assetRoot).filter(name => name.endsWith(".imageset"));
const sourceSets = imageSets.filter(name => !name.startsWith("wallet-strip-"));
const stripSets = imageSets.filter(name => name.startsWith("wallet-strip-"));
if (sourceSets.length !== 15 || stripSets.length !== 15) {
  fail(`Wallet assets: expected 15 source + 15 strip sets, got ${sourceSets.length} + ${stripSets.length}`);
}

for (const id of expectedThemeIds) {
  verifyImageSet(assetRoot, id, id, 180, 220);
  const stripHashes = verifyImageSet(
    assetRoot,
    `wallet-strip-${id}`,
    `wallet-strip-${id}`,
    375,
    123,
  );
  requireText(
    themes,
    `"${id}": ["${stripHashes.join('\", \"')}"]`,
    `WalletPassArtworkCatalog ${id}`,
  );
}

for (const needle of [
  'self.artSlot = artSlot ?? (kind == "solid" ? nil : "strip")',
  'UIImage(named: "wallet-strip-\\(id)")',
  'return passStyle == "eventTicket"',
  'normalizedArtSlot == "strip"',
  "expectedPassArtworkSHA256?.count == 3",
  "static let sha256ByTheme",
]) requireText(themes, needle, "WalletCardTheme");

for (const needle of [
  "themeRevision: revision",
  "cred.signedTheme",
  "expectedVisualTheme: chosenTheme",
  "expectedManifestDigest: manifestDigest",
  "expectedPassTypeIdentifier: passTypeIdentifier",
  "expectedSerialNumber: serialNumber",
  "signedPassAvailable(",
  "EusoWalletPassService.shared.addPass",
  '"qrPayload": cred.accessToken',
]) requireText(store, needle, "WalletCardStore");

for (const needle of [
  "theme.previewImage", "theme.logoImage", "375.0 / 220.0",
  'case "strip":',
  ".eusoFallbackToInlineQR",
  ".eusoAccessFallbackToInlineQR",
  "WalletInlineFallbackView",
  "EusoQRView(",
])
  requireText(picker, needle, "WalletCardPickerView");
forbidText(picker, "signing isn't enabled", "WalletCardPickerView");

for (const needle of [
  "func preparePickupCredential(",
  "themeId: selection.id",
  "themeRevision: selection.revision",
  "The credential service substituted a different Wallet design",
  "expectedTheme:",
  "expectedVisualTheme:",
  "expectedManifestDigest:",
  'pass.userInfo?["walletThemeId"]',
  'pass.userInfo?["walletThemeRevision"]',
  'pass.userInfo?["walletThemeDigest"]',
  'pass.userInfo?["walletThemeManifestVersion"]',
  'pass.userInfo?["walletThemePassStyle"]',
  'pass.userInfo?["walletThemeArtSlot"]',
  "fetchBoundedWalletPassData(url)",
  "hasAuthenticatedUpdateChannel(pkpass)",
  "expectedPassTypeIdentifier:",
  "expectedSerialNumber:",
  "pkpass.passTypeIdentifier == expectedPassType",
  "pkpass.serialNumber == expectedSerial",
  "WalletPassBundleVerifier.verify(",
  "digest(expectedManifestDigest, matches: manifestData)",
  "try verifyManifest(manifestData, archive: archive)",
  'canonicalColor(string(pass["backgroundColor"]))',
  "credentialKind.requiredFieldKeys(passStyle: expectedTheme.passStyle)",
  '? ["origin", "destination"]',
  ': ["lane"]',
  'string(fields["transitType"]) == "PKTransitTypeGeneric"',
  'case (.pickup, "eventTicket"), (.staffAccess, "eventTicket"):',
  "hasQRBarcode(pass)",
  "expectedVisualTheme.expectedPassArtworkSHA256",
  "sha256Hex(art) == expectedHashes[index]",
  "library.replacePass(with: pkpass)",
]) requireText(service, needle, "EusoWalletPassService");
forbidText(service, "try? await currentThemeSelection()", "EusoWalletPassService");
forbidText(service, "trimmed.filter(\\.isNumber)", "EusoWalletPassService");
requireText(service, 'for prefix in ["ld-", "load_", "load-"]', "EusoWalletPassService");
requireText(service, "suffix.allSatisfy(\\.isNumber)", "EusoWalletPassService");
requireText(store, "EusoWalletPassService.numericLoadId(from: loadId)", "WalletCardStore");
forbidText(store, "private static func numericLoadId", "WalletCardStore");

const bundleVerification = service.indexOf("try WalletPassBundleVerifier.verify(");
const passKitParsing = service.indexOf("pkpass = try PKPass(data: data)", bundleVerification);
const nativeAddSheet = service.indexOf("PKAddPassesViewController(pass: pkpass)", passKitParsing);
if (!(bundleVerification >= 0 && passKitParsing > bundleVerification && nativeAddSheet > passKitParsing)) {
  fail("EusoWalletPassService: visual bundle verification must precede PassKit parsing and presentation");
}

for (const [source, label] of [
  [walletAPI, "PickupCredential"],
  [accessAPI, "StaffAccessCredential"],
]) {
  requireText(source, "let passTypeIdentifier: String?", label);
  requireText(source, "let passSerialNumber: String?", label);
}

for (const needle of [
  "func fetchBoundedWalletPassData(_ url: URL",
  'request.setValue("application/vnd.apple.pkpass", forHTTPHeaderField: "Accept")',
  'http.mimeType?.lowercased() == "application/vnd.apple.pkpass"',
  "WalletPassNoRedirectDelegate",
  "completionHandler(nil)",
  "for try await byte in stream",
  "guard data.count < maxBytes",
  "if isFirstParty, let authToken",
  "request.httpShouldHandleCookies = false",
]) requireText(walletAPI, needle, "EusoTripAPI Wallet transport");

forbidText(service, "fetchAuthenticatedData(url)", "EusoWalletPassService");
forbidText(service, "fetchWalletPassData(url)", "EusoWalletPassService");

requireText(bolPass, "preparePickupCredential", "WalletPassScreen");
requireText(bolPass, "expectedTheme: pass.theme", "WalletPassScreen");
requireText(bolPass, "expectedVisualTheme: pass.visualTheme", "WalletPassScreen");
requireText(bolPass, "expectedManifestDigest: pass.manifestDigest", "WalletPassScreen");
requireText(bolPass, "expectedPassTypeIdentifier: pass.passTypeIdentifier", "WalletPassScreen");
requireText(bolPass, "expectedSerialNumber: pass.serialNumber", "WalletPassScreen");
requireText(bolPass, "fallbackQRPayload = credential.accessToken", "WalletPassScreen");
forbidText(bolPass, "EusoTripAPI.shared.createPickupCredential", "WalletPassScreen");
forbidText(bolPass, "documents.signWalletPass", "WalletPassScreen");
forbidText(bolPass, "not on this deploy", "WalletPassScreen");

console.log(JSON.stringify({
  verified: true,
  themes: expectedThemeIds.length,
  artworkFiles: 90,
  contracts: [
    "exact theme id and revision request",
    "15 preserved design ids",
    "45 source backgrounds and 45 PassKit strips",
    "per-scale signed artwork hashes",
    "signed bundle identity",
    "pass.json colors, style, fields, and QR",
    "signer-returned pass type and serial",
    "authenticated update channel",
    "bounded HTTPS Pass MIME transport",
    "installed-pass replacement",
    "honest credential fallback",
  ],
}, null, 2));
