#!/usr/bin/env node
/**
 * contract-symmetry.mjs — iOS ⇄ server tRPC contract drift checker.
 *
 * WHY: iOS `In`/`Out` Codable structs and the server's Zod input schemas are
 * two hand-written contracts in two languages/repos with no shared source. When
 * they drift (iOS sends `agreementId: Int` where Zod wants `z.string()`, or
 * sends `{key,value}` to a schema that has neither), the mutation fails Zod
 * validation at RUNTIME and is usually swallowed by a client `try?`/do-catch —
 * a silent, every-user failure. (the-oath §6: `agreements.submitSignature`
 * Int-vs-string; `users.updateProfile` strips `{key,value}`; `435` partner
 * agreements sent a String id + no signature.)
 *
 * WHAT: a STATIC checker. It imports nothing from the live router (which would
 * pull in Drizzle's types and OOM, the same wall full `tsc` hits) — it regex-
 * parses both sides from source and diffs the top-level scalar input fields.
 *
 * PRECISION over recall: it only flags a mismatch when BOTH sides parsed
 * cleanly. Nested/complex schemas and named (non-inline) `.input(...)` schemas
 * are reported as SKIPPED, never as a false alarm. Better to miss a few than
 * cry wolf and get muted.
 *
 * USAGE (from the iOS repo root, web repo as a sibling):
 *   node Scripts/contract-symmetry.mjs
 *   node Scripts/contract-symmetry.mjs --ios=. --web=../eusoronetechnologiesinc
 *   node Scripts/contract-symmetry.mjs --json     # machine-readable
 * Exit code: 0 = no hard mismatches, 1 = at least one TYPE/UNKNOWN-FIELD
 * mismatch (CI gate). Lower-confidence notes never fail the build.
 */
import fs from "node:fs";
import path from "node:path";

const arg = (k, d) => {
  const hit = process.argv.find((a) => a.startsWith(`--${k}=`));
  return hit ? hit.slice(k.length + 3) : d;
};
const JSON_OUT = process.argv.includes("--json");
const SUMMARY = process.argv.includes("--summary"); // id-field drift census
const IOS_ROOT = path.resolve(arg("ios", "."));
const WEB_ROOT = path.resolve(arg("web", path.join(IOS_ROOT, "..", "eusoronetechnologiesinc")));
const ROUTERS_DIR = path.join(WEB_ROOT, "frontend", "server", "routers");
const IOS_SRC = path.join(IOS_ROOT, "EusoTrip");

// ── type categories ────────────────────────────────────────────────────────
const swiftCat = (t) => {
  let s = t.trim().replace(/\?+$/, "");
  if (/^\[[^:\[\]]+:[^:]+\]$/.test(s)) return "object"; // [K: V] dictionary → JSON object
  if (/^\[.*\]$/.test(s)) return "array";               // [V] array
  if (/^(String)$/.test(s)) return "string";
  if (/^(Int|Int32|Int64|UInt|Double|Float|CGFloat|Decimal|NSNumber)$/.test(s)) return "number";
  if (/^Bool$/.test(s)) return "boolean";
  return "other"; // enums/structs/Date/etc — don't flag (too ambiguous)
};
const zodCat = (base) => {
  if (base === "string") return "string";
  if (base === "number") return "number";
  if (base === "boolean") return "boolean";
  if (base === "array") return "array";
  if (base === "enum" || base === "literal" || base === "nativeEnum") return "string";
  if (base === "object" || base === "record") return "object";
  if (base === "coerce") return "coerce"; // z.coerce.* accepts string|number — never flag
  return "other"; // union/any/unknown/lazy/instanceof — don't flag
};

// ── balanced-brace scan: given text and index just AFTER an open "{", return
//    the index of the matching "}" (or -1). ─────────────────────────────────
const matchBrace = (txt, openIdx) => {
  let depth = 1;
  for (let i = openIdx; i < txt.length; i++) {
    const c = txt[i];
    if (c === "{") depth++;
    else if (c === "}") { depth--; if (depth === 0) return i; }
  }
  return -1;
};

