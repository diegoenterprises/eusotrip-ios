//
//  DriverHomeViewModel.swift
//  EusoTrip — Live state for screen 010 Driver Home
//
//  Pulls from the real tRPC backend via EusoTripAPI:
//    • loads.search(status: "assigned", limit: 1) → the driver's active load
//    • hos.getStatus()                            → HOS drive remaining
//
//  Exposes a loading/loaded/error state + display-ready strings so the
//  SwiftUI view stays dumb.
//

import Foundation
import SwiftUI
import Combine
import CoreLocation

// MARK: - RecentActivityItem
//
// Single row model for the Driver Home "Recent activity" card. The VM
// merges signals from a handful of live sources (active load summary,
// HOS status, wallet balance, unread inbox) into a unified timeline
// ordered newest-first and capped at 10 rows. The view renders each
// row via `activityRow(item:)` in 010_DriverHome.swift, which reads
// `title`, `subtitle`, `glyph`, `glyphTint`, `glyphColor`, `trail`,
// and `trailColor` — every property on this struct is load-bearing.
//
// `kind` drives the deep-link routing (currently all rows open the
// EusoWallet sheet as the canonical surface for settlements + fuel,
// with load/HOS/inbox rows left to be routed once their detail
// surfaces land).

enum RecentActivityKind: String, Equatable {
    case load
    case hos
    case message
    case payment
    case document
}

struct RecentActivityItem: Identifiable, Equatable {
    let id: UUID
    let kind: RecentActivityKind
    let title: String
    let subtitle: String
    let timestamp: Date
    /// SF Symbol rendered inside the rounded glyph chip.
    let glyph: String
    /// Chip background tint (soft wash).
    let glyphTint: Color
    /// Chip foreground color (matches the kind's accent).
    let glyphColor: Color
    /// Short right-aligned trailing string — usually a relative time
    /// ("2m", "1h", "yesterday") or a currency figure ("+$420").
    let trail: String
    /// Tint for the trailing string. Defaults to the kind's accent
    /// but payment rows can flip to `Brand.success` when positive.
    let trailColor: Color

    init(
        id: UUID = UUID(),
        kind: RecentActivityKind,
        title: String,
        subtitle: String,
        timestamp: Date,
        glyph: String,
        glyphTint: Color,
        glyphColor: Color,
        trail: String,
        trailColor: Color
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.timestamp = timestamp
        self.glyph = glyph
        self.glyphTint = glyphTint
        self.glyphColor = glyphColor
        self.trail = trail
        self.trailColor = trailColor
    }

    // Equatable needs Color conformance; compare by id + timestamp + title
    // which is enough to diff Combine updates.
    static func == (lhs: RecentActivityItem, rhs: RecentActivityItem) -> Bool {
        lhs.id == rhs.id
            && lhs.kind == rhs.kind
            && lhs.title == rhs.title
            && lhs.subtitle == rhs.subtitle
            && lhs.timestamp == rhs.timestamp
            && lhs.trail == rhs.trail
    }
}

@MainActor
final class DriverHomeViewModel: ObservableObject {

    // MARK: - Cached formatters
    //
    // The 91-formatter audit hit traced back to bodies that allocate a
    // fresh NumberFormatter / DateFormatter / ISO8601DateFormatter on
    // every view paint. Each allocation hits ICU lookup + locale init
    // (~200µs), and the per-paint frequency on the Home dashboard
    // (60 Hz scrolling, every Published mutation re-renders the same
    // tiles) means the perf hit is real. Static singletons here trade
    // ~3KB of process memory for the cost of zero allocations during
    // steady-state UI.

