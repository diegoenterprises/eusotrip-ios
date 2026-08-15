#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = relative => fs.readFileSync(path.join(root, relative), "utf8");
const requireText = (source, needle, label) => {
  if (!source.includes(needle)) throw new Error(`${label}: missing ${needle}`);
};
const forbidText = (source, needle, label) => {
  if (source.includes(needle)) throw new Error(`${label}: forbidden ${needle}`);
};

const store = read("EusoTrip/Features/Wallet/WalletCardStore.swift");
const picker = read("EusoTrip/Features/Wallet/WalletCardPickerView.swift");
const service = read("EusoTrip/Services/EusoWalletPassService.swift");
const walletAPI = read("EusoTrip/Features/Wallet/EusoTripAPI+Wallet.swift");
const accessAPI = read("EusoTrip/Features/Wallet/EusoTripAPI+Access.swift");
const bolPass = read("EusoTrip/Views/Shipper/309_WalletPass.swift");

for (const needle of [
  "themeRevision: revision",
  "cred.signedTheme",
  "expectedPassTypeIdentifier: passTypeIdentifier",
  "expectedSerialNumber: serialNumber",
  "signedPassAvailable(",
  "EusoWalletPassService.shared.addPass",
]) requireText(store, needle, "WalletCardStore");

for (const needle of ["theme.previewImage", "theme.logoImage", "375.0 / 220.0"])
  requireText(picker, needle, "WalletCardPickerView");
forbidText(picker, "signing isn't enabled", "WalletCardPickerView");

for (const needle of [
  "expectedTheme:",
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
  "library.replacePass(with: pkpass)",
]) requireText(service, needle, "EusoWalletPassService");
forbidText(service, "try? await currentThemeSelection()", "EusoWalletPassService");
forbidText(service, "trimmed.filter(\\.isNumber)", "EusoWalletPassService");
requireText(service, 'for prefix in ["ld-", "load_", "load-"]', "EusoWalletPassService");
requireText(service, "suffix.allSatisfy(\\.isNumber)", "EusoWalletPassService");
requireText(store, "EusoWalletPassService.numericLoadId(from: loadId)", "WalletCardStore");
forbidText(store, "private static func numericLoadId", "WalletCardStore");

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

requireText(bolPass, "createPickupCredential", "WalletPassScreen");
requireText(bolPass, "expectedTheme: pass.theme", "WalletPassScreen");
requireText(bolPass, "expectedPassTypeIdentifier: pass.passTypeIdentifier", "WalletPassScreen");
requireText(bolPass, "expectedSerialNumber: pass.serialNumber", "WalletPassScreen");
forbidText(bolPass, "documents.signWalletPass", "WalletPassScreen");
forbidText(bolPass, "not on this deploy", "WalletPassScreen");

console.log(JSON.stringify({
  verified: true,
  contracts: [
    "canonical theme revision",
    "canonical preview bytes",
    "signed bundle identity",
    "signer-returned pass type and serial",
    "authenticated update channel",
    "bounded HTTPS Pass MIME transport",
    "installed-pass replacement",
    "honest credential fallback",
  ],
}, null, 2));
