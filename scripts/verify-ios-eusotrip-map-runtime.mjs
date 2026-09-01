#!/usr/bin/env node

import assert from "node:assert/strict";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const root = process.cwd();
const hereMapPath = join(
  root,
  "EusoTrip/Services/HereMaps/HereMapWebView.swift",
);
const registryPath = join(
  root,
  "EusoTrip/Services/HereMaps/EusoTripMapStyleRegistry.swift",
);
const canvasPath = join(
  root,
  "EusoTrip/Views/Components/Map/BespokeMapCanvas.swift",
);
const canvasStylePath = join(
  root,
  "EusoTrip/Views/Components/Map/BespokeMapStyle.swift",
);
const lifecyclePath = join(
  root,
  "EusoTrip/Views/Shipper/LifecycleScaffold.swift",
);
const hereMap = readFileSync(hereMapPath, "utf8");
const registry = readFileSync(registryPath, "utf8");
const canvas = readFileSync(canvasPath, "utf8");
const canvasStyle = readFileSync(canvasStylePath, "utf8");
const lifecycle = readFileSync(lifecyclePath, "utf8");

function includesAll(source, values, label) {
  for (const value of values) {
    assert.ok(
      source.includes(value),
      `${label} is missing ${JSON.stringify(value)}`,
    );
  }
}

includesAll(
  registry,
  [
    'routeOriginHex = "#1473FF"',
    'routeMidpointHex = "#813FF5"',
    'routeDestinationHex = "#BE01FF"',
    "case barge(activeVesselProduct: Bool)",
    "case escort(activeRoadEscort: Bool)",
    "case intermodal(activeSegment: EusoTripMapProductMode?)",
    "case unknownTransportMode",
    "case bargeRequiresActiveVesselProduct",
    "case escortRequiresActiveRoadProduct",
    "case intermodalRequiresActiveSegment",
  ],
  "native style registry",
);

assert.ok(
  !registry.includes("applyNavigationRecommendation"),
  "active work must recommend Navigation without forcing a family mutation",
);

includesAll(
  hereMap,
  [
    "from=[0x14,0x73,0xFF]; to=[0x81,0x3F,0xF5]",
    "from=[0x81,0x3F,0xF5]; to=[0xBE,0x01,0xFF]",
    "function eusoLineSegments(pts,budget)",
    "progress:(startDistance+endDistance)/(2*total)",
    "strokeColor:sweepColor(segment.progress, 1)",
    "function routeStateSpec(state)",
    "return {width:5}",
    'if(kind==="rail")',
    'if(kind==="vessel")',
    'if(kind==="cluster")',
    'state==="degraded"',
    'state==="offline"',
    "accessibilityReduceMotion",
    "window.__setReducedMotion",
    "if(reducedMotion){ stopFx(); }",
    "No authorized live feed",
    "observation trail, not route progress",
    "linear-gradient(90deg,#1473FF 0%,#813FF5 52%,#BE01FF 100%)",
    "EusoTripRouteStateControl(routes: routeStateSummaries)",
    'case .offRoute: return "Off Route"',
    'Section("Route key")',
  ],
  "HERE runtime overlay contract",
);

assert.ok(
  hereMap.includes("case .route:") &&
    !hereMap.includes("referenceRoutes") &&
    !hereMap.includes("addReferenceLine") &&
    !hereMap.includes('"requestedColor": hex'),
  "legacy route-like geometry must fail closed instead of painting a flat route grammar",
);

const eusoLineStart = hereMap.indexOf("function addEusoLine(grp,pts,spec)");
const eusoLineEnd = hereMap.indexOf("// ── Geofence rings", eusoLineStart);
assert.ok(
  eusoLineStart >= 0 && eusoLineEnd > eusoLineStart,
  "EusoLine renderer boundaries must exist",
);
const eusoLineRenderer = hereMap.slice(eusoLineStart, eusoLineEnd);
assert.equal(
  eusoLineRenderer.split("new H.map.Polyline(").length - 1,
  1,
  "each EusoLine gradient segment must construct exactly one HERE polyline stroke",
);
assert.ok(
  !/\b(casing|casingWidth|edgeLine|underlay|routeOutline)\b/i.test(
    eusoLineRenderer.replace(/\/\/.*$/gm, ""),
  ),
  "the EusoLine renderer must not construct an outline, casing, or underlay",
);
const routeStateSpecStart = hereMap.indexOf("function routeStateSpec(state)");
const routeStateSpecEnd = hereMap.indexOf(
  "function wrappedLngDelta",
  routeStateSpecStart,
);
assert.ok(
  routeStateSpecStart >= 0 && routeStateSpecEnd > routeStateSpecStart,
  "HERE route-state style boundary must exist",
);
const routeStateSpec = hereMap.slice(routeStateSpecStart, routeStateSpecEnd);
assert.ok(
  routeStateSpec.includes("return {width:5}") &&
    !routeStateSpec.includes("switch") &&
    !routeStateSpec.includes("lineDash"),
  "route state must not alter the continuous five-point EusoLine",
);

const routePainterStart = canvas.indexOf("static func paintRoutePaths(");
const routePainterEnd = canvas.indexOf("// MARK: 4c2", routePainterStart);
assert.ok(
  routePainterStart >= 0 && routePainterEnd > routePainterStart,
  "Canvas route painter boundaries must exist",
);
const routePainter = canvas.slice(routePainterStart, routePainterEnd);
assert.equal(
  routePainter.split("context.stroke(").length - 1,
  1,
  "each Canvas gradient segment must have exactly one route stroke",
);
assert.ok(
  !routePainter.includes("referenceColor") &&
    !routePainter.includes("guard let state"),
  "the Canvas route painter must not retain a flat state-less route stroke",
);

