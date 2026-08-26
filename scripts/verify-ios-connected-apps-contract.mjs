#!/usr/bin/env node

import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const connectedAppsPath = resolve(root, "EusoTrip/Views/Shipper/346_ConnectedApps.swift");
const registryPath = resolve(root, "EusoTrip/Services/RoleIntegrationRegistry.swift");
const apiPath = resolve(root, "EusoTrip/Services/EusoTripAPI.swift");
const connectedApps = await readFile(connectedAppsPath, "utf8");
const registry = await readFile(registryPath, "utf8");
const api = await readFile(apiPath, "utf8");

const operationalRoles = [
  "SHIPPER", "CATALYST", "BROKER", "DRIVER", "DISPATCH", "ESCORT",
  "TERMINAL_MANAGER", "COMPLIANCE_OFFICER", "SAFETY_MANAGER", "FACTORING",
  "RAIL_SHIPPER", "RAIL_CATALYST", "RAIL_DISPATCHER", "RAIL_ENGINEER",
  "RAIL_CONDUCTOR", "RAIL_BROKER",
  "VESSEL_SHIPPER", "VESSEL_OPERATOR", "PORT_MASTER", "SHIP_CAPTAIN",
  "VESSEL_BROKER", "CUSTOMS_BROKER",
].sort();

function requireText(source, text, evidence) {
  assert(source.includes(text), `${evidence}: missing ${JSON.stringify(text)}`);
}

function forbidText(source, text, evidence) {
  assert(!source.includes(text), `${evidence}: forbidden ${JSON.stringify(text)}`);
}

for (const field of [
  "applicableModes", "connectionVerification", "catalogAliases", "researchStatus",
  "researchVerifiedAt", "inputRequirement", "activationVerification", "provisioning",
  "ownershipScope", "canEstablishConnection", "establishmentBlockedReason",
]) {
  requireText(connectedApps, `let ${field}:`, `Canonical catalog ${field} DTO coverage`);
}
for (const field of [
  "feedState", "feedStateReason", "credentialState", "isUsable", "accessible",
  "ownershipScope", "sharedWithCompany", "connectedByMe", "canManage", "activation",
]) {
  requireText(connectedApps, `let ${field}:`, `Canonical connection ${field} DTO coverage`);
}
requireText(connectedApps, "let capabilities: ProviderCapabilityFlags", "Exact capability object DTO");
requireText(connectedApps, "return provider.capabilities.perUserOAuth", "Server-owned OAuth eligibility");
requireText(connectedApps, "private struct IntegrationProvisioningRequirement", "Provisioning requirement DTO");
requireText(connectedApps, "private struct IntegrationActivationSummary", "Activation evidence DTO");
requireText(connectedApps, "private enum IntegrationActivationValue: Encodable", "Typed activation payload");
for (const fieldType of ["number", "csv", "json", "url", "email"]) {
  requireText(connectedApps, `case "${fieldType}"`, `Activation field type ${fieldType}`);
}
requireText(connectedApps, 'case "certificate", "private_key":', "Certificate and private-key activation fields");
requireText(connectedApps, 'case "text", "secret":', "Text and secret activation fields");
requireText(connectedApps, "[String: IntegrationActivationValue]", "Typed activation dictionaries");
forbidText(connectedApps, "credentials: [String: String]?", "Credentials cannot flatten typed fields");
requireText(connectedApps, "SensitiveMultilineTextEditor", "Multiline masked certificate and key custody");

for (const path of [
  "userIntegrations.listCatalog", "userIntegrations.listConnections",
  "userIntegrations.connect", "userIntegrations.disconnect", "userIntegrations.sync",
]) {
  requireText(connectedApps, path, "RIOS endpoint coverage");
}

for (const forbiddenRuntimeContract of [
  "credentialRef", "IntegrationJourneyPlanner", "fallbackJourney", "Registry fallback",
]) {
  forbidText(connectedApps, forbiddenRuntimeContract, "No secret or static runtime contract");
}

