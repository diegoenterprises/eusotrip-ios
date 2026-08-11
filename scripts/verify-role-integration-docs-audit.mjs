#!/usr/bin/env node

import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const registryPath = resolve(root, "EusoTrip/Services/RoleIntegrationRegistry.swift");
const ledgerPath = resolve(root, "docs/rios-provider-docs-audit.json");
const checkedAt = "2026-08-09";

const priorProviderIds = [
  "argus_media", "daseke", "flag_marshall", "freightverify", "hapag_lloyd",
  "inttra", "iridium", "kenworth", "macropoint", "napa_heavy_duty",
  "nfi_industries", "oocl", "orbcomm", "paccar", "port_baltimore", "portbase",
  "promex", "railcarrx", "rolling_strong", "rts_financial", "sea_intelligence",
  "seko", "shipwell", "skybitz", "sps_commerce", "star_cool", "stormgeo",
  "sysco", "trimble_tmw", "truck_paper", "truck_parking_club", "trucker_path",
  "tsa_twic", "turvo", "txtag", "up", "us_foods", "usace_locks", "verisk_3e",
  "verizon_connect", "veson_imos", "vigillo", "volvo_trucks", "wabash", "wabtec",
  "wartsila", "waymo_via", "wco_hs", "werner", "wex", "worldwide_express",
  "xpo", "yang_ming", "yusen_logistics", "zencargo",
].sort();

const allowedStates = new Set([
  "verified_live",
  "verified_auth_or_bot_gated",
  "verified_temporary_provider_error",
  "verified_live_manual_tls",
  "replaced_after_drift",
  "retired_no_supported_provider",
]);

const temporaryProviderHosts = new Set();

function parseRegistry(source) {
  const declarationPattern = /private static let (\w+): \[RoleIntegration\] =/g;
  const declarations = [...source.matchAll(declarationPattern)];
  const arrays = new Map();

  for (let index = 0; index < declarations.length; index += 1) {
    const declaration = declarations[index];
    const name = declaration[1];
    const start = declaration.index;
    const end = declarations[index + 1]?.index ?? source.length;
    const section = source.slice(start, end);
    const entries = [];
    const entryPattern = /\.init\(roleKey:\s*"([^"]+)",\s*slug:\s*"([^"]+)",\s*name:\s*"([^"]+)",\s*function:\s*"([^"]+)",\s*docs:\s*"([^"]+)",\s*category:\s*\.([A-Za-z0-9_]+)\)/g;

    for (const match of section.matchAll(entryPattern)) {
      entries.push({
        roleKey: match[1],
        slug: match[2],
        name: match[3],
        function: match[4],
        docs: match[5],
        category: match[6],
      });
    }

    const cloneMatch = section.match(
      /=\s*(\w+)\.map\s*\{[\s\S]*?RoleIntegration\(roleKey:\s*"([^"]+)"/,
    );
    arrays.set(name, {
      entries,
      cloneSource: cloneMatch?.[1] ?? null,
      cloneRole: cloneMatch?.[2] ?? null,
    });
  }

  const allMatch = source.match(/static let all: \[RoleIntegration\] = \(([\s\S]*?)\n\s*\)/);
  assert(allMatch, "RoleIntegrationRegistry.all could not be parsed");
  const allArrayNames = [...allMatch[1].matchAll(/\b[a-z][A-Za-z0-9]+\b/g)]
    .map(match => match[0])
    .filter(name => arrays.has(name));
  assert(allArrayNames.length > 0, "RoleIntegrationRegistry.all contains no parsed arrays");

  const resolving = new Set();
  const resolved = new Map();
  function resolveArray(name) {
    if (resolved.has(name)) return resolved.get(name);
    assert(!resolving.has(name), `Cyclic role integration mapping at ${name}`);
    const definition = arrays.get(name);
    assert(definition, `Unknown role integration array ${name}`);
    resolving.add(name);
    const inherited = definition.cloneSource
      ? resolveArray(definition.cloneSource).map(row => ({ ...row, roleKey: definition.cloneRole }))
      : [];
    const rows = [...inherited, ...definition.entries];
    resolving.delete(name);
    resolved.set(name, rows);
    return rows;
  }

  const rows = allArrayNames.flatMap(resolveArray).map(row => ({
    ...row,
    id: `${row.roleKey}:${row.slug}`,
  }));
  const rowIds = rows.map(row => row.id);
  assert.equal(new Set(rowIds).size, rowIds.length, "Runtime catalog contains duplicate role/slug IDs");

  return {
    declaredRows: [...arrays.values()].reduce((sum, definition) => sum + definition.entries.length, 0),
    runtimeRows: rows.sort((a, b) => a.id.localeCompare(b.id)),
  };
}

