#!/usr/bin/env python3
"""Static release gate for the iOS weather/provider lifecycle boundary."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

OWNED_RUNTIME = [
    ROOT / "EusoTrip/Services/HereMaps",
    ROOT / "EusoTrip/Services/WeatherService.swift",
    ROOT / "EusoTrip/ViewModels/WeatherCardStore.swift",
    ROOT / "EusoTrip/Views/Components/HereMapView.swift",
    ROOT / "EusoTrip/Views/Components/HomeWeatherWidget.swift",
    ROOT / "EusoTrip/Views/Components/WeatherCard.swift",
    ROOT / "EusoTrip/Views/Components/WeatherIcons.swift",
    ROOT / "EusoTrip/Views/Components/WeatherSkyEngine.swift",
    ROOT / "EusoTrip/Views/Components/WeatherV3Components.swift",
    ROOT / "EusoTrip/Views/Components/PerLoadWeatherCard.swift",
    ROOT / "EusoTrip/Views/Vessel/671_VesselMarineWeatherRouting.swift",
    ROOT / "EusoTrip/Models/WeatherSnapshot.swift",
    ROOT / "EusoTrip/Models/WeatherForLoad.swift",
]

CONFIG_SUFFIXES = {".swift", ".plist", ".xcconfig", ".entitlements", ".json", ".yaml", ".yml"}
FORBIDDEN_TOMORROW = re.compile(
    r"tomorrow\.io|api\.tomorrow|tomorrow[_-]?io|TOMORROW_(?:API|KEY|TOKEN)",
    re.IGNORECASE,
)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def runtime_files() -> list[Path]:
    files: list[Path] = []
    for entry in OWNED_RUNTIME:
        if entry.is_dir():
            files.extend(sorted(entry.rglob("*.swift")))
        elif entry.exists():
            files.append(entry)
    return files


def require(text: str, needle: str, label: str, failures: list[str]) -> None:
    if needle not in text:
        failures.append(f"{label}: missing {needle!r}")


def reject(text: str, needle: str, label: str, failures: list[str]) -> None:
    if needle in text:
        failures.append(f"{label}: forbidden {needle!r}")


def main() -> int:
    failures: list[str] = []

    # Tomorrow.io must be absent from runtime source and app configuration.
    config_roots = [ROOT / "EusoTrip", ROOT / "EusoTrip.xcodeproj"]
    for config_root in config_roots:
        candidates = config_root.rglob("*") if config_root.is_dir() else [config_root]
        for path in candidates:
            if not path.is_file() or path.suffix.lower() not in CONFIG_SUFFIXES:
                continue
            match = FORBIDDEN_TOMORROW.search(read(path))
            if match:
                failures.append(f"Tomorrow.io reference in {path.relative_to(ROOT)}: {match.group(0)}")

    snapshot = read(ROOT / "EusoTrip/Models/WeatherSnapshot.swift")
    load_model = read(ROOT / "EusoTrip/Models/WeatherForLoad.swift")
    service = read(ROOT / "EusoTrip/Services/WeatherService.swift")
    store = read(ROOT / "EusoTrip/ViewModels/WeatherCardStore.swift")
    home = read(ROOT / "EusoTrip/Views/Components/HomeWeatherWidget.swift")
    card = read(ROOT / "EusoTrip/Views/Components/WeatherCard.swift")
    per_load = read(ROOT / "EusoTrip/Views/Components/PerLoadWeatherCard.swift")
    app = read(ROOT / "EusoTrip/EusoTripApp.swift")
    vessel_weather = read(ROOT / "EusoTrip/Views/Vessel/671_VesselMarineWeatherRouting.swift")
    sky = read(ROOT / "EusoTrip/Views/Components/WeatherSkyEngine.swift")
    policy_tests = read(ROOT / "EusoTripTests/Weather/WeatherProviderPolicyTests.swift")
    solar_runtime_gate = read(ROOT / "scripts/verify_weather_solar_runtime.swift")

    require(snapshot, "routeWeatherAuthority == .here", "route model authority", failures)
    require(snapshot, "func renderableLaneImpact", "lane render filter", failures)
    require(snapshot, "func live(at date: Date", "HERE endpoint freshness", failures)
    require(load_model, "routeWeatherAuthority == .here", "per-load authority", failures)
    require(service, 'preferredSource: "weatherkit"', "ambient WeatherKit preference", failures)
    require(
        service,
        "WeatherRouteDataPolicy.authority(for: s.source) == .here",
        "active-lane HERE gate",
        failures,
    )
    require(service, "let sourceLoadId: Int?", "numeric source-load decoder", failures)
    require(service, "sourceLoadId: authenticatedSourceLoadId",
            "authenticated source-load propagation", failures)
    require(service, "case \"openweather\":", "explicit ambient degradation", failures)
    require(service, "snap.isNightHint = Self.serverIsNightHint(icon: cur.icon)",
            "server provider daylight evidence", failures)
    require(store, 'return "OpenWeather fallback"', "fallback attribution", failures)
    require(home, ".eusoRefreshHandler(domains: [.weather])", "home pull refresh", failures)
    reject(home, "@Environment(\\.scenePhase)", "duplicate home foreground owner", failures)
    reject(home, "inactiveAt", "duplicate home reactivation state", failures)
    reject(home, "timeIntervalSince(awaySince) >= 60", "home delayed reactivation", failures)
    require(per_load, ".eusoRefreshHandler(domains: [.weather])", "per-load pull refresh", failures)
    reject(per_load, "@Environment(\\.scenePhase)", "duplicate per-load foreground owner", failures)
    reject(per_load, "inactiveAt", "duplicate per-load reactivation state", failures)
    reject(per_load, "timeIntervalSince(awaySince) >= 60", "per-load delayed reactivation", failures)
    require(
        app,
        "let needsFreshData = EusoRefreshCoordinator.shared.consumeStaleActivation()",
        "single app foreground weather owner",
        failures,
    )
    require(per_load, "providerDegradedState", "explicit route degradation", failures)
    require(per_load, "@State private var laneImpactExpanded = false",
            "collapsed per-load lane impact", failures)
    require(per_load, "if laneImpactExpanded {",
            "disclosed per-load lane details", failures)
    require(per_load, "case .unknown: return nil",
            "unknown route mode rejection", failures)
    reject(per_load, "snap.dataSource = .weatherKit", "per-load route provider", failures)
    reject(vessel_weather, "marineSkySnapshot", "fabricated marine sky snapshot", failures)
    reject(vessel_weather, "ESang: route to skip the swell core",
           "static vessel ESANG advice", failures)
    reject(vessel_weather, "Holds ETA · cuts slamming risk on the stacks",
           "static vessel ESANG outcome", failures)
    require(vessel_weather, "private var routeGuidance: some View",
            "provider-authored vessel route guidance", failures)
    require(vessel_weather, "WeatherNumeric.finite(value, allowed: 0...500)",
            "marine numeric boundary", failures)
    require(card, "liveLaneSegments", "home lane live filter", failures)
    require(card, "canRequestGroundedESang", "ESANG source gate", failures)
    require(card, "esangGroundingKey", "ESANG freshness key", failures)
    require(card, "input: Input(loadId: analysisLoadId)", "ESANG source identifier", failures)
    require(card, "WeatherRouteDataPolicy.parseProviderDate(providerTimestamp)",
            "fractional provider timestamp decoder", failures)
    reject(card, "input: Input(loadId: seg.loadId)", "ESANG display identifier", failures)
    reject(card, "Text(seg.esangSuggestion", "legacy static ESANG copy", failures)
    reject(card, "let shouldAnalyze", "automatic ESANG disclosure request", failures)
    reject(card, "Waiting for a fresh HERE route read", "repeated static ESANG copy", failures)
    require(card, "if !seg.canRequestGroundedESang(at: displayDate) {\n            EmptyView()",
            "grounded-only ESANG rendering", failures)
    require(sky, "switch solarState", "exclusive celestial state", failures)
    require(sky, "case .unknown:", "unknown celestial state", failures)
    require(sky, "default:                   self = .unknown",
            "unknown condition remains unknown", failures)
    require(sky, "private func boundedSkyElementCount(",
            "bounded sky element counts", failures)
    require(snapshot, "return .night\n        }\n        var cal = Calendar(identifier: .gregorian)",
            "neutral missing-timezone atmosphere", failures)
    require(policy_tests, "testStaleDaylightHintCannotPaintSunAtAustinNight",
            "stale daylight regression", failures)
    require(policy_tests, "testFreshProviderNightConditionWinsAtTheObservationInstant",
            "provider night regression", failures)
    require(policy_tests, "XCTAssertEqual(value.dayPart(at: now), .night)",
            "missing-evidence atmosphere regression", failures)
    require(policy_tests, "testUnsafeProviderNumericsNeverCrossIntegerBoundary",
            "non-finite numeric regression", failures)
    require(policy_tests, "testInvalidSnapshotMetricsRenderAsUnknown",
            "nullable snapshot regression", failures)
    require(policy_tests, "testInvalidTimelineRowsAreDroppedInsteadOfDefaulted",
            "timeline truth regression", failures)
    require(policy_tests, "testUnknownWeatherCodeKeepsSkyConditionUnknown",
            "unknown sky condition regression", failures)
    require(solar_runtime_gate, "WEATHER_SOLAR_RUNTIME_GATE=PASS",
            "executable solar runtime gate", failures)

    if failures:
        print("WEATHER_PROVIDER_GATE=FAIL")
        for failure in failures:
            print(f"- {failure}")
        return 1

    checked = len(runtime_files())
    print("WEATHER_PROVIDER_GATE=PASS")
    print(f"runtime_swift_files_checked={checked}")
    print("ambient_authority=WeatherKit")
    print("route_authority=HERE")
    print("tomorrow_io_references=0")
    return 0


if __name__ == "__main__":
    sys.exit(main())