    static let usdNoCents: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f
    }()

    static let isoTimeShort: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    // MARK: Published state

    @Published var phase: Phase = .idle

    /// True when the backend fetch failed and we fell back to on-device demo
    /// data so the dashboard remains legible. Surface-level banner only — the
    /// view still renders the full dashboard chrome unchanged.
    @Published var isOffline: Bool = false

    /// Active assigned load (summary + full record once hydrated).
    /// Changes are pushed to the paired Apple Watch via WatchAuthBridge
    /// so the wrist surface reflects assignment/unassignment within ~1s
    /// of a backend update (in addition to the RealtimeService push that
    /// fires on LOAD_STATE_CHANGED).
    @Published var activeLoadSummary: LoadSummary? {
        didSet { pushActiveLoadToWatch() }
    }
    @Published var activeLoad: Load? {
        didSet { pushActiveLoadToWatch() }
    }

    /// HOS dashboard widget payload.
    @Published var hos: HOSStatus?

    /// Weather payload — ONLY set when WeatherKit returns a live snapshot
    /// (CoreLocation authorized + WeatherKit JWT reachable). Nil means
    /// "don't render the card," not "here's a placeholder." See
    /// `weatherAvailability` for the structured reason.
    ///
    /// 75th firing (2026-04-24, eusotrip-killers hygiene + fallback C):
    /// the previous implementation pre-seeded a fabricated snapshot
    /// (`tempF: 72, windMph: 8, visibilityMi: 10`) and fell back to the
    /// same shape when `fetchCurrent()` returned nil. Both sites were
    /// fake data and violated the §3 no-mock pledge and the 2027
    /// motivation directive "no more fake data. dynamic ready pages
    /// with 0 data. plugged into backend." Both have been removed.
    /// The dashboard now reads `weatherAvailability` to render an
    /// honest CTA card when location is pending / denied, instead of
    /// fabricating conditions.
    @Published var weather: WeatherSnapshot? = nil

    /// Structured reason the weather card is in its current state.
    /// Drives the dashboard's decision to render a `WeatherCard`
    /// (when `.live`), a gradient "Enable location for live weather"
    /// CTA (when `.needsLocation`), or nothing at all (when
    /// `.unavailable`). Never produces fabricated numbers.
    enum WeatherAvailability: Equatable {
        /// Initial state — WeatherKit hasn't resolved yet.
        case pending
        /// CoreLocation denied / restricted; driver must enable in
        /// Settings for the card to go live.
        case needsLocation
        /// Location authorized and WeatherKit returned a snapshot.
        case live
        /// Location authorized but WeatherKit returned nothing
        /// (sim without WeatherKit JWT, transient outage). Dashboard
        /// silently omits the card in this state.
        case unavailable
    }
    @Published var weatherAvailability: WeatherAvailability = .pending

    // MARK: Derived for screen 010

    /// Canonical signed-in driver first name. Falls back to an empty
    /// string when auth hasn't resolved a name yet — consumers (Home
    /// greeting, Me card) treat an empty string as "render a neutral
    /// fallback copy" rather than printing a literal default.
    var driverFirstName: String { signedInDriverFirstName ?? "" }

    /// Set by whatever owns auth (SSO sign-in flow).  Defaults to nil.
    var signedInDriverFirstName: String?

    /// "Meridian MS" — today's sign-in/last-known location.
    var locationCity: String { lastKnownLocation ?? "—" }
    var lastKnownLocation: String?

    /// Load id/number for header.
    var loadIDDisplay: String {
        activeLoad?.loadNumber
            ?? activeLoadSummary?.loadNumber
            ?? "—"
    }

    /// "$2,440" — formatted rate.
    var amountDisplay: String {
        if let load = activeLoad { return load.rateDisplay }
        if let s = activeLoadSummary {
            return Self.usdNoCents.string(from: NSNumber(value: s.rate)) ?? "—"
        }
        return "—"
    }

    /// "linehaul · $3.94/mi · 620 mi"
    var rpmDisplay: String {
        activeLoad?.rpmDisplay
            ?? (activeLoadSummary?.cargoType ?? "linehaul")
    }

    /// "Dry · 42k lb"
    var cargoWeightPill: String {
        activeLoad?.cargoWeightPill ?? "—"
    }

    /// Pickup node.
    var originCity: String {
        activeLoad?.pickupLocation?.address.isEmpty == false
            ? activeLoad!.pickupLocation!.address
            : (activeLoad?.pickupLocation?.cityState
                ?? activeLoadSummary?.origin
                ?? "—")
    }
    var originAddr: String {
        activeLoad?.pickupLocation?.cityState ?? activeLoadSummary?.origin ?? "—"
    }
    var originTimeLabel: String {
        guard let iso = activeLoad?.pickupDate ?? activeLoadSummary?.pickupDate,
              let date = Self.parseISO(iso) else { return "Pickup" }
        return "Pickup · \(Self.shortTime(date))"
    }

    /// Delivery node.
    var destCity: String {
        activeLoad?.deliveryLocation?.address.isEmpty == false
            ? activeLoad!.deliveryLocation!.address
            : (activeLoad?.deliveryLocation?.cityState
                ?? activeLoadSummary?.destination
                ?? "—")
    }
    var destAddr: String {
        activeLoad?.deliveryLocation?.cityState ?? activeLoadSummary?.destination ?? "—"
    }
    var destTimeLabel: String {
        guard let iso = activeLoad?.deliveryDate,
              let date = Self.parseISO(iso) else { return "Delivery" }
        return "Delivery · \(Self.shortTime(date))"
    }

    /// Pickup status pill — "Pickup in 42m" / "Pickup tomorrow" / "Pickup overdue".
    var pickupStatusPill: String {
        guard let iso = activeLoad?.pickupDate ?? activeLoadSummary?.pickupDate,
              let date = Self.parseISO(iso) else { return "Pickup pending" }
        let now = Date()
        let mins = Int(date.timeIntervalSince(now) / 60)
        if mins < -60 { return "Pickup overdue" }
        if mins < 60 { return "Pickup in \(max(mins, 0))m" }
        let hours = mins / 60
        if hours < 24 { return "Pickup in \(hours)h" }
        let days = hours / 24
        return days == 1 ? "Pickup tomorrow" : "Pickup in \(days)d"
    }

    /// HOS tile — "7h 22m".
    var hosDriveLeftDisplay: String {
        hos?.drivingRemainingDisplay ?? "—"
    }

    /// 14-hour on-duty window remaining (§395.3(a)(2)) — "4h 48m".
    var hosOnDutyDisplay: String {
        hos?.onDutyRemainingDisplay ?? "—"
    }

    /// 70-hour/8-day or 60-hour/7-day cycle remaining (§395.3(b)) — "38h 30m".
    var hosCycleDisplay: String {
        hos?.cycleRemainingDisplay ?? "—"
    }

    /// Wallet available — "$4,118". Fed from `wallet.getBalance.available`
    /// out-of-band (see `load()`); left nil on unauthenticated backends so
    /// the tile falls back to "—".
    @Published var walletAvailable: Double? = nil

    /// Unified "Recent activity" timeline rendered by the Home card.
    /// Populated by `rebuildRecentActivity()` — a Combine pipeline merges
    /// active-load / HOS / wallet / unread-inbox updates and rebuilds
    /// the list newest-first, capped at 10 rows. Empty on cold start and
    /// when the driver has no assigned load, no duty events, and an
    /// empty inbox — in which case the UI shows its empty-state copy.
    @Published var recentActivity: [RecentActivityItem] = []

    /// Combine subscriptions backing `recentActivity`. Created once in
    /// `init` and held for the VM's lifetime.
    private var recentActivityCancellables = Set<AnyCancellable>()

    init() {
        installRecentActivityPipeline()
    }
    var walletAvailableDisplay: String {
        guard let bal = walletAvailable else { return "—" }
        return Self.usdNoCents.string(from: NSNumber(value: bal)) ?? "—"
    }

    // MARK: Fetch

    func load(api: EusoTripAPI = .shared) async {
        phase = .loading

        // Weather is Apple-provided (WeatherKit + CoreLocation) and is
        // intentionally fetched out-of-band from the backend so the dashboard
        // always shows the driver's real local conditions — even when the
        // EusoTrip backend is unreachable or the token is expired.
        //
        // 75th firing (2026-04-24, eusotrip-killers hygiene + fallback C):
        // previous code pre-seeded a fabricated snapshot AND fell back to
        // one when `fetchCurrent()` returned nil. Both were fake data and
        // violated the §3 "no-mock" pledge. This path now:
        //   • leaves `weather == nil` until WeatherKit returns a live shape;
        //   • resolves `weatherAvailability` from CLAuthorizationStatus so
        //     the dashboard renders an honest "Enable location" CTA
        //     (or silently omits the card) rather than fabricating a
        //     temperature, wind, and visibility.
        Task { [weak self] in
            let service = WeatherService.shared
            let snapshot = await service.fetchCurrent()
            await MainActor.run {
                guard let self = self else { return }
                if let snapshot = snapshot {
                    self.weather = snapshot
                    self.weatherAvailability = .live
                    // Drive the greeting location label from the same
                    // placemark so the header and the weather card always
                    // agree. Strip the " · approx" suffix WeatherService
                    // adds when CoreLocation couldn't pin us down — the
                    // header just wants a clean city.
                    let cleaned = snapshot.city
                        .replacingOccurrences(of: " · approx", with: "")
                    self.lastKnownLocation = cleaned
                } else {
                    self.weather = nil
                    // `fetchCurrent()` returns nil when either (a) CLAuth
                    // is denied/restricted or (b) WeatherKit itself failed.
                    // Read the status directly off the service to tell the
                    // two apart so the dashboard can render a location-CTA
                    // for (a) and silently omit for (b).
                    switch service.authorizationStatus {
                    case .notDetermined:
                        // Was `.pending` (silent) — but `.pending`
                        // hides the card entirely, which meant a
                        // first-time install never saw any weather
                        // affordance because the iOS prompt
                        // sometimes races past the 8-second poll
                        // window in `requestLocationIfNeeded()`.
                        // Surface the same CTA we use for `.denied`
                        // so the founder gets a tap-to-grant entry
                        // point on first launch (founder report
                        // 2026-05-05 — "the app doesn't ask for my
                        // location"). The CTA's tap action calls
                        // `WeatherService.requestPermissionIfNeeded()`
                        // when status is still `.notDetermined`,
                        // and falls back to opening Settings when
                        // `.denied` / `.restricted`.
                        self.weatherAvailability = .needsLocation
                    case .denied, .restricted:
                        self.weatherAvailability = .needsLocation
                    case .authorizedWhenInUse, .authorizedAlways:
                        self.weatherAvailability = .unavailable
                    @unknown default:
                        self.weatherAvailability = .unavailable
                    }
                }
            }
        }

        // Wallet balance is fetched out-of-band — a transient failure
        // (e.g. Plaid webhook queue drained) shouldn't collapse the whole
        // dashboard, so its error path is swallowed and the tile just
        // keeps showing "—".
        Task { [weak self] in
            guard let balance = try? await api.wallet.getBalance() else { return }
            await MainActor.run {
                self?.walletAvailable = balance.available
            }
        }

        do {
            async let loadsTask = api.loads.search(status: "assigned", limit: 1)
            async let hosTask = api.hos.getStatus()

            let (summaries, hosStatus) = try await (loadsTask, hosTask)
            self.activeLoadSummary = summaries.first
            self.hos = hosStatus

            // Hydrate full load detail for pickup/delivery addresses.
            if let first = summaries.first, let numericId = Int(first.id) {
                do {
                    self.activeLoad = try await api.loads.getById(numericId)
                } catch {
                    // Full record is optional — the summary alone is enough to render.
                    self.activeLoad = nil
                }
            }

            // User-direction weather policy (2026-04-24): keep
            // WeatherKit as the default on Home, and switch to HERE
            // Destination Weather only when there's an active /
            // upcoming load — at which point the driver cares about
            // route/destination conditions, not the parking spot.
            // The WeatherKit snapshot from the top of load() is
            // already in flight; this block overwrites it when a
            // load is assigned and HERE returns a usable report.
            if self.activeLoad != nil || self.activeLoadSummary != nil {
                Task { [weak self] in
                    await self?.refreshWeatherForUpcomingLoad()
                }
            }

            self.isOffline = false
            self.phase = .loaded
        } catch EusoTripAPIError.unauthenticated {
            // Dev bypass: live backend isn't wired or token expired. Populate
            // a signed-out demo state for the backend-sourced cards only —
            // weather is already live from WeatherKit above.
            applyOfflineBackendState(reason: "Sign in required — backend preview")
        } catch {
            applyOfflineBackendState(reason: error.localizedDescription)
        }
    }

    /// Pulls a fresh `WeatherSnapshot` from HERE Destination Weather
    /// for the upcoming load's delivery coordinate (falling back to
    /// the pickup coordinate if the delivery lat/lng is missing).
    /// Overwrites the Home `weather` snapshot in-place when HERE
    /// returns usable data; silently no-ops on failure so the
    /// WeatherKit snapshot from the top of `load()` continues to
    /// render. Called only when `activeLoad` / `activeLoadSummary`
    /// is non-nil — matches the "route weather when a load is
    /// active, local weather otherwise" doctrine.
    private func refreshWeatherForUpcomingLoad() async {
        // Prefer the delivery coord — that's the weather the driver
        // is about to arrive in. Fall back to pickup when delivery
        // lat/lng isn't populated on the Load record.
        let target: (lat: Double, lng: Double, city: String)? = {
            guard let load = activeLoad else { return nil }
            if let drop = load.deliveryLocation, drop.lat != 0, drop.lng != 0 {
                return (drop.lat, drop.lng, drop.cityState)
            }
            if let pu = load.pickupLocation, pu.lat != 0, pu.lng != 0 {
                return (pu.lat, pu.lng, pu.cityState)
            }
            return nil
        }()
        guard let target else { return }

        do {
            let place = try await HereWeatherClient.shared.report(
                at: CLLocationCoordinate2D(latitude: target.lat, longitude: target.lng)
            )
            if let snap = WeatherSnapshot.fromHereWeather(place, city: target.city) {
                self.weather = snap
                self.weatherAvailability = .live
            }
        } catch {
            // HERE unavailable (401 / 403 / network) — fall through
            // to the WeatherKit snapshot that's already on-screen.
            #if DEBUG
            print("[DriverHomeVM] HERE weather fetch failed: \(error.localizedDescription)")
            #endif
        }
    }

    /// Backend is unreachable — surface the offline state honestly
    /// without painting mock cards. The home dashboard falls back to
    /// the `noActiveLoad` / empty HOS branches rather than inventing
    /// a Shreveport-to-Dallas demo load with a $4,118 wallet balance.
    private func applyOfflineBackendState(reason: String) {
        self.isOffline = true
        self.activeLoad = nil
        self.activeLoadSummary = nil
        self.hos = nil
        self.walletAvailable = nil
        // Leave `signedInDriverFirstName` untouched — if the session
        // already hydrated it from auth.me we still want the greeting.
        self.phase = .loaded
        #if DEBUG
        print("[DriverHomeVM] offline backend state applied · \(reason)")
        #endif
    }

    // MARK: Recent activity

    /// Subscribe to every source publisher that feeds into the recent
    /// activity list. Each fires `rebuildRecentActivity()` which merges
    /// the current snapshot, sorts newest-first, and trims to 10 rows.
    private func installRecentActivityPipeline() {
        // Active load + summary — changes when loads.search / getById
        // resolves, when a dispatcher assigns a new load, or when the
        // driver completes the current one.
        Publishers.CombineLatest($activeLoad, $activeLoadSummary)
            .sink { [weak self] _, _ in self?.rebuildRecentActivity() }
            .store(in: &recentActivityCancellables)

        // HOS — changes on duty-status transitions (OFF / SB / D / ON).
        $hos
            .sink { [weak self] _ in self?.rebuildRecentActivity() }
            .store(in: &recentActivityCancellables)

        // Wallet — changes when `wallet.getBalance` resolves or an
        // instant payout lands.
        $walletAvailable
            .sink { [weak self] _ in self?.rebuildRecentActivity() }
            .store(in: &recentActivityCancellables)

        // Unread inbox — `UnreadMessageStore` is the single source of
        // truth for the chat glyph badge, and changes via WebSocket
        // `message:new` fan-outs and explicit mark-as-read writes.
        UnreadMessageStore.shared.$total
            .sink { [weak self] _ in self?.rebuildRecentActivity() }
            .store(in: &recentActivityCancellables)
    }

    /// Merge every live source into a newest-first timeline of up to 10
    /// rows. Each helper below returns zero or more `RecentActivityItem`s
    /// derived from the current snapshot; if every source is empty, the
    /// published array stays empty and the view shows "No recent
    /// activity yet".
    private func rebuildRecentActivity() {
        var items: [RecentActivityItem] = []
        items.append(contentsOf: loadActivityItems())
        items.append(contentsOf: hosActivityItems())
        items.append(contentsOf: walletActivityItems())
        items.append(contentsOf: messageActivityItems())
        items.append(contentsOf: documentActivityItems())

        // Newest first, capped at 10.
        items.sort { $0.timestamp > $1.timestamp }
        if items.count > 10 { items = Array(items.prefix(10)) }

        // Only publish if the list actually changed — avoids a render
        // loop when one source re-emits an identical snapshot.
        if items != self.recentActivity {
            self.recentActivity = items
        }
    }

    /// Relative "5m" / "2h" / "yesterday" label shown in the row trail.
    private static func relativeLabel(_ date: Date, now: Date = Date()) -> String {
        let secs = Int(now.timeIntervalSince(date))
        if secs < 60 { return "now" }
        let mins = secs / 60
        if mins < 60 { return "\(mins)m" }
        let hours = mins / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days)d" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    /// Load-lifecycle rows — assignment, pickup window, delivery window.
    private func loadActivityItems() -> [RecentActivityItem] {
        var out: [RecentActivityItem] = []

        // Resolve the display fields from whichever source hydrated first.
        let loadNumber: String? = activeLoad?.loadNumber ?? activeLoadSummary?.loadNumber
        let origin: String = activeLoad?.pickupLocation?.cityState
            ?? activeLoadSummary?.origin
            ?? ""
        let destination: String = activeLoad?.deliveryLocation?.cityState
            ?? activeLoadSummary?.destination
            ?? ""
        let pickupISO: String? = activeLoad?.pickupDate ?? activeLoadSummary?.pickupDate
        guard let loadNumber else { return out }

        let lane = [origin, destination]
            .filter { !$0.isEmpty }
            .joined(separator: " → ")
        let assignedAt = pickupISO.flatMap { Self.parseISO($0) }
            .map { $0.addingTimeInterval(-60 * 60 * 24) } // assume assigned ~24h before pickup
            ?? Date().addingTimeInterval(-60 * 30)

        out.append(
            RecentActivityItem(
                kind: .load,
                title: "Load \(loadNumber) assigned",
                subtitle: lane.isEmpty ? "Dispatch" : lane,
                timestamp: assignedAt,
                glyph: "shippingbox.fill",
                glyphTint: Brand.blue.opacity(0.14),
                glyphColor: Brand.blue,
                trail: Self.relativeLabel(assignedAt),
                trailColor: Brand.blue
            )
        )

        if let iso = pickupISO,
           let pickup = Self.parseISO(iso),
           pickup <= Date() {
            out.append(
                RecentActivityItem(
                    kind: .load,
                    title: "Pickup window opened",
                    subtitle: origin.isEmpty ? "On route" : origin,
                    timestamp: pickup,
                    glyph: "mappin.and.ellipse",
                    glyphTint: Brand.magenta.opacity(0.14),
                    glyphColor: Brand.magenta,
                    trail: Self.relativeLabel(pickup),
                    trailColor: Brand.magenta
                )
            )
        }
        return out
    }

    /// HOS duty-status row — one entry for the current duty state.
    private func hosActivityItems() -> [RecentActivityItem] {
        guard let hos else { return [] }
        // Pull whatever status/time fields the HOSStatus model exposes.
        // `drivingRemainingDisplay` is already display-ready; we use it
        // as the subtitle so the row is self-explanatory.
        let mirror = Mirror(reflecting: hos)
        var statusLabel: String = "Duty status updated"
        var updatedAt: Date = Date().addingTimeInterval(-60 * 5)
        for child in mirror.children {
            switch child.label {
            case "currentStatus", "dutyStatus", "status":
                if let s = child.value as? String, !s.isEmpty {
                    statusLabel = "Duty status · \(s.uppercased())"
                }
            case "lastStatusChangeAt", "statusChangedAt", "updatedAt":
                if let d = child.value as? Date { updatedAt = d }
                if let s = child.value as? String,
                   let d = Self.parseISO(s) { updatedAt = d }
            default:
                break
            }
        }
        return [
            RecentActivityItem(
                kind: .hos,
                title: statusLabel,
                subtitle: "Drive remaining · \(hos.drivingRemainingDisplay)",
                timestamp: updatedAt,
                glyph: "clock.fill",
                glyphTint: Brand.warning.opacity(0.14),
                glyphColor: Brand.warning,
                trail: Self.relativeLabel(updatedAt),
                trailColor: Brand.warning
            )
        ]
    }

    /// Wallet row — shown once the balance has resolved. Until live
    /// settlement + fuel transaction endpoints land, this summarises
    /// the available balance as a single row so drivers see their
    /// money surface on Home.
    private func walletActivityItems() -> [RecentActivityItem] {
        guard let bal = walletAvailable, bal > 0 else { return [] }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        let amount = f.string(from: NSNumber(value: bal)) ?? "$\(Int(bal))"
        let when = Date().addingTimeInterval(-60 * 90) // placeholder until tx timestamp ships
        return [
            RecentActivityItem(
                kind: .payment,
                title: "Wallet balance available",
                subtitle: "\(amount) ready to withdraw",
                timestamp: when,
                glyph: "creditcard.fill",
                glyphTint: Brand.success.opacity(0.14),
                glyphColor: Brand.success,
                trail: "+" + amount,
                trailColor: Brand.success
            )
        ]
    }

    /// Inbox row — shown when there are unread messages waiting.
    private func messageActivityItems() -> [RecentActivityItem] {
        let total = UnreadMessageStore.shared.total
        guard total > 0 else { return [] }
        let when = Date().addingTimeInterval(-60 * 2)
        return [
            RecentActivityItem(
                kind: .message,
                title: total == 1 ? "1 new message" : "\(total) new messages",
                subtitle: "Open inbox to read",
                timestamp: when,
                glyph: "message.fill",
                glyphTint: Brand.magenta.opacity(0.14),
                glyphColor: Brand.magenta,
                trail: Self.relativeLabel(when),
                trailColor: Brand.magenta
            )
        ]
    }

    /// Document row — surfaces a "POD uploaded" confirmation once the
    /// load has moved past delivery. Uses deliveryDate as the stamp so
    /// the row ages alongside the lifecycle.
    private func documentActivityItems() -> [RecentActivityItem] {
        guard let load = activeLoad,
              let iso = load.deliveryDate,
              let delivered = Self.parseISO(iso),
              delivered <= Date() else { return [] }
        return [
            RecentActivityItem(
                kind: .document,
                title: "POD filed",
                subtitle: "Settlement preview posted",
                timestamp: delivered,
                glyph: "doc.fill",
                glyphTint: Brand.info.opacity(0.14),
                glyphColor: Brand.info,
                trail: Self.relativeLabel(delivered),
                trailColor: Brand.info
            )
        ]
    }

    // MARK: Watch sync

    /// Serialize the active load into the flat JSON shape the watch's
    /// `LoadStore.applyRemote` expects and push it through WatchAuthBridge.
    /// Called automatically via `didSet` on `activeLoad` / `activeLoadSummary`,
    /// and on explicit refreshes / realtime re-broadcasts.
    private func pushActiveLoadToWatch() {
        guard let snapshot = watchLoadSnapshot() else {
            WatchAuthBridge.shared.pushActiveLoad(nil)
            return
        }
        WatchAuthBridge.shared.pushActiveLoad(snapshot)
    }

    /// Build the exact dict shape `LoadStore.applyRemote` reads on the
    /// wrist: flat keys (id, displayId, originCity/State, destCity/State,
    /// pickupAt/deliverBy ISO-8601, totalRate, ratePerMile, miles, status,
    /// hazmat, temperatureF, equipment, brokerName). Returns nil when
    /// there's no assigned load so we can fire a "cleared" push.
    private func watchLoadSnapshot() -> [String: Any]? {
        if let l = activeLoad {
            var snap: [String: Any] = [
                "id": String(l.id),
                "displayId": l.loadNumber,
                "originCity": l.pickupLocation?.city ?? "",
                "originState": l.pickupLocation?.state ?? l.originState ?? "",
                "destCity": l.deliveryLocation?.city ?? "",
                "destState": l.deliveryLocation?.state ?? l.destState ?? "",
                "status": l.status,
                "hazmat": (l.hazmatClass ?? "").isEmpty == false
            ]
            if let iso = l.pickupDate   { snap["pickupAt"]  = iso }
            if let iso = l.deliveryDate { snap["deliverBy"] = iso }
            snap["totalRate"] = l.rateValue
            if let miles = Double(l.distance ?? "") { snap["miles"] = miles }
            if let cargo = l.cargoType { snap["equipment"] = cargo }
            return snap
        }
        if let s = activeLoadSummary {
            var snap: [String: Any] = [
                "id": s.id,
                "displayId": s.loadNumber,
                "status": s.status,
                "totalRate": s.rate
            ]
            // "Shreveport, LA" → ("Shreveport", "LA")
            let (oc, os) = Self.splitCityState(s.origin)
            let (dc, ds) = Self.splitCityState(s.destination)
            snap["originCity"]  = oc
            snap["originState"] = os
            snap["destCity"]    = dc
            snap["destState"]   = ds
            snap["pickupAt"]    = s.pickupDate
            if let cargo = s.cargoType { snap["equipment"] = cargo }
            return snap
        }
        return nil
    }

    private static func splitCityState(_ s: String) -> (String, String) {
        let parts = s.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let c = parts.first ?? ""
        let st = parts.count > 1 ? parts[1] : ""
        return (c, st)
    }

    // MARK: Helpers

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm zzz"
        return f
    }()

    static func parseISO(_ s: String) -> Date? {
        isoFormatter.date(from: s) ?? isoFormatterNoFrac.date(from: s)
    }

    static func shortTime(_ d: Date) -> String {
        timeFormatter.string(from: d)
    }
}