forbidText(connectedApps, "RoleIntegrationRegistry.providers", "Live catalog cannot use registry fallback");
forbidText(connectedApps, "private func startNativeOAuth", "No duplicate native OAuth transport");
forbidText(connectedApps, "api/integrations/oauth/native/start", "Connected Apps must not own the OAuth route");
requireText(connectedApps, "EusoTripAPI.shared.startIntegrationOAuth(", "Canonical native OAuth starter");
requireText(connectedApps, "confirmedRequirementKeys: confirmedRequirementKeys(for: provider)", "OAuth prerequisite evidence");
requireText(connectedApps, "confirmedRequirementKeys: confirmedRequirementKeys(for: p)", "Credential-connect prerequisite evidence");
requireText(api, "func startIntegrationOAuth(", "Canonical OAuth API method");
requireText(api, "confirmedRequirementKeys: [String]", "Canonical OAuth API confirmations");
requireText(api, "let confirmedRequirementKeys: [String]", "Canonical OAuth wire input");
requireText(connectedApps, "providerCompanyConfirmations(p)", "Company confirmation journey");
requireText(connectedApps, 'step.owner == "provider" ? "Provider action" : "Company action"', "Activation ownership evidence");
requireText(connectedApps, "p.canEstablishConnection", "Server-issued credential owner boundary");
requireText(connectedApps, "provider.canEstablishConnection", "Server-issued provider activation boundary");
forbidText(connectedApps, "canEstablishIntegrationCustody", "No client-inferred credential owner boundary");
requireText(connectedApps, "var isOperational: Bool?", "Tri-state operational truth");
requireText(connectedApps, "isUsable", "Server-owned usability truth");
forbidText(connectedApps, 'case "connected": return "live"', "No legacy status-to-live inference");
forbidText(connectedApps, '["live", "on_demand"].contains(effectiveFeedState)', "No feed-label usability inference");
requireText(connectedApps, ".confirmationDialog(", "Destructive disconnect confirmation");
requireText(connectedApps, "switch await refreshConnections()", "Mutation readback");
requireText(connectedApps, "Submitted secrets go to the server vault", "Credential custody disclosure");
requireText(connectedApps, "connectionVerificationLabel", "Activation proof disclosure");
requireText(connectedApps, "providerDocsURL", "Live documentation links");
requireText(connectedApps, "components.user == nil", "Documentation and activation URLs reject embedded users");
requireText(connectedApps, "components.password == nil", "Documentation and activation URLs reject embedded passwords");
forbidText(connectedApps, "out.recordsIngested ?? 0", "Missing record counts cannot become zero");
forbidText(connectedApps, "out.observationsInserted ?? 0", "Missing observation counts cannot become zero");
forbidText(connectedApps, "benefit.connectedCount ?? 0", "Missing journey connection state cannot become zero");
requireText(connectedApps, "The provider did not return ingestion counts.", "Unknown sync count truth");
requireText(connectedApps, "case .permissionDenied", "Permission-denied state");
requireText(connectedApps, "case .unavailable", "Unavailable state");
requireText(connectedApps, "case .unauthenticated", "Unauthenticated state");

const operationalBlock = registry.match(
  /static let operationalRoleKeys: Set<String> = \[([\s\S]*?)\n\s*\]/,
);
assert(operationalBlock, "Operational role manifest could not be parsed");
const declaredRoles = [...operationalBlock[1].matchAll(/"([A-Z_]+)"/g)]
  .map(match => match[1])
  .sort();
assert.deepEqual(declaredRoles, operationalRoles, "Operational role manifest drifted");
for (const role of operationalRoles) {
  assert(
    new RegExp(`roleKey:\\s*"${role}"`).test(registry),
    `Offline parity registry has no rows for ${role}`,
  );
}
requireText(registry, "aggregateServerRoleKeys: Set<String> = [\"ADMIN\", \"SUPER_ADMIN\"]", "Aggregate role classification");
requireText(registry, "liveCatalogOnlyRoleKeys: Set<String> = [\"SERVICE_PROVIDER\"]", "Live-only role classification");
requireText(registry, "static var validationIssues", "Registry integrity evidence");

const docs = [...registry.matchAll(/docs:\s*"([^"]+)"/g)].map(match => match[1]);
assert(docs.length > 0, "No registry documentation links were parsed");
for (const raw of docs) {
  const url = new URL(raw);
  assert.equal(url.protocol, "https:", `Registry documentation must use HTTPS: ${raw}`);
  assert(url.hostname, `Registry documentation must have a host: ${raw}`);
}

