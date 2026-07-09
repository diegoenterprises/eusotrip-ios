#!/usr/bin/env node
/**
 * Scan user-facing Swift copy for dev-facing language that TestFlight
 * feedback called out as tacky or production-breaking.
 *
 * This is intentionally conservative: it looks at common SwiftUI visible
 * string callsites and skips comments/imports. It is a gate for visible copy,
 * not a general source-code denylist.
 *
 * Rules:
 *   - legacy denylist (backend/server/proc/file:line/ticket ids/TODO/...)
 *   - bare-trpc-proc: a raw tRPC procedure path (`loads.getById`) in copy
 *   - camel-internal: a camelCase internal identifier (`loadLifecycle`,
 *     `companyId`) inside an eyebrow/mono string (detected by " · "
 *     separators)
 *   - localized-description-direct / localized-description-flow: raw
 *     `error.localizedDescription` rendered in visible UI (directly inside
 *     Text(...)/message: or via a variable assigned from it)
 */
import fs from "node:fs";
import path from "node:path";

const root = path.resolve(process.argv.find((arg) => arg.startsWith("--root="))?.slice(7) || "EusoTrip");
const allow = new Set(
  (process.argv.find((arg) => arg.startsWith("--allow="))?.slice(8) || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean)
);

const patterns = [
  ["raw-backend-copy", /\bbackend\b/i],
  ["raw-server-copy", /\bservers?\b/i],
  ["raw-proc-copy", /\bproc\b/i],
  ["source-file-copy", /\b[\w./-]+\.(?:ts|tsx|swift|mjs|js):\d+\b/i],
  ["ticket-placeholder", /\bEUSO-\d{3,}\b/i],
  ["matrix-placeholder", /\bMATRIX-\d+\b/i],
  ["hardcoded-company", /\bcompanyId\s*1\b/i],
  ["raw-vertical-token", /\bvertical\s*=/i],
  ["pending-dev-copy", /\bBACKEND PENDING\b/i],
  ["todo-visible", /\bTODO\b/i]
];

// A raw tRPC router.procedure path leaking into visible copy
// ("Posts to freightClaims.fileDispute" / "loads.getById · …").
// Users get domain language, never wire identifiers.
const trpcProcPattern = /\b(?:loads|loadBidding|dispatch|wallet|eusoWallet|esang|documents|compliance|shippers|drivers|freightClaims|railShipments|vesselShipments|gamification|insurance|referrals|users|contacts|messaging|truckPosting|hotZones|marketPricing|eusoTicket|safety|hos|eld|csaScores|yardManagement|terminals|telemetry|geofencing|notifications|profile|news)\.[a-z][a-zA-Z]+\b/;

// camelCase internal identifier heuristic for eyebrow/mono strings:
// only applies to strings that use " · " separators (the eyebrow style),
// flags space-free tokens with two+ camel humps ("loadLifecycle",
// "companyId", "byEquipment"). Brand/platform spellings are allowlisted.
const camelBrandAllow = new Set([
  // Apple platform / product spellings
  "iPhone", "iPad", "iPadOS", "iPod", "iOS", "macOS", "watchOS", "tvOS",
  "visionOS", "iCloud", "iMessage", "carPlay",
  // EusoTrip brand spellings
  "eSang", "eusoTrip",
  // electronic-document industry spellings
  "eBOL", "eBOLs", "ePOD", "eManifest", "eAWB", "eCMR", "eRUC", "eLog",
  "eLogs", "eDVIR",
  // physical units
  "kWh", "mAh", "mpg", "mmHg", "dBm", "tCO2e", "gCO2e", "kgCO2e"
]);
const camelTokenPattern = /^[a-z]+(?:[A-Z][a-zA-Z0-9]*)+$/;

function camelInternalTokens(text) {
  if (!text.includes(" · ")) return [];
  const tokens = text.split(/[^A-Za-z0-9]+/).filter(Boolean);
  return tokens.filter((token) => camelTokenPattern.test(token) && !camelBrandAllow.has(token));
}

function walk(dir, out = []) {
  let entries = [];
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const entry of entries) {
    const filePath = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(filePath, out);
    else if (entry.isFile() && filePath.endsWith(".swift")) out.push(filePath);
  }
  return out;
}

