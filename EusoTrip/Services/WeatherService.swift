//
//  WeatherService.swift
//  EusoTrip — Live ambient weather shared by native home surfaces.
//
//  Pipeline:
//    CoreLocation one-shot → CLPlacemark (city) → WeatherKit current + hourly
//    + daily + alerts + solar → WeatherSnapshot (imperial units).
//
//  HERE does not participate in this ambient chain; it owns route corridor,
//  segment, hazard, and ETA intelligence through the separate lane adapters.
//  On failure this service returns nil so the mounted widget can retain its
//  last-good attributed reading without inventing a replacement.
//
//  Requires:
//    • Target capability "WeatherKit" enabled on the App ID (entitlement).
//    • INFOPLIST_KEY_NSLocationWhenInUseUsageDescription set in pbxproj.
//

import Foundation
import CoreLocation
import CryptoKit
import WeatherKit

enum WeatherNumeric {
    static let temperatureF = -200...250
    static let windMph = 0...600
    static let visibilityMi = 0...1_000
    static let percent = 0...100
    static let uvIndex = 0...100
    static let latitudeCell = -90_000...90_000
    static let longitudeCell = -180_000...180_000

    /// Network weather feeds may legally decode `NaN`/infinity. Swift traps
    /// when either is converted directly to `Int`, so every provider crosses
    /// this boundary before a numeric value reaches the snapshot model.
    static func roundedInt(
        _ value: Double?,
        allowed range: ClosedRange<Int>? = nil
    ) -> Int? {
        guard let value, value.isFinite else { return nil }
        let rounded = value.rounded()
        guard rounded >= Double(Int.min), rounded < Double(Int.max) else { return nil }
        let result = Int(rounded)
        guard range?.contains(result) ?? true else { return nil }
        return result
    }

    static func validatedInt(
        _ value: Int?,
        allowed range: ClosedRange<Int>? = nil
    ) -> Int? {
        guard let value, range?.contains(value) ?? true else { return nil }
        return value
    }

    static func finite(
        _ value: Double?,
        allowed range: ClosedRange<Double>? = nil
    ) -> Double? {
        guard let value, value.isFinite, range?.contains(value) ?? true else { return nil }
        return value
    }

    static func nonnegativeFinite(_ value: Double?) -> Double? {
        guard let value = finite(value), value >= 0 else { return nil }
        return value
    }

    static func elapsedWholeSeconds(from start: Date, to end: Date = Date()) -> Int? {
        guard let interval = finite(end.timeIntervalSince(start)) else { return nil }
        return roundedInt(max(0, interval.rounded(.down)))
    }
}

/// Authentication boundary for weather caching and coalescing. Weather itself
/// is device-local, but lane impact is tenant-scoped operational data and even
/// a cached city must never bleed across a sign-out/account switch.
struct WeatherRequestIdentity: Hashable, Sendable {
    let userID: String
    let companyID: String?
    let role: String

    init(user: AuthUser) {
        userID = user.id
        companyID = user.companyId
        role = user.role
    }

    /// Stable, filename-safe SHA-256 namespace. This keeps raw user/company
    /// IDs out of filenames and avoids Swift's process-seeded Hasher, which is
    /// unsuitable for durable names. The digest is naming hygiene, not an
    /// authorization boundary or a claim that low-entropy IDs cannot be
    /// dictionary-tested; tenant isolation is enforced by the scoped context.
    var cacheNamespace: String {
        let raw = "\(userID)|\(companyID ?? "-")|\(role)"
        return SHA256.hash(data: Data(raw.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

struct WeatherRequestScope: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case device
        case route(String)
    }

    let context: WeatherRequestContext
    let kind: Kind

    var identity: WeatherRequestIdentity { context.identity }

    static func device(_ context: WeatherRequestContext) -> Self {
        .init(context: context, kind: .device)
    }

    static func route(_ context: WeatherRequestContext, fingerprint: String) -> Self {
        .init(context: context, kind: .route(fingerprint))
    }
}

/// Ephemeral authentication generation. It changes on every sign-in/sign-out
/// edge, including signing back into the same account, while the durable
/// identity above continues to address that user's last-good disk cache.
struct WeatherRequestContext: Hashable, Sendable {
    let identity: WeatherRequestIdentity
    let sessionEpoch: UUID
}

@MainActor
final class WeatherService: NSObject, ObservableObject {

    static let shared = WeatherService()

    private let locationManager: CLLocationManager = {
        let m = CLLocationManager()
        // Best accuracy. Earlier passes used km-accuracy → 100m;
        // both still let CoreLocation hand back a cached fix that
        // pulled WeatherKit for the wrong city. `kCLLocationAccuracyBest`
        // forces a fresh GPS reading on almost every requestLocation()
        // call. Trade-off is battery, but weather only fetches on
        // dashboard appear / pull-to-refresh — not constantly.
        m.desiredAccuracy = kCLLocationAccuracyBest
        return m
    }()

    /// Maximum age (in seconds) of a CoreLocation fix we'll accept.
    /// Was 60s — too tight: CoreLocation's first response on a fresh
    /// app launch is frequently a cached fix older than 60s, which
    /// got silently rejected and the weather widget never rendered
    /// for either persona (founder report 2026-05-05 — "home screen
    /// weather widget didn't load … for either user"). 600s (10 min)
    /// is the sweet spot — drivers stay inside the same weather cell
    /// for that long unless on a sustained haul, and the next
    /// `requestLocation()` we issue refreshes the fix anyway.
    private let maxLocationAgeSeconds: TimeInterval = 600

    private let weatherService = WeatherKit.WeatherService.shared

    private final class CancellableGeocoder: @unchecked Sendable {
        let geocoder = CLGeocoder()

        func cancel() {
            geocoder.cancelGeocode()
        }
    }

    private struct WeatherFlightKey: Hashable {
        let scope: WeatherRequestScope
        let latitudeCell: Int
        let longitudeCell: Int
        let includesLaneImpact: Bool

        init?(scope: WeatherRequestScope, location: CLLocation, includesLaneImpact: Bool) {
            guard
                let latitudeCell = WeatherNumeric.roundedInt(
                    location.coordinate.latitude * 1_000,
                    allowed: WeatherNumeric.latitudeCell
                ),
                let longitudeCell = WeatherNumeric.roundedInt(
                    location.coordinate.longitude * 1_000,
                    allowed: WeatherNumeric.longitudeCell
                )
            else { return nil }
            self.scope = scope
            self.latitudeCell = latitudeCell
            self.longitudeCell = longitudeCell
            self.includesLaneImpact = includesLaneImpact
        }
    }

    /// Device location and provider work are coalesced independently. A route
    /// request cannot join ambient device weather, and neither can join work
    /// created by another authenticated identity.
    private let weatherFlights = ScopedAsyncFlightRegistry<WeatherFlightKey, WeatherSnapshot?>()
    private let locationFlights = ScopedAsyncFlightRegistry<WeatherRequestContext, CLLocation?>()
    private var activeContext: WeatherRequestContext?

    private var pendingLocation: CheckedContinuation<CLLocation?, Never>?
    private var pendingLocationID: UUID?
    private var pendingLocationTimeoutTask: Task<Void, Never>?
    /// True once the current one-shot already burned its single retry —
    /// a rejected stale cached fix triggers ONE fresh `requestLocation()`
    /// (CoreLocation is usually already acquiring the real fix) instead of
    /// failing the whole fetch.
    private var pendingLocationDidRetry = false

    override init() {
        super.init()
        locationManager.delegate = self
    }

    // MARK: - Exposed status (75th firing, 2026-04-24)
    //
    // DriverHomeViewModel needs to tell the dashboard WHY weather isn't
    // rendering (location denied vs WeatherKit unavailable), so the
    // underlying CLAuthorizationStatus is exposed read-only. Kept
    // `private(set)` equivalent via a computed getter — no public
    // locationManager surface.

    /// Current CoreLocation authorization status for the WeatherService.
    /// Consumers use this to distinguish "needs location" from "weather
    /// momentarily unavailable" so the UI can offer the right CTA.
    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    /// Fire the iOS "Allow EusoTrip to use your location?" prompt
    /// directly. Idempotent: if status is already determined (granted,
    /// denied, or restricted), this is a no-op. Callers use it to
    /// surface the system dialog from a CTA tap when the previous
    /// "request on first weather fetch" path didn't fire (e.g.
    /// because the home view appeared before `fetchCurrent()`'s
    /// internal `requestWhenInUseAuthorization()` reached the runloop).
    /// Founder report 2026-05-05 — "the app doesn't ask for my
    /// location so it doesn't load the weather widget".
    func requestPermissionIfNeeded() {
        guard locationManager.authorizationStatus == .notDetermined else { return }
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK: - Public

    /// Fetch a single current snapshot for the user's present location.
    /// Returns `nil` on any failure — UI keeps the last real reading when
    /// one exists, or shows an honest permission/unavailable state.
    ///
    /// Flow:
    ///   1. Kick CoreLocation authorization if we haven't asked yet.
    ///   2. Try a one-shot location read with a hard 4-second timeout so
    ///      the simulator (which frequently has no fix) can't stall us.
    ///   3. If no location came back, return nil — callers inspect
    ///      `authorizationStatus` to decide whether to render an
    ///      "Enable location" CTA or silently omit the card. We do NOT
    ///      fall back to a fabricated city any more (this was a Cohort A
    ///      mock before the 75th firing).
    ///
    /// 75th firing (2026-04-24, eusotrip-killers hygiene + fallback C):
    /// dropped the Dallas, TX fallback. Rendering weather for a location
    /// the driver isn't actually at violated §3 "no-mock" and the 2027
    /// motivation "no fake data" pledge. The dashboard's new
    /// `weatherAvailability` state carries the reason up to the view.
    /// Last-good location weather is partitioned by authenticated identity.
    /// Route impact is stripped before persistence below, but the identity
    /// boundary still prevents a signed-out/new user from inheriting another
    /// user's prior city while a new location fix is pending.
    private static var lastSnapshots: [WeatherRequestIdentity: WeatherSnapshot] = [:]
    private static var loadedCacheIdentities: Set<WeatherRequestIdentity> = []
    private static var discardedLegacyUnscopedCache = false

    static func cachedSnapshot(for identity: WeatherRequestIdentity) -> WeatherSnapshot? {
        if let snapshot = lastSnapshots[identity] { return snapshot }
        guard !loadedCacheIdentities.contains(identity) else { return nil }
        loadedCacheIdentities.insert(identity)
        let snapshot = loadCachedSnapshot(for: identity)
        lastSnapshots[identity] = snapshot
        return snapshot
    }

    static func cachedSnapshotIsStale(for identity: WeatherRequestIdentity) -> Bool {
        guard let snapshot = cachedSnapshot(for: identity) else { return false }
        return !isUsableCachedSnapshot(snapshot)
    }

    /// Switches the active auth boundary. Every prior provider/location task
    /// is cancelled, its waiters are released by the cancellation-aware
    /// location/provider paths, and its eventual result is disqualified by the
    /// identity check before caching or display.
    func activateContext(_ context: WeatherRequestContext) {
        guard activeContext != context else { return }
        activeContext = context
        weatherFlights.cancelAll(returning: nil)
        locationFlights.cancelAll(returning: nil)
        finishPendingLocation(nil)
        Self.discardLegacyCacheIfNeeded()
    }

    func deactivateContext() {
        activeContext = nil
        weatherFlights.cancelAll(returning: nil)
        locationFlights.cancelAll(returning: nil)
        finishPendingLocation(nil)
    }

    /// Public scoped entry point. Location is resolved before provider-flight
    /// lookup, so a move to another weather cell cannot join an older request.
    /// The app owns context activation; a stale pre-signout view is rejected
    /// here and can never reactivate its old session generation.
    func fetchCurrent(
        scope: WeatherRequestScope,
        includeLaneImpact: Bool = true,
        waiterTimeout: Duration = .seconds(15)
    ) async -> WeatherSnapshot? {
        guard activeContext == scope.context else { return nil }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: waiterTimeout)
        guard let location = await awaitLocation(
            for: scope.context,
            deadline: deadline
        ),
              LatLongParser.isValid(location.coordinate),
              !Task.isCancelled,
              activeContext == scope.context else {
            return nil
        }

        guard let key = WeatherFlightKey(
            scope: scope,
            location: location,
            includesLaneImpact: includeLaneImpact
        ) else { return nil }
        return await weatherFlights.value(
            for: key,
            deadline: deadline,
            timeoutValue: nil
        ) { [weak self] in
            guard let self else { return nil }
            let result = await self.fetchCurrentWithinDeadline(
                location: location,
                includeLaneImpact: includeLaneImpact
            )
            guard !Task.isCancelled, self.activeContext == scope.context else {
                return nil
            }
            if let result {
                Self.storeLastSnapshot(result, for: scope.identity)
            }
            return result
        }
    }

    private func awaitLocation(
        for context: WeatherRequestContext,
        deadline: ContinuousClock.Instant
    ) async -> CLLocation? {
        await locationFlights.value(
            for: context,
            deadline: deadline,
            timeoutValue: nil
        ) { [weak self] in
            guard let self else { return nil }
            let location = await self.requestLocationIfNeeded()
            guard !Task.isCancelled, self.activeContext == context else { return nil }
            return location
        }
    }

    private static let cachedSnapshotMaxAge: TimeInterval = 90 * 60
    private static let cachedSnapshotFileStem = "WeatherSnapshot.last-real.v2"
    private static let legacyCachedSnapshotFileName = "WeatherSnapshot.last-real.json"
    private static let legacyDefaultsKey = "eusotrip.weather.lastGoodSnapshot.v1"

    private static func storeLastSnapshot(
        _ snapshot: WeatherSnapshot,
        for identity: WeatherRequestIdentity
    ) {
        let cached = cacheableSnapshot(snapshot)
        lastSnapshots[identity] = cached
        loadedCacheIdentities.insert(identity)
        persistCachedSnapshot(cached, for: identity)
    }

    private static func cacheableSnapshot(_ snapshot: WeatherSnapshot) -> WeatherSnapshot {
        var cached = snapshot
        cached.laneImpact = nil
        return cached
    }

    private static func isUsableCachedSnapshot(_ snapshot: WeatherSnapshot) -> Bool {
        guard let observedAt = snapshot.observedAt else { return false }
        return Date().timeIntervalSince(observedAt) <= cachedSnapshotMaxAge
    }

    /// Application Support (NON-purgeable) — Caches can be purged by iOS
    /// under disk pressure, which silently broke the cold-launch guarantee.
    private static func cacheURL(for identity: WeatherRequestIdentity) -> URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return dir
            .appendingPathComponent("EusoTrip", isDirectory: true)
            .appendingPathComponent("\(cachedSnapshotFileStem).\(identity.cacheNamespace).json")
    }

    private static func legacyCachesURL() -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return caches
            .appendingPathComponent("EusoTrip", isDirectory: true)
            .appendingPathComponent(legacyCachedSnapshotFileName)
    }

