#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

export function selectAvailableIOSSimulator(inventory) {
  const candidates = [];
  for (const [runtime, devices] of Object.entries(inventory.devices ?? {})) {
    const version = runtime.match(/\.iOS-(\d+)(?:-(\d+))?(?:-(\d+))?$/);
    if (!version || !Array.isArray(devices)) continue;
    for (const device of devices) {
      if (
        !device ||
        device.isAvailable === false ||
        typeof device.udid !== "string" ||
        typeof device.name !== "string" ||
        !/^iPhone\b/.test(device.name)
      ) {
        continue;
      }
      candidates.push({
        device,
        version: version.slice(1).map(value => Number(value ?? 0)),
      });
    }
  }

  candidates.sort((left, right) => {
    const bootDifference = Number(right.device.state === "Booted") -
      Number(left.device.state === "Booted");
    if (bootDifference !== 0) return bootDifference;
    for (let index = 0; index < 3; index += 1) {
      const difference = right.version[index] - left.version[index];
      if (difference !== 0) return difference;
    }
    return left.device.name.localeCompare(right.device.name);
  });

  if (candidates.length === 0) {
    throw new Error("No available iPhone Simulator is installed for offline tests.");
  }
  return `platform=iOS Simulator,id=${candidates[0].device.udid}`;
}

const isMain = process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  try {
    process.stdout.write(
      selectAvailableIOSSimulator(JSON.parse(fs.readFileSync(0, "utf8")))
    );
  } catch (error) {
    console.error(
      error instanceof SyntaxError
        ? "Unable to parse the available Simulator inventory."
        : error.message
    );
    process.exit(1);
  }
}
