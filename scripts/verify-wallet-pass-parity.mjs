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
const bolPass = read("EusoTrip/Views/Shipper/309_WalletPass.swift");

for (const needle of [
  "themeRevision: revision",
  'pass.userInfo["walletThemeDigest"]',
  'pass.userInfo["walletThemeManifestVersion"]',
  'pass.userInfo["walletThemePassStyle"]',
  "library.replacePass(with: pass)",
]) requireText(store, needle, "WalletCardStore");

for (const needle of ["theme.previewImage", "theme.logoImage", "375.0 / 220.0"])
  requireText(picker, needle, "WalletCardPickerView");
forbidText(picker, "signing isn't enabled", "WalletCardPickerView");

for (const needle of [
  "expectedTheme:",
  'pkpass.userInfo["walletThemeDigest"]',
  'pkpass.userInfo["walletThemeManifestVersion"]',
  "library.replacePass(with: pkpass)",
]) requireText(service, needle, "EusoWalletPassService");

requireText(bolPass, "createPickupCredential", "WalletPassScreen");
requireText(bolPass, "expectedTheme: pass.theme", "WalletPassScreen");
forbidText(bolPass, "documents.signWalletPass", "WalletPassScreen");
forbidText(bolPass, "not on this deploy", "WalletPassScreen");

console.log(JSON.stringify({
  verified: true,
  contracts: [
    "canonical theme revision",
    "canonical preview bytes",
    "signed bundle identity",
    "installed-pass replacement",
    "honest credential fallback",
  ],
}, null, 2));