    private static func legacyApplicationSupportURL() -> URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return dir
            .appendingPathComponent("EusoTrip", isDirectory: true)
            .appendingPathComponent(legacyCachedSnapshotFileName)
    }

    private static func discardLegacyCacheIfNeeded() {
        guard !discardedLegacyUnscopedCache else { return }
        discardedLegacyUnscopedCache = true
        if let url = legacyApplicationSupportURL() { try? FileManager.default.removeItem(at: url) }
        if let url = legacyCachesURL() { try? FileManager.default.removeItem(at: url) }
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
    }

    private static func loadCachedSnapshot(
        for identity: WeatherRequestIdentity
    ) -> WeatherSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let url = cacheURL(for: identity),
              let data = try? Data(contentsOf: url),
              let snapshot = try? decoder.decode(WeatherSnapshot.self, from: data) else {
            return nil
        }
        let cached = cacheableSnapshot(snapshot)
        if snapshot.laneImpact != nil { persistCachedSnapshot(cached, for: identity) }
        return cached
    }

    private static func persistCachedSnapshot(
        _ snapshot: WeatherSnapshot,
        for identity: WeatherRequestIdentity
    ) {
        guard let url = cacheURL(for: identity) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("[WeatherService] Could not persist last real weather snapshot — \(error.localizedDescription)")
        }
    }

    private enum ProviderRaceResult: @unchecked Sendable {
        case provider(WeatherSnapshot?)
        case deadline
    }

    /// Provider work owns a real cancellation deadline. The losing child is
    /// cancelled and structurally drained before this function returns.
    private func fetchCurrentWithinDeadline(
        location: CLLocation,
        includeLaneImpact: Bool
    ) async -> WeatherSnapshot? {
        await withTaskGroup(of: ProviderRaceResult.self) { group in
            group.addTask { [weak self] in
                guard let self else { return .provider(nil) }
                return .provider(await self.fetchCurrentUncached(
                    location: location,
                    includeLaneImpact: includeLaneImpact
                ))
            }
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: 12_000_000_000)
                    return .deadline
                } catch {
                    return .deadline
                }
            }
            let first = await group.next() ?? .deadline
            group.cancelAll()
            while await group.next() != nil { }
            guard !Task.isCancelled else { return nil }
            if case .provider(let snapshot) = first { return snapshot }
            return nil
        }
    }

    private func fetchCurrentUncached(
        location: CLLocation,
        includeLaneImpact: Bool
    ) async -> WeatherSnapshot? {

        // Ambient authority chain: on-device WeatherKit, then the server's
        // WeatherKit endpoint with a visibly attributed OpenWeather failover.
        // HERE is reserved for lane/route weather; NWS/Open-Meteo are not
        // silently substituted for home/current conditions.
        //
        // PRIMARY: on-device Apple WeatherKit — the SAME source the iPhone
        // Weather app reads, so the home card matches it (current temp,
        // condition, today's REAL high/low). The App ID's WEATHERKIT
        // capability is enabled (ASC-verified 2026-07-08); no weather API
        // key ever ships in the iOS bundle — the entitlement authenticates.
        //
        // FALLBACK 1: the server (weather.byLatLon), WeatherKit-backed
        // server-side (PR #101) via its own JWT. It reliably carries the
        // full daily strip when the on-device path throws (codes 2/3/4/7 —
        // signing/provisioning nuances on some TestFlight installs). NOTE:
        // the server has its own WeatherKit → attributed failover chain and returns
        // the provider that actually answered. No fabricated reading or silent
        // provider blend is accepted at any step.
        let placemark: CLPlacemark?
        do {
            placemark = try await reverseGeocode(location)
        } catch {
            guard !Task.isCancelled else { return nil }
            placemark = nil
        }
        guard !Task.isCancelled else { return nil }
        do {
            let weather = try await weatherService.weather(for: location)
            guard !Task.isCancelled else { return nil }
            guard var snap = Self.compose(
                weather: weather,
                placemark: placemark,
                location: location
            ) else {
                throw URLError(.cannotParseResponse)
            }
            // Lane Impact rides EVERY provider path (adversarial-verify
            // 2026-07-09): it's an independent proc (weather.laneImpactActive),
            // best-effort, nil on failure — previously it was only fetched on
            // the server-fallback path, so the panel was dead whenever
            // on-device WeatherKit succeeded (the normal case).
            if includeLaneImpact {
                snap.laneImpact = await fetchLaneImpact()
                guard !Task.isCancelled else { return nil }
            }
            return snap
        } catch {
            guard !Task.isCancelled else { return nil }
            // Surface the FULL error in every build (not just DEBUG) so a
            // misconfigured signing / entitlement / portal-capability
            // failure is visible in production crash logs / Xcode
            // console — not silently masked by the fallback.
            // WeatherKit-specific failure modes we've seen:
            //   • Code 2: missing entitlement on the bundle ID
            //   • Code 3: app not signed by a team that owns the bundle
            //   • Code 4: WeatherKit not enabled on developer.apple.com
            //              for this bundle ID (user must add the
            //              capability in the dev portal — code can't fix)
            //   • Code 7: signing issue, framework not embedded
            let ns = error as NSError
            print("[WeatherService] on-device WeatherKit failed — domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription); continuing through the configured provider chain")
            // The server enforces WeatherKit → attributed OpenWeather.
            if let server = await fetchServerWeather(
                location: location,
                placemark: placemark,
                includeLaneImpact: includeLaneImpact
            ) {
                guard !Task.isCancelled else { return nil }
                return server
            }
            guard !Task.isCancelled else { return nil }
            // Do not display real weather for an unapproved provider as if it
            // were the user's authoritative ambient source. HomeWeatherWidget
            // retains last-good provider data and retries on its short backoff.
            return nil
        }
    }

    // MARK: - Server weather (WeatherKit-backed, server-proxied)

    // Wire types for the tRPC `weather.byLatLon` proc (WeatherKit-backed
    // current + hourly + 7-day daily + the single alert). All fields are
    // optional so a partial/honest server payload (missing key → "no
    // data") decodes cleanly and the client falls back rather than
    // synthesising. Field names mirror the server's normalised shape.
    private struct ServerWeather: Decodable {
        // byLatLon emits { source, fetchedAt, weatherCode, current{}, hourly[],
        // daily[], alerts[] } in the canonical METRIC NormalizedWeather shape
        // (°C / km/h / km) — the SAME shape the web Weather.tsx reads. We
        // convert to imperial in the mapping below.
        let source: String?
        let fetchedAt: String?
        let weatherCode: Int?
        let current: Current?
        let hourly: [Hour]?
        let daily: [Day]?
        let alerts: [Alert]?
        let nextHour: NextHour?

        struct Current: Decodable {
            let tempC: Double?
            let feelsC: Double?
            let condition: String?
            let icon: String?
            let uv: Double?
            let windKph: Double?
            let humidity: Double?
            let weatherCode: Int?
            let visibilityKm: Double?
            let windGustKph: Double?
            let precipPct: Double?
        }
        struct Hour: Decodable {
            let t: String?
            let tempC: Double?
            let precipPct: Double?
            let condition: String?
            let weatherCode: Int?
            let windKph: Double?
            let windGustKph: Double?
            let visibilityKm: Double?
            let uv: Double?
            let precipMm: Double?
            let precipType: String?
        }
        struct Day: Decodable {
            let d: String?
            let hi: Double?
            let lo: Double?
            let condition: String?
            let precipPct: Double?
            let sunrise: String?
            let sunset: String?
            let weatherCode: Int?
        }
        struct Alert: Decodable {
            let id: String?
            let title: String?
            let severity: String?
            let start: String?
            let end: String?
            let description: String?
            let area: String?
            let detailsUrl: String?
            let source: String?
            let urgency: String?
            let responses: [String]?
        }
        struct NextHour: Decodable {
            let forecastStart: String?
            let forecastEnd: String?
            let minutes: [Minute]?
            let summary: [Summary]?

            struct Minute: Decodable {
                let t: String?
                let precipPct: Double?
                let precipIntensityMmPerHour: Double?
            }
            struct Summary: Decodable {
                let start: String?
                let end: String?
                let precipPct: Double?
                let precipIntensityMmPerHour: Double?
                let precipitationType: String?
            }
        }
    }

    private struct ByLatLonInput: Encodable {
        let lat: Double
        let lon: Double
        let units: String
        let preferredSource: String
    }

    /// Fetch the WeatherKit-backed snapshot via the tRPC proxy. Returns
    /// `nil` on ANY failure (server unreachable, key absent → server
    /// returns no data, decode error) so `fetchCurrent()` retains last-good
    /// data and retries. Never fabricates: a nil
    /// `tempF` from the server (no data) yields `nil` here, not a zero.
    private func fetchServerWeather(
        location: CLLocation,
        placemark: CLPlacemark?,
        includeLaneImpact: Bool
    ) async -> WeatherSnapshot? {
        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude

        let server: ServerWeather
        do {
            server = try await EusoTripAPI.shared.query(
                "weather.byLatLon",
                input: ByLatLonInput(
                    lat: lat,
                    lon: lng,
                    units: "imperial",
                    preferredSource: "weatherkit"
                )
            )
        } catch {
            guard !Task.isCancelled else { return nil }
            // Server down, proc not deployed yet, or key-absent →
            // "no data". Honest fall-through, not a fabricated card.
            print("[WeatherService] weather.byLatLon unavailable — \(error.localizedDescription)")
            return nil
        }

        // The native ambient contract accepts only the server providers that
        // belong in this chain. A stale deployment must never turn HERE, NWS,
        // Open-Meteo, or an unknown tag into home/current weather merely because
        // the payload otherwise decodes. OpenWeather is an explicit, visible
        // server failover; WeatherKit remains authoritative.
        let ambientSource: WeatherSnapshot.DataSource
        switch (server.source ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
        case "weatherkit":
            ambientSource = .weatherKit
        case "openweather":
            ambientSource = .openWeather
        default:
            let rejectedSource = server.source ?? "missing"
            print("[WeatherService] rejected unapproved ambient provider source=\(rejectedSource)")
            return nil
        }

        // Require a real current temperature + condition. Without these
        // the server had no Apple WeatherKit data (key absent / upstream
        // failure) and we MUST fall back rather than render an empty
        // shell that looks live.
        guard let cur = server.current,
              let tC = cur.tempC,
              let windKph = cur.windKph,
              tC.isFinite,
              windKph.isFinite else {
            return nil
        }
        let code = cur.weatherCode ?? Self.serverWeatherCode(condition: cur.condition, icon: cur.icon)
        // byLatLon is metric (the web reads the same shape) → convert here.
        func cToF(_ c: Double) -> Double { c * 9.0 / 5.0 + 32.0 }
        func kphToMph(_ k: Double) -> Double { k * 0.621371 }
        func kmToMi(_ k: Double) -> Double { k * 0.621371 }
        guard
            let tempF = WeatherNumeric.roundedInt(cToF(tC), allowed: WeatherNumeric.temperatureF),
            let windMph = WeatherNumeric.roundedInt(kphToMph(windKph), allowed: WeatherNumeric.windMph)
        else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
        func parseDate(_ s: String?) -> Date? {
            guard let s else { return nil }
            return iso.date(from: s) ?? isoPlain.date(from: s)
        }

        // ── DATA-ACCURACY: the authoritative weatherCode is GROUND TRUTH ──
        //
        // Founder report: the home card read "Fog/Mist 34%" while Apple
        // Weather showed "Thunderstorm 100%" at the same point/time. Root
        // cause: a derived/coarse condition STRING (visibility- or
        // humidity-flavoured "Fog/Mist" from an upstream that aggregated a
        // wide cell) was being shown over a real SEVERE numeric code. The
        // numeric `weatherCode` is the canonical observation — when it
        // names a severe/authoritative condition the code's label WINS, so
        // the headline can never coarsen a thunderstorm down to fog. For
        // non-severe codes we still honour the server's nicer human string.
        let condition = Self.canonicalCondition(code: code, serverString: cur.condition)

        // City — prefer the reverse-geocoded placemark (matches the rest
        // of the pipeline), else the server's, else honest fallback.
        let city: String = {
            if let p = placemark {
                let loc = p.locality ?? p.subAdministrativeArea ?? p.administrativeArea ?? "Nearby"
                if let state = p.administrativeArea, state.count <= 3, state != loc {
                    return "\(loc), \(state)"
                }
                return loc
            }
            return "Current location"
        }()

        let hourly: [WeatherSnapshot.HourlyForecast] = (server.hourly ?? []).prefix(8).compactMap { h in
            guard
                let date = parseDate(h.t),
                let t = h.tempC,
                let hourTempF = WeatherNumeric.roundedInt(
                    cToF(t),
                    allowed: WeatherNumeric.temperatureF
                )
            else { return nil }
            let hourCode = h.weatherCode ?? Self.serverWeatherCode(condition: h.condition, icon: nil)
            return WeatherSnapshot.HourlyForecast(
                date: date,
                tempF: hourTempF,
                symbol: Self.symbolForCode(for: hourCode),
                precipChancePct: h.precipPct.flatMap {
                    WeatherNumeric.roundedInt($0, allowed: WeatherNumeric.percent)
                },
                windMph: h.windKph.flatMap {
                    WeatherNumeric.roundedInt(kphToMph($0), allowed: WeatherNumeric.windMph)
                },
                weatherCode: hourCode
            )
        }

        let nextHourPrecip: WeatherSnapshot.NextHourPrecip? = {
            guard let next = server.nextHour else { return nil }
            let minutes = (next.minutes ?? []).compactMap { minute -> WeatherSnapshot.NextHourPrecip.Minute? in
                guard let date = parseDate(minute.t) else { return nil }
                return WeatherSnapshot.NextHourPrecip.Minute(
                    date: date,
                    precipChancePct: minute.precipPct.flatMap {
                        WeatherNumeric.roundedInt($0, allowed: WeatherNumeric.percent)
                    },
                    intensityMmPerHour: WeatherNumeric.nonnegativeFinite(
                        minute.precipIntensityMmPerHour
                    )
                )
            }
            let summaries = (next.summary ?? []).compactMap { summary -> WeatherSnapshot.NextHourPrecip.Summary? in
                guard let start = parseDate(summary.start) else { return nil }
                return WeatherSnapshot.NextHourPrecip.Summary(
                    start: start,
                    end: parseDate(summary.end),
                    precipChancePct: summary.precipPct.flatMap {
                        WeatherNumeric.roundedInt($0, allowed: WeatherNumeric.percent)
                    },
                    intensityMmPerHour: WeatherNumeric.nonnegativeFinite(
                        summary.precipIntensityMmPerHour
                    ),
                    precipitationType: summary.precipitationType
                )
            }
            guard !minutes.isEmpty || !summaries.isEmpty else { return nil }
            return WeatherSnapshot.NextHourPrecip(
                forecastStart: parseDate(next.forecastStart),
                forecastEnd: parseDate(next.forecastEnd),
                minutes: minutes,
                summaries: summaries
            )
        }()

        let weekdayFmt = DateFormatter()
        weekdayFmt.locale = .current
        weekdayFmt.dateFormat = "EEE"
        let cal = Calendar.current
        let daily: [WeatherSnapshot.DailyForecast] = (server.daily ?? []).prefix(7).compactMap { d in
            guard let date = parseDate(d.d) ?? Self.dayOnly(d.d),
                  let hi = d.hi,
                  let lo = d.lo,
                  let highF = WeatherNumeric.roundedInt(
                    cToF(hi),
                    allowed: WeatherNumeric.temperatureF
                  ),
                  let lowF = WeatherNumeric.roundedInt(
                    cToF(lo),
                    allowed: WeatherNumeric.temperatureF
                  ) else { return nil }
            let label = cal.isDateInToday(date) ? "Today" : weekdayFmt.string(from: date)
            let dayCode = d.weatherCode ?? Self.serverWeatherCode(condition: d.condition, icon: nil)
            return WeatherSnapshot.DailyForecast(
                date: date,
                weekdayLabel: label,
                highF: highF,
                lowF: lowF,
                symbol: Self.symbolForCode(for: dayCode),
                condition: d.condition ?? Self.conditionForCode(for: dayCode),
                precipChance: d.precipPct.flatMap {
                    WeatherNumeric.finite($0, allowed: 0...100).map { $0 / 100.0 }
                }
            )
        }

        let alert: WeatherSnapshot.ActiveAlert? = (server.alerts ?? []).first.flatMap { a in
            guard let title = a.title, !title.isEmpty else { return nil }
            return WeatherSnapshot.ActiveAlert(
                title: title,
                severity: WeatherSnapshot.AlertSeverity(capString: a.severity),
                until: parseDate(a.end),
                source: a.source,
                detailsURL: a.detailsUrl.flatMap(URL.init(string:))
            )
        }

        // Honest visibility: nil when the server omitted it (em-dash
        // doctrine) — the old `?? 10` default could suppress LOW VIS.
        let visMi: Int? = cur.visibilityKm.flatMap {
            WeatherNumeric.roundedInt(kmToMi($0), allowed: WeatherNumeric.visibilityMi)
        }

        // Accent — real alert severity wins, else freight thresholds +
        // the code family, mirroring the other paths.
        let accent: WeatherSnapshot.Accent = {
            if let sev = alert?.severity, sev >= .severe { return .warn }
            let severeCodes: Set<Int> = [8000, 4201, 6201, 7101]
            let watchCodes: Set<Int> = [4000, 4200, 4001, 5000, 5001, 5100, 5101,
                                        6000, 6001, 6200, 7000, 7102, 2000, 2100]
            if severeCodes.contains(code) || windMph >= 25 || (visMi ?? .max) <= 2 { return .warn }
            if alert != nil { return .watch }
            if watchCodes.contains(code) { return .watch }
            return .calm
        }()

        let nextAlert: String? = daily.first.map { "today · H \($0.highF)° / L \($0.lowF)°" }

        // Probability is provider evidence, not something a condition code can
        // reconstruct. Missing probability stays unavailable even when the
        // observed condition is severe.
        let serverPrecip = cur.precipPct.flatMap {
            WeatherNumeric.roundedInt($0, allowed: WeatherNumeric.percent)
        }

        var snap = WeatherSnapshot(
            city: city,
            tempF: tempF,
            windMph: windMph,
            visibilityMi: visMi,
            condition: condition,
            symbol: Self.symbolForCode(for: code),
            nextAlert: nextAlert,
            accent: accent,
            daily: daily,
            feelsLikeF: cur.feelsC.flatMap {
                WeatherNumeric.roundedInt(cToF($0), allowed: WeatherNumeric.temperatureF)
            },
            humidityPct: cur.humidity.flatMap {
                WeatherNumeric.roundedInt($0, allowed: WeatherNumeric.percent)
            },
            windGustMph: cur.windGustKph.flatMap {
                WeatherNumeric.roundedInt(kphToMph($0), allowed: WeatherNumeric.windMph)
            },
            precipChancePct: serverPrecip
                ?? nextHourPrecip?.peakMinute?.precipChancePct,
            nextHourPrecip: nextHourPrecip,
            hourly: hourly
        )
        snap.weatherCode = code

        // ── Sky-engine geometry: carry the REAL observation point ───────
        // latitude + timezone + today's sunrise/sunset so the animated
        // scene can pick the right time-of-day / season / sun-arc. Sunrise
        // and sunset come off the first (today's) server daily entry; nil
        // when the server omitted them (the snapshot helpers fall back to
        // the queried coordinate, then its resolved timezone). Never fabricated.
        snap.latitude = lat
        snap.longitude = lng
        snap.timezoneId = placemark?.timeZone?.identifier
        if let today = (server.daily ?? []).first {
            snap.sunriseAt = parseDate(today.sunrise)
            snap.sunsetAt  = parseDate(today.sunset)
        }
        snap.isNightHint = Self.serverIsNightHint(icon: cur.icon)
        // Provenance was allowlisted before any reading was composed, so this
        // assignment can never silently relabel another provider as ambient.
        snap.dataSource = ambientSource
        snap.uvIndex = cur.uv.flatMap {
            WeatherNumeric.roundedInt($0, allowed: WeatherNumeric.uvIndex)
        }
        snap.alert = alert
        // Missing provider freshness stays missing. Using receipt time here
        // would make an old upstream observation look newly observed.
        snap.observedAt = parseDate(server.fetchedAt)

        // Lane impact — best-effort; its own proc, never blocks the card.
        if includeLaneImpact { snap.laneImpact = await fetchLaneImpact() }
        return snap
    }

    // Wire types for the tRPC `weather.laneImpact` proc — per-load ETA risk
    // from HERE route weather. A partial/honest payload still decodes;
    // non-HERE or nil/empty rows never reach the live panel.
    private struct ServerLaneImpact: Decodable {
        let available: Bool?
        let loads: [ServerSegment]?
        struct ServerSegment: Decodable {
            let loadId: String?
            let sourceLoadId: Int?
            /// Per-row availability — the server marks a load it could not
            /// compute (no coords / tier absent) `available: false`; those
            /// rows must NOT render as blank Lane Impact segments.
            let available: Bool?
            /// Human load number ("LD-260615") — preferred over the raw DB
            /// id for the footer display.
            let loadNumber: String?
            let mode: String?
            let route: String?
            /// rowMeta endpoint names — the route-string fallback when the
            /// server omits the combined `route` field.
            let origin: String?
            let destination: String?
            let pickupTime: String?
            let etaDelayMin: Int?
            let riskTier: String?
            // §3 structured peakLeg { label, time } | null. Legacy
            // payloads sent `peakLeg` as a flat string; the custom
            // decoder below accepts either the object or the string form.
            let peakLeg: ServerPeakLeg?
            // §3 headline + drivers[] + recommendation{} + computedAt.
            let headline: String?
            let drivers: [ServerDriver]?
            let recommendation: ServerRecommendation?
            let computedAt: String?
            let source: String?
            // Legacy flat ESang line (older payloads).
            let esangSuggestion: String?

            struct ServerPeakLeg: Decodable {
                let label: String?
                let time: String?

                /// Accept `peakLeg` as either `{ label, time }` (§3) or a
                /// bare string ("4 PM storm cell on I-35", legacy) so a
                /// mixed-vintage server still decodes. A string becomes
                /// the `label`; the `time` stays nil and the diagram reads
                /// the riskTier for band placement.
                init(from decoder: Decoder) throws {
                    if let single = try? decoder.singleValueContainer(),
                       let s = try? single.decode(String.self) {
                        self.label = s
                        self.time = nil
                        return
                    }
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    self.label = try c.decodeIfPresent(String.self, forKey: .label)
                    self.time  = try c.decodeIfPresent(String.self, forKey: .time)
                }
                enum CodingKeys: String, CodingKey { case label, time }
            }
            struct ServerDriver: Decodable {
                let field: String?
                let value: String?
                let available: Bool?
                let unavailableReason: String?
            }
            struct ServerRecommendation: Decodable {
                let text: String?
                let action: String?
                let protects: String?
            }
        }
    }

    /// Fetch the active loads' weather-driven ETA risk. Returns `nil` on
    /// any failure (proc absent, no active loads, route tier absent) so
    /// the LANE IMPACT panel simply collapses — never seeded.
    private struct LaneImpactActiveInput: Encodable { let limit: Int }

    private func fetchLaneImpact() async -> [WeatherSnapshot.LaneImpactSegment]? {
        let resp: ServerLaneImpact
        do {
            // laneImpactActive → the caller's active loads, each a §3 LaneImpact
            // object: { available, loads:[ { loadId, mode, riskTier, headline,
            // peakLeg{label,time}, drivers[], recommendation{}, computedAt } ] }.
            // (The single-load weather.laneImpact proc requires {loadId}; the
            // home widget wants the active set, not one load.)
            resp = try await EusoTripAPI.shared.query(
                "weather.laneImpactActive",
                input: LaneImpactActiveInput(limit: 8)
            )
        } catch {
            guard !Task.isCancelled else { return nil }
            return nil
        }
        guard resp.available != false, let segs = resp.loads, !segs.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
        let routeWeatherReadAt = Date()

        let mapped: [WeatherSnapshot.LaneImpactSegment] = segs.compactMap { s in
            guard let loadId = s.loadId, !loadId.isEmpty else { return nil }
            // Drop rows the server could not compute (`available: false`) —
            // they carried no risk data and rendered as blank segments
            // exposing the internal DB id.
            guard s.available != false else { return nil }
            let displayLoadId = (s.loadNumber?.trimmingCharacters(in: .whitespacesAndNewlines))
                .flatMap { $0.isEmpty ? nil : $0 } ?? loadId
            guard !WeatherRouteDataPolicy.isSyntheticLoadIdentifier(displayLoadId),
                  WeatherRouteDataPolicy.authority(for: s.source) == .here else {
                return nil
            }
            let mode: WeatherSnapshot.LaneMode
            switch (s.mode ?? "").lowercased() {
            case "truck":  mode = .truck
            case "rail":   mode = .rail
            case "vessel": mode = .vessel
            default:       return nil
            }
            let risk: WeatherSnapshot.RiskTier = {
                switch (s.riskTier ?? "").lowercased() {
                case "severe":         return .severe
                case "elevated":       return .elevated
                case "watch":          return .watch
                default:               return .none   // "none" / "clear" / absent
                }
            }()
            let pickup = s.pickupTime.flatMap { iso.date(from: $0) ?? isoPlain.date(from: $0) }
            let computed = s.computedAt.flatMap { iso.date(from: $0) ?? isoPlain.date(from: $0) }
            guard WeatherRouteDataPolicy.isFresh(computed, at: routeWeatherReadAt) else {
                return nil
            }

            // §3 peakLeg { label, time } — only built when a real label
            // came back; never synthesised. A legacy string-only payload
            // yields a label with no time.
            let peakLeg: WeatherSnapshot.PeakLeg? = {
                guard let pl = s.peakLeg,
                      let label = pl.label?.trimmingCharacters(in: .whitespaces),
                      !label.isEmpty else { return nil }
                return WeatherSnapshot.PeakLeg(
                    label: label,
                    time: Self.laneClockLabel(pl.time)
                )
            }()

            // §3 drivers[] — the mode metric tiles. Missing provider fields
            // remain visible as explicitly unavailable, with their reason;
            // they are never promoted into a fake numeric reading.
            let drivers: [WeatherSnapshot.Driver] = (s.drivers ?? []).compactMap { d in
                guard let field = d.field?.trimmingCharacters(in: .whitespaces),
                      !field.isEmpty else { return nil }
                let value = (d.value?.trimmingCharacters(in: .whitespaces)).flatMap {
                    $0.isEmpty ? nil : $0
                } ?? ""
                let legacyAvailable = value != "—" && value != "-" && !value.isEmpty
                return WeatherSnapshot.Driver(
                    field: field,
                    value: value,
                    available: d.available ?? legacyAvailable,
                    unavailableReason: d.unavailableReason
                )
            }

            // §3 recommendation { text, action, protects } — only when
            // the server authored a real action; nil collapses the orb.
            let recommendation: WeatherSnapshot.Recommendation? = {
                guard let r = s.recommendation,
                      let action = r.action?.trimmingCharacters(in: .whitespaces),
                      !action.isEmpty else { return nil }
                return WeatherSnapshot.Recommendation(
                    text: r.text ?? "",
                    action: action,
                    protects: r.protects ?? ""
                )
            }()

            // Route string — the combined `route` when present, else built
            // from the rowMeta endpoint names (mirrors PerLoadWeatherCard's
            // bridgedSegment). Honest "" when neither is available.
            let routeString: String = {
                if let r = s.route?.trimmingCharacters(in: .whitespaces), !r.isEmpty { return r }
                let o = s.origin?.trimmingCharacters(in: .whitespaces) ?? ""
                let d = s.destination?.trimmingCharacters(in: .whitespaces) ?? ""
                if !o.isEmpty && !d.isEmpty { return "\(o) → \(d)" }
                return o
            }()
            guard !routeString.isEmpty else { return nil }

            let authenticatedSourceLoadId = s.sourceLoadId.flatMap { value in
                value > 0 ? String(value) : nil
            }

            return WeatherSnapshot.LaneImpactSegment(
                // Prefer the human load number over the internal DB id.
                loadId: displayLoadId,
                mode: mode,
                riskTier: risk,
                headline: s.headline ?? "",
                peakLeg: peakLeg,
                drivers: drivers,
                recommendation: recommendation,
                computedAt: computed,
                source: s.source,
                sourceLoadId: authenticatedSourceLoadId,
                route: routeString,
                pickupTime: pickup,
                etaDelayMin: s.etaDelayMin,
                esangSuggestion: s.esangSuggestion
            )
        }
        return mapped.isEmpty ? nil : mapped
    }

    /// Provider route payloads occasionally carry the peak timestamp as ISO
    /// instead of the display clock promised by the contract. Normalize it at
    /// the boundary so no raw wire timestamp reaches the UI.
    private static func laneClockLabel(_ raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return "" }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard let date = fractional.date(from: raw) ?? plain.date(from: raw) else {
            return raw
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Apple WeatherKit weatherCode → human phrase (mirrors the wiring map's
    /// "label" column). Used when the server omits a condition string.
    private static func conditionForCode(for code: Int) -> String {
        switch code {
        case 1000: return "Clear"
        case 1100: return "Mostly clear"
        case 1101: return "Partly cloudy"
        case 1102: return "Mostly cloudy"
        case 1001: return "Cloudy"
        case 2000: return "Fog"
        case 2100: return "Light fog"
        case 4000: return "Drizzle"
        case 4200: return "Light rain"
        case 4001: return "Rain"
        case 4201: return "Heavy rain"
        case 8000: return "Thunderstorm"
        case 5000: return "Snow"
        case 5001: return "Flurries"
        case 5100: return "Light snow"
        case 5101: return "Heavy snow"
        case 6000: return "Freezing drizzle"
        case 6001: return "Freezing rain"
        case 6200: return "Light freezing rain"
        case 6201: return "Heavy freezing rain"
        case 7000: return "Ice pellets"
        case 7101: return "Heavy ice pellets"
        case 7102: return "Light ice pellets"
        default:   return "Cloudy"
        }
    }

    // ── Condition ground-truth (the "missing thunderstorm" fix) ─────
    //
    // The numeric weatherCode is the canonical observation. These are the
    // codes whose CONDITION must never be coarsened by a derived/visibility
    // string — a real thunderstorm/heavy-rain/heavy-freezing/ice-pellet
    // reading that an aggregating upstream might otherwise label "Fog/Mist".
    // Severe codes own their label end to end so the headline matches the
    // hourly + the animated scene.
    static let severeWeatherCodes: Set<Int> = [
        8000,                 // Thunderstorm
        4201,                 // Heavy rain
        4001,                 // Rain (authoritative — not "fog")
        6201, 6001,           // Heavy / freezing rain
        7101, 7000,           // Heavy / ice pellets
        5101                  // Heavy snow
    ]

    /// Resolve the headline condition string with the numeric code as
    /// GROUND TRUTH. For a severe/authoritative code the code's canonical
    /// label always wins (so "Fog/Mist" can never shadow a thunderstorm).
    /// For benign codes the server's friendlier human string is preferred
    /// when present, falling back to the code label. Pure + allocation-free
    /// beyond the returned string.
    static func canonicalCondition(code: Int, serverString: String?) -> String {
        if severeWeatherCodes.contains(code) {
            return conditionForCode(for: code)
        }
        if let s = serverString?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
            // Guard the inverse coarsening too: a string that claims a
            // severe condition while the code says otherwise is itself
            // suspect, but the code remains authoritative either way.
            return s
        }
        return conditionForCode(for: code)
    }

        /// Apple WeatherKit weatherCode → SF Symbol (kept for the legacy compact
    /// path + accessibility; the v2 surface draws WeatherIcons off the
    /// code directly).
    private static func symbolForCode(for code: Int) -> String {
        switch code {
        case 1000:                         return "sun.max.fill"
        case 1100, 1101:                   return "cloud.sun.fill"
        case 1102, 1001:                   return "cloud.fill"
        case 2000, 2100:                   return "cloud.fog.fill"
        case 4000, 4200:                   return "cloud.drizzle.fill"
        case 4001:                         return "cloud.rain.fill"
        case 4201:                         return "cloud.heavyrain.fill"
        case 8000:                         return "cloud.bolt.rain.fill"
        case 5000, 5001, 5100, 5101:       return "cloud.snow.fill"
        case 6000, 6001, 6200, 6201,
             7000, 7101, 7102:             return "cloud.sleet.fill"
        default:                           return "cloud.fill"
        }
    }

    /// Server WeatherKit/OpenWeather fallback paths may not carry a
    /// Apple WeatherKit numeric weatherCode. Derive the closest glyph code
    /// from the live provider condition/icon so the client keeps the
    /// payload instead of discarding a valid Apple Weather response.
    private static func serverWeatherCode(condition: String?, icon: String?) -> Int {
        let text = [condition, icon]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        if text.contains("thunder") || text.contains("bolt") { return 8000 }
        if text.contains("freezing") || text.contains("sleet") || text.contains("hail") || text.contains("ice") { return 6200 }
        if text.contains("heavy") && text.contains("snow") { return 5101 }
        if text.contains("snow") || text.contains("flurr") { return 5000 }
        if text.contains("heavy") && text.contains("rain") { return 4201 }
        if text.contains("drizzle") { return 4000 }
        if text.contains("rain") || text.contains("shower") { return 4001 }
        if text.contains("fog") || text.contains("mist") || text.contains("haze") { return 2000 }
        if text.contains("partly") { return 1101 }
        if text.contains("mostly") && text.contains("clear") { return 1100 }
        if text.contains("mostly") && text.contains("cloud") { return 1102 }
        if text.contains("cloud") || text.contains("overcast") { return 1001 }
        if text.contains("clear") || text.contains("sun") { return 1000 }
        return 0
    }

    /// Day/night evidence carried by the normalized server provider. Apple
    /// Weather symbols name sun/moon/day/night; the attributed OpenWeather
    /// fallback uses the documented two-digit `d`/`n` icon suffix. Ambiguous
    /// cloud and precipitation icons stay nil so sunrise/sunset, coordinate,
    /// and location timezone decide instead.
    private static func serverIsNightHint(icon: String?) -> Bool? {
        guard let icon else { return nil }
        let value = icon
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !value.isEmpty else { return nil }
        if value.range(of: #"^\d{2}n(?:@\dx)?$"#, options: .regularExpression) != nil {
            return true
        }
        if value.range(of: #"^\d{2}d(?:@\dx)?$"#, options: .regularExpression) != nil {
            return false
        }
        return WeatherIcons.daylightHint(forSymbol: value).map { !$0 }
    }

    /// Parse a "yyyy-MM-dd" day string (Apple WeatherKit daily timestamps can
    /// arrive date-only) to local midnight.
    private static func dayOnly(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    // MARK: - NWS (api.weather.gov) — US ground-truth fallback

    /// Two-hop NWS query: POST coords → /points → forecast endpoints,
    /// then GET observations from the nearest station. NWS uses real
    /// ground stations + Doppler radar so the "thunderstorm at sunny
    /// noon" mismatch Open-Meteo causes goes away. NWS requires no
    /// API key, just a User-Agent.
    private func fetchNWS(
        location: CLLocation,
        placemark: CLPlacemark?
    ) async throws -> WeatherSnapshot {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        struct PointsResp: Decodable {
            struct Properties: Decodable {
                let observationStations: String
                let forecast: String
                let forecastHourly: String?
                let relativeLocation: RelLoc?
            }
            struct RelLoc: Decodable { let properties: RelLocProps }
            struct RelLocProps: Decodable { let city: String?; let state: String? }
            let properties: Properties
        }
        struct StationsResp: Decodable {
            struct Feature: Decodable { let id: String }
            let features: [Feature]
        }
        struct ObsResp: Decodable {
            struct Properties: Decodable {
                struct Quant: Decodable { let value: Double? }
                let temperature: Quant?
                let windSpeed: Quant?
                let windGust: Quant?
                let visibility: Quant?
                let relativeHumidity: Quant?
                let heatIndex: Quant?
                let windChill: Quant?
                let textDescription: String?
                let icon: String?
            }
            let properties: Properties
        }
        struct ForecastResp: Decodable {
            struct Properties: Decodable {
                let periods: [Period]
            }
            struct Period: Decodable {
                let name: String
                let startTime: String
                let isDaytime: Bool
                let temperature: Int?
                let temperatureUnit: String?
                let probabilityOfPrecipitation: Quant?
                let shortForecast: String?
                let icon: String?
            }
            struct Quant: Decodable { let value: Double?; let unitCode: String? }
            let properties: Properties
        }

        let headers: [String: String] = [
            "User-Agent": "EusoTrip/59 (support@eusotrip.com)",
            "Accept": "application/geo+json",
        ]

        func get<T: Decodable>(_ url: URL, as: T.Type) async throws -> T {
            var req = URLRequest(url: url)
            req.timeoutInterval = 6
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            return try JSONDecoder().decode(T.self, from: data)
        }

        let pointsURL = URL(string: "https://api.weather.gov/points/\(lat),\(lon)")!
        let points = try await get(pointsURL, as: PointsResp.self)
        let stationsURL = URL(string: points.properties.observationStations)!
        let stations = try await get(stationsURL, as: StationsResp.self)
        guard let firstStation = stations.features.first else { throw URLError(.badServerResponse) }
        let obsURL = URL(string: "\(firstStation.id)/observations/latest")!
        let obs = try await get(obsURL, as: ObsResp.self)
        let p = obs.properties

        // NWS can return a valid observation whose temperature value is
        // null. Converting the old `.nan` sentinel to Int trapped during
        // app launch in build 766. Treat an incomplete observation as an
        // unavailable legacy-provider response rather than converting NaN.
        guard
            let tempC = p.temperature?.value,
            let windKmh = p.windSpeed?.value,
            let tempF = WeatherNumeric.roundedInt(
                tempC * 9.0 / 5.0 + 32.0,
                allowed: WeatherNumeric.temperatureF
            ),
            let windMph = WeatherNumeric.roundedInt(
                windKmh * 0.621371,
                allowed: WeatherNumeric.windMph
            )
        else {
            throw URLError(.cannotParseResponse)
        }
        // NWS gives temperature in C, wind in km/h, visibility in m.
        // Honest visibility: nil when the station omitted it — the old
        // `?? 0` default read as "0 mi" and falsely tripped LOW VIS.
        let visMi: Int? = p.visibility?.value.flatMap {
            WeatherNumeric.roundedInt($0 / 1609.344, allowed: WeatherNumeric.visibilityMi)
        }
        let conditionText = p.textDescription ?? "Conditions unknown"
        let symbol = Self.nwsSymbol(for: conditionText, iconURL: p.icon)

        // Level-100 depth — humidity straight off the station; feels-like
        // from heatIndex (warm) or windChill (cold) when the station
        // reports one; gust converted km/h → mph. All nil-safe: a station
        // that omits the field yields nil and the card renders "—".
        let humidityPct: Int? = p.relativeHumidity?.value.flatMap {
            WeatherNumeric.roundedInt($0, allowed: WeatherNumeric.percent)
        }
        let feelsLikeF: Int? = {
            if let hi = p.heatIndex?.value {
                return WeatherNumeric.roundedInt(
                    hi * 9.0 / 5.0 + 32.0,
                    allowed: WeatherNumeric.temperatureF
                )
            }
            if let wc = p.windChill?.value {
                return WeatherNumeric.roundedInt(
                    wc * 9.0 / 5.0 + 32.0,
                    allowed: WeatherNumeric.temperatureF
                )
            }
            return nil
        }()
        let windGustMph: Int? = p.windGust?.value.flatMap {
            WeatherNumeric.roundedInt($0 * 0.621371, allowed: WeatherNumeric.windMph)
        }

        // Hourly band + active CAP alerts — both real NWS feeds; each
        // degrades to empty on failure without sinking the snapshot.
        async let hourlyTask = Self.fetchNWSHourly(
            hourlyURL: points.properties.forecastHourly.flatMap(URL.init(string:)),
            headers: headers
        )
        async let alertsTask = Self.fetchNWSAlerts(lat: lat, lon: lon, headers: headers)
        let hourly = await hourlyTask
        let alerts = await alertsTask
        let precipChancePct: Int? = hourly.first?.precipChancePct

        let cityFromPlacemark: String = {
            if let p = placemark {
                let loc = p.locality ?? p.subAdministrativeArea ?? p.administrativeArea ?? "Nearby"
                if let state = p.administrativeArea, state.count <= 3, state != loc {
                    return "\(loc), \(state)"
                }
                return loc
            }
            if let rl = points.properties.relativeLocation?.properties,
               let c = rl.city, let s = rl.state {
                return "\(c), \(s)"
            }
            return "Current location"
        }()

        // Fetch the 7-day / 14-period forecast and fold day+night
        // periods into 6 daily entries. NWS interleaves periods like
        // "Today" (day) / "Tonight" (night) / "Tuesday" (day) / "Tuesday
        // Night" / etc. — the day period carries the high, the night
        // period carries the low. Without this the card flipped to
        // "Forecast unavailable" any time WeatherKit failed and NWS
        // succeeded, because the prior NWS path only fetched current
        // observations and never populated `daily`.
        let daily: [WeatherSnapshot.DailyForecast] = await Self.fetchNWSDaily(
            forecastURL: URL(string: points.properties.forecast),
            headers: headers
        )

        // Use today's high/low for the card's `nextAlert` line so the
        // current conditions still ride with a forward-looking nudge
        // (matches the WeatherKit + Open-Meteo paths).
        let nextAlert: String? = {
            guard let today = daily.first else { return nil }
            return "today · H \(today.highF)° / L \(today.lowF)°"
        }()

        // Severity accent — real CAP severity wins; otherwise promote to
        // .warn on hazard text or low visibility / strong wind, .watch on
        // moderate condition (inferred from textDescription, mirroring
        // the Open-Meteo branch's logic).
        let accent: WeatherSnapshot.Accent = {
            if alerts.contains(where: { $0.severity >= .severe }) { return .warn }
            let t = conditionText.lowercased()
            let severeText = t.contains("thunder") || t.contains("blizzard") ||
                             t.contains("hurricane") || t.contains("tropical") ||
                             t.contains("freezing rain") || t.contains("ice storm")
            let watchText  = t.contains("rain") || t.contains("snow") ||
                             t.contains("fog") || t.contains("haze") ||
                             t.contains("drizzle") || t.contains("flurr")
            if severeText || windMph >= 25 || (visMi ?? .max) <= 2 { return .warn }
            if watchText || alerts.contains(where: { $0.severity == .moderate }) { return .watch }
            return .calm
        }()

        var snap = WeatherSnapshot(
            city: cityFromPlacemark,
            tempF: tempF,
            windMph: windMph,
            visibilityMi: visMi,
            condition: conditionText,
            symbol: symbol,
            nextAlert: nextAlert,
            accent: accent,
            daily: daily,
            feelsLikeF: feelsLikeF,
            humidityPct: humidityPct,
            windGustMph: windGustMph,
            precipChancePct: precipChancePct,
            hourly: hourly,
            alerts: alerts
        )
        // v2: name the real provider (NWS, NOT Apple WeatherKit) + infer a
        // weatherCode from the symbol so the custom glyph still lights.
        // NWS is ground-station truth and `nwsSymbol` already resolves
        // thunder-first, so the inferred code never coarsens a storm to
        // fog on this path.
        snap.dataSource = .nws
        snap.weatherCode = WeatherIcons.code(forSymbol: symbol)
        snap.observedAt = Date()
        // Sky-engine geometry — the real coordinate + timezone. NWS's
        // current/forecast feeds don't carry sunrise/sunset, so those stay
        // nil and the snapshot helpers use the queried coordinate, then its
        // resolved timezone when coordinate calculation is unavailable.
        snap.latitude = lat
        snap.longitude = lon
        snap.timezoneId = placemark?.timeZone?.identifier
        if let top = alerts.max(by: { $0.severity.rank < $1.severity.rank }) {
            snap.alert = .init(title: top.event, severity: top.severity, until: top.endsAt)
        }
        return snap
    }

    /// Next-12-hours band from NWS `forecastHourly`. Returns `[]` on
    /// any failure so the snapshot still ships without an hourly band
    /// (the card collapses the strip — no fabricated hours).
    private static func fetchNWSHourly(
        hourlyURL: URL?,
        headers: [String: String]
    ) async -> [WeatherSnapshot.HourlyForecast] {
        guard let hourlyURL else { return [] }
        struct HourlyResp: Decodable {
            struct Properties: Decodable { let periods: [Period] }
            struct Period: Decodable {
                let startTime: String
                let isDaytime: Bool?
                let temperature: Int?
                let temperatureUnit: String?
                let probabilityOfPrecipitation: Quant?
                let windSpeed: String?
                let shortForecast: String?
                let icon: String?
            }
            struct Quant: Decodable { let value: Double? }
            let properties: Properties
        }

        var req = URLRequest(url: hourlyURL)
        req.timeoutInterval = 6
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        guard
            let (data, resp) = try? await URLSession.shared.data(for: req),
            let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let payload = try? JSONDecoder().decode(HourlyResp.self, from: data)
        else { return [] }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let cutoff = Date().addingTimeInterval(-1800)

        return payload.properties.periods
            .compactMap { p -> WeatherSnapshot.HourlyForecast? in
                guard
                    let date = iso.date(from: p.startTime),
                    date >= cutoff,
                    let t = p.temperature
                else { return nil }
                // NWS hourly windSpeed arrives as a display string
                // ("10 mph") — parse the leading integer; nil when absent.
                let wind: Int? = p.windSpeed
                    .flatMap { $0.split(separator: " ").first }
                    .flatMap { Int($0) }
                    .flatMap { WeatherNumeric.validatedInt($0, allowed: WeatherNumeric.windMph) }
                let convertedTemperature = (p.temperatureUnit ?? "F").uppercased() == "C"
                    ? Double(t) * 9.0 / 5.0 + 32.0
                    : Double(t)
                guard let tempF = WeatherNumeric.roundedInt(
                    convertedTemperature,
                    allowed: WeatherNumeric.temperatureF
                ) else { return nil }
                return WeatherSnapshot.HourlyForecast(
                    date: date,
                    tempF: tempF,
                    symbol: nwsSymbol(for: p.shortForecast ?? "", iconURL: p.icon),
                    precipChancePct: p.probabilityOfPrecipitation?.value.flatMap {
                        WeatherNumeric.roundedInt($0, allowed: WeatherNumeric.percent)
                    },
                    windMph: wind,
                    isDaylightHint: p.isDaytime
                )
            }
            .prefix(12)
            .map { $0 }
    }

    /// Active CAP bulletins for the point from api.weather.gov/alerts.
    /// Real NWS severity vocabulary — Minor/Moderate/Severe/Extreme.
    /// Returns `[]` on failure (no alerts ≠ fabricated calm; the card
    /// simply shows no ribbon).
    private static func fetchNWSAlerts(
        lat: Double,
        lon: Double,
        headers: [String: String]
    ) async -> [WeatherSnapshot.SevereAlert] {
        struct AlertsResp: Decodable {
            struct Feature: Decodable {
                let id: String?
                let properties: Props
            }
            struct Props: Decodable {
                let event: String?
                let headline: String?
                let severity: String?
                let ends: String?
                let expires: String?
                let senderName: String?
            }
            let features: [Feature]
        }
        guard let url = URL(string: "https://api.weather.gov/alerts/active?point=\(lat),\(lon)") else {
            return []
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        guard
            let (data, resp) = try? await URLSession.shared.data(for: req),
            let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let payload = try? JSONDecoder().decode(AlertsResp.self, from: data)
        else { return [] }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        return payload.features.compactMap { f -> WeatherSnapshot.SevereAlert? in
            guard let event = f.properties.event, !event.isEmpty else { return nil }
            let ends = (f.properties.ends ?? f.properties.expires).flatMap { iso.date(from: $0) }
            return WeatherSnapshot.SevereAlert(
                event: event,
                severity: WeatherSnapshot.AlertSeverity(capString: f.properties.severity),
                headline: f.properties.headline,
                endsAt: ends,
                source: f.properties.senderName ?? "National Weather Service",
                detailsURL: f.id.flatMap(URL.init(string:))
            )
        }
        .sorted { $0.severity.rank > $1.severity.rank }
    }

    /// Fold NWS's interleaved day/night period list into 6 daily
    /// entries. Returns `[]` on any error so the surrounding NWS path
    /// still ships a usable current-observation snapshot — empty
    /// `daily` triggers the WeatherCard's neutral fallback rather than
    /// the entire fetch failing.
    private static func fetchNWSDaily(
        forecastURL: URL?,
        headers: [String: String]
    ) async -> [WeatherSnapshot.DailyForecast] {
        guard let forecastURL else { return [] }
        struct ForecastResp: Decodable {
            struct Properties: Decodable {
                let periods: [Period]
            }
            struct Period: Decodable {
                let name: String
                let startTime: String
                let isDaytime: Bool
                let temperature: Int?
                let temperatureUnit: String?
                let probabilityOfPrecipitation: Quant?
                let shortForecast: String?
                let icon: String?
            }
            struct Quant: Decodable { let value: Double?; let unitCode: String? }
            let properties: Properties
        }

        var req = URLRequest(url: forecastURL)
        req.timeoutInterval = 6
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let payload: ForecastResp
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return [] }
            payload = try JSONDecoder().decode(ForecastResp.self, from: data)
        } catch {
            guard !Task.isCancelled else { return [] }
            return []
        }

        // ISO8601 with offset — NWS startTime examples: "2026-04-27T06:00:00-05:00"
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let dayKeyFmt = DateFormatter()
        dayKeyFmt.locale = Locale(identifier: "en_US_POSIX")
        dayKeyFmt.dateFormat = "yyyy-MM-dd"

        let weekdayFmt = DateFormatter()
        weekdayFmt.locale = .current
        weekdayFmt.dateFormat = "EEE"

        // Bucket periods by local date, tracking which side carried the
        // day vs night reading. NWS guarantees day's temperature is the
        // high, night's is the low, but not every bucket has both
        // (today's bucket may only have a night period if it's already
        // afternoon).
        struct Acc {
            var date: Date
            var highF: Int?
            var lowF: Int?
            var symbol: String = "cloud.fill"
            var condition: String = "Mixed"
            var precipChance: Double?
        }
        var byDay: [(key: String, acc: Acc)] = []
        for p in payload.properties.periods {
            guard let date = iso.date(from: p.startTime) else { continue }
            let key = dayKeyFmt.string(from: date)
            if let idx = byDay.firstIndex(where: { $0.key == key }) {
                if p.isDaytime {
                    if let t = p.temperature { byDay[idx].acc.highF = t }
                    byDay[idx].acc.symbol    = nwsSymbol(for: p.shortForecast ?? "", iconURL: p.icon)
                    byDay[idx].acc.condition = p.shortForecast ?? byDay[idx].acc.condition
                } else {
                    if let t = p.temperature { byDay[idx].acc.lowF = t }
                }
                if let pop = WeatherNumeric.finite(
                    p.probabilityOfPrecipitation?.value,
                    allowed: 0...100
                ), byDay[idx].acc.precipChance == nil {
                    byDay[idx].acc.precipChance = pop / 100.0
                }
            } else {
                var acc = Acc(date: date)
                if p.isDaytime {
                    if let t = p.temperature { acc.highF = t }
                    acc.symbol    = nwsSymbol(for: p.shortForecast ?? "", iconURL: p.icon)
                    acc.condition = p.shortForecast ?? acc.condition
                } else {
                    if let t = p.temperature { acc.lowF = t }
                    acc.symbol    = nwsSymbol(for: p.shortForecast ?? "", iconURL: p.icon)
                    acc.condition = p.shortForecast ?? acc.condition
                }
                if let pop = WeatherNumeric.finite(
                    p.probabilityOfPrecipitation?.value,
                    allowed: 0...100
                ) {
                    acc.precipChance = pop / 100.0
                }
                byDay.append((key: key, acc: acc))
            }
        }

        let cal = Calendar.current
        return byDay.prefix(6).compactMap { entry -> WeatherSnapshot.DailyForecast? in
            guard
                let high = WeatherNumeric.validatedInt(
                    entry.acc.highF,
                    allowed: WeatherNumeric.temperatureF
                ),
                let low = WeatherNumeric.validatedInt(
                    entry.acc.lowF,
                    allowed: WeatherNumeric.temperatureF
                )
            else { return nil }
            let label = cal.isDateInToday(entry.acc.date) ? "Today" : weekdayFmt.string(from: entry.acc.date)
            return WeatherSnapshot.DailyForecast(
                date: entry.acc.date,
                weekdayLabel: label,
                highF: high,
                lowF: low,
                symbol: entry.acc.symbol,
                condition: entry.acc.condition,
                precipChance: entry.acc.precipChance
            )
        }
    }

    /// Map NWS textDescription / icon URL → SF Symbol so the weather
    /// card glyph matches the dashboard's symbol vocabulary.
    private static func nwsSymbol(for text: String, iconURL: String?) -> String {
        let t = text.lowercased()
        if t.contains("thunder") { return "cloud.bolt.rain" }
        if t.contains("snow") || t.contains("flurr") { return "cloud.snow.fill" }
        if t.contains("rain") || t.contains("shower") { return "cloud.rain.fill" }
        if t.contains("drizzle") { return "cloud.drizzle.fill" }
        if t.contains("fog") || t.contains("mist") || t.contains("haze") { return "cloud.fog.fill" }
        if t.contains("cloud") || t.contains("overcast") { return "cloud.fill" }
        if t.contains("partly") || t.contains("mostly clear") { return "cloud.sun.fill" }
        if t.contains("clear") || t.contains("sunny") || t.contains("fair") { return "sun.max.fill" }
        return "cloud.fill"
    }

    // MARK: - Legacy Open-Meteo adapter (not in the ambient authority chain)

    /// Retained only for decoding/migration compatibility. Production ambient
    /// weather does not call this adapter; WeatherKit is authoritative and the
    /// server may use only its visibly attributed OpenWeather failover.
    private func fetchOpenMeteo(
        location: CLLocation,
        placemark: CLPlacemark?
    ) async throws -> WeatherSnapshot {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,wind_gusts_10m,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "visibility,temperature_2m,weather_code,precipitation_probability,wind_speed_10m,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max,sunrise,sunset"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "wind_speed_unit", value: "mph"),
            URLQueryItem(name: "forecast_days", value: "6"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = comps.url else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let payload = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)

        // City — mirror the WeatherKit path's locality-preference order.
        let city: String = {
            if let p = placemark {
                let loc = p.locality ?? p.subAdministrativeArea ?? p.administrativeArea ?? "Nearby"
                if let state = p.administrativeArea, state.count <= 3, state != loc {
                    return "\(loc), \(state)"
                }
                return loc
            }
            // Geolocation unavailable — never leak a hardcoded city name.
            // "Current location" is the honest fallback whether the GPS
            // fix is approximate or missing entirely.
            return "Current location"
        }()

        guard
            let tempF = WeatherNumeric.roundedInt(
                payload.current.temperature_2m,
                allowed: WeatherNumeric.temperatureF
            ),
            let windMph = WeatherNumeric.roundedInt(
                payload.current.wind_speed_10m,
                allowed: WeatherNumeric.windMph
            )
        else { throw URLError(.cannotParseResponse) }

        // Visibility — Open-Meteo ships this on hourly (meters). Prefer the
        // current hour if the timestamps align; otherwise first available.
        // Nil when the payload omitted it (em-dash doctrine — never a
        // fabricated 10-mile default).
        let visibilityMi: Int? = {
            let metersCandidate: Double? = {
                guard let times = payload.hourly?.time,
                      let values = payload.hourly?.visibility,
                      !values.isEmpty else { return nil }
                let now = Date()
                let df = DateFormatter()
                df.locale = Locale(identifier: "en_US_POSIX")
                df.timeZone = TimeZone(identifier: payload.timezone ?? "UTC")
                df.dateFormat = "yyyy-MM-dd'T'HH:mm"
                if let bestIdx = times.indices.min(by: { a, b in
                    let da = df.date(from: times[a]) ?? .distantPast
                    let db = df.date(from: times[b]) ?? .distantPast
                    return abs(da.timeIntervalSince(now)) < abs(db.timeIntervalSince(now))
                }), bestIdx < values.count {
                    return values[bestIdx]
                }
                return values.first
            }()
            return metersCandidate.flatMap {
                WeatherNumeric.roundedInt($0 / 1609.34, allowed: WeatherNumeric.visibilityMi)
            }
        }()

        // DATA-ACCURACY: Open-Meteo aggregates multiple models, so WMO 95
        // ("Thunderstorm") can fire for a single cell anywhere in a wide
        // coverage area even when the driver's point is outside it — the
        // mirror of the founder's headline mismatch. When 95/96/99 lands
        // with a near-zero precipitation probability at the point, treat it
        // as a scattered/cloudy reading rather than a hard thunderstorm.
        // We never UPGRADE here (no fabricated storm); we only soften an
        // over-eager aggregate when its own precip says the point is dry.
        let omPointPrecip: Int? = Self.composeOpenMeteoHourly(payload: payload).first?.precipChancePct
        let effectiveWMO: Int = {
            let raw = payload.current.weather_code
            if (raw == 95 || raw == 96 || raw == 99), (omPointPrecip ?? 0) < 30 {
                return 3   // overcast — honest "unsettled but not at-point storm"
            }
            return raw
        }()
        let (condition, symbol) = Self.openMeteoCondition(for: effectiveWMO)

        // Next-alert line — today's H/L pulled from daily.
        let nextAlert: String? = {
            guard
                let hi = payload.daily.temperature_2m_max.first,
                let lo = payload.daily.temperature_2m_min.first,
                let highF = WeatherNumeric.roundedInt(hi, allowed: WeatherNumeric.temperatureF),
                let lowF = WeatherNumeric.roundedInt(lo, allowed: WeatherNumeric.temperatureF)
            else { return nil }
            return "today · H \(highF)° / L \(lowF)°"
        }()

        // Accent — map WMO code + wind/vis thresholds to our three-level scale.
        let accent: WeatherSnapshot.Accent = {
            let code = payload.current.weather_code
            let hazardousWind = windMph >= 25
            let lowVis = (visibilityMi ?? .max) <= 2
            let severe: Set<Int> = [65, 67, 75, 82, 86, 95, 96, 99] // heavy rain/snow, thunder
            let watch: Set<Int> = [45, 48, 51, 53, 55, 56, 57, 61, 63, 66, 71, 73, 77, 80, 81, 85]
            if severe.contains(code) || hazardousWind || lowVis { return .warn }
            if watch.contains(code) { return .watch }
            return .calm
        }()

        // Pull the 6-day daily block into driver-facing entries. The
        // weekday label is localized against the IANA timezone Open-Meteo
        // resolves for the coordinate, so drivers crossing timezones
        // during a haul still see the right day chip on each card.
        let daily: [WeatherSnapshot.DailyForecast] = Self.composeOpenMeteoDaily(
            payload: payload
        )

        // Level-100 depth — feels-like / humidity / gust from the
        // `current` block; hourly band from the parallel hourly arrays
        // starting at the slot nearest now. Open-Meteo ships no CAP
        // bulletins, so `alerts` stays honestly empty on this path.
        let feelsLikeF: Int? = payload.current.apparent_temperature.flatMap {
            WeatherNumeric.roundedInt($0, allowed: WeatherNumeric.temperatureF)
        }
        let humidityPct: Int? = payload.current.relative_humidity_2m.flatMap {
            WeatherNumeric.roundedInt($0, allowed: WeatherNumeric.percent)
        }
        let windGustMph: Int? = payload.current.wind_gusts_10m.flatMap {
            WeatherNumeric.roundedInt($0, allowed: WeatherNumeric.windMph)
        }
        let hourly: [WeatherSnapshot.HourlyForecast] = Self.composeOpenMeteoHourly(payload: payload)
        let precipChancePct: Int? = hourly.first?.precipChancePct

        // 75th firing: `approximate` is always false now — the Dallas
        // fallback was removed, so we only reach this path for the
        // driver's real resolved coordinate.
        var snap = WeatherSnapshot(
            city: city,
            tempF: tempF,
            windMph: windMph,
            visibilityMi: visibilityMi,
            condition: condition,
            symbol: symbol,
            nextAlert: nextAlert,
            accent: accent,
            daily: daily,
            feelsLikeF: feelsLikeF,
            humidityPct: humidityPct,
            windGustMph: windGustMph,
            precipChancePct: precipChancePct,
            hourly: hourly
        )
        // v2: name the real provider (Open-Meteo) + infer the custom
        // glyph code from the symbol. Open-Meteo ships no CAP alerts, so
        // `alert` stays honestly nil on this path.
        snap.dataSource = .openMeteo
        snap.weatherCode = WeatherIcons.code(forSymbol: symbol)
        snap.observedAt = Date()
        // Sky-engine geometry — the real coordinate, the IANA zone
        // Open-Meteo resolved (timezone=auto), and today's local sun pair.
        snap.latitude = lat
        snap.longitude = lon
        snap.timezoneId = placemark?.timeZone?.identifier ?? payload.timezone
        let omSunFmt = DateFormatter()
        omSunFmt.locale = Locale(identifier: "en_US_POSIX")
        omSunFmt.timeZone = TimeZone(identifier: payload.timezone ?? "UTC") ?? .current
        omSunFmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        snap.sunriseAt = payload.daily.sunrise?.first.flatMap { omSunFmt.date(from: $0) }
        snap.sunsetAt  = payload.daily.sunset?.first.flatMap { omSunFmt.date(from: $0) }
        snap.isNightHint = payload.current.is_day.map { $0 == 0 }
            ?? WeatherIcons.daylightHint(forSymbol: symbol).map { !$0 }
        return snap
    }

    /// Fold Open-Meteo's parallel hourly arrays into the next-12-hours
    /// band. Index alignment is by timestamp (the same scheme the
    /// visibility lookup above uses); short arrays just truncate the
    /// band — no synthesized hours.
    private static func composeOpenMeteoHourly(
        payload: OpenMeteoResponse
    ) -> [WeatherSnapshot.HourlyForecast] {
        guard
            let times = payload.hourly?.time,
            let temps = payload.hourly?.temperature_2m,
            !times.isEmpty
        else { return [] }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: payload.timezone ?? "UTC")
        df.dateFormat = "yyyy-MM-dd'T'HH:mm"

        let cutoff = Date().addingTimeInterval(-1800)
        var out: [WeatherSnapshot.HourlyForecast] = []
        for i in times.indices {
            guard out.count < 12 else { break }
            guard
                let date = df.date(from: times[i]),
                date >= cutoff,
                temps.indices.contains(i)
            else { continue }
            let code = (payload.hourly?.weather_code?.indices.contains(i) == true)
                ? payload.hourly!.weather_code![i] : 0
            let (_, symbol) = openMeteoCondition(for: code)
            let precip: Int? = {
                guard let arr = payload.hourly?.precipitation_probability,
                      arr.indices.contains(i) else { return nil }
                return arr[i]
            }()
            let wind: Int? = {
                guard let arr = payload.hourly?.wind_speed_10m,
                      arr.indices.contains(i) else { return nil }
                return WeatherNumeric.roundedInt(arr[i], allowed: WeatherNumeric.windMph)
            }()
            guard let tempF = WeatherNumeric.roundedInt(
                temps[i],
                allowed: WeatherNumeric.temperatureF
            ) else { continue }
            out.append(WeatherSnapshot.HourlyForecast(
                date: date,
                tempF: tempF,
                symbol: symbol,
                precipChancePct: precip,
                windMph: wind,
                isDaylightHint: payload.hourly?.is_day.flatMap { values in
                    values.indices.contains(i) ? values[i] != 0 : nil
                }
            ))
        }
        return out
    }

    /// Parse the Open-Meteo daily block into our 6-day forecast array.
    /// Safe against partial payloads — if any of the parallel daily
    /// arrays are shorter than expected we just emit the entries we
    /// can verify.
    private static func composeOpenMeteoDaily(
        payload: OpenMeteoResponse
    ) -> [WeatherSnapshot.DailyForecast] {
        let daily = payload.daily
        let count = min(
            daily.time?.count ?? 0,
            daily.temperature_2m_max.count,
            daily.temperature_2m_min.count
        )
        guard count > 0 else { return [] }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: payload.timezone ?? "UTC") ?? .current
        df.dateFormat = "yyyy-MM-dd"

        let weekdayFmt = DateFormatter()
        weekdayFmt.locale = .current
        weekdayFmt.timeZone = TimeZone(identifier: payload.timezone ?? "UTC") ?? .current
        weekdayFmt.dateFormat = "EEE"

        let todayKey: String = {
            let now = DateFormatter()
            now.locale = Locale(identifier: "en_US_POSIX")
            now.timeZone = weekdayFmt.timeZone
            now.dateFormat = "yyyy-MM-dd"
            return now.string(from: Date())
        }()

        var out: [WeatherSnapshot.DailyForecast] = []
        for i in 0..<count {
            guard
                let times = daily.time,
                let date = df.date(from: times[i])
            else { continue }
            let key = times[i]
            let weekday = (key == todayKey) ? "Today" : weekdayFmt.string(from: date)
            let code = (daily.weather_code?.indices.contains(i) == true) ? daily.weather_code![i] : 0
            let (condition, symbol) = openMeteoCondition(for: code)
            let precip: Double? = {
                guard let arr = daily.precipitation_probability_max,
                      arr.indices.contains(i),
                      let v = arr[i] else { return nil }
                return Double(v) / 100.0
            }()
            guard
                let highF = WeatherNumeric.roundedInt(
                    daily.temperature_2m_max[i],
                    allowed: WeatherNumeric.temperatureF
                ),
                let lowF = WeatherNumeric.roundedInt(
                    daily.temperature_2m_min[i],
                    allowed: WeatherNumeric.temperatureF
                )
            else { continue }
            out.append(WeatherSnapshot.DailyForecast(
                date: date,
                weekdayLabel: weekday,
                highF: highF,
                lowF: lowF,
                symbol: symbol,
                condition: condition,
                precipChance: precip
            ))
        }
        return out
    }

    /// Translate an Open-Meteo WMO weather code to a human phrase and
    /// matching SF Symbol glyph.
    private static func openMeteoCondition(for code: Int) -> (String, String) {
        switch code {
        case 0:       return ("Clear", "sun.max")
        case 1:       return ("Mostly clear", "sun.max")
        case 2:       return ("Partly cloudy", "cloud.sun")
        case 3:       return ("Overcast", "cloud")
        case 45, 48:  return ("Fog", "cloud.fog")
        case 51:      return ("Light drizzle", "cloud.drizzle")
        case 53:      return ("Drizzle", "cloud.drizzle")
        case 55:      return ("Heavy drizzle", "cloud.drizzle.fill")
        case 56, 57:  return ("Freezing drizzle", "cloud.sleet")
        case 61:      return ("Light rain", "cloud.rain")
        case 63:      return ("Rain", "cloud.rain")
        case 65:      return ("Heavy rain", "cloud.heavyrain")
        case 66, 67:  return ("Freezing rain", "cloud.sleet.fill")
        case 71:      return ("Light snow", "cloud.snow")
        case 73:      return ("Snow", "cloud.snow")
        case 75:      return ("Heavy snow", "cloud.snow.fill")
        case 77:      return ("Snow grains", "cloud.snow")
        case 80:      return ("Rain showers", "cloud.rain")
        case 81:      return ("Rain showers", "cloud.rain")
        case 82:      return ("Violent showers", "cloud.heavyrain.fill")
        case 85, 86:  return ("Snow showers", "cloud.snow")
        case 95:      return ("Thunderstorm", "cloud.bolt.rain")
        case 96, 99:  return ("Thunder + hail", "cloud.bolt.rain.fill")
        default:      return ("Cloudy", "cloud")
        }
    }

    // MARK: - Open-Meteo wire types

    private struct OpenMeteoResponse: Decodable {
        let timezone: String?
        let current: Current
        let hourly: Hourly?
        let daily: Daily

        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double?
            let relative_humidity_2m: Double?
            let wind_speed_10m: Double
            let wind_gusts_10m: Double?
            let weather_code: Int
            let is_day: Int?
        }
        struct Hourly: Decodable {
            let time: [String]
            let visibility: [Double]
            let temperature_2m: [Double]?
            let weather_code: [Int]?
            let precipitation_probability: [Int?]?
            let wind_speed_10m: [Double]?
            let is_day: [Int]?
        }
        struct Daily: Decodable {
            let time: [String]?
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let weather_code: [Int]?
            let precipitation_probability_max: [Int?]?
            // Local ISO "yyyy-MM-dd'T'HH:mm" sun times (timezone=auto), one
            // per forecast day. Drives the sky-engine's day/night split.
            let sunrise: [String]?
            let sunset: [String]?
        }
    }

    // MARK: - Composition

    /// WeatherKit's TYPED `WeatherCondition` → the canonical integer code
    /// space — a Swift twin of the server's WEATHERKIT_CONDITION_TO_CODE
    /// table (weatherKit.ts), so the primary on-device path keeps the same
    /// granularity (heavy rain 4201 vs rain 4001, flurries 5001 vs snow
    /// 5000, freezing family 6xxx, ice 7xxx) the server envelope carries.
    /// Unrecognised/future cases fall back to the SF-symbol inference so
    /// the glyph still lights honestly.
    private static func code(for condition: WeatherCondition, symbol: String) -> Int {
        switch condition {
        case .clear, .hot:                                   return 1000
        case .mostlyClear, .frigid:                          return 1100
        case .partlyCloudy:                                  return 1101
        case .mostlyCloudy:                                  return 1102
        case .cloudy, .breezy, .windy:                       return 1001
        case .foggy:                                         return 2000
        case .haze, .smoky, .blowingDust:                    return 2100
        case .drizzle:                                       return 4000
        case .rain, .sunShowers:                             return 4001
        case .heavyRain:                                     return 4201
        case .flurries, .sunFlurries:                        return 5001
        case .snow, .blowingSnow:                            return 5000
        case .heavySnow, .blizzard:                          return 5101
        case .freezingDrizzle:                               return 6000
        case .freezingRain, .wintryMix:                      return 6001
        case .sleet, .hail:                                  return 7000
        case .thunderstorms, .isolatedThunderstorms,
             .scatteredThunderstorms, .strongStorms,
             .hurricane, .tropicalStorm:                     return 8000
        default:
            return WeatherIcons.code(forSymbol: symbol)
        }
    }

    private static func compose(
        weather: Weather,
        placemark: CLPlacemark?,
        location: CLLocation
    ) -> WeatherSnapshot? {
        let current = weather.currentWeather

        // City string — prefer locality, fall back to subAdministrativeArea,
        // and append the state short-code where available ("Meridian, MS").
        let city: String = {
            if let p = placemark {
                let loc = p.locality ?? p.subAdministrativeArea ?? p.administrativeArea ?? "Nearby"
                if let state = p.administrativeArea, state.count <= 3, state != loc {
                    return "\(loc), \(state)"
                }
                return loc
            }
            return "Current location"
        }()

        guard
            let tempF = WeatherNumeric.roundedInt(
                current.temperature.converted(to: .fahrenheit).value,
                allowed: WeatherNumeric.temperatureF
            ),
            let windMph = WeatherNumeric.roundedInt(
                current.wind.speed.converted(to: .milesPerHour).value,
                allowed: WeatherNumeric.windMph
            )
        else { return nil }
        let visibilityMi = WeatherNumeric.roundedInt(
            current.visibility.converted(to: .miles).value,
            allowed: WeatherNumeric.visibilityMi
        )

        // Condition line + matching SF Symbol.
        let condition = current.condition.description
        let symbol = current.symbolName

        // Next-alert line — scan the next 6 hours for the first forecast entry
        // whose condition is materially different from now, and format as
        // "Nh · <condition>". If nothing changes, use the day's summary.
        let nextAlert: String = {
            let nowCondition = current.condition
            let horizon = weather.hourlyForecast.forecast.prefix(6)
            for (i, hour) in horizon.enumerated() where hour.condition != nowCondition {
                let offset = i + 1
                return "\(offset)h · \(hour.condition.description.lowercased())"
            }
            if let today = weather.dailyForecast.first,
               let hi = WeatherNumeric.roundedInt(
                    today.highTemperature.converted(to: .fahrenheit).value,
                    allowed: WeatherNumeric.temperatureF
               ),
               let lo = WeatherNumeric.roundedInt(
                    today.lowTemperature.converted(to: .fahrenheit).value,
                    allowed: WeatherNumeric.temperatureF
               ) {
                return "today · H \(hi)° / L \(lo)°"
            }
            return nil as String? ?? ""
        }()

        // Accent — map WeatherKit severity to our three-level scale.
        let accent: WeatherSnapshot.Accent = {
            if weather.weatherAlerts?.contains(where: { $0.severity == .severe || $0.severity == .extreme }) == true {
                return .warn
            }
            let hazardousWind = windMph >= 25
            let lowVis = (visibilityMi ?? .max) <= 2
            let hazardCondition: Bool = {
                switch current.condition {
                case .thunderstorms, .heavyRain, .heavySnow, .blizzard,
                        .hurricane, .tropicalStorm, .strongStorms,
                        .freezingRain, .freezingDrizzle, .hail, .sleet, .wintryMix:
                    return true
                default:
                    return false
                }
            }()
            if hazardousWind || lowVis || hazardCondition { return .warn }

            let watchCondition: Bool = {
                switch current.condition {
                case .rain, .drizzle, .snow, .flurries, .sunShowers,
                        .foggy, .haze, .smoky, .blowingDust, .blowingSnow,
                        .scatteredThunderstorms, .isolatedThunderstorms:
                    return true
                default:
                    return false
                }
            }()
            if watchCondition { return .watch }
            return .calm
        }()

        // Pull the first 6 days of the WeatherKit daily forecast into
        // the flip-side chip row. WeatherCard lays these horizontally
        // with equal flexible widths so the row stays complete on a
        // 6.1" iPhone without fabricating a trailing day.
        let daily: [WeatherSnapshot.DailyForecast] = {
            let weekdayFmt = DateFormatter()
            weekdayFmt.locale = .current
            weekdayFmt.dateFormat = "EEE"
            let cal = Calendar.current

            return weather.dailyForecast.forecast.prefix(6).enumerated().compactMap { (i, day) in
                guard
                    let hi = WeatherNumeric.roundedInt(
                        day.highTemperature.converted(to: .fahrenheit).value,
                        allowed: WeatherNumeric.temperatureF
                    ),
                    let lo = WeatherNumeric.roundedInt(
                        day.lowTemperature.converted(to: .fahrenheit).value,
                        allowed: WeatherNumeric.temperatureF
                    )
                else { return nil }
                let label: String = {
                    if cal.isDateInToday(day.date) { return "Today" }
                    if i == 0 { return "Today" }
                    return weekdayFmt.string(from: day.date)
                }()
                return WeatherSnapshot.DailyForecast(
                    date: day.date,
                    weekdayLabel: label,
                    highF: hi,
                    lowF: lo,
                    symbol: day.symbolName,
                    condition: day.condition.description,
                    precipChance: WeatherNumeric.finite(
                        day.precipitationChance,
                        allowed: 0...1
                    )
                )
            }
        }()

        // Level-100 depth — feels-like / humidity / gust straight off
        // the WeatherKit current observation; hourly band from the next
        // 12 hours; alerts mapped onto the NWS CAP severity ladder.
        let feelsLikeF = WeatherNumeric.roundedInt(
            current.apparentTemperature.converted(to: .fahrenheit).value,
            allowed: WeatherNumeric.temperatureF
        )
        let humidityPct = WeatherNumeric.roundedInt(
            current.humidity * 100,
            allowed: WeatherNumeric.percent
        )
        let windGustMph: Int? = current.wind.gust.flatMap {
            WeatherNumeric.roundedInt(
                $0.converted(to: .milesPerHour).value,
                allowed: WeatherNumeric.windMph
            )
        }
        let now = Date()
        let hourly: [WeatherSnapshot.HourlyForecast] = weather.hourlyForecast.forecast
            .filter { $0.date >= now.addingTimeInterval(-1800) }
            .prefix(12)
            .compactMap { hour in
                guard
                    let tempF = WeatherNumeric.roundedInt(
                        hour.temperature.converted(to: .fahrenheit).value,
                        allowed: WeatherNumeric.temperatureF
                    ),
                    let precipChancePct = WeatherNumeric.roundedInt(
                        hour.precipitationChance * 100,
                        allowed: WeatherNumeric.percent
                    ),
                    let windMph = WeatherNumeric.roundedInt(
                        hour.wind.speed.converted(to: .milesPerHour).value,
                        allowed: WeatherNumeric.windMph
                    )
                else { return nil }
                return WeatherSnapshot.HourlyForecast(
                    date: hour.date,
                    tempF: tempF,
                    symbol: hour.symbolName,
                    precipChancePct: precipChancePct,
                    windMph: windMph,
                    // Typed condition → canonical code (light/heavy variants
                    // preserved); the SF-symbol round-trip is the fallback.
                    weatherCode: Self.code(for: hour.condition, symbol: hour.symbolName),
                    isDaylightHint: hour.isDaylight
                )
            }
        // Apple WeatherKit minute-by-minute next-hour precipitation — the
        // SAME product the server envelope maps at ServerWeather.NextHour.
        // Previously only the server-fallback path carried it, so the
        // forecastNextHour pill was dead on the primary on-device path.
        let nextHourPrecip: WeatherSnapshot.NextHourPrecip? = {
            let mf: Forecast<MinuteWeather>? = weather.minuteForecast
            guard let mf else { return nil }
            let minutes: [WeatherSnapshot.NextHourPrecip.Minute] = mf.forecast.prefix(60).compactMap { m in
                guard let precipChancePct = WeatherNumeric.roundedInt(
                    m.precipitationChance * 100,
                    allowed: WeatherNumeric.percent
                ) else { return nil }
                return WeatherSnapshot.NextHourPrecip.Minute(
                    date: m.date,
                    precipChancePct: precipChancePct,
                    // UnitSpeed m/s → mm/hr (1 m/s = 3,600,000 mm/hr).
                    intensityMmPerHour: WeatherNumeric.nonnegativeFinite(
                        m.precipitationIntensity
                            .converted(to: .metersPerSecond).value * 3_600_000
                    )
                )
            }
            guard !minutes.isEmpty else { return nil }
            return WeatherSnapshot.NextHourPrecip(
                forecastStart: minutes.first?.date,
                forecastEnd: minutes.last?.date,
                minutes: minutes,
                summaries: []
            )
        }()
        let precipChancePct: Int? = hourly.first?.precipChancePct
        let alerts: [WeatherSnapshot.SevereAlert] = (weather.weatherAlerts ?? []).map { alert in
            let sev: WeatherSnapshot.AlertSeverity = {
                switch alert.severity {
                case .minor:    return .minor
                case .moderate: return .moderate
                case .severe:   return .severe
                case .extreme:  return .extreme
                default:        return .unknown
                }
            }()
            return WeatherSnapshot.SevereAlert(
                event: alert.summary,
                severity: sev,
                headline: nil,
                endsAt: nil,
                source: alert.source,
                detailsURL: alert.detailsURL
            )
        }

        var snap = WeatherSnapshot(
            city: city,
            tempF: tempF,
            windMph: windMph,
            visibilityMi: visibilityMi,
            condition: condition,
            symbol: symbol,
            nextAlert: nextAlert.isEmpty ? nil : nextAlert,
            accent: accent,
            daily: daily,
            feelsLikeF: feelsLikeF,
            humidityPct: humidityPct,
            windGustMph: windGustMph,
            precipChancePct: precipChancePct,
            nextHourPrecip: nextHourPrecip,
            hourly: hourly,
            alerts: alerts
        )
        // v2: name the real provider (Apple Weather) + the canonical code
        // from WeatherKit's TYPED condition enum (heavyRain / flurries /
        // freezingDrizzle / blizzard all keep their granularity — the old
        // SF-symbol round-trip collapsed light/heavy variants so the sky
        // engine's granular scenes could never fire on the primary path).
        snap.dataSource = .weatherKit
        snap.weatherCode = Self.code(for: current.condition, symbol: symbol)
        snap.observedAt = current.date
        // Preserve the queried coordinate even when reverse geocoding fails.
        // The coordinate is the authoritative solar fallback; a placemark is
        // optional display metadata and must never erase weather geometry.
        snap.latitude = location.coordinate.latitude
        snap.longitude = location.coordinate.longitude
        snap.timezoneId = placemark?.timeZone?.identifier
        if let today = weather.dailyForecast.first {
            snap.sunriseAt = today.sun.sunrise
            snap.sunsetAt  = today.sun.sunset
        }
        snap.isNightHint = !current.isDaylight
        if let top = alerts.max(by: { $0.severity.rank < $1.severity.rank }) {
            snap.alert = .init(title: top.event, severity: top.severity, until: top.endsAt)
        }
        return snap
    }

    // MARK: - Location (one-shot)

    private func requestLocationIfNeeded() async -> CLLocation? {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            // Wait for the permission prompt to resolve (user action can
            // take any amount of time — poll for up to 8 seconds).
            for _ in 0..<16 {
                do {
                    try await Task.sleep(nanoseconds: 500_000_000)
                } catch {
                    return nil
                }
                guard !Task.isCancelled else { return nil }
                if locationManager.authorizationStatus != .notDetermined { break }
            }
            if locationManager.authorizationStatus == .authorizedWhenInUse
                || locationManager.authorizationStatus == .authorizedAlways {
                return await requestLocationOneShot()
            }
            return nil
        case .authorizedWhenInUse, .authorizedAlways:
            return await requestLocationOneShot()
        case .denied, .restricted:
            return nil
        @unknown default:
            return nil
        }
    }

    /// One-shot location read with a 4-second hard timeout so the
    /// simulator (which often has no GPS fix at all) can't stall us.
    private func requestLocationOneShot() async -> CLLocation? {
        let requestID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }
                finishPendingLocation(nil)
                pendingLocation = continuation
                pendingLocationID = requestID
                pendingLocationDidRetry = false
                locationManager.requestLocation()
                armLocationTimeout(for: requestID)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.pendingLocationID == requestID else { return }
                self?.finishPendingLocation(nil)
            }
        }
    }

    /// Four-second watchdog for one pending location attempt. A stale-fix
    /// retry keeps the same request identity and replaces this task, so caller
    /// cancellation still reaches the continuation deterministically.
    private func armLocationTimeout(for requestID: UUID) {
        pendingLocationTimeoutTask?.cancel()
        pendingLocationTimeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 4_000_000_000)
            } catch {
                return
            }
            guard let self else { return }
            guard self.pendingLocationID == requestID else { return }
            self.finishPendingLocation(nil)
        }
    }

    private func finishPendingLocation(_ location: CLLocation?) {
        pendingLocationTimeoutTask?.cancel()
        pendingLocationTimeoutTask = nil
        let continuation = pendingLocation
        pendingLocation = nil
        pendingLocationID = nil
        pendingLocationDidRetry = false
        continuation?.resume(returning: location)
    }

    // MARK: - Reverse geocode

    private func reverseGeocode(_ location: CLLocation) async throws -> CLPlacemark? {
        let request = CancellableGeocoder()
        return try await withTaskCancellationHandler {
            let placemarks = try await request.geocoder.reverseGeocodeLocation(location)
            try Task.checkCancellation()
            return placemarks.first
        } onCancel: {
            request.cancel()
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        // Pick the freshest fix that's also recent enough to trust.
        // Without this filter CoreLocation occasionally hands us a
        // multi-day-old cached fix from a previous region, which is
        // why weather rendered last week's storm system over a town
        // the driver had already left. The maxAge gate is read from
        // the actor's stored value via a Task hop so the rest of the
        // delegate stays nonisolated.
        let snapshot = locations.last
        Task { @MainActor in
            let now = Date()
            let acceptable: CLLocation? = {
                guard let s = snapshot else { return nil }
                guard LatLongParser.isValid(s.coordinate),
                      abs(now.timeIntervalSince(s.timestamp)) <= self.maxLocationAgeSeconds else {
                    return nil
                }
                return s
            }()
            // A rejected STALE cached fix gets one retry: CoreLocation is
            // typically already acquiring the fresh reading, so instead of
            // failing the fetch we keep the continuation pending, fire one
            // more `requestLocation()`, and re-arm the timeout window.
            if acceptable == nil, snapshot != nil,
               !self.pendingLocationDidRetry, self.pendingLocation != nil {
                self.pendingLocationDidRetry = true
                guard let requestID = self.pendingLocationID else { return }
                self.locationManager.requestLocation()
                self.armLocationTimeout(for: requestID)
                return
            }
            self.finishPendingLocation(acceptable)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            self.finishPendingLocation(nil)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        // Broadcast the auth change so home views can re-run their
        // weather fetch after the user taps Allow on the prompt.
        // Without this, the dashboard rendered empty on first launch
        // because `fetchCurrent()` had already finished (returning
        // nil for `.notDetermined`) and no signal told the view to
        // try again once the user responded.
        NotificationCenter.default.post(
            name: .eusoWeatherAuthorizationChanged,
            object: nil
        )
    }
}
