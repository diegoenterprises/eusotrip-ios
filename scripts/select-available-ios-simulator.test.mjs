#!/usr/bin/env node

import assert from "node:assert/strict";
import { selectAvailableIOSSimulator } from "./select-available-ios-simulator.mjs";

const runtime = version => `com.apple.CoreSimulator.SimRuntime.iOS-${version.replaceAll(".", "-")}`;
const inventory = {
  devices: {
    [runtime("27.0")]: [
      { name: "iPhone Future", udid: "future", state: "Shutdown", isAvailable: true },
    ],
    [runtime("26.4")]: [
      { name: "iPhone Known Green", udid: "known-green", state: "Booted", isAvailable: true },
      { name: "Apple Watch", udid: "watch", state: "Booted", isAvailable: true },
    ],
  },
};

assert.equal(
  selectAvailableIOSSimulator(inventory),
  "platform=iOS Simulator,id=known-green"
);
console.log("ok - a booted compatible iPhone wins over a drifting newer runtime");

inventory.devices[runtime("26.4")][0].state = "Shutdown";
assert.equal(
  selectAvailableIOSSimulator(inventory),
  "platform=iOS Simulator,id=future"
);
console.log("ok - newest runtime wins when no iPhone is already booted");

inventory.devices[runtime("27.0")][0].isAvailable = false;
assert.equal(
  selectAvailableIOSSimulator(inventory),
  "platform=iOS Simulator,id=known-green"
);
console.log("ok - unavailable devices and non-iPhone products are ignored");

assert.throws(
  () => selectAvailableIOSSimulator({ devices: {} }),
  /No available iPhone Simulator/
);
console.log("ok - missing compatible runtime fails closed");

console.log("Simulator selector regression harness passed: 4 cases.");