function groupRowsByUrl(rows) {
  const groups = new Map();
  for (const row of rows) {
    assert(row.docs.startsWith("https://"), `${row.id} must use HTTPS: ${row.docs}`);
    const group = groups.get(row.docs) ?? [];
    group.push(row.id);
    groups.set(row.docs, group);
  }
  return new Map(
    [...groups.entries()]
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([url, ids]) => [url, ids.sort()]),
  );
}

async function fetchUrl(url) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 30_000);
  try {
    const response = await fetch(url, {
      redirect: "follow",
      signal: controller.signal,
      headers: {
        accept: "text/html,application/json;q=0.9,*/*;q=0.8",
        "user-agent": "Mozilla/5.0 RIOSProviderDocsAudit/1.0",
      },
    });
    await response.body?.cancel();

    let state;
    if (response.status >= 200 && response.status < 400) {
      state = "verified_live";
    } else if ([401, 403, 406, 429].includes(response.status)) {
      state = "verified_auth_or_bot_gated";
    } else if (response.status >= 500 && temporaryProviderHosts.has(new URL(url).hostname)) {
      state = "verified_temporary_provider_error";
    } else {
      throw new Error(`${url} returned unadjudicated HTTP ${response.status}`);
    }

    return {
      state,
      httpStatus: response.status,
      finalUrl: response.url,
      verificationMethod: "live_fetch",
    };
  } finally {
    clearTimeout(timeout);
  }
}

async function refreshLedger(ledger, parsed) {
  const groupedRows = groupRowsByUrl(parsed.runtimeRows);
  const urls = [...groupedRows.keys()];
  const results = [];

  for (let index = 0; index < urls.length; index += 6) {
    const batch = urls.slice(index, index + 6);
    results.push(...await Promise.all(batch.map(async url => ({
      url,
      rowIds: groupedRows.get(url),
      checkedAt,
      ...await fetchUrl(url),
    }))));
  }

  const stateCounts = Object.fromEntries(
    [...allowedStates].map(state => [state, results.filter(result => result.state === state).length]),
  );
  const refreshed = {
    ...ledger,
    checkedAt,
    catalogSummary: {
      declaredRows: parsed.declaredRows,
      runtimeRows: parsed.runtimeRows.length,
      uniqueUrls: results.length,
      stateCounts,
    },
    catalogUrls: results.sort((left, right) => left.url.localeCompare(right.url)),
  };
  await writeFile(ledgerPath, `${JSON.stringify(refreshed, null, 2)}\n`, "utf8");
  return refreshed;
}