const output = {
  source: {
    operationalRoles: operationalRoles.length,
    registryDocumentationRows: docs.length,
    providerSource: "userIntegrations.listCatalog only",
    mutationsRequireReadback: true,
    canonicalOAuthStarter: true,
    provisioningConfirmationsForwarded: true,
    activationEvidenceDecoded: true,
    ownershipAndAccessDecoded: true,
    operationalTruth: "tri-state server evidence only",
    credentialMaterialDecoded: false,
    typedActivationPayload: true,
    customerCredentialCustodyGuard: true,
    unknownSyncCountsRemainUnknown: true,
  },
};

const cookieFileFlag = process.argv.indexOf("--live-cookie-file");
if (cookieFileFlag >= 0) {
  const cookiePath = process.argv[cookieFileFlag + 1];
  assert(cookiePath, "--live-cookie-file requires a Netscape cookie file path");
  const baseUrlFlag = process.argv.indexOf("--base-url");
  const baseUrl = baseUrlFlag >= 0
    ? process.argv[baseUrlFlag + 1]
    : "https://eusotrip-app.azurewebsites.net";
  assert(baseUrl, "--base-url requires a value");
  output.live = await verifyLiveReadOnly(baseUrl, cookiePath);
}

console.log(JSON.stringify(output, null, 2));

