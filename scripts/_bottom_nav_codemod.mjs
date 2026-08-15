import fs from "node:fs";
import path from "node:path";

const write = process.argv.includes("--write");
const viewsRoot = path.join(process.cwd(), "EusoTrip", "Views");

const configs = [
  {
    name: "Carrier",
    dirs: ["Carrier", "Catalyst"],
    route: "CarrierNavRoute",
    map: {
      home: "home", loads: "loads", dispatch: "loads", bids: "loads",
      "my loads": "loads", find: "loads", match: "loads", matches: "loads",
      drivers: "drivers", fleet: "drivers", network: "drivers",
      me: "me", wallet: "me",
    },
    leading: new Set(["home", "loads"]),
  },
  {
    name: "Broker",
    dirs: ["Broker"],
    route: "BrokerNavRoute",
    map: { home: "home", loads: "tenders", tenders: "tenders", carriers: "carriers", me: "me" },
    leading: new Set(["home", "tenders"]),
  },
  {
    name: "Escort",
    dirs: ["Escort"],
    route: "EscortNavRoute",
    map: {
      home: "home", assignments: "assignments", trip: "assignments", comms: "assignments",
      corridor: "corridor", permit: "corridor", me: "me",
    },
    leading: new Set(["home", "assignments"]),
  },
  {
    name: "Terminal",
    dirs: ["Terminal"],
    route: "TerminalNavRoute",
    map: { home: "home", movements: "movements", yard: "yard", me: "me" },
    leading: new Set(["home", "movements"]),
  },
  {
    name: "Admin",
    dirs: ["Admin"],
    route: "AdminNavRoute",
    map: { home: "home", tickets: "tickets", tower: "tickets", tenants: "tenants", me: "me" },
    leading: new Set(["home", "tickets"]),
  },
  {
    name: "Dispatch",
    dirs: ["Dispatch"],
    route: "DispatchNavRoute",
    map: {
      home: "home", board: "board", dispatch: "board", loads: "board", drivers: "board",
      comms: "comms", esang: "comms", me: "me",
    },
    leading: new Set(["home", "board"]),
  },
  {
    name: "Compliance",
    dirs: ["Compliance"],
    route: "ComplianceNavRoute",
    map: { home: "home", drivers: "drivers", docs: "drivers", audits: "audits", tiers: "me", me: "me" },
    leading: new Set(["home", "drivers"]),
  },
];

const excluded = new Set([
  "Catalyst/311_CatalystSettings.swift",
  "Dispatch/Dpch714_DispatchTrio.swift",
  "Dispatch/Dpch720_DispatcherSVGTrio.swift",
  "Dispatch/Dpch734_DispatcherControlQuartet.swift",
]);

const overrides = new Map([
  ["Carrier/320_CarrierVehiclesList.swift", "drivers"],
  ["Catalyst/303_CatalystFleetVehicles.swift", "drivers"],
  ["Catalyst/304_CatalystFleetDrivers.swift", "drivers"],
  ["Catalyst/314_CatalystMaintenanceZeun.swift", "drivers"],
  ["Catalyst/320_CatalystDriverScorecard.swift", "drivers"],
  ["Catalyst/321_CatalystDriverProfile.swift", "drivers"],
  ["Catalyst/322_CatalystDriverDocuments.swift", "drivers"],
  ["Catalyst/326_CatalystDriverCompliance.swift", "drivers"],
  ["Catalyst/327B_CatalystDriverQuarterDetail.swift", "drivers"],
  ["Catalyst/330B_CatalystVehicleScorecardAxisDetail.swift", "drivers"],
  ["Broker/402_BrokerCarrierVet.swift", "carriers"],
  ["Broker/405_BrokerActiveBrokerages.swift", "carriers"],
  ["Escort/ES04_PermitRequirements.swift", "corridor"],
  ["Terminal/AccessControllerScannerView.swift", "movements"],
  ["Dispatch/703_DispatchExceptionTriage.swift", "board"],
  ["Dispatch/706_DispatchDriverChat.swift", "comms"],
  ["Dispatch/707_DispatchDailyKPI.swift", "home"],
  ["Dispatch/Dpch780_DispatcherCommsDetailOctet.swift", "comms"],
  ["Compliance/901_ComplianceExpiringDocs.swift", "drivers"],
  ["Compliance/1111_OnboardingWizard.swift", "me"],
]);

function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    return entry.isDirectory() ? walk(full) : entry.name.endsWith(".swift") ? [full] : [];
  });
}