function verifyLedger(ledger, parsed) {
  assert.equal(ledger.schemaVersion, 1, "Unexpected provider docs audit schema");
  assert.equal(ledger.checkedAt, checkedAt, "Provider docs audit date is stale");
  assert.equal(ledger.priorUnadjudicated.length, 55, "Historical queue must contain exactly 55 providers");
  assert.deepEqual(
    ledger.priorUnadjudicated.map(row => row.providerId).sort(),
    priorProviderIds,
    "Historical 55-provider queue changed",
  );
  for (const row of ledger.priorUnadjudicated) {
    assert(allowedStates.has(row.state), `Historical provider ${row.providerId} has invalid state ${row.state}`);
  }
  const priorStateCounts = Object.fromEntries(
    [...allowedStates].map(state => [state, ledger.priorUnadjudicated.filter(row => row.state === state).length]),
  );
  assert.deepEqual(priorStateCounts, {
    verified_live: 43,
    verified_auth_or_bot_gated: 9,
    verified_temporary_provider_error: 0,
    verified_live_manual_tls: 1,
    replaced_after_drift: 1,
    retired_no_supported_provider: 1,
  }, "Historical provider dispositions drifted");

  const groupedRows = groupRowsByUrl(parsed.runtimeRows);
  assert.equal(ledger.catalogSummary.declaredRows, parsed.declaredRows, "Declared catalog row count drifted");
  assert.equal(ledger.catalogSummary.runtimeRows, parsed.runtimeRows.length, "Runtime catalog row count drifted");
  assert.equal(ledger.catalogSummary.uniqueUrls, groupedRows.size, "Unique catalog URL count drifted");
  assert.equal(ledger.catalogUrls.length, groupedRows.size, "Audit URL coverage is incomplete");
  assert.equal(new Set(ledger.catalogUrls.map(row => row.url)).size, ledger.catalogUrls.length, "Audit contains duplicate URLs");

  for (const audited of ledger.catalogUrls) {
    assert(allowedStates.has(audited.state), `${audited.url} has invalid audit state ${audited.state}`);
    assert.equal(audited.checkedAt, checkedAt, `${audited.url} has stale verification evidence`);
    assert(groupedRows.has(audited.url), `Audit contains URL absent from registry: ${audited.url}`);
    assert.deepEqual(audited.rowIds, groupedRows.get(audited.url), `Catalog row coverage drifted for ${audited.url}`);
    assert.notEqual(audited.httpStatus, 404, `${audited.url} is dead (404)`);
    assert.notEqual(audited.httpStatus, 410, `${audited.url} is dead (410)`);
    if (audited.state === "verified_live") {
      assert(audited.httpStatus >= 200 && audited.httpStatus < 400, `${audited.url} has an invalid live status`);
    } else if (audited.state === "verified_auth_or_bot_gated") {
      assert([401, 403, 406, 429].includes(audited.httpStatus), `${audited.url} has an invalid gated status`);
    } else if (audited.state === "verified_temporary_provider_error") {
      assert(audited.httpStatus >= 500, `${audited.url} has an invalid temporary-error status`);
      assert(temporaryProviderHosts.has(new URL(audited.url).hostname), `${audited.url} lacks a manual temporary-error adjudication`);
    }
  }
  for (const url of groupedRows.keys()) {
    assert(ledger.catalogUrls.some(row => row.url === url), `Registry URL is unadjudicated: ${url}`);
  }

  const coveredRows = ledger.catalogUrls.flatMap(row => row.rowIds).sort();
  assert.deepEqual(coveredRows, parsed.runtimeRows.map(row => row.id).sort(), "Not every runtime catalog row is audited");
  const catalogStateCounts = Object.fromEntries(
    [...allowedStates].map(state => [state, ledger.catalogUrls.filter(row => row.state === state).length]),
  );
  assert.deepEqual(ledger.catalogSummary.stateCounts, catalogStateCounts, "Catalog state summary drifted");
}

const source = await readFile(registryPath, "utf8");
const parsed = parseRegistry(source);
let ledger = JSON.parse(await readFile(ledgerPath, "utf8"));
if (process.argv.includes("--refresh")) ledger = await refreshLedger(ledger, parsed);
verifyLedger(ledger, parsed);

console.log(JSON.stringify({
  priorQueue: ledger.priorUnadjudicated.length,
  declaredRows: parsed.declaredRows,
  runtimeRows: parsed.runtimeRows.length,
  uniqueUrls: ledger.catalogUrls.length,
  stateCounts: ledger.catalogSummary.stateCounts,
}, null, 2));
