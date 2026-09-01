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
  ["raw-proc-copy", /\bproc(?:edure)?\b/i],
  ["source-file-copy", /\b[\w./-]+\.(?:ts|tsx|swift|mjs|js):\d+\b/i],
  ["ticket-placeholder", /\bEUSO-\d{3,}\b/i],
  ["matrix-placeholder", /\bMATRIX-\d+\b/i],
  ["hardcoded-company", /\bcompanyId\s*1\b/i],
  ["raw-vertical-token", /\bvertical\s*=/i],
  ["pending-dev-copy", /\bBACKEND PENDING\b/i],
  ["todo-visible", /\bTODO\b/i],
  // Raw ORM / query fragments. A dispatcher tapping HOLD was being shown
  // `and(eq(yardMoves.id, id), eq(yardMoves.companyId, callerCompany))`.
  ["orm-fragment", /\b(?:eq|and|or|inArray|desc|asc)\(\s*\w+\.\w+|\bdrizzle\b|\bsql`/],
  // Internal programme codenames. "filed with the-oath" means nothing to a
  // port master and appeared in eight separate vessel strings.
  ["internal-codename", /\bthe-oath\b/i]
];

// A raw tRPC router.procedure path leaking into visible copy
// ("Posts to freightClaims.fileDispute" / "loads.getById · …").
// Users get domain language, never wire identifiers.
// A router.procedure path in visible copy. This was a hardcoded list of router
// names, so every router added since — esangCoach, portOps, vesselStowage,
// blankSailing, containerTimeline, imdg, multiModal, intermodal — sailed
// through. Matched structurally instead: `something.verbCamelCase` is a wire
// path regardless of which router it names, and the router list can no longer
// drift behind the codebase.
const trpcProcPattern = /\b[a-z][a-zA-Z0-9]*\.(?:get|list|create|update|delete|approve|reject|calculate|submit|assign|record|fetch|send|cancel|resolve|acknowledge|register|revoke|issue|release|link|unlink|import|export|audit|verify|validate|lock|unlock|rebooking|for)[A-Z][a-zA-Z0-9]*\b/;

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
  "eBOL", "eBOLs", "eBL", "ePOD", "eManifest", "eAWB", "eCMR", "eRUC", "eLog",
  "eLogs", "eDVIR", "eNOA",
  // physical units
  "kW", "kWh", "mAh", "mpg", "mmHg", "dBm", "tCO2e", "gCO2e", "kgCO2e"
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
    /\b(?:pillCopy|sub|meta|cta|caption|hint|eyebrow|footnote|binding|bindingAndCount|ref|body|note|notice|reason|blurb|copy|summary|helpText):\s*"((?:\\"|[^"])*)"/g
  ];
  for (const re of calls) {
    let match;
    while ((match = re.exec(line))) out.push(match[1]);
  }

  // Strings ASSIGNED to a user-facing state variable.
  //
  // The rules above only see a literal sitting directly inside Text(...) or a
  // `title:`-style parameter. Screens routinely do
  //     gapNotice = "…"                     // @State
  //     …
  //     gapCard(gapNotice)                  // -> Text(note)
  // and that one extra hop through a function parameter made the string
  // invisible here. It was not a small gap: the HOLD button on the terminal
  // move queue was showing a dispatcher raw Drizzle ORM
  // (`and(eq(yardMoves.id, id), …)`) through exactly this path, and ~37 such
  // strings survived a pass that the gate reported as clean.
  //
  // Matching on the VARIABLE NAME keeps this precise: these suffixes are how
  // this codebase names copy destined for a human.
  const assigned = /\b\w*(?:Notice|Note|Message|Error|Warning|Banner|Hint|Subtitle|Caption|Detail|Copy|Reason|Status)\b\s*=\s*"((?:\\"|[^"])*)"/g;
  let a;
  while ((a = assigned.exec(line))) out.push(a[1]);

  // Copy RETURNED from a String-returning helper. `callGapNotice()` renders
  // under a "HONEST GAP" header and returns its prose with `return "…"`, so
  // none of the collectors above ever saw it — the single worst string in the
  // vessel area survived two cleanup passes that way. Only long returns are
  // taken: `return "OFF ROSTER"` is a label, not prose.
  const returned = /\breturn\s+"((?:\\"|[^"])*)"/g;
  let r;
  while ((r = returned.exec(line))) {
    if (r[1].length >= 40) out.push(r[1]);
  }

  return out;
}

/**
 * Every procedure name the app actually calls, harvested from the API layer.
 *
 * The router-prefixed pattern below only fires on `router.procedure`. A bare
 * procedure name — "getRailTracking failed on this pass" — sailed straight
 * through, and those are just as much wire identifiers to a port master or a
 * rail engineer. Reading the real names out of EusoTripAPI.swift means the list
 * cannot drift from what the app calls, and cannot false-positive on ordinary
 * English, because a token only counts if the app genuinely invokes it.
 */
const PROC_SHAPE = /\b(?:get|list|create|update|delete|approve|reject|calculate|submit|assign|record|fetch|send|cancel|resolve|acknowledge|register|revoke|issue|release|link|unlink|import|export|audit|verify|validate)[A-Z][a-zA-Z0-9]{2,}\b/;

// Ordinary English that happens to fit the shape. Kept deliberately tiny — if
// this list grows, the rule is being bent rather than the copy fixed.
const PROC_SHAPE_ALLOW = /\b(?:getStarted|getHelp|getSupport|createAccount|updateAvailable|getDirections)\b/;

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
const dynamicVisibleStubCopy = /"[^"\n]*\bSTUB\b[^"\n]*"/;
const dynamicVisibleGapCopy = /"[^"\n]*(?:\bnamed gap\b|\bthe-oath\b|\bnot yet wired\b|\bpending backend\b)[^"\n]*"/i;

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

    // Ternary/helper-rendered copy such as
    // `Text(gap ? "STUB · endpoint" : ref)` is visible but does not begin
    // with Text("..."), so the regular literal collectors cannot see it.
    // These implementation-state phrases are never valid product copy in any
    // quoted Swift value, even when routed through a helper first.
    if (dynamicVisibleStubCopy.test(code) || dynamicVisibleGapCopy.test(code)) {
      findings.push({ rule: "dynamic-dev-copy", file: rel, line: index + 1, text: trimmed.slice(0, 160) });
    }

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
      // A procedure name with no router prefix is still a wire identifier.
      // The router-prefixed pattern above only fires on `router.procedure`, so
      // "getRailTracking failed on this pass" sailed through — and to a rail
      // engineer that is exactly as meaningless as the prefixed form. Matched by
      // SHAPE (verb + CamelCase) rather than against a harvested list, because
      // the copy frequently names server procedures the iOS layer never calls,
      // so no list built from this repo could see them.
      const procShape = copy.replace(PROC_SHAPE_ALLOW, "");
      const bare = procShape.match(PROC_SHAPE);
      if (bare) {
        findings.push({ rule: "bare-proc-name", file: rel, line: index + 1, text: `${bare[0]} ← ${text}` });
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
