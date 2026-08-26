#!/usr/bin/env node

import { createHash } from "node:crypto";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { get as httpsGet } from "node:https";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const read = (path) => readFileSync(resolve(root, path), "utf8");
const failures = [];
const trustedOrigin = "https://eusotrip.com";
const mapStyleManifestFile =
  "client/public/map-styles/eusorone-mode-map-styles-v2.json";
const expectedModes = ["truck", "rail", "vessel"];
const expectedFamilies = ["operational", "navigation", "terrain"];
const expectedThemes = ["light", "dark"];
const omvContentByFamily = Object.freeze({
  operational: "default,advanced_roads,advanced_pois,transit",
  navigation: "default,transit",
  terrain: "default,hillshade,contours,transit",
});

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function validateArchiveBytes(label, bytes, expectedSHA) {
  if (bytes.length < 2 || bytes[0] !== 0x1f || bytes[1] !== 0x8b) {
    failures.push(`[artifact] ${label}: missing gzip magic 1f8b`);
  }
  const actualSHA = sha256(bytes);
  if (actualSHA !== expectedSHA) {
    failures.push(
      `[artifact] ${label}: SHA-256 ${actualSHA} does not match ${expectedSHA}`,
    );
  }
}

function fetchRaw(url, redirectCount = 0) {
  return new Promise((resolveRequest, rejectRequest) => {
    const request = httpsGet(
      url,
      {
        headers: {
          Accept: "application/gzip, application/octet-stream;q=0.9, */*;q=0.1",
          "User-Agent": "EusoTrip-HERE-production-gate/1.0",
        },
      },
      (response) => {
        const status = response.statusCode ?? 0;
        const location = response.headers.location;
        if (status >= 300 && status < 400 && location) {
          response.resume();
          if (redirectCount >= 5) {
            rejectRequest(new Error("too many redirects"));
            return;
          }
          resolveRequest(
            fetchRaw(new URL(location, url).toString(), redirectCount + 1),
          );
          return;
        }
        const chunks = [];
        let size = 0;
        response.on("data", (chunk) => {
          size += chunk.length;
          if (size > 20 * 1024 * 1024) {
            request.destroy(new Error("archive response exceeded 20 MiB"));
            return;
          }
          chunks.push(chunk);
        });
        response.on("end", () => {
          resolveRequest({
            status,
            headers: response.headers,
            body: Buffer.concat(chunks),
            finalURL: url,
          });
        });
      },
    );
    request.setTimeout(15_000, () =>
      request.destroy(new Error("request timed out")),
    );
    request.on("error", rejectRequest);
  });
}

function requireText(path, snippets) {
  const source = read(path);
  for (const snippet of snippets) {
    if (!source.includes(snippet)) {
      failures.push(`${path}: missing ${JSON.stringify(snippet)}`);
    }
  }
}

function denyText(path, snippets) {
  const source = read(path);
  for (const snippet of snippets) {
    if (source.includes(snippet)) {
      failures.push(`${path}: forbidden ${JSON.stringify(snippet)}`);
    }
  }
}

function requireAbsoluteText(path, snippets, label = path) {
  if (!existsSync(path)) {
    failures.push(`${label}: file is missing`);
    return null;
  }
  const source = readFileSync(path, "utf8");
  for (const snippet of snippets) {
    if (!source.includes(snippet)) {
      failures.push(`${label}: missing ${JSON.stringify(snippet)}`);
    }
  }
  return source;
}

const frontendCandidates = [
  process.env.EUSOTRIP_FRONTEND_ROOT,
  resolve(root, "frontend"),
  resolve(root, "../../_codex_rios_hardening/frontend"),
].filter(Boolean);
const frontendRoot = frontendCandidates.find((candidate) =>
  existsSync(resolve(candidate, "shared/eusoroneMapStyleRegistry.ts")),
);