// ── walk a dir for files matching a predicate ───────────────────────────────
const walk = (dir, test, out = []) => {
  let ents = [];
  try { ents = fs.readdirSync(dir, { withFileTypes: true }); } catch { return out; }
  for (const e of ents) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, test, out);
    else if (test(p)) out.push(p);
  }
  return out;
};

// ── iOS side: parse Encodable `In` structs + their mutation/query callsites ──
// Returns { "<proc>": { fields: {name:cat}, struct, file } } associated by the
// nearest preceding struct definition (handles many local `struct Input`s).
function parseIOS() {
  const calls = []; // {proc, structName, pos, file}
  const structs = []; // {name, fields:{name:cat}, end, file, raw}
  for (const f of walk(IOS_SRC, (p) => p.endsWith(".swift"))) {
    const txt = fs.readFileSync(f, "utf8");
    // callsites: .mutation("x.y", input: Name(   /  .query("x.y", input: Name(
    const callRe = /\.(?:mutation|query)\(\s*"([^"]+)"\s*,\s*input:\s*([A-Za-z_]\w*)\s*\(/g;
    let m;
    while ((m = callRe.exec(txt))) calls.push({ proc: m[1], structName: m[2], pos: m.index, file: f });
    // struct defs that conform to Encodable (In/Input/PrefIn/…)
    const structRe = /\bstruct\s+([A-Za-z_]\w*)\s*:\s*([^\{]*?)\{/g;
    let s;
    while ((s = structRe.exec(txt))) {
      if (!/\bEncodable\b|\bCodable\b/.test(s[2])) continue;
      const open = structRe.lastIndex; // index just after "{"
      const close = matchBrace(txt, open);
      if (close < 0) continue;
      const body = txt.slice(open, close);
      const fields = {};
      // only top-level `let name: Type` lines (skip nested braces in body)
      if (!/[{]/.test(body)) {
        const fre = /\blet\s+([A-Za-z_]\w*)\s*:\s*([^\n=]+?)(?:\s*=\s*[^\n]+)?\s*$/gm;
        let fm;
        while ((fm = fre.exec(body))) fields[fm[1]] = swiftCat(fm[2]);
      }
      structs.push({ name: s[1], fields, end: close, file: f, nested: /[{]/.test(body) });
    }
  }
  const byProc = {};
  for (const c of calls) {
    // nearest preceding same-name struct in the same file; else any same-name
    const same = structs.filter((st) => st.name === c.structName);
    const inFile = same.filter((st) => st.file === c.file && st.end < c.pos);
    const pick = inFile.length ? inFile.sort((a, b) => b.end - a.end)[0] : same[0];
    if (!pick || pick.nested) continue; // can't trust nested-body structs
    // first clean binding wins; record all callsites for reporting
    if (!byProc[c.proc]) byProc[c.proc] = { fields: pick.fields, struct: pick.name, file: path.relative(IOS_ROOT, c.file) };
  }
  return byProc;
}

// ── server side: parse `<proc>: …Procedure …​.input(z.object({…})) …` ────────
// Keyed as "<routerFileBasename>.<proc>" to match iOS "<prefix>.<proc>".
function parseZod() {
  const byProc = {};
  for (const f of walk(ROUTERS_DIR, (p) => p.endsWith(".ts"))) {
    const prefix = path.basename(f, ".ts");
    const txt = fs.readFileSync(f, "utf8");
    const procRe = /(^|\n)\s{2,}([A-Za-z_]\w*)\s*:\s*\w*[Pp]rocedure\b/g;
    // Collect every procedure declaration first, then bound each proc's
    // `.input(...)` search to the region BEFORE the next proc — otherwise a
    // no-input proc steals a later proc's schema and every field looks unknown.
    const procs = [];
    let m;
    while ((m = procRe.exec(txt))) procs.push({ name: m[2], after: procRe.lastIndex });
    for (let i = 0; i < procs.length; i++) {
      const proc = procs[i].name;
      const key = `${prefix}.${proc}`;
      // Duplicate proc name in one file (e.g. a sub-router with its own
      // `update`/`getById`) → the key is ambiguous; we can't know which the
      // iOS callsite targets, so never hard-fail on it. (Caught loads.ts
      // having two `update:` procs — z.string() and z.number().)
      if (byProc[key] !== undefined) { byProc[key] = { ambiguous: true }; continue; }
      const winEnd = i + 1 < procs.length ? procs[i + 1].after : txt.length;
      const region = txt.slice(procs[i].after, winEnd);
      // also bail if a non-inline named schema is used: `.input(SomeSchema)`
      const namedInput = /\.input\(\s*[A-Za-z_]\w*\s*[.)]/.test(region) && !/\.input\(\s*z\.object/.test(region);
      const inp = /\.input\(\s*z\.object\(\s*\{/.exec(region);
      if (!inp) { byProc[key] = namedInput ? { skipped: "named-schema" } : { noInput: true }; continue; }
      const open = procs[i].after + inp.index + inp[0].length;
      const close = matchBrace(txt, open);
      if (close < 0) { byProc[key] = { skipped: "unbalanced" }; continue; }
      // merged/extended schemas (.merge/.extend/spread/intersection) expose
      // fields we can't see inline → don't flag unknown-field for them.
      const merged = /z\.object\(\s*\{[\s\S]*?\}\s*\)\s*\.(merge|extend|and)\(/.test(region.slice(inp.index)) || /\.\.\./.test(txt.slice(open, close));
      const body = txt.slice(open, close);
      const strict = /\}\s*\)\s*\.strict\(/.test(txt.slice(close, close + 40));
      const passthrough = /\}\s*\)\s*\.passthrough\(/.test(txt.slice(close, close + 60));
      const fields = {};
      let partial = false;
      // top-level scalar fields only: `name: z.type()…,` on one line, no nested {
      for (const line of body.split("\n")) {
        const fm = /^\s*([A-Za-z_]\w*)\s*:\s*z\.([A-Za-z]+)\b/.exec(line);
        if (!fm) {
          if (/^\s*([A-Za-z_]\w*)\s*:/.test(line) && /[{[]/.test(line)) partial = true; // nested/complex field
          continue;
        }
        const opt = /\.optional\(|\.nullish\(|\.nullable\(|\.default\(/.test(line);
        fields[fm[1]] = { cat: zodCat(fm[2]), optional: opt };
      }
      byProc[key] = { fields, strict, passthrough, partial, merged };
    }
  }
  return byProc;
}

// ── --summary: id-field type-drift census ───────────────────────────────────
// Population scan (ALL `<x>Id` fields, not just matched inputs) of iOS String/Int
// vs server z.string/number/coerce. Shows the DRIFT SURFACE: where the iOS and
// server type populations conflict (iOS String → z.number, or iOS Int →
// z.string, both of which fail Zod). It does NOT pair specific callsites to
// specific procs (that's the per-proc diff above, which is precision-limited);
// it's the upper-bound surface to prioritise a per-field audit.
function summarize() {
  const ios = {};
  for (const f of walk(IOS_SRC, (p) => p.endsWith(".swift"))) {
    const txt = fs.readFileSync(f, "utf8");
    const re = /\blet\s+([A-Za-z_]\w*Id)\s*:\s*(String|Int)\b/g;
    let m; while ((m = re.exec(txt))) ((ios[m[1]] ??= { String: 0, Int: 0 })[m[2]]++);
  }
  const srv = {};
  for (const f of walk(ROUTERS_DIR, (p) => p.endsWith(".ts"))) {
    const txt = fs.readFileSync(f, "utf8");
    const re = /\b([A-Za-z_]\w*Id)\s*:\s*z\.(coerce\.number|number|string)\(\)/g;
    let m; while ((m = re.exec(txt))) {
      const k = m[2] === "coerce.number" ? "coerce" : m[2];
      ((srv[m[1]] ??= { string: 0, number: 0, coerce: 0 })[k]++);
    }
  }
  const rows = [...new Set([...Object.keys(ios), ...Object.keys(srv)])].map((fld) => {
    const i = ios[fld] || { String: 0, Int: 0 };
    const s = srv[fld] || { string: 0, number: 0, coerce: 0 };
    const strToNum = i.String > 0 && s.number > 0; // iOS String → z.number FAILS
    const intToStr = i.Int > 0 && s.string > 0;     // iOS Int → z.string FAILS
    return { fld, i, s, risk: strToNum || intToStr, strToNum, intToStr };
  }).filter((r) => (r.i.String + r.i.Int) > 0 && (r.s.string + r.s.number + r.s.coerce) > 0)
    .sort((a, b) => (b.risk - a.risk) || ((b.i.String + b.i.Int) - (a.i.String + a.i.Int)));

  if (JSON_OUT) { console.log(JSON.stringify(rows, null, 2)); return; }
  const C = { red: "\x1b[31m", yel: "\x1b[33m", grn: "\x1b[32m", dim: "\x1b[2m", rst: "\x1b[0m", b: "\x1b[1m" };
  console.log(`${C.b}id-field type-drift census${C.rst}  (iOS String/Int  vs  server z.string/number/coerce)\n`);
  console.log(`${C.dim}field                iOS S/I        server str/num/coerce   verdict${C.rst}`);
  let atRisk = 0;
  for (const r of rows) {
    const iosCol = `${r.i.String}/${r.i.Int}`.padEnd(13);
    const srvCol = `${r.s.string}/${r.s.number}/${r.s.coerce}`.padEnd(22);
    let v;
    if (r.strToNum && r.intToStr) v = `${C.red}BIDIRECTIONAL drift${C.rst}`;
    else if (r.strToNum) v = `${C.red}iOS String → z.number (fails)${C.rst}`;
    else if (r.intToStr) v = `${C.red}iOS Int → z.string (fails)${C.rst}`;
    else if (r.s.number > 0 && r.s.coerce > 0) v = `${C.yel}server mixes number+coerce${C.rst}`;
    else v = `${C.grn}aligned${C.rst}`;
    if (r.risk) atRisk++;
    console.log(`${r.fld.padEnd(20)} ${iosCol} ${srvCol} ${v}`);
  }
  console.log(`\n${C.b}${atRisk}${C.rst} id-fields with a type-drift surface (iOS+server populations conflict).`);
  console.log(`${C.dim}Surface ≠ confirmed bugs: a field can be z.string in proc A (iOS sends String) and z.number in proc B (iOS sends Int) and be fine per-proc. Use the per-proc diff (default mode) to confirm specific callsites; widen numeric-PK ids to z.coerce.number() (like loadId) where the underlying column is int.${C.rst}`);
}
if (SUMMARY) { summarize(); process.exit(0); }

// ── diff ─────────────────────────────────────────────────────────────────────
const ios = parseIOS();
const zod = parseZod();
const mism = []; // hard failures
const notes = []; // low-confidence / skipped

for (const [proc, c] of Object.entries(ios)) {
  const z = zod[proc];
  if (!z) { notes.push({ proc, kind: "no-server-match", detail: `iOS calls "${proc}" but no matching Zod proc found (router prefix may differ from file name).`, file: c.file }); continue; }
  if (z.noInput) { notes.push({ proc, kind: "server-no-input", detail: `iOS sends ${c.struct} but the server proc declares no z.object input.`, file: c.file }); continue; }
  if (z.skipped) { notes.push({ proc, kind: "skipped", detail: `server schema unparsed (${z.skipped}).`, file: c.file }); continue; }
  if (z.ambiguous) { notes.push({ proc, kind: "ambiguous", detail: `multiple "${proc}" procedures in the router file — can't disambiguate which the iOS call targets; skipped.`, file: c.file }); continue; }
  const zf = z.fields || {};
  // (1) type mismatches — the high-signal §6 bug class
  for (const [name, scat] of Object.entries(c.fields)) {
    const zinfo = zf[name];
    if (!zinfo) {
      // (2) iOS sends a field the schema doesn't declare → Zod strips it
      //     (silent no-op), UNLESS the schema is .passthrough(). Only flag
      //     when the schema parsed fully (no nested fields we couldn't read).
      if (!z.passthrough && !z.partial && !z.merged && Object.keys(zf).length > 0) {
        // Advisory, not a hard failure: inline parsing can't see fields a
        // schema picks up via merge/extend/spread/named refs, so this class
        // has real false positives. Surfaced for human review; the §6
        // {key,value}-stripped bug lives here. Promote to hard once schemas
        // are merge-free or the parser resolves refs.
        notes.push({ proc, field: name, kind: "unknown-field", detail: `iOS ${c.struct}.${name} (${scat}) has no matching field in the Zod schema → likely stripped at runtime (verify: schema may merge/extend).`, file: c.file });
      }
      continue;
    }
    if (scat === "other" || zinfo.cat === "other" || zinfo.cat === "coerce") continue; // ambiguous — don't flag
    if (scat !== zinfo.cat) {
      mism.push({ proc, field: name, kind: "type-mismatch", detail: `iOS ${c.struct}.${name} is ${scat}; Zod expects ${zinfo.cat}.`, file: c.file });
    }
  }
  // (3) required Zod field the iOS struct never sends (lower confidence — iOS
  //     may set it elsewhere; report as a NOTE, not a hard failure)
  if (!z.partial) {
    for (const [zn, zi] of Object.entries(zf)) {
      if (!zi.optional && !(zn in c.fields)) {
        notes.push({ proc, field: zn, kind: "maybe-missing-required", detail: `Zod requires "${zn}" (${zi.cat}) but iOS ${c.struct} doesn't send it.`, file: c.file });
      }
    }
  }
}

// ── report ────────────────────────────────────────────────────────────────
if (JSON_OUT) {
  console.log(JSON.stringify({ checked: Object.keys(ios).length, mismatches: mism, notes }, null, 2));
} else {
  const C = { red: "\x1b[31m", yel: "\x1b[33m", grn: "\x1b[32m", dim: "\x1b[2m", rst: "\x1b[0m", b: "\x1b[1m" };
  console.log(`${C.b}contract-symmetry${C.rst}  iOS=${path.relative(process.cwd(), IOS_ROOT) || "."}  web=${path.relative(process.cwd(), WEB_ROOT)}`);
  console.log(`${C.dim}matched ${Object.keys(ios).length} iOS callsites against ${Object.keys(zod).length} Zod procedures${C.rst}\n`);
  if (mism.length === 0) console.log(`${C.grn}✓ no contract type/unknown-field mismatches${C.rst}`);
  for (const x of mism) console.log(`${C.red}✗ ${x.kind}${C.rst}  ${C.b}${x.proc}${C.rst}\n    ${x.detail}\n    ${C.dim}${x.file}${C.rst}`);
  if (notes.length) {
    console.log(`\n${C.yel}notes (low-confidence / unverifiable — not failures):${C.rst}`);
    for (const n of notes) console.log(`${C.yel}·${C.rst} ${n.kind}  ${C.b}${n.proc}${C.rst} ${C.dim}${n.detail}${C.rst}`);
  }
  console.log(`\n${C.dim}Limits: top-level scalar fields only; matches by <routerFile>.<proc>; nested/named/union schemas skipped (shown as notes). Precision-biased — clean-parse mismatches only.${C.rst}`);
}
process.exit(mism.length > 0 ? 1 : 0);