function matchingIndex(source, start, open, close) {
  let depth = 0;
  let quote = null;
  let lineComment = false;
  let blockComment = 0;
  for (let i = start; i < source.length; i += 1) {
    const ch = source[i];
    const next = source[i + 1];
    if (lineComment) {
      if (ch === "\n") lineComment = false;
      continue;
    }
    if (blockComment) {
      if (ch === "/" && next === "*") { blockComment += 1; i += 1; continue; }
      if (ch === "*" && next === "/") { blockComment -= 1; i += 1; }
      continue;
    }
    if (quote) {
      if (ch === "\\") { i += 1; continue; }
      if (ch === quote) quote = null;
      continue;
    }
    if (ch === "/" && next === "/") { lineComment = true; i += 1; continue; }
    if (ch === "/" && next === "*") { blockComment = 1; i += 1; continue; }
    if (ch === '"' || ch === "'") { quote = ch; continue; }
    if (ch === open) depth += 1;
    if (ch === close) {
      depth -= 1;
      if (depth === 0) return i;
    }
  }
  return -1;
}

function navSlots(source) {
  const slots = [];
  let cursor = 0;
  while ((cursor = source.indexOf("NavSlot(", cursor)) !== -1) {
    const open = cursor + "NavSlot".length;
    const close = matchingIndex(source, open, "(", ")");
    if (close === -1) break;
    const call = source.slice(cursor, close + 1);
    const label = call.match(/label:\s*"([^"]+)"/)?.[1]?.trim().toLowerCase();
    const current = call.match(/isCurrent:\s*(true|false)/)?.[1];
    slots.push({ label, current });
    cursor = close + 1;
  }
  return slots;
}

function arrayRanges(source) {
  const ranges = [];
  for (let i = 0; i < source.length; i += 1) {
    if (source[i] !== "[") continue;
    const close = matchingIndex(source, i, "[", "]");
    if (close === -1) continue;
    const body = source.slice(i, close + 1);
    if ((body.match(/NavSlot\s*\(/g) || []).length === 2 && navSlots(body).length === 2) {
      ranges.push({ start: i, end: close + 1, body });
      i = close;
    }
  }
  return ranges;
}

function sideFor(source, start) {
  const prefix = source.slice(Math.max(0, start - 600), start).toLowerCase();
  const leading = prefix.lastIndexOf("leading");
  const trailing = prefix.lastIndexOf("trailing");
  if (leading === trailing) return null;
  return leading > trailing ? "leading" : "trailing";
}

let changedFiles = 0;
let replacements = 0;
const changedPaths = [];
const errors = [];

for (const config of configs) {
  for (const dir of config.dirs) {
    for (const file of walk(path.join(viewsRoot, dir))) {
      const relative = path.relative(viewsRoot, file);
      if (relative.endsWith("NavController.swift") || relative === "Catalyst/311_CatalystSettings.swift") continue;
      if (excluded.has(relative)) continue;

      const source = fs.readFileSync(file, "utf8");
      if (!source.includes("BottomNav(")) continue;
      const ranges = arrayRanges(source);
      if (!ranges.length) {
        errors.push(`${relative}: BottomNav found but no two-slot arrays`);
        continue;
      }

      const currentLabels = navSlots(source)
        .filter((slot) => slot.current === "true")
        .map((slot) => config.map[slot.label])
        .filter(Boolean);
      const currentSet = new Set(currentLabels);
      const override = overrides.get(relative);
      if (currentSet.size > 1 && !override) {
        errors.push(`${relative}: multiple canonical current tabs ${[...currentSet].join(",")}`);
        continue;
      }
      const current = override ?? [...currentSet][0] ?? "none";

      let output = source;
      let fileReplacements = 0;
      for (const range of [...ranges].reverse()) {
        const side = sideFor(source, range.start);
        if (!side) {
          errors.push(`${relative}:${source.slice(0, range.start).split("\n").length}: cannot classify leading/trailing`);
          continue;
        }
        const replacement = `${config.route}.${side}(current: .${current})`;
        output = output.slice(0, range.start) + replacement + output.slice(range.end);
        fileReplacements += 1;
      }

      if (fileReplacements && output !== source) {
        changedFiles += 1;
        replacements += fileReplacements;
        changedPaths.push(relative);
        if (write) fs.writeFileSync(file, output);
      }
    }
  }
}

console.log(`${write ? "WROTE" : "DRY RUN"}: ${changedFiles} files, ${replacements} slot arrays`);
for (const relative of changedPaths) console.log(`CHANGED ${relative}`);
for (const error of errors) console.error(`ERROR ${error}`);
if (errors.length) process.exitCode = 1;