let mapStyleArtifacts = [];
if (!frontendRoot) {
  failures.push(
    `[artifact] frontend root not found; set EUSOTRIP_FRONTEND_ROOT so the 18-style manifest can be verified`,
  );
} else {
  const manifestPath = resolve(frontendRoot, mapStyleManifestFile);
  if (!existsSync(manifestPath)) {
    failures.push(`[artifact] ${mapStyleManifestFile}: manifest is missing`);
  } else {
    try {
      const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
      const styles = Array.isArray(manifest.styles) ? manifest.styles : [];
      const expectedKeys = expectedModes.flatMap((mode) =>
        expectedFamilies.flatMap((family) =>
          expectedThemes.map((theme) => `${mode}.${family}.${theme}`),
        ),
      );
      const actualKeys = styles.map((style) => style?.key);

      if (manifest.schemaVersion !== 2) {
        failures.push(
          `[artifact] ${mapStyleManifestFile}: schemaVersion must be 2`,
        );
      }
      if (manifest.artifactCount !== expectedKeys.length) {
        failures.push(
          `[artifact] ${mapStyleManifestFile}: artifactCount ${manifest.artifactCount} must be ${expectedKeys.length}`,
        );
      }
      if (styles.length !== expectedKeys.length) {
        failures.push(
          `[artifact] ${mapStyleManifestFile}: styles length ${styles.length} must be ${expectedKeys.length}`,
        );
      }
      if (new Set(actualKeys).size !== actualKeys.length) {
        failures.push(`[artifact] ${mapStyleManifestFile}: duplicate style keys`);
      }
      for (const expectedKey of expectedKeys) {
        if (!actualKeys.includes(expectedKey)) {
          failures.push(
            `[artifact] ${mapStyleManifestFile}: missing ${expectedKey}`,
          );
        }
      }
      if (manifest.visualReviewState !== "approved") {
        failures.push(
          `[visual] ${mapStyleManifestFile}: aggregate visual review is ${JSON.stringify(manifest.visualReviewState ?? "missing")}, not approved`,
        );
      }

      mapStyleArtifacts = styles.flatMap((style) => {
        const key = `${style?.mode}.${style?.family}.${style?.theme}`;
        const archiveURL = String(style?.archiveUrl ?? "");
        const file = archiveURL.split("/").at(-1) ?? "";
        const sha = String(style?.sha256 ?? "");
        const content = omvContentByFamily[style?.family];
        const expectedScheme =
          style?.family === "terrain"
            ? `topo.${style?.theme === "dark" ? "night" : "day"}`
            : `logistics.${style?.theme === "dark" ? "night" : "day"}`;

        if (style?.key !== key) {
          failures.push(
            `[artifact] ${style?.key ?? "<missing key>"}: mode/family/theme identity mismatch`,
          );
        }
        if (!expectedModes.includes(style?.mode)) {
          failures.push(`[artifact] ${style?.key}: unsupported mode ${style?.mode}`);
        }
        if (!expectedFamilies.includes(style?.family)) {
          failures.push(
            `[artifact] ${style?.key}: unsupported family ${style?.family}`,
          );
        }
        if (!expectedThemes.includes(style?.theme)) {
          failures.push(
            `[artifact] ${style?.key}: unsupported theme ${style?.theme}`,
          );
        }
        if (!/^[a-f0-9]{64}$/.test(sha)) {
          failures.push(`[artifact] ${style?.key}: invalid SHA-256 ${sha}`);
        }
        if (
          archiveURL !== `/map-styles/${file}` ||
          !file.endsWith(`-${sha}.tar.gz`) ||
          archiveURL.includes("?")
        ) {
          failures.push(
            `[artifact] ${style?.key}: archive URL must be same-origin, content-addressed, and end literally in .tar.gz`,
          );
        }
        if (style?.baseIdentity?.style !== "oslo") {
          failures.push(
            `[artifact] ${style?.key}: base style must be the global oslo definition`,
          );
        }
        if (style?.baseIdentity?.scheme !== expectedScheme) {
          failures.push(
            `[artifact] ${style?.key}: base scheme ${JSON.stringify(style?.baseIdentity?.scheme)} must be ${expectedScheme}`,
          );
        }
        if (style?.styleOverrideCount !== 282) {
          failures.push(
            `[visual] ${style?.key}: expected the complete 282-key authored definition surface`,
          );
        }
        if (style?.visualReviewState !== "approved") {
          failures.push(
            `[visual] ${style?.key}: screenshot, contrast, geography, device, and accessibility review is ${JSON.stringify(style?.visualReviewState ?? "missing")}, not approved`,
          );
        }

        return content
          ? [
              {
                key: style.key,
                mode: style.mode,
                family: style.family,
                theme: style.theme,
                content,
                file,
                sha256: sha,
              },
            ]
          : [];
      });
    } catch (error) {
      failures.push(
        `[artifact] ${mapStyleManifestFile}: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }
}

for (const path of [
  "EusoTrip/Services/HereMaps/HEREAuthService.swift",
  "EusoTrip/Services/HereMaps/HereBearerFetch.swift",
  "EusoTrip/Services/HereMaps/HereTileOverlay.swift",
]) {
  if (existsSync(resolve(root, path))) {
    failures.push(`${path}: obsolete mobile OAuth transport must not exist`);
  }
}

for (const path of [
  "EusoTrip/Info.plist",
  "EusoTrip.xcodeproj/project.pbxproj",
]) {
  denyText(path, [
    "HEREAccessKeyId",
    "HEREAccessKeySecret",
    "HERE_ACCESS_KEY_ID",
    "HERE_ACCESS_KEY_SECRET",
    "HERETokenEndpointURL",
    "HERE_TOKEN_ENDPOINT_URL",
  ]);
}

const proxyContracts = new Map([
  ["EusoTrip/Services/HereMaps/HereRoutingClient.swift", "hereMaps.route"],
  ["EusoTrip/Services/HereMaps/HereGeocodingClient.swift", "hereMaps.geocode"],
  ["EusoTrip/Services/HereMaps/HereMatrixClient.swift", "hereMaps.matrix"],
  [
    "EusoTrip/Services/HereMaps/HereFuelPricesClient.swift",
    "hereMaps.fuelPricesNearby",
  ],
  ["EusoTrip/Services/HereMaps/HereWeatherClient.swift", "hereMaps.weatherAt"],
  [
    "EusoTrip/Services/HereMaps/HereTrafficClient.swift",
    "hereMaps.trafficFlow",
  ],
  [
    "EusoTrip/Services/HereMaps/HereTrafficAnalyticsClient.swift",
    "hereMaps.historicalSpeedsAlongRoute",
  ],
  ["EusoTrip/Services/HereMaps/HereEVClient.swift", "hereMaps.evChargers"],
  [
    "EusoTrip/Services/HereMaps/HereParkingClient.swift",
    "hereMaps.parkingNearby",
  ],
  [
    "EusoTrip/Services/HereMaps/HereSafetyCamerasClient.swift",
    "hereMaps.safetyCamerasAt",
  ],
]);

for (const [path, procedure] of proxyContracts) {
  requireText(path, [procedure]);
  denyText(path, ["requireBearerToken", "HEREAuthService", "HereBearerFetch"]);
}

requireText("EusoTrip/Services/HereMaps/HereMapWebView.swift", [
  "v3/3.2.8.0/mapsjs-core.js",
  "v3/3.2.8.0/mapsjs-service.js",
  "func makeUIView(context: Context) -> WKWebView",
  "jsTrustedReferrerOrigin",
  "var isUsableCoordinate: Bool",
  ".filter(\\.isUsableCoordinate)",
  '"coordinateLabel": LatLongParser.displayString',
  'endpointLabelToggle && m.kind==="delivery"',
  "EusoTripMapStyleRegistry",
  "H.map.render.harp.Style",
  "getOMVService({ queryParams: { content: contentByFamily[family] } })",
  'operational: "default,advanced_roads,advanced_pois,transit"',
  'navigation: "default,transit"',
  'terrain: "default,hillshade,contours,transit"',
  "__setMapStyle",
  'style.addEventListener("error"',
  "H.map.render.Style.State.READY",
  'new Error("HERE style did not become READY within 20000ms")',
  "if(layer && layer.dispose){ layer.dispose(); }",
  "if(style && style.dispose){ style.dispose(); }",
  "@Environment(\\.accessibilityReduceMotion)",
  "map.setCenter({lat:Number(lat),lng:Number(lng)}, !reducedMotion)",
  "resolution.descriptor?.isProductionEligible == true",
  '"customStylesRequested"',
]);
denyText("EusoTrip/Services/HereMaps/HereMapWebView.swift", [
  "HERE JS apiKey not configured",
  "createDefaultLayers(",
  "dl.vector.normal.map",
  "dl.raster.normal.mapnight",
  'styleIdentity: "explore.day"',
  "MapScene.loadScene",
  "loadScene(fromFile:",
]);
requireText("EusoTrip/Services/HereMaps/HereMapsConfig.swift", [
  'static let jsTrustedReferrerOrigin = "https://eusotrip.com"',
]);

requireText("EusoTrip/Services/HereMaps/EusoTripMapStyleRegistry.swift", [
  '"EusoTrip \\(mode.displayName) \\(family.displayName) \\(theme.displayName) \\(artifactVersion)"',
  "public static let allStyles",
  "EusoTripMapProductMode.allCases.flatMap",
  "EusoTripMapFamily.allCases.flatMap",
  "EusoTripMapTheme.allCases.map",
  "artifactSHA256",
  "family == .navigation ? \"v2\" : \"v1\"",
  "default,advanced_roads,advanced_pois,transit",
  "default,hillshade,contours,transit",
  "styleOverrideCount",
  "visualReviewState",
  "visualReviewNote",
  "isProductionEligible",
  "case .barge(activeVesselProduct: true)",
  "case .intermodal(activeSegment: .some(let mode))",
  "case .escort(activeRoadEscort: true)",
  "case .unknown:",
]);
requireText("EusoTrip.xcodeproj/project.pbxproj", [
  "EusoTripMapStyleRegistry.swift in Sources",
]);

for (const artifact of mapStyleArtifacts) {
  if (!artifact.file.endsWith(`-${artifact.sha256}.tar.gz`)) {
    failures.push(
      `[artifact] ${artifact.key}: content hash must appear immediately before .tar.gz`,
    );
  }
  const artifactPath = `/map-styles/${artifact.file}`;
  if (!artifactPath.endsWith(".tar.gz") || artifactPath.includes("?")) {
    failures.push(
      `[artifact] ${artifact.key}: URL must end literally in .tar.gz with no query string`,
    );
  }
  requireText("EusoTrip/Services/HereMaps/EusoTripMapStyleRegistry.swift", [
    artifact.sha256,
    artifact.content,
  ]);
}

if (frontendRoot) {
  const webRegistryPath = resolve(
    frontendRoot,
    "shared/eusoroneMapStyleRegistry.ts",
  );
  const webMapPath = resolve(
    frontendRoot,
    "client/src/components/maps/HereMap.tsx",
  );
  const webRegistry = requireAbsoluteText(
    webRegistryPath,
    [
      "EUSO_MAP_STYLE_REGISTRY",
      "EUSO_MAP_STYLE_ARCHIVE_SHA256",
      "getEusoMapStyle",
      "artifactUrl",
      "artifactSha256",
      "omvContent",
      "primaryStyleEntries",
      "EUSO_PRIMARY_TRANSPORT_MODES.flatMap",
      "EUSO_MAP_FAMILIES.flatMap",
      "EUSO_MAP_THEMES.map",
      "resolveEusoMapStyle",
    ],
    "frontend/shared/eusoroneMapStyleRegistry.ts",
  );
  requireAbsoluteText(
    webMapPath,
    [
      "resolveEusoMapStyle",
      "prepareBasemapSelection",
      "commitPreparedBasemapSelection",
      "new (H as any).map.render.harp.Style(styleURL)",
      'style.addEventListener("error", handleError)',
      "style.getState() === (H as any).map.render.Style.State.READY",
      "platform.getOMVService({",
      "queryParams: { content: omvContent }",
      "function createHereControlLayers",
    ],
    "frontend/client/src/components/maps/HereMap.tsx",
  );

  if (webRegistry) {
    const contentMapStart = webRegistry.indexOf(
      "export const EUSO_MAP_OMV_CONTENT_BY_FAMILY",
    );
    const contentMapEnd = webRegistry.indexOf("});", contentMapStart);
    const contentMapBlock =
      contentMapStart >= 0 && contentMapEnd >= 0
        ? webRegistry.slice(contentMapStart, contentMapEnd)
        : "";
    const familyContent = new Map(
      mapStyleArtifacts.map(({ family, content }) => [family, content]),
    );
    for (const [family, content] of familyContent) {
      const expected = `${family}: "${content}"`;
      if (!contentMapBlock.includes(expected)) {
        failures.push(
          `[artifact] frontend content registry ${family}: missing ${JSON.stringify(expected)}`,
        );
      }
    }
  }

  for (const artifact of mapStyleArtifacts) {
    if (webRegistry) {
      for (const expected of [
        artifact.sha256,
        "artifactUrl: `/map-styles/eusotrip-${mode}-${family}-${theme}-${artifactVersion}-${sha256}.tar.gz`",
        "omvContent: EUSO_MAP_OMV_CONTENT_BY_FAMILY[family]",
      ]) {
        if (!webRegistry.includes(expected)) {
          failures.push(
            `[artifact] frontend registry ${artifact.key}: missing ${JSON.stringify(expected)}`,
          );
        }
      }
    }

    const localArchive = resolve(
      frontendRoot,
      "dist/public/map-styles",
      artifact.file,
    );
    if (!existsSync(localArchive)) {
      failures.push(
        `[artifact] frontend/dist/public/map-styles/${artifact.file}: deployment archive is missing`,
      );
    } else {
      validateArchiveBytes(
        `frontend/dist/public/map-styles/${artifact.file}`,
        readFileSync(localArchive),
        artifact.sha256,
      );
    }
  }
}

requireText("EusoTrip/Services/EusoTripAPI.swift", [
  "struct HereEngagementOutcome",
  "clientEventId",
  "let loadId: Int?",
  "let engagement: HereEngagementOutcome",
  "standingXp",
  "haulMiles",
  "cashState",
  "gamification.recordHereDeliveryOutcome",
]);
requireText("EusoTrip/Services/DriverGPSPushService.swift", [
  "var currentLoadId: Int?",
]);
requireText("EusoTrip/Services/HereMaps/HereHaulBridge.swift", [
  "DriverGPSPushService.shared.currentLoadId",
  "GamificationAPI.HereEngagementOutcome",
  'let newlyCredited = response.status == "credited"',
  'let alreadyCredited = response.status == "already_credited"',
  "if newlyCredited {",
  "credited: newlyCredited",
  "response.reward.standingXp",
  "response.reward.haulMiles",
]);
for (const path of [
  "EusoTrip/Services/EusoTripAPI.swift",
  "EusoTrip/Services/DriverGPSPushService.swift",
  "EusoTrip/Services/HereMaps/HereHaulBridge.swift",
]) {
  denyText(path, [
    "poiVisitsByCategory",
    "recordCoverage",
    "reward(for",
    "HereOutcomeAction",
    ".verifyVisit",
  ]);
}

const outcomeAPI = read("EusoTrip/Services/EusoTripAPI.swift");
const outcomeStart = outcomeAPI.indexOf("// MARK: HERE outcome intake");
const outcomeEnd = outcomeAPI.indexOf("// MARK: Profile", outcomeStart);
const outcomeContract = outcomeAPI.slice(outcomeStart, outcomeEnd);
for (const forbidden of ["HereOutcomeAction", "let action:"]) {
  if (outcomeContract.includes(forbidden)) {
    failures.push(
      `EusoTrip/Services/EusoTripAPI.swift HERE outcome: forbidden ${JSON.stringify(forbidden)}`,
    );
  }
}
const haulBridge = read("EusoTrip/Services/HereMaps/HereHaulBridge.swift");
for (const forbidden of [".verifyVisit", ".discover"]) {
  if (haulBridge.includes(forbidden)) {
    failures.push(
      `EusoTrip/Services/HereMaps/HereHaulBridge.swift: forbidden ${JSON.stringify(forbidden)}`,
    );
  }
}

requireText("EusoTrip/Services/HereMaps/HereRouteModels.swift", [
  "enum HereAddressProvenance",
  "case hereGeocode",
  "case hereReverseGeocode",
  'static let unknownLabel = "Unknown address"',
  "country: country",
]);

denyText("EusoTrip/Utilities/LatLongParser.swift", [
  "!(latitude == 0 && longitude == 0)",
]);

requireText("EusoTrip/Views/Components/HereMapView.swift", [
  "This wrapper intentionally refuses to render it",
  "must arrive through the checksum-bound `route.plan` renderer contract",
  "and `.eusoRoute` on `HereLiveMapView`",
]);
denyText("EusoTrip/Views/Components/HereMapView.swift", [
  "HereRoutingClient.polyline(for: route)",
]);

requireText("EusoTrip/Models/Multimodal/MultiModalCore.swift", [
  "truck uses HERE Routing v8",
  "rail uses the AAR transit-time table",
]);
requireText("EusoTrip/Views/Vessel/VesselOceanTrackMap.swift", [
  "CanonicalRoutePlanClient.BoundRoutePlan",
  "route.plan.purpose == routePurpose",
  "route.plan.identity.mode == .vessel",
  ".eusoRoute(",
  "AIS observations remain position evidence",
]);

for (const area of [
  "EusoTrip/Views",
  "EusoTrip/Services",
  "EusoTrip/ViewModels",
]) {
  const areaRoot = resolve(root, area);
  for (const entry of readdirSync(areaRoot, {
    recursive: true,
    withFileTypes: true,
  })) {
    if (!entry.isFile() || !entry.name.endsWith(".swift")) continue;
    const path = resolve(entry.parentPath, entry.name);
    const source = readFileSync(path, "utf8");
    const nullFirst = /HereLatLng\(\s*[^,\n]*\?\?\s*0(?:\.0+)?(?![\d.])\s*,/;
    const nullSecond =
      /HereLatLng\(\s*[^,\n]+,\s*[^,\n]*\?\?\s*0(?:\.0+)?(?![\d.])(?:\s*,|\s*\))/;
    if (nullFirst.test(source) || nullSecond.test(source)) {
      failures.push(
        `${path}: HERE layer coordinate may manufacture null-island data`,
      );
    }
  }
}

await Promise.all(
  mapStyleArtifacts.map(async (artifact) => {
    const artifactURL = `${trustedOrigin}/map-styles/${artifact.file}`;
    if (!artifactURL.endsWith(".tar.gz") || artifactURL.includes("?")) {
      failures.push(
        `[runtime] ${artifact.key}: production style URL must end literally in .tar.gz`,
      );
      return;
    }
    try {
      const response = await fetchRaw(artifactURL);
      if (response.status < 200 || response.status >= 300) {
        failures.push(
          `[runtime] ${artifactURL}: HTTP ${response.status}; archive was not served`,
        );
      }
      if (new URL(response.finalURL).origin !== trustedOrigin) {
        failures.push(
          `[runtime] ${artifactURL}: redirected outside trusted eusotrip.com origin to ${response.finalURL}`,
        );
      }
      const contentType = String(
        response.headers["content-type"] ?? "",
      ).toLowerCase();
      if (contentType.includes("text/html")) {
        failures.push(
          `[runtime] ${artifactURL}: content-type ${contentType} is the HTML SPA shell, not a HERE archive`,
        );
      } else if (
        !contentType.includes("application/gzip") &&
        !contentType.includes("application/x-gzip") &&
        !contentType.includes("application/octet-stream")
      ) {
        failures.push(
          `[runtime] ${artifactURL}: unsupported archive content-type ${contentType || "<missing>"}`,
        );
      }
      validateArchiveBytes(artifactURL, response.body, artifact.sha256);
    } catch (error) {
      failures.push(
        `[runtime] ${artifactURL}: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }),
);

if (failures.length) {
  console.error("HERE production gate failed:");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(
  `HERE production gate passed: ${proxyContracts.size} native clients use typed backend procedures; all ${mapStyleArtifacts.length} content-addressed mode/family/theme archives are visually approved, present in frontend/dist/public, and served byte-identically from eusotrip.com; HARP renderers require error handling plus Style READY; canonical route geometry and HERE Haul outcomes remain server-derived.`,
);
