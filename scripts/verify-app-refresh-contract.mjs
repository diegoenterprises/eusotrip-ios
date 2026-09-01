import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const compact = (source) => source.replace(/\s+/g, " ");
const stripSwiftComments = (source) => source
  .replace(/\/\*[\s\S]*?\*\//g, "")
  .replace(/\/\/.*$/gm, "");
const repoRoot = fileURLToPath(new URL("../", import.meta.url));

const collectSwiftSources = (directoryURL) => {
  const sources = [];
  for (const entry of readdirSync(directoryURL, { withFileTypes: true })) {
    const childURL = new URL(`${entry.name}${entry.isDirectory() ? "/" : ""}`, directoryURL);
    if (entry.isDirectory()) sources.push(...collectSwiftSources(childURL));
    if (entry.isFile() && entry.name.endsWith(".swift")) {
      const absolutePath = fileURLToPath(childURL);
      sources.push({
        path: path.relative(repoRoot, absolutePath),
        source: readFileSync(childURL, "utf8"),
      });
    }
  }
  return sources;
};

const auth = read("EusoTrip/Models/AuthModels.swift");
const app = read("EusoTrip/EusoTripApp.swift");
const content = read("EusoTrip/ContentView.swift");
const refresh = read("EusoTrip/ViewModels/DynamicStore.swift");
const design = read("EusoTrip/Theme/DesignSystem.swift");
const router = read("EusoTrip/Views/RoleSurfaceRouter.swift");
const driverMe = read("EusoTrip/Views/Driver/067A_DriverMeHubs.swift");
const weather = read("EusoTrip/Views/Components/HomeWeatherWidget.swift");
const weatherService = read("EusoTrip/Services/WeatherService.swift");
const weatherModel = read("EusoTrip/Models/WeatherSnapshot.swift");
const weatherIcons = read("EusoTrip/Views/Components/WeatherIcons.swift");
const weatherCard = read("EusoTrip/Views/Components/WeatherCard.swift");
const weatherV3 = read("EusoTrip/Views/Components/WeatherV3Components.swift");
const weatherSky = read("EusoTrip/Views/Components/WeatherSkyEngine.swift");
const perLoadWeather = read("EusoTrip/Views/Components/PerLoadWeatherCard.swift");
const hereWeatherAdapter = read("EusoTrip/Services/HereMaps/HereWeatherAdapter.swift");
const hereWeatherClient = read("EusoTrip/Services/HereMaps/HereWeatherClient.swift");
const flightRegistry = read("EusoTrip/Services/ScopedAsyncFlightRegistry.swift");
const flightTimingTest = read("scripts/test-scoped-async-flight-registry.swift");
const driverHomeViewModel = read("EusoTrip/ViewModels/DriverHomeViewModel.swift");
const roleHomeIntro = read("EusoTrip/Views/Components/RoleHomeIntro.swift");
const driverActiveEnroute = read("EusoTrip/Views/Driver/013_ActiveEnroute.swift");
const driverESang = read("EusoTrip/Views/Driver/DriverTabPanes.swift");
const shipperESang = read("EusoTrip/Views/Shipper/ShipperESangCoachSheet.swift");
const newsReader = read("EusoTrip/Views/Driver/NewsArticleReader.swift");
const project = read("EusoTrip.xcodeproj/project.pbxproj");
const roleDetail = read("EusoTrip/Theme/Components/RoleDetailPush.swift");
const eusoCard = read("EusoTrip/Views/Components/EusoCardIssuePanel.swift");
const terminalHome = read("EusoTrip/Views/Terminal/700_TerminalHome.swift");
const dispatchHome = read("EusoTrip/Views/Dispatch/400_DispatcherHome.swift");
const complianceHome = read("EusoTrip/Views/Compliance/900_ComplianceOfficerHome.swift");
const railHome = read("EusoTrip/Views/Rail/550_RailEngineerHome.swift");
const vesselShipperHome = read("EusoTrip/Views/Vessel/001_VesselShipperHome.swift");
const vesselOperatorHome = read("EusoTrip/Views/Vessel/650_VesselOperatorHome.swift");
const directNativeHomes = [
  ["Driver", read("EusoTrip/Views/Driver/010_DriverHome.swift")],
  ["Shipper", read("EusoTrip/Views/Shipper/200_ShipperHome.swift")],
  ["Carrier", read("EusoTrip/Views/Carrier/300_CarrierHome.swift")],
  ["Catalyst", read("EusoTrip/Views/Catalyst/500_CatalystHome.swift")],
  ["Broker", read("EusoTrip/Views/Broker/400_BrokerHome.swift")],
  ["Dispatch", dispatchHome],
  ["Escort", read("EusoTrip/Views/Escort/600_EscortHome.swift")],
  ["Terminal", terminalHome],
  ["Compliance", complianceHome],
  ["Admin/Super Admin", read("EusoTrip/Views/Admin/800_AdminHome.swift")],
  ["Rail Engineer", railHome],
  ["Vessel Shipper", vesselShipperHome],
  ["Vessel Operator", vesselOperatorHome],
  ["Native specialists", router],
];
const directNativeHomeRefreshGaps = directNativeHomes
  .filter(([, source]) => !source.includes("ScrollView") || !source.includes(".eusoRefreshable"))
  .map(([name]) => name);
const nativeModeWorkspaces = [
  "EusoTrip/Views/Rail/551_RailShipments.swift",
  "EusoTrip/Views/Rail/552_RailCompliance.swift",
  "EusoTrip/Views/Rail/554_RailCrewHOSRoster.swift",
  "EusoTrip/Views/Rail/555_RailConsistBoard.swift",
  "EusoTrip/Views/Rail/559_RailYardOperations.swift",
  "EusoTrip/Views/Rail/595_RailCrewCertifications.swift",
  "EusoTrip/Views/Rail/639_RailYardDirectory.swift",
  "EusoTrip/Views/Vessel/651_VesselShipments.swift",
  "EusoTrip/Views/Vessel/654_VesselCrewCertifications.swift",
  "EusoTrip/Views/Vessel/660_VesselLivePosition.swift",
  "EusoTrip/Views/Vessel/661_VesselPortCalls.swift",
  "EusoTrip/Views/Vessel/686_VesselPortDirectory.swift",
  "EusoTrip/Views/Vessel/697_VesselPortOperations.swift",
  "EusoTrip/Views/Vessel/711_VesselCrewRestHours.swift",
  "EusoTrip/Views/Vessel/789_VesselCustomsStatusUpdate.swift",
  "EusoTrip/Views/Vessel/814_VesselCustomsEntryFiling.swift",
];
const nativeModeWorkspaceRefreshGaps = nativeModeWorkspaces.filter(
  (sourcePath) => !read(sourcePath).includes(".eusoRefreshable"),
);
const migrationManifest = read("scripts/app-refresh-explicit-loader-files.txt");
const allSwiftSources = collectSwiftSources(new URL("../EusoTrip/", import.meta.url));
const allSwiftCode = allSwiftSources
  .map(({ path: sourcePath, source }) => `\n// FILE ${sourcePath}\n${stripSwiftComments(source)}`)
  .join("\n");
const unscopedWeatherCallers = allSwiftSources.filter(({ source }) =>
  /(?:WeatherService\.shared|service)\.fetchCurrent\s*\(\s*\)/.test(stripSwiftComments(source))
);
const staleWeatherCacheCallers = allSwiftSources.filter(({ source }) => {
  const code = stripSwiftComments(source);
  return /WeatherService\.(?:cachedSnapshot|cachedSnapshotIsStale)(?!\s*\(\s*for:)/.test(code);
});

const expectedRoles = [
  "driver", "shipper", "catalyst", "broker", "dispatch", "escort",
  "terminal", "compliance", "safety", "admin", "superAdmin", "factoring",
  "railShipper", "railCatalyst", "railDispatch", "railEngineer",
  "railConductor", "railBroker", "vesselShipper", "vesselOperator",
  "portMaster", "shipCaptain", "vesselBroker", "customsBroker",
  "serviceProvider",
];

const roleBlock = auth.match(/enum EusoRole:[\s\S]*?var id:/)?.[0] ?? "";
const declaredRoles = [...roleBlock.matchAll(/^\s*case\s+(\w+)\s*=/gm)].map((match) => match[1]);
const roleSwitch = router.match(/switch role \{[\s\S]*?^\s*}\n\s*}/m)?.[0] ?? "";

const nativeBoundaryMarkers = [
  'eusoRefreshSurface("shipper:',
  'eusoRefreshSurface("catalyst:',
  'eusoRefreshSurface("broker:',
  'eusoRefreshSurface("escort:',
  'eusoRefreshSurface("terminal:',
  'eusoRefreshSurface("admin:',
  'eusoRefreshSurface("dispatch:',
  'eusoRefreshSurface("compliance:',
  'eusoRefreshSurface("rail-engineer:',
  'eusoRefreshSurface("vessel-shipper:',
  'eusoRefreshSurface("vessel-operator:',
  'eusoRefreshSurface("native-specialist:',
];

const specialistRoles = [
  "safety", "factoring", "serviceProvider",
];

const nativeModeRoles = [
  "railShipper", "railCatalyst", "railDispatch", "railConductor",
  "railBroker", "portMaster", "shipCaptain", "vesselBroker", "customsBroker",
];

const surfaceModifier = refresh.match(
  /private struct EusoRefreshSurfaceModifier[\s\S]*?private struct EusoRefreshHandlerModifier/
)?.[0] ?? "";
const handlerModifier = refresh.match(
  /private struct EusoRefreshHandlerModifier[\s\S]*?private struct EusoRefreshableModifier/
)?.[0] ?? "";
const refreshableModifier = refresh.match(
  /private struct EusoRefreshableModifier[\s\S]*?extension View/
)?.[0] ?? "";
const refreshControlModifier = refresh.match(
  /private struct EusoRefreshControlModifier[\s\S]*?private struct EusoRefreshTaskModifier/
)?.[0] ?? "";
const shellBlock = design.match(
  /struct Shell<Content: View, Nav: View>:[\s\S]*?\/\/ MARK: - Palette semantic-color convenience/
)?.[0] ?? "";
const baseStoreBlock = refresh.match(
  /class BaseDynamicStore<[\s\S]*?\/\/ MARK: - Concrete/
)?.[0] ?? refresh.match(/class BaseDynamicStore<[\s\S]*$/)?.[0] ?? "";
const refreshIdentityRisk = [refresh, router, content, driverMe, roleDetail]
  .some((source) => /refreshIdentity|webRefreshIdentity|\.id\([^\n)]*refresh/i.test(source));
const rawNativeRefreshOutsideCore = allSwiftSources.filter(({ path: sourcePath, source }) =>
  sourcePath !== "EusoTrip/ViewModels/DynamicStore.swift" &&
  /\.refreshable\s*\{/.test(source)
);
const taskRefreshLoaderWithoutScopedCallback = allSwiftSources.filter(({ path: sourcePath, source }) =>
  sourcePath !== "EusoTrip/ViewModels/DynamicStore.swift" &&
  /\.task\s*(?:\([^)]*\))?\s*\{/.test(source) &&
  /\.(?:eusoRefreshable|refreshable)\s*\{/.test(source) &&
  !/\.eusoRefresh(?:able|Handler)\s*\{/.test(source)
);
const realtimeViewLoaderWithoutScopedCallback = allSwiftSources.filter(({ path: sourcePath, source }) =>
  sourcePath.startsWith("EusoTrip/Views/") &&
  /publisher\s*\(\s*for:\s*\.esangRefreshSurface/.test(source) &&
  /Task\s*\{\s*await/.test(source) &&
  !/\.eusoRefresh(?:able|Handler)\s*\{/.test(source)
);
const migratedPaths = migrationManifest
  .split("\n")
  .filter((line) => line && !line.startsWith("#"));
const malformedMigratedPaths = migratedPaths.filter((sourcePath) => {
  const match = allSwiftSources.find((entry) => entry.path === sourcePath);
  return !match || !/\.eusoRefresh(?:able|Handler|Task)\s*\{/.test(match.source);
});

const checks = [
  [
    declaredRoles.length === 25 &&
      expectedRoles.every((role) => declaredRoles.includes(role)) &&
      declaredRoles.every((role) => expectedRoles.includes(role)),
    `EusoRole declares the exact 25-role production roster (found ${declaredRoles.length})`,
  ],
  [
    expectedRoles.every((role) => roleSwitch.includes(`.${role}`)),
    "RoleSurfaceRouter switch is exhaustive over all 25 role cases",
  ],
  [
    nativeBoundaryMarkers.every((marker) => router.includes(marker)),
    "all direct native role shells, including the specialist host, wrap their current route in a refresh boundary",
  ],
  [
    specialistRoles.every((role) =>
      new RegExp(`case \\.${role}:[\\s\\S]{0,140}NativeSpecialistRoleSurface\\(definition: \\.${role}`).test(router)
    ) && router.includes('.eusoRefreshSurface("native-specialist:\\(definition.role.rawValue):\\(activeDestination)")') &&
      router.includes('.eusoRefreshable { await store.refresh() }') &&
      !router.includes("struct WebContinuationSurface: View"),
    "Safety, Factoring, and Service Provider use real native refresh owners without signed-in web fallbacks",
  ],
  [
    nativeModeRoles.every((role) =>
      new RegExp(`case \\.${role}:[\\s\\S]{0,160}NativeModeRoleSurface\\(definition: \\.${role}`).test(router)
    ) && router.includes('.eusoRefreshSurface("native-mode-role:\\(definition.role.rawValue):\\(currentScreenId)")'),
    "all nine shared rail/vessel roles use the scoped native-mode refresh boundary",
  ],
  [
    content.includes('eusoRefreshSurface("driver:home:\\(s.id)")') &&
      content.includes('eusoRefreshSurface("driver:trips")') &&
      content.includes('eusoRefreshSurface("driver:loads")') &&
      driverMe.includes('eusoRefreshSurface("driver:me:\\(currentScreenId)")'),
    "Driver home, Trips, Loads, and the nested Me route all refresh without resetting Driver navigation",
  ],
  [
    roleDetail.includes('eusoRefreshSurface("role-detail:\\(detail.id.uuidString)")'),
    "in-stack pushed details refresh as the current visible screen",
  ],
  [
    refresh.includes("final class EusoRefreshCoordinator") &&
      refresh.includes("static let foregroundStaleAfter: TimeInterval = 60") &&
      refresh.includes("func consumeStaleActivation") &&
      refresh.includes("requestedTarget ?? visibleSurfaces.last?.surfaceID") &&
      refresh.includes("func surfaceDidAppear") &&
      refresh.includes("private var handlersBySurface") &&
      refresh.includes("func registerHandler(") &&
      refresh.includes("let entries = handlersBySurface[target].map { Array($0.values) } ?? []") &&
      refresh.includes("let operations = entries.map { $0.box.operation }") &&
      refresh.includes("guard !operations.isEmpty else") &&
      refresh.includes("await withTaskGroup(of: Void.self)") &&
      !refresh.includes("HandlerKind") &&
      !refresh.includes("waitForRegisteredWork") &&
      !refresh.includes("Task.yield()"),
    "coordinator snapshots and awaits only deterministic current-surface data owners",
  ],
  [
    surfaceModifier.includes(".environment(\\.eusoRefreshSurfaceID, surfaceID)") &&
      surfaceModifier.includes("surfaceDidAppear") &&
      surfaceModifier.includes("surfaceDidChange") &&
      surfaceModifier.includes("surfaceDidDisappear") &&
      !surfaceModifier.includes(".refreshable") &&
      !surfaceModifier.includes("accessibilityAction") &&
      !refresh.includes("EusoRefreshFallbackAction") &&
      !refresh.includes("EusoTopEdgeRefreshModifier") &&
      !app.includes("eusoRefreshFallback"),
    "surface boundary selects visibility only and never invents refresh work for static screens",
  ],
  [
    shellBlock.includes(".eusoRefreshControl(isEnabled: roleDockContract != nil)") &&
      refreshControlModifier.includes("await refresh(surfaceID, reason: .userPull)") &&
      !refreshControlModifier.includes("registerHandler") &&
      !refreshControlModifier.includes("session.revalidate") &&
      !refreshControlModifier.includes("NotificationCenter"),
    "every routed Shell exposes native pull while mounted real owners retain refresh authority",
  ],
  [
    !refreshIdentityRisk && !surfaceModifier.includes(".id("),
    "refresh never changes view identity or remounts the visible screen",
  ],
  [
    handlerModifier.includes("@State private var registrationToken = UUID()") &&
      handlerModifier.includes("registerHandler(") &&
      handlerModifier.includes("unregisterHandler(") &&
      handlerModifier.includes(".onAppear") &&
      handlerModifier.includes(".onDisappear") &&
      refresh.includes("func eusoRefreshHandler("),
    "mounted data owners synchronously join and leave their scoped handler registry",
  ],
  [
    rawNativeRefreshOutsideCore.length === 0 &&
      taskRefreshLoaderWithoutScopedCallback.length === 0 &&
      realtimeViewLoaderWithoutScopedCallback.length === 0 &&
      migratedPaths.length >= 400 &&
      malformedMigratedPaths.length === 0,
    `every pull/realtime-capable view loader has a scoped callback (${rawNativeRefreshOutsideCore.length} raw native refreshes; ${taskRefreshLoaderWithoutScopedCallback.length} uncovered task loaders; ${realtimeViewLoaderWithoutScopedCallback.length} bus-only loaders; ${malformedMigratedPaths.length} malformed manifest entries)`,
  ],
  [
    !baseStoreBlock.includes("NotificationCenter") &&
      !baseStoreBlock.includes("registerHandler") &&
      !baseStoreBlock.includes("EusoRefreshRequest") &&
      refresh.includes("func invalidateVisibleDomain(_ domain: EusoRefreshDomain)") &&
      refresh.includes("$0.domains.contains(domain)"),
    "BaseDynamicStore cannot fan out globally; typed invalidation targets visible matching owners only",
  ],
  [
    refreshableModifier.includes("@Environment(\\.eusoRefresh) private var refresh") &&
      refreshableModifier.includes("@Environment(\\.eusoRefreshSurfaceID) private var surfaceID") &&
      refreshableModifier.includes(".modifier(EusoRefreshHandlerModifier(handler: action, domains: [.general]))") &&
      refreshableModifier.includes("if let surfaceID") &&
      refreshableModifier.includes("await refresh(surfaceID, reason: .userPull)") &&
      refreshableModifier.includes("await action()"),
    "nested eusoRefreshable pulls enter the surface coordinator and only call directly without a boundary",
  ],
  [
    refresh.includes("date.timeIntervalSince(last) < 0.8") &&
      refresh.includes("reason == .userPull") &&
      !refresh.includes("topEdgePull") &&
      refresh.includes("private var inFlightBySurface") &&
      refresh.includes("if let existing = inFlightBySurface[target]") &&
      refresh.includes("await existing.task.value") &&
      refresh.includes("inFlightBySurface[target] = InFlightRefresh") &&
      refresh.includes("inFlightBySurface[target]?.id == refreshID") &&
      refresh.includes("inFlightBySurface[target] = nil") &&
      refresh.indexOf("if let existing = inFlightBySurface[target]") <
        refresh.indexOf("date.timeIntervalSince(last) < 0.8"),
    "physical pulls de-duplicate and concurrent requests join one token-cleaned task per surface",
  ],
  [
    compact(app).includes("if newPhase != .active { EusoRefreshCoordinator.shared.appBecameInactive() }") &&
      app.includes("consumeStaleActivation()") &&
      app.includes("await session.revalidate()") &&
      app.includes("reason: .staleForeground") &&
      app.includes("crossedCalendarDay") &&
      app.includes("NotificationCenter.default.publisher(for: .NSCalendarDayChanged)") &&
      app.includes("NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)") &&
      app.includes("UIApplication.significantTimeChangeNotification") &&
      app.includes("invalidateVisibleDomain(.weather)") &&
      app.includes("now.timeIntervalSince(lastWeatherClockRefreshAt) < 1"),
    "scene, calendar-day, time-zone, and significant-time transitions refresh visible real owners once",
  ],
  [
    weather.includes(".eusoRefreshHandler") &&
      weather.includes("await refresh(force: true)") &&
      !weather.includes("@Environment(\\.scenePhase)"),
    "HomeWeatherWidget registers its real provider reload without replacing its mounted state",
  ],
  [
    weatherService.includes("import CryptoKit") &&
      weatherService.includes("SHA256.hash(data: Data(raw.utf8))") &&
      weatherService.includes(".prefix(16)") &&
      !weatherService.includes("FNV") &&
      !weatherService.includes("non-reversible"),
    "weather cache filenames use a truncated SHA-256 namespace without making an anonymity claim",
  ],
  [
    weatherService.includes("private struct WeatherFlightKey: Hashable") &&
      weatherService.includes("let scope: WeatherRequestScope") &&
      weatherService.includes("let latitudeCell: Int") &&
      weatherService.includes("let longitudeCell: Int") &&
      weatherService.includes("let includesLaneImpact: Bool") &&
      weatherService.indexOf("guard let location = await awaitLocation") <
        weatherService.indexOf("let key = WeatherFlightKey(") &&
      weatherService.includes("guard activeContext == scope.context else { return nil }") &&
      weatherService.includes("self.activeContext == scope.context") &&
      !weatherService.includes("inFlightCurrent"),
    "weather coalescing is auth/session/scope/location/lane keyed and rejects stale contexts",
  ],
  [
    weatherService.includes("ScopedAsyncFlightRegistry<WeatherFlightKey, WeatherSnapshot?>") &&
      weatherService.includes("ScopedAsyncFlightRegistry<WeatherRequestContext, CLLocation?>") &&
      weatherService.includes("weatherFlights.cancelAll(returning: nil)") &&
      weatherService.includes("locationFlights.cancelAll(returning: nil)") &&
      flightRegistry.includes("withTaskCancellationHandler") &&
      flightRegistry.includes("withCheckedContinuation") &&
      flightRegistry.includes("cancelProviderIfUnobserved") &&
      flightRegistry.includes("guard flight.waiters.isEmpty else { return }") &&
      flightRegistry.includes("completionMonitors") &&
      project.includes("ScopedAsyncFlightRegistry.swift in Sources"),
    "per-waiter weather deadlines preserve shared work and cancel providers only after the final waiter",
  ],
  [
    flightTimingTest.includes("verifyIndependentWaiterDeadlines") &&
      flightTimingTest.includes("First waiter did not return near its 100 ms ceiling") &&
      flightTimingTest.includes("Second waiter did not receive the shared provider result") &&
      flightTimingTest.includes("Provider was not cancelled after its final waiter left") &&
      flightTimingTest.includes("Distinct keys coalesced across isolation boundaries"),
    "the executable flight test covers timeout, continued waiter, final cancellation, and key isolation",
  ],
  [
    unscopedWeatherCallers.length === 0 &&
      staleWeatherCacheCallers.length === 0 &&
      !stripSwiftComments(driverHomeViewModel).includes("fetchCurrent()") &&
      !stripSwiftComments(roleHomeIntro).includes("fetchCurrent("),
    `all weather callers are explicitly scoped (${unscopedWeatherCallers.length} unscoped fetches; ${staleWeatherCacheCallers.length} stale cache calls)`,
  ],
  [
    compact(app).includes(".environment(\\.eusoRefresh, EusoRefreshAction") &&
      refresh.includes("struct EusoRefreshActionKey: EnvironmentKey") &&
      compact(refresh).includes("func eusoRefreshSurface( _ surfaceID: String )"),
    "the refresh request is a reusable environment contract, not a screen-local singleton call",
  ],
  [
    app.includes("@State private var weatherSessionEpoch = UUID()") &&
      app.includes("WeatherRequestContext(") &&
      app.includes("sessionEpoch: weatherSessionEpoch") &&
      app.includes("weatherSessionEpoch = nextEpoch") &&
      app.includes("WeatherService.shared.activateContext(") &&
      app.includes("WeatherService.shared.deactivateContext()"),
    "every authentication edge rotates weather epoch and cancels the prior context",
  ],
  [
    weather.includes("private let firstLoadCeiling: Duration = .seconds(9)") &&
      weather.includes("waiterTimeout: hasLoadedOnce ? .seconds(15) : firstLoadCeiling") &&
      weather.includes("NotificationCenter.default.post(name: .eusoWeatherDisplayClockChanged") &&
      !weather.includes("fetchBounded") &&
      weatherService.includes("group.cancelAll()") &&
      weatherService.includes("while await group.next() != nil") &&
      weatherService.includes("withTaskCancellationHandler") &&
      weatherService.includes("geocoder.cancelGeocode()"),
    "weather has per-waiter first-load ceilings and cancellation-aware provider/location ownership",
  ],
  [
      weatherModel.includes("func displaySolarState(at displayDate: Date = Date())") &&
      weatherModel.includes("return solarState(at: displayDate)") &&
      weatherModel.includes("if let coordinate = LatLongParser.validatedCoordinate(") &&
      weatherModel.includes("latitude: latitude") &&
      weatherModel.includes("longitude: longitude") &&
      weatherModel.includes("latitude: coordinate.latitude") &&
      weatherModel.includes("longitude: coordinate.longitude") &&
      weatherModel.includes("guard let timezoneId, let zone = TimeZone(identifier: timezoneId)") &&
      !weatherCard.includes("Calendar.current.component(.hour, from: Date())") &&
      weatherCard.includes("isDaylight: solarState.isDaylight") &&
      weatherCard.includes("point.snapshot.displaySolarState(at: displayDate).isDaylight") &&
      weatherV3.includes("isDaylight: daylight(for: hour)") &&
      weatherV3.includes("return solarSnapshot.solarState(at: hour.date).isDaylight") &&
      weatherSky.includes("switch solarState") &&
      weatherSky.includes("case .night:") &&
      weatherSky.includes("case .daylight:") &&
      weatherSky.includes("case .unknown:") &&
      perLoadWeather.includes("displaySolarState(at: displayDate).isDaylight") &&
      perLoadWeather.includes("isDaylight: true") &&
      weatherIcons.includes("static func glyph(for weatherCode: Int, isDaylight: Bool? = nil)") &&
      weatherIcons.indexOf('if s.contains("cloud.moon")') < weatherIcons.indexOf('if s.contains("cloud")'),
    "one destination-local solar decision drives current sky/glyph; hourly and daily glyphs use their own instant",
  ],
  [
    weatherService.includes("snap.latitude = lat") &&
      weatherService.includes("snap.longitude = lng") &&
      weatherService.includes("snap.longitude = lon") &&
      weatherService.includes("snap.latitude = location.coordinate.latitude") &&
      weatherService.includes("snap.longitude = location.coordinate.longitude") &&
      weatherService.includes("let isDaytime: Bool?") &&
      weatherService.includes("isDaylightHint: p.isDaytime") &&
      weatherService.includes("isDaylightHint: hour.isDaylight") &&
      weatherService.includes('weather_code,is_day"') &&
      weatherService.includes("let is_day: [Int]?") &&
      weatherService.includes("isDaylightHint: payload.hourly?.is_day") &&
      hereWeatherClient.includes("let daylight: String?") &&
      hereWeatherAdapter.includes("snap.longitude = longitude") &&
      hereWeatherAdapter.includes("isDaylightHint: Self.daylightHint(h.daylight)"),
    "server, NWS, Open-Meteo, WeatherKit, and HERE preserve coordinate and per-hour daylight evidence",
  ],
  [
      driverESang.includes('.eusoRefreshSurface("modal:esang:driver")') &&
      shipperESang.includes('.eusoRefreshSurface("modal:esang:shipper")') &&
      router.includes('.eusoRefreshSurface("modal:web-continuation:shipper")') &&
      newsReader.includes('.eusoRefreshSurface("modal:news:\\(article.id)")') &&
      newsReader.includes("webView?.reload()") &&
      newsReader.includes("reloadHandler: $webViewReload") &&
      newsReader.includes('.eusoRefreshSurface("modal:news-safari:\\(article.id)")'),
    "ESANG, record-level Safari continuation, and WKWebView readers establish modal refresh boundaries without remounting",
  ],
  [
    driverActiveEnroute.match(/\.eusoRefreshTask\s*\{/g)?.length >= 2 &&
      driverActiveEnroute.includes("await hydrateLiveTrip()") &&
      driverActiveEnroute.includes("await refreshHosReachability()") &&
      refresh.includes("Static forms and session-only role landings do") &&
      refresh.includes("guard !operations.isEmpty else { return }") &&
      !refresh.includes("isFallback") &&
      !refresh.includes("fallback operation"),
    "task-only Driver 013 has scoped owners while ownerless surfaces expose no fake refresh path",
  ],
  [
    directNativeHomeRefreshGaps.length === 0 &&
      nativeModeWorkspaceRefreshGaps.length === 0 &&
      eusoCard.includes(".eusoRefreshHandler { await refresh() }"),
    `all direct native homes and shared native-mode workspaces own real pull reloads (home gaps: ${directNativeHomeRefreshGaps.join(", ") || "none"}; workspace gaps: ${nativeModeWorkspaceRefreshGaps.join(", ") || "none"})`,
  ],
];

const failures = checks.filter(([passed]) => !passed).map(([, message]) => message);
if (failures.length) {
  console.error(`App refresh contract verification failed:\n- ${failures.join("\n- ")}`);
  process.exit(1);
}

console.log(
  `App refresh contract verification passed (${checks.length}/${checks.length}); ` +
  `${declaredRoles.length} roles covered (Driver + direct native shells + ${nativeModeRoles.length} shared native-mode roles + ${specialistRoles.length} native specialist roles; zero signed-in web roles).`
);