assert.ok(
  !canvasStyle.includes("RouteActive") &&
    !canvasStyle.includes("RoutePending") &&
    !canvasStyle.includes("routePending") &&
    !canvasStyle.includes("dashPattern"),
  "native map style must not retain a dormant active/pending or dashed route split",
);
assert.ok(
  canvas.includes(
    "static func liveMarkerCoord(_ layers: [HereMapLayer]) -> HereLatLng?",
  ) &&
    (canvas.match(/liveMarkerCoord\(/g) ?? []).length === 1 &&
    !canvas.includes("nearestVertexIndex") &&
    !canvas.includes("splitIdx"),
  "raw live observations must not infer route progress in the native canvas",
);
includesAll(
  lifecycle,
  [
    "private var mapTransportMode: EusoTripMapTransportMode",
    "guard mapTransportMode == .truck",
    "mapModeContext: .unconfirmed(mapTransportMode)",
  ],
  "lifecycle map mode boundary",
);
assert.ok(
  !lifecycle.includes("guard vertical == .truck") &&
    !lifecycle.includes("addOns: vertical == .truck"),
  "role-aware lifecycle vocabulary must not select map routing or add-ons",
);

// Parse the embedded HERE runtime after substituting the finite set of Swift
// interpolations. This catches JavaScript syntax drift that `swiftc -parse`
// cannot see inside a multiline string.
const htmlReturn = hereMap.lastIndexOf('return """');
const htmlEnd = hereMap.indexOf('        """', htmlReturn + 10);
assert.ok(
  htmlReturn >= 0 && htmlEnd > htmlReturn,
  "HERE HTML template boundaries must exist",
);
let htmlTemplate = hereMap.slice(htmlReturn + 'return """'.length, htmlEnd);
for (const [swiftExpression, replacement] of [
  ["\\(styleConfigurationJSON)", "{}"],
  ['\\(endpointLabelToggle ? "true" : "false")', "false"],
  ['\\(reducedMotion ? "true" : "false")', "false"],
  ["\\(tilt)", "0"],
  ["\\(apiKey)", "test-key"],
  ["\\(centerLat)", "0"],
  ["\\(centerLng)", "0"],
  ["\\(zoom)", "4"],
  ["\\(dragFlags)", ""],
  ["\\(Int(tilt))", "0"],
]) {
  htmlTemplate = htmlTemplate.replaceAll(swiftExpression, replacement);
}
assert.ok(
  !htmlTemplate.includes("\\("),
  "all Swift interpolations in HERE HTML must be substituted",
);
const inlineScriptStart = htmlTemplate.lastIndexOf("<script>");
const inlineScriptEnd = htmlTemplate.indexOf("</script>", inlineScriptStart);
assert.ok(
  inlineScriptStart >= 0 && inlineScriptEnd > inlineScriptStart,
  "HERE inline script must exist",
);
const inlineJavaScript = htmlTemplate.slice(
  inlineScriptStart + "<script>".length,
  inlineScriptEnd,
);
assert.doesNotThrow(
  () => new Function(inlineJavaScript),
  "embedded HERE runtime JavaScript must parse after Swift interpolation",
);

function swiftFiles(directory) {
  return readdirSync(directory).flatMap((name) => {
    const path = join(directory, name);
    if (statSync(path).isDirectory()) return swiftFiles(path);
    return path.endsWith(".swift") ? [path] : [];
  });
}

const missingContexts = [];
const mismatchedModeDirectories = [];
const modeDirectoryContracts = new Map([
  ["EusoTrip/Views/Rail/", ".primary(.rail)"],
  ["EusoTrip/Views/Vessel/", ".primary(.vessel)"],
  ["EusoTrip/Views/Escort/", ".escort(activeRoadEscort: true)"],
]);

for (const path of swiftFiles(join(root, "EusoTrip"))) {
  const source = readFileSync(path, "utf8");
  const relativePath = relative(root, path);
  const matcher = /\bHere(?:Vector|Live)MapView\s*\(/g;
  for (const match of source.matchAll(matcher)) {
    const lineStart = source.lastIndexOf("\n", match.index) + 1;
    const linePrefix = source.slice(lineStart, match.index).trimStart();
    if (linePrefix.startsWith("///")) continue;

    const window = source.slice(match.index, match.index + 4_000);
    if (!window.includes("mapModeContext:")) {
      const line = source.slice(0, match.index).split("\n").length;
      missingContexts.push(`${relativePath}:${line}`);
      continue;
    }

    for (const [prefix, expectedContext] of modeDirectoryContracts) {
      if (
        relativePath.startsWith(prefix) &&
        !window.includes(expectedContext)
      ) {
        const line = source.slice(0, match.index).split("\n").length;
        mismatchedModeDirectories.push(
          `${relativePath}:${line} expected ${expectedContext}`,
        );
      }
    }
  }
}

assert.deepEqual(
  missingContexts,
  [],
  `map callsites without explicit mode context:\n${missingContexts.join("\n")}`,
);
assert.deepEqual(
  mismatchedModeDirectories,
  [],
  `mode-owned map callsites with the wrong explicit context:\n${mismatchedModeDirectories.join("\n")}`,
);

console.log(
  "PASS: iOS map runtime keeps explicit mode selection, a single uncased gradient route, non-color live truth, reduced motion, and no inferred progress",
);
