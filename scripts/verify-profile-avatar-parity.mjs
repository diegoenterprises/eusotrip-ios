#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const root = process.cwd();
const read = (relative) => fs.readFileSync(path.join(root, relative), "utf8");
const failures = [];
const requireText = (relative, pattern, message) => {
  const source = read(relative);
  if (!pattern.test(source)) failures.push(`${relative}: ${message}`);
};
const forbidText = (relative, pattern, message) => {
  const source = read(relative);
  if (pattern.test(source)) failures.push(`${relative}: ${message}`);
};

const component = "EusoTrip/Views/Components/EditableProfileAvatar.swift";
requireText(component, /"profile\.updateAvatar"/, "must call the authenticated avatar mutation");
requireText(component, /let authoritative = try await fetchProfile\(\)/, "must read back the authoritative profile after upload");
requireText(component, /guard authoritative\.avatar == dataURL/, "must reject a mismatched persistence readback");
requireText(component, /let maximumBinaryBytes = 37_000/, "must remain below the server's 45 KB binary limit");
requireText(component, /url\.scheme == "https"/, "must reject non-HTTPS remote avatars");
requireText(component, /NotificationCenter\.default\.post\(name: \.eusoProfileUpdated/, "must notify other profile consumers after verified persistence");

for (const relative of [
  "EusoTrip/Views/Driver/067A_DriverMeHubs.swift",
  "EusoTrip/Views/Shipper/320_MeHome.swift",
  "EusoTrip/Views/Admin/804_AdminMe.swift",
  "EusoTrip/Views/Carrier/350_CarrierMe.swift",
  "EusoTrip/Views/Broker/404B_BrokerMe.swift",
  "EusoTrip/Views/Compliance/903_ComplianceMe.swift",
  "EusoTrip/Views/Dispatch/400_DispatcherHome.swift",
  "EusoTrip/Views/Dispatch/402_DispatcherProfile.swift",
  "EusoTrip/Views/Dispatch/Dpch713_DispatchMe.swift",
  "EusoTrip/Views/Escort/620_EscortMeHome.swift",
  "EusoTrip/Views/Rail/556_RailEngineerAccount.swift",
  "EusoTrip/Views/Terminal/703_TerminalMe.swift",
  "EusoTrip/Views/Vessel/656_VesselOperatorAccount.swift",
]) {
  requireText(relative, /EditableProfileAvatar\(size:/, "identity surface must use the shared editable avatar");
}

forbidText(
  "EusoTrip/Views/Driver/067A_DriverMeHubs.swift",
  /func uploadAvatar\(|PhotosPickerItem|200_000/,
  "must not retain the private 200 KB driver uploader",
);
forbidText(
  "EusoTrip/Views/Shipper/320_MeHome.swift",
  /eusoShipperAvatarPickRequested|func loadAvatar\(|avatarImage/,
  "must not delegate avatar state to the role router",
);
forbidText(
  "EusoTrip/Views/RoleSurfaceRouter.swift",
  /PhotosPickerItem|uploadShipperAvatar|avatarPickerOpen|avatarUploadError/,
  "must not own a second avatar implementation",
);

const project = read("EusoTrip.xcodeproj/project.pbxproj");
for (const marker of [
  "EditableProfileAvatar.swift in Sources",
  "path = EusoTrip/Views/Components/EditableProfileAvatar.swift",
]) {
  if (!project.includes(marker)) failures.push(`project.pbxproj: missing ${marker}`);
}

if (failures.length) {
  console.error(`profile avatar parity gate failed (${failures.length})`);
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log("profile avatar parity gate passed");