async function verifyLiveReadOnly(baseUrl, cookiePath) {
  const cookie = netscapeCookieHeader(await readFile(cookiePath, "utf8"));
  assert(cookie, "Cookie file did not contain any request cookies");

  const healthResponse = await fetch(new URL("/health", baseUrl), {
    headers: { accept: "application/json" },
  });
  assert(healthResponse.ok, `Live health returned HTTP ${healthResponse.status}`);
  const health = await healthResponse.json();
  assert.equal(health.status, "healthy", "Live server is not healthy");

  const catalog = await trpcRead(baseUrl, "userIntegrations.listCatalog", cookie);
  const connections = await trpcRead(baseUrl, "userIntegrations.listConnections", cookie);
  assert(Array.isArray(catalog), "Live catalog payload is not an array");
  assert(Array.isArray(connections), "Live connections payload is not an array");
  assert(catalog.length > 0, "Authenticated role catalog is unexpectedly empty");

  const stableCatalogKeys = [
    "id", "displayName", "category", "docsUrl", "authType", "status", "capabilities",
    "applicableModes", "requiresCredentials", "credentialFields", "configurationFields",
    "connectionVerification", "supportsSync", "connectable", "blockedReason",
    "researchStatus", "researchVerifiedAt", "journey",
  ];
  const canonicalCatalogKeys = [
    "inputRequirement", "activationVerification", "provisioning", "ownershipScope",
    "canEstablishConnection", "establishmentBlockedReason",
  ];
  for (const provider of catalog) {
    for (const key of stableCatalogKeys) {
      assert(Object.hasOwn(provider, key), `Live catalog row ${provider.id ?? "?"} is missing ${key}`);
    }
    assert.equal(typeof provider.id, "string", "Live provider id must be a string");
    assert.equal(typeof provider.connectable, "boolean", `${provider.id} connectable must be boolean`);
    assert(Array.isArray(provider.credentialFields), `${provider.id} credentialFields must be an array`);
    assert(Array.isArray(provider.configurationFields), `${provider.id} configurationFields must be an array`);
    if (provider.docsUrl != null) {
      const docsUrl = new URL(provider.docsUrl);
      assert.equal(docsUrl.protocol, "https:", `${provider.id} docsUrl must use HTTPS`);
      assert.equal(docsUrl.username, "", `${provider.id} docsUrl must not embed a username`);
      assert.equal(docsUrl.password, "", `${provider.id} docsUrl must not embed a password`);
    }
    for (const field of [...provider.credentialFields, ...provider.configurationFields]) {
      assert(
        ["text", "secret", "number", "csv", "json", "url", "email", "certificate", "private_key"].includes(field.inputType),
        `${provider.id}.${field.key} declares unsupported input type ${field.inputType}`,
      );
    }
    for (const requirement of provider.provisioning?.requirements ?? []) {
      if (requirement.docsUrl != null) {
        const requirementUrl = new URL(requirement.docsUrl);
        assert.equal(requirementUrl.protocol, "https:", `${provider.id} requirement docsUrl must use HTTPS`);
        assert.equal(requirementUrl.username, "", `${provider.id} requirement docsUrl must not embed a username`);
        assert.equal(requirementUrl.password, "", `${provider.id} requirement docsUrl must not embed a password`);
      }
    }
    if (provider.connectable) {
      assert(provider.connectionVerification, `${provider.id} is connectable without activation proof`);
      assert.equal(provider.researchStatus, "verified", `${provider.id} is connectable without verified research`);
    }
  }

  const stableConnectionKeys = ["id", "providerId", "status", "feedState", "feedStateReason", "credentialState", "isUsable"];
  const canonicalConnectionKeys = [
    "accessible", "ownershipScope", "sharedWithCompany", "connectedByMe", "canManage", "activation",
  ];
  const forbiddenConnectionKeys = ["credentials", "credentialRef", "config"];
  for (const connection of connections) {
    for (const key of stableConnectionKeys) {
      assert(Object.hasOwn(connection, key), `Live connection ${connection.id ?? "?"} is missing ${key}`);
    }
    for (const key of forbiddenConnectionKeys) {
      assert(!Object.hasOwn(connection, key), `Live connection readback exposed forbidden ${key}`);
    }
  }

  const catalogCanonicalMissing = missingFieldCounts(catalog, canonicalCatalogKeys);
  const connectionCanonicalMissing = missingFieldCounts(connections, canonicalConnectionKeys);
  const catalogCanonicalCurrent = Object.values(catalogCanonicalMissing).every(count => count === 0);
  const connectionCanonicalCurrent = connections.length > 0
    ? Object.values(connectionCanonicalMissing).every(count => count === 0)
    : null;

  return {
    baseUrl,
    healthStatus: health.status,
    catalogRows: catalog.length,
    connectableRows: catalog.filter(provider => provider.connectable).length,
    verifiedConnectionPathRows: catalog.filter(provider => provider.connectable && provider.connectionVerification).length,
    documentationRows: catalog.filter(provider => provider.docsUrl != null).length,
    connectionRows: connections.length,
    catalogCanonicalContract: catalogCanonicalCurrent ? "current" : "deployment_skew",
    catalogCanonicalMissing,
    connectionCanonicalContract: connectionCanonicalCurrent == null
      ? "not_sampled_empty"
      : connectionCanonicalCurrent ? "current" : "deployment_skew",
    connectionCanonicalMissing: connections.length > 0 ? connectionCanonicalMissing : null,
    connectionReadbackRedaction: connections.length > 0 ? "verified" : "not_sampled_empty",
    connectionReadbackRowsSampled: connections.length,
    mutationsExecuted: 0,
    sampledCatalogKeys: Object.keys(catalog[0]).sort(),
  };
}

function missingFieldCounts(rows, fields) {
  return Object.fromEntries(fields.map(field => [
    field,
    rows.filter(row => !Object.hasOwn(row, field)).length,
  ]));
}

async function trpcRead(baseUrl, procedure, cookie) {
  const url = new URL(`/api/trpc/${procedure}`, baseUrl);
  url.searchParams.set("input", JSON.stringify({ json: {} }));
  const response = await fetch(url, {
    headers: {
      accept: "application/json",
      "cache-control": "no-cache",
      cookie,
    },
  });
  const body = await response.json();
  assert(response.ok, `${procedure} returned HTTP ${response.status}: ${JSON.stringify(body)}`);
  assert(Object.hasOwn(body?.result?.data ?? {}, "json"), `${procedure} response envelope changed`);
  return body.result.data.json;
}

function netscapeCookieHeader(source) {
  return source
    .split(/\r?\n/)
    .map(line => line.startsWith("#HttpOnly_") ? line.slice("#HttpOnly_".length) : line)
    .filter(line => line && !line.startsWith("#"))
    .map(line => line.split("\t"))
    .filter(parts => parts.length >= 7)
    .map(parts => `${parts[5]}=${parts[6]}`)
    .join("; ");
}