function visibleStrings(line) {
  const out = [];
  const calls = [
    /\bText\(\s*"((?:\\"|[^"])*)"/g,
    /\bLabel\(\s*"((?:\\"|[^"])*)"/g,
    /\bButton\(\s*"((?:\\"|[^"])*)"/g,
    /\bNavigationLink\(\s*"((?:\\"|[^"])*)"/g,
    /\bTextField\(\s*"((?:\\"|[^"])*)"/g,
    /\bSecureField\(\s*"((?:\\"|[^"])*)"/g,
    /\bAlert\(\s*title:\s*Text\(\s*"((?:\\"|[^"])*)"/g,
    /\b(?:title|subtitle|text|label|detail|message):\s*"((?:\\"|[^"])*)"/g,
    /\b(?:pillCopy|sub|meta|cta|caption|hint|eyebrow|footnote|binding|bindingAndCount):\s*"((?:\\"|[^"])*)"/g
  ];
  for (const re of calls) {
    let match;
    while ((match = re.exec(line))) out.push(match[1]);
  }
  return out;
}

// Drop Swift string interpolations (`\(store.loads.count)`) before running
// copy heuristics — interpolation bodies are code, not copy, and would
// otherwise false-positive the tRPC-path and camelCase rules.
function stripInterpolations(text) {
  let out = text;
  for (let i = 0; i < 4; i += 1) {
    const next = out.replace(/\\\((?:[^()]|\([^()]*\))*\)/g, "");
    if (next === out) break;
    out = next;
  }
  // A nested quote inside an interpolation (`\(x.isEmpty ? "—" : x)`)
  // truncates the visible-string capture mid-interpolation; drop the
  // unbalanced tail so interpolation code never reads as copy.
  return out.replace(/\\\(.*$/, "");
}

// Strip a trailing line comment (but not the `//` inside `https://`).
function codePart(line) {
  return line.replace(/(^|[^:])\/\/.*$/, "$1");
}

// Direct render: `Text(` (or a visible-copy param label) appears on the
// line before `localizedDescription`. Index-based so nested calls and
// quoted interpolations can't hide the leak.
function rendersLocalizedDescriptionDirectly(code) {
  const at = code.indexOf("localizedDescription");
  if (at < 0) return false;
  const head = code.slice(0, at);
  const textAt = head.search(/\bText\(/);
  if (textAt >= 0) return true;
  return /\b(?:title|subtitle|text|label|detail|message)\s*:/.test(head);
}
const localizedAssignPattern = /(?:let|var)?\s*(?:self\.)?([A-Za-z_]\w*)(?:\s*:\s*[\w?\[\]<>., ]+)?\s*=[^=][^\n]*\.localizedDescription/;

const findings = [];
for (const file of walk(root)) {
  const rel = path.relative(process.cwd(), file);
  const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);

  // Pass 1 — collect variables assigned from `.localizedDescription`
  // so we can flag Text(...) that renders them later in the file.
  const localizedVars = new Set();
  lines.forEach((line) => {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("//") || trimmed.startsWith("*")) return;
    const code = codePart(line);
    if (!code.includes("localizedDescription")) return;
    // A chained transform (`error.localizedDescription.lowercased()`) is
    // classification code, not display copy — don't track it as a flow.
    if (/localizedDescription\s*\.\s*\w+/.test(code)) return;
    const match = code.match(localizedAssignPattern);
    if (match) localizedVars.add(match[1]);
  });

  lines.forEach((line, index) => {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("//") || trimmed.startsWith("*") || trimmed.startsWith("import ")) return;
    const key = `${rel}:${index + 1}`;
    if (allow.has(key)) return;
    const code = codePart(line);

    for (const text of visibleStrings(line)) {
      for (const [rule, pattern] of patterns) {
        if (pattern.test(text)) {
          findings.push({ rule, file: rel, line: index + 1, text });
        }
      }
      const copy = stripInterpolations(text);
      if (trpcProcPattern.test(copy)) {
        findings.push({ rule: "bare-trpc-proc", file: rel, line: index + 1, text });
      }
      for (const token of camelInternalTokens(copy)) {
        findings.push({ rule: "camel-internal", file: rel, line: index + 1, text: `${token} ← ${text}` });
      }
    }

    if (code.includes("localizedDescription")) {
      if (rendersLocalizedDescriptionDirectly(code)) {
        findings.push({ rule: "localized-description-direct", file: rel, line: index + 1, text: trimmed.slice(0, 120) });
      }
    } else if (localizedVars.size && /\bText\(/.test(code)) {
      for (const name of localizedVars) {
        const renders = new RegExp(`\\bText\\((?:verbatim:\\s*)?(?:self\\.)?${name}\\b`).test(code) ||
          new RegExp(`\\bText\\("(?:\\\\"|[^"])*\\\\\\((?:self\\.)?${name}\\b`).test(code);
        if (renders) {
          findings.push({ rule: "localized-description-flow", file: rel, line: index + 1, text: `${name} ← ${trimmed.slice(0, 110)}` });
          break;
        }
      }
    }
  });
}

if (findings.length) {
  console.error(`Dev-copy gate failed: ${findings.length} visible string issue(s)`);
  for (const finding of findings.slice(0, 500)) {
    console.error(`${finding.file}:${finding.line} [${finding.rule}] ${finding.text}`);
  }
  if (findings.length > 500) {
    console.error(`...and ${findings.length - 500} more`);
  }
  process.exit(1);
}

console.log("Dev-copy gate passed: no visible dev-language findings.");
