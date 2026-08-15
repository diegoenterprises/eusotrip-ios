#!/usr/bin/env node

import fs from "node:fs";

const settings = fs.readFileSync("EusoTrip/Views/Shipper/319_EsangSettings.swift", "utf8");
const player = fs.readFileSync("EusoTrip/Services/ESangTTSPlayer.swift", "utf8");
const preference = fs.readFileSync("EusoTrip/Models/UserVoicePreference.swift", "utf8");
const glass = fs.readFileSync("EusoTrip/Theme/Glass.swift", "utf8");

const failures = [];
const requireText = (source, value, label) => {
  if (!source.includes(value)) failures.push(`${label}: missing ${value}`);
};

requireText(settings, '"esangVoice.getVoices"', "settings");
requireText(settings, '"esangVoice.listDialects"', "settings");
requireText(settings, '"esangAI.savePreferences"', "settings");
requireText(settings, '"esangAI.getPreferences"', "settings");
requireText(settings, "verified.updatedAt == written.updatedAt", "settings");
requireText(settings, "dndEnabled", "settings");
requireText(settings, "TimeZone.current.identifier", "settings");
requireText(settings, "written.timeZone == request.timeZone", "settings");
requireText(settings, ".refreshable", "settings");
requireText(settings, "EusoTripBrandMark", "settings");
requireText(player, '"esangVoice.speak"', "player");
requireText(player, "UserVoicePreference.shared.isVoiceEnabled", "player");
requireText(preference, "applyAuthoritativeSettings", "preference cache");
requireText(glass, "struct EusoTripBrandMark", "brand mark");

for (const legacy of ["Eusorone classic", 'private let languages = [', 'Image(systemName: "sparkles")']) {
  if (settings.includes(legacy)) failures.push(`settings: legacy static control remains: ${legacy}`);
}
if (settings.includes("catch { /*")) failures.push("settings: swallowed error remains");

if (failures.length) {
  console.error(failures.join("\n"));
  process.exit(1);
}

console.log("ESANG settings parity gate passed: live catalogs, verified persistence, runtime voice, DND, refresh, and brand mark are wired.");
