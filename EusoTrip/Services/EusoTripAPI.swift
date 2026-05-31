//
//  EusoTripAPI.swift
//  EusoTrip — tRPC HTTP client against the live backend
//
//  Wire format (tRPC v10):
//    GET  /api/trpc/<router>.<procedure>?input=<url-encoded-JSON>
//    POST /api/trpc/<router>.<procedure>  body: { json: <input> }
//
//  Response envelope:
//    { "result": { "data": { "json": <payload> } } }
//
//  Auth: JWT cookie (set by auth.login) or Authorization: Bearer <token>.
//  Cookies persist via HTTPCookieStorage.shared so auth survives app restarts.
//
//  Backend host: eusotrip-app.azurewebsites.net (Azure App Service).
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Errors

enum EusoTripAPIError: Error, LocalizedError {
    case notConfigured
    case badURL
    case httpStatus(Int, String)
    case decodingFailed(String)
    case unauthenticated
    case trpcError(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .notConfigured:            return "EusoTripAPI.baseURL is not set."
        case .badURL:                   return "Invalid URL."
        case .httpStatus(let c, let b): return "HTTP \(c): \(b)"
        case .decodingFailed(let s):    return "Decoding failed: \(s)"
        case .unauthenticated:          return "Authentication required."
        case .trpcError(let m):         return m
        case .empty:                    return "Empty response."
        }
    }
}

// MARK: - tRPC envelopes

private struct TRPCResult<T: Decodable>: Decodable {
    let result: Inner
    struct Inner: Decodable {
        let data: DataWrapper
        struct DataWrapper: Decodable {
            let json: T
        }
    }
}

/// tRPC v10 error envelope shape. The server wraps everything under a
/// superjson-style `json` child — `{"error":{"json":{"message":...,"code":...,"data":{...}}}}`.
/// Earlier this file mirrored an older v9/unwrapped shape
/// (`{"error":{"message":...}}`) which never matched production and caused
/// every tRPC error to surface in the UI as the fallback "Request failed"
/// string (driver saw "Can't reach news feed · Request failed" even when
/// the real message was "Please login (10001)"). Kept the nested shape so
/// `message` / `httpStatus` come through verbatim.
private struct TRPCErrorEnvelope: Decodable {
    let error: Outer
    struct Outer: Decodable {
        let json: Inner
    }
    struct Inner: Decodable {
        let message: String?
        let code: Int?
        let data: TRPCErrorData?
    }
    struct TRPCErrorData: Decodable {
        let code: String?
        let httpStatus: Int?
        let path: String?
    }
}

private struct TRPCInputEnvelope<T: Encodable>: Encodable {
    let json: T
}

/// Empty input placeholder for tRPC procedures that take no input.
/// (Swift can't nest generic-constrained types inside generic functions,
/// so we declare this at file scope.)
private struct TRPCEmptyInput: Encodable {}

// MARK: - Client

@MainActor
final class EusoTripAPI: ObservableObject {

    /// Shared singleton.
    ///
    /// The reference itself is a `let` of a Sendable reference type, so
    /// reading it from any isolation domain is safe. Marked `nonisolated`
    /// (plain, not `nonisolated(unsafe)`) so it can be referenced from
    /// nonisolated contexts such as default arguments of `@MainActor`
    /// view-model initializers. Instance-member access still enforces
    /// main-actor isolation on its own.
    nonisolated static let shared = EusoTripAPI()

    /// Nonisolated init so the `shared` singleton (itself nonisolated-unsafe)
    /// can construct the instance at static-initializer time from any context.
    /// All stored properties have default values, so no body work is needed.
    nonisolated init() {}

    /// Live Azure App Service host.  Override via `configure(baseURL:)` if needed.
    var baseURL: URL? = URL(string: "https://eusotrip-app.azurewebsites.net")

    /// Bearer token (SSO / passwordless).  Set when the user signs in.
    var authToken: String?

    /// APNs device token (hex). Sent on every authenticated request as
    /// `x-push-token` so the backend can register the device for
    /// push delivery without a separate roundtrip mutation. Set by
    /// PushService.didRegister(deviceToken:) after APNs issues the
    /// token. Was previously held only in PushService and never
    /// reached the backend — silent push-token drop.
    var pushDeviceToken: String?

    /// Underlying URLSession (swap for tests).  Wired to HTTPCookieStorage.shared
    /// so the JWT cookie set by auth.login persists across requests.
    /// Cache is explicitly disabled — see comment below.
    lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        // Disable URLCache app-wide. tRPC responses are stateful by
        // nature (signed-in user / load detail / wallet) and must
        // never be served from cache. Earlier crashes / "Failed
        // query" panics from a pre-migration deploy left poisoned
        // entries in URLCache that kept getting replayed even after
        // the server was patched, until app reinstall. .none drops
        // every response straight to disk and out.
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        // Also clear any pre-existing cache from prior builds — the
        // poisoned-entry path is a one-time-on-install problem so we
        // only need to flush once per launch.
        URLCache.shared.removeAllCachedResponses()
        return URLSession(configuration: config)
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .useDefaultKeys
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }()

    // MARK: Public configuration

    func configure(baseURL: URL, authToken: String? = nil) {
        self.baseURL = baseURL
        self.authToken = authToken
    }

    /// Hard-reset all stored cookies for the backend host.  Used on logout.
    func clearCookies() {
        guard let baseURL else { return }
        let store = HTTPCookieStorage.shared
        store.cookies(for: baseURL)?.forEach { store.deleteCookie($0) }
    }

    // MARK: Auth-cookie persistence
    //
    // The tRPC auth middleware on the backend validates BOTH the Bearer
    // header and the JWT cookie — but in practice the cookie path is the
    // primary one (Next.js middleware reads cookies first). The auth
    // cookie is issued as a session cookie by the server, which
    // `HTTPCookieStorage.shared` drops on app restart. That's the real
    // reason login didn't persist: keychain had the token string, the
    // Bearer header was set, but the server's middleware returned 401
    // because no auth cookie was present in the jar on the cold-boot
    // `/auth.me` call.
    //
    // These helpers snapshot the auth cookies from the shared jar after
    // sign-in, and rehydrate them into the jar on boot — with a far-
    // future `expiresDate` so the jar won't drop them as session cookies.
    // The bytes we persist are JSON-encoded HTTPCookie properties, which
    // HTTPCookie understands natively on restore.

    /// Return the auth-related cookies currently in the shared jar for
    /// the backend host, as JSON-encoded property dictionaries. Used by
    /// `EusoTripSession.signIn` to snapshot the jar once the server has
    /// issued credentials. Only cookies whose name matches the known
    /// auth cookie names are kept so we don't accidentally persist
    /// unrelated third-party cookies.
    func authCookieSnapshotJSON() -> String? {
        guard let baseURL else { return nil }
        let store = HTTPCookieStorage.shared
        // Canonical name the EusoTrip backend sets on login is
        // `app_session_id` (source of truth: `shared/const.ts:1`).
        // The earlier list was missing it, which is the ROOT CAUSE
        // of the "logged out every 10 minutes / every app update"
        // bug — the snapshot returned nil, nothing got persisted to
        // Keychain, and on any cold launch (app-update, iOS memory
        // reclaim after backgrounding ~10 min) the cookie jar came
        // back empty. The backend's tRPC middleware reads the cookie
        // first and only falls back to Bearer; with the cookie gone
        // and Bearer alone apparently not enough on some routes, the
        // driver got kicked to SignIn.
        //
        // `token` / `auth_token` / `session` / NextAuth entries are
        // kept for parity with any future auth provider swap — they
        // cost nothing to snapshot and mean the migration is a
        // one-line name-swap on the backend, not an app-side change.
        let keep: Set<String> = [
            "app_session_id",
            "token", "auth_token", "session",
            "next-auth.session-token", "__Secure-next-auth.session-token",
            // CSRF companion if the backend ever adds one. Harmless
            // to snapshot now.
            "__Host-csrf", "csrf_token",
        ]
        let cookies = (store.cookies(for: baseURL) ?? []).filter { keep.contains($0.name) }
        guard !cookies.isEmpty else { return nil }
        // HTTPCookie.properties values are plist-compatible (strings /
        // numbers / dates) but JSONSerialization chokes on Date. Encode
        // Date fields as ISO8601 strings for round-trip safety.
        let isoFmt = ISO8601DateFormatter()
        let bag: [[String: String]] = cookies.compactMap { c in
            var dict: [String: String] = [:]
            for (k, v) in (c.properties ?? [:]) {
                if let d = v as? Date {
                    dict[k.rawValue] = isoFmt.string(from: d)
                } else {
                    dict[k.rawValue] = "\(v)"
                }
            }
            return dict
        }
        guard let data = try? JSONSerialization.data(withJSONObject: bag, options: []) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Rehydrate auth cookies saved by `authCookieSnapshotJSON()` back
    /// into the shared jar. Sets `expiresDate` to +1 year so the cookie
    /// is treated as persistent (the original server-issued cookie was
    /// Session-scoped, which is what caused the cross-launch 401). Safe
    /// to call more than once; duplicates are overwritten by name+domain.
    func restoreAuthCookiesFromJSON(_ json: String) {
        guard let data = json.data(using: .utf8),
              let bag = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return }
        let isoFmt = ISO8601DateFormatter()
        let store = HTTPCookieStorage.shared
        let farFuture = Date().addingTimeInterval(365 * 24 * 60 * 60)
        for dict in bag {
            var props: [HTTPCookiePropertyKey: Any] = [:]
            for (k, v) in dict {
                let key = HTTPCookiePropertyKey(rawValue: k)
                // Dates round-trip as ISO strings — decode back to Date
                // so HTTPCookie treats the cookie as persistent.
                if k == HTTPCookiePropertyKey.expires.rawValue {
                    if let d = isoFmt.date(from: v) {
                        props[key] = d
                    } else {
                        props[key] = farFuture
                    }
                } else {
                    props[key] = v
                }
            }
            // Force a far-future expiry if the original was a session
            // cookie — otherwise the jar will drop it on next launch.
            if props[.expires] == nil {
                props[.expires] = farFuture
            }
            // HTTPCookie requires at minimum: name, value, path, domain
            // OR originURL. If any are missing, skip — malformed entry.
            guard props[.name] != nil, props[.value] != nil,
                  props[.path] != nil,
                  (props[.domain] != nil || props[.originURL] != nil),
                  let cookie = HTTPCookie(properties: props)
            else { continue }
            store.setCookie(cookie)
        }
    }

    // MARK: Routers

    lazy var loads: LoadsAPI = LoadsAPI(api: self)
    lazy var hos: HOSAPI = HOSAPI(api: self)
    lazy var auth: AuthAPI = AuthAPI(api: self)
    lazy var availability: AvailabilityAPI = AvailabilityAPI(api: self)
    lazy var registration: RegistrationAPI = RegistrationAPI(api: self)
    lazy var inspections: InspectionsAPI = InspectionsAPI(api: self)
    lazy var esang: eSangAPI = eSangAPI(api: self)
    lazy var wallet: WalletAPI = WalletAPI(api: self)
    // NOTE: `loadLifecycle` is declared once below near `agreements` (96th
    // firing — canonical). Removed the duplicate declaration here that
    // referenced the older 4-method LoadLifecycleAPI struct (which itself
    // has been deleted further down in this file). Two declarations of
    // the same lazy var on `EusoTripAPI` and two `struct LoadLifecycleAPI`
    // bodies were a hard Swift compile error ("invalid redeclaration").
    lazy var bayOps: BayOpsAPI = BayOpsAPI(api: self)
    lazy var pod: PODAPI = PODAPI(api: self)
    lazy var disputes: DisputesAPI = DisputesAPI(api: self)
    lazy var nrc: NRCAPI = NRCAPI(api: self)
    lazy var notifications: NotificationsAPI = NotificationsAPI(api: self)
    lazy var drivers: DriversAPI = DriversAPI(api: self)
    lazy var news: NewsAPI = NewsAPI(api: self)
    lazy var messaging: MessagingAPI = MessagingAPI(api: self)
    lazy var hotZones: HotZonesAPI = HotZonesAPI(api: self)
    /// HERE server-side add-ons (ad-zones, ISA, ADAS, road alerts,
    /// geofencing, location analytics, discover, EV chargers, …) consumed
    /// the SAME way the web client does — through the `hereMaps.*` tRPC
    /// router. iOS does NOT re-implement these against HERE directly; the
    /// OAuth Bearer + rate-limiting live server-side. 2026-05-21.
    lazy var hereMaps: HereMapsAPI = HereMapsAPI(api: self)
    lazy var eld: ELDAPI = ELDAPI(api: self)
    lazy var capabilities: CapabilitiesAPI = CapabilitiesAPI(api: self)
    lazy var media: MediaAPI = MediaAPI(api: self)
    lazy var reports: ReportsAPI = ReportsAPI(api: self)
    /// Spark — IO 2026 Tier 1 #21/#23/#24 (overnight briefs for
    /// Shipper / Dispatcher / Catalyst). Backed by
    /// `frontend/server/routers/spark.ts`.
    lazy var spark: SparkAPI = SparkAPI(api: self)
    /// Equipment Agent — IO 2026 Tier 2 #40 (Cortex-orchestrated
    /// trailer recommendation). Backed by
    /// `frontend/server/routers/equipmentAgent.ts`.
    lazy var equipmentAgent: EquipmentAgentAPI = EquipmentAgentAPI(api: self)
    /// XR Checklist — IO 2026 Tier 1 #12 (reefer HUD), Tier 3 #10
    /// (dock-worker POD), Tier 3 #11 (USMCA filing assistant).
    /// Backed by `frontend/server/routers/xrChecklist.ts`.
    lazy var xrChecklist: XRChecklistAPI = XRChecklistAPI(api: self)
    /// Lane Agent — IO 2026 Tier 2 #37 (conversational rate intel).
    /// Backed by `frontend/server/routers/laneAgent.ts`.
    lazy var laneAgent: LaneAgentAPI = LaneAgentAPI(api: self)
    /// Carrier Vet Agent — IO 2026 Tier 2 #38 (FMCSA + scorecard +
    /// guardian verdict). Backed by
    /// `frontend/server/routers/carrierVetAgent.ts`.
    lazy var carrierVetAgent: CarrierVetAgentAPI = CarrierVetAgentAPI(api: self)

    // --- Driver-facing surfaces added to back the gamification / wallet /
    // fleet / availability screens. Each router mirrors a file under
    // `server/routers/*.ts` in the EusoTrip backend repo.
    //
    // 61st-firing hygiene (2026-04-23): removed six orphan lazy-var
    // entry points whose backend routers do not exist and whose
    // consumer count across Views/ + ViewModels/ is zero:
    //   • fuelCard      → replaced by fleet.getFuelTransactionsMobile
    //   • achievements  → replaced by gamification.getMissions / getBadges
    //   • leaderboard   → replaced by gamification.getLeaderboard
    //   • availability  → no backend procs; fixture until router ships
    //   • rooms         → no backend procs; presence deferred
    //   • zeunDriver    → replaced by zeunMechanics.* canonical router
    // The struct bodies remain below with `@available(*, deprecated)`
    // sentinels so the next macOS-build-verified firing can finalize
    // removal after xcodebuild verification. Dead code that's
    // unreachable at the lazy-var level cannot be called at runtime,
    // so the 404-producing landmines are neutralised immediately by
    // this edit — even without the struct-body deletion.
    lazy var walletExtras: WalletExtrasAPI = WalletExtrasAPI(api: self)
    lazy var factoring: FactoringAPI = FactoringAPI(api: self)
    lazy var tax: TaxAPI = TaxAPI(api: self)
    lazy var rewards: RewardsAPI = RewardsAPI(api: self)
    lazy var gamification: GamificationAPI = GamificationAPI(api: self)
    /// Distinct tRPC router `advancedGamificationRouter` (mounted at
    /// `advancedGamification.*` in `frontend/server/routers.ts:1568`).
    /// Today's only consumer is `StreakTrackerStore` for brick 065
    /// The Haul · Streaks, via `advancedGamification.getStreakTracker`.
    /// Added in the 65th firing once MCP-verified the endpoint is live
    /// (advancedGamification.ts:1476-1544). If the surface grows, keep
    /// it separate from `gamification` — the server keeps them in two
    /// files and collapsing them on the client would mask that seam.
    lazy var advancedGamification: AdvancedGamificationAPI = AdvancedGamificationAPI(api: self)
    lazy var fleetCanonical: FleetCanonicalAPI = FleetCanonicalAPI(api: self)
    lazy var zeunMechanics: ZeunMechanicsAPI = ZeunMechanicsAPI(api: self)
    lazy var fleet: FleetAPI = FleetAPI(api: self)
    lazy var profile: ProfileAPI = ProfileAPI(api: self)
    // `lazy var loyalty: LoyaltyAPI` — dropped in the 62nd firing.
    // `loyaltyRouter` never shipped on the backend; the canonical
    // replacement is `gamification.getProfile`, wired through
    // `LoyaltyHeroStore` in `ViewModels/LiveDataStores.swift`.
    lazy var earnings: EarningsAPI = EarningsAPI(api: self)
    lazy var settlementBatching: SettlementBatchingAPI = SettlementBatchingAPI(api: self)

    /// `documentManagementRouter` — driver-facing CDL / Medical / TWIC /
    /// Hazmat / Registration / Insurance etc. document surface.
    /// MCP-verified at `frontend/server/routers/documentManagement.ts:277`
    /// (namespace mounted in `frontend/server/routers.ts:1671`).
    /// Added in the 67th firing (brick port 072 Me · Docs).
    lazy var documentManagement: DocumentManagementAPI = DocumentManagementAPI(api: self)

    /// `vehicleRouter` — driver-scoped assigned vehicle + maintenance
    /// history surface. Distinct from `fleetRouter` (company-scoped
    /// asset manager for dispatchers / terminal managers) and from
    /// `fleetCanonicalRouter` (rail/vessel). MCP-verified at
    /// `frontend/server/routers/vehicle.ts:22` (namespace mounted in
    /// `frontend/server/routers.ts:1275`). Added in the 68th firing
    /// (brick port 073 Me · Vehicle).
    lazy var vehicle: VehicleAPI = VehicleAPI(api: self)

    /// `safetyRouter` — driver-scoped safety score + categories +
    /// recent events surface. Also exposes the company-scoped stats
    /// procedures for admin screens. MCP-verified at
    /// `frontend/server/routers/safety.ts:820` (namespace mounted in
    /// `frontend/server/routers.ts:1008`). Added in the 69th firing
    /// (brick port 075 Me · Safety Score).
    lazy var safety: SafetyAPI = SafetyAPI(api: self)

    /// `trainingRouter` + `trainingLMSRouter` — driver-scoped training
    /// surface (assignments + LMS enrollments + certificates). Both
    /// namespaces are exposed through the single `TrainingAPI` wrapper
    /// for ergonomics. MCP-verified at
    /// `frontend/server/routers/training.ts:113` + `trainingLMS.ts:251,
    /// 549`. Namespaces mounted in `frontend/server/routers.ts:1017,
    /// 1488`. Added in the 70th firing (brick port 076 Me · Training).
    lazy var training: TrainingAPI = TrainingAPI(api: self)

    /// `paymentsRouter` — driver-facing Stripe payment-method surface.
    /// Lists cards + bank accounts, set-default, detach/unlink.
    /// MCP-verified at `frontend/server/routers/payments.ts:323-388`.
    /// Added in the 71st firing (brick port 077 Me · Payment Methods).
    lazy var payments: PaymentsAPI = PaymentsAPI(api: self)

    /// `complianceRouter` — cross-surface compliance reads + mutations.
    /// Today's iOS-relevant surface: `getViolations`,
    /// `getViolationStats`, `resolveViolation`. MCP-verified at
    /// `frontend/server/routers/compliance.ts:1055`. Added in the
    /// 75th firing (brick port 082 Me · Violations Manager).
    lazy var compliance: ComplianceAPI = ComplianceAPI(api: self)
    lazy var fmcsa: FMCSAAPI = FMCSAAPI(api: self)

    /// `csaScoresRouter` — FMCSA CSA scoring + DataQs challenge
    /// filer. Today's iOS-relevant surface: `submitDataQsChallenge`.
    /// MCP-verified at `frontend/server/routers/csaScores.ts:310`.
    /// Added in the 77th firing (brick port 084 Me · DataQs Filer).
    lazy var csaScores: CsaScoresAPI = CsaScoresAPI(api: self)

    /// `dataqsRouter` — FMCSA Request for Data Review (RDR) tracking
    /// + Gemini-assisted draft, reform-aware (2026 burden-of-proof).
    /// MCP-verified at `frontend/server/routers/dataqs.ts:113`.
    lazy var dataqs: DataQsAPI = DataQsAPI(api: self)

    /// `esangCoachRouter` — ESANG-powered safety coaching for the
    /// driver's 087 Me · Safety Coach screen. Role + vertical aware;
    /// hazmat is the most-stringent regulatory lens. MCP-verified at
    /// `frontend/server/routers/esangCoach.ts:510` (proc `forDriver`),
    /// namespace mounted in `frontend/server/routers.ts:1597`. Added
    /// in the 79th firing (brick port 087 Me · Safety Coach).
    lazy var esangCoach: eSangCoachAPI = eSangCoachAPI(api: self)

    /// `referralsRouter` — driver-scoped referral code + attribution.
    /// MCP-verified at `frontend/server/routers/referrals.ts:82`
    /// (procs `getMyCode`, `summary`, `listMine`, `applyCode`). Added
    /// in the 80th firing (brick port 088 Me · Invite & Earn).
    lazy var referrals: ReferralsAPI = ReferralsAPI(api: self)

    /// `gamificationRouter` / `missionsRouter` / `achievementsRouter`
    /// — unified façade reserved for any screen that wants one-shot
    /// access across the three Haul surfaces at once. (Unused after
    /// MeHaulView was restored as the canonical tabbed Haul screen
    /// wired directly to `gamification` + `messaging` — kept here
    /// because other screens may still want the composite shape.)
    lazy var haul: HaulAPI = HaulAPI(api: self)

    /// `supportRouter` — driver-scoped support tickets + optional
    /// knowledge-base search. MCP-verified at
    /// `frontend/server/routers/support.ts` (procs `getMyTickets`,
    /// `getSummary`, `createTicket`, `getTicketById`). Added in the
    /// 82nd firing (brick port 089 Me · Support & Tickets).
    lazy var support: SupportAPI = SupportAPI(api: self)

    /// `iftaCalculatorRouter` — IFTA quarterly estimator + full
    /// per-jurisdiction calculator. MCP-verified at
    /// `frontend/server/routers/iftaCalculator.ts` (procs
    /// `estimateFromLoads`, `calculateQuarter`). Added in the 83rd
    /// firing (brick port 090 Me · IFTA Tax).
    lazy var ifta: IftaAPI = IftaAPI(api: self)

    /// `detentionAccessorialsRouter` — detention pay recovery +
    /// demurrage + TONU + layover tracking. MCP-verified at
    /// `frontend/server/routers/detentionAccessorials.ts`. iOS
    /// surface today: dashboard + active + history + dispute.
    /// Added in the 84th firing (brick port 091 Me · Detention).
    lazy var detention: DetentionAPI = DetentionAPI(api: self)

    /// `permitsRouter` — driver-scoped trip / oversize / IRP / IFTA
    /// permit lifecycle (list / summary / expiring / renew). MCP-
    /// verified at `frontend/server/routers/permits.ts`. Added in
    /// the 85th firing (brick port 092 Me · Permits).
    lazy var permits: PermitsAPI = PermitsAPI(api: self)

    /// `driverQualificationRouter` — DQ file (CDL, medical card,
    /// hazmat endorsement, TWIC, drug tests, employment history,
    /// annual reviews). MCP-verified at
    /// `frontend/server/routers/driverQualification.ts`. Added in
    /// the 86th firing (brick port 093 Me · DQ File).
    lazy var dq: DriverQualificationAPI = DriverQualificationAPI(api: self)

    /// `fuelManagementRouter` — fuel card lifecycle + fuel-spend
    /// dashboard + theft detection + optimal-stop finder. MCP-
    /// verified at `frontend/server/routers/fuelManagement.ts`.
    /// Added in the 87th firing (brick port 094 Me · Fuel Cards).
    lazy var fuelMgmt: FuelManagementAPI = FuelManagementAPI(api: self)

    /// `ratesRouter` — lane analysis + market rates + trend
    /// forecasts. MCP-verified at
    /// `frontend/server/routers/rates.ts`. Added in the 88th
    /// firing (brick port 095 Me · Rate Intel).
    lazy var rates: RatesAPI = RatesAPI(api: self)

    /// `rateSheetRouter` — Schedule-A rate-sheet authoring +
    /// reconciliation engine. The web platform owns 16 procedures
    /// (create / list / get / update / version-history / calculator
    /// / EIA diesel / smart defaults / reconciliation generator /
    /// EusoTicket document fetch / ticket reconciliation / stats).
    /// MCP-verified at `frontend/server/routers/rateSheet.ts`.
    /// Pulls per-mileage band rates ($/BBL or $/lb) + surcharges
    /// (FSC, wait-time, split-load, reject, travel) so a tanker
    /// driver can preview their pay before the load is finalized.
    lazy var rateSheet: RateSheetAPI = RateSheetAPI(api: self)

    /// `eusoTicketRouter` — Bills of Lading + run tickets + per-haul
    /// receipts. Mirrors the web `/euso-ticket` page (Terminal Manager
    /// + Driver) 1:1. Procedures wired below: listRunTickets, getRunTicket,
    /// listBOLs, getTerminalStats, generateRunTicketPDF, generateBOLPDF,
    /// updateRunTicketStatus, updateBOLStatus. MCP-verified at
    /// `frontend/server/routers/eusoTicket.ts:119-686`. The receipts
    /// channel (lumper / scale / fuel / toll) lives under the existing
    /// `documentManagement` namespace — those rows are surfaced by
    /// HubCategory.loadDocs in 083_MeDocumentsHub. Added in the
    /// EusoTicket parity firing (2026-04-27).
    lazy var eusoTicket: EusoTicketAPI = EusoTicketAPI(api: self)

    /// `visualIntelligenceRouter` — VIGA. Photograph → AI analysis
    /// across 9 use cases (mechanical, gauge, seal, DVIR, cargo,
    /// POD, facility, damage, road). MCP-verified at
    /// `frontend/server/routers/visualIntelligence.ts`. Web platform
    /// uses Gemini + Anthropic image models server-side; iOS just
    /// uploads base64 + analysis-type and renders the typed result.
    lazy var viga: VIGAAPI = VIGAAPI(api: self)

    /// `authorityRouter` — DOT/MC operating-authority + lease-on
    /// (FMCSR Part 376 trip lease). Drivers use this when they need
    /// to operate under a larger carrier's authority for a specific
    /// load. Mirrors `frontend/server/routers/authority.ts` 1:1.
    /// Procedures wired below: getMyAuthority, getMyLeases,
    /// getLeaseStats, createLease, signLease, updateCompliance,
    /// terminateLease, browseAuthorities, getEquipmentAuthority,
    /// createLeaseFromFMCSA.
    lazy var authority: AuthorityAPI = AuthorityAPI(api: self)

    /// `adaptiveFeeRouter` — EusoWallet Adaptive Fee Engine. Per the
    /// April-2026 deployment playbook: 6-dimension multiplier table
    /// (country, vertical, equipment, hazmat, distance, cycle), MHI
    /// composite from DAT/FRED/EIA, gamification discount (Bronze
    /// 0% → Diamond 1.5%), full fintech stack (Instant Pay, Cash
    /// Advance, Quick Pay, Factoring). MCP-verified at
    /// `frontend/server/routers/adaptiveFee.ts`. iOS surfaces use
    /// `estimate` for live fee preview on load detail and `getMHI`
    /// for the cycle-phase chip on Home + Wallet.
    lazy var adaptiveFee: AdaptiveFeeAPI = AdaptiveFeeAPI(api: self)

    /// `ergRouter` — Emergency Response Guidebook hazmat lookup
    /// (49 CFR 172.604). MCP-verified at
    /// `frontend/server/routers/erg.ts` (procs `search`,
    /// `searchByUN`, `getGuidePage`, `getEmergencyContacts`).
    /// Added in the 89th firing (brick port 096 Me · ERG).
    lazy var erg: ErgAPI = ErgAPI(api: self)

    /// `ratingsRouter` — driver / catalyst / shipper reviews and
    /// rating summary. MCP-verified at
    /// `frontend/server/routers/ratings.ts`. Added in the 90th
    /// firing (brick port 097 Me · Ratings).
    lazy var ratings: RatingsAPI = RatingsAPI(api: self)

    /// `emergencyResponseRouter` — FEMA / pipeline-outage /
    /// hurricane driver mobilization operations. MCP-verified at
    /// `frontend/server/routers/emergencyResponse.ts` (procs
    /// `getMyMobilizations`, `respondToMobilization`,
    /// `updateMobilizationStatus`, `getGovernmentContacts`).
    /// Added in the 91st firing (brick port 098 Me · Emergency Ops).
    lazy var emergency: EmergencyAPI = EmergencyAPI(api: self)

    /// `freightClaimsRouter` — freight damage / loss / shortage /
    /// delay / contamination claims. MCP-verified at
    /// `frontend/server/routers/freightClaims.ts` (procs
    /// `getClaimsDashboard`, `getClaims`, `fileClaim`). Added in
    /// the 92nd firing (brick port 099 Me · Freight Claims).
    lazy var freightClaims: FreightClaimsAPI = FreightClaimsAPI(api: self)

    /// `appointmentsRouter` — pickup / delivery appointment
    /// lifecycle: driver-scoped list, check-in, start-loading,
    /// complete, cancel. MCP-verified at
    /// `frontend/server/routers/appointments.ts`. Added in the
    /// 93rd firing (brick port 101 Me · Appointments).
    lazy var appointments: AppointmentsAPI = AppointmentsAPI(api: self)

    /// `contactsRouter` — driver's contact directory (shippers /
    /// catalysts / dispatchers / brokers / drivers). MCP-verified
    /// at `frontend/server/routers/contacts.ts`. Added in the
    /// 94th firing (brick port 102 Me · Contacts).
    lazy var contacts: ContactsAPI = ContactsAPI(api: self)

    /// `agreementsRouter` — party-to-party agreements with
    /// Gradient-Ink e-signature. Driver sees all agreements
    /// where they're party A or B (lease-on, owner-op,
    /// employment, dispatch service). MCP-verified at
    /// `frontend/server/routers/agreements.ts`. Added in the
    /// 95th firing (brick port 103 Me · Agreements).
    lazy var agreements: AgreementsAPI = AgreementsAPI(api: self)

    /// `loadLifecycleRouter` — the canonical load state-machine
    /// driver. `getAvailableTransitions(loadId)` returns the
    /// legal next hops for the caller's role; `executeTransition`
    /// flips state with guards + optional location/data/
    /// compliance blocks. MCP-verified at
    /// `frontend/server/routers/loadLifecycle.ts`. Added in the
    /// 96th firing as the foundation under the trip-lifecycle
    /// screens 013–051 (per gap analysis 2026-04-24).
    lazy var loadLifecycle: LoadLifecycleAPI = LoadLifecycleAPI(api: self)

    /// `spectraMatchRouter` — crude-oil + product identification
    /// surface backing lifecycle screens 030 (Loading in Progress)
    /// and 031 (Spectra-Match Verdict). Backend procedures live at
    /// `frontend/server/routers/spectraMatch.ts` with `identify`,
    /// `getHistory`, `getLearningStats`, `getCrudeTypes`, and the
    /// terminal-product / destination-intelligence aux surfaces.
    /// Added 2026-04-24 (eusotrip-killers ledger-hygiene firing) to
    /// close the only material backend→client gap surfaced by the
    /// mock-data audit (the hardcoded `samples: [SampleLane]` array
    /// in 031_SpectraMatchVerdict.swift). Driver-facing screens now
    /// pull verified-load history via `spectraMatch.getHistory`.
    lazy var spectraMatch: SpectraMatchAPI = SpectraMatchAPI(api: self)

    /// `shippersRouter` — the canonical Shipper-role surface backing
    /// the 2xx Shipper screen track (200 Shipper Home, etc.). MCP-
    /// verified at `frontend/server/routers/shippers.ts` with
    /// `create`, `update`, `delete`, `getDashboardStats`,
    /// `getActiveLoads`, `getLoadsRequiringAttention`, and
    /// `getRecentLoads`. Added 2026-04-24 (eusotrip-killers next-port
    /// firing) at the start of the role-by-role build per the 2027
    /// motivation prompt: "all 24 users piece by piece every screen
    /// each role at a time til you are done."
    lazy var shipper: ShipperAPI = ShipperAPI(api: self)

    /// Live tRPC handle for the **Carrier** role surface. Added
    /// 2026-04-25 (100th eusotrip-killers firing, brick port 300 ·
    /// `Views/Carrier/300_CarrierHome.swift`). Backend convention
    /// mirrors `shippers.*` — every procedure name on this struct
    /// hits the real `carriers.*` router. If the parallel router
    /// has not landed yet, `EusoTripAPIError.trpcError` propagates
    /// and the live stores in `LiveDataStores.swift` surface
    /// `EusoEmptyState` per doctrine §11 + `MockDataGuard` — never
    /// fake data, ever.
    lazy var carrier: CarrierAPI = CarrierAPI(api: self)

    /// Live tRPC handle for the **Broker** role surface. Added
    /// 2026-04-25 (99th eusotrip-killers firing, brick port 400 ·
    /// `Views/Broker/400_BrokerHome.swift`). Backend convention
    /// mirrors `carriers.*` / `shippers.*` — every procedure name
    /// on this struct hits the real `brokers.*` router. The broker
    /// sits between the shipper (originator) and carrier (mover),
    /// so the home re-frames the four-card hierarchy around margin
    /// and tender flow rather than active-load count. If the
    /// parallel router has not landed yet,
    /// `EusoTripAPIError.trpcError` propagates and the live stores
    /// in `LiveDataStores.swift` surface `EusoEmptyState` per
    /// doctrine §11 + `MockDataGuard` — never fake data, ever.
    lazy var broker: BrokerAPI = BrokerAPI(api: self)

    /// Live tRPC handle for the **Catalyst** role surface. Added
    /// 2026-04-25 (102nd eusotrip-killers firing, brick port 500 ·
    /// `Views/Catalyst/500_CatalystHome.swift`). Backend convention
    /// mirrors `brokers.*` / `carriers.*` / `shippers.*` — every
    /// procedure name on this struct hits the real `catalysts.*`
    /// router. Catalyst is the AI-augmented dispatch / SpectraMatch
    /// operator role per the §16 intelligence slice (Autopilot
    /// 7-layer cortex, 52 agents); the home re-frames the four-card
    /// hierarchy around match flow + fit-score rather than tender
    /// flow or active-load count. If the parallel router has not
    /// landed yet, `EusoTripAPIError.trpcError` propagates and the
    /// live stores in `LiveDataStores.swift` surface
    /// `EusoEmptyState` per doctrine §11 + `MockDataGuard` — never
    /// fake data, ever.
    lazy var catalyst: CatalystAPI = CatalystAPI(api: self)

    /// Escort role surface — `escorts.*` tRPC namespace. Added in
    /// the 103rd eusotrip-killers firing alongside the 600 Escort
    /// Home brick. Mirrors the convention of the Catalyst (502nd
    /// firing), Broker (99th), Carrier (100th) and Shipper (91st)
    /// accessors.
    lazy var escort: EscortAPI = EscortAPI(api: self)

    /// Terminal Manager role surface — `terminals.*` tRPC namespace.
    /// Added in the 107th eusotrip-killers firing alongside the
    /// 700 Terminal Home brick. Mirrors the convention of the
    /// Escort (103rd), Catalyst (102nd), Broker (99th), Carrier
    /// (100th) and Shipper (91st) accessors. Terminal Manager owns
    /// port/yard operations: gate-in / gate-out flow, container
    /// movements, dock assignment, dwell + demurrage exposure, and
    /// hazmat clearance per the §16 admin-tenant-ops + intermodal
    /// slices. If the parallel router has not landed yet,
    /// `EusoTripAPIError.trpcError` propagates and the live stores
    /// in `LiveDataStores.swift` surface `EusoEmptyState` per
    /// doctrine §11 + `MockDataGuard` — never fake data, ever.
    lazy var terminal: TerminalAPI = TerminalAPI(api: self)

    /// Admin role surface — `admin.*` tRPC namespace. Added in the
    /// 108th eusotrip-killers firing alongside the 800 Admin Home
    /// brick. Mirrors the convention of the Terminal (107th),
    /// Escort (103rd), Catalyst (102nd), Broker (99th), Carrier
    /// (100th) and Shipper (91st) accessors. Admin owns
    /// platform-wide tenant ops, user lifecycle, approvals, support
    /// tickets, and platform health per the §16 admin-tenant-ops
    /// slice (admin console, tenants, portals, branding, approvals,
    /// experiments, control tower, DD alerts). If the parallel
    /// router has not landed yet, `EusoTripAPIError.trpcError`
    /// propagates and the live stores in `LiveDataStores.swift`
    /// surface `EusoEmptyState` per doctrine §11 + `MockDataGuard`
    /// — never fake data, ever. Note: §16 flags `admin.impersonateUser`
    /// and several system-settings endpoints as returning mock data
    /// today; the iOS surface intentionally does NOT consume those
    /// endpoints — only the legitimate dashboard envelope shapes
    /// listed below.
    lazy var admin: AdminAPI = AdminAPI(api: self)

    /// `usersRouter` — cross-role user-scoped endpoints (notification
    /// preferences, profile updates, role/tenant introspection). Distinct
    /// from `auth.*` (login/logout/MFA), `notifications.*` (per-(channel,
    /// category) toggle for the Driver Me Notifications surface), and
    /// `preferences.*` (legacy locale/theme bag). MCP-verified at
    /// `frontend/server/routers/users.ts:1648` for `getNotificationPreferences`
    /// and `frontend/server/routers/users.ts:1680` for `updateNotificationPreferences`.
    /// Both procedures are `protectedProcedure` (any authenticated user)
    /// so shippers, drivers, brokers, carriers, catalysts all consume the
    /// same matrix shape — the iOS Shipper Settings surface (brick 211)
    /// uses these as its canonical preference store. Added in the 129th
    /// firing (eusotrip-killers · 2026-04-26 · port_211_ShipperSettings).
    lazy var users: UsersAPI = UsersAPI(api: self)

    /// `loadBiddingRouter` — canonical bid-chain surface used by the
    /// web platform's bid management page. Drivers and catalysts hit
    /// `submit` to one-tap accept a posted rate (Book Now) or to
    /// open a counter-offer chain. The same row schema (`loadBids`)
    /// powers both web and app so a bid placed on iOS shows up on
    /// the shipper's web dashboard within a socket frame.
    lazy var loadBidding: LoadBiddingAPI = LoadBiddingAPI(api: self)

    /// `loadTemplatesRouter` — saved lane / commodity / equipment
    /// configurations. Shippers reuse a template when posting a
    /// recurring load (same Houston→Atlanta, same dry-van shape, same
    /// rate structure) so they don't re-key the same fields every
    /// week. MCP-verified at `frontend/server/routers/loadTemplates.ts`
    /// (procs `list`, `get`, `create`, `update`, plus archive +
    /// favorite mutations). iOS surface today: settings card list +
    /// post-load prefill. Added in the lane-configs parity firing
    /// (2026-04-27) — replaces the "Coming soon" placeholder on the
    /// 211 Shipper Settings screen.
    lazy var loadTemplates: LoadTemplatesAPI = LoadTemplatesAPI(api: self)

    /// `controlTowerRouter` — multi-modal supply-chain visibility
    /// (truck + rail + vessel). Backs the Shipper Control Tower
    /// brick (212), Catalyst dispatch overview, and any future
    /// admin / broker control surface. MCP-verified at
    /// `frontend/server/routers/controlTower.ts` (procs `overview`,
    /// `exceptions`, `recentActivity`). Added 2026-04-27 in the
    /// shipper round-2 trajectory firing.
    lazy var controlTower: ControlTowerAPI = ControlTowerAPI(api: self)

    /// `co2CalculatorRouter` — per-shipment carbon emissions across
    /// truck / rail / vessel / air with offset pricing. Backs the
    /// Shipper Sustainability brick (214) + any future
    /// per-load-detail "carbon footprint" chip. MCP-verified at
    /// `frontend/server/routers/co2Calculator.ts` (procs
    /// `calculateTruckShipment`, `calculateMultiModal`,
    /// `calculateVesselShipment` (vessel-role gated)). Added
    /// 2026-04-27 in the shipper round-2 trajectory firing.
    lazy var co2: Co2CalculatorAPI = Co2CalculatorAPI(api: self)

    /// `rfpManagerRouter` — RFP / RFQ procurement workflow. Create
    /// lane RFPs, publish to eligible carriers, collect bid
    /// responses, score them on rate / service / safety / capacity /
    /// experience, award by lane. Backs the Shipper RFP brick (215)
    /// and any future Catalyst-side bid-response surface. MCP-
    /// verified at `frontend/server/routers/rfpManager.ts` (procs
    /// `getRFPs`, `getRFPDetail`, `createRFP`, `publishRFP`,
    /// `getBidResponses`, `scoreResponses`, `awardLane`,
    /// `batchAward`). Added 2026-04-27 in the shipper round-3 firing.
    lazy var rfp: RFPManagerAPI = RFPManagerAPI(api: self)

    /// `complianceRouter` — shipper-scope subset (business
    /// verification + credit + insurance + document vault). Backs
    /// the Shipper Compliance brick (216). Distinct from the
    /// existing `compliance` namespace already wired for driver
    /// violations — that one resolves to `compliance.getViolations`
    /// etc; this set hits `getShipperCompliance` /
    /// `getShipperDocuments` / `uploadDocument` (all
    /// `protectedProcedure`, accept any auth role). MCP-verified at
    /// `frontend/server/routers/compliance.ts:2542+`. Added
    /// 2026-04-27 in the shipper round-3 firing.
    lazy var shipperCompliance: ShipperComplianceAPI = ShipperComplianceAPI(api: self)

    /// `contractsRouter` — agreement / volume-commitment lifecycle.
    /// Backs the Shipper Contracts brick (217). MCP-verified at
    /// `frontend/server/routers/contracts.ts` (procs `getAll`,
    /// `getStats`, `list`, `getById`, `create`, `update`,
    /// `submitForApproval`, `approve`, `renew`, `terminate`).
    /// Added 2026-04-27 in the shipper round-3 firing.
    lazy var contracts: ContractsAPI = ContractsAPI(api: self)

    /// `freightClaimsRouter` — shipper-as-claimant view of damage /
    /// loss / shortage / delay claims. Backs the Shipper Freight
    /// Claims brick (219). Distinct from the existing driver-side
    /// `freightClaims` lazy var — that one targets the
    /// driver-as-defendant flow; this set surfaces the dashboard +
    /// claim list + per-claim detail for the shipper. MCP-verified
    /// at `frontend/server/routers/freightClaims.ts:75+`. Mounted
    /// as `shipperFreightClaims` to avoid colliding with the
    /// driver-side `freightClaims` namespace.
    lazy var shipperFreightClaims: ShipperFreightClaimsAPI = ShipperFreightClaimsAPI(api: self)

    /// `ratesRouter` (lane-rate / market / trends). Backs Shipper
    /// 220 ShipperRateBoard. Mounted as `ratesNS` because `rates`
    /// would shadow the existing `rates: RatesAPI` mount above.
    lazy var ratesNS: ShipperRatesAPI = ShipperRatesAPI(api: self)

    /// `telemetryRouter` (live driver position + trail). Backs
    /// Shipper 222 ShipperLiveTracking. Mounted as `shipperTelemetry`
    /// to avoid colliding with any future driver-side telemetry mount.
    lazy var shipperTelemetry: ShipperTelemetryAPI = ShipperTelemetryAPI(api: self)

    /// `agreementsRouter` shipper-scope. Backs 223 ShipperAgreements
    /// (companion to 217 Contracts — agreements are the auth-trail of
    /// signatures, contracts are the volume-commitment lifecycle).
    lazy var shipperAgreements: ShipperAgreementsAPI = ShipperAgreementsAPI(api: self)

    /// `credentialScannerRouter` — Gemini-powered structured OCR for
    /// every credential in the registration wizard (CDL, COI, medical
    /// examiner cert, USDOT cert, TWIC, FRA Part 240/242, USCG MMC,
    /// SCT permit, NSC cert, EIN letter, CRA business, RFC).
    /// Covers all 3 verticals × 3 countries.
    lazy var credentialScanner: CredentialScannerAPI = CredentialScannerAPI(api: self)

    /// `documentRouter` — master classifier for every upload /
    /// bulk-upload surface. Pass any document image / PDF and get
    /// back a classifiedType (60+ supported) + confidence + summary
    /// + extractedFields + dispatchTarget (the canonical tRPC proc
    /// to call next with the extracted fields). Use this whenever a
    /// shipper / driver / catalyst drops a file into Templates /
    /// Bulk / Documents.
    lazy var documentRouter: DocumentRouterAPI = DocumentRouterAPI(api: self)

    /// `fleetRegistrationRouter` — NHTSA VIN decode + bulk vehicle
    /// + driver intake during carrier onboarding. Seeds Zeun
    /// maintenance schedules and DVIR baseline rows so the fleet
    /// is operationally ready the moment the wizard finishes.
    lazy var fleetRegistration: FleetRegistrationAPI = FleetRegistrationAPI(api: self)

    /// `supplyChain.getMyPartners` — partner directory backing 224
    /// ShipperPartnerDirectory (mirror of web `MyPartners.tsx`).
    /// Companion to `agreements` (signed-contract layer above raw
    /// partnerships).
    lazy var supplyChain: SupplyChainAPI = SupplyChainAPI(api: self)

    /// `documentsRouter` — Documents Center (BOL, run-tickets,
    /// agreements, insurance certs, W9s). Backs 226
    /// ShipperDocumentCenter (mirror of web `DocumentCenter.tsx`).
    lazy var documents: DocumentsAPI = DocumentsAPI(api: self)

    /// Shipper-scope settlement detail / approve / dispute. Mounts
    /// the `earningsRouter` procs that a SHIPPER (not a DRIVER) hits
    /// when reviewing the settlement workflow. Backs 227
    /// ShipperSettlementDetail (mirror of web `SettlementDetails.tsx`
    /// shipper-action surface).
    lazy var shipperSettlements: ShipperSettlementsAPI = ShipperSettlementsAPI(api: self)

    /// `allocationTracker.*` — daily petroleum nomination + contract
    /// fulfillment dashboard. Backs 230 ShipperAllocations (mirror of
    /// web `allocations/AllocationDashboard.tsx`).
    lazy var allocations: AllocationsAPI = AllocationsAPI(api: self)

    /// `loadBoard.*` — public-loadboard browse / search / book.
    /// Different namespace from `loads.search` (the bare loadsRouter
    /// projection). loadBoard returns market stats + lane-contract
    /// enrichment + radius-aware origin/destination filtering. Backs
    /// 108 MeLoadBoard (driver-facing browse + bid entry).
    lazy var loadBoard: LoadBoardAPI = LoadBoardAPI(api: self)

    /// `vesselShipments.*` ocean-track surface — live AIS position, historical
    /// track polyline, scheduled port calls, per-container geofence positions,
    /// and the INTTRA cross-carrier ocean-shipment track. Backs 003 Vessel
    /// Live Tracking (great-circle map). MCP-verified procs in
    /// `frontend/server/routers/vesselShipments.ts`
    /// (liveVesselPosition:1032, getVesselTrack:1085, getVesselPortCalls:1060,
    /// getContainerPositions:950, liveTrackOceanShipment:1132).
    lazy var vesselTrack: VesselTrackAPI = VesselTrackAPI(api: self)

    // MARK: Low-level tRPC invocation

    /// GET /api/trpc/<path>?input=<url-encoded-JSON>
    func query<Output: Decodable, Input: Encodable>(
        _ path: String,
        input: Input
    ) async throws -> Output {
        guard let baseURL else { throw EusoTripAPIError.notConfigured }
        let payload = TRPCInputEnvelope(json: input)
        let data = try encoder.encode(payload)
        let encoded = String(data: data, encoding: .utf8) ?? "{}"

        // URLQueryItem percent-encodes the value itself when URLComponents
        // assembles the final URL. We MUST pass the raw JSON string here —
        // pre-encoding with addingPercentEncoding(.urlQueryAllowed) caused
        // URLComponents to encode the percent signs a second time, so the
        // server saw `%257B%2522json...` and Node's JSON.parse reported
        // `Unexpected token '%', "%7B%22json"... is not valid JSON`
        // as the error body, which surfaced in Driver Intel as
        // "Can't reach news feed - Unexpected token '%'...".
        let url = baseURL
            .appendingPathComponent("api/trpc")
            .appendingPathComponent(path)
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { throw EusoTripAPIError.badURL }
        comps.queryItems = [URLQueryItem(name: "input", value: encoded)]
        guard let finalURL = comps.url else { throw EusoTripAPIError.badURL }

        var req = URLRequest(url: finalURL)
        req.httpMethod = "GET"
        // Force every tRPC query to hit the network — never serve a
        // cached response. A previous build that failed loads.getById
        // (pre-migration 0307) could have its error response cached
        // by URLCache; until the cache entry expired the iOS app
        // would keep replaying the old error even after the server
        // started returning success.
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.setValue("no-cache", forHTTPHeaderField: "Pragma")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let authToken {
            req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        if let pushDeviceToken {
            req.setValue(pushDeviceToken, forHTTPHeaderField: "x-push-token")
        }
        return try await perform(req)
    }

    func queryNoInput<Output: Decodable>(_ path: String) async throws -> Output {
        return try await query(path, input: TRPCEmptyInput())
    }

    /// Raw tRPC query that returns the server response bytes verbatim.
    /// Used by the Pulse relay path: the wrist sends us a path +
    /// already-serialized `{"json": <input>}` string, we run the GET
    /// through the authenticated iOS session (cookies + bearer), and
    /// hand back the raw `Data` for the wrist to decode with its own
    /// envelope parser. No typed decoding happens on the phone — the
    /// wrist remains the authoritative decoder so rolling the server
    /// row shape never requires coordinated phone + watch deploys.
    func rawQuery(path: String, inputJSON: String) async throws -> Data {
        guard let baseURL else { throw EusoTripAPIError.notConfigured }
        let url = baseURL
            .appendingPathComponent("api/trpc")
            .appendingPathComponent(path)
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { throw EusoTripAPIError.badURL }
        // tRPC expects the wire to be `{"json": <input>}`. If the
        // wrist already wrapped its payload we pass it through; if
        // it sent a bare value we wrap it here.
        let envelope: String = {
            let trimmed = inputJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") && trimmed.contains("\"json\"") {
                return trimmed
            }
            return "{\"json\":\(trimmed.isEmpty ? "{}" : trimmed)}"
        }()
        comps.queryItems = [URLQueryItem(name: "input", value: envelope)]
        guard let finalURL = comps.url else { throw EusoTripAPIError.badURL }

        var req = URLRequest(url: finalURL)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let authToken {
            req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        if let pushDeviceToken {
            req.setValue(pushDeviceToken, forHTTPHeaderField: "x-push-token")
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw EusoTripAPIError.httpStatus(0, "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw EusoTripAPIError.httpStatus(
                http.statusCode,
                String(data: data, encoding: .utf8) ?? ""
            )
        }
        return data
    }

    /// Fetch raw bytes from an arbitrary HTTPS URL via the session
    /// that already owns our cookies + bearer. Attaches the bearer
    /// only when the URL's host matches the configured `baseURL`
    /// host so signed third-party URLs (Azure Blob SAS, S3 pre-sign)
    /// don't get their signature clobbered by an extra Auth header.
    /// Used by the in-app PDF viewer + the file-download share sheet
    /// so every doc render stays in-app and never punts to Safari.
    func fetchAuthenticatedData(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/pdf,image/*,application/octet-stream,*/*", forHTTPHeaderField: "Accept")
        if let token = authToken,
           let baseHost = baseURL?.host,
           let urlHost = url.host,
           urlHost.caseInsensitiveCompare(baseHost) == .orderedSame {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let pushDeviceToken {
            req.setValue(pushDeviceToken, forHTTPHeaderField: "x-push-token")
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw EusoTripAPIError.httpStatus(0, "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw EusoTripAPIError.httpStatus(
                http.statusCode,
                String(data: data, encoding: .utf8) ?? ""
            )
        }
        return (data, http)
    }

    /// POST /api/trpc/<path>  body: {"json": <input>}
    func mutation<Output: Decodable, Input: Encodable>(
        _ path: String,
        input: Input
    ) async throws -> Output {
        guard let baseURL else { throw EusoTripAPIError.notConfigured }
        let url = baseURL
            .appendingPathComponent("api/trpc")
            .appendingPathComponent(path)

        let payload = TRPCInputEnvelope(json: input)
        let body = try encoder.encode(payload)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let authToken {
            req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        if let pushDeviceToken {
            req.setValue(pushDeviceToken, forHTTPHeaderField: "x-push-token")
        }
        req.httpBody = body

        return try await perform(req)
    }

    func mutationNoInput<Output: Decodable>(_ path: String) async throws -> Output {
        return try await mutation(path, input: TRPCEmptyInput())
    }

    // MARK: Shared transport

    private func perform<Output: Decodable>(_ req: URLRequest) async throws -> Output {
        let (respData, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw EusoTripAPIError.httpStatus(0, "No HTTP response")
        }

        // Extract Bearer token from Set-Cookie if the backend issued one.
        // The web platform's canonical session cookie is `app_session_id`
        // (see `frontend/shared/const.ts:1` — `COOKIE_NAME` import in
        // routers.ts powers every res.cookie() call in the auth flow).
        // The earlier `token` / `auth_token` allowlist never matched, so
        // `self.authToken` stayed nil after every successful login,
        // `keychain.save(key: kAuthToken, value: token)` no-op'd because
        // the optional bind failed, and the next cold launch had no
        // bearer to restore — kicking the user back to SignIn on every
        // app start. Including `app_session_id` here closes that loop.
        if let url = req.url,
           let fields = http.allHeaderFields as? [String: String] {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
            for c in cookies where c.name == "app_session_id"
                                || c.name == "token"
                                || c.name == "auth_token" {
                if self.authToken == nil { self.authToken = c.value }
            }
        }

        // tRPC can return 200 with an error envelope, or 4xx with an error envelope.
        // Decode the envelope FIRST (before the bare 401/403 check) so we can
        // promote UNAUTHORIZED errors to `.unauthenticated` using the real
        // code/httpStatus, while still surfacing the server's human-readable
        // message for every other trpc error (rate limits, validation, etc.).
        if let err = try? decoder.decode(TRPCErrorEnvelope.self, from: respData) {
            let inner = err.error.json
            let httpStatus = inner.data?.httpStatus ?? http.statusCode
            let code = inner.data?.code ?? ""
            if httpStatus == 401 || httpStatus == 403 || code == "UNAUTHORIZED" || code == "FORBIDDEN" {
                throw EusoTripAPIError.unauthenticated
            }
            throw EusoTripAPIError.trpcError(inner.message ?? "Request failed")
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw EusoTripAPIError.unauthenticated
        }

        guard 200..<300 ~= http.statusCode else {
            let body = String(data: respData, encoding: .utf8) ?? ""
            throw EusoTripAPIError.httpStatus(http.statusCode, body)
        }

        do {
            let env = try decoder.decode(TRPCResult<Output>.self, from: respData)
            return env.result.data.json
        } catch {
            throw EusoTripAPIError.decodingFailed(String(describing: error))
        }
    }
}

// MARK: - loadsRouter

struct LoadsAPI {
    unowned let api: EusoTripAPI

    /// `loadsRouter.search` — returns a projection (LoadSummary).
    /// Filters mirror the router's zod input.
    func search(
        query: String? = nil,
        status: String? = nil,
        cargoType: String? = nil,
        limit: Int = 30
    ) async throws -> [LoadSummary] {
        struct Input: Encodable {
            let query: String?
            let status: String?
            let cargoType: String?
            let limit: Int
        }
        let input = Input(query: query, status: status,
                          cargoType: cargoType, limit: limit)
        return try await api.query("loads.search", input: input)
    }

    /// `loadsRouter.getById` — full record.
    func getById(_ id: Int) async throws -> Load {
        struct Input: Encodable { let id: Int }
        return try await api.query("loads.getById", input: Input(id: id))
    }

    // MARK: - LoadDetail (Shipper · 205 surface)
    //
    // Full server-shaped projection of `loads.getById` mirrored verbatim
    // from `frontend/server/routers/loads.ts:1046–1130`. Differs from
    // legacy `Load` Codable in two important ways:
    //   1. The backend serializes `id` as String (`String(load.id)`) and
    //      `distance` as a Number (resolvedDistance via haversine when DB
    //      is missing) — so this struct decodes them as `String` and
    //      `Double` respectively. Legacy `Load.id: Int` was decoded from
    //      a server-side numeric and is brittle against the new shape.
    //   2. `pickupLocation` / `deliveryLocation` are narrowed to {city,
    //      state} on the server-side projection — the addresses are
    //      surfaced via `origin`/`destination` instead.
    //
    // The whole envelope decodes optional everywhere a column may be
    // null in the row (every shipper-posted draft starts with most
    // columns blank). 205's view renders an em-dash neutral state for
    // any nil — never fake data.

    /// Narrow city/state projection used in the server `pickupLocation`
    /// and `deliveryLocation` slots of the `loads.getById` response.
    struct LoadCityState: Decodable, Hashable {
        let city: String?
        let state: String?
        /// Coords land here when the server's loads.getById self-heal
        /// flow hits a successful HERE geocode. The iOS Load Detail
        /// map renders a real HereMapView lane when both endpoints
        /// have non-zero lat/lng; otherwise it shows the loading
        /// skeleton until the next read.
        let lat: Double?
        let lng: Double?
        let address: String?
        let zipCode: String?

        /// "Shreveport, LA" — empty string when both pieces are missing.
        var cityState: String {
            [city, state]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: ", ")
        }
    }

    /// Wider {address, city, state, zip} projection used in the server
    /// `origin` and `destination` slots of the response.
    struct LoadAddress: Decodable, Hashable {
        let address: String?
        let city: String?
        let state: String?
        let zip: String?
    }

    /// Full load detail mirrored from `loads.getById` server response.
    /// Every numeric DECIMAL field arrives as a String (Drizzle's
    /// MySQL DECIMAL serializer); `distance` is the only number, since
    /// the server resolves it via haversine + 1.2x road factor when the
    /// raw column is empty.
    struct LoadDetail: Decodable, Identifiable, Hashable {
        // Identity
        let id: String
        let loadNumber: String
        let status: String
        let shipperId: Int?
        let driverId: Int?
        let catalystId: Int?

        // Cargo
        let cargoType: String?
        let hazmatClass: String?
        let unNumber: String?
        let weight: String?
        let weightUnit: String?
        let commodity: String?
        let commodityName: String?
        let ergGuide: Int?
        let equipmentType: String?
        let spectraMatchVerified: Bool?

        // Geography
        let origin: LoadAddress?
        let destination: LoadAddress?
        let pickupLocation: LoadCityState?
        let deliveryLocation: LoadCityState?
        let distance: Double?
        let distanceUnit: String?

        // Dates (ISO strings; nullable on draft rows)
        let pickupDate: String?
        let deliveryDate: String?
        let estimatedDeliveryDate: String?
        let actualDeliveryDate: String?
        let createdAt: String?
        let updatedAt: String?
        let biddingEnds: String?

        // Money
        let rate: String?
        let currency: String?
        let suggestedRateMin: Double?
        let suggestedRateMax: Double?

        // ─── 2026-05-17 · Multi-modal payload (migration 0307) ───
        // Optional on the wire so older deploys (missing columns)
        // decode cleanly via nil. Every read surface that surfaces a
        // load now branches on these — the load row mode badge, the
        // detail screen pricing card (WS vs $/mile), the Catalyst /
        // Broker / Driver downstream views all consume them.
        let transportMode: String?
        let vesselClass: String?
        let multiVehicleCount: Int?
        let permitType: String?
        let originPort: String?
        let destPort: String?
        let worldscalePct: String?    // DECIMAL → String on the wire
        let worldscaleFlat: String?
        let rateUnit: String?

        // Misc
        let notes: String?

        // MARK: Derived

        /// Numeric integer id for legacy callers (driver screens still
        /// pass Int into `getById(_ id: Int)` for the older surface).
        var numericId: Int { Int(id) ?? 0 }

        /// Rate as Double in currency-major unit. Backend sends DECIMAL
        /// columns as strings; coerce safely.
        var rateValue: Double { Double(rate ?? "") ?? 0 }

        /// Weight as Double.
        var weightValue: Double { Double(weight ?? "") ?? 0 }

        /// "$2,440" — em-dash when the column is missing.
        var rateDisplay: String {
            guard rateValue > 0 else { return "—" }
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.currencyCode = currency ?? "USD"
            f.maximumFractionDigits = 0
            return f.string(from: NSNumber(value: rateValue)) ?? "$\(Int(rateValue))"
        }

        /// "620 mi" — em-dash when missing.
        var distanceDisplay: String {
            guard let d = distance, d > 0 else { return "—" }
            let unit = (distanceUnit?.isEmpty == false ? distanceUnit! : "mi")
            return "\(Int(d.rounded())) \(unit)"
        }

        /// "42,000 lb" — em-dash when missing or zero.
        var weightDisplay: String {
            guard weightValue > 0 else { return "—" }
            let unit = (weightUnit?.isEmpty == false ? weightUnit! : "lb")
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.maximumFractionDigits = 0
            let str = f.string(from: NSNumber(value: weightValue)) ?? "\(Int(weightValue))"
            return "\(str) \(unit)"
        }

        /// "Shreveport, LA → Dallas, TX" — em-dash when both sides are missing.
        var laneDisplay: String {
            let o = pickupLocation?.cityState ?? ""
            let d = deliveryLocation?.cityState ?? ""
            switch (o.isEmpty, d.isEmpty) {
            case (true, true):   return "—"
            case (false, true):  return "\(o) → —"
            case (true, false):  return "— → \(d)"
            case (false, false): return "\(o) → \(d)"
            }
        }
    }

    /// `loads.getById` — server returns the full envelope. Server expects
    /// `{ id: string }` (Zod `z.string()`) and tolerates numeric ids inside
    /// the handler via `parseInt`, but this method enforces the strict
    /// wire contract.
    func getDetail(id: String) async throws -> LoadDetail? {
        struct Input: Encodable { let id: String }
        return try await api.query("loads.getById", input: Input(id: id))
    }

    // MARK: - updateLoadStatus (Catalyst 305 + Driver lifecycle)

    /// Server-side `loads.updateLoadStatus` enum (loads.ts:3373). The
    /// Catalyst 305 status picker only surfaces a subset (the manually
    /// updatable transit states) — the lifecycle states like
    /// `en_route_pickup` / `at_pickup` / `loading` flip via the driver
    /// app's lifecycle screens (013-051), not catalyst-side.
    enum LoadStatusUpdate: String, Encodable, CaseIterable, Hashable {
        case posted
        case bidding
        case assigned
        case enRoutePickup     = "en_route_pickup"
        case atPickup          = "at_pickup"
        case loading
        case inTransit         = "in_transit"
        case atDelivery        = "at_delivery"
        case unloading
        case delivered
        case cancelled
        case disputed
        case tempExcursion     = "temp_excursion"
        case reeferBreakdown   = "reefer_breakdown"
        case contaminationReject = "contamination_reject"
        case sealBreach        = "seal_breach"
        case weightViolation   = "weight_violation"

        /// Human-readable label for the status picker UI.
        var label: String {
            switch self {
            case .posted:               return "Posted"
            case .bidding:              return "Bidding"
            case .assigned:             return "Assigned"
            case .enRoutePickup:        return "En route to pickup"
            case .atPickup:             return "At pickup"
            case .loading:              return "Loading"
            case .inTransit:            return "In transit"
            case .atDelivery:           return "At delivery"
            case .unloading:            return "Unloading"
            case .delivered:            return "Delivered"
            case .cancelled:            return "Cancelled"
            case .disputed:             return "Disputed"
            case .tempExcursion:        return "Temperature excursion"
            case .reeferBreakdown:      return "Reefer breakdown"
            case .contaminationReject:  return "Contamination reject"
            case .sealBreach:           return "Seal breach"
            case .weightViolation:      return "Weight violation"
            }
        }
    }

    struct LoadStatusUpdateResult: Decodable {
        let success: Bool?
        let loadId: String?
        let newStatus: String?
        let previousStatus: String?
        let updatedAt: String?
        
        enum CodingKeys: String, CodingKey {
            case success, loadId, newStatus, previousStatus, updatedAt
        }
        
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.success = try c.decodeIfPresent(Bool.self, forKey: .success)
            self.loadId = try c.decodeIfPresent(String.self, forKey: .loadId)
            self.newStatus = try c.decodeIfPresent(String.self, forKey: .newStatus)
            self.previousStatus = try c.decodeIfPresent(String.self, forKey: .previousStatus)
            self.updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        }
    }

    /// `loads.updateLoadStatus` — flips the `loads.status` column and
    /// fans out `LOAD_STATE_CHANGED` over the WebSocket. Authorized for
    /// shipper-of-record (cancel-only), catalyst (anything), admin.
    /// Optional `lat`/`lng` are stamped onto the load's current
    /// location; optional `notes` are appended to special instructions.
    func updateLoadStatus(
        loadId: String,
        status: LoadStatusUpdate,
        lat: Double? = nil,
        lng: Double? = nil,
        notes: String? = nil
    ) async throws -> LoadStatusUpdateResult {
        struct Input: Encodable {
            let loadId: String
            let status: String
            let lat: Double?
            let lng: Double?
            let notes: String?
        }
        return try await api.mutation(
            "loads.updateLoadStatus",
            input: Input(loadId: loadId, status: status.rawValue, lat: lat, lng: lng, notes: notes)
        )
    }

    /// `loads.update` — partial-update the load record. Used by the
    /// Shipper 205 in-app "Edit load" sheet (replaces the prior
    /// "Open on web" continuation). Server enforces shipper ownership
    /// + delivery-date >= pickup-date. Pass only the fields you want
    /// to change; the server merges into the existing row.
    struct UpdateLoadAck: Decodable, Hashable {
        let success: Bool?
        let id: String?
    }

    func updateLoad(
        loadId: String,
        rate: Double? = nil,
        specialInstructions: String? = nil,
        dispatchNotes: String? = nil,
        pickupLocation: String? = nil,
        deliveryLocation: String? = nil,
        pickupDate: String? = nil,
        deliveryDate: String? = nil
    ) async throws -> UpdateLoadAck {
        struct Data: Encodable {
            let rate: Double?
            let specialInstructions: String?
            let dispatchNotes: String?
            let pickupLocation: String?
            let deliveryLocation: String?
            let pickupDate: String?
            let deliveryDate: String?
        }
        struct Input: Encodable {
            let id: String
            let data: Data
        }
        return try await api.mutation(
            "loads.update",
            input: Input(
                id: loadId,
                data: Data(
                    rate: rate,
                    specialInstructions: specialInstructions,
                    dispatchNotes: dispatchNotes,
                    pickupLocation: pickupLocation,
                    deliveryLocation: deliveryLocation,
                    pickupDate: pickupDate,
                    deliveryDate: deliveryDate
                )
            )
        )
    }

    /// Mirrors `loads.getShipperSummary` (loads.ts:769). Topline counts
    /// for the 201 Shipper Loads filter chips + the 200 Home stat strip.
    /// Server returns a 7-key envelope; we project all of them so screens
    /// can read what they need without re-querying.
    struct ShipperSummary: Decodable, Hashable {
        let totalLoads: Int
        let activeLoads: Int
        let inTransit: Int
        let delivered: Int
        let pendingBids: Int
        let pending: Int
        let totalSpend: Double

        private enum CodingKeys: String, CodingKey {
            case totalLoads, activeLoads, inTransit, delivered
            case pendingBids, pending, totalSpend
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.totalLoads  = try c.decodeIfPresent(Int.self, forKey: .totalLoads)  ?? 0
            self.activeLoads = try c.decodeIfPresent(Int.self, forKey: .activeLoads) ?? 0
            self.inTransit   = try c.decodeIfPresent(Int.self, forKey: .inTransit)   ?? 0
            self.delivered   = try c.decodeIfPresent(Int.self, forKey: .delivered)   ?? 0
            self.pendingBids = try c.decodeIfPresent(Int.self, forKey: .pendingBids) ?? 0
            self.pending     = try c.decodeIfPresent(Int.self, forKey: .pending)     ?? 0
            // totalSpend ships as DECIMAL → JSON String through the
            // tRPC MySQL driver. Tolerate both Number and String.
            if let d = try? c.decode(Double.self, forKey: .totalSpend) {
                self.totalSpend = d
            } else if let i = try? c.decode(Int.self, forKey: .totalSpend) {
                self.totalSpend = Double(i)
            } else if let s = try? c.decode(String.self, forKey: .totalSpend),
                      let d = Double(s) {
                self.totalSpend = d
            } else {
                self.totalSpend = 0
            }
        }
    }

    func getShipperSummary() async throws -> ShipperSummary {
        try await api.queryNoInput("loads.getShipperSummary")
    }

    // MARK: - Commercial context (broker + agreement)

    /// Mirrors the `loads.getCommercialContext` server projection.
    /// Both `broker` and `agreement` may be `nil` independently — the
    /// driver-facing UI renders an em-dash neutral state for either.
    struct CommercialContext: Decodable {
        struct Broker: Decodable {
            let userId: Int
            let userName: String?
            let companyId: Int?
            let companyName: String?
            let legalName: String?
            let dotNumber: String?
            let mcNumber: String?
            let category: String?
            let complianceStatus: String?
        }
        struct Agreement: Decodable {
            let id: Int
            let agreementNumber: String
            /// One of: catalyst_shipper, broker_catalyst, broker_shipper,
            /// catalyst_driver, escort_service, dispatch_dispatch,
            /// terminal_access, master_service, lane_commitment,
            /// fuel_surcharge, accessorial_schedule, nda, factoring,
            /// custom. Surface as a friendly label via `displayLabel`.
            let agreementType: String
            /// One of: spot, short_term, long_term, evergreen.
            let contractDuration: String
            let rateType: String?
            let baseRate: Double?
            let effectiveDate: String?
            let expirationDate: String?
        }
        let broker: Broker?
        let agreement: Agreement?
        /// Always-non-null reachable target for the Message button on
        /// the load-detail surface. Resolves to the first available
        /// poster (broker → shipper → driver) per server logic in
        /// `loads.getCommercialContext`. Founder mandate 2026-05-06 —
        /// "whether its a broker or just shipper or its dispatch it
        /// needs to work when contacting whoever posts a load."
        struct Counterparty: Decodable, Hashable {
            let userId: Int
            let userName: String?
            let companyId: Int?
            let companyName: String?
            /// `BROKER | SHIPPER | DISPATCH | DRIVER | ADMIN | …` —
            /// pulled from `users.role`, falls back to the nominal
            /// candidate role when the user row is sparse.
            let role: String
        }
        let counterparty: Counterparty?
    }

    /// `loads.getCommercialContext` — broker + agreement projection for
    /// a single load. Returns `nil` only when the load itself is gone.
    func getCommercialContext(loadId: String) async throws -> CommercialContext? {
        struct Input: Encodable { let loadId: String }
        return try await api.query(
            "loads.getCommercialContext",
            input: Input(loadId: loadId)
        )
    }

    // MARK: - Escort assignment

    /// One escort assignment row attached to a load. The lead escort and
    /// chase escort each get their own entry; either may be missing.
    struct EscortAssignment: Decodable, Identifiable {
        let id: Int
        /// "lead" | "chase" | "both"
        let position: String
        /// "pending" | "accepted" | "en_route" | "on_site" | "escorting"
        /// | "completed" | "cancelled"
        let status: String
        let rate: Double?
        let rateType: String?
        let escortUserId: Int
        let escortName: String?
        let escortPhone: String?
        let companyName: String?
        let companyDot: String?
        let companyMc: String?
        let startedAt: String?
        let completedAt: String?
    }

    /// `loads.getEscortAssignment` — driver visibility into who's
    /// escorting them. Returns `[]` when the load has no escort wired.
    func getEscortAssignment(loadId: String) async throws -> [EscortAssignment] {
        struct Input: Encodable { let loadId: String }
        return try await api.query(
            "loads.getEscortAssignment",
            input: Input(loadId: loadId)
        )
    }

    // MARK: - Driver readiness (Phase 8 — pre-trip)

    /// Mirrors the verbatim `loads.getAssignedDriverReadiness` server
    /// projection. Closes Phase 8 of the 8000-scenario shipper↔driver
    /// parity audit — pre-pickup view of the assigned driver's HOS
    /// clock + insurance + hazmat + TWIC. RBAC-gated to the shipper
    /// of record (or admin/dispatch privileged role) on the load.
    /// Optionals everywhere — an unassigned load returns the empty
    /// envelope so the iOS card renders an honest neutral state.
    struct DriverReadiness: Decodable, Hashable {
        let loadId: String
        let driverId: Int?
        let driverName: String?
        let driverPhone: String?
        let cdlNumber: String?
        let cdlExpiry: String?
        let cdlClass: String?
        let hazmatEndorsed: Bool?
        let hazmatExpiry: String?
        let hazmatDaysRemaining: Int?
        let twicNumber: String?
        let twicExpiry: String?
        let twicDaysRemaining: Int?
        let carrierName: String?
        let carrierDot: String?
        let carrierMc: String?
        let carrierInsuranceExpiry: String?
        let carrierInsuranceDaysRemaining: Int?
        let hosDrivingRemainingHours: Double?
        let hosOnDutyRemainingHours: Double?
        let hosCycleRemainingHours: Double?
        let hosCanDrive: Bool?
        let hosCurrentStatus: String?
        let readinessScore: Int?
        let readinessFlags: [String]
    }

    /// `loads.getAssignedDriverReadiness` — pre-pickup driver
    /// eligibility envelope for the shipper-of-record. Pulls HOS
    /// remaining + cert expiries server-side so the iOS card flashes
    /// CLEAR / WATCH / WARN / EXPIRED without client-side parsing.
    func getAssignedDriverReadiness(loadId: String) async throws -> DriverReadiness {
        struct Input: Encodable { let loadId: String }
        return try await api.query(
            "loads.getAssignedDriverReadiness",
            input: Input(loadId: loadId)
        )
    }

    // MARK: - Cancel mutations

    /// Acknowledge envelope from `loads.cancelWithReason` /
    /// `loads.cancel`. Server hard-codes `success: true` on the
    /// happy path and writes the reason into `specialInstructions`
    /// (cancelWithReason) or into the audit envelope (cancel).
    struct CancelAck: Decodable, Hashable {
        let success: Bool?
        let loadId: AnyLoadID?
        let reason: String?
        let tonuApplied: Bool?
        let tonuFee: Double?

        /// `loads.cancelWithReason` returns `loadId: number`;
        /// `loads.cancel` returns `loadId: string`. Decode both.
        struct AnyLoadID: Decodable, Hashable {
            let stringValue: String
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let i = try? c.decode(Int.self)    { self.stringValue = String(i) }
                else if let s = try? c.decode(String.self) { self.stringValue = s }
                else { self.stringValue = "" }
            }
        }
    }

    /// `loads.cancelWithReason` (loads.ts:3036). Mirrors the verbatim
    /// shipper-canonical cancel-with-reason path: writes status =
    /// "cancelled", appends `[CANCELLED: <reason>]` to
    /// specialInstructions, emits `loadStatusChange` for the
    /// activity feed. Server accepts numeric `loadId`.
    @discardableResult
    func cancelWithReason(loadId: Int, reason: String) async throws -> CancelAck {
        struct Input: Encodable {
            let loadId: Int
            let reason: String
        }
        return try await api.mutation(
            "loads.cancelWithReason",
            input: Input(loadId: loadId, reason: reason)
        )
    }

    /// `loads.cancel` (loads.ts:1245). Cancels with optional reason
    /// + TONU fee logic for catalyst-assigned loads. Set
    /// `waiveTonus: true` to skip the TONU when a load is being
    /// cancelled by mutual agreement.
    @discardableResult
    func cancel(
        loadId: String,
        reason: String? = nil,
        waiveTonus: Bool = false
    ) async throws -> CancelAck {
        struct Input: Encodable {
            let loadId: String
            let reason: String?
            let waiveTonus: Bool
        }
        return try await api.mutation(
            "loads.cancel",
            input: Input(loadId: loadId, reason: reason, waiveTonus: waiveTonus)
        )
    }

    // MARK: - Create from template (Phase 19 — recurring materialization)

    /// Acknowledge envelope from `loads.createFromTemplate`.
    /// Server returns `{ success, loadId, loadNumber }` after
    /// inserting a fresh `loads` row keyed off the template's
    /// origin / destination / cargo and the caller-supplied
    /// pickup / delivery dates.
    struct CreateFromTemplateAck: Decodable, Hashable {
        let success: Bool?
        let loadId: Int?
        let loadNumber: String?
    }

    /// `loads.createFromTemplate` (loads.ts:2968). Materialize a
    /// real load from a saved template. Drives the shipper-side
    /// recurring composer's "Schedule next pickup" path — saves
    /// a template via `loadTemplates.create`, then immediately
    /// fires this to put the first occurrence on the schedule.
    @discardableResult
    func createFromTemplate(
        templateId: Int,
        pickupDate: String? = nil,
        deliveryDate: String? = nil
    ) async throws -> CreateFromTemplateAck {
        struct Input: Encodable {
            let templateId: Int
            let pickupDate: String?
            let deliveryDate: String?
        }
        return try await api.mutation(
            "loads.createFromTemplate",
            input: Input(
                templateId: templateId,
                pickupDate: pickupDate,
                deliveryDate: deliveryDate
            )
        )
    }
}

// MARK: - hosRouter

struct HOSAPI {
    unowned let api: EusoTripAPI

    /// `hosRouter.getStatus` — no input, returns dashboard HOSStatus.
    func getStatus() async throws -> HOSStatus {
        try await api.queryNoInput("hos.getStatus")
    }

    /// `hosRouter.getCurrentStatus` — detailed, optional driverId override.
    func getCurrentStatus(driverId: String? = nil) async throws -> HOSCurrentStatus {
        struct Input: Encodable { let driverId: String? }
        return try await api.query("hos.getCurrentStatus", input: Input(driverId: driverId))
    }

    /// `hosRouter.changeStatus` — canonical duty-status transition.
    /// Replaces the deprecated `hos.logEvent` the Pulse watch used to call.
    ///
    /// - `status`: off_duty | sleeper | driving | on_duty
    /// - `source`: "ios" | "watch" | "eld" | "dispatcher"
    /// - `lat` / `lon`: optional GPS fix at the moment of the transition
    /// - `location`: human-readable place string ("Meridian, MS") that
    ///   the backend writes into `hos_logs.location_description` per
    ///   §395.8(h). Required by the tRPC schema — pass "" when the
    ///   device has no recent fix rather than dropping the field.
    /// - `odometer`: truck odometer in miles if the ELD has one
    /// - `remark`: optional §395.8(j) annotation
    /// - `loadId`: optional load currently on the driver's board
    func changeStatus(
        status: HOSDutyCode,
        source: String = "ios",
        lat: Double? = nil,
        lon: Double? = nil,
        location: String = "",
        odometer: Double? = nil,
        remark: String? = nil,
        loadId: String? = nil,
        ts: Date = Date()
    ) async throws -> HOSChangeStatusResult {
        // Server contract (MCP-verified at
        // `frontend/server/routers/hos.ts:94`) is:
        //   { newStatus: dutyStatusSchema, location: string, notes?: string }
        //
        // An earlier build shipped an input that named the field
        // `status` with a handful of ELD-adjacent extras (source, lat,
        // lon, odometer, loadId, ts) — Zod rejected the whole payload
        // with an "invalid_value" error against `newStatus`, and that
        // raw Zod JSON leaked into the driver's duty-status toast as
        // a wall of text. The ELD-adjacent fields aren't on the server
        // schema at all; the backend records the location string,
        // derives lat/lng from the driver's most-recent telemetry
        // ping, and writes odometer from the ELD integration — so
        // dropping them from the client matches how the route is
        // actually processed.
        //
        // `source`, `lat`, `lon`, `odometer`, `loadId`, and `ts` are
        // kept on the public function signature so call-sites don't
        // have to change — they're intentionally unused here, and
        // will start flowing through if/when the server extends its
        // schema. `remark` is mapped to `notes` which IS on the
        // server schema.
        _ = (source, lat, lon, odometer, loadId, ts)
        struct Input: Encodable {
            let newStatus: String
            let location: String
            let notes: String?
        }
        let input = Input(
            newStatus: status.rawValue,
            location: location,
            notes: remark
        )
        return try await api.mutation("hos.changeStatus", input: input)
    }

    /// `hosRouter.getDailyLog` — segments + totals for a single calendar
    /// day. `date` is YYYY-MM-DD in the driver's carrier timezone;
    /// omitting it asks the server for "today".
    func getDailyLog(date: String? = nil, driverId: String? = nil) async throws -> HOSDailyLog {
        struct Input: Encodable {
            let date: String?
            let driverId: String?
        }
        return try await api.query("hos.getDailyLog", input: Input(date: date, driverId: driverId))
    }

    /// `hosRouter.getLogHistory` — array of daily logs for the last
    /// `days` calendar days (defaults to the §395.8(k) 8-day cycle).
    /// Returns newest-first to match the ELD screen's list rendering.
    func getLogHistory(days: Int = 8, driverId: String? = nil) async throws -> [HOSDailyLog] {
        struct Input: Encodable {
            let days: Int
            let driverId: String?
        }
        return try await api.query("hos.getLogHistory", input: Input(days: days, driverId: driverId))
    }

    /// `hosRouter.certifyLog` — §395.8(g) driver certification.
    /// `date` is YYYY-MM-DD. The `signature` field must be a non-empty
    /// token (biometric hash, typed name, etc.) — the server rejects empty.
    func certifyLog(date: String, signature: String) async throws -> CertifyLogResult {
        struct Input: Encodable {
            let date: String
            let signature: String
        }
        return try await api.mutation("hos.certifyLog", input: Input(date: date, signature: signature))
    }

    /// `hosRouter.addRemark` — attach an annotation (§395.8(j)) to the
    /// driver's current segment, or an explicit entry if `entryId` given.
    func addRemark(text: String, entryId: String? = nil) async throws -> AddRemarkResult {
        struct Input: Encodable {
            let text: String
            let entryId: String?
        }
        return try await api.mutation("hos.addRemark", input: Input(text: text, entryId: entryId))
    }

    /// `hosRouter.getViolations` — unresolved violations the driver
    /// should be shown on the 019 screen. Empty array when clean.
    func getViolations() async throws -> [HOSViolation] {
        try await api.queryNoInput("hos.getViolations")
    }
}

// MARK: - authRouter

struct AuthAPI {
    unowned let api: EusoTripAPI

    /// `auth.login` — POST mutation.
    /// Returns `{success:true, user}` on success, or
    /// `{success:false, requiresTwoFactor:true, method, message}` when 2FA gate trips.
    func login(email: String, password: String, twoFactorCode: String? = nil) async throws -> LoginResponse {
        struct Input: Encodable {
            let email: String
            let password: String
            let twoFactorCode: String?
        }
        return try await api.mutation(
            "auth.login",
            input: Input(email: email, password: password, twoFactorCode: twoFactorCode)
        )
    }

    /// `auth.me` — GET query, returns the currently authenticated user.
    func me() async throws -> AuthUser {
        try await api.queryNoInput("auth.me")
    }

    /// `auth.logout` — POST mutation.  Clears server-side session and cookies.
    func logout() async throws -> GenericMessageResponse {
        try await api.mutationNoInput("auth.logout")
    }

    /// `auth.forgotPassword` — POST mutation.  Always returns success
    /// (to prevent email enumeration).
    func forgotPassword(email: String) async throws -> GenericMessageResponse {
        struct Input: Encodable { let email: String }
        return try await api.mutation("auth.forgotPassword", input: Input(email: email))
    }

    // MARK: — Sign in with Apple

    /// `auth.appleSignIn` — verifies the Apple identityToken against
    /// the JWKS at appleid.apple.com, finds or creates a user, and
    /// returns the same `{success, user}` envelope as `auth.login`.
    func signInWithApple(
        identityToken: String,
        authorizationCode: String? = nil,
        givenName: String? = nil,
        familyName: String? = nil,
        email: String? = nil,
        nonce: String? = nil
    ) async throws -> LoginResponse {
        struct FullName: Encodable {
            let givenName: String?
            let familyName: String?
        }
        struct Input: Encodable {
            let identityToken: String
            let authorizationCode: String?
            let fullName: FullName?
            let email: String?
            let nonce: String?
        }
        let fullName: FullName? = (givenName == nil && familyName == nil)
            ? nil
            : FullName(givenName: givenName, familyName: familyName)
        return try await api.mutation(
            "auth.appleSignIn",
            input: Input(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                fullName: fullName,
                email: email,
                nonce: nonce
            )
        )
    }

    // MARK: — Passkeys

    struct PasskeyRegisterStartResponse: Decodable {
        struct RP: Decodable { let id: String; let name: String }
        let rp: RP
        let userHandle: String          // base64url
        let userName: String
        let userDisplayName: String
        let challenge: String           // base64url
        let algorithms: [Int]
    }
    /// `auth.passkeyRegisterStart` — protected. Returns RP + challenge
    /// + user handle for the iOS WebAuthn registration request.
    func passkeyRegisterStart(label: String? = nil) async throws -> PasskeyRegisterStartResponse {
        struct Input: Encodable { let label: String? }
        return try await api.mutation("auth.passkeyRegisterStart", input: Input(label: label))
    }

    struct PasskeyRegisterFinishAck: Decodable {
        let success: Bool
        let credentialId: String
    }
    /// `auth.passkeyRegisterFinish` — protected. Verifies attestation
    /// and persists the credential. Pass the same `challenge` the
    /// start step minted so the server can consume it.
    func passkeyRegisterFinish(
        challenge: String,
        credentialId: String,
        attestationObject: String,
        clientDataJSON: String,
        label: String? = nil,
        transports: [String]? = nil
    ) async throws -> PasskeyRegisterFinishAck {
        struct Input: Encodable {
            let challenge: String
            let credentialId: String
            let attestationObject: String
            let clientDataJSON: String
            let label: String?
            let transports: [String]?
        }
        return try await api.mutation(
            "auth.passkeyRegisterFinish",
            input: Input(
                challenge: challenge,
                credentialId: credentialId,
                attestationObject: attestationObject,
                clientDataJSON: clientDataJSON,
                label: label,
                transports: transports
            )
        )
    }

    struct PasskeyAuthStartResponse: Decodable {
        struct RP: Decodable { let id: String; let name: String }
        struct AllowedCredential: Decodable {
            let credentialId: String
            let transports: [String]?
        }
        let rp: RP
        let challenge: String
        let allowCredentials: [AllowedCredential]
    }
    /// `auth.passkeyAuthStart` — public. Optionally pass `email` to
    /// constrain the credential list to that account; omitting it
    /// lets iOS surface any platform-stored passkey for the RP.
    func passkeyAuthStart(email: String? = nil) async throws -> PasskeyAuthStartResponse {
        struct Input: Encodable { let email: String? }
        return try await api.mutation("auth.passkeyAuthStart", input: Input(email: email))
    }

    /// `auth.passkeyAuthFinish` — public. Verifies the assertion and
    /// returns the standard `{success, user}` login envelope.
    func passkeyAuthFinish(
        challenge: String,
        credentialId: String,
        authenticatorData: String,
        clientDataJSON: String,
        signature: String,
        userHandle: String?
    ) async throws -> LoginResponse {
        struct Input: Encodable {
            let challenge: String
            let credentialId: String
            let authenticatorData: String
            let clientDataJSON: String
            let signature: String
            let userHandle: String?
        }
        return try await api.mutation(
            "auth.passkeyAuthFinish",
            input: Input(
                challenge: challenge,
                credentialId: credentialId,
                authenticatorData: authenticatorData,
                clientDataJSON: clientDataJSON,
                signature: signature,
                userHandle: userHandle
            )
        )
    }

    struct PasskeyListRow: Decodable, Hashable, Identifiable {
        let id: Int
        let credentialId: String
        let label: String?
        let rpId: String
        let createdAt: String?
        let lastUsedAt: String?
    }
    /// `auth.passkeyList` — protected. Renders the Settings list.
    func passkeyList() async throws -> [PasskeyListRow] {
        try await api.queryNoInput("auth.passkeyList")
    }

    /// `auth.passkeyRevoke` — protected. Soft-revoke by id.
    func passkeyRevoke(id: Int) async throws -> GenericSuccessResponse {
        struct Input: Encodable { let id: Int }
        return try await api.mutation("auth.passkeyRevoke", input: Input(id: id))
    }

    /// `auth.resetPassword` — POST mutation.
    func resetPassword(token: String, newPassword: String) async throws -> GenericMessageResponse {
        struct Input: Encodable {
            let token: String
            let newPassword: String
        }
        return try await api.mutation(
            "auth.resetPassword",
            input: Input(token: token, newPassword: newPassword)
        )
    }
}

/// Minimal `{success}` envelope used by passkey revoke + similar
/// "side-effect, no payload" mutations.
struct GenericSuccessResponse: Decodable { let success: Bool }

// MARK: - availabilityRouter
//
// Backed by `frontend/server/routers/availability.ts`. The driver
// availability surface (MeAvailabilityView · home-time block planner ·
// duty schedule) reads weeklyGrid + utilization, writes blocks via
// blockTime, and exports the week to iCalendar via `exportICS`.
// Without this namespace the "Export calendar (.ics)" CTA was a
// dead notification post — user reported "ICS calendar export
// doesn't work" (2026-04-25).

struct AvailabilityAPI {
    unowned let api: EusoTripAPI

    /// Backend mints a 15-minute signed token and returns the URL that
    /// serves the rendered ICS (`/api/exports/availability/{token}.ics`).
    /// iOS receives the URL + opens it via `UIApplication.shared.open`
    /// so the system Calendar app picks up the .ics import handler.
    struct ExportTokenResponse: Decodable {
        let url: String
        let expiresAt: String
    }

    struct ExportInput: Encodable {
        let weekStartISO: String?
    }

    /// Mints a signed export URL for the given week (defaults to the
    /// current ISO week when `weekStartISO` is nil).
    func exportICS(weekStartISO: String? = nil) async throws -> ExportTokenResponse {
        try await api.mutation(
            "availability.exportICS",
            input: ExportInput(weekStartISO: weekStartISO)
        )
    }
}

// MARK: - registrationRouter

struct RegistrationAPI {
    unowned let api: EusoTripAPI

    // Shared registration primitive.  Each role uses different zod inputs
    // on the backend; we pass a dictionary so each caller controls its own shape.
    private func register(procedure: String, input: [String: AnyEncodable]) async throws -> RegistrationResponse {
        try await api.mutation(procedure, input: input)
    }

    // MARK: Driver

    struct DriverRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String?
        let cdlNumber: String?
        let cdlState: String?
        let cdlClass: String?       // A / B / C
        let dateOfBirth: String?    // YYYY-MM-DD
        let companyCode: String?    // joins existing carrier via invite
    }

    func registerDriver(_ input: DriverRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerDriver", input: input)
    }

    // MARK: Shipper

    struct ShipperRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String?
        let companyName: String
        let address: String?
        let city: String?
        let state: String?
        let zip: String?
    }

    func registerShipper(_ input: ShipperRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerShipper", input: input)
    }

    // MARK: Catalyst (Carrier)

    struct CatalystRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String?
        let companyName: String
        let mcNumber: String?
        let dotNumber: String?
        let ein: String?
    }

    func registerCatalyst(_ input: CatalystRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerCatalyst", input: input)
    }

    // MARK: Broker

    struct BrokerRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String?
        let companyName: String
        let brokerMcNumber: String?
        let bondProvider: String?
        let bondAmount: Double?
    }

    func registerBroker(_ input: BrokerRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerBroker", input: input)
    }

    // MARK: Dispatch

    struct DispatchRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String?
        let companyCode: String?   // required to join a carrier
    }

    func registerDispatch(_ input: DispatchRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerDispatch", input: input)
    }

    // MARK: Escort

    struct EscortRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String?
        let escortCertState: String?
        let certificationExpires: String? // YYYY-MM-DD
    }

    func registerEscort(_ input: EscortRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerEscort", input: input)
    }

    // MARK: Terminal Manager (added for iOS ↔ web role parity)
    //
    // Backend proc MCP-verified at
    // `frontend/server/routers/registration.ts:registerTerminalManager`.
    // Terminal managers supervise a physical facility (warehouse, dock,
    // port terminal). Joined to a Catalyst/Shipper company via
    // `companyCode` invite — parity with the web's company-bound flow.

    struct TerminalManagerRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String?
        let companyName: String?       // optional — used when provisioning a new terminal
        let facilityName: String?
        let epaFacilityId: String?     // facilities handling hazmat report under 40 CFR
        let companyCode: String?       // invite token from parent Catalyst / Shipper
    }

    func registerTerminalManager(_ input: TerminalManagerRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerTerminalManager", input: input)
    }

    // MARK: Compliance Officer
    //
    // Company-bound role per FMCSA §390 — must be associated with a
    // DOT-registered carrier. Backend proc: `registration.registerComplianceOfficer`.

    struct ComplianceOfficerRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String?
        let certificationNumber: String?   // CDS / TSDCA / state cert
        let trainingProvider: String?
        let trainingCompletionDate: String?  // YYYY-MM-DD
        let companyCode: String?           // required — ties officer to carrier
    }

    func registerComplianceOfficer(_ input: ComplianceOfficerRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerComplianceOfficer", input: input)
    }

    // MARK: Safety Manager
    //
    // Oversees FMCSA CSA metrics + driver qualification files. Backend
    // proc: `registration.registerSafetyManager`. Carrier-bound like
    // Compliance Officer.

    struct SafetyManagerRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String?
        let csaSpecialistCert: String?     // optional NSC / CSA cert
        let yearsOfExperience: Int?
        let companyCode: String?           // required — ties manager to carrier
    }

    func registerSafetyManager(_ input: SafetyManagerRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerSafetyManager", input: input)
    }

    // MARK: Admin (invite-only)
    //
    // Platform administrator. The backend rejects the call unless the
    // `inviteCode` matches a SUPER_ADMIN-issued token, so this form is
    // safe to ship on consumer App Store builds — an attacker with the
    // form can't self-provision without a valid code. Backend proc:
    // `registration.registerAdmin`.

    struct AdminRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String?
        let inviteCode: String             // required — SUPER_ADMIN-issued token
    }

    func registerAdmin(_ input: AdminRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerAdmin", input: input)
    }

    // MARK: Rail (6 roles)
    //
    // Backend procs added 2026-04-24 via `createSimpleRoleUser` — all
    // share the firstName/lastName/email/phone/password identity
    // spine + role-specific regulatory fields the STB / FRA / IMC /
    // USCG asks for. The struct shapes below match each Zod schema
    // exactly so the server never sees surprise payloads.

    struct RailShipperRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String
        let companyName: String
        let dba: String?
        let ein: String?
        let stbRegistration: String?
        let streetAddress: String?
        let city: String?
        let state: String?
        let zipCode: String?
    }

    func registerRailShipper(_ input: RailShipperRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerRailShipper", input: input)
    }

    struct RailCatalystRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String
        let companyName: String
        let dba: String?
        let ein: String?
        let stbDocket: String?
        let fraCertification: String?
        let locomotiveCount: Int?
        let railcarCount: Int?
        let operatingStates: [String]?
    }

    func registerRailCatalyst(_ input: RailCatalystRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerRailCatalyst", input: input)
    }

    struct RailDispatcherRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String
        let employerRailroad: String
        let dispatcherCertification: String?
        let yearsExperience: String?
        let companyCode: String?
    }

    func registerRailDispatcher(_ input: RailDispatcherRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerRailDispatcher", input: input)
    }

    struct RailEngineerRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String
        let dateOfBirth: String?
        let fraCertificationNumber: String       // required — §49 CFR 240
        let fraCertificationExpires: String?
        let employerRailroad: String?
        let yearsExperience: String?
        let medicalCardNumber: String?
        let medicalCardExpires: String?
    }

    func registerRailEngineer(_ input: RailEngineerRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerRailEngineer", input: input)
    }

    struct RailConductorRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String
        let dateOfBirth: String?
        let fraCertificationNumber: String       // required — §49 CFR 242
        let fraCertificationExpires: String?
        let employerRailroad: String?
        let yearsExperience: String?
        let medicalCardNumber: String?
        let medicalCardExpires: String?
    }

    func registerRailConductor(_ input: RailConductorRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerRailConductor", input: input)
    }

    struct RailBrokerRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String
        let companyName: String
        let dba: String?
        let imcRegistration: String?
        let stbRegistration: String?
        let ein: String?
        let bondProvider: String?
        let bondAmount: Double?
    }

    func registerRailBroker(_ input: RailBrokerRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerRailBroker", input: input)
    }

    // MARK: Vessel (6 roles)

    struct VesselShipperRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String
        let companyName: String
        let dba: String?
        let ein: String?
        let fmcRegistration: String?
        let cargoTypes: [String]?
    }

    func registerVesselShipper(_ input: VesselShipperRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerVesselShipper", input: input)
    }

    struct VesselOperatorRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String
        let companyName: String
        let fmcLicenseNumber: String?
        let uscgDocumentNumber: String?
        let vesselCount: Int?
        let operatingPorts: [String]?
    }

    func registerVesselOperator(_ input: VesselOperatorRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerVesselOperator", input: input)
    }

    struct ShipCaptainRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String
        let dateOfBirth: String?
        let mmcLicenseNumber: String            // required — Merchant Mariner Credential
        let mmcExpires: String?
        let stcwCertification: String?
        let stcwExpires: String?
        let vesselClassEndorsements: [String]?
        let yearsAtSea: String?
        let medicalCertificateNumber: String?
        let medicalCertificateExpires: String?
    }

    func registerShipCaptain(_ input: ShipCaptainRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerShipCaptain", input: input)
    }

    struct VesselBrokerRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String
        let companyName: String
        let dba: String?
        let fmcLicenseNumber: String?
        let ein: String?
        let bondProvider: String?
        let bondAmount: Double?
    }

    func registerVesselBroker(_ input: VesselBrokerRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerVesselBroker", input: input)
    }

    struct PortMasterRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String
        let portName: String
        let portAuthority: String?
        let mtsaFacilityPlan: String?
        let uscgFacilityId: String?
        let jobTitle: String?
        let yearsExperience: String?
    }

    func registerPortMaster(_ input: PortMasterRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerPortMaster", input: input)
    }

    struct CustomsBrokerRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String
        let companyName: String
        let dba: String?
        let cbpLicenseNumber: String            // required — CBP broker license
        let cbpLicenseExpires: String?
        let bondNumber: String?
        let bondAmount: Double?
        let bondProvider: String?
        let ein: String?
        let portsOfEntry: [String]?
    }

    func registerCustomsBroker(_ input: CustomsBrokerRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerCustomsBroker", input: input)
    }

    /// Container demurrage accrual response from `vesselShipments.calculateVesselDemurrage`.
    /// Maps server keys {demurrage, dwellDays, freeTimeDays, chargeableDays, containerCount}
    /// to iOS properties {chargeUsd, metersStarted, freeDays, accruedDays}.
    struct VesselDemurrage: Decodable {
        let freeDays: Int?
        let accruedDays: Int?
        let chargeUsd: Double?
        let metersStarted: Int?

        private enum CodingKeys: String, CodingKey {
            case freeDays = "freeTimeDays"
            case accruedDays = "chargeableDays"
            case chargeUsd = "demurrage"
            case metersStarted = "dwellDays"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.freeDays = try c.decodeIfPresent(Int.self, forKey: .freeDays)
            self.accruedDays = try c.decodeIfPresent(Int.self, forKey: .accruedDays)
            self.chargeUsd = try c.decodeIfPresent(Double.self, forKey: .chargeUsd)
            self.metersStarted = try c.decodeIfPresent(Int.self, forKey: .metersStarted)
        }
    }

    // MARK: Financial / platform (Factoring, Super-Admin)

    struct FactoringRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String
        let companyName: String
        let dba: String?
        let ein: String?
        let stateLenderLicense: String?
        let yearsInBusiness: String?
        let operatingStates: [String]?
        let serviceCommodities: [String]?
        let advanceRate: Double?        // percentage
        let factoringFeeRate: Double?   // percentage
    }

    func registerFactoring(_ input: FactoringRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerFactoring", input: input)
    }

    struct SuperAdminRegistration: Encodable {
        let email: String
        let password: String
        let firstName: String
        let lastName: String
        let phone: String
        let inviteCode: String          // required — SUPER_ADMIN-issued token
        let reason: String?
    }

    func registerSuperAdmin(_ input: SuperAdminRegistration) async throws -> RegistrationResponse {
        try await api.mutation("registration.registerSuperAdmin", input: input)
    }

    // MARK: Verify / Resend

    func verifyEmail(token: String) async throws -> GenericMessageResponse {
        struct Input: Encodable { let token: String }
        return try await api.mutation("registration.verifyEmail", input: Input(token: token))
    }

    func resendVerification(email: String) async throws -> GenericMessageResponse {
        struct Input: Encodable { let email: String }
        return try await api.mutation("registration.resendVerification", input: Input(email: email))
    }
}

// MARK: - inspectionsRouter

struct InspectionsAPI {
    unowned let api: EusoTripAPI

    /// `inspections.getTemplate` — returns the FMCSA walk-around template
    /// (categories × required items) for pre-trip / post-trip / DVIR.
    ///
    /// T-018 · 2026-05-20 — Accepts an optional canonical `TrailerCode`
    /// so the server returns trailer-keyed checklist categories (tanker
    /// PRV + vapor recovery for `liquid_tank`, reefer setpoint + FSMA
    /// wash-out for `reefer`, livestock 28-hr arming + bedding for
    /// `livestock_cattle_pot`, intermodal CSC plate + twist-locks for
    /// `intermodal_chassis`, etc.). Round-trip shipped 2026-05-20 in
    /// server commit c4905024 (frontend/server/routers/inspections.ts).
    /// Nil-safe: when omitted the server returns the legacy generic
    /// FMCSA 393 walkaround template.
    func getTemplate(type: InspectionType, trailer: TrailerCode? = nil) async throws -> InspectionTemplate {
        struct Input: Encodable { let type: String; let trailer: String? }
        return try await api.query(
            "inspections.getTemplate",
            input: Input(type: type.rawValue, trailer: trailer?.rawValue)
        )
    }

    /// `inspections.submit` — writes the full DVIR payload to `inspections`
    /// table, fires `safety_inspection_passed` gamification, auto-indexes for AI.
    func submit(_ payload: InspectionSubmission) async throws -> InspectionSubmitResponse {
        try await api.mutation("inspections.submit", input: payload)
    }

    /// `inspections.getHistory` — last N inspections for a given vehicle.
    func getHistory(vehicleId: String, limit: Int = 10) async throws -> [InspectionHistoryEntry] {
        struct Input: Encodable { let vehicleId: String; let limit: Int }
        return try await api.query(
            "inspections.getHistory",
            input: Input(vehicleId: vehicleId, limit: limit)
        )
    }

    /// `inspections.getPrevious` — current driver's recent inspections.
    func getPrevious(vehicleId: String? = nil) async throws -> [InspectionPreviousEntry] {
        struct Input: Encodable { let vehicleId: String? }
        return try await api.query(
            "inspections.getPrevious",
            input: Input(vehicleId: vehicleId)
        )
    }

    /// `inspections.getOpenDefects` — inspections with defects > 0 across the company.
    func getOpenDefects(vehicleId: String? = nil) async throws -> [InspectionDefectEntry] {
        struct Input: Encodable { let vehicleId: String? }
        return try await api.query(
            "inspections.getOpenDefects",
            input: Input(vehicleId: vehicleId)
        )
    }

    // MARK: - DVIR (49 CFR 396.11)

    /// `inspections.createDVIR` — writes a DVIR to `dvir_reports` + defect items.
    func createDVIR(
        vehicleId: Int,
        reportType: String,
        odometerMiles: Int? = nil,
        overallCondition: String,
        defects: [DVIRDefectInput] = []
    ) async throws -> DVIRCreateResponse {
        struct Input: Encodable {
            let vehicleId: Int
            let reportType: String
            let odometerMiles: Int?
            let overallCondition: String
            let defects: [DVIRDefectInput]
        }
        return try await api.mutation(
            "inspections.createDVIR",
            input: Input(
                vehicleId: vehicleId,
                reportType: reportType,
                odometerMiles: odometerMiles,
                overallCondition: overallCondition,
                defects: defects
            )
        )
    }

    /// `inspections.getDVIRHistory` — current driver's DVIR history (optionally per vehicle).
    func getDVIRHistory(vehicleId: Int? = nil, limit: Int = 20) async throws -> [DVIRHistoryEntry] {
        struct Input: Encodable {
            let vehicleId: Int?
            let limit: Int
        }
        return try await api.query(
            "inspections.getDVIRHistory",
            input: Input(vehicleId: vehicleId, limit: limit)
        )
    }

    /// `inspections.getDVIRCategories` — canonical list from 49 CFR 396.11(a)(1).
    func getDVIRCategories() async throws -> [DVIRCategory] {
        try await api.queryNoInput("inspections.getDVIRCategories")
    }
}

/// Matches the inline zod shape expected by `inspections.createDVIR`.
struct DVIRDefectInput: Encodable {
    let category: String
    let description: String
    /// `"minor" | "major" | "out_of_service"` — defaults to `"minor"` server-side.
    let severity: String
    let photoUrl: String?
}

// MARK: - esangRouter
//
// Mirrors the web platform's `esangRouter` — POST /api/trpc/esang.chat with
// input { message, context?: { currentPage?, loadId? } } and response
// matching the backend `ESANGResponse` type (message + optional
// suggestions/actions). The backend is powered by Google Gemini via
// esangAI.chat(); this Swift client is the same entry point the web app
// uses, so driver replies match what the web eSang would return.

struct eSangAPI {
    unowned let api: EusoTripAPI

    /// Shape of `esang.chat` context field — both keys are optional on the
    /// server, so encoding nils here is safe.
    struct ChatContext: Encodable {
        /// Where the driver is when they asked — "home", "eusoboards",
        /// "active_trip", "me", etc. The backend uses this to colour
        /// the system prompt so replies stay on-topic.
        let currentPage: String?
        /// Active load id when the question pertains to a specific
        /// dispatch. Passed through so eSang can pull live load + HOS
        /// context server-side.
        let loadId: String?
    }

    /// Mirror of the backend `ESANGResponse` payload. We only decode the
    /// fields the iOS client actually reads today; unknown keys (actions,
    /// factors, compliance metadata) are ignored by JSONDecoder.
    struct ChatResponse: Decodable {
        /// The assistant reply text — this is what we render into the
        /// transcript bubble.
        let message: String
        /// Optional quick-reply chips the web uses below each reply.
        let suggestions: [String]?
    }

    /// `esang.chat` — POST mutation. Sends the driver's message to the
    /// production eSang (Gemini-backed) and returns the assistant reply.
    /// `currentPage` / `loadId` are optional context hints; pass them when
    /// available so replies factor in the caller's surface.
    func chat(
        message: String,
        currentPage: String? = nil,
        loadId: String? = nil
    ) async throws -> ChatResponse {
        struct Input: Encodable {
            let message: String
            let context: ChatContext?
        }
        let ctx: ChatContext? = (currentPage == nil && loadId == nil)
            ? nil
            : ChatContext(currentPage: currentPage, loadId: loadId)
        return try await api.mutation(
            "esang.chat",
            input: Input(message: message, context: ctx)
        )
    }

    /// `esang.clearHistory` — POST mutation. Drops the server-side
    /// Gemini conversation history for the signed-in user so the next
    /// message starts a fresh thread.
    func clearHistory() async throws {
        struct EmptyResp: Decodable { let success: Bool? }
        _ = try await api.mutationNoInput("esang.clearHistory") as EmptyResp
    }
}

// MARK: - walletRouter (Plaid + Stripe)

/// Wallet-side calls for linking external accounts through Plaid and
/// payment methods through Stripe. The iOS client only ever sees:
///   - Plaid **link tokens** issued by the backend (short-lived, account-
///     scoped) — the Plaid client_id/secret live server-side only.
///   - Stripe **publishable key** (safe to ship in iOS) + **client secret**
///     for a SetupIntent issued by the backend — the Stripe secret key
///     lives server-side only.
///
/// Mirrors the web platform's `walletRouter` — every mutation here exists
/// on the backend already (sandbox + prod); if a route 404s the backend is
/// simply on an older deploy.
struct WalletAPI {
    unowned let api: EusoTripAPI

    // MARK: — Shipper Apple-Pay / PassKit surface (239 Wallet)

    /// One row in `wallet.listPaymentMethods`. Mirrors the server's
    /// projection of a Stripe Customer payment method.
    struct PaymentMethodRow: Decodable, Hashable, Identifiable {
        let id: String           // pm_xxx
        let brand: String        // "visa" / "mastercard" / "amex" / "discover" / "jcb" / "unknown"
        let last4: String
        let expMonth: Int
        let expYear: Int
        let isDefault: Bool
        let billingName: String?
    }

    /// `wallet.listPaymentMethods` — GET query, protected.
    /// Returns the signed-in user's Stripe Customer cards.
    func listPaymentMethods() async throws -> [PaymentMethodRow] {
        try await api.queryNoInput("wallet.listPaymentMethods")
    }

    struct SetDefaultAck: Decodable, Hashable {
        let success: Bool
        let defaultPaymentMethodId: String
    }
    /// `wallet.setDefaultPaymentMethod` — POST mutation. Backend
    /// updates the Stripe Customer's `invoice_settings.default_payment_method`.
    func setDefaultPaymentMethod(_ paymentMethodId: String) async throws -> SetDefaultAck {
        struct Input: Encodable { let paymentMethodId: String }
        return try await api.mutation("wallet.setDefaultPaymentMethod",
                                      input: Input(paymentMethodId: paymentMethodId))
    }

    /// One row in `wallet.shipperPassesSnapshot.passes`, also reused
    /// for the active pass on the hero card (carries the richer fields
    /// the hero needs: carrier name, rate, UN number, etc.).
    struct ShipperPassRow: Decodable, Hashable, Identifiable {
        let id: String           // "LD-<dbId>"
        let loadId: Int
        let loadNumber: String?
        let tilePrefix: String
        let lane: String
        let spec: String
        let installedNote: String
        let status: String       // "ACTIVE" / "IN_TRANSIT" / "ESCORT" / "PENDING"
        // Hero-only fields (nil on list rows when the server doesn't
        // populate them).
        let cargoType: String?
        let equipmentType: String?
        let unNumber: String?
        let rate: String?
        let pickupDate: String?
        let deliveryDate: String?
        let carrierName: String?
        let carrierMc: String?
    }

    struct ShipperPassesSnapshot: Decodable, Hashable {
        let active: ShipperPassRow?
        let passes: [ShipperPassRow]
    }

    /// `wallet.shipperPassesSnapshot` — GET query. Returns the active
    /// pickup credential + the 3 most-recent installable passes for
    /// the signed-in shipper. `active` is null when the shipper has
    /// no live loads (iOS renders an empty-state hero in that case).
    func shipperPassesSnapshot() async throws -> ShipperPassesSnapshot {
        try await api.queryNoInput("wallet.shipperPassesSnapshot")
    }

    // MARK: Plaid

    struct PlaidLinkToken: Decodable {
        let linkToken: String
        /// Plaid environment the token was minted against: "sandbox",
        /// "development", or "production". iOS uses this to pick the
        /// matching Plaid Link SDK / hosted URL.
        let environment: String
        /// Expiration (ISO-8601) — iOS should re-fetch if this has passed.
        let expiration: String?
    }

    struct PlaidLinkedAccount: Decodable {
        let accountId: String
        let institution: String
        let accountMask: String
        let accountName: String
        let accountType: String   // "depository" / "credit" / etc.
        let accountSubtype: String?
    }

    /// `wallet.createPlaidLinkToken` — POST mutation. Backend creates a
    /// short-lived link token via Plaid's `/link/token/create` using the
    /// server-side PLAID_CLIENT_ID + PLAID_SECRET. iOS passes the token
    /// into LinkKit (native) or the hosted Link URL (Safari fallback).
    func createPlaidLinkToken() async throws -> PlaidLinkToken {
        return try await api.mutationNoInput("wallet.createPlaidLinkToken")
    }

    /// `wallet.exchangePlaidPublicToken` — POST mutation. iOS hands the
    /// `public_token` back to the backend, which calls Plaid's
    /// `/item/public_token/exchange` to get the access_token (stored
    /// server-side only) and persists the linked account for the driver.
    func exchangePlaidPublicToken(publicToken: String,
                                  institution: String?) async throws -> PlaidLinkedAccount {
        struct Input: Encodable {
            let publicToken: String
            let institution: String?
        }
        return try await api.mutation(
            "wallet.exchangePlaidPublicToken",
            input: Input(publicToken: publicToken, institution: institution)
        )
    }

    // MARK: Stripe

    struct StripeSetupIntent: Decodable {
        let clientSecret: String
        /// Stripe publishable key for the **current environment** (test vs
        /// live). Safe to ship to iOS. Backend returns it per-call so the
        /// app stays in sync with whatever mode the backend is running in.
        let publishableKey: String
    }

    struct StripeAttachedPaymentMethod: Decodable {
        let paymentMethodId: String
        let brand: String         // "visa" / "mastercard" / etc.
        let last4: String
        let expMonth: Int
        let expYear: Int
    }

    /// `wallet.createStripeSetupIntent` — POST mutation. Backend creates a
    /// SetupIntent against the driver's Stripe Customer using
    /// STRIPE_SECRET_KEY and returns only the `client_secret` plus the
    /// environment-matched publishable key for iOS to use with
    /// StripePaymentSheet (native) or the hosted Checkout session (Safari
    /// fallback).
    func createStripeSetupIntent() async throws -> StripeSetupIntent {
        return try await api.mutationNoInput("wallet.createStripeSetupIntent")
    }

    /// `wallet.attachStripePaymentMethod` — POST mutation. After the user
    /// completes the Stripe card-entry flow, iOS reports the resulting
    /// PaymentMethod id back to the backend, which attaches it to the
    /// Stripe Customer and persists the driver-facing summary row.
    func attachStripePaymentMethod(paymentMethodId: String) async throws -> StripeAttachedPaymentMethod {
        struct Input: Encodable { let paymentMethodId: String }
        return try await api.mutation(
            "wallet.attachStripePaymentMethod",
            input: Input(paymentMethodId: paymentMethodId)
        )
    }

    // MARK: Balance

    /// `wallet.getBalance` — query, no input. Returns the driver's live
    /// Eusowallet balance breakdown. Home-tab "walletAvailable" surface
    /// reads the `available` field; the other fields are used by the Me
    /// tab's detailed Eusowallet sheet.
    struct WalletBalance: Decodable {
        let available: Double
        let pending: Double
        let reserved: Double
        let escrow: Double
        let total: Double
        let currency: String
        let lastUpdated: String?
        let paymentMethods: Int?
        let totalReceived: Double?
        let totalSpent: Double?
        let monthVolume: Double?
        let stripeBalance: StripeBalance?

        struct StripeBalance: Codable {
            let available: Double
            let pending: Double
            let instantAvailable: Double
        }

        private enum CodingKeys: String, CodingKey {
            case available, pending, reserved, escrow, total, currency
            case lastUpdated, paymentMethods, totalReceived, totalSpent, monthVolume
            case stripeBalance
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.available = try c.decode(Double.self, forKey: .available)
            self.pending = try c.decode(Double.self, forKey: .pending)
            self.reserved = try c.decode(Double.self, forKey: .reserved)
            self.escrow = try c.decode(Double.self, forKey: .escrow)
            self.total = try c.decode(Double.self, forKey: .total)
            self.currency = try c.decode(String.self, forKey: .currency)
            self.lastUpdated = try c.decodeIfPresent(String.self, forKey: .lastUpdated)
            self.paymentMethods = try c.decodeIfPresent(Int.self, forKey: .paymentMethods)
            self.totalReceived = try c.decodeIfPresent(Double.self, forKey: .totalReceived)
            self.totalSpent = try c.decodeIfPresent(Double.self, forKey: .totalSpent)
            self.monthVolume = try c.decodeIfPresent(Double.self, forKey: .monthVolume)
            self.stripeBalance = try c.decodeIfPresent(StripeBalance.self, forKey: .stripeBalance)
        }
    }

    func getBalance() async throws -> WalletBalance {
        try await api.queryNoInput("wallet.getBalance")
    }

    /// `wallet.getInstantPayoutEligibility` — query, no input.
    struct InstantPayoutEligibility: Decodable {
        let eligible: Bool
        let maxAmount: Double
        let feePercentage: Double
        let minFee: Double
        let availableBalance: Double
        let reason: String?
    }

    func getInstantPayoutEligibility() async throws -> InstantPayoutEligibility {
        try await api.queryNoInput("wallet.getInstantPayoutEligibility")
    }

    // MARK: Payout Schedule (078)
    //
    // MCP-verified at `frontend/server/routers/wallet.ts:689` and
    // `:701`. Drives brick 078 Me · Payout Schedule — the cadence
    // picker (daily / weekly / biweekly / monthly), day-of-week
    // selector for weekly/biweekly, per-payout minimum threshold,
    // and the auto-payout toggle.

    struct PayoutSchedule: Decodable, Equatable {
        /// "daily" | "weekly" | "biweekly" | "monthly"
        let frequency: String
        /// "monday".."friday" — populated for weekly / biweekly only.
        /// Server returns empty string for non-weekly cadences.
        let dayOfWeek: String
        let minimumAmount: Double
        /// ISO-8601 date of the next scheduled payout. May be empty
        /// until the scheduler has computed the first run.
        let nextScheduledPayout: String
        let autoPayoutEnabled: Bool
    }

    func getPayoutSchedule() async throws -> PayoutSchedule {
        try await api.queryNoInput("wallet.getPayoutSchedule")
    }

    struct UpdatePayoutScheduleInput: Encodable {
        let frequency: String?
        let dayOfWeek: String?
        let minimumAmount: Double?
        let autoPayoutEnabled: Bool?
    }

    struct UpdatePayoutScheduleResult: Decodable {
        let success: Bool
        let updatedAt: String?
    }

    func updatePayoutSchedule(
        frequency: String? = nil,
        dayOfWeek: String? = nil,
        minimumAmount: Double? = nil,
        autoPayoutEnabled: Bool? = nil
    ) async throws -> UpdatePayoutScheduleResult {
        try await api.mutation(
            "wallet.updatePayoutSchedule",
            input: UpdatePayoutScheduleInput(
                frequency: frequency,
                dayOfWeek: dayOfWeek,
                minimumAmount: minimumAmount,
                autoPayoutEnabled: autoPayoutEnabled
            )
        )
    }

    // MARK: Earnings Breakdown (079)
    //
    // MCP-verified at `frontend/server/routers/wallet.ts:731`. Drives
    // brick 079 Me · Earnings Breakdown — the revenue-type split
    // (linehaul / fuel surcharge / accessorials / bonuses / other) +
    // top-earning loads list over a rolling 7 / 30 / 90 day window.

    /// Server's `byType` dollar split. Every field is a positive sum
    /// in USD over the selected window — not a percentage. The view
    /// derives percentages at render time against the total so a
    /// category with $0 still renders a zero-width bar instead of
    /// dividing by an all-zero denominator.
    struct EarningsTypeBreakdown: Decodable, Equatable {
        let linehaul: Double
        let fuelSurcharge: Double
        let accessorials: Double
        let bonuses: Double
        let other: Double

        var total: Double {
            linehaul + fuelSurcharge + accessorials + bonuses + other
        }
    }

    /// Row shape in `topLoads[]`. Server caps at 3 rows today; the
    /// iOS view surfaces whatever the server sends so widening the
    /// server limit later doesn't require a mobile release.
    struct EarningsTopLoad: Decodable, Identifiable, Equatable {
        let loadNumber: String
        let amount: Double
        let date: String          // YYYY-MM-DD
        var id: String { "\(date)::\(loadNumber)" }
    }

    /// Optional weekly rollup (server returns []; populated when the
    /// analytics engine ships — iOS decodes whatever arrives and the
    /// view gates rendering on `byWeek.isEmpty == false`).
    struct EarningsWeekBucket: Decodable, Identifiable, Equatable {
        let weekStart: String
        let weekEnd: String
        let total: Double
        var id: String { weekStart }
    }

    struct EarningsBreakdown: Decodable, Equatable {
        let period: String      // "week" | "month" | "quarter"
        let byType: EarningsTypeBreakdown
        let topLoads: [EarningsTopLoad]
        /// Decoded with a permissive fallback — the server ships `[]`
        /// today; when the analytics engine adds weekly rollups iOS
        /// will pick them up without a version bump.
        let byWeek: [EarningsWeekBucket]

        enum CodingKeys: String, CodingKey {
            case period, byType, topLoads, byWeek
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.period    = try c.decode(String.self,                  forKey: .period)
            self.byType    = try c.decode(EarningsTypeBreakdown.self,    forKey: .byType)
            self.topLoads  = try c.decode([EarningsTopLoad].self,        forKey: .topLoads)
            // Server currently returns heterogeneous anys for byWeek —
            // tolerate missing / shape-drift so we never drop the
            // whole breakdown on a schema hiccup.
            self.byWeek = (try? c.decode([EarningsWeekBucket].self, forKey: .byWeek)) ?? []
        }
    }

    struct EarningsBreakdownInput: Encodable {
        let period: String    // "week" | "month" | "quarter"
    }

    func getEarningsBreakdown(period: String = "month") async throws -> EarningsBreakdown {
        try await api.query(
            "wallet.getEarningsBreakdown",
            input: EarningsBreakdownInput(period: period)
        )
    }

    // MARK: Tax Documents (080)
    //
    // MCP-verified at `frontend/server/routers/wallet.ts:758`. Drives
    // brick 080 Me · Tax Documents. Year is optional — omitting it
    // asks the server for the current + prior year (the typical
    // driver view). Passing a specific year is used by the per-year
    // filter pill in the UI.

    struct TaxDocument: Decodable, Identifiable, Equatable {
        let id: String
        /// "1099-NEC" | "1099-K" | "W-9" | "state-1099" | etc.
        /// The server only ships "1099-NEC" today; iOS treats `type`
        /// as a freeform string so state / schedule-C additions
        /// don't need a mobile release.
        let type: String
        let year: Int
        /// "available" | "pending" | "processing"
        let status: String
        /// Relative path (`/api/tax/...pdf`) or absolute URL. The
        /// view resolves against `EusoTripAPI.baseURL` when relative.
        let downloadUrl: String
    }

    struct TaxDocumentsInput: Encodable {
        let year: Int?
    }

    func getTaxDocuments(year: Int? = nil) async throws -> [TaxDocument] {
        try await api.query(
            "wallet.getTaxDocuments",
            input: TaxDocumentsInput(year: year)
        )
    }
}

// MARK: - loadLifecycleRouter (deprecated stub removed)
//
// The original 4-method `LoadLifecycleAPI` definition that lived here
// (executeTransition with `targetLocation` + `ComplianceChecks` struct
// + `ExecuteTransitionResponse` envelope) was a duplicate of the
// canonical 96th-firing struct that lives further down in this file
// (search for "MARK: - loadLifecycleRouter (trip-execution state
// machine)"). Keeping both definitions made the file fail to compile
// with "invalid redeclaration of 'LoadLifecycleAPI'". The canonical
// version replaces this one — no production caller used the older
// signatures (verified via grep across Views/ + ViewModels/ + Services/
// for `targetLocation:`, `LoadLifecycleAPI.LatLng`,
// `LoadLifecycleAPI.ComplianceChecks`, `ExecuteTransitionResponse` —
// only this struct itself referenced them).

// MARK: - podRouter
//
// Mirrors `frontend/server/routers/pod.ts`. POD (Proof of Delivery)
// is the driver's hand-off after the consignee unloads — the driver
// captures a photo of the signed BOL, a fingertip / stylus signature
// from the receiver, and any over/short/damage notes. Server stores
// the bundle as a `documents.pod` row + flips the load to
// `pod_pending`. Shipper / dispatch / admin can then `approvePOD`
// (status → `delivered`) or `rejectPOD` (status → `pod_rejected`,
// driver re-captures).
//
// Closes phase 13 (POD capture & approval) of the shipper↔driver
// 8000-scenario gap analysis from PARTIAL → PASS.

struct PODAPI {
    unowned let api: EusoTripAPI

    /// Server ack envelope shared by `submitPOD` / `approvePOD` /
    /// `rejectPOD`. The minimal `success` flag is the only field
    /// every variant guarantees; the rest are optional projections.
    struct PODAck: Decodable, Hashable {
        let success: Bool?
        let message: String?
    }

    /// One row from `pod.getPODForLoad` — the POD packet attached
    /// to a delivered or pod_pending load. Used by the shipper-side
    /// approve / reject screen.
    struct PODPacket: Decodable, Hashable {
        let id: Int?
        let loadId: Int?
        let userId: Int?
        let receiverName: String?
        let photoBase64: String?
        let signatureBase64: String?
        let notes: String?
        let submittedAt: String?
        let status: String?
    }

    /// `pod.submitPOD` — driver-side submit. Server validates the
    /// caller is the assigned driver and the load is in
    /// `unloaded` or `pod_rejected` state, then stores the packet
    /// in `documents` and transitions the load to `pod_pending`.
    @discardableResult
    func submitPOD(
        loadId: Int,
        receiverName: String,
        photoBase64: String? = nil,
        signatureBase64: String? = nil,
        notes: String? = nil
    ) async throws -> PODAck {
        struct Input: Encodable {
            let loadId: Int
            let receiverName: String
            let photoBase64: String?
            let signatureBase64: String?
            let notes: String?
        }
        return try await api.mutation(
            "pod.submitPOD",
            input: Input(
                loadId: loadId,
                receiverName: receiverName,
                photoBase64: photoBase64,
                signatureBase64: signatureBase64,
                notes: notes
            )
        )
    }

    /// `pod.approvePOD` — shipper / dispatch / admin flips the load
    /// from `pod_pending` to `delivered`. Server enforces ownership
    /// (shipper of record) or privileged role.
    @discardableResult
    func approvePOD(loadId: Int) async throws -> PODAck {
        struct Input: Encodable { let loadId: Int }
        return try await api.mutation(
            "pod.approvePOD",
            input: Input(loadId: loadId)
        )
    }

    /// `pod.rejectPOD` — shipper / dispatch / admin sends the load
    /// back to `pod_rejected` so the driver can re-capture. Reason
    /// stored on the load `holdReason` column.
    @discardableResult
    func rejectPOD(loadId: Int, reason: String) async throws -> PODAck {
        struct Input: Encodable {
            let loadId: Int
            let reason: String
        }
        return try await api.mutation(
            "pod.rejectPOD",
            input: Input(loadId: loadId, reason: reason)
        )
    }

    /// `pod.getPODForLoad` — fetch the packet for a single load.
    /// Returns `nil` when no POD has been submitted yet.
    func getPODForLoad(loadId: Int) async throws -> PODPacket? {
        struct Input: Encodable { let loadId: Int }
        return try await api.query(
            "pod.getPODForLoad",
            input: Input(loadId: loadId)
        )
    }
}

// MARK: - disputesRouter
//
// Mirrors `frontend/server/routers/disputes.ts`. Unified dispute
// lifecycle covering settlement / detention / accessorial / POD
// / damage / rate / fraud / other. Phase 16 of the 8000-scenario
// parity audit lands MISSING -> PASS once both shipper-side
// `294_DisputeSettlement.swift` and the driver-side dispute view
// inside `MeDetailRoute` consume this surface.

struct DisputesAPI {
    unowned let api: EusoTripAPI

    enum Category: String, Codable, CaseIterable, Identifiable, Hashable {
        case detention, accessorial, demurrage, settlement
        case rate, damage, pod, fraud, other
        var id: String { rawValue }
        var label: String {
            switch self {
            case .detention:   return "Detention"
            case .accessorial: return "Accessorial"
            case .demurrage:   return "Demurrage"
            case .settlement:  return "Settlement"
            case .rate:        return "Rate"
            case .damage:      return "Damage"
            case .pod:         return "POD"
            case .fraud:       return "Fraud"
            case .other:       return "Other"
            }
        }
        var icon: String {
            switch self {
            case .detention:   return "clock.badge.exclamationmark"
            case .accessorial: return "doc.text.magnifyingglass"
            case .demurrage:   return "shippingbox.and.arrow.backward"
            case .settlement:  return "creditcard.trianglebadge.exclamationmark"
            case .rate:        return "dollarsign.arrow.circlepath"
            case .damage:      return "exclamationmark.triangle"
            case .pod:         return "doc.text.image"
            case .fraud:       return "exclamationmark.shield"
            case .other:       return "exclamationmark.bubble"
            }
        }
    }

    /// Composite dispute id — `dc_<n>` for detention strand,
    /// `pay_<n>` for settlement strand. Stable across calls so
    /// per-row navigation works.
    struct Dispute: Decodable, Hashable, Identifiable {
        let id: String
        let category: String
        let status: String
        let loadId: Int?
        let filedByUserId: Int?
        let filedAgainstUserId: Int?
        let amount: Double?
        let reason: String?
        let evidence: [EvidenceItem]
        let createdAt: String?
        let updatedAt: String?

        struct EvidenceItem: Codable, Hashable {
            let type: String
            let url: String?
            let description: String?
            let message: String?
            let byUserId: Int?
            let byRole: String?
            let timestamp: String?
        }

        /// Strongly-typed category — falls through to `.other` when
        /// the server emits a category the client doesn't yet know.
        var categoryKind: Category {
            Category(rawValue: category) ?? .other
        }
    }

    struct ListResponse: Decodable, Hashable {
        let rows: [Dispute]
        let total: Int
    }

    /// `disputes.list` — every dispute the caller filed or is named
    /// in. Cross-strand union sorted newest-first by createdAt.
    func list(
        category: Category? = nil,
        limit: Int = 40
    ) async throws -> ListResponse {
        struct Input: Encodable {
            let category: String?
            let limit: Int
        }
        return try await api.query(
            "disputes.list",
            input: Input(category: category?.rawValue, limit: limit)
        )
    }

    /// `disputes.getById` — full detail with evidence/message thread.
    func getById(id: String) async throws -> Dispute {
        struct Input: Encodable { let id: String }
        return try await api.query(
            "disputes.getById",
            input: Input(id: id)
        )
    }

    struct ActionAck: Decodable, Hashable {
        let success: Bool?
        let id: String?
        let status: String?
    }

    /// `disputes.respond` — counterparty replies to a dispute.
    /// Server appends a message entry to the evidence thread +
    /// writes a DISPUTE_RESPONDED audit log row.
    @discardableResult
    func respond(
        id: String,
        message: String,
        evidence: [Dispute.EvidenceItem]? = nil
    ) async throws -> ActionAck {
        struct Input: Encodable {
            let id: String
            let message: String
            let evidence: [Dispute.EvidenceItem]?
        }
        return try await api.mutation(
            "disputes.respond",
            input: Input(id: id, message: message, evidence: evidence)
        )
    }

    /// `disputes.escalate` — bump to admin / arbitration. Sets
    /// detention strand to `pending_review`; settlement strand
    /// stays `disputed` but an audit log marks the escalation.
    @discardableResult
    func escalate(
        id: String,
        reason: String
    ) async throws -> ActionAck {
        struct Input: Encodable {
            let id: String
            let reason: String
        }
        return try await api.mutation(
            "disputes.escalate",
            input: Input(id: id, reason: reason)
        )
    }
}

// MARK: - nrcComplianceRouter (hazmat-7 chain-of-custody + dosimetry)
//
// Mirrors `frontend/server/routers/nrcCompliance.ts`. Closes the
// final 160 MISSING scenarios in the 8000-scenario shipper↔driver
// parity audit (cargo type 08 hazmat-7 radioactive). UF + CT both
// lack civilian-freight NRC integration; this router + the iOS
// surfaces shipping alongside it turn those 160 scenarios from
// MISSING into EXCLUSIVE LEAD.

struct NRCAPI {
    unowned let api: EusoTripAPI

    enum LicenseCategory: String, Codable, CaseIterable, Identifiable, Hashable {
        case general, specific
        case typeBCertificate = "type_b_certificate"
        case fissileClass     = "fissile_class"
        case exempt
        var id: String { rawValue }
        var label: String {
            switch self {
            case .general:           return "General license"
            case .specific:          return "Specific license"
            case .typeBCertificate:  return "Type B certificate"
            case .fissileClass:      return "Fissile class"
            case .exempt:            return "Exempt"
            }
        }
    }

    enum DosimetryKind: String, Codable, CaseIterable, Identifiable, Hashable {
        case tldMonthly      = "tld_monthly"
        case epdContinuous   = "epd_continuous"
        case shipmentLog     = "shipment_log"
        case ambient
        var id: String { rawValue }
        var label: String {
            switch self {
            case .tldMonthly:    return "TLD · monthly"
            case .epdContinuous: return "EPD · continuous"
            case .shipmentLog:   return "Shipment log"
            case .ambient:       return "Ambient"
            }
        }
    }

    enum TransferKind: String, Codable, CaseIterable, Identifiable, Hashable {
        case shipperToDriver   = "shipper_to_driver"
        case driverToConsignee = "driver_to_consignee"
        case driverToDriver    = "driver_to_driver"
        case driverToTerminal  = "driver_to_terminal"
        case terminalToDriver  = "terminal_to_driver"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .shipperToDriver:   return "Shipper → Driver"
            case .driverToConsignee: return "Driver → Consignee"
            case .driverToDriver:    return "Driver → Driver"
            case .driverToTerminal:  return "Driver → Terminal"
            case .terminalToDriver:  return "Terminal → Driver"
            }
        }
    }

    // MARK: - License

    struct LicenseStatus: Decodable, Hashable {
        let loadId: String
        let category: String?
        let licenseNumber: String?
        let issuedBy: String?
        let issuedAt: String?
        let expiresAt: String?
        let daysRemaining: Int?
        let authorizedForms: [String]
        let verifiedAt: String?
        let verifiedBy: Int?
        let status: String?  // "active" | "expired" | "missing"
    }

    func getLicenseStatus(loadId: String) async throws -> LicenseStatus {
        struct Input: Encodable { let loadId: String }
        return try await api.query(
            "nrc.getLicenseStatus",
            input: Input(loadId: loadId)
        )
    }

    struct RecordLicenseAck: Decodable, Hashable {
        let success: Bool?
        let documentId: Int?
    }

    @discardableResult
    func recordLicense(
        loadId: String,
        category: LicenseCategory,
        licenseNumber: String,
        issuedBy: String,
        issuedAt: String,
        expiresAt: String,
        authorizedForms: [String]
    ) async throws -> RecordLicenseAck {
        struct Input: Encodable {
            let loadId: String
            let category: String
            let licenseNumber: String
            let issuedBy: String
            let issuedAt: String
            let expiresAt: String
            let authorizedForms: [String]
        }
        return try await api.mutation(
            "nrc.recordLicense",
            input: Input(
                loadId: loadId, category: category.rawValue,
                licenseNumber: licenseNumber, issuedBy: issuedBy,
                issuedAt: issuedAt, expiresAt: expiresAt,
                authorizedForms: authorizedForms
            )
        )
    }

    // MARK: - Chain of custody

    struct CustodyTransfer: Decodable, Hashable, Identifiable {
        let kind: String
        let fromUserId: Int
        let fromUserName: String?
        let fromSignature: String?
        let toUserId: Int
        let toUserName: String?
        let toSignature: String?
        let dosimeterReadingMrem: Double?
        let dosimeterKind: String?
        let location: String?
        let timestamp: String
        let notes: String?

        var id: String { "\(timestamp)-\(fromUserId)-\(toUserId)" }
    }

    struct ChainOfCustody: Decodable, Hashable {
        let loadId: String
        let transfers: [CustodyTransfer]
    }

    func getChainOfCustody(loadId: String) async throws -> ChainOfCustody {
        struct Input: Encodable { let loadId: String }
        return try await api.query(
            "nrc.getChainOfCustody",
            input: Input(loadId: loadId)
        )
    }

    struct RecordTransferAck: Decodable, Hashable {
        let success: Bool?
        let transferIndex: Int?
        let documentId: Int?
    }

    @discardableResult
    func recordTransfer(
        loadId: String,
        kind: TransferKind,
        fromUserId: Int,
        toUserId: Int,
        fromSignatureBase64: String,
        toSignatureBase64: String,
        dosimeterReadingMrem: Double? = nil,
        dosimeterKind: DosimetryKind? = nil,
        location: String? = nil,
        notes: String? = nil
    ) async throws -> RecordTransferAck {
        struct Input: Encodable {
            let loadId: String
            let kind: String
            let fromUserId: Int
            let toUserId: Int
            let fromSignatureBase64: String
            let toSignatureBase64: String
            let dosimeterReadingMrem: Double?
            let dosimeterKind: String?
            let location: String?
            let notes: String?
        }
        return try await api.mutation(
            "nrc.recordTransfer",
            input: Input(
                loadId: loadId, kind: kind.rawValue,
                fromUserId: fromUserId, toUserId: toUserId,
                fromSignatureBase64: fromSignatureBase64,
                toSignatureBase64: toSignatureBase64,
                dosimeterReadingMrem: dosimeterReadingMrem,
                dosimeterKind: dosimeterKind?.rawValue,
                location: location, notes: notes
            )
        )
    }

    // MARK: - Dosimetry

    struct DosimetryReading: Decodable, Hashable, Identifiable {
        let readingMrem: Double
        let kind: String
        let readingTime: String
        let loggedByUserId: Int?
        let notes: String?

        var id: String { "\(readingTime)-\(readingMrem)" }
    }

    struct DosimetryLog: Decodable, Hashable {
        let loadId: String
        let readings: [DosimetryReading]
        let cumulativeMrem: Double
        /// "clear" | "watch" | "warn" | "expired"
        let severity: String
    }

    func getDosimetryLog(loadId: String) async throws -> DosimetryLog {
        struct Input: Encodable { let loadId: String }
        return try await api.query(
            "nrc.getDosimetryLog",
            input: Input(loadId: loadId)
        )
    }

    struct SubmitDosimetryAck: Decodable, Hashable {
        let success: Bool?
        let readingIndex: Int?
        let documentId: Int?
    }

    @discardableResult
    func submitDosimetryReading(
        loadId: String,
        readingMrem: Double,
        kind: DosimetryKind,
        notes: String? = nil
    ) async throws -> SubmitDosimetryAck {
        struct Input: Encodable {
            let loadId: String
            let readingMrem: Double
            let kind: String
            let readingTime: String
            let notes: String?
        }
        return try await api.mutation(
            "nrc.submitDosimetryReading",
            input: Input(
                loadId: loadId,
                readingMrem: readingMrem,
                kind: kind.rawValue,
                readingTime: ISO8601DateFormatter().string(from: Date()),
                notes: notes
            )
        )
    }
}

// MARK: - bayOpsRouter
//
// Four wizards — backingAssist, discharge, connectHose, disconnect — each
// exposing a canonical verb set: start / advanceStep / recordEvidence /
// complete / abort / getSession. Server parity: server/routers/bayOps/*.ts.
//
// Note: `loadId` is `z.number().int().positive()` here (unlike the string
// loadId on loadLifecycle.executeTransition). Pass the numeric Load.id.
//

struct BayOpsAPI {
    unowned let api: EusoTripAPI

    lazy var backingAssist: Wizard = Wizard(api: api, kind: .backingAssist)
    lazy var discharge:     Wizard = Wizard(api: api, kind: .discharge)
    lazy var connectHose:   Wizard = Wizard(api: api, kind: .connectHose)
    lazy var disconnect:    Wizard = Wizard(api: api, kind: .disconnect)

    /// Session snapshot returned by every mutation except recordEvidence.
    struct WizardSession: Decodable {
        let loadId: Int
        let kind: String
        let step: String
        let status: String
        let startedAt: String?
        let startedBy: Int?
        let lastEventId: Int?
    }

    struct WizardSessionEnvelope: Decodable {
        let session: WizardSession
    }

    struct EvidenceAck: Decodable {
        let eventId: Int
        let step: String
    }

    struct GetSessionResponse: Decodable {
        struct Event: Decodable {
            let id: Int?
            let step: String?
            let kind: String?
            let createdAt: String?
        }
        let session: WizardSession?
        let history: [Event]?
    }

    /// One wizard's procedure bundle. The `kind` string is baked into the
    /// tRPC path (e.g. "bayOps.backingAssist.start").
    struct Wizard {
        unowned let api: EusoTripAPI
        let kind: WizardKind

        private var path: String { "bayOps.\(kind.rawValue)" }

        @discardableResult
        func start(loadId: Int) async throws -> WizardSessionEnvelope {
            struct Input: Encodable { let loadId: Int }
            return try await api.mutation("\(path).start", input: Input(loadId: loadId))
        }

        @discardableResult
        func advanceStep(loadId: Int, toStep: String) async throws -> WizardSessionEnvelope {
            struct Input: Encodable {
                let loadId: Int
                let toStep: String
            }
            return try await api.mutation(
                "\(path).advanceStep",
                input: Input(loadId: loadId, toStep: toStep)
            )
        }

        @discardableResult
        func recordEvidence(
            loadId: Int,
            step: String,
            s3Key: String,
            kind evidenceKind: EvidenceKind,
            note: String? = nil
        ) async throws -> EvidenceAck {
            struct Input: Encodable {
                let loadId: Int
                let step: String
                let s3Key: String
                let kind: String
                let note: String?
            }
            return try await api.mutation(
                "\(path).recordEvidence",
                input: Input(
                    loadId: loadId,
                    step: step,
                    s3Key: s3Key,
                    kind: evidenceKind.rawValue,
                    note: note
                )
            )
        }

        @discardableResult
        func complete(loadId: Int) async throws -> WizardSessionEnvelope {
            struct Input: Encodable { let loadId: Int }
            return try await api.mutation("\(path).complete", input: Input(loadId: loadId))
        }

        @discardableResult
        func abort(loadId: Int, reason: String) async throws -> WizardSessionEnvelope {
            struct Input: Encodable {
                let loadId: Int
                let reason: String
            }
            return try await api.mutation(
                "\(path).abort",
                input: Input(loadId: loadId, reason: reason)
            )
        }

        func getSession(loadId: Int) async throws -> GetSessionResponse {
            struct Input: Encodable { let loadId: Int }
            return try await api.query("\(path).getSession", input: Input(loadId: loadId))
        }
    }
}

// MARK: - notificationsRouter
//
// Server parity: `server/routers/notifications.ts` (updatePreferences) and
// `server/routers/push.ts` (getSettings). Device-token registration
// currently lives in the push service-layer (not exposed as tRPC); on
// launch the APNs token is mirrored through the `notifications`
// preferences mutation so the backend at least knows push is enabled.
//

struct NotificationsAPI {
    unowned let api: EusoTripAPI

    struct PreferencesUpdateAck: Decodable {
        let success: Bool
        let channel: String
        let category: String
        let enabled: Bool
    }

    func updatePreferences(
        channel: String,     // "email" | "push" | "sms"
        category: String,    // "loads" | "compliance" | "safety" | "billing" | "system" | "drivers"
        enabled: Bool
    ) async throws -> PreferencesUpdateAck {
        struct Input: Encodable {
            let channel: String
            let category: String
            let enabled: Bool
        }
        return try await api.mutation(
            "notifications.updatePreferences",
            input: Input(channel: channel, category: category, enabled: enabled)
        )
    }

    struct PushSettings: Decodable {
        struct Categories: Decodable {
            let loads: Bool?
            let alerts: Bool?
            let messages: Bool?
            let system: Bool?
        }
        let enabled: Bool
        let deviceToken: String?
        let categories: Categories?
    }

    func getPushSettings() async throws -> PushSettings {
        try await api.queryNoInput("push.getSettings")
    }
}

// MARK: - driversRouter
//
// `drivers.acceptLoad` / `drivers.declineLoad` / `drivers.getPendingLoads`
// from `server/routers/drivers.ts`. `loadId` here is `z.string()` so
// numeric ids must be stringified. The mutations don't return the full
// load record — just a `{ success, loadId }` envelope.
//

struct DriversAPI {
    unowned let api: EusoTripAPI

    struct AcceptDeclineAck: Decodable {
        let success: Bool
        let loadId: String
    }

    /// `drivers.acceptLoad` — driver takes ownership of the offered load.
    /// Server sets `driverId = currentUser.id`, `status = 'assigned'`.
    @discardableResult
    func acceptLoad(loadId: String) async throws -> AcceptDeclineAck {
        struct Input: Encodable { let loadId: String }
        return try await api.mutation("drivers.acceptLoad", input: Input(loadId: loadId))
    }

    /// `drivers.declineLoad` — driver refuses the offered load. Server
    /// clears `driverId`, reverts `status = 'posted'`.
    @discardableResult
    func declineLoad(loadId: String, reason: String? = nil) async throws -> AcceptDeclineAck {
        struct Input: Encodable {
            let loadId: String
            let reason: String?
        }
        return try await api.mutation(
            "drivers.declineLoad",
            input: Input(loadId: loadId, reason: reason)
        )
    }

    struct PendingLoad: Decodable {
        let id: String
        let loadNumber: String?
        let status: String?
        let origin: String?
        let destination: String?
        let rate: Double?
        let pickupDate: String?
    }

    func getPendingLoads() async throws -> [PendingLoad] {
        try await api.queryNoInput("drivers.getPendingLoads")
    }

    // MARK: - Active tender (iOS 052 Ratecon Tender)

    /// Tender endpoint (origin / destination) as projected by
    /// `drivers.getActiveTender` on the server.
    struct TenderEndpoint: Decodable {
        let name: String
        let detail: String?
    }

    /// Rate breakdown materialized server-side. Numbers are authoritative
    /// — the client never recomputes them.
    struct TenderRate: Decodable {
        let totalToDriver: Double
        let ratePerMile: Double
        let linehaul: Double
        let fuelSurcharge: Double
        let accessorials: Double
        let fuelSurchargeIndex: String?
        let accessorialNote: String?
        let platformFeePct: Double?
    }

    /// Broker projection. `rating` will populate once the carrier
    /// scorecard surfaces it; `avatarInitial` is a single uppercase letter
    /// used for the circular glyph in the broker card.
    struct TenderBroker: Decodable {
        let id: String
        let name: String
        let mc: String?
        let rating: String?
        let avatarInitial: String?
    }

    /// Active tender projection. Mirrors `drivers.getActiveTender` on the
    /// server — `null` when the driver has no live tender (the UI renders
    /// a neutral empty state per SKILL.md §13).
    struct ActiveTender: Decodable {
        let loadId: String
        let loadNumber: String?
        /// `"awaiting_accept" | "accepted_in_flight"`
        let status: String
        let originName: String
        let originDetail: String?
        let destinationName: String
        let destinationDetail: String?
        let miles: Double
        let commodity: String?
        let commodityCode: String?
        let equipment: String?
        let weight: String?
        let rate: TenderRate
        let broker: TenderBroker?
        let expiresAt: String?
        let bolNumber: String?
        let bolIssuedAt: String?
        let esangInsight: String?
    }

    /// `drivers.getActiveTender` — query, no input. Returns `nil` when
    /// no tender is live for the current driver. The iOS ViewModel maps
    /// `nil` to the empty state, a populated value to the rendered
    /// tender card.
    func getActiveTender() async throws -> ActiveTender? {
        try await api.queryNoInput("drivers.getActiveTender")
    }

    /// Counter-offer ack returned by `drivers.counterOffer`.
    struct CounterOfferAck: Decodable {
        let success: Bool
        let loadId: String
        let bidId: String?
        let amount: Double
        let status: String
    }

    /// `drivers.counterOffer` — driver proposes a different rate on the
    /// posted tender. Creates a row in `loadBids` with
    /// bidderRole='driver' and status='countered'.
    @discardableResult
    func counterOffer(loadId: String, amount: Double, conditions: String? = nil) async throws -> CounterOfferAck {
        struct Input: Encodable {
            let loadId: String
            let amount: Double
            let conditions: String?
        }
        return try await api.mutation(
            "drivers.counterOffer",
            input: Input(loadId: loadId, amount: amount, conditions: conditions)
        )
    }

    /// Rate-con PDF URL projection returned by `drivers.getRateConURL`.
    struct RateConURL: Decodable {
        let url: String?
        let loadId: String
        let generated: Bool
    }

    /// `drivers.getRateConURL` — URL the iOS client can hand to
    /// SFSafariViewController or `UIApplication.shared.open(_:)` to render
    /// the rate confirmation PDF. `url == nil` when the backend can't
    /// resolve a document — UI surfaces a neutral "PDF unavailable"
    /// message rather than a fake success.
    func getRateConURL(loadId: String) async throws -> RateConURL {
        struct Input: Encodable { let loadId: String }
        return try await api.query("drivers.getRateConURL", input: Input(loadId: loadId))
    }

    // MARK: - Carrier (employer) lookup

    /// Wire shape returned by `drivers.getMyCarrier`. Mirrors the server
    /// projection 1:1 — every field is optional because a freshly seeded
    /// driver may have empty company metadata, and the iOS surfaces fall
    /// back to em-dash neutral state per the Cohort B M2 doctrine.
    ///
    /// `*DaysRemaining` is server-evaluated so the UI can flash amber
    /// (≤30d), red (≤7d), or "Lapsed" (≤0d) without re-parsing the
    /// timestamp client-side. `null` means the carrier never recorded
    /// that cert, not "good forever."
    struct MyCarrier: Decodable {
        let companyId: Int
        let name: String?
        let legalName: String?
        let dotNumber: String?
        let mcNumber: String?
        let ein: String?
        let phone: String?
        let email: String?
        let website: String?
        let logo: String?
        let address: String?
        let city: String?
        let state: String?
        let zipCode: String?
        let country: String?
        let complianceStatus: String?
        let companyCategory: String?
        let supportedModes: [String]?
        let insuranceExpiry: String?
        let insuranceDaysRemaining: Int?
        let hazmatExpiry: String?
        let hazmatDaysRemaining: Int?
        let twicExpiry: String?
        let twicDaysRemaining: Int?
    }

    /// `drivers.getMyCarrier` — who the signed-in driver works for.
    /// Returns `nil` when the driver row is missing a company link
    /// (server returns `null`, not an error). Render an
    /// "Attach to a carrier" CTA in that branch.
    func getMyCarrier() async throws -> MyCarrier? {
        try await api.queryNoInput("drivers.getMyCarrier")
    }

    // MARK: - Performance metrics (Catalyst 320 Driver Scorecard)

    /// One driver's performance scorecard. Backed by
    /// `drivers.getPerformanceMetrics` (frontend/server/routers/drivers.ts:544)
    /// which joins loads + inspections + hosLogs + fuelTransactions
    /// for the named period and emits real metric numerators —
    /// onTimeDeliveryRate is delivered/total over the window,
    /// hosCompliance is non-violation HOS days / total, fuelEfficiency
    /// is loads.distance / fuelTransactions.gallons. The scorecard
    /// surface (320 Catalyst Driver Performance Scorecard) renders
    /// these directly. Empty / zeroed envelope when the driver has no
    /// loads in the window — never a fabricated number.
    struct PerformanceMetrics: Decodable, Equatable {
        let totalMiles: Double
        let totalLoads: Int
        let onTimeDeliveryRate: Double  // 0–100
        let safetyScore: Double         // 0–100 (server stores int)
        let fuelEfficiency: Double      // mpg
        let customerRating: Double      // 0–5
        let hosCompliance: Double       // 0–100
        let inspectionPassRate: Double  // 0–100
    }

    struct PerformanceRankings: Decodable, Equatable {
        let overall: Int
        let totalDrivers: Int
        let safetyRank: Int
        let productivityRank: Int
    }

    struct PerformanceTrend: Decodable, Equatable {
        let current: Double
        let previous: Double
        let change: Double
    }

    struct PerformanceTrends: Decodable, Equatable {
        let safetyScore: PerformanceTrend
        let onTimeRate: PerformanceTrend
    }

    struct PerformanceScorecard: Decodable, Equatable {
        let driverId: String
        let period: String
        let metrics: PerformanceMetrics
        let rankings: PerformanceRankings
        let trends: PerformanceTrends
    }

    enum PerformancePeriod: String, Encodable {
        case week, month, quarter, year
    }

    func getPerformanceMetrics(
        driverId: String,
        period: PerformancePeriod = .month
    ) async throws -> PerformanceScorecard {
        struct Input: Encodable {
            let driverId: String
            let period: String
        }
        return try await api.query(
            "drivers.getPerformanceMetrics",
            input: Input(driverId: driverId, period: period.rawValue)
        )
    }

    // MARK: - Driver profile (Catalyst 321 Driver Profile)

    /// Full driver profile envelope returned by `drivers.getById`
    /// (drivers.ts:378). Joins drivers ↔ users for the display name +
    /// contact, then per-driver joins the live `loads` row (in_transit
    /// / assigned status) for `currentLoad` and the trailing-month
    /// `loads` aggregate for the stats sub-envelope. Powers the
    /// Catalyst-side 321 Driver Profile screen + future driver-detail
    /// surfaces (323 Performance, 324 Settlement Ledger, 327 Quarterly
    /// History) that need richer per-driver context than the lightweight
    /// `catalysts.getMyDrivers` row.
    struct DriverProfileLocation: Decodable, Hashable {
        let lat: Double
        let lng: Double
        let city: String
        let state: String
    }

    struct DriverProfileCDL: Decodable, Hashable {
        let number: String
        /// "A" | "B" | "C"
        let `class`: String
        /// Endorsements like ["H", "N", "T", "P", "X"]
        let endorsements: [String]
        let expirationDate: String
    }

    struct DriverProfileMedicalCard: Decodable, Hashable {
        let expirationDate: String
        /// "valid" | "expired"
        let status: String
    }

    struct DriverProfilePayRate: Decodable, Hashable {
        let type: String       // "per_mile" | "per_load" | "salary"
        let rate: Double
    }

    struct DriverProfileMonthlyStats: Decodable, Hashable {
        let loadsThisMonth: Int
        let milesThisMonth: Double
        let earningsThisMonth: Double
        let onTimeRate: Double
    }

    struct DriverProfile: Decodable, Hashable {
        let id: String
        let name: String
        let phone: String
        let email: String
        /// "on_load" | "available" | "off_duty"
        let status: String
        let currentLoad: String?
        let location: DriverProfileLocation
        let hoursRemaining: Double
        let safetyScore: Double
        let rating: Double
        let hireDate: String
        let truckNumber: String
        let cdlNumber: String
        let cdl: DriverProfileCDL
        let medicalCard: DriverProfileMedicalCard
        let homeTerminal: String
        let payRate: DriverProfilePayRate
        let stats: DriverProfileMonthlyStats
        let loadsCompleted: Int
        let onTimeRate: Double
        let milesLogged: Double
    }

    /// `drivers.getById` — full per-driver profile. Returns nil when
    /// the row doesn't exist (server returns null, not an error).
    func getProfileById(driverId: String) async throws -> DriverProfile? {
        struct Input: Encodable { let id: String }
        return try await api.query(
            "drivers.getById",
            input: Input(id: driverId)
        )
    }

    // MARK: - assignLoad (Catalyst 305 dispatcher action)

    struct AssignLoadResult: Decodable {
        let success: Bool
        let driverId: String
        let loadId: String
        let assignedAt: String
    }

    /// `drivers.assignLoad` (drivers.ts:597) — flips a load's
    /// `driverId` column to the named driver's `userId` and bumps
    /// `loads.status` to `'assigned'`. Catalyst 305 dispatcher action
    /// is the canonical caller (REASSIGN / ASSIGN buttons).
    func assignLoad(driverId: String, loadId: String, notes: String? = nil) async throws -> AssignLoadResult {
        struct Input: Encodable {
            let driverId: String
            let loadId: String
            let notes: String?
        }
        return try await api.mutation(
            "drivers.assignLoad",
            input: Input(driverId: driverId, loadId: loadId, notes: notes)
        )
    }

    // MARK: - update (Catalyst 321 Edit Profile)

    struct UpdateDriverResult: Decodable {
        let success: Bool?
    }

    /// `drivers.update` (drivers.ts:45) — patches a driver row's
    /// editable columns. Server takes Int id; iOS sends as Int via the
    /// matching Encodable. Catalyst 321 Edit sheet is the canonical
    /// caller (catalyst editing one of their own drivers' DQ fields).
    func update(
        driverId: String,
        licenseNumber: String? = nil,
        licenseState: String? = nil,
        licenseExpiry: String? = nil,
        medicalCardExpiry: String? = nil,
        hazmatEndorsement: Bool? = nil,
        status: String? = nil
    ) async throws -> UpdateDriverResult {
        struct Input: Encodable {
            let id: Int
            let licenseNumber: String?
            let licenseState: String?
            let licenseExpiry: String?
            let medicalCardExpiry: String?
            let hazmatEndorsement: Bool?
            let status: String?
        }
        let intId = Int(driverId) ?? 0
        return try await api.mutation(
            "drivers.update",
            input: Input(
                id: intId,
                licenseNumber: licenseNumber,
                licenseState: licenseState,
                licenseExpiry: licenseExpiry,
                medicalCardExpiry: medicalCardExpiry,
                hazmatEndorsement: hazmatEndorsement,
                status: status
            )
        )
    }
}

// MARK: - AnyEncodable (erased encodable for dictionary inputs)

struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

/// Wraps an already-serialized JSON `Data` payload so it can be
/// re-encoded verbatim by the outer JSONEncoder. Used by
/// `ShipperAPI.create` to forward heterogenous `[String: Any]`
/// dictionaries (e.g. `modeRoutePayload`) that can't satisfy
/// Swift's `Encodable` existential constraints directly.
struct JSONRawEncodable: Encodable {
    let data: Data
    func encode(to encoder: Encoder) throws {
        // Decode into a generic AnyDecodable-ish shape and re-encode
        // so the result is a real JSON object in the parent envelope
        // rather than a string-escaped blob.
        let json = try JSONSerialization.jsonObject(with: data)
        try encodeJSONValue(json, to: encoder)
    }

    private func encodeJSONValue(_ value: Any, to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as String: try container.encode(v)
        case let v as Bool:   try container.encode(v)
        case let v as Int:    try container.encode(v)
        case let v as Double: try container.encode(v)
        case is NSNull:       try container.encodeNil()
        case let v as [Any]:
            try container.encode(v.map { JSONRawElement(value: $0) })
        case let v as [String: Any]:
            try container.encode(v.mapValues { JSONRawElement(value: $0) })
        default:
            // Best-effort fallback — stringify so the field isn't lost.
            try container.encode(String(describing: value))
        }
    }
}

/// Single JSON value wrapper used by `JSONRawEncodable.encode` so the
/// nested encoding into arrays/dicts goes through the same switch.
private struct JSONRawElement: Encodable {
    let value: Any
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as String: try container.encode(v)
        case let v as Bool:   try container.encode(v)
        case let v as Int:    try container.encode(v)
        case let v as Double: try container.encode(v)
        case is NSNull:       try container.encodeNil()
        case let v as [Any]:
            try container.encode(v.map { JSONRawElement(value: $0) })
        case let v as [String: Any]:
            try container.encode(v.mapValues { JSONRawElement(value: $0) })
        default:
            try container.encode(String(describing: value))
        }
    }
}

// MARK: - newsRouter
//
// Mirrors frontend/server/routers/news.ts. The server fans out to ~100
// tier-1 RSS feeds across 11 categories and caches a unified feed; we
// just call `getArticles`, `getMorningBrief`, `getBreakingNews`, and
// `cacheStatus` for the lightweight poll.

struct NewsAPI {
    unowned let api: EusoTripAPI

    /// `news.getArticles` — paginated, filtered feed.
    func getArticles(
        category: String? = nil,
        search: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> NewsArticlePage {
        struct Input: Encodable {
            let category: String?
            let search: String?
            let limit: Int
            let offset: Int
        }
        return try await api.query(
            "news.getArticles",
            input: Input(category: category, search: search, limit: limit, offset: offset)
        )
    }

    /// `news.cacheStatus` — cheap poll (~1KB) to detect new articles
    /// without refetching the whole feed.
    func cacheStatus() async throws -> NewsCacheStatus {
        try await api.queryNoInput("news.cacheStatus")
    }

    /// `news.getTrending` — top 10 by engagement.
    func getTrending() async throws -> [NewsArticle] {
        try await api.queryNoInput("news.getTrending")
    }

    /// `news.getMorningBrief` — 8 articles personalised to the role.
    /// Role strings match the server enum (DRIVER, DISPATCH, SHIPPER, …).
    func getMorningBrief(role: String) async throws -> NewsMorningBrief {
        struct Input: Encodable { let role: String }
        return try await api.query("news.getMorningBrief", input: Input(role: role))
    }

    /// `news.getBreakingNews` — clusters from the last 2 hours reported
    /// by 3+ distinct sources.
    func getBreakingNews() async throws -> [NewsBreakingCluster] {
        try await api.queryNoInput("news.getBreakingNews")
    }

    /// `news.saveArticle` / `news.unsaveArticle` — bookmark toggles.
    func saveArticle(id: String) async throws -> GenericMessageResponse {
        struct Input: Encodable { let articleId: String }
        return try await api.mutation("news.saveArticle", input: Input(articleId: id))
    }

    func unsaveArticle(id: String) async throws -> GenericMessageResponse {
        struct Input: Encodable { let articleId: String }
        return try await api.mutation("news.unsaveArticle", input: Input(articleId: id))
    }

    /// `news.getSavedArticles` — user's bookmark list.
    func getSavedArticles() async throws -> [NewsArticle] {
        try await api.queryNoInput("news.getSavedArticles")
    }

    /// `news.translateArticle` — Gemini 3.5 (ESANG) article translation.
    ///
    /// 2026-05-20: replaces the in-app reader's old Apple-Translation-
    /// framework + dead `translate.google.com/translate?u=` proxy path.
    /// The reader extracts the visible DOM text and posts it here; the
    /// server translates via ESANG and returns the translated body.
    /// Works on every iOS version + every publisher (no CSP/X-Frame
    /// problems because we never re-navigate the WebView).
    func translateArticle(
        text: String,
        targetLanguage: String,
        sourceLanguage: String? = nil,
        articleId: String? = nil
    ) async throws -> NewsTranslationResult {
        struct Input: Encodable {
            let text: String
            let targetLanguage: String
            let sourceLanguage: String?
            let articleId: String?
        }
        return try await api.mutation(
            "news.translateArticle",
            input: Input(
                text: text,
                targetLanguage: targetLanguage,
                sourceLanguage: sourceLanguage,
                articleId: articleId
            )
        )
    }
}

/// Mirrors the server's `news.translateArticle` reply shape.
struct NewsTranslationResult: Decodable, Sendable {
    let ok: Bool
    let translated: String
    let sourceLanguage: String
    let targetLanguage: String
    let error: String?
    let latencyMs: Int?
}

// MARK: - HereMapsAPI
//
// iOS-side facade over the `hereMaps.*` tRPC router
// (frontend/server/routers/hereMaps.ts). Every server-side HERE add-on
// — including the monetization (ad-zones, fuel-affiliate) +
// gamification (haul missions, location analytics) layer — is reached
// here so iOS and web stay in lockstep. Inputs match the verified Zod
// schemas; outputs decode into the shapes below (extend as the UI needs
// more fields — decoding is lenient on unknown keys via optionals).

struct HereMapsAPI {
    unowned let api: EusoTripAPI

    // ── Shared wire types ──
    struct LatLng: Encodable { let lat: Double; let lng: Double }
    struct BBox: Encodable { let north: Double; let south: Double; let east: Double; let west: Double }

    // MARK: Ad Zones (MONETIZATION — sponsored / SAE-ODD zones)
    struct AdZone: Decodable, Identifiable, Hashable {
        let id: String
        let name: String?
        let saeLevel: Int?
        let polygon: [Coord]?
        let conditions: [String]?
        struct Coord: Decodable, Hashable { let lat: Double; let lng: Double }
    }
    func adZonesInBbox(_ bbox: BBox) async throws -> [AdZone] {
        // Server returns an array; wrap-tolerant decode.
        try await api.query("hereMaps.adZonesInBbox", input: bbox)
    }

    // MARK: ISA — speed limits (feeds safety score + gamification)
    struct IsaResult: Decodable, Hashable {
        let speedLimitKph: Double?
        let speedUnit: String?
        let inSchoolZone: Bool?
    }
    func isaForPoint(lat: Double, lng: Double) async throws -> IsaResult {
        try await api.query("hereMaps.isaForPoint", input: LatLng(lat: lat, lng: lng))
    }
    func isaAlongPolyline(_ polyline: String) async throws -> [IsaResult] {
        struct In: Encodable { let polyline: String }
        return try await api.query("hereMaps.isaAlongPolyline", input: In(polyline: polyline))
    }

    // MARK: ADAS attributes (curvature / slope — co-pilot ODD)
    func adasForLink(tileId: Int, linkId: Int) async throws -> AdasResult {
        struct In: Encodable { let tileId: Int; let linkId: Int }
        return try await api.query("hereMaps.adasForLink", input: In(tileId: tileId, linkId: linkId))
    }
    struct AdasResult: Decodable, Hashable {
        let curvatures: [Double]?
        let slopes: [Double]?
    }

    // MARK: Road alerts along a route
    struct RoadAlert: Decodable, Identifiable, Hashable {
        let id: String
        let type: String?
        let description: String?
        let lat: Double?
        let lng: Double?
    }
    func roadAlertsAlongRoute(polyline: String, marginMeters: Int? = nil) async throws -> [RoadAlert] {
        struct In: Encodable { let polyline: String; let marginMeters: Int? }
        return try await api.query("hereMaps.roadAlertsAlongRoute", input: In(polyline: polyline, marginMeters: marginMeters))
    }

    // MARK: Discover / Browse nearby (truck stops, scales, weigh stations)
    struct Place: Decodable, Identifiable, Hashable {
        let id: String
        let title: String?
        let lat: Double?
        let lng: Double?
        let category: String?
        let distanceMeters: Int?
    }
    func discoverNearby(query: String, at: LatLng, radiusMeters: Int? = nil) async throws -> [Place] {
        struct In: Encodable { let query: String; let at: LatLng; let radiusMeters: Int? }
        return try await api.query("hereMaps.discoverNearby", input: In(query: query, at: at, radiusMeters: radiusMeters))
    }

    // MARK: Autosuggest (address fields)
    struct Suggestion: Decodable, Identifiable, Hashable {
        let id: String
        let title: String
        let lat: Double?
        let lng: Double?
    }
    func autosuggest(query: String, anchor: LatLng, country: String? = nil, limit: Int? = nil) async throws -> [Suggestion] {
        struct In: Encodable { let query: String; let anchor: LatLng; let country: String?; let limit: Int? }
        return try await api.query("hereMaps.autosuggest", input: In(query: query, anchor: anchor, country: country, limit: limit))
    }

    // MARK: EV chargers (consumed alongside HereEVClient)
    struct Charger: Decodable, Identifiable, Hashable {
        let id: String
        let name: String?
        let lat: Double?
        let lng: Double?
        let maxPowerKw: Double?
        let connectorTypes: [String]?
        let available: Int?
    }
    func evChargers(at: LatLng, radiusMeters: Int? = nil, connectorType: String? = nil, minPowerKw: Double? = nil) async throws -> [Charger] {
        struct In: Encodable { let at: LatLng; let radiusMeters: Int?; let connectorType: String?; let minPowerKw: Double? }
        return try await api.query("hereMaps.evChargers", input: In(at: at, radiusMeters: radiusMeters, connectorType: connectorType, minPowerKw: minPowerKw))
    }

    // MARK: Location Analytics (GAMIFICATION — leaderboards + territory badges)
    /// Server collapses breadcrumbs → coverage scalars used by The Haul.
    struct CoverageSummary: Decodable, Hashable {
        let uniqueStates: [String]?
        let uniqueMetros: [String]?
        let uniqueZips: [String]?
        let totalKm: Double?
        let corridorKm: [String: Double]?
    }
    func locationAnalytics(breadcrumbs: [Breadcrumb]) async throws -> CoverageSummary {
        struct In: Encodable { let breadcrumbs: [Breadcrumb] }
        return try await api.query("hereMaps.locationAnalytics", input: In(breadcrumbs: breadcrumbs))
    }
    struct Breadcrumb: Encodable { let lat: Double; let lng: Double; let capturedAt: String; let speedKph: Double? }
}

// MARK: - messagesRouter
//
// Mirrors frontend/server/routers/messages.ts.  The backend is an
// OpenIM-inspired Drizzle/MySQL implementation — 100% DB-backed with
// WebSocket fanout via `emitMessage → message:new` on the
// `conversation:<id>` Socket.IO room.  Procedures we wire:
//
//   messaging.getConversations       → [MessagingConversation]
//   messaging.getMessages            → [MessagingMessage]
//   messaging.sendMessage            → MessagingSendResult
//   messaging.markAsRead             → MessagingMarkReadResult
//   messaging.getUnreadCount         → MessagingUnreadCount
//   messaging.search                 → MessagingSearchResult
//   messaging.searchUsers            → [MessagingUserResult]
//   messaging.createConversation     → MessagingCreateResult
//   messaging.deleteConversation     → MessagingActionResult
//   messaging.archiveConversation    → MessagingActionResult
//   messaging.uploadAttachment       → MessagingAttachmentResult
//   messaging.sendPayment            → MessagingPaymentResult
//   messaging.unsendMessage          → MessagingActionResult
//   messaging.getUserPhone           → MessagingUserPhone
//
// `path` strings point at the canonical `messages` router (the one with
// payments, uploads and unsend). We expose it as `messaging` in Swift to
// line up with how the iOS surface talks about "the messaging stack".

struct MessagingAPI {
    unowned let api: EusoTripAPI

    /// GET /api/trpc/messages.getConversations
    func getConversations(search: String? = nil) async throws -> [MessagingConversation] {
        struct Input: Encodable { let search: String? }
        return try await api.query("messages.getConversations", input: Input(search: search))
    }

    /// GET /api/trpc/messages.getMessages
    func getMessages(
        conversationId: String,
        limit: Int = 50,
        before: String? = nil
    ) async throws -> [MessagingMessage] {
        struct Input: Encodable {
            let conversationId: String
            let limit: Int
            let before: String?
        }
        return try await api.query(
            "messages.getMessages",
            input: Input(conversationId: conversationId, limit: limit, before: before)
        )
    }

    /// POST /api/trpc/messages.sendMessage
    func sendMessage(
        conversationId: String,
        content: String,
        type: String = "text"
    ) async throws -> MessagingSendResult {
        struct Input: Encodable {
            let conversationId: String
            let content: String
            let type: String
        }
        return try await api.mutation(
            "messages.sendMessage",
            input: Input(conversationId: conversationId, content: content, type: type)
        )
    }

    /// POST /api/trpc/messages.markAsRead
    @discardableResult
    func markAsRead(conversationId: String) async throws -> MessagingMarkReadResult {
        struct Input: Encodable { let conversationId: String }
        return try await api.mutation(
            "messages.markAsRead",
            input: Input(conversationId: conversationId)
        )
    }

    /// GET /api/trpc/messages.getUnreadCount
    func getUnreadCount() async throws -> MessagingUnreadCount {
        try await api.queryNoInput("messages.getUnreadCount")
    }

    /// GET /api/trpc/messages.search
    func search(
        query: String,
        conversationId: String? = nil,
        limit: Int = 20
    ) async throws -> MessagingSearchResult {
        struct Input: Encodable {
            let query: String
            let conversationId: String?
            let limit: Int
        }
        return try await api.query(
            "messages.search",
            input: Input(query: query, conversationId: conversationId, limit: limit)
        )
    }

    /// GET /api/trpc/messages.searchUsers — suggest people to DM.
    func searchUsers(query: String? = nil, limit: Int = 20) async throws -> [MessagingUserResult] {
        struct Input: Encodable { let query: String?; let limit: Int }
        return try await api.query(
            "messages.searchUsers",
            input: Input(query: query, limit: limit)
        )
    }

    /// POST /api/trpc/messages.createConversation — idempotent for 1:1 DMs.
    func createConversation(
        participantIds: [Int],
        type: String = "direct",
        name: String? = nil,
        loadId: Int? = nil,
        initialMessage: String? = nil
    ) async throws -> MessagingCreateResult {
        struct Input: Encodable {
            let participantIds: [Int]
            let type: String
            let name: String?
            let loadId: Int?
            let initialMessage: String?
        }
        return try await api.mutation(
            "messages.createConversation",
            input: Input(
                participantIds: participantIds,
                type: type,
                name: name,
                loadId: loadId,
                initialMessage: initialMessage
            )
        )
    }

    /// POST /api/trpc/messages.deleteConversation — soft-delete for caller.
    @discardableResult
    func deleteConversation(conversationId: String) async throws -> MessagingActionResult {
        struct Input: Encodable { let conversationId: String }
        return try await api.mutation(
            "messages.deleteConversation",
            input: Input(conversationId: conversationId)
        )
    }

    /// POST /api/trpc/messages.archiveConversation — hide from inbox.
    @discardableResult
    func archiveConversation(conversationId: String) async throws -> MessagingActionResult {
        struct Input: Encodable { let conversationId: String }
        return try await api.mutation(
            "messages.archiveConversation",
            input: Input(conversationId: conversationId)
        )
    }

    /// POST /api/trpc/messages.uploadAttachment — base64 data URL.
    /// Image `Data` → `data:<mime>;base64,<...>` so the backend can store
    /// it in `messageAttachments.fileUrl` and surface it via `<img src>`.
    func uploadAttachment(
        conversationId: String,
        data: Data,
        fileName: String,
        mimeType: String = "image/jpeg"
    ) async throws -> MessagingAttachmentResult {
        let base64 = data.base64EncodedString()
        let dataURL = "data:\(mimeType);base64,\(base64)"
        struct Input: Encodable {
            let conversationId: String
            let fileName: String
            let fileData: String
            let mimeType: String
            let fileSize: Int
        }
        return try await api.mutation(
            "messages.uploadAttachment",
            input: Input(
                conversationId: conversationId,
                fileName: fileName,
                fileData: dataURL,
                mimeType: mimeType,
                fileSize: data.count
            )
        )
    }

    /// POST /api/trpc/messages.sendPayment
    /// type == "send" debits caller EusoWallet + credits the other party;
    /// type == "request" just posts a `payment_request` card.
    func sendPayment(
        conversationId: String,
        amount: Double,
        currency: String = "USD",
        note: String? = nil,
        type: String = "send"
    ) async throws -> MessagingPaymentResult {
        struct Input: Encodable {
            let conversationId: String
            let amount: Double
            let currency: String
            let note: String?
            let type: String
        }
        return try await api.mutation(
            "messages.sendPayment",
            input: Input(
                conversationId: conversationId,
                amount: amount,
                currency: currency,
                note: note,
                type: type
            )
        )
    }

    /// POST /api/trpc/messages.unsendMessage
    @discardableResult
    func unsendMessage(messageId: String) async throws -> MessagingActionResult {
        struct Input: Encodable { let messageId: String }
        return try await api.mutation(
            "messages.unsendMessage",
            input: Input(messageId: messageId)
        )
    }

    /// GET /api/trpc/messages.getUserPhone — `tel:` link resolution.
    func getUserPhone(userId: Int) async throws -> MessagingUserPhone {
        struct Input: Encodable { let userId: Int }
        return try await api.query("messages.getUserPhone", input: Input(userId: userId))
    }
}

// MARK: - Messaging DTOs
//
// Wire-shape mirrors are loose on purpose: the backend occasionally
// sends `null` where the UI expects a string, and omits optional fields
// entirely when there is no conversation metadata yet. All optional
// fields below are either `nil` or a sensible default after decode.

struct MessagingConversation: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let participantName: String?
    let avatar: String?
    let type: String?
    let lastMessage: String?
    let lastMessageAt: String?
    let unread: Int?
    let unreadCount: Int?
    let online: Bool?
    let role: String?
    let loadId: Int?
    let isPinned: Bool?
    let isMuted: Bool?

    var displayName: String { participantName ?? name }
    var effectiveUnread: Int { unreadCount ?? unread ?? 0 }
}

struct MessagingMessage: Decodable, Identifiable, Equatable {
    let id: String
    let conversationId: String
    let senderId: String
    let senderName: String?
    let senderAvatar: String?
    let content: String
    let type: String?
    let timestamp: String?
    let read: Bool?
    let isOwn: Bool?

    /// Decodes tRPC's `metadata` field (arbitrary JSON) into the subset
    /// the chat UI actually cares about: payment amount/note/status for
    /// `payment_sent` / `payment_request` cards, and attachment preview
    /// URLs for image messages.
    let metadata: MessagingMessageMetadata?
}

struct MessagingMessageMetadata: Decodable, Equatable {
    let amount: Double?
    let currency: String?
    let note: String?
    let status: String?
    let senderName: String?
    let fileUrl: String?
    let fileName: String?
    let mimeType: String?
    let recipientId: Int?
}

struct MessagingSendResult: Decodable {
    let id: String
    let conversationId: String
    let senderId: String?
    let senderName: String?
    let content: String?
    let type: String?
    let timestamp: String?
    let read: Bool?
    let isOwn: Bool?
}

struct MessagingMarkReadResult: Decodable {
    let success: Bool
    let conversationId: String
    let markedCount: Int?
}

struct MessagingUnreadCount: Decodable {
    let total: Int
    let byConversation: [String: Int]
}

struct MessagingSearchResult: Decodable {
    struct Hit: Decodable, Identifiable {
        let messageId: String
        let conversationId: String
        let content: String
        let timestamp: String?
        let senderName: String?
        let highlight: String?
        var id: String { messageId }
    }
    let results: [Hit]
    let total: Int
}

struct MessagingUserResult: Decodable, Identifiable, Equatable {
    let id: Int
    let name: String
    let email: String?
    let role: String?
    let avatar: String?
    let phone: String?
}

struct MessagingCreateResult: Decodable {
    let id: String
    let createdAt: String?
    let existing: Bool?
}

struct MessagingActionResult: Decodable {
    let success: Bool?
    let conversationId: String?
    let messageId: String?
}

struct MessagingAttachmentResult: Decodable {
    let success: Bool
    let messageId: String
    let attachmentId: String
    let fileName: String
    let type: String
}

struct MessagingPaymentResult: Decodable {
    let id: String
    let type: String
    let amount: Double
    let currency: String
    let status: String
}

struct MessagingUserPhone: Decodable {
    let phone: String?
    let name: String?
}

// MARK: - hotZonesRouter
//
// Wraps `hotZones.getRateFeed` — the same tRPC procedure the web
// `/hot-zones` page uses to power its national heatmap + rate feed.
// The iOS Driver Home widget reuses the same intelligence data so the
// driver sees the exact same load-to-truck ratios, live rates, surge
// multipliers, and demand levels that the dispatcher sees on the web.
//
// The web procedure returns ~25 zones with rich fields (FMCSA, fuel,
// weather, forecasts). On mobile we decode a leaner subset (just what
// the widget renders) so the decode stays fast and flexible when the
// backend adds new fields.

struct HotZonesAPI {
    unowned let api: EusoTripAPI

    /// GET /api/trpc/hotZones.getRateFeed — national zone intelligence.
    /// Equipment filter narrows to zones whose topEquipment includes it
    /// (e.g. "REEFER", "FLATBED"). Role-based filtering happens server-side
    /// off the authenticated user.
    func getRateFeed(equipment: String? = nil) async throws -> HotZonesFeedResult {
        struct Input: Encodable {
            let equipment: String?
            // `layers` / `userLat` / `userLng` accepted by the server but
            // not used by the mobile widget — omit to keep the request
            // envelope small.
        }
        return try await api.query("hotZones.getRateFeed", input: Input(equipment: equipment))
    }
}

// MARK: - HotZones DTOs

/// National hot-zone intelligence feed. Decodes a leaner subset of the
/// web `/hot-zones` rateFeed so the mobile widget stays nimble when the
/// backend adds new fields (FMCSA sub-object, AI trends, etc.).
struct HotZonesFeedResult: Decodable {
    let zones: [HotZoneEntry]
    let coldZones: [ColdZoneEntry]?
    let marketPulse: HotZonesMarketPulse?
    let timestamp: String?
    let refreshInterval: Int?
    let feedSource: String?
}

struct HotZoneCenter: Decodable, Hashable {
    let lat: Double
    let lng: Double
}

struct HotZoneEntry: Decodable, Identifiable, Equatable {
    var id: String { zoneId }
    let zoneId: String
    let zoneName: String
    let state: String
    let center: HotZoneCenter
    let radius: Double
    let demandLevel: String          // "CRITICAL" | "HIGH" | "ELEVATED"
    let demandTrend: String?         // "RISING" | "STABLE" | "FALLING"
    let nextWeekForecast: String?    // short forecast blurb
    let liveRate: Double             // $/mile
    let liveLoads: Int
    let liveTrucks: Int
    let liveRatio: Double
    let liveSurge: Double
    let rateChange: Double?
    let rateChangePercent: Double?
    let topEquipment: [String]
    let reasons: [String]?           // why this zone is hot
    // ── peakHours is a STRING on the wire (e.g. "06:00-14:00 PT"),
    // ── not an array. Decoding it as [String] made the whole feed fail.
    let peakHours: String?
    let hazmatClasses: [String]?
    let oversizedFrequency: String?
    let weatherRiskLevel: String?
    let weatherAlerts: [HotZoneWeatherAlert]?
    let complianceRiskScore: Int?
    let safetyScore: Double?
    let carriersWithViolations: Int?
    let recentHazmatIncidents: Int?
    let activeWildfires: Int?
    let femaDisasterActive: Bool?
    let seismicRiskLevel: String?
    let epaFacilitiesCount: Int?
    let fuelPrice: Double?
    let platformLoads: Int?
    let aiRateTrend: String?
    let aiRateAnomaly: Bool?
    let fmcsa: HotZoneFMCSA?

    static func == (lhs: HotZoneEntry, rhs: HotZoneEntry) -> Bool { lhs.zoneId == rhs.zoneId }
}

/// FMCSA enrichment block attached to each zone — 9.8M-record carrier
/// census sliced by state and blended with recent crash / inspection
/// rollups (last 90 days / 30 days).
struct HotZoneFMCSA: Decodable, Equatable {
    let carriers: Int?
    let powerUnits: Int?
    let drivers: Int?
    let hazmatCarriers: Int?
    let avgFleetSize: Double?
    let crashes90d: Int?
    let crashFatalities: Int?
    let crashInjuries: Int?
    let inspections30d: Int?
    let violations30d: Int?
    let oosRate: Double?
}

/// NWS/active weather alert attached to a hot zone. Server sends up to
/// 3 per zone; we only use a handful of fields for the widget's risk
/// banner but decode loosely so new fields can ship server-side without
/// breaking the app.
struct HotZoneWeatherAlert: Decodable, Equatable {
    let event: String?
    let severity: String?
    let headline: String?
    let areaDesc: String?
}

struct ColdZoneEntry: Decodable, Identifiable, Equatable {
    var id: String { zoneId ?? (name ?? UUID().uuidString) }
    let zoneId: String?
    let name: String?
    let state: String?
    let center: HotZoneCenter?
    let radius: Double?
    let liveRate: Double?
    let liveSurge: Double?
    let liveTrucks: Int?

    enum CodingKeys: String, CodingKey {
        case zoneId = "id", name, state, center, radius, liveRate, liveSurge, liveTrucks
    }

    static func == (lhs: ColdZoneEntry, rhs: ColdZoneEntry) -> Bool { lhs.id == rhs.id }
}

struct HotZonesMarketPulse: Decodable, Equatable {
    let avgRate: Double?
    let avgRatio: Double?
    let totalLoads: Int?
    let totalTrucks: Int?
    let criticalZones: Int?
    let avgFuelPrice: Double?
    let activeWeatherAlerts: Int?
}

// MARK: - eldRouter (Electronic Logging Device integration)
//
// Mirrors frontend/server/routers/eld.ts + frontend/server/services/eld.ts.
// The web platform is the source-of-truth for the supported ELD catalog —
// we don't hardcode a second copy of the provider list on iOS. Instead we
// call `eld.getAllProviders` and render whatever the backend returns so new
// providers (Samsara, Geotab, Motive, Powerfleet, Zonar, Lytx, Netradyne,
// Verizon Connect, Azuga, Solera, Trimble/PeopleNet, and any future adds)
// show up on-device the moment they're shipped server-side.
//
// Connection persistence lives in the `integrationConnections` table on the
// server (one row per (companyId, providerSlug), unique index). Credentials
// never touch the app binary — the driver types their API key into the
// provider screen, we POST it to `eld.connectProvider`, and the Samsara/
// Motive/Geotab poll runs server-side from that moment on.
//
// HOS data is already consumed from the same `hos.getStatus` / `hos.getDailyLog`
// endpoints that back MeEldView + 019_HosDutyStatus; once the ELD is connected,
// those endpoints receive real-time driver status from the provider (49 CFR 395)
// instead of the self-reported fallback, so no additional iOS wiring is needed
// beyond this connector UI — the data pipe "just turns on."
//
// Read-only symbiotic connection policy: the iOS surface never pushes status
// changes to the external ELD. The ELD pushes to us; we only write back
// EusoTrip-internal state (loads, messaging, dispatch) that never leaves the
// platform. This mirrors the web `ELDConnectionPanel` shield badge.

struct ELDAPI {
    unowned let api: EusoTripAPI

    /// `eld.getAllProviders` — catalog of supported ELD providers.
    /// Server source: `ELD_PROVIDERS` in `frontend/server/services/eld.ts`.
    /// Returned newest-first by the canonical registry (Samsara → Trimble).
    func getAllProviders() async throws -> [ELDProvider] {
        try await api.queryNoInput("eld.getAllProviders")
    }

    /// `eld.getConnectionStatus` — is this company's fleet wired up to an
    /// ELD right now? Loaded from `integrationConnections` server-side so
    /// any web-user or dispatcher change is reflected immediately on iOS.
    func getConnectionStatus() async throws -> ELDConnectionStatus {
        try await api.queryNoInput("eld.getConnectionStatus")
    }

    /// `eld.getProviderConfig` — rich config snapshot for the currently
    /// configured ELD (Samsara-primary today; other providers rely on
    /// the generic `getConnectionStatus` surface). Also exposes the 49
    /// CFR 395 HOS limit constants so the iOS compliance card can render
    /// them without a second round-trip.
    func getProviderConfig() async throws -> ELDProviderConfig {
        try await api.queryNoInput("eld.getProviderConfig")
    }

    /// `eld.connectProvider` — POST mutation. Upserts a provider
    /// credential (API key / bearer token) for the caller's company into
    /// `integrationConnections`, marks status = "connected", and clears
    /// the server-side ELD service cache so the next `hos.getStatus`
    /// call pulls live data from the provider.
    ///
    /// - `providerSlug`: canonical slug returned by `getAllProviders`
    ///   (e.g. "samsara", "motive", "geotab"). The server accepts
    ///   back-compat aliases ("keeptruckin", "omnitracs", "peoplenet",
    ///   "verizonconnect") and normalises them.
    /// - `apiKey`: bearer token / API key supplied by the fleet admin in
    ///   their ELD provider dashboard. Never cached on-device.
    /// - `authType`: "bearer" by default — matches every provider in the
    ///   current registry. OAuth providers, when added server-side, will
    ///   hand back a `publicAuthorizationURL` via a separate endpoint.
    @discardableResult
    func connectProvider(
        providerSlug: String,
        apiKey: String,
        authType: String = "bearer"
    ) async throws -> ELDConnectResult {
        struct Input: Encodable {
            let providerSlug: String
            let apiKey: String
            let authType: String
        }
        return try await api.mutation(
            "eld.connectProvider",
            input: Input(
                providerSlug: providerSlug,
                apiKey: apiKey,
                authType: authType
            )
        )
    }

    /// `eld.disconnectProvider` — POST mutation. Flips the row's
    /// `status` to "disconnected" but keeps the record so the history
    /// (first connected at, last sync, error count) survives for audit.
    @discardableResult
    func disconnectProvider(providerSlug: String) async throws -> ELDDisconnectResult {
        struct Input: Encodable { let providerSlug: String }
        return try await api.mutation(
            "eld.disconnectProvider",
            input: Input(providerSlug: providerSlug)
        )
    }
}

// MARK: - ELD DTOs
//
// Wire shapes match the server zod outputs exactly. Optional fields are
// the ones the backend sometimes omits when a feature hasn't been enabled
// yet (e.g. `satisfaction` may be null for a newly-onboarded provider).

/// One row of `eld.getAllProviders` — what the iOS picker renders per tile.
struct ELDProvider: Decodable, Identifiable, Equatable, Hashable {
    var id: String { slug }
    /// Display name e.g. "Samsara", "Verizon Connect", "Trimble / PeopleNet".
    let name: String
    /// Canonical slug used in every other ELD mutation. Source-of-truth key.
    let slug: String
    /// Driver satisfaction score (0–100) sourced from the registry. Used
    /// to sort/label the provider grid; higher is better.
    let satisfaction: Int?
    /// Brand hex color (e.g. "#1A73E8" for Samsara). Used for the tile
    /// accent bar and the Connected pill.
    let logoColor: String?
    /// Feature tags ["GPS", "HOS", "DVIR", "IFTA", "Dashcam", ...] — shown
    /// as small chips under the name so the driver knows what will flow
    /// through once connected.
    let features: [String]?
}

/// `eld.getConnectionStatus` envelope. `providers` is the list of
/// currently-connected provider slugs (typically 0 or 1 for a single-fleet
/// account; larger for mixed fleets running dual ELDs during migration).
struct ELDConnectionStatus: Decodable, Equatable {
    let connected: Bool
    /// Slugs currently in `connected` status for this company.
    let providers: [String]
    /// Primary provider — matches `providers.first` when connected, or
    /// "none" when disconnected. Used by the MeEldView footer pill.
    let provider: String
}

/// `eld.getProviderConfig` output. Currently Samsara-centric (per router
/// comment) but the shape accommodates additional providers — the backend
/// will fill in per-provider feature flags as we ship them.
struct ELDProviderConfig: Decodable {
    let provider: String
    let configured: Bool
    let connected: Bool
    let apiBase: String?
    let envVar: String?
    let features: Features?
    let hosLimits: HOSLimits?
    let regulation: String?
    let setupInstructions: String?

    struct Features: Decodable {
        let realTimeHOS: Bool?
        let dailyLogs: Bool?
        let violations: Bool?
        let vehicleLocation: Bool?
        let dvirIntegration: Bool?
        let fuelUsage: Bool?
    }

    /// Canonical 49 CFR 395 constants from the server. Copied here so the
    /// iOS compliance card can render them verbatim and stay authoritative
    /// regardless of future rulemaking changes (FMCSA adjustments flow in
    /// automatically via the server).
    struct HOSLimits: Decodable {
        let maxDrivingMinutes: Int
        let maxOnDutyMinutes: Int
        let breakRequiredAfterMinutes: Int
        let cycle7DayMinutes: Int
        let cycle8DayMinutes: Int
        let minBreakMinutes: Int
        let minOffDutyMinutes: Int
    }
}

struct ELDConnectResult: Decodable {
    let success: Bool
    let providerSlug: String
}

struct ELDDisconnectResult: Decodable {
    let success: Bool?
    let providerSlug: String?
}

// ============================================================================
// MARK: - Driver-facing router clients (wallet extras / factoring / tax /
//         fuelCard / rewards / achievements / leaderboard / fleet / profile /
//         availability / rooms / loyalty / zeun driver read surface)
//
// Each of these mirrors a file under `server/routers/*.ts` in the backend
// repo (`/Users/diegousoro/Downloads/eusotrip-frontend/`). The backend
// procedures currently return empty-shape mocks; the Swift DTOs below
// decode exactly that shape so the iOS app can bind through
// `@StateObject` stores today and pick up real data the moment the
// backend body swaps in a DB query.
// ============================================================================

// MARK: - walletExtrasRouter (wallet.getTransactions, …)

struct WalletExtrasAPI {
    unowned let api: EusoTripAPI

    // MARK: Transactions (canonical `wallet.getTransactions`)
    //
    // Verified against `frontend/server/routers/wallet.ts:371` (L371 getTransactions).
    // Input: { type?, status?, startDate?, endDate?, limit=20, offset=0 }
    // Output: BARE ARRAY of rows:
    //   { id: "txn_N", type, amount, currency, status, description,
    //     loadNumber?, date, completedAt? }
    //
    // We project the wire row into `WalletTxn` so the UI layer stays
    // unchanged: the `kind` field maps from `type`, the display `title`
    // maps from `description` (falls back to type), subtitle maps from
    // the date string, timestamp preserves `completedAt ?? date`.

    struct TxnWireRow: Decodable {
        let id: String
        let type: String
        let amount: Double
        let currency: String?
        let status: String?
        let description: String?
        let loadNumber: String?
        let date: String?
        let completedAt: String?
    }

    struct TransactionsResponse: Decodable {
        let items: [WalletTxn]
        let nextCursor: String?

        init(from decoder: Decoder) throws {
            // Canonical shape is a bare array. Single-value container.
            let c = try decoder.singleValueContainer()
            let rows = try c.decode([TxnWireRow].self)
            self.items = rows.map { r in
                WalletTxn(
                    id: r.id,
                    kind: Self.kindFor(type: r.type),
                    title: (r.description?.isEmpty == false) ? r.description! : Self.titleFor(type: r.type),
                    subtitle: r.loadNumber.map { "Load \($0)" } ?? r.date,
                    amount: r.amount,
                    currency: r.currency,
                    timestamp: r.completedAt ?? r.date,
                    loadId: nil,
                    iconHint: nil
                )
            }
            self.nextCursor = nil
        }

        private static func kindFor(type: String) -> String {
            switch type.lowercased() {
            case "earnings":    return "load_payout"
            case "payout":      return "instant_payout"
            case "fee":         return "fee"
            case "refund":      return "refund"
            case "bonus":       return "bonus"
            case "adjustment":  return "adjustment"
            case "transfer":    return "transfer"
            case "deposit":     return "deposit"
            default:            return type.lowercased()
            }
        }

        private static func titleFor(type: String) -> String {
            switch type.lowercased() {
            case "earnings":   return "Load payout"
            case "payout":     return "Payout"
            case "fee":        return "Platform fee"
            case "refund":     return "Refund"
            case "bonus":      return "Bonus"
            case "adjustment": return "Adjustment"
            case "transfer":   return "Transfer"
            case "deposit":    return "Deposit"
            default:           return type.capitalized
            }
        }
    }

    struct GetTransactionsInput: Encodable {
        let limit: Int
        let offset: Int
    }

    /// `wallet.getTransactions` — paginated via offset. Returns a bare array;
    /// the Decodable in `TransactionsResponse` wraps it.
    /// The `filter` / `cursor` params on the iOS side are tolerated for
    /// call-site compatibility but ignored: the canonical router doesn't
    /// expose a client-facing cursor — offset-based only.
    func getTransactions(
        filter: String? = nil,
        cursor: String? = nil,
        limit: Int = 20
    ) async throws -> TransactionsResponse {
        let offset = Int(cursor ?? "0") ?? 0
        return try await api.query(
            "wallet.getTransactions",
            input: GetTransactionsInput(limit: limit, offset: offset)
        )
    }

    // MARK: Payout methods (canonical `wallet.getPayoutMethods`)
    //
    // Verified against `frontend/server/routers/wallet.ts:421`.
    // Output: bare array of:
    //   { id: "pm_N", type, name, bankName?, brand?, last4, isDefault,
    //     instantPayoutEligible, createdAt }

    struct PayoutMethodWireRow: Decodable {
        let id: String
        let type: String
        let name: String?
        let bankName: String?
        let brand: String?
        let last4: String
        let isDefault: Bool?
        let instantPayoutEligible: Bool?
        let createdAt: String?
    }

    struct PaymentMethodsResponse: Decodable {
        let items: [WalletPaymentMethod]

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            let rows = try c.decode([PayoutMethodWireRow].self)
            self.items = rows.map { r in
                WalletPaymentMethod(
                    id: r.id,
                    kind: r.type == "bank_account" ? "bank" : "debit",
                    institution: r.bankName ?? r.brand ?? r.name ?? "Account",
                    mask: r.last4,
                    isDefault: r.isDefault ?? false,
                    isInstant: r.instantPayoutEligible ?? false,
                    addedAt: r.createdAt
                )
            }
        }
    }

    /// `wallet.getPayoutMethods` — canonical name on backend. The older
    /// iOS spec called this `wallet.listPaymentMethods`; we renamed the
    /// call to match the server and kept the Swift API method name so
    /// call sites stay identical.
    func listPaymentMethods() async throws -> PaymentMethodsResponse {
        try await api.queryNoInput("wallet.getPayoutMethods")
    }

    // MARK: Earnings summary (canonical `earnings.getSummary` + YTD)
    //
    // Backend doesn't expose a single `wallet.getEarningsSummary` — the
    // matching driver data is spread across `earnings.getSummary(period)`
    // (weekly gross, pending, loads) and `earnings.getYTDSummary` (year-
    // to-date gross). We aggregate both and project into
    // `WalletEarningsSummary` so the UI layer stays unchanged.

    struct EarningsSummaryWire: Decodable {
        let totalEarnings: Double?
        let loadsCompleted: Int?
        let paid: Double?
        let pending: Double?
        let avgPerMile: Double?
    }

    struct EarningsYTDWire: Decodable {
        let totalEarnings: Double?
        let projectedAnnual: Double?
    }

    struct EarningsSummaryInput: Encodable { let period: String }

    func getEarningsSummary() async throws -> WalletEarningsSummary {
        async let weekly: EarningsSummaryWire = api.query(
            "earnings.getSummary",
            input: EarningsSummaryInput(period: "week")
        )
        async let monthly: EarningsSummaryWire = api.query(
            "earnings.getSummary",
            input: EarningsSummaryInput(period: "month")
        )
        async let ytd: EarningsYTDWire = api.queryNoInput("earnings.getYTDSummary")

        let (w, m, y) = try await (weekly, monthly, ytd)
        return WalletEarningsSummary(
            thisWeekGross: w.totalEarnings ?? 0,
            thisMonthGross: m.totalEarnings ?? 0,
            ytdGross: y.totalEarnings ?? 0,
            pending: w.pending ?? 0,
            settledLoadsCount: w.loadsCompleted ?? 0,
            avgRatePerMile: w.avgPerMile,
            deadheadPct: nil,
            detentionDollars: nil,
            projectedAnnual: y.projectedAnnual,
            currency: "USD"
        )
    }
}

// MARK: - factoringRouter

struct FactoringAPI {
    unowned let api: EusoTripAPI

    /// Canonical `factoring.getOffer` response.
    /// Backend: `server/routers/factoring.ts` — driver-scoped
    /// procedure, returns a day-bucketed idempotent advance proposal
    /// for the driver's current post-POD load.
    struct Offer: Decodable {
        let offerId: String
        let loadId: Int
        let provider: String
        let grossAmount: Double
        let feeBps: Int
        let feeAmount: Double
        let netAmount: Double
        let currency: String
        let expiresAt: String
        let eligible: Bool
        let reason: String?
    }

    struct GetOfferInput: Encodable { let loadId: Int }

    func getOffer(loadId: Int) async throws -> Offer {
        try await api.query("factoring.getOffer", input: GetOfferInput(loadId: loadId))
    }

    /// Canonical `factoring.accept` response.
    struct AcceptResponse: Decodable {
        let accepted: Bool
        let paymentId: String
        let netAmount: Double
        let transferredAt: String
    }

    struct AcceptInput: Encodable { let loadId: Int; let offerId: String }

    func accept(loadId: Int, offerId: String) async throws -> AcceptResponse {
        try await api.mutation(
            "factoring.accept",
            input: AcceptInput(loadId: loadId, offerId: offerId)
        )
    }
}

// MARK: - taxRouter

struct TaxAPI {
    unowned let api: EusoTripAPI

    struct TaxSummary: Decodable {
        struct Deduction: Decodable, Hashable { let category: String; let amount: Double }
        let year: Int
        let grossEarnings: Double
        let platformFees: Double
        let fuelSpend: Double
        let maintenanceSpend: Double
        let milesDriven: Int
        let deductions: [Deduction]
        let estimatedTaxLiability: Double
        let currency: String
        let updatedAt: String

        // ── EusoWallet §8 driver-surface additions ────────────────
        // `tax.getSummary` now emits these alongside the legacy
        // fields above. They're optional so older server builds
        // still decode cleanly while the new router rolls out.
        let taxYear: Int?
        let ytdGross: Double?
        let estimatedTax: Double?
        let quarterlyEstimate: Double?
        let federalWithheld: Double?
        let stateWithheld: Double?
        let filingThresholdMet: Bool?
        let download1099Available: Bool?
        let download1099URL: String?
    }

    struct YearInput: Encodable { let year: Int }

    /// Driver-facing tax summary. As of the 68th firing this hits the
    /// live `tax.getSummary({ year })` backend procedure (MCP-verified
    /// at `frontend/server/routers/tax.ts:43`). The server aggregates
    /// `payments` rows where the driver is the payee, applies the
    /// server-configured self-employed tax BPS, and surfaces the
    /// quarterly estimate + 1099 availability. Prior implementations
    /// derived the summary client-side from `earnings.getYTDSummary`
    /// with a hardcoded 25.31% tax rate — that derivation has been
    /// removed (the comment claiming `tax.*` didn't exist was stale).
    func getSummary(year: Int) async throws -> TaxSummary {
        try await api.query("tax.getSummary", input: YearInput(year: year))
    }

    /// Driver-scoped summary — no input; uses current calendar year.
    func getDriverSummary() async throws -> TaxSummary {
        let year = Calendar.current.component(.year, from: Date())
        return try await getSummary(year: year)
    }

    struct Tax1099Document: Decodable {
        let year: Int
        let available: Bool
        let documentType: String?    // "1099-NEC" | "1099-K"
        let url: String?
        let issuedAt: String?
        let totalAmount: Double
        let currency: String
        let payerName: String
        let payerTIN: String?
    }

    func get1099(year: Int) async throws -> Tax1099Document {
        try await api.query("tax.get1099", input: YearInput(year: year))
    }
}

// MARK: - fuelCardRouter — removed 65th firing (Phase C landmine sweep).
// Backend router `fuelCardRouter` does not exist. Canonical replacement
// for fuel receipts is `fleet.getFuelTransactionsMobile`. Zero consumers.

// MARK: - rewardsRouter

struct RewardsAPI {
    unowned let api: EusoTripAPI

    struct CatalogResponse: Decodable {
        let items: [RewardItem]
        let pointsBalance: Int
    }

    func getCatalog() async throws -> CatalogResponse {
        try await api.queryNoInput("rewards.getCatalog")
    }

    // Canonical rewards.getHistory returns a BARE ARRAY of badge-earned rows.
    // Web binds to `historyQuery.data?.map`, so the canonical shape IS the
    // wire format. We project it into RewardRedemption-shaped rows on iOS by
    // mapping { id, name, xpEarned, earnedAt, type } → { itemName, pointsSpent,
    // redeemedAt, status, fulfillmentRef } at the call site.
    struct RewardRedemption: Decodable, Identifiable, Hashable {
        let id: String
        let type: String?
        let name: String?
        let category: String?
        let tier: String?
        let xpEarned: Int?
        let earnedAt: String?

        // Compatibility shims for existing UI that reads itemName/pointsSpent/redeemedAt.
        var itemName: String { name ?? "" }
        var pointsSpent: Int { xpEarned ?? 0 }
        var redeemedAt: String { earnedAt ?? "" }
        var status: String { "fulfilled" }
        var fulfillmentRef: String? { nil }
    }

    // getHistory decodes a BARE ARRAY — wrap in a shim struct for the caller.
    struct HistoryResponse: Decodable {
        let items: [RewardRedemption]
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            self.items = try c.decode([RewardRedemption].self)
        }
    }
    struct GetHistoryInput: Encodable { let limit: Int }

    func getHistory(limit: Int = 25) async throws -> HistoryResponse {
        try await api.query("rewards.getHistory", input: GetHistoryInput(limit: limit))
    }

    struct RedeemResponse: Decodable {
        let success: Bool
        let itemId: String
        let newPointsBalance: Int
        let reason: String?
    }

    struct RedeemInput: Encodable { let itemId: String }

    func redeem(itemId: String) async throws -> RedeemResponse {
        try await api.mutation("rewards.redeem", input: RedeemInput(itemId: itemId))
    }
}

// MARK: - achievementsRouter — removed 65th firing (Phase C landmine sweep).
// Canonical replacements on `gamificationRouter`:
//   • achievements.getMissions → gamification.getMissions
//   • achievements.getBadges   → gamification.getBadges
//   • achievements.claim       → gamification.claimMissionReward
// Zero consumers at removal.

// MARK: - gamificationRouter (canonical — `server/routers/gamification.ts`)
//
// 60th firing: stood up to replace the dead `achievements.getMissions`
// endpoint that `AchievementsAPI` was calling. The backend canonical
// procedure lives under `gamification.getMissions` and returns three
// buckets — `active`, `completed`, `available` — each with a richer
// shape than the prior `items: [DriverMission]` projection.
//
// Every field below mirrors `formatMission` in gamification.ts L743 so
// the iOS layer decodes the wire format verbatim. `MissionsStore` +
// the new `TheHaulMissionsStore` map these rows onto the existing
// `DriverMission` struct at the edge so the UI primitives (060 dashboard
// row, 061 dedicated mission card) keep their current bindings.
//
// Per §16 of SKILL.md: every reward emitted here is XP/title only — the
// `loot_crates` / `user_inventory` / `miles_transactions` tables have
// zero writers on the backend today, so the UI must not present a
// "cash added" confirmation. `claimMissionReward` resolves with XP
// credited to the profile; any `rewardType == "cash"` or `"miles"`
// value is treated as display-only until writers ship.

struct GamificationAPI {
    unowned let api: EusoTripAPI

    // MARK: Mission DTO (canonical `formatMission` shape)

    /// One row from any of `active` / `completed` / `available`.
    /// Every optional field on the backend is declared optional here so
    /// the decoder never trips on missing JSON keys (seeded missions vs
    /// template-generated fallbacks emit different sub-sets).
    struct Mission: Decodable, Identifiable, Hashable {
        let id: Int
        let code: String?
        let name: String
        let description: String?
        /// `daily` | `weekly` | `monthly` | `epic` | `seasonal` | `raid` |
        /// `story` | `achievement`
        let type: String?
        /// `deliveries` | `earnings` | `safety` | `efficiency` | `social` |
        /// `special` | `onboarding`
        let category: String?
        let targetType: String?
        let targetValue: Double?
        let targetUnit: String?
        let rewardType: String?
        let rewardValue: Double?
        let xpReward: Int?
        let currentProgress: Double?
        /// `not_started` | `in_progress` | `completed` | `claimed` |
        /// `cancelled` | `expired`
        let status: String?
        let completedAt: String?
        let startsAt: String?
        let endsAt: String?
    }

    /// Canonical response shape — three buckets as the backend returns them.
    struct MissionsResponse: Decodable {
        let active: [Mission]
        let completed: [Mission]
        let available: [Mission]
    }

    struct GetMissionsInput: Encodable {
        let type: String?
        let category: String?
    }

    /// `gamification.getMissions` — query with optional `type` /
    /// `category` filters that mirror the server zod input. Omit both to
    /// ask for every mission the role can run.
    func getMissions(type: String? = nil, category: String? = nil) async throws -> MissionsResponse {
        try await api.query(
            "gamification.getMissions",
            input: GetMissionsInput(type: type, category: category)
        )
    }

    // MARK: Mutations

    struct MissionActionResult: Decodable {
        let success: Bool
        let message: String?
    }

    struct MissionIdInput: Encodable { let missionId: Int }

    /// `gamification.startMission` — drops the driver into `in_progress`
    /// on the requested mission. Fails with `success: false` + a reason
    /// string when the HOS-compliance guard (line 829 of gamification.ts)
    /// rejects driving-category missions.
    func startMission(missionId: Int) async throws -> MissionActionResult {
        try await api.mutation(
            "gamification.startMission",
            input: MissionIdInput(missionId: missionId)
        )
    }

    /// `gamification.claimMissionReward` — moves a `completed` mission to
    /// `claimed` and credits `xpReward` onto the driver's gamification
    /// profile. Returns `success: false` with a message when the mission
    /// has not yet reached 100% progress or was already claimed.
    func claimMissionReward(missionId: Int) async throws -> MissionActionResult {
        try await api.mutation(
            "gamification.claimMissionReward",
            input: MissionIdInput(missionId: missionId)
        )
    }

    // MARK: Profile (used by 060 loyalty hero + future 065 streaks)

    /// Canonical `gamification.getProfile` shape — XP, rank, streaks, stats.
    /// Declared here (not in Models/) because it's scoped to this router.
    struct Profile: Decodable, Hashable {
        let userId: Int
        let name: String?
        let role: String?
        let level: Int?
        let title: String?
        let totalPoints: Int?
        let currentXp: Int?
        let xpToNextLevel: Int?
        let pointsToNextLevel: Int?
        let nextLevelAt: Int?
        let rank: Int?
        let totalUsers: Int?
        let percentile: Double?
        let memberSince: String?
        let currentMiles: Double?
        let totalMilesEarned: Double?
    }

    struct GetProfileInput: Encodable { let userId: String? }

    /// `gamification.getProfile` — omit `userId` to ask for the caller's
    /// own profile.
    func getProfile(userId: String? = nil) async throws -> Profile {
        try await api.query(
            "gamification.getProfile",
            input: GetProfileInput(userId: userId)
        )
    }

    // MARK: - Leaderboard (canonical)
    //
    // `gamification.getLeaderboard` — MCP-verified at
    // frontend/server/routers/gamification.ts:294.
    // Input: { period, category, limit, roleFilter }. Returns
    // { period, category, role, leaders:[...], myRank, totalParticipants }.

    struct LeaderboardLeader: Decodable, Hashable {
        let rank: Int
        let userId: Int
        let name: String
        let role: String
        let level: Int
        let totalXp: Int
        let totalMiles: Double?
        let missionsCompleted: Int?
    }

    struct LeaderboardResponse: Decodable {
        let period: String
        let category: String
        let role: String
        let leaders: [LeaderboardLeader]
        let myRank: Int
        let totalParticipants: Int
    }

    struct GetLeaderboardInput: Encodable {
        let period: String
        let category: String
        let limit: Int
        let roleFilter: String
    }

    func getLeaderboard(
        period: String = "month",
        category: String = "points",
        limit: Int = 20,
        roleFilter: String = "own"
    ) async throws -> [LeaderboardRow] {
        let resp: LeaderboardResponse = try await api.query(
            "gamification.getLeaderboard",
            input: GetLeaderboardInput(period: period, category: category, limit: limit, roleFilter: roleFilter)
        )
        let myUserId = resp.leaders.first(where: { $0.rank == resp.myRank })?.userId ?? -1
        return resp.leaders.map { l in
            LeaderboardRow(
                id: String(l.userId),
                rank: l.rank,
                displayName: l.name,
                avatarUrl: nil,
                score: l.totalXp,
                isCurrentDriver: l.userId == myUserId,
                changeVsLastWeek: nil
            )
        }
    }

    // MARK: - Leaderboard snapshot (canonical, full-envelope)
    //
    // 62nd firing: brick 064 `TheHaulLeaderboard` needs `myRank` and
    // `totalParticipants` to render its self-rank hero + participant
    // denominator, neither of which the row-only `getLeaderboard(...)`
    // projection exposes. This snapshot variant returns the whole
    // response envelope (rows + myRank + totalParticipants + echoed
    // period/category/role) so the dedicated leaderboard surface
    // never has to fabricate a denominator or invent "you're #?".

    struct LeaderboardSnapshot: Hashable {
        let period: String
        let category: String
        let role: String
        let myRank: Int
        let totalParticipants: Int
        let rows: [LeaderboardRow]
    }

    func getLeaderboardSnapshot(
        period: String = "month",
        category: String = "points",
        limit: Int = 20,
        roleFilter: String = "own"
    ) async throws -> LeaderboardSnapshot {
        let resp: LeaderboardResponse = try await api.query(
            "gamification.getLeaderboard",
            input: GetLeaderboardInput(period: period, category: category, limit: limit, roleFilter: roleFilter)
        )
        let myUserId = resp.leaders.first(where: { $0.rank == resp.myRank })?.userId ?? -1
        let rows = resp.leaders.map { l in
            LeaderboardRow(
                id: String(l.userId),
                rank: l.rank,
                displayName: l.name,
                avatarUrl: nil,
                score: l.totalXp,
                isCurrentDriver: l.userId == myUserId,
                changeVsLastWeek: nil
            )
        }
        return LeaderboardSnapshot(
            period: resp.period,
            category: resp.category,
            role: resp.role,
            myRank: resp.myRank,
            totalParticipants: resp.totalParticipants,
            rows: rows
        )
    }

    // MARK: - Rewards catalog (canonical)
    //
    // `gamification.getRewardsCatalog` — MCP-verified at
    // frontend/server/routers/gamification.ts:377. Returns
    // { availablePoints, rewards:[...], categories }.

    struct RewardsCatalogReward: Decodable {
        let id: String
        let name: String
        let cost: Int?
        let category: String?
        let available: Bool?
        let image: String?
        
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try c.decode(String.self, forKey: .id)
            self.name = try c.decode(String.self, forKey: .name)
            // Server sends 'pointsCost' not 'cost'; map it
            self.cost = try c.decodeIfPresent(Int.self, forKey: .cost) 
                     ?? (try c.decodeIfPresent(Int.self, forKey: .pointsCost))
            self.category = try c.decodeIfPresent(String.self, forKey: .category)
            self.available = try c.decodeIfPresent(Bool.self, forKey: .available)
            self.image = try c.decodeIfPresent(String.self, forKey: .image)
        }
        
        enum CodingKeys: String, CodingKey {
            case id, name, category, available, image
            case cost, pointsCost
        }
    }

    struct RewardsCatalogResponse: Decodable {
        let availablePoints: Int
        let rewards: [RewardsCatalogReward]
        let categories: [String]?
    }

    func getRewardsCatalog() async throws -> (availablePoints: Int, rewards: [RewardItem]) {
        let resp: RewardsCatalogResponse = try await api.queryNoInput("gamification.getRewardsCatalog")
        let mapped = resp.rewards.map { r in
            RewardItem(
                id: r.id,
                name: r.name,
                pointsCost: r.cost ?? 0,
                category: r.category,
                imageUrl: r.image,
                inStock: r.available,
                tierRequired: nil
            )
        }
        return (resp.availablePoints, mapped)
    }

    // MARK: - Badges (canonical)
    //
    // `gamification.getBadges` — MCP-verified at
    // frontend/server/routers/gamification.ts:528. Returns an array of
    // badge rows { id, name, description, iconName, earnedAt, tier, ... }.

    struct BadgeWire: Decodable {
        let id: String?
        let name: String?
        let iconName: String?
        let icon: String?
        let description: String?
        let earnedAt: String?
        let tier: String?
        let isDisplay: Bool?
    }

    /// Server envelope as of the 71st firing — `getBadges` returns
    /// `{ displayBadges: [...], allBadges: [...] }`, NOT a bare array.
    /// The earlier comment / previous decoder claimed a bare array
    /// shape and threw `keyNotFound("displayBadges")` on every refresh,
    /// surfacing as the user-reported "badge collection error".
    private struct BadgesEnvelope: Decodable {
        let displayBadges: [BadgeWire]?
        let allBadges: [BadgeWire]?
    }

    func getBadges() async throws -> [DriverBadge] {
        let env: BadgesEnvelope = try await api.queryNoInput("gamification.getBadges")
        // Prefer the full collection so the page can render earned +
        // locked side-by-side; `displayBadges` is the 3-up profile
        // showcase subset and lives behind the `isDisplay` flag.
        let rows = env.allBadges ?? env.displayBadges ?? []
        return rows.map { w in
            DriverBadge(
                id: w.id ?? UUID().uuidString,
                name: w.name ?? "Badge",
                iconName: w.iconName ?? w.icon ?? "rosette",
                earnedAt: w.earnedAt,
                description: w.description,
                tier: w.tier
            )
        }
    }

    // MARK: - Crates (canonical)
    //
    // `gamification.getCrates` — MCP-verified at
    // frontend/server/routers/gamification.ts:1039. Returns bare array
    // of pending crate rows owned by the current user.
    // `gamification.openCrate({ crateId })` — gamification.ts:1066.
    // Mutation rolls contents server-side, updates profile XP/miles,
    // and returns `{ success, contents:[{type,value,name}] }` (or
    // `{ success: false, message }` if the crate is gone/already open).

    struct Crate: Decodable, Identifiable, Hashable {
        let id: Int
        /// `common` | `uncommon` | `rare` | `epic` | `legendary` | `mythic`
        let crateType: String
        /// Origin label (e.g. `mission`, `streak`, `tournament`).
        let source: String?
        let createdAt: String?
        let expiresAt: String?
    }

    func getCrates() async throws -> [Crate] {
        try await api.queryNoInput("gamification.getCrates")
    }

    struct CrateReward: Decodable, Hashable {
        /// `miles` | `xp`
        let type: String
        let value: Double
        let name: String
    }

    struct OpenCrateResponse: Decodable, Equatable {
        let success: Bool
        let message: String?
        let contents: [CrateReward]?
    }

    struct OpenCrateInput: Encodable { let crateId: Int }

    func openCrate(crateId: Int) async throws -> OpenCrateResponse {
        try await api.mutation("gamification.openCrate", input: OpenCrateInput(crateId: crateId))
    }
}

// MARK: - FleetCanonicalAPI (canonical `fleet.*` procedures)
//
// The legacy `FleetAPI` hit iOS-shaped wrappers that don't exist on
// the backend. `FleetCanonicalAPI` binds to the real canonical
// procedures verified via MCP search against frontend/server/routers/fleet.ts.

struct FleetCanonicalAPI {
    unowned let api: EusoTripAPI

    // `fleet.getVehicles` — returns the caller's assigned fleet vehicles.
    // MCP-verified at frontend/server/routers/fleet.ts:117. Server returns
    // a bare array of rows with these minimum fields.
    struct VehicleWire: Decodable {
        let id: Int?
        let unitNumber: String?
        let type: String?
        let make: String?
        let model: String?
        let year: Int?
        let status: String?
        let plate: String?
        let odometer: Int?

        enum CodingKeys: String, CodingKey {
            // Server sends `id` as String, `vin` as the plate field, `mileage` as odometer.
            case id
            case unitNumber
            case type
            case make
            case model
            case year
            case status
            case vin
            case mileage
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            
            // Decode unitNumber, type, make, model, year, status from standard keys
            self.unitNumber = try c.decodeIfPresent(String.self, forKey: .unitNumber)
            self.type = try c.decodeIfPresent(String.self, forKey: .type)
            self.make = try c.decodeIfPresent(String.self, forKey: .make)
            self.model = try c.decodeIfPresent(String.self, forKey: .model)
            self.year = try c.decodeIfPresent(Int.self, forKey: .year)
            self.status = try c.decodeIfPresent(String.self, forKey: .status)
            
            // Server sends `id` as String; convert to Int
            if let idStr = try c.decodeIfPresent(String.self, forKey: .id) {
                self.id = Int(idStr)
            } else if let idInt = try c.decodeIfPresent(Int.self, forKey: .id) {
                self.id = idInt
            } else {
                self.id = nil
            }
            
            // Server sends `vin` in the response; map to `plate`
            self.plate = try c.decodeIfPresent(String.self, forKey: .vin)

            // Server sends `mileage` in the response; map to `odometer`
            self.odometer = try c.decodeIfPresent(Int.self, forKey: .mileage)
        }
    }

    struct GetVehiclesInput: Encodable {
        let status: String?
        let limit: Int?
    }

    func getVehicles(status: String? = nil, limit: Int? = 50) async throws -> [FleetVehicleRow] {
        let rows: [VehicleWire] = try await api.query(
            "fleet.getVehicles",
            input: GetVehiclesInput(status: status, limit: limit)
        )
        return rows.map { w in
            FleetVehicleRow(
                id: String(w.id ?? Int.random(in: 1...Int.max)),
                unitNumber: w.unitNumber ?? "UNIT-\(w.id ?? 0)",
                kind: (w.type ?? "tractor").lowercased(),
                make: w.make,
                model: w.model,
                year: w.year,
                plate: w.plate,
                status: w.status,
                odometer: w.odometer
            )
        }
    }
}

// MARK: - ZeunMechanicsAPI (canonical `zeunMechanics.*`)
//
// MCP-verified at frontend/server/routers/zeunMechanics.ts. Uses the
// live 1900-line router (NOT the stubbed `zeun.*` namespace — see SKILL
// §16 landmines: "zeunRouter is mostly stubs; zeunMechanicsRouter is
// the live surface").

struct ZeunMechanicsAPI {
    unowned let api: EusoTripAPI

    // MARK: - getMyBreakdowns (existing)

    struct GetMyBreakdownsInput: Encodable {
        let limit: Int
        let offset: Int
        let status: String
    }

    func getMyBreakdowns(
        limit: Int = 20,
        offset: Int = 0,
        status: String = "ALL"
    ) async throws -> [ZeunBreakdownRow] {
        try await api.query(
            "zeunMechanics.getMyBreakdowns",
            input: GetMyBreakdownsInput(limit: limit, offset: offset, status: status)
        )
    }

    // MARK: - reportBreakdown
    //
    // Mirrors the server's `reportBreakdown` mutation. Optional fields
    // are kept optional on iOS so the form-builder can skip telemetry
    // the driver can't read off the dash (no DEF % on a class-3 truck,
    // no oil PSI without an OBD reader, etc.).

    struct BreakdownProvider: Decodable, Identifiable, Hashable {
        let id: Int
        let name: String?
        let type: String?
        let distance: String?
        let phone: String?
        let rating: Double?
        let available24x7: Bool?
    }

    struct BreakdownDiagnosis: Decodable, Hashable {
        let issue: String?
        let probability: Double?
        let severity: String?
        let description: String?
    }

    struct BreakdownCostRange: Decodable, Hashable {
        let min: Double?
        let max: Double?
    }

    struct ReportBreakdownAck: Decodable {
        let success: Bool
        let reportId: Int
        let processingTimeMs: Int?
        let diagnosis: BreakdownDiagnosis?
        let canDrive: Bool?
        let providers: [BreakdownProvider]
        let estimatedCost: BreakdownCostRange?
        let partsLikelyNeeded: [String]?
        let safetyWarnings: [String]?
        let preventiveTips: [String]?
        let aiModel: String?
    }

    struct ReportBreakdownInput: Encodable {
        let vehicleVin: String?
        let vehicleId: Int?
        let issueCategory: String   // engine | brakes | tires | etc.
        let severity: String        // LOW | MEDIUM | HIGH | CRITICAL
        let symptoms: [String]
        let canDrive: Bool
        let latitude: Double
        let longitude: Double
        let loadId: Int?
        let loadStatus: String?     // EMPTY | LOADED | HAZMAT
        let cargoType: String?
        let isHazmat: Bool?
        let hazmatClass: String?
        let faultCodes: [String]?
        let driverNotes: String?
        let photos: [String]?       // base64 image data URIs
        let videos: [String]?
        let fuelLevelPercent: Double?
        let defLevelPercent: Double?
        let oilPressurePsi: Double?
        let coolantTempF: Double?
        let batteryVoltage: Double?
        let currentOdometer: Int?
    }

    func reportBreakdown(_ input: ReportBreakdownInput) async throws -> ReportBreakdownAck {
        try await api.mutation("zeunMechanics.reportBreakdown", input: input)
    }

    // MARK: - getBreakdownReport (single drill-in)

    struct BreakdownDetail: Decodable {
        struct Diagnostic: Decodable {
            let confidence: Double?
            let primaryDiagnosis: BreakdownDiagnosis?
            let canDrive: Bool?
            let estimatedCost: BreakdownCostRange?
        }
        let id: Int
        let driverId: Int?
        let driverName: String?
        let issueCategory: String?
        let severity: String?
        let status: String?
        let canDrive: Bool?
        let symptoms: [String]?
        let driverNotes: String?
        let createdAt: String?
        let resolvedAt: String?
        let actualCost: Double?
        let selectedProviderId: Int?
        let diagnostic: Diagnostic?
    }

    struct ReportIdInput: Encodable { let reportId: Int }

    func getBreakdownReport(reportId: Int) async throws -> BreakdownDetail? {
        try await api.query(
            "zeunMechanics.getBreakdownReport",
            input: ReportIdInput(reportId: reportId)
        )
    }

    // MARK: - updateBreakdownStatus

    struct UpdateBreakdownInput: Encodable {
        let reportId: Int
        let status: String
        let notes: String?
        let actualCost: Double?
        let selectedProviderId: Int?
    }

    struct OkAck: Decodable { let success: Bool }

    func updateBreakdownStatus(
        reportId: Int,
        status: String,
        notes: String? = nil,
        actualCost: Double? = nil,
        selectedProviderId: Int? = nil
    ) async throws -> OkAck {
        try await api.mutation(
            "zeunMechanics.updateBreakdownStatus",
            input: UpdateBreakdownInput(
                reportId: reportId, status: status, notes: notes,
                actualCost: actualCost, selectedProviderId: selectedProviderId
            )
        )
    }

    // MARK: - findProviders / searchProviders

    struct ProviderRow: Decodable, Identifiable, Hashable {
        let id: Int
        let name: String?
        let type: String?
        let chainName: String?
        let address: String?
        let city: String?
        let state: String?
        let phone: String?
        let distance: Double?
        let rating: Double?
        let reviewCount: Int?
        let available24x7: Bool?
        let hasMobileService: Bool?
        let services: [String]?
        let aiGenerated: Bool?
    }

    struct FindProvidersInput: Encodable {
        let latitude: Double
        let longitude: Double
        let radiusMiles: Double
        let providerType: String?
        let maxResults: Int
    }

    func findProviders(
        latitude: Double,
        longitude: Double,
        radiusMiles: Double = 50,
        providerType: String? = nil,
        maxResults: Int = 10
    ) async throws -> [ProviderRow] {
        try await api.query(
            "zeunMechanics.findProviders",
            input: FindProvidersInput(
                latitude: latitude, longitude: longitude,
                radiusMiles: radiusMiles, providerType: providerType,
                maxResults: maxResults
            )
        )
    }

    struct SearchProvidersInput: Encodable {
        let query: String
        let latitude: Double?
        let longitude: Double?
        let radiusMiles: Double
    }

    func searchProviders(
        query: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        radiusMiles: Double = 50
    ) async throws -> [ProviderRow] {
        try await api.query(
            "zeunMechanics.searchProviders",
            input: SearchProvidersInput(
                query: query, latitude: latitude,
                longitude: longitude, radiusMiles: radiusMiles
            )
        )
    }

    // MARK: - getProvider (full detail + reviews)

    struct ProviderReview: Decodable, Identifiable, Hashable {
        let id: Int
        let rating: Double
        let title: String?
        let reviewText: String?
        let serviceType: String?
        let createdAt: String?
    }

    struct ProviderDetail: Decodable {
        let id: Int
        let name: String?
        let providerType: String?
        let chainName: String?
        let address: String?
        let city: String?
        let state: String?
        let zip: String?
        let phone: String?
        let website: String?
        let email: String?
        let services: [String]?
        let certifications: [String]?
        let oemBrands: [String]?
        let available24x7: Bool?
        let hasMobileService: Bool?
        let acceptsCreditCard: Bool?
        let acceptsFleetAccounts: Bool?
        let rating: Double?
        let reviewCount: Int?
        let zeunRating: String?
        let zeunReviewCount: Int?
        let averageWaitTimeMinutes: Int?
        let jobsCompleted: Int?
        let reviews: [ProviderReview]
    }

    struct ProviderIdInput: Encodable { let providerId: Int }

    func getProvider(providerId: Int) async throws -> ProviderDetail? {
        try await api.query(
            "zeunMechanics.getProvider",
            input: ProviderIdInput(providerId: providerId)
        )
    }

    // MARK: - submitProviderReview

    struct SubmitReviewInput: Encodable {
        let providerId: Int
        let breakdownReportId: Int?
        let rating: Int
        let title: String?
        let reviewText: String?
        let serviceType: String?
        let waitTimeMinutes: Int?
        /// "LOWER" | "AS_QUOTED" | "HIGHER"
        let costAccuracy: String?
        let wouldRecommend: Bool
    }

    func submitProviderReview(_ input: SubmitReviewInput) async throws -> OkAck {
        try await api.mutation("zeunMechanics.submitProviderReview", input: input)
    }

    // MARK: - Maintenance

    struct MaintenanceStatusInput: Encodable {
        let vehicleId: Int
        let currentOdometer: Int
    }

    struct ScheduledItem: Decodable, Hashable, Identifiable {
        var id: String { "\(serviceType ?? "")-\(dueOdometer ?? 0)" }
        let serviceType: String?
        let dueOdometer: Int?
        let priority: String?
        let milesRemaining: Int?
    }

    struct MaintenanceStatus: Decodable {
        let overdue: [ScheduledItem]
        let dueSoon: [ScheduledItem]
        let upcoming: [ScheduledItem]
    }

    func getMaintenanceStatus(vehicleId: Int, currentOdometer: Int) async throws -> MaintenanceStatus? {
        try await api.query(
            "zeunMechanics.getMaintenanceStatus",
            input: MaintenanceStatusInput(vehicleId: vehicleId, currentOdometer: currentOdometer)
        )
    }

    struct MaintenanceLog: Decodable, Identifiable, Hashable {
        let id: Int
        let serviceType: String?
        let serviceDate: String?
        let odometerAtService: Int?
        let cost: Double?
        let providerName: String?
        let notes: String?
    }

    struct MaintenanceHistoryInput: Encodable {
        let vehicleId: Int
        let limit: Int
    }

    func getMaintenanceHistory(vehicleId: Int, limit: Int = 50) async throws -> [MaintenanceLog] {
        try await api.query(
            "zeunMechanics.getMaintenanceHistory",
            input: MaintenanceHistoryInput(vehicleId: vehicleId, limit: limit)
        )
    }

    struct LogMaintenanceInput: Encodable {
        let vehicleId: Int
        let serviceType: String
        let serviceDate: String
        let odometerAtService: Int
        let cost: Double?
        let providerName: String?
        let providerId: Int?
        let partsReplaced: [String]?
        let laborHours: Double?
        let invoiceUrl: String?
        let notes: String?
    }

    func logMaintenance(_ input: LogMaintenanceInput) async throws -> OkAck {
        try await api.mutation("zeunMechanics.logMaintenance", input: input)
    }

    // MARK: - DTC + Self-repair + Emergency procedures

    struct DTCResult: Decodable {
        let found: Bool
        let code: String?
        let spn: String?
        let fmi: String?
        let description: String?
        let severity: String?
        let category: String?
        let symptoms: [String]?
        let commonCauses: [String]?
        let canDrive: Bool?
        let repairUrgency: String?
        let estimatedCost: BreakdownCostRange?
        let estimatedTimeHours: Double?
        let affectedSystems: [String]?
    }

    struct DTCInput: Encodable { let code: String }

    func lookupDTC(code: String) async throws -> DTCResult {
        try await api.query("zeunMechanics.lookupDTC", input: DTCInput(code: code))
    }

    struct EmergencyContact: Decodable, Hashable, Identifiable {
        var id: String { "\(name ?? "")-\(number ?? "")" }
        let name: String?
        let number: String?
        let priority: String?
    }

    struct EmergencyProcedure: Decodable {
        let title: String
        let severity: String
        let immediateAction: String?
        let steps: [String]
        let emergencyContacts: [EmergencyContact]
        let doNot: [String]?
    }

    /// One of: engine_fire, brake_failure, tire_blowout, rollover,
    /// hazmat_spill, medical_emergency, accident, stolen_vehicle,
    /// weather_severe, breakdown_highway.
    struct EmergencyTypeInput: Encodable { let emergencyType: String }

    func getEmergencyProcedure(type: String) async throws -> EmergencyProcedure {
        try await api.query(
            "zeunMechanics.getEmergencyProcedure",
            input: EmergencyTypeInput(emergencyType: type)
        )
    }

    // MARK: - Recalls

    struct Recall: Decodable, Identifiable, Hashable {
        let id: Int
        let campaignNumber: String?
        let manufacturer: String?
        let component: String?
        let summary: String?
        let consequence: String?
        let remedy: String?
        let recallDate: String?
        let isCompleted: Bool?
    }

    struct VehicleIdInput: Encodable { let vehicleId: Int }

    func checkRecalls(vehicleId: Int) async throws -> [Recall] {
        try await api.query(
            "zeunMechanics.checkRecalls",
            input: VehicleIdInput(vehicleId: vehicleId)
        )
    }
}

// MARK: - leaderboardRouter — removed 65th firing (Phase C landmine sweep).
// Canonical replacement: `gamification.getLeaderboard` (wired via
// `LeaderboardStore` in `ViewModels/LiveDataStores.swift`). Zero consumers.

// MARK: - fleetRouter

struct FleetAPI {
    unowned let api: EusoTripAPI

    struct AssetsResponse: Decodable { let items: [FleetAsset] }

    func listAssets() async throws -> AssetsResponse {
        try await api.queryNoInput("fleet.listAssets")
    }

    struct AssetDetail: Decodable {
        let id: String
        let kind: String
        let unitNumber: String
        let make: String?
        let model: String?
        let year: Int?
        let plate: String?
        let odometerMiles: Int?
        let homeBase: String?
        let status: String?
        let vin: String?
        let lastInspectionDate: String?
        let nextInspectionDue: String?
    }

    struct GetAssetInput: Encodable { let id: String }

    func getAsset(id: String) async throws -> AssetDetail {
        try await api.query("fleet.getAsset", input: GetAssetInput(id: id))
    }

    struct MaintenanceItem: Decodable, Identifiable, Hashable {
        let id: String
        let assetId: String
        let taskName: String
        let dueDate: String?
        let dueMiles: Int?
        let severity: String
        let lastCompletedAt: String?
        let notes: String?
    }

    struct MaintenanceResponse: Decodable { let items: [MaintenanceItem] }
    struct GetMaintenanceInput: Encodable { let assetId: String? }

    // NOTE: canonical `fleet.getMaintenanceSchedule` returns a bare array with
    // different field names (used by the web Fleet Maintenance page). iOS now
    // calls the iOS-shaped wrapper `fleet.getMaintenanceScheduleMobile`, which
    // returns { items: [MaintenanceItem] } with the fields iOS decodes.
    func getMaintenanceSchedule(assetId: String? = nil) async throws -> MaintenanceResponse {
        try await api.query(
            "fleet.getMaintenanceScheduleMobile",
            input: GetMaintenanceInput(assetId: assetId)
        )
    }

    struct FuelTxn: Decodable, Identifiable, Hashable {
        let id: String
        let assetId: String?
        let stationName: String
        let city: String
        let state: String
        let timestamp: String
        let gallons: Double
        let pricePerGallon: Double
        let total: Double
        let odometer: Int?
        let currency: String
    }

    struct FuelTxnsResponse: Decodable { let items: [FuelTxn] }
    struct GetFuelTxnsInput: Encodable { let assetId: String?; let limit: Int }

    // NOTE: canonical `fleet.getFuelTransactions` returns a bare array with
    // different field names (vehicleId/date/location/totalCost) used by the
    // web Fleet Fuel page. iOS calls the iOS-shaped wrapper
    // `fleet.getFuelTransactionsMobile`, which returns { items: [FuelTxn] }
    // with stationName/city/state/timestamp/total/currency/odometer.
    func getFuelTransactions(
        assetId: String? = nil,
        limit: Int = 50
    ) async throws -> FuelTxnsResponse {
        try await api.query(
            "fleet.getFuelTransactionsMobile",
            input: GetFuelTxnsInput(assetId: assetId, limit: limit)
        )
    }
}

// MARK: - profileRouter

struct ProfileAPI {
    unowned let api: EusoTripAPI

    struct ReferralsResponse: Decodable {
        let items: [DriverReferral]
        let totalEarned: Double
        let currency: String
    }

    func listReferrals() async throws -> ReferralsResponse {
        try await api.queryNoInput("profile.listReferrals")
    }

    struct ReferralCode: Decodable {
        let code: String
        let bonusAmount: Double
        let bonusTerms: String
        let currency: String
        let shareUrl: String?
    }

    func getReferralCode() async throws -> ReferralCode {
        try await api.queryNoInput("profile.getReferralCode")
    }

    struct Reputation: Decodable {
        let overallScore: Double
        let onTimePickupPct: Double
        let onTimeDeliveryPct: Double
        let safetyScore: Double
        let cancellationRate: Double
        let ratingAverage: Double
        let ratingCount: Int
        let lastUpdatedAt: String
    }

    func getReputation() async throws -> Reputation {
        try await api.queryNoInput("profile.getReputation")
    }
}

// MARK: - availabilityRouter — removed 65th firing (Phase C landmine sweep).
// No backend router and no canonical replacement yet. Driver availability
// grid in `MeAvailabilityView` remains Cohort A until the backend ships.
// Zero consumers at removal.

// MARK: - roomsRouter — removed 65th firing (Phase C landmine sweep).
// No backend router; nearest surface is `messaging.*` (no presence counts).
// Zero consumers at removal.

// MARK: - loyaltyRouter — removed 65th firing (Phase C landmine sweep).
// Canonical replacement: `gamification.getProfile` (wired via
// `LoyaltyHeroStore` in `ViewModels/LiveDataStores.swift`). Zero consumers.

// MARK: - zeun driver router — removed 65th firing (Phase C landmine sweep).
// Canonical replacement: `ZeunMechanicsAPI.getMyBreakdowns` (wired via
// `ZeunBreakdownsStore`). Procedure `zeun.getDiagnostics` never existed —
// real name is `zeun.getDiagnosticCodes`. Zero consumers at removal.

// MARK: - earningsRouter (canonical — `server/routers/earnings.ts`)
//
// Weekly settlement history lives on `earnings.getWeeklySummaries({ weeks })`
// — a bare array of per-week gross + miles + loads rows. The iOS
// EusoWallet weekly-chart section reads from here, which is the only
// place the backend exposes a weekly time series today (wallet.ts has
// no `getWeeklyHistory` procedure — verified via MCP search_code).
//
// We also expose `getSummary(period)` and `getYTDSummary` so the
// EarningsStore can aggregate the hero-card side tiles without adding
// a dedicated router.
//

struct EarningsAPI {
    unowned let api: EusoTripAPI

    /// Weekly summary row returned by `earnings.getWeeklySummaries`.
    /// `totalEarnings` is the gross the driver was paid that week; the
    /// chart treats this as the bar height. `totalLoads` and
    /// `totalMiles` are surfaced for tooltips/secondary labels.
    struct WeeklySummary: Decodable, Identifiable, Hashable {
        let weekStart: String
        let weekEnd: String
        let totalLoads: Int
        let totalMiles: Double
        let totalEarnings: Double
        let avgPerMile: Double
        let avgPerLoad: Double
        var id: String { weekStart }
    }

    struct GetWeeklySummariesInput: Encodable { let weeks: Int }

    /// `earnings.getWeeklySummaries({ weeks })` — bare array. The server
    /// returns `weeks` rows ordered most-recent first (index 0 == this
    /// week). iOS reverses into chronological order at the render layer.
    func getWeeklySummaries(weeks: Int = 7) async throws -> [WeeklySummary] {
        try await api.query(
            "earnings.getWeeklySummaries",
            input: GetWeeklySummariesInput(weeks: weeks)
        )
    }

    // MARK: - Brick 068 · Me · Earnings additions
    //
    // Typed access to `earnings.getSummary({ period })`, `earnings.getYTDSummary`
    // and a derived `getTopLoads` built from `earnings.getEarnings` (there is
    // no dedicated `earnings.getTopLoads` procedure — verified via MCP
    // search_code against frontend/server/routers/earnings.ts).

    /// Wire shape of `earnings.getSummary` — superset of all fields the
    /// server currently emits so future evolution decodes cleanly.
    struct PeriodSummary: Decodable, Hashable {
        let period: String
        let totalEarnings: Double
        let totalLoads: Int
        let totalMiles: Double
        let avgPerMile: Double
        let avgPerLoad: Double
        let pendingAmount: Double?
        let approvedAmount: Double?
        let paidAmount: Double?
        let bonuses: Double?
        let change: Double?

        struct Comparison: Decodable, Hashable {
            let previousPeriod: Double
            let percentChange: Double
            let trend: String
        }
        let comparison: Comparison?
    }

    struct GetSummaryInput: Encodable { let period: String }

    /// `earnings.getSummary({ period })` — week | month | quarter | year.
    /// The server rejects any other enum value; `ytd` is computed from
    /// `getYTDSummary` on iOS rather than dispatched to this procedure.
    func getSummary(period: String) async throws -> PeriodSummary {
        try await api.query(
            "earnings.getSummary",
            input: GetSummaryInput(period: period)
        )
    }

    /// Wire shape of `earnings.getYTDSummary`. `monthlyBreakdown` is
    /// declared on the server but always emitted empty today; iOS keeps
    /// it optional so future population decodes transparently.
    struct YTDSummaryWire: Decodable, Hashable {
        let year: Int
        let totalEarnings: Double
        let totalLoads: Int
        let totalMiles: Double
        let avgPerMile: Double
        let avgPerLoad: Double
        let projectedAnnual: Double
    }

    func getYTDSummary() async throws -> YTDSummaryWire {
        try await api.queryNoInput("earnings.getYTDSummary")
    }

    /// Row shape returned by `earnings.getEarnings` — per-load completed
    /// row. Brick 068's "TOP LOADS THIS PERIOD" section sorts these by
    /// `totalPay` descending and takes the top N.
    struct EarningsLoadRow: Decodable, Identifiable, Hashable {
        let id: String
        let loadNumber: String?
        let date: String
        let origin: String
        let destination: String
        let miles: Double
        let pay: Double?
        let totalPay: Double
        let hazmatPremium: Double?
        let fuelBonus: Double?
        let status: String
    }

    struct GetEarningsInput: Encodable {
        let period: String?
        let offset: Int
        let limit: Int
    }

    /// `earnings.getEarnings({ period, offset, limit })` — list of
    /// completed-load rows. Caller sorts + truncates for the "top loads"
    /// section on brick 068.
    func getEarnings(period: String, limit: Int = 50) async throws -> [EarningsLoadRow] {
        try await api.query(
            "earnings.getEarnings",
            input: GetEarningsInput(period: period, offset: 0, limit: limit)
        )
    }

    // ── §42 · earnings.previewSettlement — real per-load driver settlement ──
    /// Wire shape of `earnings.previewSettlement({ loadId })` — the REAL
    /// per-load driver settlement breakdown. Every monetary field is an
    /// optional `Double` because the server returns `null` (not a fabricated
    /// number) when the underlying settlement / settlement-document row does
    /// not yet exist. `hasSettlement` is the honest gate: false ⇒ no real
    /// settlement persisted yet, and the caller should keep its frame
    /// references for display rather than show zeros.
    struct SettlementPreview: Decodable, Hashable {
        let loadId: Int
        let loadNumber: String
        let lane: String
        let currency: String          // "USD" | "CAD" | "MXN" — tri-country honest
        let cargoType: String
        let hasSettlement: Bool
        let settlementId: String?
        let documentId: String?
        let settlementStatus: String  // pending | processing | completed | failed | disputed | none
        let documentStatus: String    // DRAFT | FINALIZED | PAID | none
        let settledAt: String?        // ISO-8601
        let linehaul: Double?
        let hazmatSurcharge: Double?
        let detention: Double?
        let accessorialTotal: Double?
        let platformFee: Double?
        let catalystShare: Double?
        let carrierPayment: Double?
        let grossPay: Double?
        let driverNet: Double?
        let deductions: [String: Double]?
    }

    struct PreviewSettlementInput: Encodable { let loadId: Int }

    /// `earnings.previewSettlement({ loadId })` — driver-facing settlement
    /// preview for a single closed load. Throws on NOT_FOUND / FORBIDDEN /
    /// DB-unavailable so the caller surfaces the failure honestly.
    func previewSettlement(loadId: Int) async throws -> SettlementPreview {
        try await api.query(
            "earnings.previewSettlement",
            input: PreviewSettlementInput(loadId: loadId)
        )
    }
}

// MARK: - settlementBatchingRouter (canonical — `server/routers/settlementBatching.ts`)
//
// EusoWallet's "upcoming settlements" section reads from
// `settlementBatching.getDriverBatchView({ driverId })`. Input is the
// driver user id; response is `{ batches: [BatchRow] }` where each row
// carries `batchId`, `batchNumber`, `periodStart`, `periodEnd`,
// `totalAmount`, `status`, and `paidAt`. Statuses observed in the
// source: `draft | pending_approval | approved | processing | paid |
// failed | disputed` — we surface non-`paid` rows as "upcoming" on
// the driver wallet pane.
//

struct SettlementBatchingAPI {
    unowned let api: EusoTripAPI

    struct DriverBatchRow: Decodable, Identifiable, Hashable {
        let batchId: Int
        let batchNumber: String
        let periodStart: String?
        let periodEnd: String?
        let totalAmount: String            // server returns DECIMAL-string
        let status: String
        let paidAt: String?
        var id: Int { batchId }
    }

    struct DriverBatchViewResponse: Decodable {
        let batches: [DriverBatchRow]
    }

    struct GetDriverBatchViewInput: Encodable { let driverId: Int }

    /// Server requires a driver id. iOS passes the currently-authenticated
    /// user id; when unknown we pass 0 and the server returns `{ batches: [] }`.
    func getDriverBatchView(driverId: Int) async throws -> DriverBatchViewResponse {
        try await api.query(
            "settlementBatching.getDriverBatchView",
            input: GetDriverBatchViewInput(driverId: driverId)
        )
    }
}

// MARK: - advancedGamificationRouter (canonical — `server/routers/advancedGamification.ts`)
//
// Streaks, multipliers, daily-bonus XP, and the 7-day history rail
// drive brick 065 The Haul · Streaks. The server reads
// `gamificationProfiles.streakDays` / `longestStreak` /
// `lastActivityAt`, derives the multiplier tier, and synthesises the
// 7-day history. The iOS layer renders exactly what comes back —
// no local multiplier math, no fabricated streak count.
//
// Added in the 65th firing. MCP-verified at
// frontend/server/routers/advancedGamification.ts:1476 (procedure
// body) and routers.ts:1568 (router mount point).
//

struct AdvancedGamificationAPI {
    unowned let api: EusoTripAPI

    /// A single entry in the 7-day streak history rail. Returned by
    /// the server as `{ date, completed }` — `date` is an ISO
    /// yyyy-MM-dd string, `completed` indicates whether that day
    /// counted toward the current streak window.
    struct StreakDay: Decodable, Hashable, Identifiable {
        let date: String
        let completed: Bool
        var id: String { date }
    }

    /// Full response envelope for `advancedGamification.getStreakTracker`.
    /// Every field lands server-side; the iOS layer never synthesises.
    struct StreakTracker: Decodable, Hashable {
        let dailyStreak: Int
        let weeklyStreak: Int
        let bestDailyStreak: Int
        let bestWeeklyStreak: Int
        let currentMultiplier: Double
        let nextMultiplierAt: Int
        let nextMultiplierValue: Double
        let streakHistory: [StreakDay]
        let dailyBonusXp: Int
    }

    /// Fetch the canonical streak tracker for the authenticated driver.
    /// Returns a fully-populated envelope even when the driver has no
    /// active streak (dailyStreak == 0, streakHistory == 7 false days,
    /// currentMultiplier == 1.0). The empty-streak hero in 065 keys off
    /// `dailyStreak == 0 && bestDailyStreak == 0`, not off missing data.
    func getStreakTracker() async throws -> StreakTracker {
        try await api.queryNoInput("advancedGamification.getStreakTracker")
    }

    // MARK: - Cosmetics (canonical)
    //
    // `advancedGamification.getCustomizationOptions` — MCP-verified at
    // frontend/server/routers/advancedGamification.ts:1786. Returns
    // `{ avatars, frames, titles }` sliced from the server-side
    // `CUSTOMIZATION_OPTIONS` catalog (static game-design config —
    // same catalog for every driver, with `owned: true` on the starter
    // set + `owned: false` on items gated by cost / prestige).
    //
    // `advancedGamification.equipCustomization({ type, itemId })` —
    // advancedGamification.ts:1794. Mutation. Server validates
    // `item.owned == true`; returns BAD_REQUEST if not. For
    // `type: "title"` the server writes
    // `gamificationProfiles.activeTitle`. For `type: "avatar"` and
    // `type: "frame"` the mutation resolves with `success: true` but
    // does NOT persist — this is a known backend partial-implementation
    // (the `getDriverProfile.customization` response is hardcoded to
    // av1/fr1/ti1). 066 Cosmetics discloses this limitation in-copy
    // rather than hiding it behind a stub banner.

    /// Single catalog row as returned by `getCustomizationOptions`.
    /// `owned` = "available to every driver out of the box" (starter
    /// set). `equipped` = "default equipped for every driver" (one per
    /// type). These are game-design config flags, not per-user state.
    struct CustomizationOption: Decodable, Identifiable, Hashable {
        let id: String
        /// `avatar` | `frame` | `title`
        let type: String
        let name: String
        /// Optional image URL (titles are `null`).
        let image: String?
        /// Purchase cost in points (0 for starter items).
        let cost: Int
        /// Prestige level required to unlock (0 for starter items).
        let prestigeRequired: Int
        let owned: Bool
        let equipped: Bool
    }

    /// Catalog envelope — three arrays sliced from the shared catalog.
    struct CustomizationCatalog: Decodable, Hashable {
        let avatars: [CustomizationOption]
        let frames: [CustomizationOption]
        let titles: [CustomizationOption]
    }

    func getCustomizationOptions() async throws -> CustomizationCatalog {
        try await api.queryNoInput("advancedGamification.getCustomizationOptions")
    }

    struct EquipCustomizationInput: Encodable {
        /// `avatar` | `frame` | `title`
        let type: String
        let itemId: String
    }

    struct EquipCustomizationResponse: Decodable {
        let success: Bool
        /// Echoed item id on success. Absent on server-thrown errors
        /// (the tRPC error path handles those — see `EusoTripAPIError`).
        let equipped: String?
        let type: String?
    }

    func equipCustomization(type: String, itemId: String) async throws -> EquipCustomizationResponse {
        try await api.mutation(
            "advancedGamification.equipCustomization",
            input: EquipCustomizationInput(type: type, itemId: itemId)
        )
    }
}

// MARK: - DocumentManagementAPI
//
// Driver document surface backing 072 Me · Docs (CDL / Medical / TWIC /
// Hazmat / Registration / Insurance). Mirrors
// `frontend/server/routers/documentManagement.ts` — only the driver-
// relevant read procedures are exposed here; workflow, e-signature, and
// template surfaces live behind the admin-only 200s ladder and are not
// wired on mobile yet.
//
// MCP-verified procedures (tRPC namespace `documentManagement.*`):
//   • getDocuments            — list (paginated, filterable by type)
//   • getDocumentById         — single detail fetch
//   • getExpiringDocuments    — expiration alerts (expiring+expired)
//
// 67th firing (brick port 072).

struct DocumentManagementAPI {
    let api: EusoTripAPI

    // MARK: Decoded shapes

    /// Shape returned by `documentManagement.getDocuments[].map(mapDocRow)`
    /// on the backend. Drops the admin-heavy fields the driver UI never
    /// renders (workflow state, audit trail, retention policy, etc.) —
    /// Swift `Decodable` silently ignores unknown JSON keys, so adding
    /// extra server-side fields later is non-breaking for the app.
    struct Document: Decodable, Identifiable, Equatable {
        let id: String
        let name: String
        /// Backend `documentTypeSchema` enum value — e.g. "medical_card",
        /// "hazmat_placard", "permit", "registration", "insurance",
        /// "operating_authority", "other". See
        /// `documentManagement.ts:51-58` for the full list.
        let type: String
        let status: String
        /// Convenience bucket the backend computes with
        /// `getCategoryForType(type)`. Useful for grouping when the raw
        /// `type` value isn't specific enough (e.g. "other" documents
        /// sort under the "personal" category on the server).
        let category: String?
        let mimeType: String?
        let size: Int?
        /// May be a relative path (`/api/documents/:id/download`) or an
        /// absolute blob URL. Views resolve against `EusoTripAPI.baseURL`
        /// when relative.
        let url: String?
        /// ISO-8601 string. Nil for documents with no expiration.
        let expiresAt: String?
        let uploadedAt: String?
        let updatedAt: String?
    }

    struct GetDocumentsResponse: Decodable {
        let documents: [Document]
        let total: Int
        let page: Int
        let pageSize: Int
        let totalPages: Int
    }

    /// Row shape inside `getExpiringDocuments.expiring[]`.
    struct ExpiringDoc: Decodable, Identifiable, Equatable {
        let id: String
        let name: String
        let type: String
        let expiresAt: String?
        let daysUntilExpiry: Int
        /// Server-computed: "critical" | "high" | "medium" | "low".
        let urgency: String
    }

    /// Row shape inside `getExpiringDocuments.expired[]`.
    struct ExpiredDoc: Decodable, Identifiable, Equatable {
        let id: String
        let name: String
        let type: String
        let expiresAt: String?
        let daysExpired: Int
    }

    struct ExpiringDocumentsResponse: Decodable, Equatable {
        let expiring: [ExpiringDoc]
        let expired: [ExpiredDoc]
        let totalExpiring: Int
        let totalExpired: Int
    }

    // MARK: Input envelopes

    struct GetDocumentsInput: Encodable {
        let page: Int
        let pageSize: Int
        let sortBy: String
        let sortOrder: String
    }

    struct GetExpiringInput: Encodable {
        let daysAhead: Int
        let includeExpired: Bool
    }

    // MARK: Procedures

    /// List driver-scoped documents. The server filters by `userId`
    /// against the session, so no `driverId` parameter is needed —
    /// whichever driver is signed in sees their own docs.
    func getDocuments(page: Int = 1, pageSize: Int = 50) async throws -> GetDocumentsResponse {
        try await api.query(
            "documentManagement.getDocuments",
            input: GetDocumentsInput(
                page: page,
                pageSize: pageSize,
                sortBy: "uploadedAt",
                sortOrder: "desc"
            )
        )
    }

    /// Expiration alerts — expiring within `daysAhead` + already-expired.
    /// Backend default is 30 days; we bump to 90 for the Me · Docs
    /// surface so drivers see renewal warnings a full quarter out for
    /// TWIC (5-year) / CDL (varies) / medical (2-year) certs.
    func getExpiringDocuments(daysAhead: Int = 90, includeExpired: Bool = true) async throws -> ExpiringDocumentsResponse {
        try await api.query(
            "documentManagement.getExpiringDocuments",
            input: GetExpiringInput(daysAhead: daysAhead, includeExpired: includeExpired)
        )
    }

    // MARK: Document mutations (083 Me · Documents Hub)
    //
    // MCP-verified procedures at `frontend/server/routers/documentManagement.ts`:
    //   • uploadDocument      — line 519
    //   • classifyDocument    — line 591  (AI kick; server-side OCR)
    //   • shareDocument       — line 1639
    //   • archiveDocument     — line 1916
    //   • requestESignature   — line 1121

    struct UploadDocumentInput: Encodable {
        let name: String
        let type: String
        let mimeType: String
        let size: Int
        /// Base-64 encoded file body. Server expects this field exactly.
        let fileData: String
        /// "load" | "driver" | "vehicle" | "company" | "carrier" |
        /// "broker" | "shipper". Me·Docs uploads default to "driver".
        let entityType: String
        let entityId: String
        let tags: [String]?
        let expiresAt: String?
    }

    struct UploadDocumentResponse: Decodable, Equatable {
        let id: String
        let name: String
        let type: String
        let status: String
        let uploadedAt: String?
        let message: String?
    }

    /// Upload a document. Driver-scoped by default — passes `driver`
    /// as `entityType` and the driver's user-id as the entity id so
    /// the server rows land under the right owner.
    func uploadDocument(
        name: String,
        type: String,
        mimeType: String,
        size: Int,
        fileData: String,
        entityType: String = "driver",
        entityId: String,
        tags: [String]? = nil,
        expiresAt: String? = nil
    ) async throws -> UploadDocumentResponse {
        try await api.mutation(
            "documentManagement.uploadDocument",
            input: UploadDocumentInput(
                name: name, type: type, mimeType: mimeType,
                size: size, fileData: fileData,
                entityType: entityType, entityId: entityId,
                tags: tags, expiresAt: expiresAt
            )
        )
    }

    struct DocumentIdInput: Encodable {
        let documentId: String
    }

    struct ClassifyDocumentResponse: Decodable, Equatable {
        let success: Bool
        let classification: ClassificationResult?
        let error: String?

        struct ClassificationResult: Decodable, Equatable {
            let type: String?
            let confidence: Double?
        }
    }

    /// Kick AI classification / OCR on the uploaded document. The
    /// server runs this async on its side and persists the result
    /// into `user_documents.ocrExtractedData`; the mobile caller only
    /// needs to know success/failure.
    func classifyDocument(documentId: String) async throws -> ClassifyDocumentResponse {
        try await api.mutation(
            "documentManagement.classifyDocument",
            input: DocumentIdInput(documentId: documentId)
        )
    }

    struct ArchiveDocumentInput: Encodable {
        let documentId: String
        /// "1_year" | "3_years" | "5_years" | "7_years" | "10_years" | "permanent"
        let retentionPolicy: String
        let reason: String?
    }

    struct ArchiveDocumentResponse: Decodable, Equatable {
        let success: Bool
        let documentId: String?
        let archivedAt: String?
        let retentionPolicy: String?
        let message: String?
        let error: String?
    }

    /// Soft-delete a document with a retention policy. The server
    /// stamps `deletedAt` + `status = "expired"`; rows stay in the
    /// audit trail for the chosen retention window.
    func archiveDocument(
        documentId: String,
        retentionPolicy: String = "7_years",
        reason: String? = nil
    ) async throws -> ArchiveDocumentResponse {
        try await api.mutation(
            "documentManagement.archiveDocument",
            input: ArchiveDocumentInput(
                documentId: documentId,
                retentionPolicy: retentionPolicy,
                reason: reason
            )
        )
    }

    struct ShareDocumentInput: Encodable {
        let documentId: String
        let recipientEmail: String
        let recipientName: String?
        let expiresInHours: Int
        /// "view" | "download" | "sign"
        let permissions: String
        let message: String?
    }

    struct ShareDocumentResponse: Decodable, Equatable {
        let success: Bool
        let shareLink: String?
        let shareToken: String?
        let expiresAt: String?
        let permissions: String?
        let recipientEmail: String?
        let message: String?
        let error: String?
    }

    func shareDocument(
        documentId: String,
        recipientEmail: String,
        recipientName: String? = nil,
        expiresInHours: Int = 72,
        permissions: String = "view",
        message: String? = nil
    ) async throws -> ShareDocumentResponse {
        try await api.mutation(
            "documentManagement.shareDocument",
            input: ShareDocumentInput(
                documentId: documentId,
                recipientEmail: recipientEmail,
                recipientName: recipientName,
                expiresInHours: expiresInHours,
                permissions: permissions,
                message: message
            )
        )
    }

    struct ESignSigner: Encodable {
        let name: String
        let email: String
        let order: Int
    }

    struct RequestESignatureInput: Encodable {
        let documentId: String
        let signers: [ESignSigner]
        let message: String
        let expiresInDays: Int
    }

    struct RequestESignatureResponse: Decodable, Equatable {
        let success: Bool
        let requestId: String?
        let expiresAt: String?
        let message: String?
        let error: String?
    }

    /// Fire a DocuSign-equivalent e-signature request. The server
    /// stores the request in `audit_logs` under `doc_signature` and
    /// emails each signer. Response's `requestId` is safe to
    /// round-trip into a Driver → Dispatch chat so both sides can
    /// track signing progress.
    func requestESignature(
        documentId: String,
        signers: [ESignSigner],
        message: String = "Please review and sign this document.",
        expiresInDays: Int = 7
    ) async throws -> RequestESignatureResponse {
        try await api.mutation(
            "documentManagement.requestESignature",
            input: RequestESignatureInput(
                documentId: documentId,
                signers: signers,
                message: message,
                expiresInDays: expiresInDays
            )
        )
    }
}

// MARK: - VehicleAPI
//
// Driver-scoped assigned-vehicle + maintenance history surface backing
// 073 Me · Vehicle. Mirrors `frontend/server/routers/vehicle.ts`.
//
// MCP-verified procedures (tRPC namespace `vehicle.*`):
//   • getAssigned             — the driver's currently assigned truck
//                               (id/unitNumber/year/make/model/vin/
//                               licensePlate/odometer/fuelLevel/status).
//                               Server returns all-zero sentinel fields
//                               (id="" etc.) when no assignment exists —
//                               the store folds that into `.empty`.
//   • getMaintenanceHistory   — maintenance work-order records keyed to
//                               the driver's company. Returns {records:
//                               [{id, description, type, date, status}]}.
//
// 68th firing (brick port 073).

struct VehicleAPI {
    let api: EusoTripAPI

    // MARK: Decoded shapes

    /// Shape returned by `vehicle.getAssigned`. The server always returns
    /// a non-null object; an empty `id` string means "no vehicle assigned
    /// to this driver" (new driver, between assignments, etc.).
    ///
    /// Note on odometer / fuelLevel: the current backend implementation
    /// hardcodes these to 0 because the telematics integration has not
    /// shipped yet (vehicle.ts:138). The view surfaces them only when
    /// non-zero and renders a disclosure footer otherwise. No fake data.
    struct AssignedVehicle: Decodable, Equatable {
        let id: String
        let unitNumber: String
        let year: Int
        let make: String
        let model: String
        let vin: String
        let licensePlate: String
        let odometer: Int
        let fuelLevel: Double
        let status: String

        /// True when the server returned the "no assignment" sentinel.
        var isUnassigned: Bool { id.isEmpty }
    }

    /// Row shape inside `getMaintenanceHistory.records[]`. Derived from
    /// the `documents` table filtered to maintenance-category items, so
    /// `status` tracks the document lifecycle (uploaded / approved /
    /// archived / etc.) rather than a work-order-specific state.
    struct MaintenanceRecord: Decodable, Identifiable, Equatable {
        let id: String
        let description: String
        let type: String
        /// `YYYY-MM-DD` string (server-trimmed ISO date).
        let date: String
        let status: String
    }

    struct MaintenanceResponse: Decodable {
        let records: [MaintenanceRecord]
    }

    struct GetMaintenanceInput: Encodable {
        let vehicleId: String?
        let limit: Int?
    }

    // MARK: Procedures

    /// Fetch the driver's currently assigned vehicle. Server filters by
    /// `ctx.user.id`, so no explicit driver-id parameter is needed.
    func getAssigned() async throws -> AssignedVehicle {
        try await api.queryNoInput("vehicle.getAssigned")
    }

    /// Fetch maintenance-event history. `vehicleId` is optional — when
    /// omitted, the server returns the company's full maintenance feed
    /// (dispatcher view). For the driver's Me · Vehicle surface we pass
    /// the assigned vehicle's id so the list is scoped to their truck.
    func getMaintenanceHistory(vehicleId: String? = nil, limit: Int = 20) async throws -> MaintenanceResponse {
        try await api.query(
            "vehicle.getMaintenanceHistory",
            input: GetMaintenanceInput(vehicleId: vehicleId, limit: limit)
        )
    }
}

// MARK: - SafetyAPI
//
// Driver-facing safety score + contributing-factor breakdown + recent
// event log. Mirrors the driver-relevant procedures of
// `frontend/server/routers/safety.ts`.
//
// MCP-verified procedures (tRPC namespace `safety.*`):
//   • getDriverScoreDetail({ driverId })   — score + categories + events
//   • getDriverScores                      — company leaderboard (admin)
//   • getDriverSafetyStats                 — company aggregates (admin)
//
// 69th firing (brick port 075 Me · Safety Score).

struct SafetyAPI {
    let api: EusoTripAPI

    // MARK: Decoded shapes

    /// One category row in the driver's score detail payload — e.g.
    /// "Driving", "Compliance", "Vehicle Care". Server scores are
    /// 0-100; we decode as `Int` since the backend rounds to whole
    /// numbers.
    struct ScoreCategory: Decodable, Identifiable, Equatable {
        let name: String
        let score: Int
        var id: String { name }
    }

    /// One recent-event row — today typed as "inspection" by the
    /// server (derived from `inspections` rows joined by driver).
    /// Future types ("incident", "near_miss", "training_completed")
    /// will land here too; views should treat `type` as a string
    /// and render a known set of icons / fall back to a neutral
    /// icon for unknown types.
    struct ScoreEvent: Decodable, Identifiable, Equatable {
        let type: String
        let date: String
        let status: String
        var id: String { "\(date)::\(type)::\(status)" }
    }

    /// Response shape from `safety.getDriverScoreDetail`.
    struct DriverScoreDetail: Decodable, Equatable {
        let driverId: String
        let name: String
        /// Aggregate score 0-100 (server caps). `overall` vs.
        /// `overallScore` are duplicates the backend keeps for
        /// historical callers; we read `overallScore` preferentially
        /// and fall back to `overall` on the decoder.
        let overall: Int
        let overallScore: Int
        let licenseNumber: String
        let categories: [ScoreCategory]
        let recentEvents: [ScoreEvent]

        /// Best value for rendering — prefers `overallScore` but
        /// tolerates older payloads.
        var canonicalScore: Int {
            overallScore > 0 ? overallScore : overall
        }
    }

    // MARK: Input envelopes

    struct DriverIdInput: Encodable {
        let driverId: String
    }

    // MARK: Procedures

    /// Fetch the driver's score detail. `driverId` comes from the
    /// signed-in session — callers resolve it off
    /// `EusoTripSession.user?.id` (canonical for every Me· screen).
    func getDriverScoreDetail(driverId: String) async throws -> DriverScoreDetail {
        try await api.query(
            "safety.getDriverScoreDetail",
            input: DriverIdInput(driverId: driverId)
        )
    }

    // MARK: Incident filing (086 Me · Incident Report Filer)
    //
    // Drivers file one of three incident kinds from the field:
    //   1. Accident / crash  → `safety.submitAccidentReport`
    //   2. Near-miss         → `safetyRisk.reportNearMiss`
    //   3. Property damage   → `safety.submitAccidentReport` with
    //                          severity="minor" and type hint in
    //                          the description.
    //
    // Both procs MCP-verified at
    // `frontend/server/routers/safety.ts:700` and
    // `frontend/server/routers/safetyRisk.ts:812`.

    struct AccidentReportInput: Encodable {
        let driverId: String?
        let date: String?           // ISO-8601 — when the event occurred
        let description: String?
        /// "critical" | "major" | "minor"
        let severity: String?
    }

    struct AccidentReportResponse: Decodable, Equatable {
        let success: Bool
        let reportId: String?
    }

    /// File a crash / property-damage incident. Server writes
    /// `incidents` row with type=accident, indexes for AI semantic
    /// search, and returns the new report id.
    func submitAccidentReport(
        driverId: String? = nil,
        date: String? = nil,
        description: String,
        severity: String = "minor"
    ) async throws -> AccidentReportResponse {
        try await api.mutation(
            "safety.submitAccidentReport",
            input: AccidentReportInput(
                driverId: driverId,
                date: date,
                description: description,
                severity: severity
            )
        )
    }

    struct NearMissReportInput: Encodable {
        /// "lane_departure" | "hard_brake" | "close_call" |
        /// "distraction" | "fatigue" | "weather_related" |
        /// "equipment_issue" | "pedestrian" | "rollover_risk" | "other"
        let nearMissType: String
        let description: String
        let location: String?
        /// ISO-8601 — required by server schema.
        let occurredAt: String
        /// "critical" | "major" | "minor" (default "minor")
        let severity: String?
        let driverId: Int?
        let weatherConditions: String?
        let roadConditions: String?
        let actionTaken: String?
    }

    struct NearMissReportResponse: Decodable, Equatable {
        let success: Bool
        let reportId: String?
    }

    /// File a near-miss event. Surfaces to the carrier's safety
    /// manager in the same incidents-table queue as crashes, tagged
    /// `type="near_miss"` so analytics can pivot on leading vs
    /// lagging events.
    func reportNearMiss(
        nearMissType: String,
        description: String,
        location: String? = nil,
        occurredAt: String,
        severity: String = "minor",
        driverId: Int? = nil,
        weatherConditions: String? = nil,
        roadConditions: String? = nil,
        actionTaken: String? = nil
    ) async throws -> NearMissReportResponse {
        try await api.mutation(
            "safetyRisk.reportNearMiss",
            input: NearMissReportInput(
                nearMissType: nearMissType,
                description: description,
                location: location,
                occurredAt: occurredAt,
                severity: severity,
                driverId: driverId,
                weatherConditions: weatherConditions,
                roadConditions: roadConditions,
                actionTaken: actionTaken
            )
        )
    }
}

// MARK: - TrainingAPI
//
// Driver-scoped training + certification surface backing 076 Me ·
// Training. Wraps the relevant procedures from two server routers:
//
//   `trainingRouter` (frontend/server/routers/training.ts):
//     • getDriverAssignments({driverId?, status?})
//     • getPendingMandatoryTraining({driverId?})
//     • getProgress({courseId?})
//
//   `trainingLMSRouter` (frontend/server/routers/trainingLMS.ts):
//     • getMyEnrollments({status?})
//     • getMyCertificates
//
// Both namespaces scope to the signed-in user when driverId is
// omitted, so the driver sees only their own records.
//
// 70th firing (brick port 076 Me · Training).

struct TrainingAPI {
    let api: EusoTripAPI

    // MARK: Shapes

    /// Assignment row from `training.getDriverAssignments`.
    struct Assignment: Decodable, Identifiable, Equatable {
        let id: String
        /// "not_started" | "in_progress" | "completed" | "expired"
        let status: String
        let courseName: String
        let courseId: String?
        /// 0-100.
        let progress: Int
        /// ISO-8601. May be nil for assignments without a hard deadline.
        let dueDate: String?
        let assignedAt: String?
        let completedAt: String?
        let score: Int?
        /// Server label — "safety" / "hazmat" / "compliance" / etc.
        let category: String?

        private enum CodingKeys: String, CodingKey {
            case id, status, progress, completedAt, score, category
            case courseName, courseId, dueDate, assignedAt
            // Server field names that need mapping
            case moduleId, startedAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try c.decode(String.self, forKey: .id)
            self.status = try c.decode(String.self, forKey: .status)
            self.progress = try c.decode(Int.self, forKey: .progress)
            self.completedAt = try c.decodeIfPresent(String.self, forKey: .completedAt)
            self.score = try c.decodeIfPresent(Int.self, forKey: .score)
            self.category = try c.decodeIfPresent(String.self, forKey: .category)
            // courseName: server omits it, so provide empty default
            self.courseName = try c.decodeIfPresent(String.self, forKey: .courseName) ?? ""
            // dueDate: server omits it
            self.dueDate = try c.decodeIfPresent(String.self, forKey: .dueDate)
            // courseId: server sends moduleId instead
            self.courseId = try c.decodeIfPresent(String.self, forKey: .courseId) ?? (try c.decodeIfPresent(String.self, forKey: .moduleId))
            // assignedAt: server sends startedAt instead
            self.assignedAt = try c.decodeIfPresent(String.self, forKey: .assignedAt) ?? (try c.decodeIfPresent(String.self, forKey: .startedAt))
        }
    }

    struct AssignmentSummary: Decodable, Equatable {
        let total: Int
        let completed: Int
        let inProgress: Int
        let expired: Int
        let notStarted: Int
    }

    struct AssignmentsResponse: Decodable, Equatable {
        let assignments: [Assignment]
        let summary: AssignmentSummary
    }

    /// Certificate row from `trainingLMS.getMyCertificates`.
    struct Certificate: Decodable, Identifiable, Equatable {
        let id: String
        let courseName: String
        let certificateNumber: String
        let issuedAt: String?
        /// ISO-8601. Nil for certificates without expiration (rare).
        let expiresAt: String?
        /// "active" | "expired" | "revoked"
        let status: String
        let verificationCode: String?
    }

    struct CertificatesResponse: Decodable, Equatable {
        let certificates: [Certificate]

        init(from decoder: Decoder) throws {
            // Server returns a bare array: [{ certificate: {...}, courseTitle, courseSlug, courseCategory }, ...]
            // Flatten to Certificate objects.
            let c = try decoder.singleValueContainer()
            let rows = try c.decode([CertificateWireRow].self)
            self.certificates = rows.map { row in
                Certificate(
                    id: String(row.certificate.id),
                    courseName: row.courseTitle,
                    certificateNumber: row.certificate.certificateNumber,
                    issuedAt: row.certificate.issuedAt,
                    expiresAt: row.certificate.expiresAt,
                    status: row.certificate.status,
                    verificationCode: row.certificate.verificationCode
                )
            }
        }

        /// Wire row from the server's select join.
        private struct CertificateWireRow: Decodable {
            let certificate: CertificateDBRow
            let courseTitle: String
            let courseSlug: String
            let courseCategory: String
        }

        /// Represents the flattened user_certificates table row.
        private struct CertificateDBRow: Decodable {
            let id: Int
            let certificateNumber: String
            let issuedAt: String?
            let expiresAt: String?
            let status: String
            let verificationCode: String?
        }
    }

    /// "Pending mandatory" row from `training.getPendingMandatoryTraining`
    /// — overdue + not-started courses the driver must complete to stay
    /// in dispatch rotation.
    struct PendingCourse: Decodable, Identifiable, Equatable {
        let id: String
        let courseName: String
        let dueDate: String?
        let progress: Int
        /// Whether this is past its due date.
        let overdue: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case courseName
            case dueDate
            case progress
            case overdue = "isOverdue"
        }
    }

    struct PendingResponse: Decodable, Equatable {
        let pending: [PendingCourse]
        let overdue: [PendingCourse]
    }

    // MARK: Inputs

    struct AssignmentsInput: Encodable {
        let driverId: String?
        let status: String?
    }

    struct PendingInput: Encodable {
        let driverId: String?
    }

    struct EnrollmentsInput: Encodable {
        let status: String?
    }

    // MARK: Procedures

    /// Driver's assignments (all statuses) with summary counts.
    /// Server defaults to the signed-in user when driverId is nil.
    func getDriverAssignments(driverId: String? = nil, status: String? = nil) async throws -> AssignmentsResponse {
        try await api.query(
            "training.getDriverAssignments",
            input: AssignmentsInput(driverId: driverId, status: status)
        )
    }

    /// Pending + overdue mandatory courses. Drives the red "due now"
    /// strip at the top of the 076 screen.
    func getPendingMandatoryTraining(driverId: String? = nil) async throws -> PendingResponse {
        try await api.query(
            "training.getPendingMandatoryTraining",
            input: PendingInput(driverId: driverId)
        )
    }

    /// Earned certificates with issue + expiry dates. The server
    /// scopes to the signed-in user via ctx.user.id — no param needed.
    func getMyCertificates() async throws -> CertificatesResponse {
        try await api.queryNoInput("trainingLMS.getMyCertificates")
    }

    // MARK: - Course catalog (training.listCourses)

    /// One row from `training.listCourses` — full regulatory catalog.
    struct CatalogCourse: Decodable, Identifiable, Equatable {
        let id: String
        let title: String
        let category: String
        let duration: Int
        let modules: Int
        let passingScore: Int
        let description: String
        let renewalPeriod: Int
    }

    struct ListCoursesInput: Encodable {
        let category: String?
        let search: String?
    }

    /// Catalog browse — backs the iOS Training "Courses" tab.
    func listCourses(category: String? = nil, search: String? = nil) async throws -> [CatalogCourse] {
        try await api.query(
            "training.listCourses",
            input: ListCoursesInput(category: category, search: search)
        )
    }

    struct StartCourseInput: Encodable { let courseId: String }
    struct StartCourseAck: Decodable { let success: Bool; let enrollmentId: String }

    /// Enroll the signed-in driver in a catalog course. Returns the
    /// fresh `userTraining.id` so the caller can link to a take-test
    /// flow.
    func startCourse(courseId: String) async throws -> StartCourseAck {
        try await api.mutation(
            "training.startCourse",
            input: StartCourseInput(courseId: courseId)
        )
    }

    struct UpdateProgressInput: Encodable { let assignmentId: String; let progress: Int }
    struct UpdateProgressAck: Decodable { let success: Bool; let newProgress: Int }

    /// Drive the in-app course player progress bar.
    func updateProgress(assignmentId: String, progress: Int) async throws -> UpdateProgressAck {
        try await api.mutation(
            "training.updateProgress",
            input: UpdateProgressInput(assignmentId: assignmentId, progress: progress)
        )
    }

    struct CompleteTrainingInput: Encodable { let assignmentId: String; let score: Int }
    struct CompleteTrainingAck: Decodable {
        let success: Bool
        let passed: Bool
        let certificateId: String?
        let expirationDate: String?
    }

    /// Final exam submit. Score 0-100 — server passes at ≥75 and issues
    /// a certificate id when so.
    func completeTraining(assignmentId: String, score: Int) async throws -> CompleteTrainingAck {
        try await api.mutation(
            "training.completeTraining",
            input: CompleteTrainingInput(assignmentId: assignmentId, score: score)
        )
    }
}

// MARK: - DataQsAPI
//
// FMCSA Request for Data Review (RDR) filing surface backing the iOS
// 077A DataQs Filer screen. Mirrors `dataqs.*` server router (added
// alongside the 2026 reform: burden of proof on the requestor; 21/21/45
// timeline; issuing officers can no longer decide their own challenges).

struct DataQsAPI {
    let api: EusoTripAPI

    struct Filing: Decodable, Identifiable, Equatable {
        let id: String
        let requestType: String
        let referenceNumber: String
        let eventDate: String?
        let jurisdiction: String?
        let issuingOfficer: String?
        let violationCode: String?
        let challengeStatement: String
        let evidenceUrls: [String]
        let rdrSubmissionId: String?
        let status: String
        let reviewerNotes: String?
        let resolution: String?
        let expectedReplyBy: String?
        let submittedAt: String?
        let resolvedAt: String?
        let createdAt: String
    }

    struct ListResponse: Decodable, Equatable {
        let total: Int
        let rows: [Filing]
    }

    struct ListInput: Encodable {
        let status: String?
        let limit: Int
        let offset: Int
    }

    func listMine(status: String? = nil, limit: Int = 25, offset: Int = 0) async throws -> ListResponse {
        try await api.query(
            "dataqs.listMine",
            input: ListInput(status: status, limit: limit, offset: offset)
        )
    }

    struct FileInput: Encodable {
        let requestType: String
        let referenceNumber: String
        let eventDate: String?
        let jurisdiction: String?
        let issuingOfficer: String?
        let violationCode: String?
        let challengeStatement: String
        let evidenceUrls: [String]
        let dotNumber: String?
        let driverId: String?
        let rdrSubmissionId: String?
        let status: String
    }

    struct FileAck: Decodable {
        let success: Bool
        let id: String
        let status: String
        let expectedReplyBy: String
    }

    func file(_ input: FileInput) async throws -> FileAck {
        try await api.mutation("dataqs.file", input: input)
    }

    struct AIDraftInput: Encodable {
        let requestType: String
        let violationCode: String?
        let eventDate: String?
        let jurisdiction: String?
        let issuingOfficer: String?
        let carrierFacts: String
        let driverAccount: String?
    }

    struct AIDraft: Decodable {
        let available: Bool
        let challengeStatement: String
        let evidenceChecklist: [String]
        let frivolousClaimRisk: String
        let reasoning: String
        let localResolutionRecommended: Bool?
        let regulationsCited: [String]?
    }

    /// Gemini-assisted draft. Reads the carrier's facts + driver's
    /// account and returns the burden-of-proof challenge statement +
    /// evidence checklist + frivolous-claim self-check.
    func aiDraft(_ input: AIDraftInput) async throws -> AIDraft {
        try await api.mutation("dataqs.aiDraft", input: input)
    }
}

// MARK: - PaymentsAPI
//
// Driver-facing payment-methods surface backing 077 Me · Payment
// Methods. Reads / writes Stripe via the backend — no raw Stripe keys
// on the device.
//
// MCP-verified procedures (tRPC namespace `payments.*`):
//   • getPaymentMethods     — cards + us_bank_account types (mixed list)
//   • setDefaultMethod      — mutate customer.invoice_settings
//   • deletePaymentMethod   — detach the payment method id
//
// 71st firing.

struct PaymentsAPI {
    let api: EusoTripAPI

    // MARK: Decoded shapes

    /// One row in the driver's payment-methods list. Two shapes: a
    /// `card` row has `brand` + `expiryDate`; a `bank` row has
    /// `bankName`. `last4` is populated on both. `billingAddress` is
    /// present on cards only.
    struct PaymentMethod: Decodable, Identifiable, Equatable {
        let id: String
        /// "card" | "bank"
        let type: String
        let last4: String
        let brand: String?
        let expiryDate: String?          // "MM/YY"
        let bankName: String?
        let isDefault: Bool
        let billingAddress: BillingAddress?

        struct BillingAddress: Decodable, Equatable {
            let street: String
            let city: String
            let state: String
            let zip: String
        }
    }

    // MARK: Inputs

    struct PaymentMethodIdInput: Encodable {
        let paymentMethodId: String
    }

    // MARK: Procedures

    /// Returns the driver's cards + bank-account payment methods,
    /// with the `isDefault` flag set against whichever one is wired
    /// as the Stripe Customer invoice default.
    func listPaymentMethods() async throws -> [PaymentMethod] {
        try await api.queryNoInput("payments.getPaymentMethods")
    }

    /// Promote a payment method to the default. Returns `{success,
    /// methodId}` — we don't currently surface the methodId after, so
    /// the response is decoded as a generic success row.
    struct SetDefaultResponse: Decodable {
        let success: Bool
        let methodId: String?
    }

    func setDefaultMethod(paymentMethodId: String) async throws -> SetDefaultResponse {
        try await api.mutation(
            "payments.setDefaultMethod",
            input: PaymentMethodIdInput(paymentMethodId: paymentMethodId)
        )
    }

    /// Detach a payment method from the driver's Stripe Customer.
    /// Irreversible — the row disappears from the list on next refresh.
    struct DeleteResponse: Decodable {
        let success: Bool
        let methodId: String?
    }

    func deletePaymentMethod(paymentMethodId: String) async throws -> DeleteResponse {
        try await api.mutation(
            "payments.deletePaymentMethod",
            input: PaymentMethodIdInput(paymentMethodId: paymentMethodId)
        )
    }
}

// MARK: - ComplianceAPI
//
// Violations + resolution surface. Backs 082 Me · Violations
// Manager.
//
// MCP-verified procedures (tRPC namespace `compliance.*`):
//   • getViolations({search?, status?, severity?, page, limit})
//       — returns either a bare `[Violation]` array or a
//         `{violations: [...], complianceKnowledge: [...]}` envelope
//         depending on whether the server fired its AI enrichment
//         path. The Swift decoder tolerates both shapes.
//   • getViolationStats — aggregate counts (open / critical /
//         inProgress / resolved / totalFines / avgResolutionDays).
//   • resolveViolation({id, resolution?, notes?}) — marks the
//         backing inspection row `status = passed` and stamps
//         resolvedAt + resolvedBy.
//
// 75th firing.

struct ComplianceAPI {
    let api: EusoTripAPI

    // MARK: Decoded shapes

    /// One violation row from `compliance.getViolations`. `type`,
    /// `severity`, and `status` are decoded as strings so server
    /// additions (e.g. "warning" severity, "acknowledged" status)
    /// don't require a mobile release.
    struct Violation: Decodable, Identifiable, Equatable {
        let id: String
        let type: String          // "inspection" | "annual" | "preTrip" | etc.
        let driver: String
        let driverId: String
        let vehicleId: String
        let date: String          // YYYY-MM-DD
        /// "critical" | "major" | "minor"
        let severity: String
        /// "open" | "resolved"
        let status: String
        let defectsFound: Int
        let oosViolation: Bool
        let location: String
        /// FMCSA CFR reference — e.g. "49 CFR 396.7" or "49 CFR 396.3".
        let regulation: String
    }

    /// Response shape — tolerates either a bare array or the
    /// `{violations, complianceKnowledge}` envelope the server
    /// returns when search-term AI enrichment fires.
    struct ViolationsResponse: Decodable, Equatable {
        let violations: [Violation]
        /// AI-retrieved knowledge snippets tied to the search term.
        /// Server returns 0-3 entries when relevance > 0.3; empty
        /// otherwise.
        let complianceKnowledge: [String]

        init(from decoder: Decoder) throws {
            // Try bare-array shape first.
            if let single = try? decoder.singleValueContainer(),
               let bare = try? single.decode([Violation].self) {
                self.violations = bare
                self.complianceKnowledge = []
                return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.violations = (try? c.decode([Violation].self, forKey: .violations)) ?? []
            self.complianceKnowledge = (try? c.decode([String].self, forKey: .complianceKnowledge)) ?? []
        }

        enum CodingKeys: String, CodingKey {
            case violations, complianceKnowledge
        }
    }

    struct ViolationStats: Decodable, Equatable {
        let open: Int
        let critical: Int
        let inProgress: Int
        let resolved: Int
        let totalFines: Double
        let avgResolutionDays: Double
    }

    struct ResolveViolationResult: Decodable, Equatable {
        let success: Bool
        let id: String
        let resolvedAt: String?
        let resolvedBy: String?
    }

    // MARK: Inputs

    struct GetViolationsInput: Encodable {
        let search: String?
        let status: String?
        let severity: String?
        let page: Int
        let limit: Int
    }

    struct ResolveViolationInput: Encodable {
        let id: String
        let resolution: String?
        let notes: String?
    }

    // MARK: Procedures

    func getViolations(
        search: String? = nil,
        status: String? = nil,
        severity: String? = nil,
        page: Int = 1,
        limit: Int = 20
    ) async throws -> ViolationsResponse {
        try await api.query(
            "compliance.getViolations",
            input: GetViolationsInput(
                search: search, status: status, severity: severity,
                page: page, limit: limit
            )
        )
    }

    func getViolationStats() async throws -> ViolationStats {
        try await api.queryNoInput("compliance.getViolationStats")
    }

    func resolveViolation(
        id: String,
        resolution: String? = nil,
        notes: String? = nil
    ) async throws -> ResolveViolationResult {
        try await api.mutation(
            "compliance.resolveViolation",
            input: ResolveViolationInput(id: id, resolution: resolution, notes: notes)
        )
    }

    // MARK: - Driver compliance roster (Catalyst 326 Driver Compliance)

    /// One driver row in the catalyst's compliance list. Backed by
    /// `compliance.getDriverComplianceList` (compliance.ts:2395) which
    /// joins drivers ↔ users for the display name and emits CDL,
    /// medical, hazmat expiry dates plus a derived per-driver
    /// "compliant / expiring / expired" status against the 30-day
    /// horizon. Powers the canonical 49 CFR §391 / §382 / §391.41
    /// row stack on Catalyst 326.
    struct DriverComplianceRow: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let cdlNumber: String
        /// "compliant" | "expiring" | "expired"
        let status: String
        let safetyScore: Int
        /// Driver row's `drivers.status` column ("active", "off_duty", ...).
        let driverStatus: String
        /// `YYYY-MM-DD` projection of the underlying TIMESTAMP, empty
        /// when not on file.
        let licenseExpiry: String
        let medicalExpiry: String
        let nearestExpiry: String
    }

    struct DriverComplianceList: Decodable {
        let drivers: [DriverComplianceRow]
    }

    func getDriverComplianceList(limit: Int = 50) async throws -> DriverComplianceList {
        struct Input: Encodable { let limit: Int }
        return try await api.query(
            "compliance.getDriverComplianceList",
            input: Input(limit: limit)
        )
    }

    // MARK: - Catalyst (carrier-level) compliance overview (Catalyst 317)

    /// Carrier-level compliance envelope. Backed by
    /// `compliance.getCatalystCompliance` (compliance.ts:2456) which
    /// reads the catalyst's `companies` row and derives the score from
    /// MC + DOT + insurance expiry + compliance_status + hazmat license
    /// presence. Powers the Catalyst 317 surface (carrier-level mirror
    /// of the per-driver 326 federal scanline).
    struct CatalystComplianceInsurance: Decodable, Hashable {
        /// "active" | "expiring" | "expired" | "missing"
        let status: String
        let coverage: Double
        /// `YYYY-MM-DD` projection of the underlying TIMESTAMP, empty
        /// when not on file.
        let expires: String
    }

    struct CatalystComplianceOverview: Decodable, Hashable {
        /// 0–100 overall score. Sum of: MC (20) + DOT (20) + insurance
        /// not expired (20) + compliance_status compliant (20) + hazmat
        /// license (10) + baseline (10).
        let score: Int
        /// MC number (empty when no for-hire authority).
        let mcAuthority: String
        let dotNumber: String
        /// "Active" when MC is on file, empty otherwise.
        let ucr: String
        let ifta: String
        let irp: String
        let liabilityInsurance: CatalystComplianceInsurance
        let cargoInsurance: CatalystComplianceInsurance
        /// "Satisfactory" | "Conditional" | "Unsatisfactory"
        let safetyRating: String
        /// FMCSA CSA composite score; 0 until the SMS feed is wired.
        let csaScore: Int
    }

    func getCatalystCompliance() async throws -> CatalystComplianceOverview {
        try await api.queryNoInput("compliance.getCatalystCompliance")
    }
}

// MARK: - FMCSA self-lookup (Catalyst 317 — live SAFER record)

/// Mirrors `fmcsa.lookupSelf` (frontend/server/routers/fmcsa.ts:298).
/// Returns the catalyst's own DOT/MC SAFER record, joining the QCMobile
/// catalyst payload + Redis/MySQL cache + live SAFER call. The two
/// shapes share the `available` discriminator: when `available: false`
/// the response carries a `reason` string; when `available: true` the
/// response carries the flattened SAFER fields below.
struct FMCSASelfLookup: Decodable, Hashable {
    /// True when the SAFER record resolved. False with a `reason`
    /// string when DOT/MC isn't on file or SAFER returned no record.
    let available: Bool
    let reason: String?

    let dotNumber: String?
    let mcNumber: String?
    let legalName: String?
    /// "SATISFACTORY" | "CONDITIONAL" | "UNSATISFACTORY" | "NOT RATED"
    let safetyRating: String?
    /// Out-of-service violations across driver + vehicle + hazmat
    /// inspection sets (sum from QCMobile feed).
    let oosViolations: Int?
    /// `lastInspection` is the SAFER `ratingDate` projection — empty
    /// when no rating has been issued yet.
    let lastInspection: String?
}

struct FMCSAAPI {
    unowned let api: EusoTripAPI

    /// `fmcsa.lookupSelf` — pulls the signed-in catalyst's own DOT
    /// from `companies.dotNumber` and resolves the SAFER record via
    /// the cached / live QCMobile chain. Powers 317 Catalyst
    /// Compliance + 308 Authority + Insurance surfaces.
    func lookupSelf() async throws -> FMCSASelfLookup {
        try await api.queryNoInput("fmcsa.lookupSelf")
    }

    // MARK: — Registration-time SAFER autofill
    //
    // Mirrors the web `FMCSALookup` component's two queries (the
    // canonical view of these endpoints lives at
    // `frontend/server/routers/fmcsa.ts:131` and `:415`). Used by the
    // catalyst / broker registration forms to verify a DOT or MC
    // number and pre-fill 30+ company / authority / insurance
    // fields in one round-trip.

    func lookupByDOT(_ dotNumber: String) async throws -> FMCSACarrierLookup {
        struct Input: Encodable { let dotNumber: String }
        return try await api.query("fmcsa.lookupByDOT", input: Input(dotNumber: dotNumber))
    }

    func lookupByMC(_ mcNumber: String) async throws -> FMCSACarrierLookup {
        struct Input: Encodable { let mcNumber: String }
        return try await api.query("fmcsa.lookupByMC", input: Input(mcNumber: mcNumber))
    }
}

// MARK: - FMCSACarrierLookup
//
// The full SAFER autofill envelope returned by `fmcsa.lookupByDOT` /
// `lookupByMC`. Mirrors `parseCatalystResponse()` at
// `frontend/server/routers/fmcsa.ts:44` plus the error / warning
// envelope wrapping it.

struct FMCSACarrierLookup: Decodable, Hashable {
    /// `true` when SAFER resolved a carrier for the input number.
    /// When `false`, `error` carries the human-facing reason and the
    /// rest of the envelope is empty.
    let verified: Bool
    let error: String?
    /// FMCSA web-key wasn't set on the server — UI surfaces a
    /// "register manually" hint in this case rather than an error
    /// toast.
    let noApiKey: Bool?
    /// SAFER marks the carrier `allowedToOperate = N`. The UI blocks
    /// the Submit button when this fires.
    let isBlocked: Bool?
    let blockReason: String?
    /// Non-fatal warnings — out-of-service rates above the national
    /// average, missing BIPD insurance, conditional safety rating.
    let warnings: [String]?
    /// Raw cache freshness — when the lookup hit the Redis or MySQL
    /// cache layer, the server stamps the original fetch time so the
    /// UI can show "verified 14 days ago".
    let fetchedAt: String?
    let fromCache: Bool?

    let companyProfile: CompanyProfile?
    let authority: Authority?
    let safety: Safety?
    let insurance: Insurance?
    let hazmat: Hazmat?

    // MARK: Decodable

    enum CodingKeys: String, CodingKey {
        case verified, error, noApiKey, isBlocked, blockReason, warnings, fetchedAt, fromCache
        case companyProfile, authority, safety, insurance, hazmat
        case results  // MC search envelope
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try standard profile shape (lookupByDOT).
        if let verified = try container.decodeIfPresent(Bool.self, forKey: .verified) {
            self.verified = verified
            self.error = try container.decodeIfPresent(String.self, forKey: .error)
            self.noApiKey = try container.decodeIfPresent(Bool.self, forKey: .noApiKey)
            self.isBlocked = try container.decodeIfPresent(Bool.self, forKey: .isBlocked)
            self.blockReason = try container.decodeIfPresent(String.self, forKey: .blockReason)
            self.warnings = try container.decodeIfPresent([String].self, forKey: .warnings)
            self.fetchedAt = try container.decodeIfPresent(String.self, forKey: .fetchedAt)
            self.fromCache = try container.decodeIfPresent(Bool.self, forKey: .fromCache)
            self.companyProfile = try container.decodeIfPresent(CompanyProfile.self, forKey: .companyProfile)
            self.authority = try container.decodeIfPresent(Authority.self, forKey: .authority)
            self.safety = try container.decodeIfPresent(Safety.self, forKey: .safety)
            self.insurance = try container.decodeIfPresent(Insurance.self, forKey: .insurance)
            self.hazmat = try container.decodeIfPresent(Hazmat.self, forKey: .hazmat)
        } else if container.contains(.results) {
            // MC search envelope: `{ results: [...], error?, noApiKey? }`.
            // Set verified=false since this is a search result array, not a profile.
            self.verified = false
            self.error = try container.decodeIfPresent(String.self, forKey: .error)
            self.noApiKey = try container.decodeIfPresent(Bool.self, forKey: .noApiKey)
            self.isBlocked = nil
            self.blockReason = nil
            self.warnings = nil
            self.fetchedAt = nil
            self.fromCache = try container.decodeIfPresent(Bool.self, forKey: .fromCache)
            self.companyProfile = nil
            self.authority = nil
            self.safety = nil
            self.insurance = nil
            self.hazmat = nil
        } else {
            // Fallback: missing/invalid top-level shape.
            self.verified = false
            self.error = "Invalid FMCSA response envelope"
            self.noApiKey = nil
            self.isBlocked = nil
            self.blockReason = nil
            self.warnings = nil
            self.fetchedAt = nil
            self.fromCache = nil
            self.companyProfile = nil
            self.authority = nil
            self.safety = nil
            self.insurance = nil
            self.hazmat = nil
        }
    }

    struct CompanyProfile: Decodable, Hashable {
        let legalName: String
        let dba: String?
        let phone: String?
        let email: String?
        let physicalAddress: Address
        let mailingAddress: Address?
        let fleetSize: Int
        let driverCount: Int
    }

    struct Address: Decodable, Hashable {
        let street: String
        let city: String
        let state: String
        let zip: String
        let country: String?
    }

    struct Authority: Decodable, Hashable {
        let dotNumber: String
        let allowedToOperate: Bool
        /// "ACTIVE" | "INACTIVE"
        let operatingStatus: String
        /// "Y" / "N" / "P" (pending) per FMCSA dictionary
        let commonAuthority: String
        let contractAuthority: String
        let brokerAuthority: String
        let catalystOperation: String?
        let catalystOperationCode: String?
    }

    struct Safety: Decodable, Hashable {
        /// "SATISFACTORY" | "CONDITIONAL" | "UNSATISFACTORY" | "NOT RATED"
        let rating: String
        let ratingDate: String?
        let crashTotal: Int
        let fatalCrash: Int
        let injCrash: Int
        let towCrash: Int
        let inspections: Inspections

        struct Inspections: Decodable, Hashable {
            let driver: Cell
            let vehicle: Cell
            let hazmat: Cell
            struct Cell: Decodable, Hashable {
                let total: Int
                let oos: Int
                let rate: Double
            }
        }
    }

    struct Insurance: Decodable, Hashable {
        let bipdOnFile: Bool
        let bipdRequired: Bool
        let bipdAmount: Double?
        let cargoOnFile: Bool
        let cargoRequired: Bool
        let bondOnFile: Bool
        let bondRequired: Bool
    }

    struct Hazmat: Decodable, Hashable {
        let authorized: Bool
    }
}

// MARK: - CsaScoresAPI
//
// FMCSA CSA (Compliance, Safety, Accountability) surface. Today the
// iOS app only uses the DataQs Challenge filer — an RDR (Request for
// Data Review) under 49 CFR §386 that contests a specific FMCSA-
// reported violation. MCP-verified at
// `frontend/server/routers/csaScores.ts:310`.
//
// 77th firing.

struct CsaScoresAPI {
    let api: EusoTripAPI

    struct DataQsChallengeInput: Encodable {
        let violationId: String
        /// Server enum: "incorrect_data" | "not_responsible" |
        /// "documentation_error" | "other".
        let reason: String
        let explanation: String
        /// Document ids the driver wants attached as supporting
        /// evidence. Resolved server-side to the actual document
        /// blobs at submission time.
        let supportingDocs: [String]?
    }

    struct DataQsChallengeResponse: Decodable, Equatable {
        let challengeId: String
        let violationId: String
        let status: String
        let submittedBy: String?
        let submittedAt: String?
        /// ISO-8601. FMCSA's typical response window is 60 days, so
        /// the server stamps a +60-day estimate here by default.
        let estimatedResponse: String?
    }

    func submitDataQsChallenge(
        violationId: String,
        reason: String,
        explanation: String,
        supportingDocs: [String]? = nil
    ) async throws -> DataQsChallengeResponse {
        try await api.mutation(
            "csaScores.submitDataQsChallenge",
            input: DataQsChallengeInput(
                violationId: violationId,
                reason: reason,
                explanation: explanation,
                supportingDocs: supportingDocs
            )
        )
    }

    // MARK: Overview (085 Me · Carrier Scorecard)
    //
    // MCP-verified at `frontend/server/routers/csaScores.ts:23`.
    // Returns the carrier's full BASIC scorecard — 7 Behavior
    // Analysis and Safety Improvement Categories (BASICs), SAFER
    // data (OOS rates, inspection count), and FMCSA bulk-data
    // enrichment (crashes, violations) when the carrier's USDOT is
    // on file.

    /// One BASIC category row in the `basics[]` array. Thresholds
    /// are the percentile cutoffs FMCSA uses to flag a category:
    /// 65 for safety-sensitive BASICs (Unsafe Driving, HOS, Crash),
    /// 80 for the others. A percentile at or above threshold trips
    /// the `alert` flag on the server.
    struct BasicCategory: Decodable, Identifiable, Equatable {
        let category: String         // "unsafe_driving" | "hos_compliance" | ...
        let name: String             // human label
        let percentile: Double       // 0-100
        let threshold: Int           // 65 or 80
        let status: String           // "ok" | "warning" | "alert"
        let trend: String            // "stable" | "up" | "down" (future-proof)
        let inspections: Int
        let violations: Int
        let alert: Bool
        var id: String { category }
    }

    /// SAFER snapshot. Server zeroes fields the FMCSA bulk pull
    /// didn't populate; iOS treats zero as unknown for display.
    struct SaferData: Decodable, Equatable {
        let outOfServiceRate: Double
        let nationalAverage: Double
        let inspectionCount24Months: Int
        let driverOOSRate: Double
        let vehicleOOSRate: Double

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.outOfServiceRate = try c.decodeIfPresent(Double.self, forKey: .outOfServiceRate) ?? 0
            self.nationalAverage = try c.decodeIfPresent(Double.self, forKey: .nationalAverage) ?? 0
            self.inspectionCount24Months = try c.decodeIfPresent(Int.self, forKey: .inspectionCount24Months) ?? 0
            self.driverOOSRate = try c.decodeIfPresent(Double.self, forKey: .driverOOSRate) ?? 0
            self.vehicleOOSRate = try c.decodeIfPresent(Double.self, forKey: .vehicleOOSRate) ?? 0
        }

        enum CodingKeys: String, CodingKey {
            case outOfServiceRate
            case nationalAverage
            case inspectionCount24Months
            case driverOOSRate
            case vehicleOOSRate
        }
    }

    /// FMCSA crashes 24-month summary. Nil when the USDOT isn't on
    /// file or the bulk pull hasn't run yet.
    struct FmcsaCrashes: Decodable, Equatable {
        let total: Int
        let fatalities: Int
        let injuries: Int
        let towAways: Int
        let hazmatReleases: Int
        let recent: Int?
    }

    /// FMCSA inspections 24-month summary. Same nil rule as crashes.
    struct FmcsaInspections: Decodable, Equatable {
        let total: Int
        let violations: Int
        let driverOos: Int
        let vehicleOos: Int
        let hazmatOos: Int
        let recent: Int?
    }

    struct CsaOverview: Decodable, Equatable {
        let companyId: String
        let companyName: String
        let dotNumber: String
        let mcNumber: String
        let lastUpdated: String
        /// "satisfactory" | "alert" | "critical" | "out_of_service"
        let overallStatus: String
        /// "none" | "warning" | "critical"
        let alertLevel: String
        let basics: [BasicCategory]
        let saferData: SaferData?
        let fmcsaCrashes: FmcsaCrashes?
        let fmcsaInspections: FmcsaInspections?
        let outOfService: Bool?
        let oosReason: String?
        /// "fmcsa_bulk_9.8M" when real FMCSA data resolved, else
        /// "platform_internal". UI uses this to tell the driver
        /// whether they're looking at true federal data or the
        /// internal placeholder.
        let dataSource: String?
    }

    struct CsaOverviewInput: Encodable {
        let companyId: String?
    }

    func getOverview(companyId: String? = nil) async throws -> CsaOverview {
        try await api.query(
            "csaScores.getOverview",
            input: CsaOverviewInput(companyId: companyId)
        )
    }
}

// MARK: - esangCoachRouter (087 Me · Safety Coach)
//
// Mirrors `frontend/server/routers/esangCoach.ts`. Today's iOS-
// relevant surface is the `forDriver` query, which returns 3–10
// coaching items personalized to the driver's role + vertical +
// recent compliance signal. The server may ship either a Gemini-
// authored payload or the deterministic fallback when Gemini is
// down; the iOS client treats both identically — we render whatever
// items the server returned.

struct eSangCoachAPI {
    unowned let api: EusoTripAPI

    // MARK: Server-shaped input / output

    struct ForDriverInput: Encodable {
        let recentIncidents: Int?
        let recentViolations: Int?
        let recentNearMisses: Int?
        let focus: String?
        let limit: Int?
    }

    /// One coaching card. `severity` and `topic` use the server's
    /// lowercase enums verbatim — no client-side remapping — so the
    /// UI can evolve alongside the backend without cross-coding.
    struct CoachingItem: Decodable, Equatable, Identifiable {
        /// Stable identity for SwiftUI `ForEach`. Server doesn't ship
        /// an id field (the items are stateless) so we derive one from
        /// topic + title. Collisions across a single response are not
        /// expected given the server already filters empty titles.
        var id: String { "\(topic)::\(title)" }

        let title: String          // ≤ 60 chars per server prompt
        let body: String           // ≤ 200 chars per server prompt
        /// "info" | "watch" | "critical"
        let severity: String
        /// Short CFR reference (e.g. "49 CFR 395.3(a)(3)"), or nil
        /// when the server chose not to cite one. Never synthesised
        /// client-side.
        let cfr: String?
        /// Short lowercase slug the UI maps to an SF Symbol.
        let topic: String
    }

    struct ForDriverResponse: Decodable, Equatable {
        let items: [CoachingItem]
        /// Echoed user role from ctx; used by the view to render the
        /// "For <role-label>" subheader.
        let role: String
        /// "truck" | "rail" | "vessel" | "cross"
        let vertical: String
        /// Server clock epoch millis. UI shows relative time
        /// ("Updated 2m ago") keyed off this.
        let generatedAt: Double
    }

    // MARK: Queries

    /// `esangCoach.forDriver` — GET query. Returns role- and
    /// vertical-tailored coaching cards. All inputs are optional —
    /// pass driver-observed recent counts for a fresher result, or
    /// omit to let the server pull the signed-in driver's own
    /// counts from the database.
    func forDriver(
        recentIncidents: Int? = nil,
        recentViolations: Int? = nil,
        recentNearMisses: Int? = nil,
        focus: String? = nil,
        limit: Int = 6
    ) async throws -> ForDriverResponse {
        try await api.query(
            "esangCoach.forDriver",
            input: ForDriverInput(
                recentIncidents: recentIncidents,
                recentViolations: recentViolations,
                recentNearMisses: recentNearMisses,
                focus: (focus?.isEmpty ?? true) ? nil : focus,
                limit: limit
            )
        )
    }
}

// MARK: - referralsRouter (088 Me · Invite & Earn)
//
// Mirrors `frontend/server/routers/referrals.ts`. The driver-scoped
// Me · Invite & Earn screen reads `getMyCode` (one per driver,
// minted on first call), `summary` (counters for the header), and
// `listMine` (recent referral events by stage).
//
// Reward schedule is authoritative server-side (`REWARD_CENTS` in
// referrals.ts). The iOS client never fabricates the reward
// amount — it renders whatever the server returned.

struct ReferralsAPI {
    unowned let api: EusoTripAPI

    // MARK: - Shapes

    struct ReferralCode: Decodable, Equatable {
        let id: Int
        let code: String
        let uses: Int
        /// Nil → unlimited. A truthy value caps how many referees
        /// may redeem this code; used by admins only (drivers don't
        /// manage their own cap today).
        let maxUses: Int?
    }

    struct ReferralSummary: Decodable, Equatable {
        let totalRefs: Int
        let totalEarnedCents: Int
        let pendingCents: Int
        /// Per-stage roll-up keyed by the server's stage strings:
        /// "signup" | "first_load" | "first_payout" | "kyc_verified".
        /// Each entry is `{n, totalCents, paidCents, pendingCents}`.
        let byStage: [String: StageRollup]

        struct StageRollup: Decodable, Equatable {
            let n: Int?
            let totalCents: Int?
            let paidCents: Int?
            let pendingCents: Int?
        }
    }

    /// One referral event — the referee's funnel stage + the reward
    /// the referrer earned for crossing it. `paidAt == nil` means
    /// the reward is still accruing.
    struct ReferralEvent: Decodable, Equatable, Identifiable {
        let id: Int
        let referredId: Int
        /// Server stage enum — "signup" | "first_load" |
        /// "first_payout" | "kyc_verified".
        let stage: String
        let rewardCents: Int
        let rewardKind: String
        /// Nil while pending.
        let paidAt: String?
        let createdAt: String?
    }

    // MARK: - Queries

    /// `referrals.getMyCode` — returns (minting on first call) the
    /// caller's active referral code. Safe to call repeatedly — the
    /// server checks for an existing row before minting.
    func getMyCode() async throws -> ReferralCode {
        try await api.queryNoInput("referrals.getMyCode")
    }

    /// `referrals.summary` — totals for the Invite & Earn header.
    func getSummary() async throws -> ReferralSummary {
        try await api.queryNoInput("referrals.summary")
    }

    /// `referrals.listMine` — recent referral events with optional
    /// stage filter. Server clamps limit to [1, 100]; default 30.
    func listMine(
        stage: String? = nil,
        limit: Int = 30
    ) async throws -> [ReferralEvent] {
        struct Input: Encodable {
            let stage: String?
            let limit: Int
        }
        return try await api.query(
            "referrals.listMine",
            input: Input(stage: stage, limit: limit)
        )
    }

    // MARK: - Mutations

    struct ApplyResult: Decodable, Equatable {
        let ok: Bool
        let stage: String?
        let rewardCents: Int?
    }

    /// `referrals.applyCode` — the referee applies another driver's
    /// code during onboarding. Referrer + referee both need the link
    /// to land, so this mutation is safe for the referee to call
    /// from the sign-up flow.
    func applyCode(_ code: String) async throws -> ApplyResult {
        struct Input: Encodable { let code: String }
        return try await api.mutation(
            "referrals.applyCode",
            input: Input(code: code)
        )
    }
}

// MARK: - Haul (gamification + missions + achievements, 089 Me · The Haul)
//
// Composite façade for the driver's Haul brand surface. The
// iOS client calls three live tRPC procs in parallel:
//
//   gamification.getProfile    → level + XP + rank + streaks + stats
//   missions.listMine          → active + claimable mission progress rows
//   achievements.listMine      → earned + optionally-displayed badges
//
// Each proc is exposed as its own method so the UI can refresh one
// feed independently (e.g. optimistic refresh of missions after a
// claim without re-fetching the whole profile).

struct HaulAPI {
    unowned let api: EusoTripAPI

    // MARK: - gamification.getProfile

    struct Streaks: Decodable, Equatable {
        let currentOnTime: Int?
        let longestOnTime: Int?
        let currentSafe: Int?
        let longestSafe: Int?
    }

    struct ProfileStats: Decodable, Equatable {
        let loadsCompleted: Int?
        let milesDriver: Int?
        let onTimeRate: Double?
        let safetyScore: Double?
        let customerRating: Double?
    }

    struct Profile: Decodable, Equatable {
        let userId: Int
        let name: String
        let level: Int
        /// Optional user-facing title (e.g. "Highway Pro"). Nil when
        /// the driver hasn't earned one yet.
        let title: String?
        let totalPoints: Int
        let currentXp: Int
        let xpToNextLevel: Int
        /// Rank in the signed-in driver's cohort. Nil when the cohort
        /// hasn't settled yet (new signup) — UI renders "—".
        let rank: Int?
        let totalUsers: Int?
        let percentile: Double?
        /// YYYY-MM-DD from the server.
        let memberSince: String?
        let streaks: Streaks?
        let stats: ProfileStats?
    }

    /// `gamification.getProfile` — the signed-in driver's Haul
    /// profile. Server returns the zero-state payload for a brand-
    /// new driver so the view always has a shape to render.
    func getProfile() async throws -> Profile {
        struct Input: Encodable { let userId: String? = nil }
        return try await api.query(
            "gamification.getProfile",
            input: Input()
        )
    }

    // MARK: - missions.listMine

    struct Mission: Decodable, Equatable, Identifiable {
        /// Server uses a separate progress id per (driver, mission)
        /// row — we use that as the SwiftUI identity since a driver
        /// might work the same mission across seasons.
        let progressId: Int
        let missionId: Int
        let name: String?
        let category: String?
        let type: String?
        let targetType: String?
        let targetValue: Double
        let currentProgress: Double
        /// "in_progress" | "completed" | "claimed" | "failed" | "cancelled"
        let status: String
        let createdAt: String?
        let completedAt: String?
        let claimedAt: String?

        var id: Int { progressId }
    }

    /// `missions.listMine` — caller's in-progress + recently completed
    /// missions. Pass `status` to filter the server-side selection.
    func listMyMissions(
        status: String? = nil,
        limit: Int = 20
    ) async throws -> [Mission] {
        struct Input: Encodable {
            let status: String?
            let limit: Int
        }
        return try await api.query(
            "missions.listMine",
            input: Input(status: status, limit: limit)
        )
    }

    /// `missions.claim` — flips a `status == completed` mission into
    /// `claimed` and credits the driver's reward. Server rejects if
    /// the progress row isn't in a claimable state.
    struct MissionClaimResult: Decodable, Equatable {
        let success: Bool?
        let progressId: Int?
        let rewardCents: Int?
    }

    func claimMission(progressId: Int) async throws -> MissionClaimResult {
        struct Input: Encodable { let progressId: Int }
        return try await api.mutation(
            "missions.claim",
            input: Input(progressId: progressId)
        )
    }

    // MARK: - achievements.listMine

    struct Badge: Decodable, Equatable, Identifiable {
        let id: Int
        let badgeId: Int
        let code: String?
        let name: String?
        let description: String?
        let category: String?
        let tier: String?
        let iconUrl: String?
        let xpValue: Int
        let isRare: Bool
        let earnedAt: String?
        let displayOrder: Int?
        let isDisplayed: Bool
    }

    /// `achievements.listMine` — driver's earned badges.
    /// `onlyDisplayed: true` narrows to the small row the driver has
    /// pinned to their public profile, which matches the Haul
    /// header's "Shelf" affordance.
    func listMyBadges(
        onlyDisplayed: Bool = false,
        limit: Int = 100
    ) async throws -> [Badge] {
        struct Input: Encodable {
            let onlyDisplayed: Bool
            let limit: Int
        }
        return try await api.query(
            "achievements.listMine",
            input: Input(onlyDisplayed: onlyDisplayed, limit: limit)
        )
    }
}

// MARK: - supportRouter (089 Me · Support & Tickets)
//
// Mirrors `frontend/server/routers/support.ts`. Today's iOS-relevant
// surface is the driver's ticket lifecycle: see open/in-progress/
// resolved counts (`getSummary`), list their own tickets
// (`getMyTickets`), and create a new one (`createTicket`). The
// server NLP-auto-classifies category on create when the driver
// leaves the category default, so "general" is always a safe fallback.

struct SupportAPI {
    unowned let api: EusoTripAPI

    // MARK: - Shapes

    struct Summary: Decodable, Equatable {
        let total: Int
        let open: Int
        let inProgress: Int
        let resolved: Int
        let avgResponseTime: String?

        // Server uses both `open` and `openTickets` in the response
        // shape. The key we actually decode is `open`; `openTickets`
        // is ignored because it's a duplicate of the same counter.
    }

    struct Ticket: Decodable, Equatable, Identifiable {
        /// MySQL primary key. Raw DB rows ship as Int; we coerce to
        /// String via a custom init so SwiftUI ForEach can key on id.
        let id: String
        let ticketNumber: String?
        let subject: String
        /// Body of the initial message. Server ships this as `message`
        /// on the raw `support_tickets` row.
        let message: String?
        let category: String?
        let priority: String?
        /// "open" | "in_progress" | "waiting_user" | "resolved" | "closed"
        let status: String?
        let loadId: Int?
        /// ISO timestamp.
        let createdAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case ticketNumber
            case subject
            case message
            case category
            case priority
            case status
            case loadId
            case createdAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // id may come as Int (raw DB row) or String (getTicketById).
            if let intId = try? c.decode(Int.self, forKey: .id) {
                self.id = String(intId)
            } else {
                self.id = try c.decode(String.self, forKey: .id)
            }
            self.ticketNumber   = try? c.decode(String.self, forKey: .ticketNumber)
            self.subject        = (try? c.decode(String.self, forKey: .subject)) ?? "(untitled)"
            self.message        = try? c.decode(String.self, forKey: .message)
            self.category       = try? c.decode(String.self, forKey: .category)
            self.priority       = try? c.decode(String.self, forKey: .priority)
            self.status         = try? c.decode(String.self, forKey: .status)
            self.loadId         = try? c.decode(Int.self, forKey: .loadId)
            self.createdAt      = try? c.decode(String.self, forKey: .createdAt)
        }
    }

    struct MyTicketsResponse: Decodable {
        let tickets: [Ticket]
        let total: Int
    }

    // MARK: - Queries

    /// `support.getSummary` — the signed-in user's counters (open /
    /// in_progress / resolved / total). Admins get company-wide
    /// counts server-side; drivers get their own only.
    func getSummary() async throws -> Summary {
        try await api.queryNoInput("support.getSummary")
    }

    /// `support.getMyTickets` — driver-scoped paginated list.
    func getMyTickets(
        status: String? = nil,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> MyTicketsResponse {
        struct Input: Encodable {
            let status: String?
            let limit: Int
            let offset: Int
        }
        return try await api.query(
            "support.getMyTickets",
            input: Input(status: status, limit: limit, offset: offset)
        )
    }

    // MARK: - Mutations

    struct CreateTicketInput: Encodable {
        let subject: String
        let message: String
        let category: String
        let priority: String
        let loadId: String?
    }

    struct CreateTicketResult: Decodable, Equatable {
        let id: String?
        let ticketNumber: String?
        let status: String?
    }

    /// `support.createTicket` — opens a new ticket. Server NLP auto-
    /// classifies the category when `category` is "general"; otherwise
    /// the passed value is used verbatim.
    func createTicket(
        subject: String,
        message: String,
        category: String = "general",
        priority: String = "medium",
        loadId: String? = nil
    ) async throws -> CreateTicketResult {
        try await api.mutation(
            "support.createTicket",
            input: CreateTicketInput(
                subject: subject,
                message: message,
                category: category,
                priority: priority,
                loadId: loadId
            )
        )
    }
}

// MARK: - iftaCalculatorRouter (090 Me · IFTA Tax)
//
// Mirrors `frontend/server/routers/iftaCalculator.ts`. Today's
// iOS surface exposes:
//
//   estimateFromLoads  — query. Pulls the driver's delivered loads
//                        in a year+quarter window, returns estimated
//                        total miles + gallons consumed + tax
//                        liability. Zero input from the driver
//                        needed; the number is "best we can see
//                        from your real loads."
//   calculateQuarter   — mutation. Accepts per-jurisdiction miles +
//                        fuel purchases and returns the full IFTA
//                        return shape (per-state tax due / refund +
//                        filing deadline). This is the one the
//                        driver uses at filing time.

struct IftaAPI {
    unowned let api: EusoTripAPI

    enum Quarter: String, Codable, CaseIterable, Identifiable {
        case Q1, Q2, Q3, Q4
        var id: String { rawValue }

        /// ISO filing-deadline date the server stamps on quarterly
        /// returns. Computed client-side for display — the server
        /// authoritative copy is the one on the actual response.
        func filingDeadline(year: Int) -> String {
            switch self {
            case .Q1: return "\(year)-04-30"
            case .Q2: return "\(year)-07-31"
            case .Q3: return "\(year)-10-31"
            case .Q4: return "\(year + 1)-01-31"
            }
        }

        var label: String { rawValue }

        /// Which quarter "now" is in — used to pre-select the latest
        /// completed quarter on view first-load.
        static func current(in date: Date = .init()) -> Quarter {
            let m = Calendar.current.component(.month, from: date)
            switch m {
            case 1...3:   return .Q1
            case 4...6:   return .Q2
            case 7...9:   return .Q3
            default:      return .Q4
            }
        }
    }

    // MARK: - estimateFromLoads

    struct Estimate: Decodable, Equatable {
        let period: String
        let loadsInPeriod: Int
        let estimatedTotalMiles: Double
        let estimatedGallonsConsumed: Double
        let estimatedTaxLiability: Double
        let note: String?
    }

    /// `iftaCalculator.estimateFromLoads` — quick tax-liability
    /// forecast from the driver's delivered loads in a year+quarter.
    func estimateFromLoads(
        year: Int,
        quarter: Quarter,
        fleetMpg: Double = 6.5
    ) async throws -> Estimate {
        struct Input: Encodable {
            let year: Int
            let quarter: String
            let fleetMpg: Double
        }
        return try await api.query(
            "iftaCalculator.estimateFromLoads",
            input: Input(year: year, quarter: quarter.rawValue, fleetMpg: fleetMpg)
        )
    }

    // MARK: - calculateQuarter

    struct QuarterSummary: Decodable, Equatable {
        let totalMiles: Double
        let totalGallonsPurchased: Double
        let totalGallonsConsumed: Double
        let fleetMpg: Double
        let netTaxDue: Double
        let jurisdictionsOwed: Int
        let jurisdictionsRefund: Int
    }

    struct JurisdictionRow: Decodable, Equatable, Identifiable {
        let jurisdiction: String
        let miles: Double
        let gallonsConsumed: Double
        let gallonsPurchased: Double
        let netGallons: Double
        let taxRate: Double
        let taxDue: Double
        let isRefund: Bool

        var id: String { jurisdiction }
    }

    struct QuarterReturn: Decodable, Equatable {
        let period: String
        let summary: QuarterSummary
        let jurisdictions: [JurisdictionRow]
        let filingDeadline: String
    }

    /// `iftaCalculator.calculateQuarter` — full filing-ready IFTA
    /// return. Takes the driver's per-jurisdiction miles + gallons
    /// and returns the filing breakdown.
    func calculateQuarter(
        year: Int,
        quarter: Quarter,
        milesByJurisdiction: [String: Double],
        fuelPurchasesByJurisdiction: [String: Double],
        fleetMpg: Double = 6.5
    ) async throws -> QuarterReturn {
        struct Input: Encodable {
            let year: Int
            let quarter: String
            let milesByJurisdiction: [String: Double]
            let fuelPurchasesByJurisdiction: [String: Double]
            let fleetMpg: Double
        }
        return try await api.mutation(
            "iftaCalculator.calculateQuarter",
            input: Input(
                year: year,
                quarter: quarter.rawValue,
                milesByJurisdiction: milesByJurisdiction,
                fuelPurchasesByJurisdiction: fuelPurchasesByJurisdiction,
                fleetMpg: fleetMpg
            )
        )
    }
}

// MARK: - detentionAccessorialsRouter (091 Me · Detention)
//
// Mirrors `frontend/server/routers/detentionAccessorials.ts`. The
// driver Me surface focuses on three reads + one write:
//   - `getDetentionDashboard` — $ billed / collected / disputed
//   - `getActiveDetentions`   — what's accruing right now
//   - `getDetentionHistory`   — past events
//   - `disputeDetention`      — challenge a claim
// TONU / demurrage / layover surfaces ship in follow-up bricks.

struct DetentionAPI {
    unowned let api: EusoTripAPI

    // MARK: - Dashboard

    struct Dashboard: Decodable, Equatable {
        let activeDetentions: Int
        let avgWaitMinutes: Int
        let totalCharges: Double
        let totalEvents: Int
        let billedAmount: Double
        let collectedAmount: Double
        let disputedAmount: Double
    }

    /// `detentionAccessorials.getDetentionDashboard` — counters for
    /// the hero. Optional date-range input; default server window is
    /// the last 30 days.
    func getDashboard(dateFrom: String? = nil, dateTo: String? = nil) async throws -> Dashboard {
        struct Input: Encodable {
            let dateFrom: String?
            let dateTo: String?
        }
        return try await api.query(
            "detentionAccessorials.getDetentionDashboard",
            input: Input(dateFrom: dateFrom, dateTo: dateTo)
        )
    }

    // MARK: - Active detentions

    struct ActiveDetention: Decodable, Equatable, Identifiable {
        let id: Int
        let loadId: Int?
        let facilityName: String
        let locationType: String
        let arrivalTime: String?
        let elapsedMinutes: Int
        let freeTimeMinutes: Int
        let billableMinutes: Int
        let currentCharge: Double
    }

    struct ActiveDetentionsResponse: Decodable {
        let detentions: [ActiveDetention]
        let total: Int
    }

    /// `detentionAccessorials.getActiveDetentions` — drivers stuck
    /// at a dock right now, with live elapsed + billable minutes
    /// computed server-side from arrival time.
    func getActive(limit: Int = 25) async throws -> ActiveDetentionsResponse {
        struct Input: Encodable {
            let limit: Int
            let offset: Int
        }
        return try await api.query(
            "detentionAccessorials.getActiveDetentions",
            input: Input(limit: limit, offset: 0)
        )
    }

    // MARK: - History

    struct HistoryEvent: Decodable, Equatable, Identifiable {
        let id: Int
        let loadId: Int?
        let facilityName: String
        let locationType: String
        let arrivalTime: String?
        let departureTime: String?
        let totalMinutes: Int
        let freeTimeMinutes: Int
        let billableMinutes: Int
        let totalCharge: Double
        let status: String?
        let billingStatus: String?
        let carrierName: String?
        let shipperName: String?
        let cargoType: String?
        let createdAt: String?
    }

    struct HistoryResponse: Decodable {
        let events: [HistoryEvent]
        let total: Int
    }

    /// `detentionAccessorials.getDetentionHistory` — past detention
    /// claims with billingStatus rollup ("paid" | "invoiced" |
    /// "disputed" | "pending").
    func getHistory(
        status: String? = nil,
        facilityName: String? = nil,
        limit: Int = 50
    ) async throws -> HistoryResponse {
        struct Input: Encodable {
            let status: String?
            let facilityName: String?
            let limit: Int
            let offset: Int
        }
        return try await api.query(
            "detentionAccessorials.getDetentionHistory",
            input: Input(status: status, facilityName: facilityName, limit: limit, offset: 0)
        )
    }

    // MARK: - Dispute

    struct DisputeResult: Decodable, Equatable {
        let success: Bool?
        let claimId: Int?
        let status: String?
        let message: String?
    }

    /// `detentionAccessorials.disputeDetention` — challenge a charge.
    /// Server input field is `claimId` (NOT `detentionId`); the external
    /// argument label stays `detentionId:` for caller compatibility
    /// (§52-C — the old `detentionId` payload failed server zod validation,
    /// making every iOS dispute a dead write on 091/573/577).
    @discardableResult
    func dispute(detentionId: Int, reason: String) async throws -> DisputeResult {
        struct Input: Encodable {
            let claimId: Int
            let reason: String
        }
        return try await api.mutation(
            "detentionAccessorials.disputeDetention",
            input: Input(claimId: detentionId, reason: reason)
        )
    }
}

// MARK: - permitsRouter (092 Me · Permits)
//
// Mirrors `frontend/server/routers/permits.ts`. The driver Me
// surface today reads:
//   - `getSummary`  → {total, active, expiring, expired}
//   - `getActive`   → array of currently-approved permits
//   - `getExpiring` → permits whose expirationDate lands in the
//                     next N days (default 30)
// And writes:
//   - `renew` → push the expirationDate forward
//
// The server's `getActive` and `list` use an unusual "array plus
// summary keys via Object.assign" pattern; when JSON-serialized,
// only the array elements survive. We decode as a plain array.

struct PermitsAPI {
    unowned let api: EusoTripAPI

    // MARK: - Permit shape

    struct Permit: Decodable, Equatable, Identifiable {
        let id: String
        let permitNumber: String?
        /// "trip" | "oversize" | "overweight" | "IRP" | "IFTA" | etc.
        let type: String?
        /// "pending" | "approved" | "denied" | "expired"
        let status: String?
        let states: [String]?
        let origin: String?
        let destination: String?
        let commodity: String?
        let weight: Double?
        let expirationDate: String?
        let fees: Double?
        let createdAt: String?
    }

    // MARK: - Summary

    struct Summary: Decodable, Equatable {
        let total: Int
        let active: Int
        let expiring: Int
        let expired: Int
    }

    /// `permits.getSummary` — counters for the hero strip.
    func getSummary() async throws -> Summary {
        try await api.queryNoInput("permits.getSummary")
    }

    // MARK: - Active

    /// `permits.getActive` — all approved permits sorted by
    /// expirationDate ascending.
    func getActive() async throws -> [Permit] {
        try await api.queryNoInput("permits.getActive")
    }

    // MARK: - Expiring

    struct ExpiringPermit: Decodable, Equatable, Identifiable {
        let id: String
        let permitNumber: String?
        let type: String?
        let expirationDate: String?
        let daysRemaining: Int
        let states: [String]?
    }

    /// `permits.getExpiring` — permits expiring within the window
    /// (server default 30 days). Use for the "needs attention"
    /// section and renewal nudges.
    func getExpiring(days: Int = 30) async throws -> [ExpiringPermit] {
        struct Input: Encodable { let days: Int }
        return try await api.query(
            "permits.getExpiring",
            input: Input(days: days)
        )
    }

    // MARK: - Renew

    struct RenewResult: Decodable, Equatable {
        let success: Bool?
        let permitId: String?
    }

    /// `permits.renew` — push the expirationDate to
    /// `requestedEndDate` (ISO yyyy-MM-dd). Server may flip status
    /// back to `pending` for re-approval depending on permit type.
    func renew(
        permitId: String,
        requestedEndDate: String,
        notes: String? = nil
    ) async throws -> RenewResult {
        struct Input: Encodable {
            let permitId: String
            let requestedEndDate: String
            let notes: String?
        }
        return try await api.mutation(
            "permits.renew",
            input: Input(
                permitId: permitId,
                requestedEndDate: requestedEndDate,
                notes: notes
            )
        )
    }
}

// MARK: - driverQualificationRouter (093 Me · DQ File)
//
// Mirrors `frontend/server/routers/driverQualification.ts`. The
// driver's own DQ file — CDL, medical card, hazmat endorsement,
// TWIC, drug tests, employment history, annual reviews — gated
// under a single compliance score.
//
// Expiry tracking: `getExpiringItems` watches four
// driver-row columns (licenseExpiry / medicalCardExpiry /
// hazmatExpiry / twicExpiry) plus the certifications table. The
// server returns a flat array with type + expiresAt + daysRemaining
// so the view can render one combined "needs attention" list
// without joining across sources.

struct DriverQualificationAPI {
    unowned let api: EusoTripAPI

    // MARK: - Overview

    struct DocumentsSummary: Decodable, Equatable {
        let total: Int
        let valid: Int
        let expiringSoon: Int
        let expired: Int
        let missing: Int
    }

    struct Overview: Decodable, Equatable {
        let driverId: String
        let driverName: String?
        let hireDate: String?
        let status: String
        let complianceScore: Int
        let documents: DocumentsSummary
        let lastAudit: String?
        let nextAudit: String?
    }

    /// `driverQualification.getOverview` — single-driver DQ file
    /// summary. Requires the driver's user id.
    func getOverview(driverId: String) async throws -> Overview {
        struct Input: Encodable { let driverId: String }
        return try await api.query(
            "driverQualification.getOverview",
            input: Input(driverId: driverId)
        )
    }

    // MARK: - Documents

    struct DQDocument: Decodable, Equatable, Identifiable {
        let id: String
        /// CDL | medical_card | hazmat | twic | drug_test | mvr | etc.
        let type: String
        let name: String?
        /// "valid" | "expired" | "pending" | ...
        let status: String?
        let uploadedAt: String?
        let expiresAt: String?
        let required: Bool?
        let regulation: String?
    }

    struct DocumentsResponse: Decodable {
        let documents: [DQDocument]
        let total: Int
    }

    /// `driverQualification.getDocuments` — all DQ docs for the
    /// driver, newest first. Optional type/status filters.
    func getDocuments(
        driverId: String,
        type: String? = nil,
        status: String? = nil
    ) async throws -> DocumentsResponse {
        struct Input: Encodable {
            let driverId: String
            let type: String?
            let status: String?
        }
        return try await api.query(
            "driverQualification.getDocuments",
            input: Input(driverId: driverId, type: type, status: status)
        )
    }

    // MARK: - Expiring items

    struct ExpiringItem: Decodable, Equatable, Identifiable {
        let driverId: Int
        let type: String
        let expiresAt: String
        let daysRemaining: Int

        /// Composite id stable across renders (server doesn't ship
        /// an id on these rows — they're synthesized from multiple
        /// driver-row columns + certifications rows).
        var id: String { "\(driverId)-\(type)-\(expiresAt)" }
    }

    /// `driverQualification.getExpiringItems` — company-scoped
    /// watchlist of CDL / medical / hazmat / TWIC / cert expiries
    /// within `daysAhead` (default 60).
    func getExpiringItems(daysAhead: Int = 60) async throws -> [ExpiringItem] {
        struct Input: Encodable { let daysAhead: Int }
        return try await api.query(
            "driverQualification.getExpiringItems",
            input: Input(daysAhead: daysAhead)
        )
    }

    // MARK: - Mutations (Catalyst 322 Documents · upload + update status)

    struct UploadDocumentResult: Decodable {
        let documentId: String
        let uploadedBy: Int?
        let uploadedAt: String?
    }

    /// `driverQualification.uploadDocument` (driverQualification.ts:64).
    /// Server-side only stores metadata (type / name / expiresAt /
    /// notes) — the file binary upload is a separate flow handled by
    /// `documentManagement.uploadDocument` when needed. Use this
    /// procedure for "record-keeping" entries (catalyst noting a
    /// medical card was filed offline, etc.).
    func uploadDocument(
        driverId: String,
        type: String,
        name: String,
        expiresAt: String? = nil,
        notes: String? = nil
    ) async throws -> UploadDocumentResult {
        struct Input: Encodable {
            let driverId: String
            let type: String
            let name: String
            let expiresAt: String?
            let notes: String?
        }
        return try await api.mutation(
            "driverQualification.uploadDocument",
            input: Input(driverId: driverId, type: type, name: name, expiresAt: expiresAt, notes: notes)
        )
    }

    struct UpdateDocumentResult: Decodable {
        let success: Bool?
        let documentId: String?
        let updatedAt: String?
    }

    /// `driverQualification.updateDocument` — flips a document's
    /// status (`valid` / `expiring_soon` / `expired` / `pending` /
    /// `missing`) or sets/extends its `expiresAt`. Catalyst 322 row
    /// detail sheet's "Mark expired" / "Mark valid" buttons call here.
    func updateDocument(
        documentId: String,
        status: String? = nil,
        expiresAt: String? = nil,
        notes: String? = nil
    ) async throws -> UpdateDocumentResult {
        struct Input: Encodable {
            let documentId: String
            let status: String?
            let expiresAt: String?
            let notes: String?
        }
        return try await api.mutation(
            "driverQualification.updateDocument",
            input: Input(documentId: documentId, status: status, expiresAt: expiresAt, notes: notes)
        )
    }
}

// MARK: - fuelManagementRouter (094 Me · Fuel Cards)
//
// Mirrors `frontend/server/routers/fuelManagement.ts`. The driver
// Me surface today exposes:
//   - `getFuelDashboard`      — month-over-month spend + MPG +
//                               cost-per-mile counters for the hero.
//   - `getFuelCardManagement` — company-scoped fuel cards. The
//                               driver view narrows client-side
//                               to their own driverId.
// Mutations (setFuelCardLimits, investigateFuelAnomaly) ship in
// follow-up bricks — this screen is read + glance only.

struct FuelManagementAPI {
    unowned let api: EusoTripAPI

    // MARK: - Dashboard

    struct FuelTrends: Decodable, Equatable {
        let spendChange: Double
        let mpgChange: Double
        let costPerMileChange: Double
    }

    struct MonthSpend: Decodable, Equatable, Identifiable {
        let month: String
        let amount: Double
        var id: String { month }
    }

    struct Dashboard: Decodable, Equatable {
        let totalSpend: Double
        let avgMpg: Double
        let fuelCostPerMile: Double
        let totalGallons: Double
        let totalMiles: Double
        let transactionCount: Int
        let avgPricePerGallon: Double
        let trends: FuelTrends
        let monthlySpend: [MonthSpend]
    }

    /// `fuelManagement.getFuelDashboard` — spend + MPG + cost/mile
    /// over the selected period. Server defaults to "month."
    func getDashboard(period: String = "month") async throws -> Dashboard {
        struct Input: Encodable { let period: String }
        return try await api.query(
            "fuelManagement.getFuelDashboard",
            input: Input(period: period)
        )
    }

    // MARK: - Fuel cards

    struct FuelCard: Decodable, Equatable, Identifiable {
        let id: String
        /// Server masks all but last 4 digits.
        let cardNumber: String
        let cardType: String?
        /// "active" | "suspended" | "cancelled"
        let status: String?
        let driverName: String?
        let driverId: Int?
        let dailyLimit: Double
        let monthlyLimit: Double
        let dailySpent: Double
        let monthlySpent: Double
        let totalSpent: Double
        let fuelOnly: Bool?
        let lastUsed: String?
        let expirationDate: String?
    }

    struct FuelCardSummary: Decodable, Equatable {
        let total: Int
        let active: Int
        let suspended: Int
        let totalSpent: Double
        let monthlyLimit: Double
    }

    struct FuelCardsResponse: Decodable {
        let cards: [FuelCard]
        let summary: FuelCardSummary
    }

    /// `fuelManagement.getFuelCardManagement` — all company fuel
    /// cards (admin view). Driver's personal Me screen filters to
    /// just their own `driverId` before rendering.
    func getFuelCards(status: String = "all") async throws -> FuelCardsResponse {
        struct Input: Encodable {
            let status: String
            let limit: Int
        }
        return try await api.query(
            "fuelManagement.getFuelCardManagement",
            input: Input(status: status, limit: 50)
        )
    }
}

// MARK: - ratesRouter (095 Me · Rate Intel)
//
// Mirrors `frontend/server/routers/rates.ts`. Driver Me surface:
//   - `getTrends`       — rate delta vs. prior window + short-
//                         horizon forecast. Optional equipment /
//                         region filters. The hero of the screen.
//   - `getMarketRates`  — per-lane breakdown with history. Reserved
//                         for the "Look up a lane" drilldown.

struct RatesAPI {
    unowned let api: EusoTripAPI

    // MARK: - Trends

    struct Forecast: Decodable, Equatable {
        let nextWeek: Double
        let nextMonth: Double
        /// 0.0–1.0 — server's own model confidence.
        let confidence: Double
    }

    struct TrendFactor: Decodable, Equatable, Identifiable {
        let factor: String?
        let impact: String?
        let description: String?

        var id: String { factor ?? UUID().uuidString }
    }

    struct Trends: Decodable, Equatable {
        let period: String
        let currentAvg: Double
        let previousAvg: Double
        let changePercent: Double
        /// "up" | "down" | "stable"
        let trend: String
        let forecast: Forecast
        let factors: [TrendFactor]
    }

    enum Period: String, CaseIterable, Identifiable {
        case week, month, quarter, year
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    enum Equipment: String, CaseIterable, Identifiable {
        case any
        case dry_van, reefer, flatbed, stepdeck, tanker, lowboy, container

        var id: String { rawValue }
        var label: String {
            switch self {
            case .any:       return "Any"
            case .dry_van:   return "Dry Van"
            case .reefer:    return "Reefer"
            case .flatbed:   return "Flatbed"
            case .stepdeck:  return "Step Deck"
            case .tanker:    return "Tanker"
            case .lowboy:    return "Lowboy"
            case .container: return "Container"
            }
        }
    }

    /// `rates.getTrends` — rate change + forecast over the
    /// selected window. Pass equipment as `nil` to let the server
    /// aggregate across all equipment types.
    func getTrends(
        equipment: String? = nil,
        region: String? = nil,
        period: Period = .month
    ) async throws -> Trends {
        struct Input: Encodable {
            let equipment: String?
            let region: String?
            let period: String
        }
        return try await api.query(
            "rates.getTrends",
            input: Input(
                equipment: equipment,
                region: region,
                period: period.rawValue
            )
        )
    }

    // MARK: - Lane benchmark (above-market meter)

    /// `rates.compareLaneRate` — server-canonical "above market"
    /// meter the LoadDetailSheet renders next to the posted rate.
    /// Looks at the last `lookbackDays` of delivered loads on the
    /// same origin→dest state pair within ±25% of the distance and
    /// returns the lane percentile + min/avg/max RPM. When fewer than
    /// 3 comparable loads are found, the server falls back to a
    /// distance-banded national benchmark (annotated via
    /// `source: "national_benchmark"`) so the meter still renders a
    /// real number rather than going blank.
    struct LaneComparison: Decodable, Equatable {
        let lane: String
        let yourRate: Double
        let yourRPM: Double
        let distance: Double
        let marketAvgRPM: Double
        let marketMinRPM: Double
        let marketMaxRPM: Double
        let percentile: Int
        /// "ABOVE_MARKET" | "AT_MARKET" | "BELOW_MARKET"
        let position: String
        let sampleSize: Int
        let savingsVsAvg: Double
        let recommendation: String
        /// "platform_data" | "national_benchmark" | "gemini"
        let source: String
        /// 2026-05-19 — mode-aware unit + transport mode echoed back
        /// by the server. Optional for back-compat with older deploys
        /// that haven't shipped the rewrite yet.
        let unit: String?
        let unitLong: String?
        let transportMode: String?
    }

    func compareLaneRate(
        originState: String,
        destState: String,
        rate: Double,
        distance: Double,
        cargoType: String? = nil,
        lookbackDays: Int = 90,
        transportMode: String = "truck",
        rateUnit: String? = nil,
        commodity: String? = nil
    ) async throws -> LaneComparison {
        struct Input: Encodable {
            let originState: String
            let destState: String
            let rate: Double
            let distance: Double
            let cargoType: String?
            let lookbackDays: Int
            let transportMode: String
            let rateUnit: String?
            let commodity: String?
        }
        return try await api.query(
            "rates.compareLaneRate",
            input: Input(
                originState: originState,
                destState: destState,
                rate: rate,
                distance: distance,
                cargoType: cargoType,
                lookbackDays: lookbackDays,
                transportMode: transportMode,
                rateUnit: rateUnit,
                commodity: commodity
            )
        )
    }
}

// MARK: - loadBiddingRouter
//
// Mirrors `frontend/server/routers/loadBidding.ts`. The web platform's
// bid-chain surface — drivers / catalysts call `submit` to accept a
// posted rate or open a counter chain. Counter-offers go through
// `counter` with the parent bidId. Shippers / brokers call `accept`
// or `reject` on their bid review surface.

struct LoadBiddingAPI {
    unowned let api: EusoTripAPI

    /// Result of a `submit` call. `status` is "pending" by default,
    /// "auto_accepted" when a shipper auto-accept rule matched the
    /// bid, or "countered" when the caller is a driver flagging a
    /// non-posted rate as a starting offer.
    struct SubmitAck: Decodable, Equatable {
        let id: Int?
        let status: String
    }

    /// `loadBidding.submit` — one-tap accept at posted rate (Book Now
    /// on the iOS load-detail sheet maps `bidAmount = load.rate`)
    /// or open a chain at a custom rate. Server inserts a `loadBids`
    /// row, fans `BID_RECEIVED` to the shipper's USER channel, and
    /// runs the bidder's bid through the auto-accept rules.
    @discardableResult
    func submit(
        loadId: Int,
        bidAmount: Double,
        rateType: String = "flat",
        equipmentType: String? = nil,
        estimatedPickup: String? = nil,
        estimatedDelivery: String? = nil,
        transitTimeDays: Int? = nil,
        fuelSurchargeIncluded: Bool? = nil,
        accessorialsIncluded: [String]? = nil,
        conditions: String? = nil,
        agreementId: Int? = nil,
        expiresInHours: Int = 24
    ) async throws -> SubmitAck {
        struct Input: Encodable {
            let loadId: Int
            let bidAmount: Double
            let rateType: String
            let equipmentType: String?
            let estimatedPickup: String?
            let estimatedDelivery: String?
            let transitTimeDays: Int?
            let fuelSurchargeIncluded: Bool?
            let accessorialsIncluded: [String]?
            let conditions: String?
            let agreementId: Int?
            let expiresInHours: Int
        }
        return try await api.mutation(
            "loadBidding.submit",
            input: Input(
                loadId: loadId,
                bidAmount: bidAmount,
                rateType: rateType,
                equipmentType: equipmentType,
                estimatedPickup: estimatedPickup,
                estimatedDelivery: estimatedDelivery,
                transitTimeDays: transitTimeDays,
                fuelSurchargeIncluded: fuelSurchargeIncluded,
                accessorialsIncluded: accessorialsIncluded,
                conditions: conditions,
                agreementId: agreementId,
                expiresInHours: expiresInHours
            )
        )
    }

    /// `loadBidding.counter` — counter an existing bid in a chain.
    /// Marks the parent bid as `countered`, inserts a fresh row at
    /// `bidRound = parent.round + 1`, fans the counter event to the
    /// other party. Used when the driver receives a shipper counter
    /// and wants to push back rather than accept.
    @discardableResult
    func counter(
        parentBidId: Int,
        loadId: Int,
        counterAmount: Double,
        rateType: String = "flat",
        conditions: String? = nil,
        expiresInHours: Int = 24
    ) async throws -> SubmitAck {
        struct Input: Encodable {
            let parentBidId: Int
            let loadId: Int
            let counterAmount: Double
            let rateType: String
            let conditions: String?
            let expiresInHours: Int
        }
        return try await api.mutation(
            "loadBidding.counter",
            input: Input(
                parentBidId: parentBidId,
                loadId: loadId,
                counterAmount: counterAmount,
                rateType: rateType,
                conditions: conditions,
                expiresInHours: expiresInHours
            )
        )
    }

    /// `loadBidding.withdraw` — drop a still-pending bid the driver
    /// changed their mind on. Server flips status to `withdrawn`
    /// without notifying the counterparty.
    @discardableResult
    func withdraw(bidId: Int) async throws -> SubmitAck {
        struct Input: Encodable { let bidId: Int }
        return try await api.mutation(
            "loadBidding.withdraw",
            input: Input(bidId: bidId)
        )
    }

    /// `loadBidding.getMyBids` — bids the caller has placed.
    /// Used by the iOS My Bids surface and the post-Book ack to
    /// confirm the bid landed in the chain.
    struct MyBid: Decodable, Equatable, Identifiable {
        let id: Int
        let loadId: Int
        let bidAmount: String?
        let rateType: String?
        let bidRound: Int?
        let status: String
        let createdAt: String?
        let respondedAt: String?
    }

    func getMyBids(limit: Int = 50) async throws -> [MyBid] {
        struct Input: Encodable { let limit: Int }
        return try await api.query(
            "loadBidding.getMyBids",
            input: Input(limit: limit)
        )
    }

    /// MyBids envelope returned by the server when filtering — the
    /// raw projection wraps the rows in `{ bids, total }`. The
    /// flat-array variant above remains for legacy call sites that
    /// expect the un-enveloped shape.
    struct MyBidsEnvelope: Decodable {
        let bids: [MyBid]
        let total: Int
    }

    /// Filter my bids by status. Used by the driver counter-receive
    /// inbox (Phase 4 of the 8000-scenario parity audit) — pulls
    /// status='countered' rows so the driver sees every active
    /// counter-from-shipper awaiting their action.
    func getMyBids(
        status: String,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> MyBidsEnvelope {
        struct Input: Encodable {
            let status: String
            let limit: Int
            let offset: Int
        }
        return try await api.query(
            "loadBidding.getMyBids",
            input: Input(status: status, limit: limit, offset: offset)
        )
    }

    /// One row in the multi-round counter chain. Mirrors the verbatim
    /// `loadBids` row projection at `loadBidding.ts:604` (raw table
    /// select). Driver-side bid detail (109 MeBidDetail) walks rounds
    /// in chronological order and resolves the latest unresolved row
    /// to decide which CTAs to render.
    struct ChainRow: Decodable, Identifiable, Hashable {
        let id: Int
        let loadId: Int
        let bidderUserId: Int?
        let bidderCompanyId: Int?
        let bidderRole: String?
        let bidAmount: String?
        let rateType: String?
        let parentBidId: Int?
        let bidRound: Int?
        let equipmentType: String?
        let estimatedPickup: String?
        let estimatedDelivery: String?
        let transitTimeDays: Int?
        let fuelSurchargeIncluded: Bool?
        let conditions: String?
        let isAutoAccepted: Bool?
        let agreementId: Int?
        let status: String?
        let rejectionReason: String?
        let expiresAt: String?
        let respondedAt: String?
        let respondedBy: Int?
        let createdAt: String?
        let updatedAt: String?
    }

    /// `loadBidding.getBidChain` — full thread of bids + counters for
    /// a load. Server orders by (bidRound asc, createdAt asc) so the
    /// caller can render top-down chronological.
    func getBidChain(loadId: Int, rootBidId: Int? = nil) async throws -> [ChainRow] {
        struct Input: Encodable {
            let loadId: Int
            let rootBidId: Int?
        }
        return try await api.query(
            "loadBidding.getBidChain",
            input: Input(loadId: loadId, rootBidId: rootBidId)
        )
    }

    /// `loadBidding.accept` — accept a bid (or a shipper's counter
    /// when called by the driver). Server runs the FMCSA safety-rating
    /// + operating-authority compliance gate before flipping the bid
    /// to `accepted` and the load to `assigned`.
    @discardableResult
    func accept(bidId: Int) async throws -> SubmitAck {
        struct Input: Encodable { let bidId: Int }
        return try await api.mutation(
            "loadBidding.accept",
            input: Input(bidId: bidId)
        )
    }

    /// `loadBidding.reject` — decline a bid (shipper-side action on
    /// driver bids, or driver-side decline of a shipper counter).
    /// Server flips the bid to `rejected`, stores the optional reason,
    /// and emits a `bid_rejected` notification to the bidder.
    @discardableResult
    func reject(bidId: Int, reason: String? = nil) async throws -> SubmitAck {
        struct Input: Encodable {
            let bidId: Int
            let reason: String?
        }
        return try await api.mutation(
            "loadBidding.reject",
            input: Input(bidId: bidId, reason: reason)
        )
    }

    // MARK: - Auto-Accept Rules

    /// One auto-accept rule. Mirrors the verbatim
    /// `bidAutoAcceptRules` row at `schema.ts`. Each is a set of
    /// criteria that, when ALL satisfied by an incoming bid, flips
    /// the bid to `auto_accepted` server-side without the user
    /// having to react. Decimals serialize as String through Drizzle.
    struct AutoAcceptRule: Decodable, Identifiable, Hashable {
        let id: Int
        let userId: Int?
        let companyId: Int?
        let name: String
        let maxRate: String?
        let maxRatePerMile: String?
        let minCatalystRating: String?
        let requiredInsuranceMin: String?
        let requiredEquipmentTypes: [String]?
        let requiredHazmat: Bool?
        let maxTransitDays: Int?
        let preferredCatalystIds: [Int]?
        let originStates: [String]?
        let destinationStates: [String]?
        let isActive: Bool?
        let createdAt: String?
    }

    struct CreateRuleAck: Decodable, Hashable {
        let id: Int?
        let success: Bool?
    }

    struct ToggleAck: Decodable, Hashable {
        let success: Bool?
    }

    struct DeleteAck: Decodable, Hashable {
        let success: Bool?
    }

    func listAutoAcceptRules() async throws -> [AutoAcceptRule] {
        try await api.queryNoInput("loadBidding.listAutoAcceptRules")
    }

    func createAutoAcceptRule(
        name: String,
        maxRate: Double? = nil,
        maxRatePerMile: Double? = nil,
        minCatalystRating: Double? = nil,
        requiredInsuranceMin: Double? = nil,
        requiredEquipmentTypes: [String]? = nil,
        requiredHazmat: Bool? = nil,
        maxTransitDays: Int? = nil,
        preferredCatalystIds: [Int]? = nil,
        originStates: [String]? = nil,
        destinationStates: [String]? = nil
    ) async throws -> CreateRuleAck {
        struct Input: Encodable {
            let name: String
            let maxRate: Double?
            let maxRatePerMile: Double?
            let minCatalystRating: Double?
            let requiredInsuranceMin: Double?
            let requiredEquipmentTypes: [String]?
            let requiredHazmat: Bool?
            let maxTransitDays: Int?
            let preferredCatalystIds: [Int]?
            let originStates: [String]?
            let destinationStates: [String]?
        }
        return try await api.mutation(
            "loadBidding.createAutoAcceptRule",
            input: Input(
                name: name,
                maxRate: maxRate,
                maxRatePerMile: maxRatePerMile,
                minCatalystRating: minCatalystRating,
                requiredInsuranceMin: requiredInsuranceMin,
                requiredEquipmentTypes: requiredEquipmentTypes,
                requiredHazmat: requiredHazmat,
                maxTransitDays: maxTransitDays,
                preferredCatalystIds: preferredCatalystIds,
                originStates: originStates,
                destinationStates: destinationStates
            )
        )
    }

    @discardableResult
    func toggleAutoAcceptRule(id: Int, isActive: Bool) async throws -> ToggleAck {
        struct Input: Encodable {
            let id: Int
            let isActive: Bool
        }
        return try await api.mutation(
            "loadBidding.toggleAutoAcceptRule",
            input: Input(id: id, isActive: isActive)
        )
    }

    @discardableResult
    func deleteAutoAcceptRule(id: Int) async throws -> DeleteAck {
        struct Input: Encodable { let id: Int }
        return try await api.mutation(
            "loadBidding.deleteAutoAcceptRule",
            input: Input(id: id)
        )
    }
}

// MARK: - ergRouter (096 Me · ERG Hazmat Lookup)
//
// Mirrors `frontend/server/routers/erg.ts`. This is the driver's
// wrist + phone copy of the Emergency Response Guidebook that
// 49 CFR 172.604 requires to be in the cab whenever hazardous
// materials are being transported. The server is backed by the
// canonical ERG material tables + guide pages; iOS renders the
// lookup + guide detail + emergency contact strip.
//
// Procs surfaced today:
//   - `search`                — typeahead by name or UN
//   - `searchByUN`            — full detail for a UN number
//   - `getEmergencyContacts`  — CHEMTREC + NRC + Poison + 911

struct ErgAPI {
    unowned let api: EusoTripAPI

    // MARK: - Search

    struct SearchHit: Decodable, Equatable, Identifiable {
        let unNumber: String
        let name: String
        let guide: Int
        let hazardClass: String
        let isTIH: Bool?
        let isWR: Bool?
        let alternateNames: [String]?
        let placardName: String

        var id: String { unNumber }
    }

    struct SearchResponse: Decodable {
        let results: [SearchHit]
        let count: Int
    }

    /// `erg.search` — typeahead by partial UN number or material
    /// name. Short queries (<2 chars) return empty server-side so
    /// we don't hammer with single-letter strokes.
    func search(query: String, limit: Int = 10) async throws -> SearchResponse {
        struct Input: Encodable {
            let query: String
            let limit: Int
        }
        return try await api.query(
            "erg.search",
            input: Input(query: query, limit: limit)
        )
    }

    // MARK: - Full detail

    struct ProtectiveDistance: Decodable, Equatable {
        let smallSpill: PDRow?
        let largeSpill: PDRow?

        struct PDRow: Decodable, Equatable {
            let isolate: String?
            let downwindDay: String?
            let downwindNight: String?
        }
    }

    struct GuideDetail: Decodable, Equatable {
        let title: String?
        let potentialHazards: [String]?
        let publicSafety: [String]?
        let emergencyResponse: [String]?
    }

    struct MaterialDetail: Decodable, Equatable {
        let found: Bool
        let unNumber: String?
        let name: String?
        let guideNumber: Int?
        let hazardClass: String?
        let placard: String?
        let placardColor: String?
        let isTIH: Bool?
        let isWR: Bool?
        let alternateNames: [String]?
        let guide: GuideDetail?
        let guideFull: GuideFull?
        let protectiveDistance: ProtectiveDistance?
    }

    /// Full structured ERG handbook data — every field the canonical
    /// guide page lists, decoded directly so iOS can lay out health
    /// vs fire/explosion separately, isolation distances as hero
    /// stats, fire small/large/tank in 3 columns, etc. Server emits
    /// this alongside the back-compat flat `guide` block.
    struct GuideFull: Decodable, Equatable {
        let title: String?
        let health: [String]
        let fireExplosion: [String]
        let isolationDistanceMeters: Int?
        let isolationDistanceFeet: Int?
        let fireIsolationMeters: Int?
        let fireIsolationFeet: Int?
        let protectiveClothing: String?
        let evacuationNotes: String?
        let fireSmall: [String]
        let fireLarge: [String]
        let fireTank: [String]
        let spillGeneral: [String]
        let spillSmall: [String]
        let spillLarge: [String]
        let firstAid: [String]
    }

    /// `erg.searchByUN` — full detail + emergency response steps +
    /// TIH initial isolation / protective action distances.
    func searchByUN(_ unNumber: String) async throws -> MaterialDetail {
        struct Input: Encodable { let unNumber: String }
        return try await api.query(
            "erg.searchByUN",
            input: Input(unNumber: unNumber)
        )
    }

    // MARK: - Emergency contacts

    struct EmergencyContact: Decodable, Equatable {
        let name: String
        let phone: String
        let description: String
        let international: String?
    }

    struct EmergencyContactsResponse: Decodable, Equatable {
        let chemtrec: EmergencyContact
        let national: EmergencyContact
        let poison: EmergencyContact
        let emergency: EmergencyContact
    }

    /// `erg.getEmergencyContacts` — CHEMTREC + National Response
    /// Center + Poison Control + 911. Drivers hauling hazmat
    /// should have these at a tap, per §172.704.
    func getEmergencyContacts() async throws -> EmergencyContactsResponse {
        try await api.queryNoInput("erg.getEmergencyContacts")
    }
}

// MARK: - ratingsRouter (097 Me · Ratings)
//
// Mirrors `frontend/server/routers/ratings.ts`. Driver Me surface:
//   - `getMySummary` → roles × {overall rating, review count, trend}
//   - `getReviews`    → paginated reviews for a given entity (for
//                       the driver's Me screen: entityType="user",
//                       entityId=signed-in user id)
//   - `respond`       → reply to a review
//   - `report`        → flag an abusive / false review

struct RatingsAPI {
    unowned let api: EusoTripAPI

    // MARK: - Summary

    struct RoleSummary: Decodable, Equatable {
        let overallRating: Double
        let totalReviews: Int
        /// "up" | "down" | "stable"
        let recentTrend: String
    }

    struct MySummary: Decodable, Equatable {
        let asDriver: RoleSummary
        let asCatalyst: RoleSummary
        let givenThisMonth: Int
        let receivedThisMonth: Int
    }

    /// `ratings.getMySummary` — per-role summaries for the driver's
    /// Me · Ratings header.
    func getMySummary() async throws -> MySummary {
        try await api.queryNoInput("ratings.getMySummary")
    }

    // MARK: - Reviews

    enum Sort: String, CaseIterable, Identifiable {
        case recent, highest, lowest
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    struct Review: Decodable, Equatable, Identifiable {
        let id: String
        let score: Double
        let category: String?
        let comment: String
        let reviewerName: String?
        let loadId: String?
        let createdAt: String?
    }

    struct ReviewsResponse: Decodable {
        let reviews: [Review]
        let total: Int
    }

    /// `ratings.getReviews` — paginated reviews for an entity. The
    /// driver's own reviews pass `entityType: "user"` with their
    /// own id.
    func getReviews(
        entityType: String,
        entityId: String,
        sort: Sort = .recent,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> ReviewsResponse {
        struct Input: Encodable {
            let entityType: String
            let entityId: String
            let sortBy: String
            let limit: Int
            let offset: Int
        }
        return try await api.query(
            "ratings.getReviews",
            input: Input(
                entityType: entityType,
                entityId: entityId,
                sortBy: sort.rawValue,
                limit: limit,
                offset: offset
            )
        )
    }

    // MARK: - Submit (rate the counterparty)

    /// Acknowledge envelope from `ratings.submit`. Server returns the
    /// new row id + the timestamp it was persisted. Used by the
    /// post-delivery rating-prompt sheets on both shipper and driver.
    struct SubmitAck: Decodable, Hashable {
        let id: String?
        let success: Bool?
        let submittedBy: Int?
        let submittedAt: String?
    }

    /// Categories the server accepts in the per-axis ratings map.
    /// Mirrors `ratingCategorySchema` on the backend (ratings.ts).
    /// Bound here as a string set so callers can pass a
    /// `[String: Int]` without a separate enum dependency.
    static let categoryKeys: Set<String> = [
        "communication", "professionalism", "delivery_quality",
        "timeliness", "equipment_condition", "payment_promptness"
    ]

    /// `ratings.submit` — caller leaves a 1-5 overall (required) +
    /// optional per-axis scores + optional 500-char comment +
    /// optional anonymity. Server enforces no-self-rating + one
    /// rating per (fromUserId × toUserId × loadId) tuple. Wired to
    /// the post-delivery prompt sheets on both shipper and driver.
    @discardableResult
    func submit(
        entityType: String,
        entityId: String,
        loadId: String,
        overallRating: Int,
        categories: [String: Int]? = nil,
        comment: String? = nil,
        anonymous: Bool = false
    ) async throws -> SubmitAck {
        struct Input: Encodable {
            let entityType: String
            let entityId: String
            let loadId: String
            let overallRating: Int
            let categories: [String: Int]?
            let comment: String?
            let anonymous: Bool
        }
        return try await api.mutation(
            "ratings.submit",
            input: Input(
                entityType: entityType,
                entityId: entityId,
                loadId: loadId,
                overallRating: overallRating,
                categories: categories,
                comment: comment,
                anonymous: anonymous
            )
        )
    }

    // MARK: - Respond / report

    struct RespondResult: Decodable, Equatable {
        let success: Bool?
        let responseId: String?
        let respondedAt: String?
    }

    /// `ratings.respond` — publicly reply to a review (≤500 chars).
    func respond(reviewId: String, response: String) async throws -> RespondResult {
        struct Input: Encodable {
            let reviewId: String
            let response: String
        }
        return try await api.mutation(
            "ratings.respond",
            input: Input(reviewId: reviewId, response: response)
        )
    }

    /// `ratings.report` — report a review for inappropriate content,
    /// false info, spam, harassment, or other reasons.
    struct ReportResult: Decodable, Equatable {
        let success: Bool?
        let reportId: String?
        let reportedAt: String?
    }

    func report(
        reviewId: String,
        reason: String,
        details: String? = nil
    ) async throws -> ReportResult {
        struct Input: Encodable {
            let reviewId: String
            let reason: String
            let details: String?
        }
        return try await api.mutation(
            "ratings.report",
            input: Input(reviewId: reviewId, reason: reason, details: details)
        )
    }
}

// MARK: - emergencyResponseRouter (098 Me · Emergency Ops)
//
// Mirrors `frontend/server/routers/emergencyResponse.ts`. Emergency
// operations (FEMA mobilizations, pipeline-outage fuel surge,
// hurricane evacuations) dispatch mobilization orders to drivers
// with a CDL + hazmat or fuel tanker endorsement. Drivers see
// active calls, accept or decline, and track loads hauled.
//
// Note: server-side this router stores state in-memory module
// arrays (not DB); an in-flight mobilization resets on server
// restart. The iOS surface still wires real endpoints — the
// server-authoritative view is what the driver sees, placeholder-
// free.

struct EmergencyAPI {
    unowned let api: EusoTripAPI

    // MARK: - Operation + order + response shapes
    //
    // Keep these forgiving — the server returns a mix of typed
    // TypeScript shapes that evolve. All fields decoded as
    // optional so a new server field never crashes the client.

    struct Operation: Decodable, Equatable, Identifiable {
        let id: String
        let name: String?
        let status: String?
        let severity: String?
        let type: String?
        let declaredAt: String?
        let location: String?
        let estimatedEnd: String?
    }

    struct MobilizationOrder: Decodable, Equatable, Identifiable {
        let id: String
        let operationId: String
        /// Summary of the ask — regions, capacity, commodity.
        let title: String?
        let description: String?
        let commodity: String?
        let region: String?
        let hazmatRequired: Bool?
        let payPerMileCents: Int?
        let surgeMultiplier: Double?
        let deadline: String?
        let createdAt: String?
        let myResponse: MobilizationResponse?
        let operation: Operation?
    }

    struct MobilizationResponse: Decodable, Equatable, Identifiable {
        let id: String
        let mobilizationOrderId: String?
        let operationId: String?
        let status: String?
        let currentState: String?
        let estimatedArrivalMinutes: Int?
        let respondedAt: String?
        let acceptedAt: String?
        let loadsCompleted: Int?
        let milesHauled: Double?
    }

    struct MyMobilizations: Decodable, Equatable {
        let availableOrders: [MobilizationOrder]
        let myActiveResponses: [MobilizationResponse]
        let myCompletedResponses: [MobilizationResponse]
        let totalLoadsCompleted: Int
        let totalMilesHauled: Double
    }

    /// `emergencyResponse.getMyMobilizations` — driver-scoped
    /// available orders + my active + my completed + aggregate stats.
    func getMyMobilizations() async throws -> MyMobilizations {
        try await api.queryNoInput("emergencyResponse.getMyMobilizations")
    }

    // MARK: - Respond / update

    struct RespondResult: Decodable, Equatable {
        let id: String?
        let status: String?
        let acceptedAt: String?
    }

    /// `emergencyResponse.respondToMobilization` — accept or decline
    /// with optional location + ETA.
    func respondToMobilization(
        orderId: String,
        accept: Bool,
        currentState: String? = nil,
        estimatedArrivalMinutes: Int? = nil
    ) async throws -> RespondResult {
        struct Input: Encodable {
            let mobilizationOrderId: String
            let accept: Bool
            let currentState: String?
            let estimatedArrivalMinutes: Int?
        }
        return try await api.mutation(
            "emergencyResponse.respondToMobilization",
            input: Input(
                mobilizationOrderId: orderId,
                accept: accept,
                currentState: currentState,
                estimatedArrivalMinutes: estimatedArrivalMinutes
            )
        )
    }

    /// `emergencyResponse.updateMobilizationStatus` — flip the
    /// driver's response status (EN_ROUTE / ON_SITE / COMPLETED /
    /// ABANDONED).
    func updateStatus(
        responseId: String,
        status: String,
        loadsCompleted: Int? = nil,
        milesHauled: Double? = nil
    ) async throws -> RespondResult {
        struct Input: Encodable {
            let responseId: String
            let status: String
            let loadsCompleted: Int?
            let milesHauled: Double?
        }
        return try await api.mutation(
            "emergencyResponse.updateMobilizationStatus",
            input: Input(
                responseId: responseId,
                status: status,
                loadsCompleted: loadsCompleted,
                milesHauled: milesHauled
            )
        )
    }
}

// MARK: - freightClaimsRouter (099 Me · Freight Claims)
//
// Mirrors `frontend/server/routers/freightClaims.ts`. Driver files
// a claim from the cab when cargo is damaged / lost / short /
// delayed / contaminated. Server auto-maps the claim type onto
// the canonical incident `type` enum (damage→property_damage,
// contamination→hazmat_spill, delay→near_miss, etc.) and creates
// the row; dispatch + safety pick it up from there.

struct FreightClaimsAPI {
    unowned let api: EusoTripAPI

    // MARK: - Claim type

    enum ClaimType: String, CaseIterable, Identifiable, Codable {
        case damage, loss, shortage, delay, contamination
        var id: String { rawValue }
        var label: String {
            switch self {
            case .damage:        return "Damage"
            case .loss:          return "Loss"
            case .shortage:      return "Shortage"
            case .delay:         return "Delay"
            case .contamination: return "Contamination"
            }
        }
        var icon: String {
            switch self {
            case .damage:        return "shippingbox.and.arrow.backward"
            case .loss:          return "xmark.bin"
            case .shortage:      return "minus.rectangle"
            case .delay:         return "clock.badge.exclamationmark"
            case .contamination: return "exclamationmark.triangle"
            }
        }
    }

    // MARK: - Dashboard

    struct Aging: Decodable, Equatable {
        let under30: Int
        let days30to60: Int
        let days60to90: Int
        let over90: Int
    }

    struct Dashboard: Decodable, Equatable {
        let open: Int
        let pending: Int
        let resolved: Int
        let denied: Int
        let totalValue: Double
        let avgResolutionDays: Double
        let aging: Aging
    }

    /// `freightClaims.getClaimsDashboard` — counters + aging
    /// breakdown. Admin-scoped in production; drivers see
    /// company-wide counts which is fine — a driver knowing
    /// "carrier has 4 claims over 90 days" is actionable
    /// information when they push for resolution on theirs.
    func getDashboard() async throws -> Dashboard {
        try await api.queryNoInput("freightClaims.getClaimsDashboard")
    }

    // MARK: - Claim rows

    struct Claim: Decodable, Equatable, Identifiable {
        let id: Int
        let type: String?
        let status: String?
        let description: String?
        let createdAt: String?
        let severity: String?

        /// Stable String id for SwiftUI ForEach.
        var stableId: String { String(id) }
    }

    struct ClaimsResponse: Decodable {
        let claims: [Claim]
        let total: Int
    }

    func getClaims(
        status: String? = nil,
        search: String? = nil,
        limit: Int = 20
    ) async throws -> ClaimsResponse {
        struct Input: Encodable {
            let status: String?
            let search: String?
            let limit: Int
            let offset: Int
        }
        return try await api.query(
            "freightClaims.getClaims",
            input: Input(status: status, search: search, limit: limit, offset: 0)
        )
    }

    // MARK: - File a claim

    struct FileClaimResult: Decodable, Equatable {
        let id: Int?
        let status: String?
        let claimNumber: String?
    }

    func fileClaim(
        loadId: String,
        type: ClaimType,
        amount: Double,
        description: String,
        commodity: String? = nil,
        damageExtent: String? = nil
    ) async throws -> FileClaimResult {
        struct Input: Encodable {
            let loadId: String
            let type: String
            let amount: Double
            let description: String
            let commodity: String?
            let damageExtent: String?
        }
        return try await api.mutation(
            "freightClaims.fileClaim",
            input: Input(
                loadId: loadId,
                type: type.rawValue,
                amount: amount,
                description: description,
                commodity: commodity,
                damageExtent: damageExtent
            )
        )
    }
}

// MARK: - appointmentsRouter (101 Me · Appointments)
//
// Mirrors `frontend/server/routers/appointments.ts`. Each driver
// row comes from the appointments table (scheduledAt in local
// time window). iOS Me surface lists upcoming / today / past +
// offers check-in → start-loading → complete progression.

struct AppointmentsAPI {
    unowned let api: EusoTripAPI

    // MARK: - Status window

    enum Window: String, CaseIterable, Identifiable, Codable {
        case upcoming, today, past
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    // MARK: - Row shape

    struct Appointment: Decodable, Equatable, Identifiable {
        let id: String
        let type: String?
        let loadNumber: String?
        let facilityName: String?
        let address: String?
        let scheduledDate: String?
        let scheduledTime: String?
        /// "scheduled" | "checked_in" | "loading" | "completed" |
        /// "cancelled" etc.
        let status: String?
        let product: String?
        let quantity: Double?
    }

    // MARK: - Summary

    struct Summary: Decodable, Equatable {
        let today: Int
        let completed: Int
        let inProgress: Int
        let upcoming: Int
        let cancelled: Int
    }

    /// `appointments.getSummary` — today's counters + upcoming
    /// count for the hero strip.
    func getSummary() async throws -> Summary {
        try await api.queryNoInput("appointments.getSummary")
    }

    /// `appointments.getMyAppointments` — paginated driver-scoped
    /// list for the selected window.
    func getMyAppointments(window: Window = .upcoming) async throws -> [Appointment] {
        struct Input: Encodable { let status: String }
        return try await api.query(
            "appointments.getMyAppointments",
            input: Input(status: window.rawValue)
        )
    }

    // MARK: - Mutations

    struct SimpleResult: Decodable, Equatable {
        let success: Bool?
        let appointmentId: String?
        let checkInTime: String?
        let queuePosition: Int?
        let estimatedWait: Int?
    }

    /// `appointments.checkIn` — driver arrives at the facility.
    func checkIn(
        appointmentId: String,
        trailerNumber: String? = nil,
        notes: String? = nil
    ) async throws -> SimpleResult {
        struct Input: Encodable {
            let appointmentId: String
            let trailerNumber: String?
            let notes: String?
        }
        return try await api.mutation(
            "appointments.checkIn",
            input: Input(
                appointmentId: appointmentId,
                trailerNumber: trailerNumber,
                notes: notes
            )
        )
    }

    /// `appointments.startLoading` — dock started loading /
    /// unloading. Flips status to `loading`.
    func startLoading(appointmentId: String) async throws -> SimpleResult {
        struct Input: Encodable { let appointmentId: String }
        return try await api.mutation(
            "appointments.startLoading",
            input: Input(appointmentId: appointmentId)
        )
    }

    /// `appointments.complete` — driver pulled out + POD captured.
    func complete(appointmentId: String) async throws -> SimpleResult {
        struct Input: Encodable { let appointmentId: String }
        return try await api.mutation(
            "appointments.complete",
            input: Input(appointmentId: appointmentId)
        )
    }

    /// `appointments.cancel` — cancel with reason.
    func cancel(id: String, reason: String) async throws -> SimpleResult {
        struct Input: Encodable {
            let id: String
            let reason: String
        }
        return try await api.mutation(
            "appointments.cancel",
            input: Input(id: id, reason: reason)
        )
    }

    // MARK: - Phase 10 (Pickup operations) closure

    /// Single appointment row used by the Phase 10 by-load lookup
    /// path. Mirrors verbatim the `appointments.getByLoad` server
    /// projection. Optionals everywhere — caller renders an honest
    /// empty state when the load has no appointment yet.
    struct ByLoadAppointment: Decodable, Hashable {
        let id: String
        let loadId: String?
        let terminalId: String?
        let driverId: String?
        let type: String?
        let status: String?
        let dockNumber: String?
        let scheduledAt: String?
        let createdAt: String?
    }

    /// `appointments.getByLoad` — the most recent appointment for a
    /// load id. Used by the iOS shipper 205 dock-assign sheet AND
    /// by the driver lifecycle screens 014/015/016 to look up the
    /// appointment they need to advance via updateStatus.
    func getByLoad(loadId: String) async throws -> ByLoadAppointment? {
        struct Input: Encodable { let loadId: String }
        return try await api.query(
            "appointments.getByLoad",
            input: Input(loadId: loadId)
        )
    }

    struct AssignDockAck: Decodable, Hashable {
        let success: Bool?
        let id: String?
        let dockNumber: String?
        let assignedAt: String?
    }

    /// `appointments.assignDock` — shipper-of-record (or terminal
    /// manager / dispatch / admin) writes the assigned dock door
    /// directly to the appointments.dockNumber column. Closes the
    /// shipper-side half of Phase 10.
    @discardableResult
    func assignDock(id: String, dockNumber: String) async throws -> AssignDockAck {
        struct Input: Encodable {
            let id: String
            let dockNumber: String
        }
        return try await api.mutation(
            "appointments.assignDock",
            input: Input(id: id, dockNumber: dockNumber)
        )
    }

    /// `appointments.updateStatus` — driver lifecycle screens
    /// 014/015/016 fire this at state transitions so the
    /// appointment record stays in sync with the trip lifecycle
    /// store. Status values: 'scheduled' / 'confirmed' /
    /// 'checked_in' / 'loading' / 'unloading' / 'completed' /
    /// 'cancelled' / 'no_show' (server enum).
    @discardableResult
    func updateStatus(
        id: String,
        status: String,
        notes: String? = nil
    ) async throws -> SimpleResult {
        struct Input: Encodable {
            let id: String
            let status: String
            let notes: String?
            let timestamp: String
        }
        return try await api.mutation(
            "appointments.updateStatus",
            input: Input(
                id: id,
                status: status,
                notes: notes,
                timestamp: ISO8601DateFormatter().string(from: Date())
            )
        )
    }
}

// MARK: - contactsRouter (102 Me · Contacts)
//
// Mirrors `frontend/server/routers/contacts.ts`. Driver's
// contact book — shipper reps, dispatchers, broker agents,
// mechanic partners, fellow drivers. Server joins the `users`
// table with the `companies` table so each row carries company
// context + role.

struct ContactsAPI {
    unowned let api: EusoTripAPI

    // MARK: - Row shape

    struct Address: Decodable, Equatable {
        let city: String?
        let state: String?
    }

    struct Contact: Decodable, Equatable, Identifiable {
        let id: String
        /// "driver" | "shipper" | "catalyst" | "broker" | "dispatcher"
        /// | "other"
        let type: String
        let name: String
        let company: String?
        let email: String?
        let phone: String?
        let address: Address?
        let favorite: Bool
        let lastContact: String?
    }

    // MARK: - Summary

    struct Summary: Decodable, Equatable {
        let total: Int
        let shippers: Int
        let catalysts: Int
        let drivers: Int
    }

    /// `contacts.getSummary` — counters per role for the header strip.
    func getSummary() async throws -> Summary {
        try await api.queryNoInput("contacts.getSummary")
    }

    /// `contacts.list` — paginated + optionally filtered by type /
    /// search / favorite. Returns a flat array (not enveloped).
    func list(
        type: String? = nil,
        search: String? = nil,
        favorite: Bool? = nil,
        limit: Int = 40
    ) async throws -> [Contact] {
        struct Input: Encodable {
            let type: String?
            let search: String?
            let favorite: Bool?
            let limit: Int
            let offset: Int
        }
        return try await api.query(
            "contacts.list",
            input: Input(
                type: type,
                search: search,
                favorite: favorite,
                limit: limit,
                offset: 0
            )
        )
    }

    // MARK: - Mutations

    struct ToggleFavoriteResult: Decodable, Equatable {
        let success: Bool?
        let id: String?
        let favorite: Bool?
    }

    /// `contacts.toggleFavorite` — flip the favorite flag.
    func toggleFavorite(id: String) async throws -> ToggleFavoriteResult {
        struct Input: Encodable { let id: String }
        return try await api.mutation(
            "contacts.toggleFavorite",
            input: Input(id: id)
        )
    }

    struct InteractionResult: Decodable, Equatable {
        let id: String?
        let contactId: String?
        let type: String?
        let date: String?
    }

    /// `contacts.addInteraction` — log a call / email / meeting /
    /// note against a contact.
    func addInteraction(
        contactId: String,
        kind: String,
        notes: String
    ) async throws -> InteractionResult {
        struct Input: Encodable {
            let contactId: String
            let type: String
            let notes: String
        }
        return try await api.mutation(
            "contacts.addInteraction",
            input: Input(contactId: contactId, type: kind, notes: notes)
        )
    }
}

// MARK: - agreementsRouter (103 Me · Agreements)
//
// Mirrors `frontend/server/routers/agreements.ts`. Driver sees
// any agreement where they are party A or B (lease-on, owner-op,
// employment, dispatch service contract, per-load rate agreement,
// etc.). Server stores agreements encrypted + generates Gradient-
// Ink e-signatures on sign().
//
// Note on scope: this covers the MASTER AGREEMENTS system. The
// related laneContracts router (recurring lane commitments)
// filters by shipperId / catalystId / brokerId — no driverId
// column today, so a driver seeing "my dedicated lanes" needs a
// server-side change first. Documented in the Pulse-role-wiring
// doctrine.

struct AgreementsAPI {
    unowned let api: EusoTripAPI

    // MARK: - Stats

    struct Stats: Decodable, Equatable {
        let total: Int
        let active: Int
        let draft: Int
        let negotiating: Int
        let pendingSignature: Int
        let expired: Int
        let totalValue: Double
    }

    /// `agreements.getStats` — counters for the hero. Server
    /// scopes to the signed-in user's party-A / party-B rows.
    func getStats() async throws -> Stats {
        try await api.queryNoInput("agreements.getStats")
    }

    // MARK: - List

    struct Agreement: Decodable, Equatable, Identifiable {
        let id: Int
        let agreementNumber: String?
        let agreementType: String?
        let contractDuration: String?
        /// "draft" | "negotiating" | "pending_signature" |
        /// "active" | "terminated" | "expired"
        let status: String?
        let partyAUserId: Int?
        let partyARole: String?
        let partyBUserId: Int?
        let partyBRole: String?
        let baseRate: Double?
        let rateType: String?
        let paymentTermDays: Int?
        let effectiveDate: String?
        let expirationDate: String?
        let equipmentTypes: [String]?
        let hazmatRequired: Bool?
        let isEncrypted: Bool?
        let createdAt: String?
        let updatedAt: String?
    }

    struct ListResponse: Decodable {
        let agreements: [Agreement]
        let total: Int
    }

    /// `agreements.list` — filter by status / type / duration /
    /// search / partyUserId. Server narrows to the signed-in
    /// user's own agreements unless they're admin.
    func list(
        status: String? = nil,
        type: String? = nil,
        search: String? = nil,
        limit: Int = 40
    ) async throws -> ListResponse {
        struct Input: Encodable {
            let status: String?
            let type: String?
            let search: String?
            let limit: Int
            let offset: Int
        }
        return try await api.query(
            "agreements.list",
            input: Input(
                status: status,
                type: type,
                search: search,
                limit: limit,
                offset: 0
            )
        )
    }

    // MARK: - Sign

    struct SignResult: Decodable, Equatable {
        let success: Bool?
        let agreementId: Int?
        let status: String?
        let signatureHash: String?
    }

    /// `agreements.sign` — apply a Gradient-Ink digital signature.
    /// `signatureData` is a base64-encoded PNG of the driver's
    /// signature stroke; the server hashes it SHA-256 for
    /// verification.
    func sign(
        agreementId: Int,
        signatureBase64: String,
        signatureRole: String,
        signerName: String? = nil,
        signerTitle: String? = nil
    ) async throws -> SignResult {
        struct Input: Encodable {
            let agreementId: Int
            let signatureData: String
            let signatureRole: String
            let signerName: String?
            let signerTitle: String?
        }
        return try await api.mutation(
            "agreements.sign",
            input: Input(
                agreementId: agreementId,
                signatureData: signatureBase64,
                signatureRole: signatureRole,
                signerName: signerName,
                signerTitle: signerTitle
            )
        )
    }
}

// MARK: - loadLifecycleRouter (trip-execution state machine)
//
// Mirrors `frontend/server/routers/loadLifecycle.ts`. This is the
// foundation under the 013–051 trip execution screens. Each screen
// subscribes to the same `TripLifecycleStore` (defined in
// `ViewModels/LiveDataStores.swift`) which reads state from the
// load + available-transitions from this API. Driver actions (tap
// "I've arrived", "Loading", "BOL signed", "Delivered") fire
// `executeTransition` with the appropriate transition id and the
// store refreshes — which means the next screen in the 34-screen
// lifecycle automatically picks up the new state.
//
// The server-side state machine handles guards (HOS compliance,
// hazmat endorsement, BOL present, etc.) and validates the role
// is allowed to perform the transition. iOS never hardcodes the
// next state — it asks the server "what's legal next from here?"
// and renders whatever came back.

struct LoadLifecycleAPI {
    unowned let api: EusoTripAPI

    // MARK: - Transition DTO

    struct Transition: Decodable, Equatable, Identifiable {
        let transitionId: String
        let to: String
        /// Human-readable label for the action button (from the
        /// transition's server definition).
        let label: String?
        /// Guard-failure messages the server precomputed. When
        /// non-empty, the transition is REJECTED and the driver
        /// should see these as a reason on the UI before tap.
        let guardErrors: [String]?
        /// Whether the transition requires capture of location,
        /// photo, BOL data, etc. The UI should prompt before
        /// executing.
        let requiresLocation: Bool?
        let requiresData: Bool?

        var id: String { transitionId }
    }

    /// `loadLifecycle.getAvailableTransitions` — role-filtered
    /// next-hop options + guard evaluation. Returns `[]` when
    /// no legal transitions remain (terminal state).
    func getAvailableTransitions(loadId: String) async throws -> [Transition] {
        struct Input: Encodable { let loadId: String }
        return try await api.query(
            "loadLifecycle.getAvailableTransitions",
            input: Input(loadId: loadId)
        )
    }

    // MARK: - Execute transition

    struct TransitionResult: Decodable, Equatable {
        let success: Bool
        let newState: String?
        let error: String?
        let guardErrors: [String]?
    }

    struct ExecuteLocation: Encodable {
        let lat: Double
        let lng: Double
    }

    struct ComplianceBlock: Encodable {
        let hosCompliant: Bool?
        let hazmatEndorsed: Bool?
        let vehicleInspected: Bool?
        let bolPresent: Bool?
        let runTicketPresent: Bool?
        let podSigned: Bool?
    }

    /// `loadLifecycle.executeTransition` — flip the load's state.
    /// Guarded server-side by the state-machine rules; the caller
    /// should pass the location fix (if the transition requires
    /// one) + any transition-specific `data` payload (BOL id,
    /// POD photo id, damage notes, etc.).
    func executeTransition(
        loadId: String,
        transitionId: String,
        location: ExecuteLocation? = nil,
        data: [String: String]? = nil,
        compliance: ComplianceBlock? = nil
    ) async throws -> TransitionResult {
        struct Input: Encodable {
            let loadId: String
            let transitionId: String
            let location: ExecuteLocation?
            let data: [String: String]?
            let complianceChecks: ComplianceBlock?
        }
        return try await api.mutation(
            "loadLifecycle.executeTransition",
            input: Input(
                loadId: loadId,
                transitionId: transitionId,
                location: location,
                data: data,
                complianceChecks: compliance
            )
        )
    }

    // MARK: - State history

    struct StateTransition: Decodable, Equatable, Identifiable {
        let id: Int
        let fromState: String?
        let toState: String?
        let transitionId: String?
        let triggerType: String?
        let triggerEvent: String?
        let actorName: String?
        let actorRole: String?
        let success: Bool?
        let errorMessage: String?
        let createdAt: String?
    }

    /// `loadLifecycle.getStateHistory` — immutable audit trail of
    /// every transition on this load. Each row carries actor +
    /// trigger + outcome.
    func getStateHistory(loadId: String) async throws -> [StateTransition] {
        struct Input: Encodable { let loadId: String }
        return try await api.query(
            "loadLifecycle.getStateHistory",
            input: Input(loadId: loadId)
        )
    }

    // MARK: - Check-in

    struct CheckInResult: Decodable, Equatable {
        let success: Bool?
        let loadId: String?
        let checkInTime: String?
    }

    /// `loadLifecycle.checkIn` — location-gated arrival confirm.
    /// Server verifies geofence match; on success, auto-fires
    /// the relevant transition (arrive-at-pickup, arrive-at-
    /// receiver, etc.).
    func checkIn(
        loadId: String,
        lat: Double,
        lng: Double,
        stopType: String
    ) async throws -> CheckInResult {
        struct Input: Encodable {
            let loadId: String
            let lat: Double
            let lng: Double
            let stopType: String
        }
        return try await api.mutation(
            "loadLifecycle.checkIn",
            input: Input(
                loadId: loadId,
                lat: lat,
                lng: lng,
                stopType: stopType
            )
        )
    }
}

// MARK: - spectraMatchRouter
//
// Driver-facing surface for crude-oil + product identification.
// Backed verbatim by `frontend/server/routers/spectraMatch.ts`.
// Today's iOS callsites:
//
//   • `031_SpectraMatchVerdict` → `getHistory(limit:)` to render
//     the per-fill sample lane strip.
//   • `030_LoadingInProgress`   → `getHistory(limit: 1)` to render
//     the in-flight Spectra-Match card (target % + last reading).
//
// Added 2026-04-24 (eusotrip-killers ledger-hygiene firing) to
// remove the hardcoded `samples` array in 031. Other procedures
// (identify, identifyWithAI, getLearningStats, askAboutProduct,
// getCrudeTypes, getCrudesByCountry, getCrudeSpecs, saveToRunTicket,
// getTerminalProductCatalog, autoIdentifyFromTerminal,
// getProductMarketContext, getDestinationIntelligence,
// quickDestinationMatch, getPipelineCompatibility,
// getBlendingRecommendations) are reserved for follow-up bricks
// (terminal product catalog, destination intelligence, etc.) and
// will be added when those screens are wired.

struct SpectraMatchAPI {
    unowned let api: EusoTripAPI

    /// One verified spectra-match identification (one BOL signoff
    /// or run-ticket save, one crude/product confirmation). The
    /// shape is mirrored from `spectraMatch.getHistory` in
    /// `frontend/server/routers/spectraMatch.ts:414`.
    struct Identification: Decodable, Identifiable, Hashable {
        /// Server-assigned identifier in `SM-NNN` form.
        let id: String
        /// ISO-8601 timestamp of the verifying BOL signoff /
        /// run-ticket save.
        let timestamp: String
        /// Resolved product / crude name (e.g. "Bakken Light").
        let crudeType: String
        /// 0–1 match confidence at the time the load was signed.
        let confidence: Double
        /// API gravity (degrees) recorded at sign-off.
        let apiGravity: Double
        /// BS&W percent recorded at sign-off.
        let bsw: Double
        /// Server-side load handle (`LD-<id>`).
        let loadId: String
        /// "ESANG AI" if AI-verified, "System" if static-only.
        let verifiedBy: String
        /// Static category bucket (sweet/sour/medium-sour/etc.).
        let category: String
    }

    /// Top-level envelope returned by `spectraMatch.getHistory`.
    struct HistoryResponse: Decodable {
        let identifications: [Identification]
        let total: Int
    }

    struct GetHistoryInput: Encodable {
        let terminalId: String?
        let limit: Int
    }

    /// `spectraMatch.getHistory` — most-recent verified
    /// identifications across the caller's company / driver scope.
    /// Server filters to loads with a non-null `spectraMatchResult`,
    /// in `loads.createdAt DESC` order, capped by `limit`.
    func getHistory(terminalId: String? = nil, limit: Int = 20) async throws -> HistoryResponse {
        try await api.query(
            "spectraMatch.getHistory",
            input: GetHistoryInput(terminalId: terminalId, limit: limit)
        )
    }
}

// MARK: - shippersRouter
//
// The first Shipper-facing surface on the iOS client. Today's
// callsite is the new `200_ShipperHome` brick (Shipper · Home).
// Backed verbatim by `frontend/server/routers/shippers.ts`. Added
// 2026-04-24 at the start of the role-by-role build wave that
// follows the Driver track (010–103) being shipped.
//
// Procedures wired today:
//   • getDashboardStats — header KPIs for Shipper Home
//   • getActiveLoads    — "Active loads" card list
//   • getLoadsRequiringAttention — "Needs your attention" alerts
//   • getRecentLoads    — recent activity feed
//
// Mutations (`create`, `update`, `delete`) will land when the
// post-a-load (201_PostLoad) and load-detail (203_LoadDetail) bricks
// ship in the next sub-firing.

struct ShipperAPI {
    unowned let api: EusoTripAPI

    /// Dashboard KPI envelope. Mirrors `shippers.getDashboardStats`
    /// (frontend/server/routers/shippers.ts:77).
    ///
    /// Note on `totalSpendThisMonth`: the backend casts the SUM out
    /// of MySQL using a `DECIMAL(19,4)` column, which returns as a
    /// JSON STRING through tRPC's MySQL driver (`"0"`, `"298775"`
    /// etc.). Hand-rolled decoder accepts both shapes so the iOS
    /// client doesn't blow up on `DecodingError.typeMismatch` when
    /// the server returns the canonical string form.
    struct DashboardStats: Decodable, Hashable {
        let activeLoads: Int
        let pendingBids: Int
        let deliveredThisWeek: Int
        let ratePerMile: Double
        let onTimeRate: Double
        let totalSpendThisMonth: Double

        private enum CodingKeys: String, CodingKey {
            case activeLoads, pendingBids, deliveredThisWeek
            case ratePerMile, onTimeRate, totalSpendThisMonth
        }

        /// Memberwise init kept explicit since we ship a custom
        /// `init(from:)` (which suppresses the synthesized memberwise).
        /// Used by `200_ShipperHome.canonStats` runtime fallback.
        init(activeLoads: Int,
             pendingBids: Int,
             deliveredThisWeek: Int,
             ratePerMile: Double,
             onTimeRate: Double,
             totalSpendThisMonth: Double) {
            self.activeLoads = activeLoads
            self.pendingBids = pendingBids
            self.deliveredThisWeek = deliveredThisWeek
            self.ratePerMile = ratePerMile
            self.onTimeRate = onTimeRate
            self.totalSpendThisMonth = totalSpendThisMonth
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.activeLoads        = try c.decodeIfPresent(Int.self, forKey: .activeLoads) ?? 0
            self.pendingBids        = try c.decodeIfPresent(Int.self, forKey: .pendingBids) ?? 0
            self.deliveredThisWeek  = try c.decodeIfPresent(Int.self, forKey: .deliveredThisWeek) ?? 0
            self.ratePerMile        = Self.decodeNumeric(c, .ratePerMile) ?? 0
            self.onTimeRate         = Self.decodeNumeric(c, .onTimeRate) ?? 0
            self.totalSpendThisMonth = Self.decodeNumeric(c, .totalSpendThisMonth) ?? 0
        }

        /// Numeric tolerator: tries Double, then Int (promoted), then
        /// String parsed as Double. Returns nil if the key is missing
        /// — caller substitutes 0. Centralized here because the same
        /// shape problem hits `ratePerMile`/`onTimeRate` whenever
        /// backend rows touch `DECIMAL` columns.
        private static func decodeNumeric(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
            if let d = try? c.decode(Double.self, forKey: key) { return d }
            if let i = try? c.decode(Int.self, forKey: key)    { return Double(i) }
            if let s = try? c.decode(String.self, forKey: key) { return Double(s) }
            return nil
        }
    }

    func getDashboardStats() async throws -> DashboardStats {
        try await api.queryNoInput("shippers.getDashboardStats")
    }

    /// One in-flight load on the Shipper's plate. Mirrors
    /// `shippers.getActiveLoads` (line 109).
    struct ActiveLoad: Decodable, Identifiable, Hashable {
        let id: String
        let loadNumber: String
        let status: String
        let origin: String
        let destination: String
        let catalyst: String
        let driver: String
        /// Numeric `users.id` of the assigned driver, when one is
        /// assigned. Required by 222 LiveTracking to call
        /// `telemetry.getLiveLocation(driverId:)`. Server emits this
        /// at `shippers.ts:139` (shippers.getActiveLoads).
        let driverId: Int?
        let catalystId: Int?
        let eta: String
        let rate: Double
        // EUSO-2042 — cargo / commodity surface so 200 Shipper Home's
        // active-loads row can render `LD-… · UN1203 · MC-306 · 50k lb`
        // per wireframe canon. All optional — older server builds that
        // don't carry these decode without error.
        let cargoType: String?
        let commodity: String?
        let unNumber: String?
        let hazmatClass: String?
        let weightDisplay: String?
        let cargoSummary: String?
        // Real distance from `loads.distance` — was missing entirely
        // and every active-loads card showed 0 mi. Founder report
        // 2026-05-06: "i see alot of loads with 0 miles."
        let distance: Double?
        let miles: Double?
        // ─── 2026-05-17 · Multi-modal payload ───
        // Powers LoadModeBadge on every Shipper Dispatch Control row
        // + Shipper Home active-loads card. Server projection ticket:
        // shippers.getActiveLoads — append transportMode /
        // multiVehicleCount / permitType / rateUnit / worldscalePct to
        // the SELECT.
        let transportMode: String?
        let multiVehicleCount: Int?
        let permitType: String?
        let rateUnit: String?
        let worldscalePct: String?
    }

    struct GetActiveLoadsInput: Encodable { let limit: Int }

    func getActiveLoads(limit: Int = 10) async throws -> [ActiveLoad] {
        try await api.query(
            "shippers.getActiveLoads",
            input: GetActiveLoadsInput(limit: limit)
        )
    }

    /// One alert row on the Shipper's "needs attention" feed.
    /// Mirrors `shippers.getLoadsRequiringAttention` (line 147).
    struct LoadAlert: Decodable, Identifiable, Hashable {
        let id: String
        let loadNumber: String
        let issue: String
        let severity: String
        let message: String
    }

    func getLoadsRequiringAttention() async throws -> [LoadAlert] {
        try await api.queryNoInput("shippers.getLoadsRequiringAttention")
    }

    /// One row in the Shipper's recent-activity feed. Server
    /// returns a slim load summary; richer detail hangs off
    /// `loads.getById`. `deliveredAt` is the server's `YYYY-MM-DD`
    /// projection of `actualDeliveryDate ?? deliveryDate`, empty
    /// string when neither is set.
    struct RecentLoad: Decodable, Identifiable, Hashable {
        let id: String
        let loadNumber: String
        let status: String
        let origin: String
        let destination: String
        let deliveredAt: String
        let rate: Double
        let distance: Double?
        let miles: Double?
    }

    struct GetRecentLoadsInput: Encodable { let limit: Int }

    func getRecentLoads(limit: Int = 5) async throws -> [RecentLoad] {
        try await api.query(
            "shippers.getRecentLoads",
            input: GetRecentLoadsInput(limit: limit)
        )
    }

    /// One row in the Shipper's "my loads" table — the shipper-track
    /// equivalent of the carrier-side dispatch board. Used by 384
    /// Bulk Re-tender + 412 Drafts + 413 Archived. Mirrors
    /// `shippers.getMyLoads` (line 282).
    struct MyLoad: Decodable, Identifiable, Hashable {
        struct LocationRef: Decodable, Hashable { let city: String; let state: String }
        struct PartyRef: Decodable, Hashable { let id: String; let name: String }

        let id: String
        let loadNumber: String
        let status: String
        let originRef: LocationRef
        let destinationRef: LocationRef
        let pickupDate: String
        let deliveryDate: String
        let equipment: String
        let weight: Double
        let hazmat: Bool
        let hazmatClass: String?
        let product: String
        let catalyst: PartyRef?
        let driver: PartyRef?
        // Server returns 0 when no rate is set; we project Optional so
        // the 282/285 screens (`if let r = ld.rate`) work as written.
        let rate: Double?
        let eta: String
        let bidsReceived: Int
        let deliveredAt: String?
        // Server-side timestamp of when the load was first persisted.
        // Used by 285 sparkline trend to bucket loads per month.
        // Optional — will be nil until backend ships the projection
        // change (server ticket EUSO-2042b).
        let createdAt: String?
        /// Distance in miles, projected from `loads.distance`. Was
        /// missing from the server projection — every "My Loads" row
        /// rendered 0 mi. Optional so older server builds that
        /// don't carry the field still decode.
        let distance: Double?
        let miles: Double?

        // ─── 2026-05-17 · Multi-modal projection ───
        // Surfaced on every "My Loads" row so the shipper sees the mode
        // badge + vehicle count on each card. Optional on the wire so
        // pre-0307 deploys decode cleanly. Server projection ticket:
        // shippers.getMyLoads — append transportMode / multiVehicleCount
        // / permitType / rateUnit / worldscalePct to the SELECT.
        let transportMode: String?
        let multiVehicleCount: Int?
        let permitType: String?
        let rateUnit: String?
        let worldscalePct: String?

        // Map server JSON to the struct above. The server emits
        // `origin` / `destination` as `{city,state}` — Swift can't bind
        // those to non-conflicting names without explicit CodingKeys.
        enum CodingKeys: String, CodingKey {
            case id, loadNumber, status, pickupDate, deliveryDate
            case equipment, weight, hazmat, hazmatClass, product
            case catalyst, driver, rate, eta, bidsReceived, deliveredAt, createdAt
            case distance, miles
            case transportMode, multiVehicleCount, permitType, rateUnit, worldscalePct
            case originRef = "origin"
            case destinationRef = "destination"
        }

        // Convenience flat strings for screens that don't care about
        // city/state separation (e.g., 384's row label).
        var origin: String {
            "\(originRef.city), \(originRef.state)".trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        }
        var destination: String {
            "\(destinationRef.city), \(destinationRef.state)".trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        }
        // Convenience: 282 filters by catalystId — server returns it
        // nested as `catalyst.id`. Hoist it to the top level so client
        // code reads naturally.
        var catalystId: String? { catalyst?.id }
        var driverId: String? { driver?.id }
    }

    struct GetMyLoadsInput: Encodable {
        let status: String?
        let limit: Int
        let offset: Int
    }

    struct GetMyLoadsResponse: Decodable {
        let loads: [MyLoad]
        let total: Int
    }

    func getMyLoads(status: String? = nil, limit: Int = 50, offset: Int = 0) async throws -> [MyLoad] {
        let env: GetMyLoadsResponse = try await api.query(
            "shippers.getMyLoads",
            input: GetMyLoadsInput(status: status, limit: limit, offset: offset)
        )
        return env.loads
    }

    // ===================================================================
    // 117th eusotrip-killers firing · 2026-04-26 · brick 202 wiring
    // -------------------------------------------------------------------
    // Profile + Stats DTOs and the matching `getProfile()` / `getStats()`
    // methods land in the same firing as `202_ShipperProfile.swift`
    // (Cohort B day-1, no mock data). Wire-format mirrors verbatim what
    // the backend returns at `frontend/server/routers/shippers.ts:583`
    // (`getProfile`) and `:605` (`getStats`). Both procedures use the
    // shipper-gated `protectedProcedure` and return populated envelopes
    // even when the underlying tables are empty (server returns sentinel
    // empty strings / zeros), so the client never has to invent data —
    // every blank field surfaces as an em-dash sentinel in the UI.
    // ===================================================================

    /// Shipper company profile envelope. Mirrors verbatim
    /// `shippers.getProfile` at `frontend/server/routers/shippers.ts:583`.
    /// Server returns empty strings / `false` when the underlying
    /// `companies` row hasn't been hydrated yet — the screen surfaces
    /// those as em-dashes rather than fabricating values.
    struct Profile: Decodable, Hashable {
        let id: String
        let companyName: String
        let contactName: String
        let email: String
        let phone: String
        let address: String
        let dotNumber: String
        let mcNumber: String
        let verified: Bool
        /// ISO-8601 timestamp string from `companies.createdAt.toISOString()`.
        /// Empty string when not set. Client formats this for display.
        let memberSince: String
        let website: String
    }

    func getProfile() async throws -> Profile {
        try await api.queryNoInput("shippers.getProfile")
    }

    /// Per-month volume row. Mirrors verbatim each entry in
    /// `monthlyVolume` returned by `shippers.getStats` at
    /// `frontend/server/routers/shippers.ts:605`. Server projects
    /// `month` as `YYYY-MM` and `loads` as the row count.
    struct ProfileMonthlyVolume: Decodable, Hashable, Identifiable {
        let month: String
        let loads: Int

        var id: String { month }
    }

    /// Shipper aggregate stats envelope. Mirrors verbatim
    /// `shippers.getStats` at `frontend/server/routers/shippers.ts:605`.
    /// `avgRatePerMile` and `avgPaymentTime` are server-side TODOs (the
    /// backend currently returns 0 for both); the client honors that
    /// honestly with em-dash sentinels rather than fake projections.
    struct Stats: Decodable, Hashable {
        let totalLoads: Int
        let totalSpend: Int
        let avgRatePerMile: Double
        let onTimeDeliveryRate: Int
        let preferredCatalysts: Int
        let avgPaymentTime: Double
        let onTimeRate: Int
        let monthlyVolume: [ProfileMonthlyVolume]
        let maxMonthlyLoads: Int
    }

    func getStats() async throws -> Stats {
        try await api.queryNoInput("shippers.getStats")
    }

    // ===================================================================
    // 119th eusotrip-killers firing · 2026-04-26 · brick 203 wiring
    // -------------------------------------------------------------------
    // Bid DTOs + getBidsForLoad / acceptBid / rejectBid land in the same
    // firing as `203_ShipperBids.swift` (Cohort B day-1, no mock data).
    // Wire-format mirrors verbatim what the backend returns at:
    //   • `frontend/server/routers/shippers.ts:358` (`getBidsForLoad`)
    //   • `frontend/server/routers/shippers.ts:392` (`acceptBid`)
    //   • `frontend/server/routers/shippers.ts:415` (`rejectBid`)
    // All three use the shipper-gated `protectedProcedure`. The server
    // returns sentinel zeros / empty strings when underlying fields
    // (e.g. `safetyScore`, `transitTime`) aren't yet populated — the
    // client surfaces those as em-dash sentinels rather than fabricating
    // values. `recommended` is a server-side flag (currently the most-
    // recent bid) — the screen renders a gradient pill only when true.
    // ===================================================================

    /// One bid row returned by `shippers.getBidsForLoad`. Mirrors
    /// verbatim the catalyst-decorated payload constructed at
    /// `frontend/server/routers/shippers.ts:368`. `id` and
    /// `catalystId` carry the `bid_` / `car_` prefixes the server
    /// emits — the client passes them back to `acceptBid` /
    /// `rejectBid` unmodified (the server strips the prefix on its
    /// side before the SQL update).
    struct Bid: Decodable, Identifiable, Hashable {
        let id: String
        let catalystId: String
        let catalystName: String
        let dotNumber: String
        let safetyScore: Double
        let amount: Double
        let transitTime: String
        let submittedAt: String
        let message: String
        let recommended: Bool
    }

    struct GetBidsForLoadInput: Encodable { let loadId: String }

    /// Fetch every bid for a single posted load. Server returns an
    /// empty array (not an error) when the load has no bids yet, so
    /// the screen surfaces the canonical `EusoEmptyState` rather
    /// than an error tile.
    func getBidsForLoad(loadId: String) async throws -> [Bid] {
        try await api.query(
            "shippers.getBidsForLoad",
            input: GetBidsForLoadInput(loadId: loadId)
        )
    }

    struct AcceptBidInput: Encodable {
        let loadId: String
        let bidId: String
    }

    /// Accept-bid mutation envelope. Mirrors verbatim the return of
    /// `shippers.acceptBid` at `frontend/server/routers/shippers.ts:409`.
    /// Server-side this also rejects every other pending bid on the
    /// load and updates `loads.status` → `assigned`, so the client
    /// must refresh the bids list (the rejected bids re-render with
    /// `status` = "rejected" — though the client filters on the
    /// caller's side via `ShipperBidsStore`) and the loads list (the
    /// load drops out of `getActiveLoads` / re-categorises to
    /// `assigned` in the next refresh window).
    struct AcceptBidOutput: Decodable, Hashable {
        let success: Bool
        let loadId: String
        let bidId: String
        let status: String
        let acceptedAt: String
    }

    func acceptBid(loadId: String, bidId: String) async throws -> AcceptBidOutput {
        try await api.mutation(
            "shippers.acceptBid",
            input: AcceptBidInput(loadId: loadId, bidId: bidId)
        )
    }

    struct RejectBidInput: Encodable {
        let loadId: String
        let bidId: String
        let reason: String?
    }

    /// Reject-bid mutation envelope. Mirrors verbatim the return of
    /// `shippers.rejectBid` at `frontend/server/routers/shippers.ts:427`.
    /// `reason` is optional — the server stores it on `bids.notes`
    /// only when non-nil. Empty / whitespace strings on the client
    /// are coalesced to `nil` by `203_ShipperBids.swift` before the
    /// call so the wire never carries a meaningless reason field.
    struct RejectBidOutput: Decodable, Hashable {
        let success: Bool
        let bidId: String
        let rejectedAt: String
    }

    func rejectBid(
        loadId: String,
        bidId: String,
        reason: String? = nil
    ) async throws -> RejectBidOutput {
        try await api.mutation(
            "shippers.rejectBid",
            input: RejectBidInput(
                loadId: loadId,
                bidId: bidId,
                reason: reason
            )
        )
    }

    // ===================================================================
    // Round 4 / Arc E lifecycle wiring · 2026-04-28
    // -------------------------------------------------------------------
    // `shippers.getLifecycleSnapshot(loadId)` is the composite endpoint
    // every shipper lifecycle brick (260-279) consumes. One round-trip
    // returns load detail + stops + bids summary + assigned carrier /
    // driver / vehicle + last geofence event + escrow + accessorial
    // total + recommended bid id. Mirrors verbatim the return at
    // `frontend/server/routers/shippers.ts:getLifecycleSnapshot`.
    //
    // Cohort B day-1: every field is server-emitted; missing rows
    // surface as `nil` and the screen renders em-dash sentinels.
    // ===================================================================

    struct LifecycleSnapshot: Decodable, Hashable {
        struct Load: Decodable, Hashable {
            let id: Int
            let loadNumber: String
            let status: String
            let cargoType: String?
            let hazmatClass: String?
            let unNumber: String?
            let ergGuide: Int?
            let equipmentType: String?
            let rate: Double?
            let weight: Double?
            let distance: Double?
            let pickupDate: String?
            let deliveryDate: String?
            let estimatedDeliveryDate: String?
            let actualDeliveryDate: String?
            let biddingEnds: String?
            let specialInstructions: String?
            let spectraMatchVerified: Bool?
            // Server-derived lane relationship for the in-transit echo
            // re-skin. "head_haul" | "backhaul" | "matrix". Optional &
            // forward-safe: thin payloads that omit it still decode and
            // render as head_haul (the base look) — a web lane is adding
            // the server side in parallel.
            let relationship: String?
        }
        struct Stop: Decodable, Hashable, Identifiable {
            let id: Int
            let sequence: Int
            let stopType: String
            let facilityName: String?
            let address: String?
            let city: String?
            let state: String?
            let contactName: String?
            let contactPhone: String?
            let appointmentStart: String?
            let appointmentEnd: String?
            let arrivedAt: String?
            let departedAt: String?
            let status: String
            let notes: String?
            let lat: Double?
            let lng: Double?
        }
        struct BidsSummary: Decodable, Hashable {
            let count: Int
            let topBid: Double?
            let highestBid: Double?
            let averageBid: Double?
            let acceptedBidId: Int?
        }
        struct Carrier: Decodable, Hashable {
            let id: Int
            let name: String
            let dotNumber: String?
            let mcNumber: String?
        }
        struct Driver: Decodable, Hashable {
            let id: Int
            let name: String
            let email: String?
            let phone: String?
        }
        struct Vehicle: Decodable, Hashable {
            let id: Int
            let vehicleNumber: String?
            let vin: String?
            let make: String?
            let model: String?
        }
        struct Geofence: Decodable, Hashable {
            let type: String
            let eventTimestamp: String?
            let latitude: Double
            let longitude: Double
            let dwellSeconds: Int?
        }
        struct Escrow: Decodable, Hashable {
            let id: Int
            let amount: Double
            let status: String?
            let releaseAt: String?
        }

        let load: Load
        let pickup: Stop?
        let delivery: Stop?
        let stops: [Stop]
        let bidsSummary: BidsSummary
        let carrier: Carrier?
        let driver: Driver?
        let vehicle: Vehicle?
        let lastGeofence: Geofence?
        let escrow: Escrow?
        let accessorialTotal: Double
        let recommendedBidId: Int?
        let fetchedAt: String
    }

    struct LifecycleSnapshotInput: Encodable { let loadId: String }

    /// Fetch the lifecycle composite snapshot for a single load.
    /// Throws on transport errors and on `loads.getById`-style "not
    /// found" — the screen surfaces a real retry banner.
    func getLifecycleSnapshot(loadId: String) async throws -> LifecycleSnapshot {
        try await api.query(
            "shippers.getLifecycleSnapshot",
            input: LifecycleSnapshotInput(loadId: loadId)
        )
    }

    /// Optional settlement view for a load. `nil` until the
    /// settlement is constructed.
    struct SettlementForLoad: Decodable, Hashable {
        let id: Int
        let status: String
        let amount: Double
        let payableDate: String?
        let paidAt: String?
        let invoiceUrl: String?
        let source: String
    }

    func getSettlementForLoad(loadId: String) async throws -> SettlementForLoad? {
        struct In: Encodable { let loadId: String }
        return try await api.query(
            "shippers.getSettlementForLoad",
            input: In(loadId: loadId)
        )
    }

    // ===================================================================
    // 121st eusotrip-killers firing · 2026-04-26 · brick 204 wiring
    // -------------------------------------------------------------------
    // PostLoad input + ack DTOs and the matching `create()` method land
    // in the same firing as `204_ShipperPostLoad.swift` (Cohort B day-1,
    // no mock data). Wire-format mirrors verbatim what the backend
    // accepts and returns at:
    //   • `frontend/server/routers/shippers.ts:18` (`shippers.create`)
    //
    // Procedure is `shipperProcedure` (alias of `protectedProcedure` in
    // shippers.ts), so a logged-in non-shipper hits a 403 — the screen
    // surfaces the readable tRPC error, never invents a fake load
    // number. `cargoType` is a fixed-cardinality string enum the
    // backend defaults to "general" when the client sends a missing
    // / unknown value; the iOS picker enumerates the same 8 values
    // verbatim so the wire never drifts. `rate` / `weight` are the
    // optional cents-anonymous numerics — the backend coerces both to
    // string-decimal for the Drizzle insert. `pickupDate` is an
    // ISO-8601 date string when present (the screen serialises with
    // `ISO8601DateFormatter` to keep the wire stable across locales).
    // ===================================================================

    /// Cargo-type enum the backend accepts at `shippers.create`. The
    /// raw value matches the Zod enum verbatim
    /// (`general | hazmat | refrigerated | oversized | liquid | gas |
    /// chemicals | petroleum`). Order is preserved from the schema so
    /// the gradient-chip picker in `204_ShipperPostLoad` can iterate
    /// `allCases` for the visible row.
    enum CargoType: String, Codable, CaseIterable, Hashable, Identifiable {
        case general
        case hazmat
        case refrigerated
        case oversized
        case liquid
        case gas
        case chemicals
        case petroleum

        var id: String { rawValue }

        /// Human-readable label rendered on the picker chip. Mirrors
        /// the marketing copy used on the web shipper UI; no
        /// abbreviations.
        var label: String {
            switch self {
            case .general:      return "General"
            case .hazmat:       return "Hazmat"
            case .refrigerated: return "Refrigerated"
            case .oversized:    return "Oversized"
            case .liquid:       return "Liquid bulk"
            case .gas:          return "Gas"
            case .chemicals:    return "Chemicals"
            case .petroleum:    return "Petroleum"
            }
        }

        /// SF Symbol on the picker chip — keeps the visual hierarchy
        /// readable when the label wraps. All glyphs are SF-Symbols
        /// 5+ available on iOS 17+ targets.
        var systemImage: String {
            switch self {
            case .general:      return "shippingbox"
            case .hazmat:       return "exclamationmark.triangle.fill"
            case .refrigerated: return "thermometer.snowflake"
            case .oversized:    return "ruler.fill"
            case .liquid:       return "drop.fill"
            case .gas:          return "wind"
            case .chemicals:    return "testtube.2"
            case .petroleum:    return "fuelpump.fill"
            }
        }
    }

    /// Input envelope for `shippers.create`. Mirrors verbatim the Zod
    /// schema at `shippers.ts:19`. Optional numerics / notes / pickup
    /// date are wire-omitted when nil so the backend's
    /// `.optional()` defaults apply. `cargoType` carries the raw
    /// enum string (`"general"`, `"hazmat"`, …) — the screen never
    /// sends free-form strings.
    // PostLoadInput intentionally drops `Hashable` because the
    // multi-modal `modeRoutePayload` is a type-erased `AnyEncodable`,
    // which has no value semantics for hashing. PostLoadInput is only
    // used as a one-shot mutation payload, so Hashable was never
    // referenced — removing it has no call-site impact.
    struct PostLoadInput: Encodable {
        let origin: String
        let destination: String
        let cargoType: CargoType
        let rate: Double?
        let weight: Double?
        let notes: String?
        /// ISO-8601 date string (no time) — backend coerces to
        /// `Date` via `new Date(input.pickupDate)` for the Drizzle
        /// insert. Empty strings are coalesced to nil before send.
        let pickupDate: String?
        /// Captured from HERE autosuggest / "lat,lng" paste in
        /// `HereAddressField`. When present the backend skips
        /// re-geocoding and goes straight to truck-route distance.
        /// Nil → server geocodes the free-text address as a fallback.
        let originLat: Double?
        let originLng: Double?
        let destLat: Double?
        let destLng: Double?
        // ─── 2026-05-17 · Multi-modal payload ─────────────────────────
        // Lands the Step-1 mode picker + Step-2/3 multi-modal payload
        // into `loads.transport_mode` + the columns added in migration
        // 0307_loads_multimodal_fields.sql. All optional so older clients
        // omit them and the server defaults to the truck-only behavior.
        let transportMode: String?
        let vesselClass: String?
        let multiVehicleCount: Int?
        let permitType: String?
        let originPort: String?
        let destPort: String?
        let worldscalePct: Double?
        let worldscaleFlat: Double?
        let rateUnit: String?
        /// Snapshot of the ModeRoute the shipper accepted (distance,
        /// transit-range, cost-range, feasibility). Round-trips as
        /// arbitrary JSON; backend stores in `mode_route_payload`.
        let modeRoutePayload: AnyEncodable?
        let equipmentType: String?
    }

    /// Acknowledgement envelope returned by `shippers.create`.
    /// Mirrors verbatim the return at `shippers.ts:44`. The backend
    /// emits `loadNumber` as `SHP-${Date.now().toString(36)
    /// .toUpperCase()}` — the screen surfaces the verbatim string in
    /// the success toast (no client-side reformatting).
    struct PostLoadAck: Decodable, Hashable {
        let success: Bool
        let id: Int
        let loadNumber: String
    }

    /// Create a freshly-posted load. Server flow on success:
    ///   1. Inserts a row in `loads` with `status = 'posted'`,
    ///      `shipperId = ctx.user.companyId`, and a freshly-minted
    ///      `loadNumber`.
    ///   2. Returns `{ success: true, id, loadNumber }`.
    ///
    /// Failure modes the screen handles explicitly:
    ///   • Database unavailable — backend throws (status 500). The
    ///     screen surfaces `EusoTripAPIError.trpcError` via the
    ///     readable-error helper.
    ///   • Non-shipper role — `shipperProcedure` rejects with 403.
    ///     Same readable-error path.
    ///   • Invalid Zod payload — surfaces 400 via the same path.
    ///
    /// The screen does NOT cache or replay successful inserts: every
    /// CTA tap hits the network with the freshest input value. On
    /// success the `ShipperActiveLoadsStore` is invalidated by the
    /// caller so the loads list re-fetches and shows the new row.
    func create(
        origin: String,
        destination: String,
        cargoType: CargoType = .general,
        rate: Double? = nil,
        weight: Double? = nil,
        notes: String? = nil,
        pickupDate: String? = nil,
        originLat: Double? = nil,
        originLng: Double? = nil,
        destLat: Double? = nil,
        destLng: Double? = nil,
        // ─── 2026-05-17 · Multi-modal payload ───
        transportMode: String? = nil,
        vesselClass: String? = nil,
        multiVehicleCount: Int? = nil,
        permitType: String? = nil,
        originPort: String? = nil,
        destPort: String? = nil,
        worldscalePct: Double? = nil,
        worldscaleFlat: Double? = nil,
        rateUnit: String? = nil,
        modeRoutePayload: [String: Any]? = nil,
        equipmentType: String? = nil
    ) async throws -> PostLoadAck {
        // Wrap the heterogenous [String: Any] payload into an
        // AnyEncodable that round-trips through JSONSerialization —
        // direct `AnyEncodable($0)` won't compile because Swift's
        // existential `Encodable` has Self requirements that bar
        // casting from `Any`. The JSON path narrows the input to
        // JSON-compatible primitives + arrays + dicts, then re-emits
        // as Data the encoder can pass through verbatim.
        let encodablePayload: AnyEncodable? = {
            guard let dict = modeRoutePayload else { return nil }
            guard JSONSerialization.isValidJSONObject(dict),
                  let data = try? JSONSerialization.data(withJSONObject: dict) else {
                return nil
            }
            return AnyEncodable(JSONRawEncodable(data: data))
        }()
        return try await api.mutation(
            "shippers.create",
            input: PostLoadInput(
                origin: origin,
                destination: destination,
                cargoType: cargoType,
                rate: rate,
                weight: weight,
                notes: notes,
                pickupDate: pickupDate,
                originLat: originLat,
                originLng: originLng,
                destLat: destLat,
                destLng: destLng,
                transportMode: transportMode,
                vesselClass: vesselClass,
                multiVehicleCount: multiVehicleCount,
                permitType: permitType,
                originPort: originPort,
                destPort: destPort,
                worldscalePct: worldscalePct,
                worldscaleFlat: worldscaleFlat,
                rateUnit: rateUnit,
                modeRoutePayload: encodablePayload,
                equipmentType: equipmentType
            )
        )
    }

    // ===================================================================
    // 124th eusotrip-killers firing · 2026-04-26 · brick 206 wiring
    // -------------------------------------------------------------------
    // DeliveryConfirmation DTO + `getDeliveryConfirmations()` lands in
    // the same firing as `206_ShipperSettlements.swift` (Cohort B day-1,
    // no mock data). Wire-format mirrors verbatim what the backend
    // returns at `frontend/server/routers/shippers.ts:534`. Server
    // selects every `loads` row where `shipperId == ctx.user.id` AND
    // `status == 'delivered'`, joined with the pickup/delivery JSON
    // and `actualDeliveryDate ?? deliveryDate` for the `deliveredAt`
    // ISO timestamp. The procedure is `protectedProcedure`, so a
    // logged-in non-shipper hits a 403 — the screen surfaces the
    // readable tRPC error rather than fabricating rows.
    //
    // The Settlements surface aggregates these confirmations into a
    // billable summary (count + total spend + avg) on the client side
    // and renders the row list below the KPI tiles. The aggregate
    // numbers are derived locally from the verified server array so
    // there is zero risk of drift between two queries — every cell on
    // the screen traces back to a real DELIVERED row.
    // ===================================================================

    /// Status filter accepted by `shippers.getDeliveryConfirmations`.
    /// Mirrors the Zod enum at line 536 verbatim.
    enum DeliveryConfirmationStatus: String, Encodable, Hashable {
        case pending, confirmed, disputed
    }

    /// One row in the shipper's delivery-confirmations feed. Mirrors
    /// verbatim the projection at `shippers.ts:548-553`. `loadId` is
    /// the server-emitted `load_NNN` form (the backend prefixes the
    /// numeric primary key); the client passes it back unmodified
    /// when wiring to load-detail. `deliveredAt` is an ISO-8601
    /// timestamp string (or empty when neither `actualDeliveryDate`
    /// nor `deliveryDate` is set — the screen surfaces "—" then).
    /// `rate` is `parseFloat(loads.rate)` server-side, defaulting to
    /// `0` when the column is empty. `status` is the literal
    /// "confirmed" string the backend hard-codes today (the row was
    /// returned because `loads.status == 'delivered'`); the field
    /// is kept on the wire for forward compatibility with the
    /// `pending` / `disputed` filters once the backend writes a real
    /// confirmation status column.
    struct DeliveryConfirmation: Decodable, Identifiable, Hashable {
        let loadId: String
        let loadNumber: String
        let origin: String
        let destination: String
        let deliveredAt: String
        let status: String
        let rate: Double

        var id: String { loadId }
    }

    struct GetDeliveryConfirmationsInput: Encodable {
        /// Optional server-side filter. The backend treats a
        /// missing key as "all confirmed". The screen passes nil
        /// for the canonical "show every settled load" view.
        let status: DeliveryConfirmationStatus?
        let limit: Int
    }

    /// Fetch the shipper's delivery-confirmations feed. Server
    /// returns an empty array (not an error) when the shipper has
    /// no delivered loads yet, so the screen surfaces the canonical
    /// `EusoEmptyState` rather than an error tile.
    func getDeliveryConfirmations(
        status: DeliveryConfirmationStatus? = nil,
        limit: Int = 20
    ) async throws -> [DeliveryConfirmation] {
        try await api.query(
            "shippers.getDeliveryConfirmations",
            input: GetDeliveryConfirmationsInput(status: status, limit: limit)
        )
    }

    // ===================================================================
    // 126th eusotrip-killers firing · 2026-04-26 · brick 207 wiring
    // -------------------------------------------------------------------
    // Spending Analytics + Catalyst Performance DTOs land in the same
    // firing as `207_ShipperReports.swift` (Cohort B day-1, no mock
    // data). Wire-format mirrors verbatim the backend at
    // `frontend/server/routers/shippers.ts:470` (getSpendingAnalytics,
    // single envelope) and `:433` (getCatalystPerformance, list). Both
    // are `shipperProcedure` aliases of `protectedProcedure` so a non-
    // shipper login surfaces the readable tRPC error rather than
    // fabricating numbers.
    //
    // The Reports surface combines the two endpoints in a single
    // dashboard — spend KPIs at the top + catalyst leaderboard below.
    // Period switcher (Month / Quarter / Year) propagates to both
    // queries via the shared `SpendingPeriod` token so the two strips
    // can never describe different time windows.
    // ===================================================================

    /// Period filter accepted by both `shippers.getSpendingAnalytics`
    /// and `shippers.getCatalystPerformance`. Mirrors the Zod enums at
    /// lines 472 + 435 verbatim. Backend defaults differ (`month` vs
    /// `quarter`); the screen unifies them client-side at `.month`.
    enum SpendingPeriod: String, Encodable, Hashable, CaseIterable {
        case month, quarter, year
    }

    /// Spending-analytics envelope. Mirrors the projection at
    /// `shippers.ts:getSpendingAnalytics`. Numeric fields typed as
    /// `Double` so backend-side `Math.round(...)` integer outputs
    /// AND any future fractional values both decode cleanly.
    ///
    /// `byLane` / `byEquipment` / `byCatalyst` ship live cohort
    /// breakdowns: state-pair lanes (top 8 by spend), cargoType-
    /// classified equipment mix, and per-catalyst spend (top 10).
    /// All three are computed from the same time-window filter as
    /// the headline totals so cross-lens numbers always agree.
    struct SpendingAnalytics: Decodable, Hashable {
        let period: String
        let totalSpend: Double
        let loadCount: Int
        let avgPerLoad: Double
        let avgPerMile: Double
        let vsMarketRate: Double
        let byLane: [LaneCohort]
        let byEquipment: [EquipmentCohort]
        let byCatalyst: [CatalystSpend]

        struct LaneCohort: Decodable, Hashable, Identifiable {
            let origin: String
            let destination: String
            let loadCount: Int
            let totalSpend: Double
            let avgPerLoad: Double
            var id: String { "\(origin)->\(destination)" }
        }

        struct EquipmentCohort: Decodable, Hashable, Identifiable {
            let equipment: String
            let loadCount: Int
            let totalSpend: Double
            /// Server-computed share of total spend, 0–100.
            let share: Int
            var id: String { equipment }
        }

        struct CatalystSpend: Decodable, Hashable, Identifiable {
            let catalystId: String
            let name: String
            let loadCount: Int
            let totalSpend: Double
            var id: String { catalystId }
        }

        // Default-empty cohort arrays so a server still returning the
        // pre-cohort shape decodes without throwing — JSONDecoder
        // throws on a missing required key. `init(from:)` accepts
        // missing arrays as `[]`.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.period       = try c.decode(String.self, forKey: .period)
            self.totalSpend   = try c.decode(Double.self, forKey: .totalSpend)
            self.loadCount    = try c.decode(Int.self,    forKey: .loadCount)
            self.avgPerLoad   = try c.decode(Double.self, forKey: .avgPerLoad)
            self.avgPerMile   = try c.decode(Double.self, forKey: .avgPerMile)
            self.vsMarketRate = try c.decode(Double.self, forKey: .vsMarketRate)
            self.byLane       = (try? c.decode([LaneCohort].self,      forKey: .byLane))      ?? []
            self.byEquipment  = (try? c.decode([EquipmentCohort].self, forKey: .byEquipment)) ?? []
            self.byCatalyst   = (try? c.decode([CatalystSpend].self,   forKey: .byCatalyst))  ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case period, totalSpend, loadCount, avgPerLoad, avgPerMile, vsMarketRate
            case byLane, byEquipment, byCatalyst
        }
    }

    struct GetSpendingAnalyticsInput: Encodable {
        let period: SpendingPeriod
    }

    /// One catalyst's recent performance — projection mirrors
    /// `shippers.ts:454-461`. `catalystId` is the server-emitted
    /// `car_NNN` form. `onTimeRate` is a 0–100 integer percent
    /// (backend `Math.round((onTime / total) * 100)`).
    struct CatalystPerformance: Decodable, Identifiable, Hashable {
        let catalystId: String
        let name: String
        let totalLoads: Int
        let delivered: Int
        let onTimeRate: Int
        let totalSpend: Double

        var id: String { catalystId }
    }

    struct GetCatalystPerformanceInput: Encodable {
        let period: SpendingPeriod
    }

    /// Fetch this shipper's spend analytics for the given period.
    /// Server returns a fully-populated envelope (all-zeros if the
    /// shipper has no loads in window) so the call never throws on
    /// "no data"; the store's `foldState` collapses an all-zero
    /// envelope to `.empty` for the UI.
    func getSpendingAnalytics(
        period: SpendingPeriod = .month
    ) async throws -> SpendingAnalytics {
        try await api.query(
            "shippers.getSpendingAnalytics",
            input: GetSpendingAnalyticsInput(period: period)
        )
    }

    /// 10-bucket time-series for the spend trend hero on
    /// 210_ShipperAnalyticsDeepDive. `current[i]` is the spend in
    /// bucket `i` of the in-window period; `prior[i]` is the same
    /// bucket from the period before that, so the chart can render
    /// the "vs prior" dashed comparison line. Server-side: see
    /// `shippers.getSpendTrend` in `frontend/server/routers/shippers.ts`.
    struct SpendTrend: Decodable, Hashable {
        let period: String
        let bucketCount: Int
        let current: [Double]
        let prior: [Double]
        let currentTotal: Double
        let priorTotal: Double
    }

    func getSpendTrend(
        period: SpendingPeriod = .quarter
    ) async throws -> SpendTrend {
        struct In: Encodable { let period: SpendingPeriod }
        return try await api.query(
            "shippers.getSpendTrend",
            input: In(period: period)
        )
    }

    /// Fetch this shipper's catalyst-performance leaderboard.
    /// Server returns an empty array (not an error) when the shipper
    /// has no catalyst-assigned loads in window.
    func getCatalystPerformance(
        period: SpendingPeriod = .month
    ) async throws -> [CatalystPerformance] {
        try await api.query(
            "shippers.getCatalystPerformance",
            input: GetCatalystPerformanceInput(period: period)
        )
    }

    // MARK: - Favorite Catalysts (brick 209_ShipperContacts · 127th firing)
    //
    // Backs the shipper's "Working Carriers" / contact directory.
    // Server-side this is a derived view: catalysts the shipper has
    // worked with (status='delivered'), aggregated by COUNT + SUM(rate),
    // ordered DESC by load count, top 10. The "favorite" framing is
    // doctrine: the most-worked-with carriers ARE the shipper's de-
    // facto contact list.
    //
    // MCP-verified at firing open: shippers.getFavoriteCatalysts at
    // frontend/server/routers/shippers.ts:500 (returns Array<{
    // catalystId: "car_${id}", name, dotNumber, loadsCompleted,
    // totalSpend (Math.rounded int) }>). Empty when shipper has zero
    // delivered loads.
    //
    // addFavoriteCatalyst is a no-op acknowledgment server-side
    // (returns { success, catalystId, addedAt }) — favorites are
    // derived from history, not stored as a separate junction table
    // — but the mutation exists so the UI can fire-and-forget on
    // explicit "favorite" taps for future-proofing.

    /// One row of the shipper's working-carriers directory.
    /// Mirrors `shippers.ts:511-516`. `catalystId` is the server-
    /// emitted `car_NNN` form. `totalSpend` is in dollars (the server
    /// does `Math.round(...)` so it lands as an integer-valued Double).
    struct FavoriteCatalyst: Decodable, Identifiable, Hashable {
        let catalystId: String
        let name: String
        let dotNumber: String
        let loadsCompleted: Int
        let totalSpend: Double

        var id: String { catalystId }
    }

    /// Server response for `addFavoriteCatalyst`. The backend treats
    /// this as a no-op acknowledgment — the catalyst will surface in
    /// `getFavoriteCatalysts` once a delivered load exists, not by
    /// virtue of this call. Kept on the wire so iOS can flush the
    /// optimistic favorite-tap UX without breaking the contract.
    struct AddFavoriteCatalystResponse: Decodable {
        let success: Bool
        let catalystId: String
        let addedAt: String
    }

    struct AddFavoriteCatalystInput: Encodable {
        let catalystId: String
    }

    /// Fetch the shipper's working-carriers directory (top 10 by
    /// delivered-load count). Server returns an empty array when the
    /// shipper has zero delivered loads — view surfaces EusoEmptyState.
    func getFavoriteCatalysts() async throws -> [FavoriteCatalyst] {
        try await api.queryNoInput("shippers.getFavoriteCatalysts")
    }

    /// Acknowledge a favorite tap server-side. Idempotent (server
    /// derives favorites from history); kept available for parity
    /// with the `addFavoriteCatalyst` UI affordance.
    func addFavoriteCatalyst(
        catalystId: String
    ) async throws -> AddFavoriteCatalystResponse {
        try await api.mutation(
            "shippers.addFavoriteCatalyst",
            input: AddFavoriteCatalystInput(catalystId: catalystId)
        )
    }
}

// =====================================================================
// CarrierAPI · live tRPC surface for Carrier role (brick 300+)
// ---------------------------------------------------------------------
// Added 2026-04-25 in the 100th eusotrip-killers firing as the role-
// switch from Shipper to Carrier per the 2027 motivation: "all 24 users
// piece by piece every screen each role at a time til you are done."
//
// Every procedure on this struct calls a real backend path. There are
// no mock fixtures, no stubbed return values, no `if PREVIEW { return
// .sample }` short-circuits. If the backend has not yet exposed the
// `carriers.*` router, the call throws `EusoTripAPIError.trpcError`
// and the Carrier* stores in `ViewModels/LiveDataStores.swift` surface
// `EusoEmptyState`. This satisfies doctrine §11 (no mock data) and the
// `MockDataGuard` self-check wired at `EusoTripApp.swift:101`.
//
// Field shapes are carrier-side KPIs and rows. Where a field has a
// natural Shipper analog with a different name (Shipper's
// `pendingBids` ↔ Carrier's `openOffers`; Shipper's
// `totalSpendThisMonth` ↔ Carrier's `weeklyRevenue`), the rename is
// in the Carrier struct — the **fetch path** still mirrors Shipper's
// `getDashboardStats` shape so the wire-format is symmetric.
// =====================================================================

struct CarrierAPI {
    unowned let api: EusoTripAPI

    /// Dashboard KPI envelope. Mirrors the convention of
    /// `shippers.getDashboardStats` on the Carrier role's home.
    /// Backend path: `carriers.getDashboardStats`.
    struct DashboardStats: Decodable, Hashable {
        /// In-flight loads currently assigned to one of the
        /// carrier's drivers (any status that is post-dispatch and
        /// pre-delivery).
        let activeLoads: Int
        /// Open offers on the carrier's board awaiting accept /
        /// decline. Carrier-side analog of Shipper's `pendingBids`.
        let openOffers: Int
        /// Loads delivered in the trailing 7-day window.
        let deliveredThisWeek: Int
        /// Carrier's blended rate-per-mile across all delivered
        /// loads in the trailing 7-day window.
        let ratePerMile: Double
        /// On-time delivery rate (0.0…1.0) over the trailing 30-
        /// day window.
        let onTimeRate: Double
        /// Net carrier revenue in the trailing 7-day window
        /// (after platform fee, before any factoring discount).
        /// Carrier-side analog of Shipper's
        /// `totalSpendThisMonth`.
        let weeklyRevenue: Double
    }

    func getDashboardStats() async throws -> DashboardStats {
        try await api.queryNoInput("carriers.getDashboardStats")
    }

    /// One in-flight load on the carrier's plate. Mirrors the
    /// shape of Shipper's `ActiveLoad` so the home cards can share
    /// row scaffolding. Backend path:
    /// `carriers.getActiveLoads`.
    struct ActiveLoad: Decodable, Identifiable, Hashable {
        let id: String
        let loadNumber: String
        let status: String
        let origin: String
        let destination: String
        /// Driver display name assigned to this load (or empty if
        /// the load is dispatched but not yet driver-assigned).
        let driver: String
        /// Broker / shipper display name (counterparty on this
        /// haul). Carrier sees who tendered the load.
        let counterparty: String
        let eta: String
        /// Gross load rate the carrier will collect on delivery
        /// (before platform fee + factoring).
        let rate: Double
    }

    struct GetActiveLoadsInput: Encodable { let limit: Int }

    func getActiveLoads(limit: Int = 10) async throws -> [ActiveLoad] {
        try await api.query(
            "carriers.getActiveLoads",
            input: GetActiveLoadsInput(limit: limit)
        )
    }

    /// One alert on the carrier's "needs attention" feed.
    /// Backend path: `carriers.getLoadsRequiringAttention`.
    /// Issue strings come from the server's exception engine
    /// (overdue check-call, detention-pending, dock-rejection,
    /// HOS-stop, breakdown, etc).
    struct LoadAlert: Decodable, Identifiable, Hashable {
        let id: String
        let loadNumber: String
        let issue: String
        let severity: String
        let message: String
    }

    func getLoadsRequiringAttention() async throws -> [LoadAlert] {
        try await api.queryNoInput("carriers.getLoadsRequiringAttention")
    }

    /// One row in the carrier's recent-activity feed (a slim
    /// summary of recently delivered loads). Backend path:
    /// `carriers.getRecentLoads`. `deliveredAt` is the server's
    /// `YYYY-MM-DD` projection of `actualDeliveryDate ??
    /// deliveryDate`; empty string when neither is set.
    struct RecentLoad: Decodable, Identifiable, Hashable {
        let id: String
        let loadNumber: String
        let status: String
        let origin: String
        let destination: String
        let deliveredAt: String
        /// Net carrier payout on this delivered load (after
        /// platform fee, before any factoring discount).
        let netPayout: Double
    }

    struct GetRecentLoadsInput: Encodable { let limit: Int }

    func getRecentLoads(limit: Int = 5) async throws -> [RecentLoad] {
        try await api.query(
            "carriers.getRecentLoads",
            input: GetRecentLoadsInput(limit: limit)
        )
    }
}

// =====================================================================
// BrokerAPI — `brokers.*` router surface for the Broker role home
// (brick 400_BrokerHome) and downstream Broker-track screens.
// ---------------------------------------------------------------------
// Added 2026-04-25 in the 99th eusotrip-killers firing, parallel to
// the dev-team's existing 300/301 Carrier surfaces. The broker sits
// between the shipper (origin) and the carrier (mover) — the home
// re-frames the four-card hierarchy around tender flow + margin
// rather than active-load count.
//
// Every procedure on this struct hits the real `brokers.*` tRPC
// router. If the parallel router has not yet shipped on the
// `brokers.*` router, the call throws `EusoTripAPIError.trpcError`
// and the Broker* stores in `ViewModels/LiveDataStores.swift` surface
// `EusoEmptyState`. This satisfies doctrine §11 (no mock data) and
// the `MockDataGuard` self-check wired at `EusoTripApp.swift:101`.
// =====================================================================

struct BrokerAPI {
    unowned let api: EusoTripAPI

    /// Dashboard KPI envelope. Mirrors the convention of
    /// `carriers.getDashboardStats` on the Broker role's home.
    /// Backend path: `brokers.getDashboardStats`.
    /// Mirrors the EXACT envelope emitted by `brokers.getDashboardStats`
    /// on `origin/main` (`frontend/server/routers/brokers.ts`):
    /// `{ activeLoads, pendingMatches, weeklyVolume, commissionEarned,
    ///    marginAverage, loadToCatalystRatio }`. Every field is optional
    /// so an older/newer deploy that drops or adds a key decodes cleanly
    /// rather than throwing — the home em-dashes any field the proc omits
    /// instead of failing the whole KPI strip.
    struct DashboardStats: Decodable, Hashable {
        /// Loads currently on the broker's plate (all statuses).
        let activeLoads: Int?
        /// Loads awaiting a carrier match.
        let pendingMatches: Int?
        /// Loads posted in the trailing 7-day window.
        let weeklyVolume: Int?
        /// Estimated broker commission earned in the trailing 7-day
        /// window (USD, server-side projection of load rate).
        let commissionEarned: Int?
        /// Average broker margin across the window (USD).
        let marginAverage: Double?
        /// Server-projected load-to-catalyst coverage ratio.
        let loadToCatalystRatio: Double?
    }

    func getDashboardStats() async throws -> DashboardStats {
        try await api.queryNoInput("brokers.getDashboardStats")
    }

    /// One open-tender row on the broker's plate. Mirrors the
    /// shape of Carrier's `ActiveLoad` so the home cards can
    /// share row scaffolding. Backend path:
    /// `brokers.getOpenTenders`.
    struct OpenTender: Decodable, Identifiable, Hashable {
        let id: String
        let loadNumber: String
        let origin: String
        let destination: String
        /// Number of carriers that have submitted a bid /
        /// response on this tender (zero is valid — newly
        /// posted tenders will start at 0 until the dispatch
        /// engine fans out to the broker's network).
        let respondingCarriers: Int
        /// Server-side projection of `postedAt` as a relative
        /// short label (e.g. "12m", "2h", "1d") suitable for
        /// inline display. Empty string when not set.
        let postedAt: String
        /// Shipper / customer display name on this tender.
        let shipper: String
        /// Target rate the broker is targeting for this
        /// tender (their ask before any carrier counter-bids).
        /// Zero when the broker has not set a target (open
        /// tender, market price).
        let targetRate: Double
        // 2026-05-17 — Multi-modal payload. Optional on the wire so
        // older deploys decode cleanly; UI defaults to truck when nil.
        // Powers the LoadModeBadge on every Broker tender row.
        let transportMode: String?
        let multiVehicleCount: Int?
    }

    struct GetOpenTendersInput: Encodable { let limit: Int }

    func getOpenTenders(limit: Int = 10) async throws -> [OpenTender] {
        try await api.query(
            "brokers.getOpenTenders",
            input: GetOpenTendersInput(limit: limit)
        )
    }

    /// One alert on the broker's "needs attention" feed.
    /// Backend path: `brokers.getLoadsRequiringAttention`.
    /// Issue strings come from the server's exception engine
    /// (carrier no-show, customer escalation, late tender,
    /// detention dispute, rate-confirmation reject, etc).
    struct LoadAlert: Decodable, Identifiable, Hashable {
        let id: String
        let loadNumber: String
        let issue: String
        let severity: String
        let message: String
    }

    func getLoadsRequiringAttention() async throws -> [LoadAlert] {
        try await api.queryNoInput("brokers.getLoadsRequiringAttention")
    }

    /// One row in the broker's recent-activity feed (a slim
    /// summary of recently delivered loads). Backend path:
    /// `brokers.getRecentLoads`. `deliveredAt` is the server's
    /// `YYYY-MM-DD` projection of `actualDeliveryDate ??
    /// deliveryDate`; empty string when neither is set.
    struct RecentLoad: Decodable, Identifiable, Hashable {
        let id: String
        let loadNumber: String
        let status: String
        let origin: String
        let destination: String
        let deliveredAt: String
        /// Net broker margin on this delivered load (after
        /// platform fee, before any factoring discount).
        let netMargin: Double
    }

    struct GetRecentLoadsInput: Encodable { let limit: Int }

    func getRecentLoads(limit: Int = 5) async throws -> [RecentLoad] {
        try await api.query(
            "brokers.getRecentLoads",
            input: GetRecentLoadsInput(limit: limit)
        )
    }
}

// =====================================================================
// CatalystAPI — `catalysts.*` router surface for the Catalyst role
// home (brick 500_CatalystHome) and downstream Catalyst-track screens.
// ---------------------------------------------------------------------
// Added 2026-04-25 in the 102nd eusotrip-killers firing, parallel to
// the Shipper (200) / Carrier (300) / Broker (400) surfaces. Catalyst
// is the AI-augmented dispatch / SpectraMatch operator role per the
// EusoTrip backend §16 intelligence slice (Autopilot 7-layer cortex,
// 52 agents). The home re-frames the four-card hierarchy around match
// flow + SpectraMatch fit-score rather than tender flow or active-
// load count.
//
// Every procedure on this struct hits the real `catalysts.*` tRPC
// router. If the parallel router has not yet shipped on the
// `catalysts.*` namespace, the call throws
// `EusoTripAPIError.trpcError` and the Catalyst* stores in
// `ViewModels/LiveDataStores.swift` surface `EusoEmptyState`. This
// satisfies doctrine §11 (no mock data) and the `MockDataGuard`
// self-check wired at `EusoTripApp.swift:101`.
// =====================================================================

struct CatalystAPI {
    unowned let api: EusoTripAPI

    /// Dashboard KPI envelope. Mirrors the convention of
    /// `brokers.getDashboardStats` on the Catalyst role's home.
    /// Backend path: `catalysts.getDashboardStats`.
    struct DashboardStats: Decodable, Hashable {
        /// Live SpectraMatch / autopilot match sessions the catalyst
        /// is currently running (an "active match" is a load with
        /// at least one autopilot agent in the loop). Catalyst-side
        /// analog of Carrier's `activeLoads` and Broker's
        /// `openTenders`.
        let activeMatches: Int
        /// Loads that resolved to a carrier-accepted match in the
        /// trailing 7-day window.
        let matchedThisWeek: Int
        /// Matched loads that delivered through the catalyst's lane
        /// in the trailing 7-day window.
        let deliveredThisWeek: Int
        /// Average SpectraMatch best-fit score across resolved
        /// matches in the trailing 7-day window (0.0…1.0).
        let avgFitScore: Double
        /// On-time delivery rate (0.0…1.0) for matched loads in the
        /// trailing 30-day window.
        let onTimeRate: Double
        /// Gross merchandise value (lane revenue) of loads matched
        /// through this catalyst in the trailing 7-day window.
        /// Catalyst-side analog of Broker's `grossMarginThisWeek`
        /// and Carrier's `weeklyRevenue` — reframed as GMV since
        /// the catalyst doesn't capture margin or rate, only
        /// match volume.
        let gmvThisWeek: Double
    }

    func getDashboardStats() async throws -> DashboardStats {
        try await api.queryNoInput("catalysts.getDashboardStats")
    }

    /// One active SpectraMatch / autopilot session row on the
    /// catalyst's plate. Mirrors the shape of Broker's `OpenTender`
    /// so the home cards can share row scaffolding. Backend path:
    /// `catalysts.getActiveMatches`.
    struct ActiveMatch: Decodable, Identifiable, Hashable {
        let id: String
        let loadNumber: String
        let origin: String
        let destination: String
        /// Number of carrier candidates the autopilot has scored
        /// for this load (zero is valid — newly fired matches
        /// will start at 0 until SpectraMatch fans out across the
        /// network).
        let candidateCount: Int
        /// Server-side projection of `startedAt` as a relative
        /// short label (e.g. "2m", "12m", "1h") suitable for
        /// inline display. Empty string when not set.
        let startedAt: String
        /// Display name of the autopilot agent driving this match
        /// (one of the 52 agents in the §16 intelligence slice).
        /// Empty when the catalyst is running the match manually
        /// without an agent attached.
        let agentName: String
        /// Highest SpectraMatch fit score across all candidates on
        /// this match (0.0…1.0). Zero when no carrier has been
        /// scored yet.
        let bestFitScore: Double
        // ─── 2026-05-17 · Multi-modal payload ───
        // Powers LoadModeBadge on every catalyst match row so a rail
        // unit-train or vessel charter never gets carrier-matched as
        // a single dry-van. Optional on the wire so older deploys
        // decode cleanly.
        let transportMode: String?
        let multiVehicleCount: Int?
    }

    struct GetActiveMatchesInput: Encodable { let limit: Int }

    func getActiveMatches(limit: Int = 10) async throws -> [ActiveMatch] {
        try await api.query(
            "catalysts.getActiveMatches",
            input: GetActiveMatchesInput(limit: limit)
        )
    }

    /// One alert on the catalyst's "needs attention" feed.
    /// Backend path: `catalysts.getLoadsRequiringAttention`. Issue
    /// strings come from the server's exception engine (match
    /// stall, fit drift, autopilot fault, capacity shortage,
    /// rate misfit, etc).
    struct LoadAlert: Decodable, Identifiable, Hashable {
        let id: String
        let loadNumber: String
        let issue: String
        let severity: String
        let message: String
    }

    func getLoadsRequiringAttention() async throws -> [LoadAlert] {
        try await api.queryNoInput("catalysts.getLoadsRequiringAttention")
    }

    /// One row in the catalyst's recent-activity feed (a slim
    /// summary of recently resolved matches). Backend path:
    /// `catalysts.getRecentMatches`. `resolvedAt` is the server's
    /// `YYYY-MM-DD` projection of `actualMatchedAt ?? matchedAt`;
    /// empty string when neither is set.
    struct RecentMatch: Decodable, Identifiable, Hashable {
        let id: String
        let loadNumber: String
        let status: String
        let origin: String
        let destination: String
        let resolvedAt: String
        /// Final SpectraMatch fit score on the carrier this match
        /// resolved to (0.0…1.0). Zero when the match resolved
        /// without a SpectraMatch lock (manual override).
        let finalFitScore: Double
    }

    struct GetRecentMatchesInput: Encodable { let limit: Int }

    func getRecentMatches(limit: Int = 5) async throws -> [RecentMatch] {
        try await api.query(
            "catalysts.getRecentMatches",
            input: GetRecentMatchesInput(limit: limit)
        )
    }

    /// One driver row on the Catalyst fleet roster. Backed by
    /// `catalysts.getMyDrivers` (frontend/server/routers/catalysts.ts:382)
    /// — server resolves the catalyst's companyId from the auth ctx,
    /// joins drivers ↔ users for the display name, then per-row
    /// joins the live `loads` row (in_transit / assigned status) for
    /// `currentLoad`, the latest `hos_logs` row for `hoursRemaining`
    /// (660-min cap minus today's drivingMinutesAtEvent → hours), and
    /// the latest `gps_tracking` row for `location` (lat,lng tuple
    /// rendered as a "DD.DD, DD.DD" pair). Catalyst↔Driver relationship
    /// surface — this is the canonical roster the §11.4 sole-driver
    /// Eusotrans LLC carrier renders on its 304 Fleet · Drivers screen.
    struct FleetDriver: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        /// "driving" when there's an active load, otherwise the
        /// drivers.status column ("available", "off_duty", etc.).
        let status: String
        /// Active load number if the driver is currently in_transit
        /// or assigned, nil otherwise.
        let currentLoad: String?
        /// Hours of drive time remaining today (0.0…11.0). Nil when
        /// the driver hasn't logged a HOS event today.
        let hoursRemaining: Double?
        /// "lat, lng" formatted to 2 decimals, or "Unknown" when no
        /// GPS data is available for this driver yet.
        let location: String
        /// T-021 · 2026-05-20 — Canonical CDL endorsement codes the
        /// driver holds, sourced from `drivers.endorsements[]` once
        /// the server column ships. Optional during the migration —
        /// the catalyst-side filter treats nil as "endorsements
        /// unknown" and excludes the driver when any endorsement is
        /// required (fail-safe; better to over-filter than to assign
        /// a non-endorsed driver to a hazmat load).
        let endorsementCodes: [String]?

        /// Convenience — typed endorsement set for the canonical
        /// `required.isSubset(of:)` filter pattern. Empty when the
        /// server hasn't shipped endorsement data yet.
        var endorsements: Set<DriverEndorsement> {
            Set((endorsementCodes ?? []).compactMap { DriverEndorsement(rawValue: $0) })
        }
    }

    struct GetMyDriversInput: Encodable { let limit: Int }

    func getMyDrivers(limit: Int = 25) async throws -> [FleetDriver] {
        try await api.query(
            "catalysts.getMyDrivers",
            input: GetMyDriversInput(limit: limit)
        )
    }
}

// =====================================================================
// EscortAPI — `escorts.*` router surface for the Escort role
// home (brick 600_EscortHome) and downstream Escort-track screens.
// ---------------------------------------------------------------------
// Added 2026-04-25 in the 103rd eusotrip-killers firing, parallel to
// the Shipper (200) / Carrier (300) / Broker (400) / Catalyst (500)
// surfaces. Escort is the regulated-corridor pilot-car / safety-escort
// operator role per the EusoTrip backend §16 compliance-safety slice
// (`escortOverview`, `escort_*` tables, bridge clearance integration).
// The home re-frames the four-card hierarchy around live assignment
// flow + corridor coverage rather than match flow or tender flow.
//
// Every procedure on this struct hits the real `escorts.*` tRPC
// router. If the parallel router has not yet shipped on the
// `escorts.*` namespace, the call throws
// `EusoTripAPIError.trpcError` and the Escort* stores in
// `ViewModels/LiveDataStores.swift` surface `EusoEmptyState`. This
// satisfies doctrine §11 (no mock data) and the `MockDataGuard`
// self-check wired at `EusoTripApp.swift:101`.
// =====================================================================

struct EscortAPI {
    unowned let api: EusoTripAPI

    /// Dashboard KPI envelope. Mirrors the convention of
    /// `catalysts.getDashboardStats` on the Escort role's home.
    /// Backend path: `escorts.getDashboardStats`.
    struct DashboardStats: Decodable, Hashable {
        /// Live escort assignments the operator is currently
        /// piloting (an "active assignment" is a load with at
        /// least one lead/chase escort vehicle in the corridor).
        /// Escort-side analog of Catalyst's `activeMatches` and
        /// Broker's `openTenders`.
        let activeAssignments: Int
        /// Loads that resolved to a completed escort delivery in
        /// the trailing 7-day window.
        let completedThisWeek: Int
        /// Total escort-corridor mileage piloted in the trailing
        /// 7-day window.
        let milesThisWeek: Double
        /// Mean corridor-coverage ratio (0.0…1.0) across active
        /// and recently-resolved escort assignments. New semantic
        /// for the Escort role; replaces Catalyst's `avgFitScore`.
        let corridorCoverage: Double
        /// On-time delivery rate (0.0…1.0) for escort-piloted
        /// loads in the trailing 30-day window.
        let onTimeRate: Double
        /// Lane revenue captured by the escort operator in the
        /// trailing 7-day window. Escort-side analog of Catalyst's
        /// `gmvThisWeek` and Broker's `grossMarginThisWeek`.
        let revenueThisWeek: Double
    }

    func getDashboardStats() async throws -> DashboardStats {
        try await api.queryNoInput("escorts.getDashboardStats")
    }

    /// One active escort assignment row on the operator's plate.
    /// Mirrors the shape of Catalyst's `ActiveMatch` so the home
    /// cards can share row scaffolding. Backend path:
    /// `escorts.getActiveAssignments`.
    struct ActiveAssignment: Decodable, Identifiable, Hashable {
        let id: String
        let loadNumber: String
        let origin: String
        let destination: String
        /// Whether this escort vehicle is leading or chasing the
        /// piloted load. Server-side enum (e.g. "lead", "chase",
        /// "lead+chase") rendered uppercase in the row.
        let escortRole: String
        /// Server-side projection of `startedAt` as a relative
        /// short label (e.g. "2m", "12m", "1h") suitable for
        /// inline display. Empty string when not set.
        let startedAt: String
        /// Permit number authorizing this corridor (OS/OW, hazmat,
        /// etc.). Empty when no permit attached.
        let permitNumber: String
        /// Live corridor-coverage ratio (0.0…1.0) — the proportion
        /// of the routed corridor currently covered by lead/chase
        /// escort presence. Zero when no escort vehicle has rolled.
        let corridorCoverage: Double
    }

    struct GetActiveAssignmentsInput: Encodable { let limit: Int }

    func getActiveAssignments(limit: Int = 10) async throws -> [ActiveAssignment] {
        try await api.query(
            "escorts.getActiveAssignments",
            input: GetActiveAssignmentsInput(limit: limit)
        )
    }

    /// One alert on the escort operator's "needs attention" feed.
    /// Backend path: `escorts.getLoadsRequiringAttention`. Issue
    /// strings come from the server's exception engine (clearance
    /// breach, route deviation, escort handoff stall, lead/chase
    /// imbalance, permit drift, etc).
    struct LoadAlert: Decodable, Identifiable, Hashable {
        let id: String
        let loadNumber: String
        let issue: String
        let severity: String
        let message: String
    }

    func getLoadsRequiringAttention() async throws -> [LoadAlert] {
        try await api.queryNoInput("escorts.getLoadsRequiringAttention")
    }

    /// One row in the escort operator's recent-activity feed (a
    /// slim summary of recently completed escort assignments).
    /// Backend path: `escorts.getRecentAssignments`. `resolvedAt`
    /// is the server's `YYYY-MM-DD` projection of
    /// `actualClosedAt ?? closedAt`; empty string when neither is
    /// set.
    struct RecentAssignment: Decodable, Identifiable, Hashable {
        let id: String
        let loadNumber: String
        let status: String
        let origin: String
        let destination: String
        let resolvedAt: String
        /// Final corridor-coverage ratio (0.0…1.0) achieved on
        /// the resolved escort assignment. Zero when the assignment
        /// resolved without coverage data (manual override).
        let finalCoverage: Double
    }

    struct GetRecentAssignmentsInput: Encodable { let limit: Int }

    func getRecentAssignments(limit: Int = 5) async throws -> [RecentAssignment] {
        try await api.query(
            "escorts.getRecentAssignments",
            input: GetRecentAssignmentsInput(limit: limit)
        )
    }

    // MARK: - Assignment detail (601_EscortAssignmentDetail)
    //
    // Added 2026-04-27 in the 147th eusotrip-killers firing as the
    // detail surface drilled into from `getActiveAssignments` rows on
    // brick 600. Mirrors the 502_CatalystMatchDetail / 402_BrokerTender
    // /302_CarrierLoadDetail pattern: the row tap presents the full
    // assignment record so the operator can review the corridor route,
    // lead/chase pairing, permit, hazmat / OS-OW context, and confirm
    // the route before they roll. Backend path:
    // `escorts.getActiveAssignmentDetail` (input `{ id: string }`).
    //
    // If the parallel router has not yet shipped the detail procedure,
    // the call throws `EusoTripAPIError.trpcError` and the
    // `EscortAssignmentDetailStore` resolves to `.error` — the screen
    // surfaces an honest retry banner. No fixture data, ever (doctrine
    // §11 + `MockDataGuard`).

    /// Full escort-assignment record served by
    /// `escorts.getActiveAssignmentDetail`. Strict superset of the
    /// `ActiveAssignment` row shape — the detail screen reads both
    /// the live envelope (corridorCoverage, escortRole, started…) and
    /// the deeper fields (route legs, lead/chase pairing, permit /
    /// hazmat / OS-OW context). Optional fields surface as `nil` on
    /// the wire and as em-dash sentinels in the UI per §13 doctrine.
    struct AssignmentDetail: Decodable, Identifiable, Hashable {
        let id: String
        let loadNumber: String
        let origin: String
        let destination: String
        /// Server-side enum: "lead", "chase", "lead+chase", or "" when
        /// no escort vehicle is paired yet.
        let escortRole: String
        /// ISO-8601 timestamp the corridor went live; empty string
        /// when the assignment hasn't rolled yet.
        let startedAt: String
        /// OS/OW / hazmat permit number authorizing this corridor.
        /// Empty string when none attached.
        let permitNumber: String
        /// Live corridor-coverage ratio (0.0…1.0).
        let corridorCoverage: Double
        /// Coarse status enum from the server. Examples:
        /// `pending`, `dispatched`, `enroute`, `at_origin`, `at_destination`,
        /// `completed`, `cancelled`. Rendered uppercase in the UI.
        let status: String
        /// Stage-2 fields (optional — server returns `null` until the
        /// corridor is fully resolved). Each is wrapped optionally so
        /// the UI can decide whether to render the row.
        let routedMiles: Double?
        let routeName: String?
        /// Permit + corridor compliance metadata.
        let hazmatClass: String?
        let unNumber: String?
        let oversizeFlag: Bool?
        let overweightFlag: Bool?
        let bridgeClearanceFt: Double?
        /// Lead / chase vehicle identifiers (server-side strings).
        /// Empty string when no escort vehicle paired yet.
        let leadVehicleId: String?
        let chaseVehicleId: String?
        /// Driver / shipper / broker contact metadata.
        let driverName: String?
        let driverPhone: String?
        let shipperName: String?
        /// Free-form corridor notes / restrictions from dispatch.
        let notes: String?
        /// Whether the operator has already confirmed the route on
        /// this assignment. Drives the CTA's enable/disable state.
        let routeConfirmed: Bool?
    }

    struct GetActiveAssignmentDetailInput: Encodable { let id: String }

    func getActiveAssignmentDetail(id: String) async throws -> AssignmentDetail? {
        try await api.query(
            "escorts.getActiveAssignmentDetail",
            input: GetActiveAssignmentDetailInput(id: id)
        )
    }

    /// Mutation acknowledging that the operator has reviewed and
    /// confirmed the routed corridor for an active assignment.
    /// Backend path: `escorts.confirmRoute` (input `{ id: string }`).
    /// Returns the updated `AssignmentDetail` so the UI can re-paint
    /// without an extra round-trip. If the router hasn't shipped, the
    /// call throws and the CTA flips back to its idle label with an
    /// honest inline error — the local state never lies about the
    /// commit landing.
    struct ConfirmRouteInput: Encodable { let id: String }

    func confirmRoute(id: String) async throws -> AssignmentDetail {
        try await api.mutation(
            "escorts.confirmRoute",
            input: ConfirmRouteInput(id: id)
        )
    }

    // MARK: - Corridor map (602_EscortCorridorMap)
    //
    // Added 2026-04-27 in the 159th eusotrip-killers firing as the
    // third Escort-track surface. Drilled into from
    // 601_EscortAssignmentDetail's "View corridor →" sheet CTA — the
    // operator opens the corridor map to inspect the routed legs,
    // milestone schedule, geofences, and lead/chase pairing visualised
    // along the corridor. Backend path: `escorts.getCorridor` (input
    // `{ id: string }`).
    //
    // Single-read envelope mirrors the convention of
    // `terminals.getYardMap` and `admin.getControlTowerOverview` — the
    // server returns the full corridor topology (route legs +
    // milestones + geofences + KPI counts) in one payload so the
    // screen can render its full state from a single fetch. If the
    // parallel router has not yet shipped the procedure, the call
    // throws `EusoTripAPIError.trpcError` and the
    // `EscortCorridorStore` resolves to `.error` — the screen
    // surfaces an honest retry banner. No fixture data ever
    // (doctrine §11 + `MockDataGuard`).

    /// One leg of the routed corridor (origin → waypoint, waypoint →
    /// waypoint, …, waypoint → destination). Server-shaped so the UI
    /// never needs to compute leg geometry locally. Empty `name` /
    /// nil distance fold to em-dash sentinels in the UI.
    struct CorridorLeg: Decodable, Identifiable, Hashable {
        let id: String
        /// Display label (e.g. "Leg 1 · Yard → Bridge"). Server-formatted.
        let label: String
        /// Origin waypoint identifier or place name for the leg.
        let origin: String
        /// Destination waypoint identifier or place name for the leg.
        let destination: String
        /// Server-projected leg distance in miles. `nil` until the
        /// route engine resolves the geometry.
        let miles: Double?
        /// Coverage ratio (0.0…1.0) — the proportion of this leg
        /// already piloted by an escort vehicle. Zero on a leg that
        /// hasn't rolled yet.
        let coverage: Double
        /// Server-side enum: "pending", "active", "completed",
        /// "skipped". Drives the leg's status pill.
        let status: String
        /// Coarse hazmat / OS-OW chip rendered on the leg row when
        /// the leg crosses a regulated segment. Empty when none.
        let chips: [String]?
    }

    /// One milestone the operator must hit along the corridor —
    /// permit check-in, bridge clearance survey, weigh stop, escort
    /// handoff, etc. Server-defined ordering. `eta` and `elapsed`
    /// are server-projected short labels suitable for inline display.
    struct CorridorMilestone: Decodable, Identifiable, Hashable {
        let id: String
        /// Display label ("Permit check", "Bridge clearance survey", …).
        let label: String
        /// Server-side enum: "pending", "in_progress", "completed",
        /// "skipped".
        let status: String
        /// Optional short ETA label (e.g. "in 12m", "in 1h 20m").
        /// Empty when not scheduled or already completed.
        let eta: String?
        /// Optional short elapsed label for completed milestones
        /// (e.g. "12m ago"). Empty when not yet completed.
        let elapsed: String?
        /// Optional milestone note / remark from dispatch. Empty when
        /// none attached.
        let note: String?
    }

    /// One geofence overlay along the corridor (bridge clearance
    /// zone, hazmat exclusion, weigh-station bypass, etc.). The UI
    /// renders a chip row — full polygon rendering is server-side
    /// when the corridor is presented in the EusoTrip mapping engine.
    struct CorridorGeofence: Decodable, Identifiable, Hashable {
        let id: String
        /// Display label.
        let label: String
        /// Geofence kind ("bridge_clearance", "hazmat_exclusion",
        /// "weigh_station_bypass", "ports_of_entry", …). Drives icon
        /// pick.
        let kind: String
        /// Optional short status: "armed", "breached", "cleared".
        let status: String?
    }

    /// Lead / chase escort vehicle envelope — flattened so the UI
    /// renders the pairing card without re-merging fields from the
    /// detail surface. Empty when no vehicle paired yet.
    struct CorridorEscortVehicle: Decodable, Hashable {
        /// Server-side enum: "lead", "chase".
        let role: String
        /// Vehicle identifier (e.g. "PILOT-12", "ESC-3-A").
        let vehicleId: String
        /// Optional driver name.
        let driverName: String?
        /// Optional last-known place label (e.g. "I-44 mp 142").
        let lastKnownLocation: String?
        /// Optional short relative-time label for the last ping
        /// (e.g. "2m", "15m").
        let lastPingAt: String?
    }

    /// Corridor map envelope. Mirrors `terminals.getYardMap` shape
    /// (single read, server-shaped payload). Backend path:
    /// `escorts.getCorridor`.
    struct EscortCorridor: Decodable, Hashable {
        /// The escort assignment id this corridor belongs to.
        let id: String
        /// Load number for the piloted load.
        let loadNumber: String
        /// Origin / destination labels (mirrors `AssignmentDetail`).
        let origin: String
        /// Origin / destination labels (mirrors `AssignmentDetail`).
        let destination: String
        /// Optional named route the corridor follows.
        let routeName: String?
        /// Total routed miles for the corridor (server-summed across
        /// legs). `nil` until the route engine resolves geometry.
        let routedMiles: Double?
        /// Server-computed mean coverage ratio (0.0…1.0) across legs.
        let corridorCoverage: Double
        /// Server-side enum mirroring `AssignmentDetail.status`.
        let status: String
        /// Legs in render order.
        let legs: [CorridorLeg]
        /// Milestones in dispatch order.
        let milestones: [CorridorMilestone]
        /// Geofence overlays.
        let geofences: [CorridorGeofence]
        /// Paired escort vehicles (lead / chase). Empty when none paired.
        let escortVehicles: [CorridorEscortVehicle]
        /// Server-computed legs-completed counter for the header KPI
        /// strip. Saves the UI from re-summing client-side.
        let legsCompleted: Int
        /// Server-computed total leg count for the header KPI strip.
        let legsTotal: Int
        /// Optional bridge clearance feet for the corridor's most
        /// restrictive leg. `nil` when no clearance survey attached.
        let bridgeClearanceFt: Double?
        /// Optional permit number authorising the corridor.
        let permitNumber: String?
    }

    struct GetCorridorInput: Encodable { let id: String }

    func getCorridor(id: String) async throws -> EscortCorridor? {
        try await api.query(
            "escorts.getCorridor",
            input: GetCorridorInput(id: id)
        )
    }
}

// =====================================================================
// MARK: - terminalsRouter
//
// Mirrors `frontend/server/routers/terminals.ts` 1:1. Terminal Manager
// owns port/yard operations across the EusoTrip ecosystem:
//
//   • Gate-in / gate-out flow for trucks crossing the terminal fence.
//   • Container movements between staging, dock, and rail spur (per
//     the §16 intermodal-xborder slice — chassis pool / drayage / ISF
//     10+2 gate).
//   • Dock assignment + dwell + demurrage exposure (the same dwell
//     model the Driver `015_AtGateAwaitingDock` brick reads from the
//     other side of the gate).
//   • Hazmat clearance + ADR/IMDG/TDG holds (compliance-safety slice).
//
// Procedure coverage (mirrors carriers/brokers/catalysts/escorts):
//   • getDashboardStats           — six-figure KPI envelope
//   • getActiveMovements          — yard rows currently in motion
//   • getMovementsRequiringAttention — exception engine alerts
//   • getRecentMovements          — recently-resolved gate-outs
//
// If the parallel router has not yet shipped on the `terminals.*`
// namespace, the call throws `EusoTripAPIError.trpcError` and the
// Terminal* stores in `ViewModels/LiveDataStores.swift` surface
// `EusoEmptyState`. This satisfies doctrine §11 (no mock data) and
// the `MockDataGuard` self-check wired at `EusoTripApp.swift:101`.
// =====================================================================

struct TerminalAPI {
    unowned let api: EusoTripAPI

    /// Dashboard KPI envelope. Mirrors the convention of
    /// `escorts.getDashboardStats` on the Terminal role's home.
    /// Backend path: `terminals.getDashboardStats`.
    struct DashboardStats: Decodable, Hashable {
        /// Live container/truck movements the terminal is currently
        /// processing (a "movement" is a yard row not yet at
        /// `GATED_OUT` / `DEPARTED`). Terminal-side analog of
        /// Escort's `activeAssignments` and Broker's `openTenders`.
        let activeMovements: Int
        /// Movements that resolved to a completed gate-out in the
        /// trailing 7-day window.
        let completedThisWeek: Int
        /// Mean dwell time (hours) across resolved movements in the
        /// trailing 7-day window. Drives demurrage exposure
        /// projections — anything above `freeDwellHours` on a
        /// shipping-line container is the terminal's exposure.
        let avgDwellHoursThisWeek: Double
        /// Total movements processed (gate-in + gate-out events) in
        /// the trailing 7-day window. Throughput proxy for terminal
        /// utilization KPI on the operations dashboard.
        let throughputThisWeek: Int
        /// On-time gate-out rate (0.0…1.0) versus the appointment
        /// window for the trailing 30-day window. Below 0.85 is the
        /// terminal-ops red line.
        let onTimeRate: Double
        /// Live gate utilization ratio (0.0…1.0). 1.0 means every
        /// scheduled gate slot in the next hour is occupied; below
        /// 0.5 indicates wasted gate capacity.
        let gateUtilization: Double
    }

    func getDashboardStats() async throws -> DashboardStats {
        try await api.queryNoInput("terminals.getDashboardStats")
    }

    /// One active terminal movement row. Mirrors the shape of the
    /// other role active-row types (`EscortAPI.ActiveAssignment`,
    /// `CatalystAPI.ActiveMatch`) so the home cards can share row
    /// scaffolding. Backend path: `terminals.getActiveMovements`.
    struct ActiveMovement: Decodable, Identifiable, Hashable {
        let id: String
        /// Load number / shipment number / container number — the
        /// terminal-facing identifier the operator looks up by. Server
        /// projects whichever is most specific for the movement type.
        let loadNumber: String
        /// Origin city/state or upstream port/rail yard.
        let origin: String
        /// Destination city/state or downstream port/rail yard.
        let destination: String
        /// Movement stage as a server-side enum: "AT_GATE",
        /// "ON_YARD", "AT_DOCK", "STAGING", "AT_RAIL_SPUR", etc.
        /// Rendered uppercase in the row.
        let stage: String
        /// Server-side projection of `arrivedAt` as a relative
        /// short label (e.g. "2m", "12m", "1h") suitable for inline
        /// display. Empty string when not set.
        let arrivedAt: String
        /// Dock assignment for this movement, e.g. "D-12",
        /// "Spur 3", "Yard A-7". Empty when no dock yet assigned.
        let dockAssignment: String
        /// Live dwell time (hours) since gate-in. Drives the
        /// demurrage exposure column on the home card.
        let dwellHours: Double
    }

    struct GetActiveMovementsInput: Encodable { let limit: Int }

    func getActiveMovements(limit: Int = 10) async throws -> [ActiveMovement] {
        try await api.query(
            "terminals.getActiveMovements",
            input: GetActiveMovementsInput(limit: limit)
        )
    }

    /// One alert on the terminal operator's "needs attention" feed.
    /// Backend path: `terminals.getMovementsRequiringAttention`.
    /// Issue strings come from the server's exception engine
    /// (dwell breach, demurrage exposure, dock conflict, hazmat
    /// clearance pending, BOL mismatch, ISF 10+2 hold, etc).
    struct MovementAlert: Decodable, Identifiable, Hashable {
        let id: String
        let loadNumber: String
        let issue: String
        let severity: String
        let message: String
    }

    func getMovementsRequiringAttention() async throws -> [MovementAlert] {
        try await api.queryNoInput("terminals.getMovementsRequiringAttention")
    }

    /// One row in the terminal operator's recent-activity feed (a
    /// slim summary of recently completed gate-outs / movements).
    /// Backend path: `terminals.getRecentMovements`. `resolvedAt`
    /// is the server's `YYYY-MM-DD` projection of `gatedOutAt ??
    /// closedAt`; empty string when neither is set.
    struct RecentMovement: Decodable, Identifiable, Hashable {
        let id: String
        let loadNumber: String
        let status: String
        let origin: String
        let destination: String
        let resolvedAt: String
        /// Final dwell time (hours) on the resolved movement. Zero
        /// when the movement resolved without dwell tracking.
        let finalDwellHours: Double
    }

    struct GetRecentMovementsInput: Encodable { let limit: Int }

    func getRecentMovements(limit: Int = 5) async throws -> [RecentMovement] {
        try await api.query(
            "terminals.getRecentMovements",
            input: GetRecentMovementsInput(limit: limit)
        )
    }

    // MARK: - Gate queue (701_TerminalGateQueue)
    //
    // Added 2026-04-27 in the 150th eusotrip-killers firing as the
    // detail surface drilled into from the 700 active-movements
    // section header. Mirrors the 601_EscortAssignmentDetail pattern
    // (147th firing): the operator opens a sheet that shows the full
    // list of trucks/containers currently waiting for a dock, each
    // row with an inline "Assign dock" mutation.
    //
    // Backend procedure pair:
    //   • `terminals.getGateQueue`  — input `{ limit: number }`,
    //     returns `[GateQueueItem]`. Empty list when no gate-queue
    //     items pending.
    //   • `terminals.assignDock`    — input `{ id: string, dock: string }`,
    //     returns the updated `GateQueueItem` so the UI can re-paint
    //     the row without an extra round-trip.
    //
    // If the parallel router has not yet shipped, every call throws
    // `EusoTripAPIError.trpcError` and the `TerminalGateQueueStore`
    // resolves to `.error` — the screen surfaces an honest retry
    // banner. No fixture data, ever (doctrine §11 + `MockDataGuard`).

    /// One row in the terminal operator's gate queue (a movement that
    /// has gated in and is currently waiting for a dock assignment or
    /// hazmat clearance). Strict superset of the `ActiveMovement` row
    /// so the 701 detail can render the same `loadNumber / origin /
    /// destination / stage / arrivedAt` columns without a translation
    /// shim. Backend path: `terminals.getGateQueue`.
    struct GateQueueItem: Decodable, Identifiable, Hashable {
        let id: String
        /// Load number / shipment number / container number — terminal-
        /// facing identifier. Empty when the row is a placeholder.
        let loadNumber: String
        /// Origin city/state or upstream port/rail yard.
        let origin: String
        /// Destination city/state or downstream port/rail yard.
        let destination: String
        /// Movement stage as a server-side enum: "AT_GATE",
        /// "STAGING", "AT_DOCK", etc. Rendered uppercase.
        let stage: String
        /// Server-side projection of `arrivedAt` as a relative short
        /// label (e.g. "2m", "12m", "1h"). Empty string when not set.
        let arrivedAt: String
        /// Current dock assignment (e.g. "D-12"). Empty when the row
        /// is still waiting for the operator's call.
        let dockAssignment: String
        /// Live dwell time (hours) since gate-in. Drives the demurrage
        /// exposure column on the queue row.
        let dwellHours: Double
        /// Optional priority hint from the server's queue scheduler:
        /// "expedited", "appointment", "standby", or empty. Drives the
        /// gradient priority chip on the row.
        let priority: String?
        /// Optional hazmat class code (e.g. "2.2", "3", "8") when the
        /// movement carries regulated freight. Empty/absent when none.
        let hazmatClass: String?
        /// Optional appointment window the queue row was scheduled
        /// against, server-projected as a short label like
        /// "08:30–09:00" or "08:30 ETA". Empty when none scheduled.
        let appointmentWindow: String?
    }

    struct GetGateQueueInput: Encodable { let limit: Int }

    func getGateQueue(limit: Int = 25) async throws -> [GateQueueItem] {
        try await api.query(
            "terminals.getGateQueue",
            input: GetGateQueueInput(limit: limit)
        )
    }

    /// Mutation that assigns a dock identifier to a queue row. Backend
    /// path: `terminals.assignDock` (input `{ id: string, dock: string }`).
    /// Returns the updated `GateQueueItem` so the UI can re-paint the
    /// row without an extra round-trip. If the router hasn't shipped,
    /// the call throws and the inline CTA flips back to its idle label
    /// with an honest error — local state never lies about the commit
    /// landing.
    struct AssignDockInput: Encodable {
        let id: String
        let dock: String
    }

    func assignDock(id: String, dock: String) async throws -> GateQueueItem {
        try await api.mutation(
            "terminals.assignDock",
            input: AssignDockInput(id: id, dock: dock)
        )
    }

    // MARK: - Yard map (702_TerminalYardMap)
    //
    // Added 2026-04-27 in the 154th eusotrip-killers firing as the third
    // brick on the Terminal Manager role track (700s). Drilled into from
    // 700_TerminalHome's "Yard" trailing nav slot — shows the full yard
    // occupancy by zone, with each slot rendered as a tile (free / occupied)
    // and per-slot mutation to release a slot when a truck departs.
    //
    // Backend procedure pair:
    //   • `terminals.getYardMap`   — input `{}`, returns `YardMap` with
    //     `zones: [YardZone]` (each zone has `slots: [YardSlot]`). When
    //     the yard is empty the server returns zones with empty slot
    //     arrays — the screen renders zone scaffolding with em-dashed
    //     slots so the operator sees the geometry of the yard even at
    //     idle.
    //   • `terminals.releaseSlot`  — input `{ id: string }`, returns the
    //     updated `YardSlot` (now empty) so the UI can re-paint the tile
    //     without an extra round-trip.
    //
    // If the parallel router has not yet shipped, every call throws
    // `EusoTripAPIError.trpcError` and the `TerminalYardMapStore`
    // resolves to `.error` — the screen surfaces an honest retry
    // banner. No fixture data, ever (doctrine §11 + `MockDataGuard`).

    /// One yard zone — a grouping of physical slots (Zone A, Spur 3,
    /// Dock Row, Reefer Row, Hazmat Pad). Mirrors the server's
    /// physical-yard topology so the operator's mental model maps
    /// directly to the on-screen layout.
    struct YardZone: Decodable, Identifiable, Hashable {
        let id: String
        /// Display label, e.g. "ZONE A", "SPUR 3", "REEFER ROW".
        /// Server projects pre-uppercased; rendered as-is.
        let label: String
        /// Optional kind hint from the server: "STAGING", "DOCK",
        /// "RAIL_SPUR", "REEFER", "HAZMAT", or empty. Used to pick
        /// the zone's leading SF Symbol (and nothing else — fills
        /// stay neutral; only the priority chip on a slot uses
        /// gradient).
        let kind: String?
        /// Slots belonging to this zone, server-ordered. Server returns
        /// every slot in the zone, including unoccupied ones, so the
        /// operator sees yard geometry at idle.
        let slots: [YardSlot]
    }

    /// One yard slot — a discrete physical position that may or may not
    /// hold a truck/container. Empty slots have empty `loadNumber` /
    /// `containerNumber` and zero `dwellHours`, so the row falls back
    /// to em-dash sentinels.
    struct YardSlot: Decodable, Identifiable, Hashable {
        let id: String
        /// Slot identifier rendered on the tile, e.g. "A-3", "S3-12",
        /// "D-7", "RR-2". Server projects pre-formatted.
        let label: String
        /// Load number / shipment number / container number occupying
        /// this slot. Empty when the slot is free.
        let loadNumber: String
        /// Container number when the slot holds an ocean/intermodal
        /// container (e.g. "MSCU 123-4567"). Empty when not applicable.
        let containerNumber: String
        /// Live dwell time (hours) since the slot was occupied. Zero
        /// when the slot is free. Drives the demurrage exposure chip.
        let dwellHours: Double
        /// Optional hazmat class code (e.g. "2.2", "3", "8") when the
        /// occupied movement carries regulated freight. Empty/absent
        /// when none.
        let hazmatClass: String?
        /// Optional appointment window the slot was scheduled against,
        /// server-projected as a short label like "08:30–09:00". Empty
        /// when none scheduled.
        let appointmentWindow: String?
        /// Whether the slot is currently occupied. The server is the
        /// authority — the UI never infers from `loadNumber` because
        /// the server may report a slot as "occupied" while the load
        /// is in the staging-to-dock transit window before the load
        /// number flips.
        let occupied: Bool
    }

    /// Yard map envelope. Mirrors the convention of `escorts.getCorridor`
    /// and `admin.getControlTowerOverview` — single read, server-shaped
    /// payload. Backend path: `terminals.getYardMap`.
    struct YardMap: Decodable, Hashable {
        /// Zones in render order, each carrying its own slots. Server
        /// returns the empty array only when the yard hasn't been
        /// configured at all (which the screen treats as `.empty`).
        let zones: [YardZone]
        /// Total slot count across all zones. Server-computed so the
        /// header KPI doesn't need a client-side sum (and stays right
        /// when the server filters slots the operator can't see).
        let totalSlots: Int
        /// Occupied slot count. Drives the occupancy ratio in the
        /// header KPI strip.
        let occupiedSlots: Int
        /// Server-computed mean dwell hours across occupied slots.
        /// Zero when no slots occupied.
        let avgDwellHours: Double
        /// Count of slots whose `dwellHours` exceeds the server's
        /// demurrage threshold. Surfaced as a danger chip in the
        /// header.
        let dwellBreachCount: Int
    }

    func getYardMap() async throws -> YardMap {
        try await api.queryNoInput("terminals.getYardMap")
    }

    /// Mutation that releases a yard slot — used when a truck departs
    /// and the operator confirms the slot is clear. Backend path:
    /// `terminals.releaseSlot` (input `{ id: string }`). Returns the
    /// updated `YardSlot` (now `occupied: false` with empty load /
    /// container) so the UI can re-paint the tile without an extra
    /// round-trip. If the router hasn't shipped, the call throws and
    /// the inline CTA flips back to its idle label with an honest
    /// error — local state never lies about the commit landing.
    struct ReleaseSlotInput: Encodable {
        let id: String
    }

    func releaseSlot(id: String) async throws -> YardSlot {
        try await api.mutation(
            "terminals.releaseSlot",
            input: ReleaseSlotInput(id: id)
        )
    }
}

// =====================================================================
// MARK: - adminRouter
//
// Mirrors the legitimate read-side of the §16 admin-tenant-ops slice
// 1:1. Admin owns platform-wide ops: tenant lifecycle, user lifecycle,
// approvals, support tickets, experiments, and control tower DD alerts.
//
// Procedure coverage (mirrors carriers/brokers/catalysts/escorts/
// terminals, intentionally read-side only — §16 flags impersonate +
// system-settings as mock-stubbed today):
//   • getDashboardStats           — six-figure platform-health envelope
//   • getOpenTickets              — support tickets currently open
//   • getApprovalsRequiringAttention — pending approval queue alerts
//   • getRecentTickets            — recently-resolved tickets
//
// If the parallel router has not yet shipped on the `admin.*`
// namespace, the call throws `EusoTripAPIError.trpcError` and the
// Admin* stores in `ViewModels/LiveDataStores.swift` surface
// `EusoEmptyState`. This satisfies doctrine §11 (no mock data) and
// the `MockDataGuard` self-check wired at `EusoTripApp.swift:101`.
// =====================================================================

struct AdminAPI {
    unowned let api: EusoTripAPI

    /// Dashboard KPI envelope. Mirrors the convention of
    /// `terminals.getDashboardStats` on the Admin role's home.
    /// Backend path: `admin.getDashboardStats`.
    struct DashboardStats: Decodable, Hashable {
        /// Active tenants on the platform (tenants whose primary
        /// account has had at least one signed-in user in the
        /// trailing 30-day window). Admin-side analog of Terminal's
        /// `activeMovements` and Escort's `activeAssignments`.
        let activeTenants: Int
        /// Distinct users who signed in during the trailing 7-day
        /// window. Drives the platform-engagement KPI.
        let activeUsersThisWeek: Int
        /// Approvals in the queue waiting for an admin decision
        /// (new tenant, new user, credit-line, contract, etc).
        /// Admin-side analog of Carrier's `loadsRequiringAttention`.
        let pendingApprovals: Int
        /// Support tickets currently in `open` or `in_progress`
        /// state (not yet resolved). Drives the operations KPI on
        /// the home dashboard.
        let supportTicketsOpen: Int
        /// Trailing-month MRR snapshot (US dollars). Pulled from
        /// the `wallet.*` + `money.*` rollup; zero until the first
        /// settlement closes for the current calendar month.
        let mrrThisMonth: Double
        /// Live platform-health composite (0.0…1.0). Computed by
        /// the control-tower DD-alerts pipeline as a weighted mean
        /// of API SLO, queue lag, error rate, and external-vendor
        /// integration status. Below 0.85 is the admin red line.
        let systemHealthScore: Double
    }

    func getDashboardStats() async throws -> DashboardStats {
        try await api.queryNoInput("admin.getDashboardStats")
    }

    /// One open support ticket on the admin operator's plate.
    /// Mirrors the shape of the other role active-row types
    /// (`TerminalAPI.ActiveMovement`, `EscortAPI.ActiveAssignment`)
    /// so the home cards can share row scaffolding. Backend path:
    /// `admin.getOpenTickets`.
    struct ActiveTicket: Decodable, Identifiable, Hashable {
        let id: String
        /// Ticket number / case identifier the admin operator looks
        /// up by (e.g. "EUSO-12345"). Server projects whichever is
        /// most specific for the ticket type.
        let ticketNumber: String
        /// Tenant or user name the ticket originated from.
        let customer: String
        /// Brief one-line subject summarising the ticket.
        let subject: String
        /// Ticket status as a server-side enum: "open",
        /// "in_progress", "awaiting_customer", "escalated", etc.
        /// Rendered uppercase in the row.
        let status: String
        /// Server-side projection of `openedAt` as a relative
        /// short label (e.g. "2m", "12m", "1h") suitable for inline
        /// display. Empty string when not set.
        let openedAt: String
        /// Priority bucket: "low", "normal", "high", "urgent".
        /// Drives the row's right-side priority chip.
        let priority: String
    }

    struct GetOpenTicketsInput: Encodable { let limit: Int }

    func getOpenTickets(limit: Int = 10) async throws -> [ActiveTicket] {
        try await api.query(
            "admin.getOpenTickets",
            input: GetOpenTicketsInput(limit: limit)
        )
    }

    /// One alert on the admin operator's "needs attention" feed.
    /// Backend path: `admin.getApprovalsRequiringAttention`. Issue
    /// strings come from the server's exception engine (pending
    /// approval, failed integration, payment exception, fraud
    /// signal, MFA enrollment lapse, blockchain-audit drift, etc).
    struct AdminAlert: Decodable, Identifiable, Hashable {
        let id: String
        let ticketNumber: String
        let issue: String
        let severity: String
        let message: String
    }

    func getApprovalsRequiringAttention() async throws -> [AdminAlert] {
        try await api.queryNoInput("admin.getApprovalsRequiringAttention")
    }

    /// One row in the admin operator's recent-activity feed (a slim
    /// summary of recently resolved tickets / approvals). Backend
    /// path: `admin.getRecentTickets`. `resolvedAt` is the server's
    /// `YYYY-MM-DD` projection of `closedAt ?? resolvedAt`; empty
    /// string when neither is set.
    struct RecentTicket: Decodable, Identifiable, Hashable {
        let id: String
        let ticketNumber: String
        let status: String
        let customer: String
        let subject: String
        let resolvedAt: String
    }

    struct GetRecentTicketsInput: Encodable { let limit: Int }

    func getRecentTickets(limit: Int = 5) async throws -> [RecentTicket] {
        try await api.query(
            "admin.getRecentTickets",
            input: GetRecentTicketsInput(limit: limit)
        )
    }

    // MARK: - listTenants (802 brick · 151st firing)
    //
    // One row in the admin operator's tenant directory. Each `Tenant`
    // is a customer organisation on the EusoTrip platform — a
    // shipper company, a carrier company, a brokerage, a catalyst
    // collective, etc. This wires the second screen on the Admin
    // role track (`802_AdminTenants`) — the natural drill-down from
    // the home dashboard's `ACTIVE TENANTS` KPI.
    //
    // Backend path: `admin.listTenants`. If the parallel router has
    // not shipped yet, calls throw `EusoTripAPIError.trpcError` and
    // the client store resolves to `.error` — the screen surfaces an
    // honest retry banner. Doctrine §11 + `MockDataGuard`: never a
    // fixture row.
    //
    // Every nullable column (`plan`, `primaryUserName`, `primaryUserEmail`,
    // `monthlyVolumeUsd`, `mrrUsd`) renders as a neutral em-dash on the
    // 802 row when absent — shape mirrors the 701 GateQueueItem pattern.
    struct Tenant: Decodable, Identifiable, Hashable {
        let id: String
        /// Display name of the tenant organisation (the company,
        /// brokerage, fleet, or catalyst collective). Server-side
        /// projection of `companies.legalName ?? companies.dba`.
        let name: String
        /// Server-side enum: "active", "trial", "suspended",
        /// "churned", "pending_review". Drives the row's status pill.
        let status: String
        /// Subscription plan label (e.g. "Starter", "Growth",
        /// "Enterprise"). Optional — empty when the tenant is on a
        /// custom contract or hasn't completed plan selection.
        let plan: String?
        /// Primary user / owner of the tenant account. Optional —
        /// empty when the org has multiple equally-privileged owners.
        let primaryUserName: String?
        let primaryUserEmail: String?
        /// Active distinct user count for this tenant in the trailing
        /// 30-day window. Zero on a brand-new tenant.
        let activeUserCount: Int
        /// Trailing-month USD volume routed through the tenant
        /// (load gross, ticket gross, settlement gross — server
        /// picks the most representative). Optional — null until the
        /// first settlement closes.
        let monthlyVolumeUsd: Double?
        /// Trailing-month MRR contribution (USD). Optional — null
        /// when the tenant is on a custom contract that doesn't roll
        /// into the standard MRR engine.
        let mrrUsd: Double?
        /// Server projection of `createdAt` as a `YYYY-MM-DD` string.
        /// Empty when the tenant predates the migrations that set
        /// the column (rare).
        let signedUpAt: String
    }

    /// Optional status filter mirrors the server's `status` query
    /// parameter — when nil/empty, the server returns all tenants
    /// regardless of status, sorted by `monthlyVolumeUsd` descending.
    /// Otherwise filters to that single status enum value.
    struct ListTenantsInput: Encodable {
        let limit: Int
        let status: String?
    }

    func listTenants(limit: Int = 50, status: String? = nil) async throws -> [Tenant] {
        try await api.query(
            "admin.listTenants",
            input: ListTenantsInput(limit: limit, status: status)
        )
    }

    // MARK: - controlTower (801 brick · 156th firing)
    //
    // Platform-wide control-tower pane. Closes the 800->802 leapfrog
    // by giving Admin a third deep surface (parity with Terminal
    // 700/701/702 and Catalyst 500/501/502). Mirrors the convention
    // of the per-role control-tower routers on the web platform
    // (slice 13 of SKILL.md §16 — "admin-tenant-ops"). All
    // procedures throw `EusoTripAPIError.trpcError` if the parallel
    // router has not shipped on the `admin.controlTower.*` namespace,
    // and the matching `Admin*Store` resolves to `.error` so the
    // screen surfaces an honest retry banner. Doctrine §11 holds:
    // never a fixture row.
    //
    // Backend paths:
    //   • admin.controlTower.getOverview     -> ControlTowerOverview
    //   • admin.controlTower.getExceptions   -> [ControlTowerException]
    //   • admin.controlTower.acknowledgeExc  -> ControlTowerException

    /// Composite control-tower KPI envelope. Each scalar represents
    /// a platform-health dimension surfaced as a single tile on the
    /// 801 home strip. The server computes these from the DD-alerts
    /// pipeline + system-health composite + integration-status
    /// register; on a fresh tenant where one rollup hasn't seeded
    /// (e.g., no settlements yet for the calendar month), the
    /// scalar projects 0 / 0.0 / "" and the row renders the neutral
    /// em-dash — never a fabricated value.
    struct ControlTowerOverview: Decodable, Hashable {
        /// Distinct active exceptions across the platform right now
        /// (any ticket / alert in `open` or `escalated` state).
        let activeExceptionsCount: Int
        /// Exceptions whose SLA window has already breached and are
        /// awaiting an admin response. Subset of `activeExceptionsCount`.
        let breachedSLAExceptionsCount: Int
        /// Composite system-health score (0.0 ... 1.0). Below 0.85
        /// is the admin red line. Same column the home dashboard's
        /// `systemHealthScore` tile reads — surfaced here too so the
        /// drill-down always agrees with the home tile.
        let systemHealthScore: Double
        /// API SLO compliance over the trailing 24h window, expressed
        /// as a fraction (0.0 ... 1.0). `eusotrip-api` p99 budget.
        let apiSLO24h: Double
        /// Queue lag in seconds — max of the message-bus consumer
        /// lag across `loads.events`, `dispatch.events`, `wallet.events`.
        let queueLagSeconds: Int
        /// Error rate over the trailing 1h window (fraction of
        /// requests that returned 5xx or threw an unhandled exception).
        let errorRate1h: Double
        /// Vendor-integration status rollup — one of "green", "yellow",
        /// "red". Aggregates Stripe + HERE + FMCSA + CBP + CBSA. When
        /// any single vendor is "red", the rollup is "red"; when any is
        /// "yellow" but none are "red", "yellow"; else "green".
        let vendorIntegrationStatus: String
        /// Server-side projection of the most-recent control-tower
        /// pipeline timestamp as a relative short label ("just now",
        /// "12s", "1m"). Empty string when the pipeline has never run.
        let lastUpdatedAt: String
    }

    func getControlTowerOverview() async throws -> ControlTowerOverview {
        try await api.queryNoInput("admin.controlTower.getOverview")
    }

    /// One row in the control-tower exception feed. Each row is an
    /// active platform-level exception that needs admin attention.
    /// Severity bucket drives the row's left-side gradient bar; SLA
    /// status drives the right-side chip ("BREACHED", "AT RISK",
    /// "ON TRACK"). Empty `category` and `assignee` render as
    /// em-dash sentinels — never a fabricated label.
    struct ControlTowerException: Decodable, Identifiable, Hashable {
        let id: String
        /// Server enum: "infra", "integration", "fraud", "billing",
        /// "compliance", "support", "security". Empty when not
        /// classified yet (rare on a settled exception).
        let category: String
        /// Server enum: "low", "normal", "high", "urgent", "critical".
        /// Drives the row's severity colour-band.
        let severity: String
        /// Server enum: "on_track", "at_risk", "breached". Drives the
        /// right-side SLA chip.
        let slaStatus: String
        /// Brief one-line headline of the exception.
        let headline: String
        /// Tenant or scope this exception is attached to (e.g.
        /// "Acme Logistics", "Platform-wide", "Stripe webhook").
        let scope: String
        /// User name of the admin currently assigned (empty when
        /// unassigned). Not the email — server-side projection.
        let assignee: String
        /// Server-side projection of `openedAt` as a relative short
        /// label ("2m", "12m", "1h", "3h"). Empty when not set.
        let openedAt: String
    }

    struct GetControlTowerExceptionsInput: Encodable {
        let limit: Int
        let severity: String?
    }

    func getControlTowerExceptions(
        limit: Int = 25,
        severity: String? = nil
    ) async throws -> [ControlTowerException] {
        try await api.query(
            "admin.controlTower.getExceptions",
            input: GetControlTowerExceptionsInput(limit: limit, severity: severity)
        )
    }

    struct AcknowledgeExceptionInput: Encodable { let id: String }

    /// Mark a control-tower exception as acknowledged. The server
    /// sets `acknowledgedAt = now()` and `acknowledgedBy = currentUser`,
    /// returning the updated row. The 801 screen flips that row's
    /// SLA chip from `breached` -> `at_risk` (or holds, depending on
    /// recompute) and the right-side chevron is removed. Calls do
    /// NOT close the exception — closure is a separate flow on the
    /// future detail screen `802` (admin tenants is at 802; the
    /// detail editor lands at `803_AdminTenantDetail`/`804_...`).
    func acknowledgeControlTowerException(id: String) async throws -> ControlTowerException {
        try await api.mutation(
            "admin.controlTower.acknowledgeException",
            input: AcknowledgeExceptionInput(id: id)
        )
    }

    // MARK: - getTenantDetail (803 brick · 161st firing)
    //
    // Per-tenant deep view that drills in from the 802 row's
    // "View detail →" CTA. Lifts Admin to 4-deep parity with
    // Driver/Shipper. Mirrors the convention of the per-record
    // detail routers on Carrier (`carriers.getLoadDetail`),
    // Catalyst (`catalysts.getMatchDetail`), and Escort
    // (`escorts.getAssignmentDetail`). Backend path:
    // `admin.getTenantDetail` (input `{ id: string }`).
    //
    // If the parallel router has not yet shipped on the `admin.*`
    // namespace, the call throws `EusoTripAPIError.trpcError` and
    // `AdminTenantDetailStore` resolves to `.error` so the screen
    // surfaces an honest retry banner. No fixture data ever
    // (doctrine §11 + `MockDataGuard`).
    //
    // Every nullable column (`primaryUserName`, `primaryUserEmail`,
    // `monthlyVolumeUsd`, `mrrUsd`, `lifetimeVolumeUsd`,
    // `lifetimeRevenueUsd`, `nextRenewalAt`, …) renders as a neutral
    // em-dash on the 803 screen when absent — never a fabricated
    // value or a fallback zero.
    struct TenantContact: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let email: String?
        let phone: String?
        /// Server-side enum: "owner", "billing", "operations",
        /// "compliance". Drives the contact-card subtitle.
        let role: String
    }

    struct TenantUsageMetric: Decodable, Identifiable, Hashable {
        let id: String
        /// Display label for the metric ("Loads booked",
        /// "Drivers active", "Documents signed", "API calls",
        /// "Push notifications sent"). Server-projected so the
        /// client never localises a server-driven dimension.
        let label: String
        /// Trailing-30-day count for the metric. Always present —
        /// a metric the tenant has never used would be omitted by
        /// the server, never returned with a zero value.
        let value: Int
        /// Optional delta vs the prior trailing-30-day window
        /// (signed integer). Drives the trend chip on the row.
        let delta30dPct: Double?
    }

    struct TenantPaymentSummary: Decodable, Hashable {
        /// Stripe customer id when the tenant is billed via the
        /// platform's Stripe Connect account. Null when the tenant
        /// is on a custom invoicing arrangement.
        let stripeCustomerId: String?
        /// Brand of the primary card on file ("visa", "mastercard",
        /// "amex"). Null when the tenant pays via ACH/wire.
        let primaryCardBrand: String?
        /// Last 4 digits of the primary card on file. Null when
        /// the tenant pays via ACH/wire.
        let primaryCardLast4: String?
        /// "active", "past_due", "canceled", "trialing", "unpaid".
        /// Drives the billing-status pill on the screen.
        let billingStatus: String
        /// Trailing-90-day on-time payment rate (0.0-1.0). Null
        /// when the tenant has had < 3 invoices closed.
        let onTimeRate90d: Double?
        /// Trailing-30-day balance owed (USD). Always present —
        /// a tenant with no balance returns 0.0, not null.
        let balanceUsd: Double
    }

    struct TenantAuditEntry: Decodable, Identifiable, Hashable {
        let id: String
        /// Server-projected event label ("Tenant created",
        /// "Plan upgraded", "Suspended", "Reinstated", "Owner
        /// transferred", "Billing method updated"). Localisation
        /// is deliberately deferred to the server.
        let label: String
        /// ISO-8601 timestamp of the event.
        let occurredAt: String
        /// Optional actor ("system", "admin@eusotrip.com",
        /// "owner@tenantco.com"). Drives the byline on the row.
        let actor: String?
        /// Optional one-line context shown beneath the label.
        let note: String?
    }

    struct TenantDetail: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        /// Server-side enum: "active", "trial", "suspended",
        /// "churned", "pending_review". Drives the hero status pill.
        let status: String
        /// Subscription plan label ("Starter", "Growth",
        /// "Enterprise", "Custom"). Optional — null on a tenant
        /// without an active plan (custom contract or pending
        /// signup).
        let plan: String?
        /// Server-projected `companies.role` ("shipper", "carrier",
        /// "broker", "catalyst", "terminal", …). Drives the type
        /// chip in the hero row.
        let kind: String
        /// Trailing-month USD volume routed through the tenant.
        /// Optional — null until the first settlement closes.
        let monthlyVolumeUsd: Double?
        /// Trailing-month MRR contribution (USD). Optional — null
        /// for custom contracts that don't roll into the standard
        /// MRR engine.
        let mrrUsd: Double?
        /// Lifetime USD volume routed through the tenant. Optional
        /// — null when the tenant predates the migrations that
        /// added the column (rare).
        let lifetimeVolumeUsd: Double?
        /// Lifetime USD revenue captured from the tenant (sum of
        /// platform fees + plan revenue + add-ons). Optional.
        let lifetimeRevenueUsd: Double?
        /// Active distinct users in the trailing-30-day window.
        let activeUserCount30d: Int
        /// Total distinct users on the tenant ever (lifetime).
        let totalUserCount: Int
        /// Server-projected `createdAt` as `YYYY-MM-DD`.
        let signedUpAt: String
        /// ISO-8601 of the next renewal date. Optional — null on
        /// trial / churned tenants.
        let nextRenewalAt: String?
        /// Free-form server-projected health score 0-100. Optional
        /// — null when the score engine hasn't run for this
        /// tenant yet (very-new accounts).
        let healthScore: Int?
        /// Free-form risk note from the server-side classifier.
        /// Optional — null when no risks are flagged.
        let riskNote: String?
        /// Contact roster (owner, billing, operations,
        /// compliance). May be empty if the tenant hasn't
        /// completed onboarding.
        let contacts: [TenantContact]
        /// Trailing-30-day usage rollup. May be empty on a
        /// brand-new tenant that hasn't generated any activity yet.
        let usageMetrics: [TenantUsageMetric]
        /// Billing summary. Always present — a tenant on a custom
        /// contract still returns a billing summary with empty
        /// Stripe fields.
        let paymentSummary: TenantPaymentSummary
        /// Most recent admin audit events (suspend, reinstate,
        /// plan changes, billing updates). Server-paged — most-
        /// recent-first. May be empty on a brand-new tenant.
        let auditTrail: [TenantAuditEntry]
    }

    struct GetTenantDetailInput: Encodable { let id: String }

    /// Read the per-tenant deep envelope. Server returns a fully
    /// hydrated `TenantDetail` or throws when the id is unknown.
    /// The store folds nil → `.empty` only when the server
    /// explicitly omits a tenant body (parallel router has not
    /// yet shipped); otherwise either `.loaded` or `.error`.
    func getTenantDetail(id: String) async throws -> TenantDetail? {
        try await api.query(
            "admin.getTenantDetail",
            input: GetTenantDetailInput(id: id)
        )
    }
}

// MARK: - rateSheetRouter
//
// Mirrors `frontend/server/routers/rateSheet.ts` 1:1. The web platform
// is the source of truth for the data model — these wire types are
// therefore Codable on both sides (mutations send the same shape they
// receive on a read), so a driver who edits a tier on iOS produces a
// payload the React consumer accepts unchanged.
//
// Procedure coverage (16 total, all wired):
//   • create / list / getRateSheet / updateRateSheet / deleteRateSheet
//   • getDefaultTiers / getSmartDefaultTiers / getCurrentDiesel
//   • calculateRate (driver-facing pay preview)
//   • getVersionHistory / listMyRateSheets
//   • generateReconciliation / listReconciliations / getStats
//   • getEusoTicketDocuments / reconcileTickets
//
// Driver-side, the highest-value procedures are `calculateRate`,
// `getCurrentDiesel`, `listMyRateSheets`, and `getRateSheet` —
// everything else is for catalyst/broker authoring flows the iOS
// surface still exposes for the carrier-as-driver case.

struct RateSheetAPI {
    unowned let api: EusoTripAPI

    // MARK: Wire types

    /// One mileage band on a Schedule-A rate sheet. The web router's
    /// `rateTierSchema` is `{ minMiles, maxMiles, ratePerBarrel }`.
    /// We mirror that exact shape so a payload round-trips cleanly
    /// between iOS authoring and the React consumer.
    struct RateTier: Codable, Identifiable, Hashable {
        var id: String { "\(minMiles)-\(maxMiles)" }
        let minMiles: Double
        let maxMiles: Double
        let ratePerBarrel: Double

        init(minMiles: Double, maxMiles: Double, ratePerBarrel: Double) {
            self.minMiles = minMiles
            self.maxMiles = maxMiles
            self.ratePerBarrel = ratePerBarrel
        }
    }

    /// Surcharge schedule. Mirrors `surchargeRulesSchema` in the web
    /// router. Defaults match the Permian Crude baseline so a fresh
    /// iOS authoring sheet starts from a known-good config.
    struct Surcharges: Codable, Hashable {
        var fscEnabled: Bool = true
        var fscBaselineDieselPrice: Double = 3.75
        var fscMilesPerGallon: Double = 5
        var fscPaddRegion: String = "3"
        var waitTimeFreeHours: Double = 1
        var waitTimeRatePerHour: Double = 85
        var splitLoadFee: Double = 50
        var rejectFee: Double = 85
        var minimumBarrels: Double = 160
        var travelSurchargePerMile: Double = 1.50
        var longLeaseRoadFee: Double? = nil
        var multipleGatesFee: Double? = nil
    }

    // MARK: - calculateRate (driver pay preview)

    /// Live-preview output for a single run. The iOS rate calculator
    /// surface binds every numeric field below to a row in the
    /// breakdown card, so changing `oneWayMiles` re-runs the round-
    /// trip and the panel rebuilds in place.
    struct CalculatedRate: Decodable {
        let ratePerBarrel: Double
        let baseAmount: Double
        let fsc: Double
        let waitTimeCharge: Double
        let splitLoadFee: Double
        let rejectFee: Double
        let travelSurcharge: Double
        let totalAmount: Double
        /// Pre-rendered explanation lines ("160 BBL × $3.40 = $544.00").
        /// We render verbatim — the server is the rounding authority.
        let breakdown: [String]
    }

    struct CalculateRateInput: Encodable {
        let netBarrels: Double
        let oneWayMiles: Double
        var waitTimeHours: Double = 0
        var isSplitLoad: Bool = false
        var isReject: Bool = false
        var travelSurchargeMiles: Double = 0
        var currentDieselPrice: Double? = nil
        var rateTiers: [RateTier]? = nil
        var surcharges: Surcharges? = nil
    }

    /// Driver-facing pay preview. Mirrors `rateSheet.calculateRate`.
    func calculateRate(_ input: CalculateRateInput) async throws -> CalculatedRate {
        try await api.query("rateSheet.calculateRate", input: input)
    }

    // MARK: - Defaults + EIA diesel auto-populate

    struct DefaultTiers: Decodable {
        let tiers: [RateTier]
        let surcharges: Surcharges
    }

    /// `rateSheet.getDefaultTiers` — Permian Crude baseline tiers.
    func getDefaultTiers() async throws -> DefaultTiers {
        try await api.queryNoInput("rateSheet.getDefaultTiers")
    }

    struct SmartTiersInput: Encodable {
        let region: String?
        let product: String?
        let trailerType: String?
    }

    struct RegionInfo: Decodable {
        let label: String?
        let padd: String?
        let multiplier: Double?
    }

    struct AvailableRegion: Decodable, Identifiable {
        var id: String { key }
        let key: String
        let label: String
        let padd: String
        let multiplier: Double
    }

    struct AvailableProduct: Decodable, Identifiable {
        var id: String { name }
        let name: String
        let multiplier: Double
    }

    struct AvailableTrailer: Decodable, Identifiable {
        var id: String { key }
        let key: String
        let multiplier: Double
        let unit: String
        let defaultProduct: String?
    }

    struct SmartTiers: Decodable {
        let tiers: [RateTier]
        let surcharges: Surcharges
        let regionInfo: RegionInfo?
        let productMultiplier: Double?
        let trailerMultiplier: Double?
        let availableRegions: [AvailableRegion]
        let availableProducts: [AvailableProduct]
        let availableTrailers: [AvailableTrailer]
    }

    /// `rateSheet.getSmartDefaultTiers` — region/product/trailer-aware
    /// defaults. Pass any/all of the three; server returns the matching
    /// adjusted tier set + surcharges + the available enums for the UI
    /// pickers.
    func getSmartDefaultTiers(
        region: String? = nil,
        product: String? = nil,
        trailerType: String? = nil
    ) async throws -> SmartTiers {
        try await api.query(
            "rateSheet.getSmartDefaultTiers",
            input: SmartTiersInput(region: region, product: product, trailerType: trailerType)
        )
    }

    struct CurrentDiesel: Decodable {
        let price: Double
        let padd: String?
        let state: String?
        let reportDate: String?
        /// "EIA" when live-fed, "default" when the server fell back.
        let source: String
        let change1w: Double?
        let change1m: Double?
    }

    struct CurrentDieselInput: Encodable {
        let state: String?
        let paddRegion: String?
    }

    /// `rateSheet.getCurrentDiesel` — auto-populates the FSC diesel
    /// input. Pass either a USPS state code or a PADD region.
    func getCurrentDiesel(state: String? = nil, padd: String? = nil) async throws -> CurrentDiesel {
        try await api.query(
            "rateSheet.getCurrentDiesel",
            input: CurrentDieselInput(state: state, paddRegion: padd)
        )
    }

    // MARK: - Sheet authoring (CRUD)

    struct RateSheetSummary: Decodable, Identifiable {
        let id: Int
        let name: String?
        let status: String?
        let createdAt: String
    }

    struct ListInput: Encodable { let limit: Int }

    /// `rateSheet.list` — company-scoped sheet list (lightweight).
    func list(limit: Int = 20) async throws -> [RateSheetSummary] {
        try await api.query("rateSheet.list", input: ListInput(limit: limit))
    }

    /// `rateSheet.listMyRateSheets` — user/company-scoped active list.
    struct ListMineInput: Encodable { let includeExpired: Bool? }
    func listMyRateSheets(includeExpired: Bool = false) async throws -> [RateSheetSummary] {
        try await api.query(
            "rateSheet.listMyRateSheets",
            input: ListMineInput(includeExpired: includeExpired)
        )
    }

    /// Full rate-sheet record. Mirrors `rateSheet.getRateSheet` output.
    struct RateSheetDetail: Decodable, Identifiable {
        let id: Int
        let name: String?
        let status: String?
        let createdAt: String
        let region: String?
        let productType: String?
        let trailerType: String?
        let rateUnit: String?
        let effectiveDate: String?
        let expirationDate: String?
        let agreementId: Int?
        let rateTiers: [RateTier]
        let surcharges: Surcharges
        let notes: String?
        let version: Int
    }

    struct GetRateSheetInput: Encodable { let id: Int }

    func getRateSheet(id: Int) async throws -> RateSheetDetail? {
        try await api.query("rateSheet.getRateSheet", input: GetRateSheetInput(id: id))
    }

    // MARK: - Create / update

    /// Mirrors `rateSheetSchema` on the server — anything optional on
    /// the wire is optional here too. Driver-side authoring usually
    /// only needs (name, effectiveDate, issuedBy, rateTiers, surcharges).
    struct CreateInput: Encodable {
        let name: String
        let effectiveDate: String
        let expirationDate: String?
        let fuelSurchargeIncluded: Bool
        let issuedBy: String
        let issuedByContact: String?
        let issuedByPhone: String?
        let issuedByEmail: String?
        let issuedByAddress: String?
        let issuedTo: String?
        let rateTiers: [RateTier]
        let surcharges: Surcharges
        let notes: String?
        let agreementId: Int?
        let region: String?
        let productType: String?
        let trailerType: String?
        let rateUnit: String?

        init(
            name: String,
            effectiveDate: String,
            issuedBy: String,
            rateTiers: [RateTier],
            surcharges: Surcharges,
            expirationDate: String? = nil,
            fuelSurchargeIncluded: Bool = false,
            issuedByContact: String? = nil,
            issuedByPhone: String? = nil,
            issuedByEmail: String? = nil,
            issuedByAddress: String? = nil,
            issuedTo: String? = nil,
            notes: String? = nil,
            agreementId: Int? = nil,
            region: String? = nil,
            productType: String? = nil,
            trailerType: String? = nil,
            rateUnit: String? = nil
        ) {
            self.name = name
            self.effectiveDate = effectiveDate
            self.expirationDate = expirationDate
            self.fuelSurchargeIncluded = fuelSurchargeIncluded
            self.issuedBy = issuedBy
            self.issuedByContact = issuedByContact
            self.issuedByPhone = issuedByPhone
            self.issuedByEmail = issuedByEmail
            self.issuedByAddress = issuedByAddress
            self.issuedTo = issuedTo
            self.rateTiers = rateTiers
            self.surcharges = surcharges
            self.notes = notes
            self.agreementId = agreementId
            self.region = region
            self.productType = productType
            self.trailerType = trailerType
            self.rateUnit = rateUnit
        }
    }

    struct CreateAck: Decodable {
        let success: Bool
        let id: Int
        let name: String?
        let effectiveDate: String?
        let tierCount: Int?
        let createdAt: String?
    }

    func create(_ input: CreateInput) async throws -> CreateAck {
        try await api.mutation("rateSheet.create", input: input)
    }

    struct UpdateInput: Encodable {
        let id: Int
        let name: String?
        let region: String?
        let productType: String?
        let trailerType: String?
        let rateUnit: String?
        let effectiveDate: String?
        let expirationDate: String?
        let agreementId: Int?
        let rateTiers: [RateTier]?
        let surcharges: Surcharges?
        let notes: String?
    }

    struct UpdateAck: Decodable {
        let success: Bool
        let id: Int
        let version: Int
    }

    func update(_ input: UpdateInput) async throws -> UpdateAck {
        try await api.mutation("rateSheet.updateRateSheet", input: input)
    }

    struct DeleteInput: Encodable { let id: Int }
    struct DeleteAck: Decodable { let success: Bool }
    func delete(id: Int) async throws -> DeleteAck {
        try await api.mutation("rateSheet.deleteRateSheet", input: DeleteInput(id: id))
    }

    // MARK: - Version history

    struct Version: Decodable, Identifiable {
        let id: Int
        let version: Int
        let snapshotAt: String?
        let name: String?
        let tierCount: Int?
        let region: String?
        let productType: String?
    }

    struct VersionHistoryInput: Encodable { let sheetId: Int }
    func getVersionHistory(sheetId: Int) async throws -> [Version] {
        try await api.query(
            "rateSheet.getVersionHistory",
            input: VersionHistoryInput(sheetId: sheetId)
        )
    }

    // MARK: - Reconciliation

    struct ReconcileLineInput: Encodable {
        let runDate: String
        let bolNumber: String?
        let runTicket: String?
        let origin: String?
        let destination: String?
        let netBarrels: Double
        let oneWayMiles: Double
        let waitTimeHours: Double?
        let isSplitLoad: Bool?
        let isReject: Bool?
        let travelSurchargeMiles: Double?
    }

    struct ReconcileInput: Encodable {
        let periodStart: String
        let periodEnd: String
        let customerName: String
        let carrierName: String
        let lines: [ReconcileLineInput]
        let rateTiers: [RateTier]?
        let surcharges: Surcharges?
        let currentDieselPrice: Double?
    }

    /// Each calculated reconciliation line — mirrors what the server
    /// builds when aggregating a billing period. The server is the
    /// rounding authority; we render the numbers verbatim.
    struct ReconcileLineOut: Decodable, Identifiable {
        let id: String
        let runDate: String?
        let bolNumber: String?
        let runTicket: String?
        let netBarrels: Double?
        let oneWayMiles: Double?
        let ratePerBarrel: Double?
        let baseAmount: Double?
        let fsc: Double?
        let waitTimeCharge: Double?
        let splitLoadFee: Double?
        let rejectFee: Double?
        let travelSurcharge: Double?
        let totalAmount: Double?
    }

    struct ReconcileTotals: Decodable {
        let totalRuns: Int?
        let totalBarrels: Double?
        let totalMiles: Double?
        let totalGross: Double?
        let totalFsc: Double?
        let totalWaitTime: Double?
        let totalSplitLoad: Double?
        let totalReject: Double?
        let totalTravelSurcharge: Double?
        let totalAmount: Double?
    }

    struct ReconcilePlatformFees: Decodable {
        let pct: Double?
        let amount: Double?
    }

    struct ReconcileSettlement: Decodable {
        let netToCarrier: Double?
        let payoutTimingDays: Int?
        let scheduledPayoutAt: String?
    }

    struct ReconciliationOut: Decodable {
        let reconciliationId: Int?
        let lines: [ReconcileLineOut]
        let totals: ReconcileTotals
        let platformFees: ReconcilePlatformFees?
        let settlement: ReconcileSettlement?
        let generatedAt: String?
    }

    func generateReconciliation(_ input: ReconcileInput) async throws -> ReconciliationOut {
        try await api.mutation("rateSheet.generateReconciliation", input: input)
    }

    func listReconciliations(limit: Int = 20) async throws -> [RateSheetSummary] {
        try await api.query("rateSheet.listReconciliations", input: ListInput(limit: limit))
    }

    struct ReconcileStats: Decodable {
        let totalStatements: Int?
        let totalPaid: Double?
        let pending: Int?
    }
    func getStats() async throws -> ReconcileStats {
        try await api.queryNoInput("rateSheet.getStats")
    }

    // MARK: - EusoTicket documents

    struct EusoTicketDocument: Decodable, Identifiable {
        let id: Int
        let name: String?
        let type: String?
        let status: String?
        let createdAt: String?
    }

    struct EusoTicketStats: Decodable {
        let bols: Int?
        let runTickets: Int?
        let rateSheets: Int?
        let reconciliations: Int?
    }

    struct EusoTicketResponse: Decodable {
        let documents: [EusoTicketDocument]
        let stats: EusoTicketStats?
    }

    struct EusoTicketInput: Encodable {
        let type: String?
        let limit: Int?
    }

    func getEusoTicketDocuments(type: String? = nil, limit: Int = 50) async throws -> EusoTicketResponse {
        try await api.query(
            "rateSheet.getEusoTicketDocuments",
            input: EusoTicketInput(type: type, limit: limit)
        )
    }
}

// MARK: - visualIntelligenceRouter (VIGA)
//
// Mirrors `frontend/server/routers/visualIntelligence.ts` 1:1. The
// server takes a base64 image + analysis-type discriminator and runs
// it through Gemini / Anthropic vision models, returning a typed
// envelope `{ type, data }` that maps to one of nine analysis structs.
//
// iOS converts UIImage → JPEG (0.85 quality) → base64 in the call
// site. Don't preprocess the bytes here — the server's quality
// pipeline already handles resize / contrast normalization.
//
// Procedure coverage (10 wired):
//   • diagnoseMechanical (ZEUN integration)
//   • readGauge          (tank/pressure/temp)
//   • verifySeal         (BOL seal tamper detection)
//   • inspectDVIR        (per-inspection-point AI assist)
//   • assessCargo        (securement + integrity)
//   • verifyPOD          (visual POD validation)
//   • mapFacility        (terminal/yard intel)
//   • assessDamage       (accident/incident)
//   • reportRoadCondition(route hazards)
//   • analyzeMulti       (multi-pass for ambiguous photos)

struct VIGAAPI {
    unowned let api: EusoTripAPI

    /// Server-side analysis types — must stay in sync with the
    /// `passes` enum on `visualIntelligenceRouter.analyzeMulti`.
    enum AnalysisType: String, Codable, CaseIterable {
        case mechanicalDiagnosis = "MECHANICAL_DIAGNOSIS"
        case gaugeReading        = "GAUGE_READING"
        case sealVerification    = "SEAL_VERIFICATION"
        case dvirInspection      = "DVIR_INSPECTION"
        case cargoCondition      = "CARGO_CONDITION"
        case podVerification     = "POD_VERIFICATION"
        case facilityMapping     = "FACILITY_MAPPING"
        case damageAssessment    = "DAMAGE_ASSESSMENT"
        case roadCondition       = "ROAD_CONDITION"
        case generalVisual       = "GENERAL_VISUAL"
    }

    // MARK: Result envelopes — one struct per analysis type.

    /// MECHANICAL_DIAGNOSIS shape.
    struct MechanicalDiagnosis: Decodable {
        struct Defect: Decodable, Hashable {
            let description: String
            let severity: String
            let location: String?
        }
        let component: String
        let componentCategory: String?
        /// "GOOD" | "WORN" | "DAMAGED" | "CRITICAL" | "FAILED"
        let condition: String
        let defects: [Defect]
        let repairRecommendation: String?
        let repairSteps: [String]?
        let partsNeeded: [String]?
        let estimatedRepairTime: String?
        /// "NONE" | "LOW" | "MODERATE" | "HIGH" | "IMMEDIATE_DANGER"
        let safetyRisk: String
        let canContinueDriving: Bool
        let confidence: Double
        let visualNotes: String?
    }

    /// GAUGE_READING shape.
    struct GaugeReading: Decodable {
        struct Additional: Decodable, Hashable {
            let label: String
            let value: String
            let unit: String?
        }
        let gaugeType: String
        let reading: String
        let unit: String?
        let numericValue: Double?
        let normalRange: String?
        let isWithinNormal: Bool
        let additionalReadings: [Additional]?
        let confidence: Double
        let visualNotes: String?
    }

    /// SEAL_VERIFICATION shape.
    struct SealVerification: Decodable {
        let sealNumber: String?
        let sealType: String?
        /// "INTACT" | "BROKEN" | "TAMPERED" | "MISSING" | "UNREADABLE"
        let condition: String
        let tamperEvidence: Bool
        let tamperDetails: String?
        let matchesBOL: Bool?
        let confidence: Double
        let visualNotes: String?
    }

    /// DVIR_INSPECTION shape.
    struct DVIRInspection: Decodable {
        struct Defect: Decodable, Hashable {
            let description: String
            /// "MINOR" | "MAJOR" | "CRITICAL_OOS"
            let severity: String
            let requiresImmediate: Bool
        }
        let inspectionPoint: String?
        /// "PASS" | "MARGINAL" | "FAIL"
        let condition: String
        let defectsFound: [Defect]
        let regulatoryNotes: [String]?
        let confidence: Double
        let visualNotes: String?
    }

    /// CARGO_CONDITION shape.
    struct CargoCondition: Decodable {
        struct Issue: Decodable, Hashable {
            let description: String
            let severity: String
            let location: String?
        }
        let cargoType: String?
        /// "SECURE" | "SHIFTED" | "DAMAGED" | "LEAKING" | "UNKNOWN"
        let condition: String
        let issues: [Issue]
        let securementStatus: String?
        let hazmatVisible: Bool
        let placardInfo: String?
        let confidence: Double
        let visualNotes: String?
    }

    /// POD_VERIFICATION shape.
    struct PODVerification: Decodable {
        let deliveryConfirmed: Bool
        let siteCondition: String
        let visibleEvidence: [String]
        let discrepancies: [String]
        let signatureVisible: Bool
        let timestampEvidence: String?
        let confidence: Double
        let visualNotes: String
    }

    /// FACILITY_MAPPING shape.
    struct FacilityMapping: Decodable {
        let facilityType: String?
        let features: [String]?
        let accessPoints: [String]?
        let equipment: [String]?
        let hazards: [String]?
        let capacity: String?
        let navigationNotes: [String]?
        let confidence: Double
        let visualNotes: String?
    }

    /// DAMAGE_ASSESSMENT shape.
    struct DamageAssessment: Decodable {
        struct AffectedArea: Decodable, Hashable {
            let area: String
            let description: String
            let severity: String
        }
        struct CostRange: Decodable, Hashable {
            let min: Double
            let max: Double
        }
        let damageType: String
        /// "COSMETIC" | "MINOR" | "MODERATE" | "SEVERE" | "TOTAL"
        let severity: String
        let affectedAreas: [AffectedArea]
        let estimatedRepairCost: CostRange?
        let safetyImplications: [String]?
        let evidenceNotes: [String]?
        let insuranceRelevant: Bool
        let confidence: Double
        let visualNotes: String?
    }

    /// ROAD_CONDITION shape.
    struct RoadCondition: Decodable {
        let conditionType: String
        /// "GOOD" | "FAIR" | "POOR" | "HAZARDOUS" | "IMPASSABLE"
        let severity: String
        let hazards: [String]?
        let recommendedAction: String?
        let alternateRouteAdvised: Bool
        let confidence: Double
        let visualNotes: String?
    }

    // Each procedure returns a `{ type, data }` envelope. We surface
    // ONLY the typed `.data` since iOS call sites already know which
    // analysis they asked for.

    private struct Envelope<T: Decodable>: Decodable {
        let type: String
        let data: T
    }

    // MARK: - Inputs

    private struct ImageInput: Encodable {
        let imageBase64: String
        let mimeType: String
    }

    struct DiagnoseMechanicalInput: Encodable {
        let imageBase64: String
        let mimeType: String
        let vehicleMake: String?
        let vehicleModel: String?
        let vehicleYear: Int?
        let issueCategory: String?
        let symptoms: [String]?
    }

    struct GaugeInput: Encodable {
        let imageBase64: String
        let mimeType: String
        let gaugeType: String?
    }

    struct SealInput: Encodable {
        let imageBase64: String
        let mimeType: String
        let expectedSealNumber: String?
    }

    struct DVIRInput: Encodable {
        let imageBase64: String
        let mimeType: String
        let inspectionPoint: String?
    }

    struct PODInput: Encodable {
        let imageBase64: String
        let mimeType: String
        let loadNumber: String?
        let consigneeName: String?
    }

    // MARK: - Calls

    /// `viga.diagnoseMechanical` — photograph → AI mechanical diagnosis.
    func diagnoseMechanical(
        imageBase64: String,
        mimeType: String = "image/jpeg",
        vehicleMake: String? = nil,
        vehicleModel: String? = nil,
        vehicleYear: Int? = nil,
        issueCategory: String? = nil,
        symptoms: [String]? = nil
    ) async throws -> MechanicalDiagnosis {
        let env: Envelope<MechanicalDiagnosis> = try await api.mutation(
            "visualIntelligence.diagnoseMechanical",
            input: DiagnoseMechanicalInput(
                imageBase64: imageBase64, mimeType: mimeType,
                vehicleMake: vehicleMake, vehicleModel: vehicleModel,
                vehicleYear: vehicleYear, issueCategory: issueCategory,
                symptoms: symptoms
            )
        )
        return env.data
    }

    func readGauge(
        imageBase64: String,
        mimeType: String = "image/jpeg",
        gaugeType: String? = nil
    ) async throws -> GaugeReading {
        let env: Envelope<GaugeReading> = try await api.mutation(
            "visualIntelligence.readGauge",
            input: GaugeInput(imageBase64: imageBase64, mimeType: mimeType, gaugeType: gaugeType)
        )
        return env.data
    }

    func verifySeal(
        imageBase64: String,
        mimeType: String = "image/jpeg",
        expectedSealNumber: String? = nil
    ) async throws -> SealVerification {
        let env: Envelope<SealVerification> = try await api.mutation(
            "visualIntelligence.verifySeal",
            input: SealInput(imageBase64: imageBase64, mimeType: mimeType, expectedSealNumber: expectedSealNumber)
        )
        return env.data
    }

    func inspectDVIR(
        imageBase64: String,
        mimeType: String = "image/jpeg",
        inspectionPoint: String? = nil
    ) async throws -> DVIRInspection {
        let env: Envelope<DVIRInspection> = try await api.mutation(
            "visualIntelligence.inspectDVIR",
            input: DVIRInput(imageBase64: imageBase64, mimeType: mimeType, inspectionPoint: inspectionPoint)
        )
        return env.data
    }

    func assessCargo(
        imageBase64: String,
        mimeType: String = "image/jpeg"
    ) async throws -> CargoCondition {
        let env: Envelope<CargoCondition> = try await api.mutation(
            "visualIntelligence.assessCargo",
            input: ImageInput(imageBase64: imageBase64, mimeType: mimeType)
        )
        return env.data
    }

    func verifyPOD(
        imageBase64: String,
        mimeType: String = "image/jpeg",
        loadNumber: String? = nil,
        consigneeName: String? = nil
    ) async throws -> PODVerification {
        let env: Envelope<PODVerification> = try await api.mutation(
            "visualIntelligence.verifyPOD",
            input: PODInput(imageBase64: imageBase64, mimeType: mimeType, loadNumber: loadNumber, consigneeName: consigneeName)
        )
        return env.data
    }

    func mapFacility(
        imageBase64: String,
        mimeType: String = "image/jpeg"
    ) async throws -> FacilityMapping {
        let env: Envelope<FacilityMapping> = try await api.mutation(
            "visualIntelligence.mapFacility",
            input: ImageInput(imageBase64: imageBase64, mimeType: mimeType)
        )
        return env.data
    }

    func assessDamage(
        imageBase64: String,
        mimeType: String = "image/jpeg"
    ) async throws -> DamageAssessment {
        let env: Envelope<DamageAssessment> = try await api.mutation(
            "visualIntelligence.assessDamage",
            input: ImageInput(imageBase64: imageBase64, mimeType: mimeType)
        )
        return env.data
    }

    func reportRoadCondition(
        imageBase64: String,
        mimeType: String = "image/jpeg"
    ) async throws -> RoadCondition {
        let env: Envelope<RoadCondition> = try await api.mutation(
            "visualIntelligence.reportRoadCondition",
            input: ImageInput(imageBase64: imageBase64, mimeType: mimeType)
        )
        return env.data
    }

    // MARK: - UIImage helper

    #if canImport(UIKit)
    /// Convenience: convert a UIImage to base64 JPEG (0.85 quality).
    /// Returns nil when the conversion fails (caller should fall back
    /// to a neutral "couldn't read photo" toast).
    static func base64(from image: UIImage, quality: CGFloat = 0.85) -> String? {
        image.jpegData(compressionQuality: quality)?.base64EncodedString()
    }
    #endif
}

// MARK: - authorityRouter (lease-on / DOT-MC sharing)
//
// Mirrors `frontend/server/routers/authority.ts` 1:1. The web platform
// is the source of truth for the data model. Lease types map to
// FMCSR Part 376:
//   • full_lease  — long-term lease-on, owner-op leased to a fleet
//   • trip_lease  — single trip under another carrier's authority
//   • interline   — two carriers share a haul (handoff at terminal)
//   • seasonal    — produce / harvest / hurricane response
// Compliance gates the lease activation: all 4 Part 376 boxes must
// be checked (written lease, exclusive control, insurance coverage,
// vehicle marking) before status can flip to "active."

struct AuthorityAPI {
    unowned let api: EusoTripAPI

    // MARK: Wire types

    struct OwnAuthority: Decodable {
        let companyId: Int
        let companyName: String?
        let legalName: String?
        let mcNumber: String?
        let dotNumber: String?
        let insurancePolicy: String?
        let insuranceExpiry: String?
        let complianceStatus: String?
        let isActive: Bool?
    }

    struct LeaseRow: Decodable, Identifiable {
        let id: Int
        let leaseType: String
        let status: String
        let mcNumber: String?
        let dotNumber: String?
        let startDate: String?
        let endDate: String?
        let revenueSharePercent: Double?
        let originCity: String?
        let originState: String?
        let destinationCity: String?
        let destinationState: String?
        let hasWrittenLease: Bool?
        let hasExclusiveControl: Bool?
        let hasInsuranceCoverage: Bool?
        let hasVehicleMarking: Bool?
        let lessorSignedAt: String?
        let lesseeSignedAt: String?
        // Resolved on the lessee/lessor side respectively
        let lessorCompanyName: String?
        let lessorMcNumber: String?
        let lessorDotNumber: String?
        let lesseeName: String?
        let notes: String?
    }

    struct MyAuthority: Decodable {
        let ownAuthority: OwnAuthority?
        let activeLeasesAsLessee: [LeaseRow]
        let activeLeasesAsLessor: [LeaseRow]
        let complianceScore: Int
    }

    func getMyAuthority() async throws -> MyAuthority {
        try await api.queryNoInput("authority.getMyAuthority")
    }

    struct GetMyLeasesInput: Encodable { let status: String? }
    func getMyLeases(status: String? = nil) async throws -> [LeaseRow] {
        try await api.query("authority.getMyLeases", input: GetMyLeasesInput(status: status))
    }

    struct LeaseStats: Decodable {
        let activeAsLessor: Int?
        let activeAsLessee: Int?
        let pendingSignature: Int?
        let expired: Int?
        let totalLeases: Int?
    }

    func getLeaseStats() async throws -> LeaseStats {
        try await api.queryNoInput("authority.getLeaseStats")
    }

    // MARK: - Browse + search authorities

    struct AuthorityListing: Decodable, Identifiable {
        var id: Int { companyId }
        let companyId: Int
        let companyName: String?
        let legalName: String?
        let mcNumber: String?
        let dotNumber: String?
        let complianceStatus: String?
        let insuranceValid: Bool?
    }

    struct BrowseInput: Encodable { let search: String? }

    func browseAuthorities(search: String? = nil) async throws -> [AuthorityListing] {
        try await api.query("authority.browseAuthorities", input: BrowseInput(search: search))
    }

    // MARK: - Create lease

    struct CreateLeaseInput: Encodable {
        let lessorCompanyId: Int
        let lesseeUserId: Int?
        let leaseType: String
        let startDate: String?
        let endDate: String?
        let revenueSharePercent: Double?
        let loadId: Int?
        let originCity: String?
        let originState: String?
        let destinationCity: String?
        let destinationState: String?
        let trailerTypes: [String]?
        let notes: String?
    }

    struct CreateLeaseAck: Decodable {
        let success: Bool
        let leaseId: Int
    }

    func createLease(_ input: CreateLeaseInput) async throws -> CreateLeaseAck {
        try await api.mutation("authority.createLease", input: input)
    }

    /// FMCSA SAFER lookup variant — pass the carrier's MC/DOT and
    /// legal name from a SAFER scrape; server creates the company
    /// row if it doesn't exist, then creates the lease.
    struct CreateLeaseFromFMCSAInput: Encodable {
        let mcNumber: String
        let dotNumber: String
        let legalName: String
        let leaseType: String
        let startDate: String?
        let endDate: String?
        let revenueSharePercent: Double?
        let loadId: Int?
        let originCity: String?
        let originState: String?
        let destinationCity: String?
        let destinationState: String?
        let notes: String?
    }

    func createLeaseFromFMCSA(_ input: CreateLeaseFromFMCSAInput) async throws -> CreateLeaseAck {
        try await api.mutation("authority.createLeaseFromFMCSA", input: input)
    }

    // MARK: - Compliance + sign + terminate

    struct UpdateComplianceInput: Encodable {
        let leaseId: Int
        let hasWrittenLease: Bool?
        let hasExclusiveControl: Bool?
        let hasInsuranceCoverage: Bool?
        let hasVehicleMarking: Bool?
    }

    struct AuthorityOkAck: Decodable { let success: Bool }

    func updateCompliance(
        leaseId: Int,
        hasWrittenLease: Bool? = nil,
        hasExclusiveControl: Bool? = nil,
        hasInsuranceCoverage: Bool? = nil,
        hasVehicleMarking: Bool? = nil
    ) async throws -> AuthorityOkAck {
        try await api.mutation(
            "authority.updateCompliance",
            input: UpdateComplianceInput(
                leaseId: leaseId,
                hasWrittenLease: hasWrittenLease,
                hasExclusiveControl: hasExclusiveControl,
                hasInsuranceCoverage: hasInsuranceCoverage,
                hasVehicleMarking: hasVehicleMarking
            )
        )
    }

    struct SignLeaseInput: Encodable {
        let leaseId: Int
        /// "lessor" | "lessee"
        let role: String
    }

    func signLease(leaseId: Int, role: String) async throws -> AuthorityOkAck {
        try await api.mutation(
            "authority.signLease",
            input: SignLeaseInput(leaseId: leaseId, role: role)
        )
    }

    struct TerminateLeaseInput: Encodable {
        let leaseId: Int
        let reason: String?
    }

    func terminateLease(leaseId: Int, reason: String? = nil) async throws -> AuthorityOkAck {
        try await api.mutation(
            "authority.terminateLease",
            input: TerminateLeaseInput(leaseId: leaseId, reason: reason)
        )
    }

    // MARK: - Equipment authority

    struct EquipmentAuthority: Decodable, Identifiable {
        var id: Int { vehicleId }
        let vehicleId: Int
        let vin: String?
        let make: String?
        let model: String?
        let year: Int?
        let type: String?
        let licensePlate: String?
        let status: String?
        /// "own" | "leased"
        let authoritySource: String
        let leaseId: Int?
        let leaseMcNumber: String?
        let leaseDotNumber: String?
    }

    func getEquipmentAuthority() async throws -> [EquipmentAuthority] {
        try await api.queryNoInput("authority.getEquipmentAuthority")
    }
}

// MARK: - adaptiveFeeRouter (EusoWallet Adaptive Fee Engine)
//
// Mirrors `frontend/server/routers/adaptiveFee.ts` 1:1. The web
// platform is the source of truth — server runs the 6-dimension
// multiplier × cycle-dampener × MHI math and returns a fully-priced
// breakdown the iOS UI just renders. Driver-side surfaces use
// `estimate` (no audit log; cheap to call on every load card focus)
// and `getMHI` (one chip on Home + Wallet showing the current
// market phase). The catalyst-side `calculate` mutation runs at
// load booking — iOS doesn't call that directly.

struct AdaptiveFeeAPI {
    unowned let api: EusoTripAPI

    // MARK: - Wire types

    /// `AdaptiveFeeResult.breakdown` — every multiplier the server
    /// applied. Drivers see this as a per-line trace ("vertical x
    /// 1.18 reefer", "hazmat x 1.25", "cycle x 1.15 contraction")
    /// so they can argue with the carrier when the fee feels wrong.
    struct FeeBreakdown: Decodable, Hashable {
        let baseRate: Double
        let countryMultiplier: Double
        let verticalMultiplier: Double
        let productMultiplier: Double
        let hazmatMultiplier: Double
        let distanceMultiplier: Double
        let cycleDampener: Double
        let loadTypeAdjustment: Double
        let rawRate: Double
        let floor: Double
        let ceiling: Double
        let cyclePhase: String
        let marketHealthIndex: Double
        let volumeDiscount: Double
        let gamificationDiscount: Double
    }

    struct FeeResult: Decodable, Hashable {
        let effectiveRate: Double
        let feeAmount: Double
        let carrierPayment: Double?
        let breakdown: FeeBreakdown?
        
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.effectiveRate = try c.decode(Double.self, forKey: .effectiveRate)
            self.feeAmount = try c.decode(Double.self, forKey: .feeAmount)
            self.carrierPayment = try c.decodeIfPresent(Double.self, forKey: .carrierPayment)
            self.breakdown = try c.decodeIfPresent(FeeBreakdown.self, forKey: .breakdown)
        }
        
        enum CodingKeys: String, CodingKey {
            case effectiveRate
            case feeAmount
            case carrierPayment
            case breakdown
        }
    }

    // MARK: - estimate (driver-facing live preview)

    struct EstimateInput: Encodable {
        let loadRate: Double
        let originCountry: String
        let destCountry: String
        let vertical: String
        let equipmentType: String
        let hazmatClass: String
        let distanceMiles: Double
        let loadType: String
    }

    /// `adaptiveFee.estimate` — live fee preview without writing to
    /// the audit log. Use on load detail to show drivers what they'd
    /// net before they tap Book. Defaults match the playbook's
    /// "domestic dry van spot" baseline so a missing field doesn't
    /// blow up the call.
    func estimate(
        loadRate: Double,
        originCountry: String = "US",
        destCountry: String = "US",
        vertical: String = "general_freight",
        equipmentType: String = "dry_van",
        hazmatClass: String = "none",
        distanceMiles: Double = 500,
        loadType: String = "spot"
    ) async throws -> FeeResult {
        try await api.query(
            "adaptiveFee.estimate",
            input: EstimateInput(
                loadRate: loadRate,
                originCountry: originCountry,
                destCountry: destCountry,
                vertical: vertical,
                equipmentType: equipmentType,
                hazmatClass: hazmatClass,
                distanceMiles: distanceMiles,
                loadType: loadType
            )
        )
    }

    // MARK: - MHI + Cycle dampener

    struct MHISnapshot: Decodable {
        let composite: Double
        let cyclePhase: String   // EXPANSION | NEUTRAL | CONTRACTION
        let dampener: Double
        let floor: Double
        let ceiling: Double
        let asOf: String?
        let components: MHIComponents?
    }

    struct MHIComponents: Decodable, Hashable {
        let loadToTruck: Double?
        let truckingPPI: Double?
        let dieselDelta: Double?
        let contractSpotSpread: Double?
    }

    func getMHI() async throws -> MHISnapshot {
        try await api.queryNoInput("adaptiveFee.getMHI")
    }

    struct DampenerSnapshot: Decodable {
        let cyclePhase: String
        let dampener: Double
        let floor: Double
        let ceiling: Double
    }

    struct DampenerInput: Encodable { let mhiOverride: Double? }
    func getCycleDampener(mhiOverride: Double? = nil) async throws -> DampenerSnapshot {
        try await api.query(
            "adaptiveFee.getCycleDampener",
            input: DampenerInput(mhiOverride: mhiOverride)
        )
    }

    // MARK: - Fintech stack

    struct FintechOption: Decodable, Identifiable, Hashable {
        var id: String { type }
        let type: String        // instant_pay | cash_advance | quick_pay_net7 | quick_pay_net3 | same_day | factoring
        let label: String
        let feePercent: Double?
        let flatFee: Double?
        let description: String?
        let active: Bool
    }

    func getAvailableFintech() async throws -> [FintechOption] {
        try await api.queryNoInput("adaptiveFee.getAvailableFintech")
    }

    struct FintechFeeInput: Encodable {
        let type: String
        let amount: Double
    }

    struct FintechFeeAck: Decodable {
        let type: String
        let amount: Double
        let feeAmount: Double
        let netToCarrier: Double
    }

    func calculateFintechFee(type: String, amount: Double) async throws -> FintechFeeAck {
        try await api.mutation(
            "adaptiveFee.calculateFintechFee",
            input: FintechFeeInput(type: type, amount: amount)
        )
    }

    struct EngineStatus: Decodable {
        let mode: String           // shadow | full | off
        let mhi: Double?
        let cyclePhase: String?
        let lastUpdated: String?
    }

    func getEngineStatus() async throws -> EngineStatus {
        try await api.queryNoInput("adaptiveFee.getEngineStatus")
    }
}

// MARK: - usersRouter
//
// Server parity: `frontend/server/routers/users.ts`. This file currently
// surfaces the cross-role notification-preferences matrix used by the
// Shipper Settings brick (211) and any future role-Settings ports. Other
// `users.*` procedures (admin impersonation, role updates, tenant
// introspection) are deliberately NOT wrapped here — they are admin-
// only flows and the iOS Driver/Shipper/Carrier/Broker/Catalyst surfaces
// have no consumers for them. Adding a wrapper without a consumer would
// be a doctrine §13 no-fake-data violation by the same logic that keeps
// other admin-only flows out of the iOS API layer.
//
// Both procedures wrapped below are `protectedProcedure` server-side, so
// any authenticated user can read and update their own preferences.
// Server-side the row in `notificationPreferences` is keyed on
// `userId = ctx.user.id` — there is no shipper/driver/broker variant.
//
// Returned shape (full 11-boolean matrix):
//
//   {
//     emailNotifications: bool        // master email switch
//     pushNotifications:  bool        // master push switch
//     smsNotifications:   bool        // master SMS switch
//     inAppNotifications: bool        // in-app banner toasts
//     loadUpdates:        bool        // load posted / assigned / status change
//     bidAlerts:          bool        // new bid received on a posted load
//     paymentAlerts:      bool        // settlement / payout / invoice paid
//     messageAlerts:      bool        // new chat message
//     missionAlerts:      bool        // gamification mission / streak / crate
//     promotionalAlerts:  bool        // marketing / referral / new feature
//     weeklyDigest:       bool        // Monday digest email
//   }
//
// `updateNotificationPreferences` accepts the same 11 fields, all
// optional — the server does a partial update (`UPDATE … SET <only the
// supplied keys>` semantics via Drizzle's `.set(input)` with `updatedAt`
// stamped). On the client we typically send a single field at a time so
// the optimistic UI flip and the server reconcile happen on the same
// boolean. Server returns `{ success: true }` and does NOT echo the new
// matrix — clients that need the canonical state should `.refresh()`
// from `users.getNotificationPreferences` after the mutation lands.
//

struct UsersAPI {
    unowned let api: EusoTripAPI

    /// 11-boolean preference matrix. Mirrors the row shape of
    /// `drizzle/schema.ts → notificationPreferences`. Defaults below
    /// are the same as the server's "no row exists yet" defaults so
    /// the UI never has to special-case a brand-new account.
    struct PreferenceMatrix: Decodable, Equatable {
        let emailNotifications: Bool
        let pushNotifications: Bool
        let smsNotifications: Bool
        let inAppNotifications: Bool
        let loadUpdates: Bool
        let bidAlerts: Bool
        let paymentAlerts: Bool
        let messageAlerts: Bool
        let missionAlerts: Bool
        let promotionalAlerts: Bool
        let weeklyDigest: Bool

        /// Server-aligned default matrix. Used by the Settings UI when
        /// rendering before the first round-trip lands so the toggles
        /// don't flash off→on as the network resolves.
        static let serverDefault = PreferenceMatrix(
            emailNotifications: true,
            pushNotifications: true,
            smsNotifications: false,
            inAppNotifications: true,
            loadUpdates: true,
            bidAlerts: true,
            paymentAlerts: true,
            messageAlerts: true,
            missionAlerts: true,
            promotionalAlerts: false,
            weeklyDigest: true
        )
    }

    /// Partial-update payload. Every field is optional — only the
    /// supplied keys move on the server. The Settings UI sends a single
    /// `Patch` per toggle flip so optimistic and authoritative states
    /// converge on one boolean at a time.
    struct Patch: Encodable {
        var emailNotifications: Bool?
        var pushNotifications: Bool?
        var smsNotifications: Bool?
        var inAppNotifications: Bool?
        var loadUpdates: Bool?
        var bidAlerts: Bool?
        var paymentAlerts: Bool?
        var messageAlerts: Bool?
        var missionAlerts: Bool?
        var promotionalAlerts: Bool?
        var weeklyDigest: Bool?

        // Encode only the non-nil keys so server's `.set(input)` writes
        // exactly the fields the user toggled — leaving the rest alone.
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: K.self)
            if let v = emailNotifications  { try c.encode(v, forKey: .emailNotifications) }
            if let v = pushNotifications   { try c.encode(v, forKey: .pushNotifications) }
            if let v = smsNotifications    { try c.encode(v, forKey: .smsNotifications) }
            if let v = inAppNotifications  { try c.encode(v, forKey: .inAppNotifications) }
            if let v = loadUpdates         { try c.encode(v, forKey: .loadUpdates) }
            if let v = bidAlerts           { try c.encode(v, forKey: .bidAlerts) }
            if let v = paymentAlerts       { try c.encode(v, forKey: .paymentAlerts) }
            if let v = messageAlerts       { try c.encode(v, forKey: .messageAlerts) }
            if let v = missionAlerts       { try c.encode(v, forKey: .missionAlerts) }
            if let v = promotionalAlerts   { try c.encode(v, forKey: .promotionalAlerts) }
            if let v = weeklyDigest        { try c.encode(v, forKey: .weeklyDigest) }
        }

        private enum K: String, CodingKey {
            case emailNotifications, pushNotifications, smsNotifications, inAppNotifications
            case loadUpdates, bidAlerts, paymentAlerts, messageAlerts, missionAlerts
            case promotionalAlerts, weeklyDigest
        }
    }

    struct UpdateAck: Decodable {
        let success: Bool
    }

    /// `users.getNotificationPreferences` — query, no input. Returns the
    /// full 11-boolean matrix for the current authenticated user. Server
    /// upserts a default row on first read.
    func getNotificationPreferences() async throws -> PreferenceMatrix {
        try await api.queryNoInput("users.getNotificationPreferences")
    }

    /// `users.updateNotificationPreferences` — mutation, partial update.
    /// Pass a `Patch` with only the keys that changed. Returns
    /// `{ success: true }`. The Settings UI typically follows up with a
    /// `getNotificationPreferences()` to reconcile, but optimistic flips
    /// can stand on this ack alone for non-critical preferences.
    func updateNotificationPreferences(_ patch: Patch) async throws -> UpdateAck {
        try await api.mutation("users.updateNotificationPreferences", input: patch)
    }
}

// MARK: - EusoTicketAPI
//
// Bills of Lading + run tickets + per-haul receipts. Mirrors
// `frontend/server/routers/eusoTicket.ts` 1:1. Used by 089_MeEusoTickets
// driver screen + (future) terminal-manager surfaces.
//
// All procedures are `protectedProcedure` server-side — any authenticated
// user (DRIVER included) can read their own tickets/BOLs. Mutations
// (status changes, PDF generation) authorize off the resolver context,
// not the role gate, so the driver-facing list/PDF flow works without
// the carrier-sheet role-gate problem `drivers.getMyCarrier` had.
//
// Receipts (lumper / scale / fuel / toll) ride on the Documents Center
// (HubCategory.loadDocs) — they are the same `documents` table rows
// the BOL list reads, just classified by type. No separate router.
struct EusoTicketAPI {
    unowned let api: EusoTripAPI

    /// Driver-facing list row for run tickets. Mirrors the `tickets[]`
    /// shape returned by `eusoTicket.listRunTickets`.
    struct RunTicketRow: Decodable, Identifiable {
        let ticketNumber: String
        let status: String
        let productName: String?
        let netVolume: Double?
        let apiGravity: Double?
        let driverName: String?
        let vehiclePlate: String?
        let terminalName: String?
        let createdAt: String?
        let spectraMatchVerified: Bool?
        let spectraMatchConfidence: Double?

        var id: String { ticketNumber }
    }

    struct RunTicketList: Decodable {
        let tickets: [RunTicketRow]
        let total: Int
    }

    /// Driver-facing list row for BOLs. Mirrors `eusoTicket.listBOLs`.
    struct BOLRow: Decodable, Identifiable {
        let bolNumber: String?
        let loadNumber: String?
        let status: String
        let driverName: String?
        let fileUrl: String?
        let createdAt: String?

        var id: String { bolNumber ?? UUID().uuidString }
    }

    struct BOLList: Decodable {
        let bols: [BOLRow]
        let total: Int
    }

    /// Terminal stats — used by the EusoTicket header summary strip.
    struct TerminalStats: Decodable {
        let terminalId: String
        let todayTickets: Int
        let todayVolume: Double
        let weekTickets: Int
        let weekVolume: Double
        let monthTickets: Int
        let monthVolume: Double
        let avgLoadTime: Double?
        let avgApiGravity: Double?
        let pendingTickets: Int
        let pendingBOLs: Int
        struct CrudeType: Decodable, Hashable {
            let name: String
            let count: Int
        }
        let topCrudeTypes: [CrudeType]
    }

    /// Single run-ticket detail — broader shape with hazmat / SpectraMatch
    /// fields. Many fields are optional to absorb the server's empty
    /// "not_found" response without throwing.
    struct RunTicketDetail: Decodable {
        let ticketNumber: String
        let status: String
        let loadId: String?
        let catalystId: String?
        let driverId: String?
        let vehicleId: String?
        let originTerminalId: String?
        let productName: String?
        let crudeType: String?
        let apiGravity: Double?
        let bsw: Double?
        let sulfurContent: Double?
        let temperature: Double?
        let grossVolume: Double?
        let netVolume: Double?
        let grossWeight: Double?
        let netWeight: Double?
        let loadStartTime: String?
        let loadEndTime: String?
        let rackNumber: String?
        let bayNumber: String?
        let meterNumber: String?
        let sealNumbers: [String]?
        let spectraMatchVerified: Bool?
        let spectraMatchConfidence: Double?
        let createdAt: String?
    }

    struct PDFGenerated: Decodable {
        let success: Bool
        let documentUrl: String
        let generatedAt: String
        let ticketNumber: String?
        let bolNumber: String?
    }

    struct StatusUpdated: Decodable {
        let success: Bool
        let updatedAt: String
        let status: String
        let ticketNumber: String?
        let bolNumber: String?
    }

    // MARK: List

    /// `eusoTicket.listRunTickets` — driver scoped to their own loads
    /// when the server resolves `ctx.user.id` (no per-driver filter
    /// needed in input; the server already filters via `loads.driverId`
    /// when called from a driver context).
    func listRunTickets(driverId: String? = nil,
                       status: String? = nil,
                       limit: Int = 20) async throws -> RunTicketList {
        struct Input: Encodable {
            let driverId: String?
            let status: String?
            let limit: Int
        }
        return try await api.query(
            "eusoTicket.listRunTickets",
            input: Input(driverId: driverId, status: status, limit: limit)
        )
    }

    /// `eusoTicket.listBOLs`.
    func listBOLs(status: String? = nil, limit: Int = 20) async throws -> BOLList {
        struct Input: Encodable {
            let status: String?
            let limit: Int
        }
        return try await api.query(
            "eusoTicket.listBOLs",
            input: Input(status: status, limit: limit)
        )
    }

    /// `eusoTicket.getRunTicket`.
    func getRunTicket(ticketNumber: String) async throws -> RunTicketDetail {
        struct Input: Encodable { let ticketNumber: String }
        return try await api.query(
            "eusoTicket.getRunTicket",
            input: Input(ticketNumber: ticketNumber)
        )
    }

    /// `eusoTicket.getTerminalStats`.
    func getTerminalStats(terminalId: String) async throws -> TerminalStats {
        struct Input: Encodable { let terminalId: String }
        return try await api.query(
            "eusoTicket.getTerminalStats",
            input: Input(terminalId: terminalId)
        )
    }

    // MARK: Status mutations

    /// `eusoTicket.updateRunTicketStatus`.
    func updateRunTicketStatus(ticketNumber: String,
                               status: String,
                               notes: String? = nil) async throws -> StatusUpdated {
        struct Input: Encodable {
            let ticketNumber: String
            let status: String
            let notes: String?
        }
        return try await api.mutation(
            "eusoTicket.updateRunTicketStatus",
            input: Input(ticketNumber: ticketNumber, status: status, notes: notes)
        )
    }

    /// `eusoTicket.updateBOLStatus`.
    func updateBOLStatus(bolNumber: String,
                        status: String,
                        notes: String? = nil,
                        proofOfDelivery: String? = nil) async throws -> StatusUpdated {
        struct Input: Encodable {
            let bolNumber: String
            let status: String
            let notes: String?
            let proofOfDelivery: String?
        }
        return try await api.mutation(
            "eusoTicket.updateBOLStatus",
            input: Input(bolNumber: bolNumber, status: status,
                         notes: notes, proofOfDelivery: proofOfDelivery)
        )
    }

    // MARK: PDF generation

    /// `eusoTicket.generateRunTicketPDF` — server returns a relative
    /// path under `/documents/run-tickets/`; iOS resolves it against
    /// the API origin like other document URLs.
    func generateRunTicketPDF(ticketNumber: String) async throws -> PDFGenerated {
        struct Input: Encodable { let ticketNumber: String }
        return try await api.mutation(
            "eusoTicket.generateRunTicketPDF",
            input: Input(ticketNumber: ticketNumber)
        )
    }

    /// `eusoTicket.generateBOLPDF`.
    func generateBOLPDF(bolNumber: String) async throws -> PDFGenerated {
        struct Input: Encodable { let bolNumber: String }
        return try await api.mutation(
            "eusoTicket.generateBOLPDF",
            input: Input(bolNumber: bolNumber)
        )
    }
}

// MARK: - LoadTemplatesAPI
//
// Saved lane / commodity / equipment configurations. Backs the
// shipper-settings "Default lane configs" card and (next firing) the
// post-load screen's prefill flow. Mirrors
// `frontend/server/routers/loadTemplates.ts` 1:1.
struct LoadTemplatesAPI {
    unowned let api: EusoTripAPI

    /// One saved template row. Mirrors the `loadTemplates` schema
    /// (`drizzle/schema.ts:561+`). Most fields optional — a shipper can
    /// save a lane-only template without locking commodity / rate.
    struct Template: Decodable, Identifiable, Hashable {
        let id: Int
        let name: String
        let description: String?
        let origin: Location?
        let destination: Location?
        let distance: String?
        let commodity: String?
        let cargoType: String?
        let equipmentType: String?
        let trailerType: String?
        let weight: String?
        let weightUnit: String?
        let quantity: String?
        let quantityUnit: String?
        let hazmatClass: String?
        let unNumber: String?
        let rate: String?
        let rateType: String?
        let isFavorite: Bool?
        let isArchived: Bool?
        let useCount: Int?
        let lastUsedAt: String?
        let createdAt: String?
        let updatedAt: String?

        struct Location: Decodable, Hashable {
            let city: String?
            let state: String?
            let zipCode: String?
            let address: String?
            let facilityName: String?
        }
    }

    struct ListInput: Encodable {
        let search: String?
        let favoritesOnly: Bool?
        let includeArchived: Bool?
    }

    /// `loadTemplates.list` — current user's saved templates.
    /// Returns favorites first (server-side ORDER BY), then most
    /// recently used. iOS settings card pulls top 100.
    func list(search: String? = nil,
              favoritesOnly: Bool? = nil,
              includeArchived: Bool? = nil) async throws -> [Template] {
        try await api.query(
            "loadTemplates.list",
            input: ListInput(
                search: search,
                favoritesOnly: favoritesOnly,
                includeArchived: includeArchived
            )
        )
    }

    // MARK: - Create + materialize (Phase 19 — recurring loads)

    /// Wire shape for `loadTemplates.create`. Mirrors the server
    /// schema exactly (loadTemplates.ts:105) — every field besides
    /// `name` is optional so a shipper can save a lane-only
    /// template and fill the rest at materialization time.
    struct CreateInput: Encodable {
        let name: String
        let description: String?
        let origin: TemplateLocation
        let destination: TemplateLocation
        let distance: Double?
        let commodity: String?
        let cargoType: String?
        let equipmentType: String?
        let weight: String?
        let weightUnit: String?
        let rate: Double?
        let rateType: String?
        let preferredDays: [String]?
        let preferredPickupTime: String?
        let specialInstructions: String?
    }

    /// Encodable Location used at create time. Server stores under
    /// the same JSON column used by Template.Location. Caller
    /// passes city + state at minimum; richer columns (street,
    /// zip, facility) optional.
    struct TemplateLocation: Encodable {
        let city: String
        let state: String
        let zipCode: String?
        let address: String?
        let facilityName: String?
    }

    struct CreateAck: Decodable, Hashable {
        let id: Int?
        let name: String?
    }

    /// `loadTemplates.create` — save a recurring lane template.
    /// Once saved, `loads.createFromTemplate(templateId, pickupDate,
    /// deliveryDate)` materializes a real load on the schedule.
    @discardableResult
    func create(_ input: CreateInput) async throws -> CreateAck {
        try await api.mutation("loadTemplates.create", input: input)
    }
}

// MARK: - ControlTowerAPI
//
// Multi-modal supply-chain visibility. Mirrors verbatim
// `frontend/server/routers/controlTower.ts` (procs `overview`,
// `exceptions`, `recentActivity`). Backs the Shipper Control Tower
// brick 212 + any future Catalyst / Broker dispatch overview surface
// that wants the same envelope shape.
struct ControlTowerAPI {
    unowned let api: EusoTripAPI

    /// Per-mode lane counts (active / inTransit / delivered for truck,
    /// active / inTransit for vessel + rail). The web peer
    /// (`ControlTower.tsx`) sums truck.active + vessel.active for the
    /// "Total Active" header tile.
    struct ModeCounts: Decodable, Hashable {
        let active: Int
        let inTransit: Int
        let delivered: Int?
    }

    struct Totals: Decodable, Hashable {
        let active: Int
        let inTransit: Int
    }

    struct Overview: Decodable, Hashable {
        let truck: ModeCounts
        let vessel: ModeCounts
        let rail: ModeCounts
        let total: Totals
    }

    /// Fetch the multi-modal overview. No input.
    func overview() async throws -> Overview {
        try await api.queryNoInput("controlTower.overview")
    }

    // MARK: Exceptions

    /// One late-delivery / ETA-passed exception row. Server emits
    /// truck rows with `mode: "truck"` carrying pickup + delivery
    /// JSON columns; vessel rows with `mode: "vessel"` carrying
    /// origin + destination port ids + booking number. Wire-field
    /// `id` (Int) is mapped to `rowId` so `Identifiable.id: String`
    /// can return a stable composite without colliding.
    struct ExceptionRow: Decodable, Hashable, Identifiable {
        let rowId: Int
        let mode: String
        let exceptionType: String
        let status: String?
        // Truck-shape fields
        let loadNumber: String?
        let deliveryDate: String?
        // Vessel-shape fields
        let bookingNumber: String?
        let eta: String?
        let originPortId: Int?
        let destinationPortId: Int?
        let pickupLocation: LocationStub?
        let deliveryLocation: LocationStub?

        enum CodingKeys: String, CodingKey {
            case rowId = "id"
            case mode, exceptionType, status
            case loadNumber, deliveryDate
            case bookingNumber, eta, originPortId, destinationPortId
            case pickupLocation, deliveryLocation
        }

        var id: String { "\(mode)-\(rowId)" }

        struct LocationStub: Decodable, Hashable {
            let city: String?
            let state: String?
        }
    }

    struct ExceptionsResponse: Decodable, Hashable {
        let truckExceptions: [ExceptionRow]
        let vesselExceptions: [ExceptionRow]
        let totalExceptions: Int
    }

    func exceptions(limit: Int = 50) async throws -> ExceptionsResponse {
        struct Input: Encodable { let limit: Int }
        return try await api.query(
            "controlTower.exceptions",
            input: Input(limit: limit)
        )
    }

    // MARK: Recent activity

    /// One row in the multi-modal activity feed. Server merges the
    /// most-recent truck loads + vessel shipments and returns them
    /// sorted by `updatedAt` desc. Wire-field `id` (Int) is mapped to
    /// `rowId` so the SwiftUI `Identifiable` requirement can return a
    /// composite "\(mode)-\(rowId)" String without clashing with the
    /// Int wire shape.
    struct ActivityRow: Decodable, Hashable, Identifiable {
        let mode: String
        let rowId: Int
        let status: String?
        let label: String?    // loadNumber for truck, bookingNumber for vessel
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case mode
            case rowId = "id"
            case status, label, updatedAt
        }

        var id: String { "\(mode)-\(rowId)" }
    }

    func recentActivity(limit: Int = 20) async throws -> [ActivityRow] {
        struct Input: Encodable { let limit: Int }
        return try await api.query(
            "controlTower.recentActivity",
            input: Input(limit: limit)
        )
    }
}

// MARK: - Co2CalculatorAPI
//
// Per-shipment carbon emissions across truck / rail / vessel / air with
// equivalence helpers (trees-to-offset, gallons-of-gasoline, car-miles)
// and CII rating for vessel mode. Mirrors verbatim
// `frontend/server/routers/co2Calculator.ts` (procs
// `calculateTruckShipment`, `calculateMultiModal`). Vessel-only
// `calculateVesselShipment` is gated by `vesselProcedure` server-side
// and therefore not exposed here for the Shipper-track surface.
struct Co2CalculatorAPI {
    unowned let api: EusoTripAPI

    /// Equivalence triplet emitted by the truck-shipment calculator —
    /// gives the shipper a tangible feel for what a CO2 number means.
    struct Equivalents: Decodable, Hashable {
        let treesNeededToOffset: Int
        let gallonsOfGasoline: Int
        let milesInAvgCar: Int
    }

    /// Truck-shipment result envelope. Mirrors
    /// `co2Calculator.calculateTruckShipment` output.
    struct TruckResult: Decodable, Hashable {
        let mode: String
        let distanceMiles: Double
        let weightTons: Double
        let equipmentType: String
        let emissionFactor: Double
        let co2Kg: Double
        let co2Tonnes: Double
        let equivalents: Equivalents
    }

    struct TruckInput: Encodable {
        let loadId: Int?
        let distanceMiles: Double?
        let weightTons: Double?
        let equipmentType: String?
    }

    /// Compute the truck-mode CO2 footprint for a single shipment.
    /// Either pass `loadId` (server pulls distance/weight/equipment
    /// from the loads row) OR the raw triplet.
    func calculateTruckShipment(
        loadId: Int? = nil,
        distanceMiles: Double? = nil,
        weightTons: Double? = nil,
        equipmentType: String? = nil
    ) async throws -> TruckResult {
        try await api.query(
            "co2Calculator.calculateTruckShipment",
            input: TruckInput(
                loadId: loadId,
                distanceMiles: distanceMiles,
                weightTons: weightTons,
                equipmentType: equipmentType
            )
        )
    }

    // MARK: Multi-modal

    /// One leg of a multi-modal shipment. Different modes accept
    /// different distance units (miles / nm / km) — encode whatever
    /// the caller has and the server picks the right field.
    struct MultiModalLeg: Encodable {
        let mode: String        // "truck" | "rail" | "vessel" | "air"
        let distanceMiles: Double?
        let distanceNm: Double?
        let distanceKm: Double?
        let weightTons: Double?
        let equipmentType: String?
        let fuelType: String?
        let fuelConsumedTonnes: Double?

        init(mode: String,
             distanceMiles: Double? = nil,
             distanceNm: Double? = nil,
             distanceKm: Double? = nil,
             weightTons: Double? = nil,
             equipmentType: String? = nil,
             fuelType: String? = nil,
             fuelConsumedTonnes: Double? = nil) {
            self.mode = mode
            self.distanceMiles = distanceMiles
            self.distanceNm = distanceNm
            self.distanceKm = distanceKm
            self.weightTons = weightTons
            self.equipmentType = equipmentType
            self.fuelType = fuelType
            self.fuelConsumedTonnes = fuelConsumedTonnes
        }
    }

    struct MultiModalLegResult: Decodable, Hashable, Identifiable {
        let leg: Int
        let mode: String
        let co2Kg: Double

        var id: Int { leg }
    }

    struct MultiModalResult: Decodable, Hashable {
        let legs: [MultiModalLegResult]
        let totalCo2Kg: Double
        let totalCo2Tonnes: Double
        let carbonOffsetCostUsd: Double
    }

    struct MultiModalInput: Encodable { let legs: [MultiModalLeg] }

    /// Compute carbon footprint across an arbitrary leg sequence.
    func calculateMultiModal(legs: [MultiModalLeg]) async throws -> MultiModalResult {
        try await api.query(
            "co2Calculator.calculateMultiModal",
            input: MultiModalInput(legs: legs)
        )
    }
}

// MARK: - RFPManagerAPI
//
// Procurement workflow — list / create / publish / score / award RFPs.
// Mirrors verbatim `frontend/server/routers/rfpManager.ts`. Backs the
// Shipper RFP brick (215) and any future Catalyst-side bid-response
// surface (Catalyst sees the same RFPs as a "carrier opportunity"
// inbox).
struct RFPManagerAPI {
    unowned let api: EusoTripAPI

    /// Carrier-eligibility constraints attached to an RFP. All
    /// optional — a draft RFP can publish without any constraints
    /// and accept bids from every motor carrier.
    struct CarrierRequirements: Decodable, Hashable, Encodable {
        let minSafetyScore: Int?
        let minOnTimeRate: Int?
        let requiredInsurance: Int?
        let hazmatCertRequired: Bool?
        let minFleetSize: Int?
        let preferredTiers: [String]?
    }

    /// Server-emitted scoring weights. Each is a 0–100 weight that
    /// adds up to ~100 across the 5 dimensions.
    struct ScoringWeights: Decodable, Hashable, Encodable {
        let rate: Int?
        let serviceLevel: Int?
        let safety: Int?
        let capacity: Int?
        let experience: Int?
    }

    /// City + state pair — used for both lane origin and destination.
    struct CityState: Decodable, Hashable, Encodable {
        let city: String
        let state: String
    }

    /// One lane on an RFP. Server returns a flat shape with origin /
    /// destination broken out as nested `CityState` (see
    /// `loadRFPWithLanes` in the server module).
    struct Lane: Decodable, Hashable, Identifiable {
        let id: String
        let origin: CityState
        let destination: CityState
        let estimatedDistance: Int
        let annualVolume: Int?
        let volumeUnit: String?
        let equipmentRequired: String
        let hazmat: Bool?
        let temperatureControlled: Bool?
        let targetRate: Double?
        let rateType: String?
        let frequencyPerWeek: Int
        let specialRequirements: [String]?
    }

    /// Full RFP envelope. Mirrors server `loadRFPWithLanes` projection.
    struct RFP: Decodable, Hashable, Identifiable {
        let id: String
        let title: String
        let description: String?
        let status: String
        let responseDeadline: String?
        let contractStartDate: String?
        let contractEndDate: String?
        let distributedTo: Int
        let responsesReceived: Int
        let publishedAt: String?
        let companyName: String?
        let lanes: [Lane]
        let carrierRequirements: CarrierRequirements?
        let scoringWeights: ScoringWeights?
    }

    /// One lane bid inside a carrier's overall RFP response.
    struct LaneBid: Decodable, Hashable, Identifiable {
        let laneId: String
        let bidRate: Double
        let transitDays: Int?
        let capacityPerWeek: Int?

        var id: String { laneId }
    }

    /// One carrier's response to an RFP. Carries their reputational
    /// summary (tier / safety / on-time / fleet size) plus per-lane
    /// bid amounts.
    struct BidResponse: Decodable, Hashable, Identifiable {
        let id: String
        let carrierId: Int
        let carrierName: String
        let carrierTier: String?
        let safetyScore: Int?
        let onTimeRate: Int?
        let fleetSize: Int?
        let laneBids: [LaneBid]
        let submittedAt: String?
    }

    /// Server-side scoring projection across 5 dimensions, with a
    /// final overallScore + recommendation enum (`award` / `shortlist`
    /// / `decline`). Built by `scoreBidResponse` against the RFP's
    /// scoringWeights (or platform defaults).
    struct Scorecard: Decodable, Hashable, Identifiable {
        let carrierId: Int
        let carrierName: String
        let carrierTier: String?
        let overallScore: Int
        let rateScore: Int
        let serviceLevelScore: Int
        let safetyScore: Int
        let capacityScore: Int
        let experienceScore: Int
        let recommendation: String   // "award" | "shortlist" | "decline"

        var id: Int { carrierId }
    }

    // MARK: List + Detail

    func getRFPs() async throws -> [RFP] {
        try await api.queryNoInput("rfpManager.getRFPs")
    }

    func getRFPDetail(rfpId: String) async throws -> RFP {
        struct Input: Encodable { let rfpId: String }
        return try await api.query(
            "rfpManager.getRFPDetail",
            input: Input(rfpId: rfpId)
        )
    }

    // MARK: Bids + Scoring

    func getBidResponses(rfpId: String) async throws -> [BidResponse] {
        struct Input: Encodable { let rfpId: String }
        return try await api.query(
            "rfpManager.getBidResponses",
            input: Input(rfpId: rfpId)
        )
    }

    func scoreResponses(rfpId: String) async throws -> [Scorecard] {
        struct Input: Encodable { let rfpId: String }
        return try await api.query(
            "rfpManager.scoreResponses",
            input: Input(rfpId: rfpId)
        )
    }

    // MARK: Mutations

    struct PublishResult: Decodable {
        let success: Bool
        let rfpId: String
        let status: String
        let distributedTo: Int
        let publishedAt: String?
    }

    /// Flip a draft RFP to `published`, count eligible motor
    /// carriers, fan distribution. Server-side this is the moment
    /// the RFP becomes visible to every carrier in the marketplace.
    func publishRFP(rfpId: String) async throws -> PublishResult {
        struct Input: Encodable { let rfpId: String }
        return try await api.mutation(
            "rfpManager.publishRFP",
            input: Input(rfpId: rfpId)
        )
    }

    struct AwardResult: Decodable {
        let success: Bool
        let rfpId: String?
        let laneId: String?
        let carrierId: Int?
        let awardedRate: Double?
        let awardedAt: String?
    }

    func awardLane(rfpId: String,
                   laneId: String,
                   carrierId: Int,
                   awardedRate: Double? = nil) async throws -> AwardResult {
        struct Input: Encodable {
            let rfpId: String
            let laneId: String
            let carrierId: Int
            let awardedRate: Double?
        }
        return try await api.mutation(
            "rfpManager.awardLane",
            input: Input(
                rfpId: rfpId,
                laneId: laneId,
                carrierId: carrierId,
                awardedRate: awardedRate
            )
        )
    }
}

// MARK: - ShipperComplianceAPI
//
// Business verification + credit + insurance + document vault for
// the shipper. Mirrors the shipper-scope subset of
// `frontend/server/routers/compliance.ts` (`getShipperCompliance`,
// `getShipperDocuments`, `uploadDocument`). Distinct from the
// driver-side compliance namespace which surfaces violations.
//
// Naming: the iOS-side `compliance: ComplianceAPI` lazy var already
// exists for driver violations (108 violations dashboard etc); this
// new namespace mounts under `shipperCompliance` so consumers don't
// collide.
struct ShipperComplianceAPI {
    unowned let api: EusoTripAPI

    /// General-liability insurance summary block. Mirrors the server
    /// projection at `compliance.ts:2561`.
    struct GeneralLiability: Decodable, Hashable {
        let status: String       // "active" | "expiring" | "missing"
        let coverage: Double     // dollars (e.g. 1_000_000)
        let expires: String      // YYYY-MM-DD or empty
    }

    /// Compliance summary envelope.
    struct Summary: Decodable, Hashable {
        let score: Int
        let businessVerified: Bool
        let creditApproved: Bool
        let creditLimit: Double
        let availableCredit: Double
        let paymentTerms: String
        let creditRating: String
        let generalLiability: GeneralLiability
    }

    /// One row in the shipper's document vault. Server-side this
    /// joins the `documents` table filtered by `companyId` plus a
    /// derived `status` that promotes expired rows.
    struct Document: Decodable, Hashable, Identifiable {
        let id: String
        let name: String
        let type: String?
        let status: String       // "active" | "expiring" | "expired" | "pending"
        let expiresAt: String    // YYYY-MM-DD or empty
        let fileUrl: String
    }

    /// Outcome of an upload mutation. The server-side handler is
    /// currently a stub (returns success: true with a placeholder
    /// documentId); full S3 / Azure Blob wiring lands in a
    /// follow-up server firing. iOS path is correct as-is.
    struct UploadResult: Decodable, Hashable {
        let success: Bool
        let documentId: String
        let documentType: String
        let userType: String
        let status: String
        let uploadedAt: String
    }

    /// Fetch the shipper-scope compliance summary.
    func getShipperCompliance() async throws -> Summary {
        try await api.queryNoInput("compliance.getShipperCompliance")
    }

    /// Fetch the shipper's compliance document list.
    func getShipperDocuments() async throws -> [Document] {
        try await api.queryNoInput("compliance.getShipperDocuments")
    }

    /// Upload a compliance document. `userType` defaults to "shipper"
    /// per the platform vocabulary; pass another role only if the
    /// caller is on a multi-capability account.
    func uploadDocument(
        documentType: String,
        expirationDate: String? = nil,
        userType: String = "shipper",
        fileUrl: String? = nil
    ) async throws -> UploadResult {
        struct Input: Encodable {
            let documentType: String
            let expirationDate: String?
            let userType: String
            let fileUrl: String?
        }
        return try await api.mutation(
            "compliance.uploadDocument",
            input: Input(
                documentType: documentType,
                expirationDate: expirationDate,
                userType: userType,
                fileUrl: fileUrl
            )
        )
    }
}

// MARK: - ContractsAPI
//
// Volume-commitment / agreement lifecycle. Mirrors verbatim
// `frontend/server/routers/contracts.ts`. Backs the Shipper
// Contracts brick (217).
struct ContractsAPI {
    unowned let api: EusoTripAPI

    /// Aggregate stats for the contracts header strip.
    /// Mirrors `contracts.getStats`.
    struct Stats: Decodable, Hashable {
        let total: Int
        let active: Int
        let expiring: Int
        let expired: Int
        let totalValue: Double
    }

    /// Trim row used by `contracts.getAll` for the list surface.
    /// Server-side `customer` is the agreement notes column for
    /// now (no joined company name yet) — display as-is.
    struct ContractRow: Decodable, Hashable, Identifiable {
        let id: String
        let number: String?
        let customer: String?
        let type: String?
        let status: String?
        let value: Double
        let endDate: String?
    }

    /// Wider envelope returned by `contracts.list` (offset paginated).
    struct ContractListItem: Decodable, Hashable, Identifiable {
        let id: String
        let contractNumber: String?
        let type: String?
        let status: String?
        let startDate: String?
        let endDate: String?
        let baseRate: Double
    }

    struct ContractListResponse: Decodable, Hashable {
        let contracts: [ContractListItem]
        let total: Int
    }

    /// Detail envelope from `contracts.getById`.
    struct ContractDetail: Decodable, Hashable {
        let id: String
        let contractNumber: String?
        let type: String?
        let status: String?
        let terms: Terms?
        let pricing: Pricing?
        let volume: Volume?
        let notes: String?
        let createdAt: String?

        struct Terms: Decodable, Hashable {
            let startDate: String?
            let endDate: String?
            let autoRenew: Bool
        }
        struct Pricing: Decodable, Hashable {
            let rateType: String
            let baseRate: Double
            let fuelSurcharge: String
        }
        struct Volume: Decodable, Hashable {
            let commitment: Int
            let period: String
        }
    }

    // MARK: Reads

    /// `contracts.getStats` — header KPI envelope.
    func getStats() async throws -> Stats {
        try await api.queryNoInput("contracts.getStats")
    }

    /// `contracts.getAll` — full list for the contracts surface,
    /// optional search / status filter.
    func getAll(search: String? = nil, status: String? = nil) async throws -> [ContractRow] {
        struct Input: Encodable { let search: String?; let status: String? }
        return try await api.query(
            "contracts.getAll",
            input: Input(search: search, status: status)
        )
    }

    /// `contracts.getById` — full detail. Pass the contract id as a
    /// String (server parses to Int internally).
    func getContract(id: String) async throws -> ContractDetail {
        struct Input: Encodable { let id: String }
        return try await api.query(
            "contracts.getById",
            input: Input(id: id)
        )
    }
}

// MARK: - ShipperFreightClaimsAPI
//
// Shipper-as-claimant view of damage / loss / shortage / delay claims.
// Mirrors verbatim `frontend/server/routers/freightClaims.ts` (procs
// `getClaimsDashboard`, `getClaims`, `getClaimById`, `fileClaim`).
//
// Naming: the iOS-side `freightClaims: FreightClaimsAPI` lazy var
// already exists for the driver-side defendant flow (brick 099). This
// new namespace mounts under `shipperFreightClaims` so the two views
// don't collide.
struct ShipperFreightClaimsAPI {
    unowned let api: EusoTripAPI

    /// Aging breakdown of open claims by days-since-filed bucket.
    struct AgingBuckets: Decodable, Hashable {
        let under30: Int
        let days30to60: Int
        let days60to90: Int
        let over90: Int
    }

    /// Trim row used in `getClaimsDashboard.recentClaims` AND
    /// `getClaims.claims`. Server returns the same shape on both
    /// surfaces (id, claimNumber, type, status, description, amount,
    /// filedDate). The list-only response also carries severity +
    /// shipper / carrier / loadNumber stubs.
    struct ClaimRow: Decodable, Hashable, Identifiable {
        let id: String
        let claimNumber: String
        let type: String
        let status: String
        let description: String
        let amount: Double
        let filedDate: String
        let severity: String?
        let shipper: String?
        let carrier: String?
        let loadNumber: String?
    }

    struct Dashboard: Decodable, Hashable {
        let open: Int
        let pending: Int
        let resolved: Int
        let denied: Int
        let totalValue: Double
        let avgResolutionDays: Double
        let aging: AgingBuckets
        let recentClaims: [ClaimRow]
    }

    struct ClaimsListResponse: Decodable, Hashable {
        let claims: [ClaimRow]
        let total: Int
    }

    // MARK: Reads

    /// `freightClaims.getClaimsDashboard` — header KPIs + 5 most
    /// recent claims for the dashboard hero strip.
    func getClaimsDashboard() async throws -> Dashboard {
        try await api.queryNoInput("freightClaims.getClaimsDashboard")
    }

    /// `freightClaims.getClaims` — filtered list with optional
    /// search / status / type / amount / date filters. Pagination
    /// via offset.
    func getClaims(
        status: String? = nil,
        type: String? = nil,
        search: String? = nil,
        startDate: String? = nil,
        endDate: String? = nil,
        limit: Int = 30,
        offset: Int = 0
    ) async throws -> ClaimsListResponse {
        struct Input: Encodable {
            let status: String?
            let type: String?
            let search: String?
            let startDate: String?
            let endDate: String?
            let limit: Int
            let offset: Int
        }
        return try await api.query(
            "freightClaims.getClaims",
            input: Input(
                status: status,
                type: type,
                search: search,
                startDate: startDate,
                endDate: endDate,
                limit: limit,
                offset: offset
            )
        )
    }

    // MARK: Mutations

    /// `freightClaims.addClaimEvidence` — attaches a metadata-only
    /// evidence record to a filed claim. Server returns the evidence
    /// id + a server-side upload URL the iOS layer can later POST
    /// the binary blob to (see `addClaimEvidence` server signature).
    struct EvidenceRecord: Decodable, Hashable {
        let id: String
        let claimId: String
        let type: String
        let name: String
        let uploadUrl: String?
        let uploadedAt: String?
    }

    func addClaimEvidence(
        claimId: String,
        type: String,
        name: String,
        description: String? = nil,
        url: String? = nil
    ) async throws -> EvidenceRecord {
        struct Input: Encodable {
            let claimId: String
            let type: String
            let name: String
            let description: String?
            let url: String?
        }
        return try await api.mutation(
            "freightClaims.addClaimEvidence",
            input: Input(
                claimId: claimId,
                type: type,
                name: name,
                description: description,
                url: url
            )
        )
    }

    /// `freightClaims.fileDispute` — opens a formal dispute on a
    /// claim or invoice. Different surface from a claim — disputes
    /// are mediated via mediator user, claims are damage / loss /
    /// shortage records.
    struct FiledDispute: Decodable, Hashable {
        let id: String
        let disputeNumber: String
        let status: String
        let filedAt: String?
    }

    func fileDispute(
        type: String,
        invoiceNumber: String,
        amount: Double,
        description: String,
        loadId: String? = nil,
        carrierId: String? = nil
    ) async throws -> FiledDispute {
        struct Input: Encodable {
            let type: String
            let invoiceNumber: String
            let amount: Double
            let description: String
            let loadId: String?
            let carrierId: String?
        }
        return try await api.mutation(
            "freightClaims.fileDispute",
            input: Input(
                type: type,
                invoiceNumber: invoiceNumber,
                amount: amount,
                description: description,
                loadId: loadId,
                carrierId: carrierId
            )
        )
    }
}

// MARK: - ShipperRatesAPI
//
// Lane-rate intel + market average + 30-day history. Mirrors the
// shipper-relevant slice of `ratesRouter` (`getMarketRates`,
// `getFuelSurcharge`, `getTrends`).
struct ShipperRatesAPI {
    unowned let api: EusoTripAPI

    struct HistoryPoint: Decodable, Hashable, Identifiable {
        let date: String
        let rate: Double
        var id: String { date }
    }

    struct Comparison: Decodable, Hashable {
        let nationalAvg: Double
        let regionalAvg: Double
        let laneRank: Int
        let totalLanes: Int
    }

    struct MarketRateResponse: Decodable, Hashable {
        let lane: String
        let period: String
        let avgRate: Double
        let trend: String          // "up" | "down" | "stable"
        let trendPercent: Double
        let loadToTruckRatio: Double
        let volumeIndex: Int
        let history: [HistoryPoint]
        let comparison: Comparison
    }

    struct FuelSurcharge: Decodable, Hashable {
        let currentRate: Double
        let basePrice: Double
        let effectiveDate: String
        let nextUpdate: String
    }

    /// `rates.getMarketRates` — lane average + history for a chosen period.
    func getMarketRates(originState: String,
                        destState: String,
                        equipment: String? = nil,
                        period: String = "month") async throws -> MarketRateResponse {
        struct Input: Encodable {
            let originState: String
            let destState: String
            let equipment: String?
            let period: String
        }
        return try await api.query(
            "rates.getMarketRates",
            input: Input(
                originState: originState,
                destState: destState,
                equipment: equipment,
                period: period
            )
        )
    }

    /// `rates.getFuelSurcharge` — current EIA-anchored FSC.
    func getFuelSurcharge() async throws -> FuelSurcharge {
        try await api.queryNoInput("rates.getFuelSurcharge")
    }
}

// MARK: - ShipperTelemetryAPI
//
// Live carrier-position + trail for the dispatch surface. Mirrors
// the shipper-relevant slice of `telemetryRouter`.
struct ShipperTelemetryAPI {
    unowned let api: EusoTripAPI

    struct LiveLocation: Decodable, Hashable {
        let driverId: Int
        let lat: Double?
        let lng: Double?
        let speed: Double?
        let heading: Double?
        let updatedAt: String?
        let stale: Bool
    }

    struct TrailPoint: Decodable, Hashable, Identifiable {
        let lat: Double
        let lng: Double
        let recordedAt: String
        var id: String { recordedAt }
    }

    func getLiveLocation(driverId: Int) async throws -> LiveLocation {
        struct Input: Encodable { let driverId: Int }
        return try await api.query(
            "telemetry.getLiveLocation",
            input: Input(driverId: driverId)
        )
    }

    func getTrail(driverId: Int, hoursBack: Int = 4) async throws -> [TrailPoint] {
        struct Input: Encodable { let driverId: Int; let hoursBack: Int }
        return try await api.query(
            "telemetry.getTrail",
            input: Input(driverId: driverId, hoursBack: hoursBack)
        )
    }
}

// MARK: - ShipperAgreementsAPI
//
// Agreements companion to ContractsAPI. Surfaces the lighter-weight
// `agreements.list` view + `agreements.sendForReview` mutation that
// the wizard uses.
struct ShipperAgreementsAPI {
    unowned let api: EusoTripAPI

    struct Agreement: Decodable, Hashable, Identifiable {
        let id: Int
        let agreementNumber: String?
        let agreementType: String?
        let status: String?
        let effectiveDate: String?
        let expirationDate: String?
        let baseRate: String?
        let partyAUserId: Int?
        let partyBUserId: Int?
        let createdAt: String?
        let notes: String?
    }

    struct ListResponse: Decodable, Hashable {
        let agreements: [Agreement]?
        let total: Int?

        // The server may return either { agreements, total } OR a raw
        // array. Handle both shapes.
        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer(),
               let arr = try? single.decode([Agreement].self) {
                self.agreements = arr
                self.total = arr.count
                return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.agreements = try? c.decode([Agreement].self, forKey: .agreements)
            self.total      = try? c.decode(Int.self, forKey: .total)
        }
        private enum CodingKeys: String, CodingKey { case agreements, total }
    }

    func list(limit: Int = 50, offset: Int = 0) async throws -> ListResponse {
        struct Input: Encodable { let limit: Int; let offset: Int }
        return try await api.query(
            "agreements.list",
            input: Input(limit: limit, offset: offset)
        )
    }

    /// `agreements.sign` — append the caller's "Gradient Ink"
    /// signature row. The server hashes (agreementId, userId, ts) into
    /// a SHA-256 audit trail (see `agreements.ts:1115`). When both
    /// parties have signed, the row's status auto-flips to `active`.
    /// `signatureData` is a base64-encoded canvas snapshot.
    /// Mirrors the verbatim sign() return at `agreements.ts:1185` /
    /// `:1228`. `status` flips to `"active"` when both parties have
    /// signed (`fullyExecuted == true`); otherwise it stays at
    /// `"pending_signature"`.
    struct SignAck: Decodable, Hashable {
        let success: Bool?
        let status: String?
        let fullyExecuted: Bool?
    }
    func sign(agreementId: Int, signatureData: String, signatureRole: String,
              signerName: String? = nil, signerTitle: String? = nil) async throws -> SignAck {
        struct Input: Encodable {
            let agreementId: Int
            let signatureData: String
            let signatureRole: String
            let signerName: String?
            let signerTitle: String?
        }
        return try await api.mutation(
            "agreements.sign",
            input: Input(
                agreementId: agreementId,
                signatureData: signatureData,
                signatureRole: signatureRole,
                signerName: signerName,
                signerTitle: signerTitle
            )
        )
    }

    // MARK: — State-transition mutations (DRAFT → REVIEW → SENT)
    //
    // The web `agreementsRouter` exposes a discrete mutation for each
    // step of the negotiation arc; the previous iOS surface only
    // exposed `sign`, so a draft agreement had no way to advance.
    // These three wrappers close the gap and back the
    // ShipperAgreementDetailSheet action rail.

    struct StatusAck: Decodable, Hashable {
        let success: Bool?
        let status: String?
    }

    /// Move a draft agreement into pending_review.
    /// Maps to `agreements.sendForReview` (agreements.ts:1061).
    func sendForReview(agreementId: Int) async throws -> StatusAck {
        struct Input: Encodable { let id: Int }
        return try await api.mutation("agreements.sendForReview", input: Input(id: agreementId))
    }

    /// Move an agreement into pending_signature (notifies counter-party).
    /// Maps to `agreements.sendForSignature` (agreements.ts:1075).
    func sendForSignature(agreementId: Int) async throws -> StatusAck {
        struct Input: Encodable { let id: Int }
        return try await api.mutation("agreements.sendForSignature", input: Input(id: agreementId))
    }

    // MARK: — Counter-proposal (pre-signature negotiation)
    //
    // Maps to `agreements.counterPropose` / `agreements.respondToCounter`.
    // Distinct from `proposeAmendment` which targets active agreements.

    struct CounterAck: Decodable, Hashable {
        let success: Bool?
        let amendmentId: Int?
        let status: String?
    }

    /// Push back on terms before signing. At least one of the proposed*
    /// fields must be non-nil; the server rejects empty counters.
    func counterPropose(
        agreementId: Int,
        title: String = "Counter-proposal",
        message: String? = nil,
        proposedBaseRate: Double? = nil,
        proposedPaymentTermDays: Int? = nil,
        proposedEffectiveDate: String? = nil,
        proposedExpirationDate: String? = nil,
        proposedNotes: String? = nil
    ) async throws -> CounterAck {
        struct Input: Encodable {
            let agreementId: Int
            let title: String
            let message: String?
            let proposedBaseRate: Double?
            let proposedPaymentTermDays: Int?
            let proposedEffectiveDate: String?
            let proposedExpirationDate: String?
            let proposedNotes: String?
        }
        return try await api.mutation(
            "agreements.counterPropose",
            input: Input(
                agreementId: agreementId,
                title: title,
                message: message,
                proposedBaseRate: proposedBaseRate,
                proposedPaymentTermDays: proposedPaymentTermDays,
                proposedEffectiveDate: proposedEffectiveDate,
                proposedExpirationDate: proposedExpirationDate,
                proposedNotes: proposedNotes
            )
        )
    }

    struct CounterResponseAck: Decodable, Hashable {
        let success: Bool?
        let status: String?
        let agreementStatus: String?
    }

    /// Accept or reject a counter-proposal. Accepting applies the
    /// proposed changes and resets signatures so both parties re-sign.
    func respondToCounter(amendmentId: Int, action: String) async throws -> CounterResponseAck {
        struct Input: Encodable { let amendmentId: Int; let action: String }
        return try await api.mutation(
            "agreements.respondToCounter",
            input: Input(amendmentId: amendmentId, action: action)
        )
    }

    // MARK: — Amendments (counter + active-period)

    /// Row in `agreement_amendments`. Used by the detail-sheet counter
    /// card to show the latest open counter-proposal.
    struct Amendment: Decodable, Hashable, Identifiable {
        let id: Int
        let agreementId: Int
        let amendmentNumber: Int?
        let title: String?
        let description: String?
        let status: String?
        let proposedBy: Int?
        let acceptedBy: Int?
        let acceptedAt: String?
        let effectiveDate: String?
        let createdAt: String?
        let changes: [Change]?

        /// Single proposed delta. `oldValue` / `newValue` come back as
        /// heterogeneous JSON (string, number, bool, or null), so we
        /// decode them into a small JSON envelope and expose a
        /// human-readable `display` for the UI.
        struct Change: Decodable, Hashable {
            let field: String
            let oldValue: JSONScalar?
            let newValue: JSONScalar?

            var oldDisplay: String { oldValue?.display ?? "—" }
            var newDisplay: String { newValue?.display ?? "—" }
        }
    }

    /// Heterogeneous JSON scalar — string / number / bool / null.
    /// Used by amendment changes where the server stores `oldValue` /
    /// `newValue` in their original types inside a JSON column.
    enum JSONScalar: Decodable, Hashable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)
        case null

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .null; return }
            if let v = try? c.decode(Bool.self) { self = .bool(v); return }
            if let v = try? c.decode(Int.self) { self = .int(v); return }
            if let v = try? c.decode(Double.self) { self = .double(v); return }
            if let v = try? c.decode(String.self) { self = .string(v); return }
            self = .null
        }

        var display: String {
            switch self {
            case .string(let s): return s.isEmpty ? "—" : s
            case .int(let i): return "\(i)"
            case .double(let d):
                // Trim trailing .0 for integer-valued doubles.
                return d == d.rounded() ? String(format: "%.0f", d) : String(format: "%g", d)
            case .bool(let b): return b ? "Yes" : "No"
            case .null: return "—"
            }
        }
    }

    /// `agreements.listAmendments` — pull the chain for one row.
    func listAmendments(agreementId: Int) async throws -> [Amendment] {
        struct Input: Encodable { let agreementId: Int }
        return try await api.query("agreements.listAmendments", input: Input(agreementId: agreementId))
    }
}

// MARK: - SupplyChainAPI
//
// Partnership directory. Backs 224 ShipperPartnerDirectory and any
// future Catalyst/Broker partner-rolodex surface. Mirrors the
// `supplyChainRouter.getMyPartners` shape verbatim — outbound +
// inbound rows merged server-side, deduped by partnership id, with
// per-partner agreement-status enrichment.
struct SupplyChainAPI {
    unowned let api: EusoTripAPI

    /// One row in the merged partnership directory. Mirrors the union
    /// shape returned by `supplyChainRouter.getMyPartners` at
    /// `supplyChain.ts:820`. The server merges outbound (we invited)
    /// + inbound (they invited) and dedupes by `id`.
    struct Partner: Decodable, Identifiable, Hashable {
        let id: Int
        let direction: String?            // "outbound" | "inbound"
        let partnerCompanyId: Int?
        let fromRole: String?
        let toRole: String?
        let relationshipType: String?
        let status: String?               // "active" | "pending" | "declined" | …
        let notes: String?
        let invitedVia: String?
        let createdAt: String?
        let companyName: String?
        let companyDot: String?
        let companyMc: String?
        let companyCity: String?
        let companyState: String?

        /// Server emits `agreementStatus` only when an agreement
        /// exists between the caller's company and `partnerCompanyId`
        /// — `null` means "no agreement on file".
        let agreementStatus: String?
    }

    func getMyPartners(status: String? = nil, toRole: String? = nil) async throws -> [Partner] {
        struct Input: Encodable {
            let status: String?
            let toRole: String?
        }
        // Server treats `input` as optional (`.optional()`) — pass
        // an envelope with both fields omittable.
        return try await api.query(
            "supplyChain.getMyPartners",
            input: Input(status: status, toRole: toRole)
        )
    }
}

// MARK: - DocumentsAPI
//
// Documents Center. Backs 226 ShipperDocumentCenter (mirror of web
// `DocumentCenter.tsx`). Wraps the `documentsRouter` procs.
struct DocumentsAPI {
    unowned let api: EusoTripAPI

    /// One row from `documents.getAll`. Mirrors the slim projection
    /// the server emits at `documents.ts:42`. The PDF/preview URL is
    /// reachable via `/documents/file/:id` (handled outside this
    /// struct in the document-viewer surface).
    struct Document: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let category: String
        let status: String
        let uploadedAt: String
        let size: Int
    }

    /// Aggregate counts from `documents.getStats` —
    /// total/active/valid/expiring/expired.
    struct Stats: Decodable, Hashable {
        let total: Int
        let active: Int
        let valid: Int
        let expiring: Int
        let expired: Int
    }

    /// One bucket from `documents.getCategories`. Server filters out
    /// empty buckets so a count of 0 never shows up in the array.
    struct Category: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let count: Int
    }

    /// Acknowledge envelope from `documents.delete`.
    struct DeleteAck: Decodable, Hashable {
        let success: Bool
        let deletedId: String?
    }

    func getAll(search: String? = nil, category: String? = nil) async throws -> [Document] {
        struct Input: Encodable {
            let search: String?
            let category: String?
        }
        return try await api.query(
            "documents.getAll",
            input: Input(search: search, category: category)
        )
    }

    func getStats() async throws -> Stats {
        try await api.queryNoInput("documents.getStats")
    }

    func getCategories() async throws -> [Category] {
        try await api.queryNoInput("documents.getCategories")
    }

    func delete(id: String) async throws -> DeleteAck {
        struct Input: Encodable { let id: String }
        return try await api.mutation("documents.delete", input: Input(id: id))
    }
}

// MARK: - ShipperSettlementsAPI
//
// Settlement detail + approve + dispute. Backs 227
// ShipperSettlementDetail (mirror of web `SettlementDetails.tsx`
// shipper-action surface). Sits alongside `EarningsAPI` (which is
// driver-scope earnings reporting) without conflicting — these are
// the SHIPPER's mutations on a settlement they're paying out.
struct ShipperSettlementsAPI {
    unowned let api: EusoTripAPI

    /// One settlement detail from `earnings.getSettlementById`.
    /// Mirrors the verbatim envelope at `earnings.ts:276` — every
    /// field is optional because the server returns an "empty"
    /// scaffold when the settlement can't be resolved.
    struct SettlementDetail: Decodable, Hashable {
        let id: String
        let settlementNumber: String?
        let period: String?
        let periodStart: String?
        let periodEnd: String?
        let driverId: String?
        let driverName: String?
        let grossPay: Double?
        let grossRevenue: Double?
        let driverPay: Double?
        let payRate: Double?
        let payType: String?
        let paymentMethod: String?
        let deductions: Double?
        let totalDeductions: Double?
        let netPay: Double?
        let status: String?
        let paidDate: String?
        let breakdown: Breakdown?
        /// Phase 18 closure: backend earnings.getSettlementById now
        /// returns the underlying `loadId` so the iOS shipper-side
        /// rating prompt can derive the load anchor required by
        /// ratings.submit (one-rating-per-from/to/load constraint).
        /// Optional — older server builds may still omit the field.
        let loadId: Int?

        struct Breakdown: Decodable, Hashable {
            let lineHaul: Double?
            let fuelSurcharge: Double?
            let accessorials: Double?
        }
    }

    /// Acknowledge envelope from `earnings.approveSettlement`.
    struct ApproveAck: Decodable, Hashable {
        let success: Bool?
        let settlementId: String?
        let approvedAt: String?
    }

    /// Acknowledge envelope from `earnings.disputeSettlement`.
    struct DisputeAck: Decodable, Hashable {
        let success: Bool?
        let settlementId: String?
        let disputeId: String?
        let status: String?
    }

    func getDetail(settlementId: String) async throws -> SettlementDetail {
        struct Input: Encodable { let settlementId: String }
        return try await api.query(
            "earnings.getSettlementById",
            input: Input(settlementId: settlementId)
        )
    }

    func approve(settlementId: String) async throws -> ApproveAck {
        struct Input: Encodable { let settlementId: String }
        return try await api.mutation(
            "earnings.approveSettlement",
            input: Input(settlementId: settlementId)
        )
    }

    func dispute(settlementId: String, reason: String, evidence: String? = nil) async throws -> DisputeAck {
        struct Input: Encodable {
            let settlementId: String
            let reason: String
            let evidence: String?
        }
        return try await api.mutation(
            "earnings.disputeSettlement",
            input: Input(settlementId: settlementId, reason: reason, evidence: evidence)
        )
    }
}

// MARK: - AllocationsAPI
//
// Daily nomination + fulfillment tracker. Backs 230 ShipperAllocations
// (mirror of web `allocations/AllocationDashboard.tsx`). Mirrors
// `frontend/server/routers/allocationTracker.ts`. Used heavily by
// petroleum / refined-products shippers that need the nominate-load-
// deliver loop tracked by-the-barrel by-the-day.
struct AllocationsAPI {
    unowned let api: EusoTripAPI

    /// One row in the contracts list. Mirrors the verbatim
    /// `allocationContracts` projection from the server.
    struct Contract: Decodable, Identifiable, Hashable {
        let id: Int
        let shipperId: Int?
        let contractName: String?
        let buyerName: String?
        let originTerminalId: Int?
        let destinationTerminalId: Int?
        let product: String?
        let cargoType: String?
        let unit: String?
        let dailyNominationBbl: String?
        let effectiveDate: String?
        let expirationDate: String?
        let ratePerBbl: String?
        let status: String?
    }

    struct ContractsResponse: Decodable {
        let contracts: [Contract]
    }

    /// One row in the per-contract-per-date tracking view.
    struct DailyContractRow: Decodable, Identifiable, Hashable {
        let contractId: Int
        let contractName: String?
        let buyerName: String?
        let product: String?
        let originTerminalId: Int?
        let destinationTerminalId: Int?
        let ratePerBbl: String?
        let nominatedBbl: Double
        let loadedBbl: Double
        let deliveredBbl: Double
        let remainingBbl: Double
        let loadsNeeded: Int
        let loadsCreated: Int
        let loadsCompleted: Int
        let status: String?

        var id: Int { contractId }
    }

    /// Aggregated bar at the top of the daily view. Mirrors the
    /// `summaryBar` projection at `allocationTracker.ts:177`.
    struct SummaryBar: Decodable, Hashable {
        let totalNominated: Double
        let totalLoaded: Double
        let totalDelivered: Double
        let fulfillmentPercent: Int
    }

    struct DailyDashboard: Decodable {
        let date: String
        let summaryBar: SummaryBar
        let contracts: [DailyContractRow]
    }

    func getContracts(status: String? = nil) async throws -> ContractsResponse {
        struct Input: Encodable {
            let status: String?
        }
        return try await api.query(
            "allocationTracker.getContracts",
            input: Input(status: status)
        )
    }

    func getDailyDashboard(date: String? = nil) async throws -> DailyDashboard {
        struct Input: Encodable { let date: String? }
        return try await api.query(
            "allocationTracker.getDailyDashboard",
            input: Input(date: date)
        )
    }

    struct CreatedContract: Decodable {
        let id: Int?
        let contractName: String?
        let status: String?
    }

    func createContract(
        shipperId: Int,
        contractName: String,
        buyerName: String?,
        originTerminalId: Int,
        destinationTerminalId: Int,
        product: String,
        cargoType: String = "petroleum",
        unit: String = "bbl",
        dailyNominationBbl: Double,
        effectiveDate: String,
        expirationDate: String,
        ratePerBbl: Double?
    ) async throws -> CreatedContract {
        struct Input: Encodable {
            let shipperId: Int
            let contractName: String
            let buyerName: String?
            let originTerminalId: Int
            let destinationTerminalId: Int
            let product: String
            let cargoType: String
            let unit: String
            let dailyNominationBbl: Double
            let effectiveDate: String
            let expirationDate: String
            let ratePerBbl: Double?
        }
        return try await api.mutation(
            "allocationTracker.createContract",
            input: Input(
                shipperId: shipperId,
                contractName: contractName,
                buyerName: buyerName,
                originTerminalId: originTerminalId,
                destinationTerminalId: destinationTerminalId,
                product: product,
                cargoType: cargoType,
                unit: unit,
                dailyNominationBbl: dailyNominationBbl,
                effectiveDate: effectiveDate,
                expirationDate: expirationDate,
                ratePerBbl: ratePerBbl
            )
        )
    }
}

// MARK: - LoadBoardAPI
//
// Public loadboard search + book. Mirrors `loadBoardRouter.search`
// + `getById` + `bookLoad`. Different envelope from `loadsRouter`
// — surfaces market stats + lane-contract enrichment per row so
// drivers see "Lane contract · $2.85/mi" inline on the card without
// an N+1 lookup. Backs 108 MeLoadBoard (driver browse) + future
// 230 ShipperLoadBoardSearch (shipper market intel).
struct LoadBoardAPI {
    unowned let api: EusoTripAPI

    /// One row in the search result projection. Mirrors the verbatim
    /// `loadBoard.ts:754` server projection.
    struct SearchRow: Decodable, Identifiable, Hashable {
        let id: String
        let loadNumber: String?
        let status: String?
        let origin: CityState
        let destination: CityState
        let rate: Double
        let distance: Double
        let weight: Double?
        let weightUnit: String?
        let cargoType: String?
        let equipmentType: String?
        let hazmat: Bool?
        let hazmatClass: String?
        let commodityName: String?
        let unNumber: String?
        let packingGroup: String?
        let properShippingName: String?
        let pickupDate: String?
        let createdAt: String?
        let postedAt: String?
        let isLaneContract: Bool?
        let laneContractRate: Double?
        let laneContractRateType: String?
        let laneContractMiles: Double?

        // ─── 2026-05-17 · Multi-modal payload on every search row ───
        // Powers LoadModeBadge in every driver / catalyst / broker
        // load row. Optional on the wire so older deploys decode.
        let transportMode: String?
        let multiVehicleCount: Int?
        let permitType: String?
        let rateUnit: String?
        let worldscalePct: String?

        struct CityState: Decodable, Hashable {
            let city: String?
            let state: String?
            var display: String {
                let c = (city ?? "").trimmingCharacters(in: .whitespaces)
                let s = (state ?? "").trimmingCharacters(in: .whitespaces)
                if !c.isEmpty && !s.isEmpty { return "\(c), \(s)" }
                if !c.isEmpty { return c }
                return s
            }
        }
    }

    struct MarketStats: Decodable, Hashable {
        let avgRate: Double
        let totalLoads: Int
        let loadToTruckRatio: Double
    }

    struct SearchResponse: Decodable {
        let loads: [SearchRow]
        let total: Int
        let marketStats: MarketStats
    }

    /// `loadBoard.search` — filtered browse. Origin/destination radius
    /// defaults to 50 mi server-side. Sort options:
    /// `rate` / `distance` / `pickup_date` / `posted_date` (default).
    func search(
        originState: String? = nil,
        originCity: String? = nil,
        originRadius: Int = 50,
        destState: String? = nil,
        destCity: String? = nil,
        destRadius: Int = 50,
        equipmentType: String? = nil,
        pickupDateStart: String? = nil,
        pickupDateEnd: String? = nil,
        minRate: Double? = nil,
        maxWeight: Double? = nil,
        hazmat: Bool? = nil,
        hazmatClass: String? = nil,
        unNumber: String? = nil,
        sortBy: String = "posted_date",
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> SearchResponse {
        struct Geo: Encodable { let city: String?; let state: String; let radius: Int }
        struct Input: Encodable {
            let origin: Geo?
            let destination: Geo?
            let equipmentType: String?
            let pickupDateStart: String?
            let pickupDateEnd: String?
            let minRate: Double?
            let maxWeight: Double?
            let hazmat: Bool?
            let hazmatClass: String?
            let unNumber: String?
            let sortBy: String
            let limit: Int
            let offset: Int
        }
        let originGeo: Geo? = originState.map { Geo(city: originCity, state: $0, radius: originRadius) }
        let destGeo:   Geo? = destState.map   { Geo(city: destCity,   state: $0, radius: destRadius) }
        return try await api.query(
            "loadBoard.search",
            input: Input(
                origin: originGeo,
                destination: destGeo,
                equipmentType: equipmentType,
                pickupDateStart: pickupDateStart,
                pickupDateEnd: pickupDateEnd,
                minRate: minRate,
                maxWeight: maxWeight,
                hazmat: hazmat,
                hazmatClass: hazmatClass,
                unNumber: unNumber,
                sortBy: sortBy,
                limit: limit,
                offset: offset
            )
        )
    }
}

// MARK: - bol.generateBOLFromLoad ON EusoTicketAPI
//
// Bridge proc — generates a BOL from an existing load. Lives on the
// `bol` router (NOT eusoTicket), but iOS callers expect a single
// EusoTicket-namespaced surface. Re-exported here as a thin
// passthrough for ergonomic call-site grouping.
extension EusoTicketAPI {
    struct GeneratedBOL: Decodable {
        let bolNumber: String?
        let loadId: Int?
        let loadNumber: String?
        let type: String?
        let cargoType: String?
        let status: String?
        let createdAt: String?
    }

    func generateBOLFromLoad(loadId: Int) async throws -> GeneratedBOL {
        struct Input: Encodable { let loadId: Int }
        return try await api.mutation("bol.generateBOLFromLoad", input: Input(loadId: loadId))
    }
}

// MARK: - capabilitiesRouter (hardware capability registry)
//
// Mirrors `frontend/server/routers/capabilities.ts` (built in the
// follow-up backend commit). Per-tenant self-declaration of what
// hardware each terminal / carrier / piece of equipment has, so the
// iOS app can light up the matching feature path (NearbyInteraction
// UWB anchors, partner camera NVR streams, dash-cam vendor passes,
// trailer dome cams, ARKit door markers, geofence layouts) versus
// rendering it disabled.
//
// Doctrine refs:
// - `feedback_no_ceilings` — never remove a Figma affordance because
//   backend isn't built; let the founder's tenant declare capability
//   and the affordance lights up. Until declared, the affordance
//   renders as "Pair hardware" (greyed) — never inert.
// - `reference_nearby_interaction` — UWB anchor accessory data lives
//   on `TerminalCapabilities.uwbAnchors[doorNumber]`.
//
// 102nd firing.

struct CapabilitiesAPI {
    unowned let api: EusoTripAPI

    // MARK: - Terminal capabilities

    /// One UWB anchor. `accessoryConfigData` is the manufacturer-
    /// signed blob the iOS NI session passes to
    /// `NINearbyAccessoryConfiguration(accessoryData:bluetoothPeerIdentifier:)`.
    /// Servers store it base64-encoded.
    struct UwbAnchor: Codable, Hashable {
        let doorNumber: String
        let vendor: String                 // "qorvo" | "nxp" | "applefindmy"
        let accessoryConfigData: String    // base64 blob
        let bluetoothPeerIdentifier: String?
    }

    /// One partner camera-feed source. iOS opens `streamUrl` via
    /// WebRTC (the existing WebRTC.framework or Agora SDK once it
    /// lands). `signalingToken` is a short-TTL JWT minted server-side
    /// when iOS calls `media.startCamSession(doorNumber)`.
    struct CameraFeed: Codable, Hashable {
        let doorNumber: String
        let vendor: String                 // "genetec" | "avigilon" | "milestone" | "rtsp"
        let label: String?
        let streamUrl: String?             // signaling URL or RTSP fallback
        let signalingToken: String?
    }

    /// ARKit visual-fiducial marker per dock door. Driver phone scans
    /// the printed QR / AprilTag, iOS resolves the marker GUID to
    /// `doorNumber + offsetX + offsetY` so the AR overlay can place
    /// the back-in centerline correctly.
    struct DoorMarker: Codable, Hashable {
        let doorNumber: String
        let markerId: String
        let offsetX: Double
        let offsetY: Double
    }

    /// Capability envelope for a single terminal. Every list defaults
    /// empty so the iOS UI's capability gating reads "nothing
    /// declared yet" rather than crashing on missing fields.
    struct TerminalCapabilities: Codable, Hashable {
        let terminalId: Int
        var uwbAnchors: [UwbAnchor]
        var cameraFeeds: [CameraFeed]
        var doorMarkers: [DoorMarker]
        var yardLayoutGeoJson: String?     // GeoJSON polygon string

        static var empty: TerminalCapabilities {
            TerminalCapabilities(
                terminalId: 0,
                uwbAnchors: [],
                cameraFeeds: [],
                doorMarkers: [],
                yardLayoutGeoJson: nil
            )
        }

        /// Convenience: does any UWB anchor exist for `doorNumber`?
        func hasUwbAnchor(doorNumber: String) -> Bool {
            uwbAnchors.contains { $0.doorNumber == doorNumber }
        }

        /// Convenience: does a camera feed exist for `doorNumber`?
        func hasCameraFeed(doorNumber: String) -> Bool {
            cameraFeeds.contains { $0.doorNumber == doorNumber }
        }

        /// Convenience: does an ARKit marker exist for `doorNumber`?
        func hasDoorMarker(doorNumber: String) -> Bool {
            doorMarkers.contains { $0.doorNumber == doorNumber }
        }

        /// Convenience: does the terminal admin uploaded a yard layout
        /// GeoJSON polygon (Option B in the yardmap options menu)?
        var hasYardLayout: Bool {
            (yardLayoutGeoJson?.isEmpty == false)
        }
    }

    /// `capabilities.getTerminal` — fetch a single terminal's
    /// capability envelope. Returns `.empty` (with the requested
    /// terminalId) when no row exists yet so callers can render
    /// "no hardware declared" UI uniformly.
    func getTerminal(terminalId: Int) async throws -> TerminalCapabilities {
        struct Input: Encodable { let terminalId: Int }
        do {
            return try await api.query(
                "capabilities.getTerminal",
                input: Input(terminalId: terminalId)
            )
        } catch {
            // Backend not yet shipped → render-empty fallback so the
            // capability-aware UI gates everything to "Pair hardware"
            // without surfacing an error toast. Real production
            // returns the row + an empty-shaped envelope when no
            // declaration exists yet.
            var empty = TerminalCapabilities.empty
            empty = TerminalCapabilities(
                terminalId: terminalId,
                uwbAnchors: empty.uwbAnchors,
                cameraFeeds: empty.cameraFeeds,
                doorMarkers: empty.doorMarkers,
                yardLayoutGeoJson: empty.yardLayoutGeoJson
            )
            return empty
        }
    }

    /// `capabilities.setTerminal` — terminal manager / admin /
    /// shipper-of-record persists the declared capabilities.
    /// RBAC-gated server-side to those three roles.
    @discardableResult
    func setTerminal(_ caps: TerminalCapabilities) async throws -> TerminalCapabilities {
        try await api.mutation("capabilities.setTerminal", input: caps)
    }

    // MARK: - Carrier capabilities

    /// The carrier's fleet-wide dash-cam vendor (Samsara, Motive,
    /// Garmin, Cipia, none). When set, the iOS dock-cam picker can
    /// route the "Dash cam" source to the vendor's live-stream URL.
    struct DashCamVendor: Codable, Hashable {
        let vendor: String                 // "samsara" | "motive" | "garmin" | "cipia" | "none"
        let credentialsToken: String?      // OAuth bearer token (server-only field; iOS reads boolean below)
        let configured: Bool               // true once the vendor handshake completed
    }

    struct CarrierCapabilities: Codable, Hashable {
        let carrierId: Int
        var dashCam: DashCamVendor

        static var empty: CarrierCapabilities {
            CarrierCapabilities(
                carrierId: 0,
                dashCam: DashCamVendor(
                    vendor: "none",
                    credentialsToken: nil,
                    configured: false
                )
            )
        }
    }

    /// `capabilities.getMyCarrier` — driver / dispatcher /
    /// admin-of-carrier reads their fleet's declared dash-cam
    /// vendor. Empty envelope when no row exists.
    func getMyCarrier() async throws -> CarrierCapabilities {
        do {
            return try await api.queryNoInput("capabilities.getMyCarrier")
        } catch {
            return CarrierCapabilities.empty
        }
    }

    @discardableResult
    func setMyCarrier(_ caps: CarrierCapabilities) async throws -> CarrierCapabilities {
        try await api.mutation("capabilities.setMyCarrier", input: caps)
    }

    // MARK: - Trailer / equipment capabilities

    /// Per-trailer dome cam + reefer monitoring vendor.
    struct TrailerCapabilities: Codable, Hashable {
        let trailerId: String
        var domeCamVendor: String          // "sensata" | "orbcomm" | "spireon" | "none"
        var domeCamStreamUrl: String?
        var reeferMonitorVendor: String?

        static func empty(trailerId: String) -> TrailerCapabilities {
            TrailerCapabilities(
                trailerId: trailerId,
                domeCamVendor: "none",
                domeCamStreamUrl: nil,
                reeferMonitorVendor: nil
            )
        }
    }

    func getTrailer(trailerId: String) async throws -> TrailerCapabilities {
        struct Input: Encodable { let trailerId: String }
        do {
            return try await api.query(
                "capabilities.getTrailer",
                input: Input(trailerId: trailerId)
            )
        } catch {
            return TrailerCapabilities.empty(trailerId: trailerId)
        }
    }

    @discardableResult
    func setTrailer(_ caps: TrailerCapabilities) async throws -> TrailerCapabilities {
        try await api.mutation("capabilities.setTrailer", input: caps)
    }

    // MARK: - Vendor OAuth flows

    /// Per-vendor authorize URL + opaque CSRF state. iOS opens
    /// `authorizeUrl` in `SFSafariViewController`; the vendor
    /// redirects back to `eusotrip://oauth/callback/<vendor>?code=…&state=…`
    /// which AppRoot's URL handler captures and forwards to
    /// `exchangeOAuthCode`. Backend mints the state token + caches
    /// it under the user id so the callback verifies as same-user.
    struct OAuthAuthorize: Decodable, Hashable {
        let authorizeUrl: String
        let state: String
        let vendor: String
    }

    /// `capabilities.startVendorOAuth` — request the authorize URL.
    /// Vendors today: "samsara" | "motive" | "garmin" | "cipia"
    /// (dash cam) | "sensata" | "orbcomm" | "spireon" (dome cam).
    func startVendorOAuth(vendor: String) async throws -> OAuthAuthorize {
        struct Input: Encodable { let vendor: String }
        return try await api.mutation(
            "capabilities.startVendorOAuth",
            input: Input(vendor: vendor)
        )
    }

    struct OAuthExchangeAck: Decodable, Hashable {
        let success: Bool
        let vendor: String
        let configured: Bool
    }

    /// `capabilities.exchangeOAuthCode` — backend trades the
    /// authorization code for the vendor's long-lived token, stores
    /// the ciphertext on `carrierCapabilities` / `trailerCapabilities`,
    /// flips the matching `configured` boolean, returns the iOS-side
    /// truth value (no token leakage). On success the iOS UI reloads
    /// the capability envelope and the matching dock-cam picker row
    /// flips from "Pair" to enabled.
    func exchangeOAuthCode(vendor: String, code: String, state: String) async throws -> OAuthExchangeAck {
        struct Input: Encodable {
            let vendor: String
            let code: String
            let state: String
        }
        return try await api.mutation(
            "capabilities.exchangeOAuthCode",
            input: Input(vendor: vendor, code: code, state: state)
        )
    }
}

// MARK: - EusoNISession (NearbyInteraction UWB session)
//
// Cm-level distance + direction service powering yard navigation,
// dock-door alignment, and escort proximity. Wraps `NISession` so
// SwiftUI surfaces just observe published @Published state.
//
// Usage shapes:
//   - Phone ↔ accessory  (UWB anchor at a dock door):
//       startAccessory(configData: anchor.accessoryConfigData,
//                      btIdentifier: anchor.bluetoothPeerIdentifier)
//   - Phone ↔ phone      (driver ↔ escort):
//       Exchange tokens out-of-band, then `startPeer(token:)`.
//
// Lifecycle: foreground only; sessions auto-pause when the app
// backgrounds (NI framework constraint). The host SwiftUI view
// should call `.task { uwb.startAccessory(...) }` on `.onAppear`
// and `uwb.stop()` on `.onDisappear` to keep the radio off when
// the screen isn't visible.
//
// Doctrine: `reference_nearby_interaction` memory holds the design
// notes + EusoTrip use-case map. The class published here is the
// "drop-in skeleton" referenced there.

import NearbyInteraction
import simd

@MainActor
final class EusoNISession: NSObject, ObservableObject, NISessionDelegate {
    /// Published state surfaces drive the SwiftUI overlay. Distance
    /// is meters (nil when out of range or LOS lost). Direction is
    /// the phone-frame unit vector (nil when too close to resolve).
    @Published var distance: Float? = nil
    @Published var direction: simd_float3? = nil
    @Published var lastUpdate: Date? = nil
    @Published var status: Status = .idle
    @Published var lostLineOfSight: Bool = false

    enum Status: Equatable {
        case idle
        case unsupported(String)
        case ranging
        case suspended
        case failed(String)
    }

    private let session = NISession()

    /// Static availability check — is NearbyInteraction on this
    /// device. iOS 16+ exposes `deviceCapabilities`; on iOS 14/15 we
    /// inspect `NISession.isSupported` (deprecated but still
    /// available). Returns false on simulator.
    static var isSupported: Bool {
        if #available(iOS 16.0, *) {
            return NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
        } else {
            return NISession.isSupported
        }
    }

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = .main
    }

    // MARK: - Phone ↔ accessory (UWB anchor at dock door)

    /// Start ranging to a fixed UWB anchor (a Qorvo / NXP / Apple
    /// Find My Network accessory installed at a dock door). The
    /// `configData` blob comes from the manufacturer's pairing
    /// flow — EusoTrip stores it on
    /// `terminalCapabilities.uwbAnchors[doorNumber].accessoryConfigData`.
    func startAccessory(configData: Data, btIdentifier: UUID? = nil) {
        guard Self.isSupported else {
            status = .unsupported("NearbyInteraction not available on this device.")
            return
        }
        do {
            let cfg: NINearbyAccessoryConfiguration
            if #available(iOS 16.0, *), let bt = btIdentifier {
                cfg = try NINearbyAccessoryConfiguration(
                    accessoryData: configData,
                    bluetoothPeerIdentifier: bt
                )
            } else {
                cfg = try NINearbyAccessoryConfiguration(data: configData)
            }
            session.run(cfg)
            status = .ranging
        } catch {
            status = .failed("Couldn't start UWB anchor session: \(error.localizedDescription)")
        }
    }

    // MARK: - Phone ↔ phone (driver ↔ escort, hand-off pairing, etc.)

    /// Exchanged with the peer over BLE / Multipeer / your own
    /// websocket so they can run a peer config against you.
    var localToken: NIDiscoveryToken? { session.discoveryToken }

    /// Start ranging to a paired phone. `peerToken` is the
    /// `NIDiscoveryToken` the peer published over the chosen
    /// out-of-band channel.
    func startPeer(token peerToken: NIDiscoveryToken) {
        guard Self.isSupported else {
            status = .unsupported("NearbyInteraction not available on this device.")
            return
        }
        let cfg = NINearbyPeerConfiguration(peerToken: peerToken)
        session.run(cfg)
        status = .ranging
    }

    func stop() {
        session.invalidate()
        distance = nil
        direction = nil
        lostLineOfSight = false
        status = .idle
    }

    // MARK: - NISessionDelegate
    //
    // Each method is `nonisolated` so Swift 6 strict-concurrency
    // accepts the protocol conformance crossing the @MainActor
    // boundary. Per-method we snapshot the inputs on the framework's
    // delegate queue, then hop to the main actor via
    // `Task { @MainActor in self.<state> = ... }` so the
    // `@Published` property updates fire on the right context.

    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        // Single-peer model — yardmap + back-in alignment + escort
        // pairing all bind to one ranging target at a time. Multi-
        // peer use-cases (yard hostler tracking many trailers)
        // would split state into a per-token dictionary.
        guard let target = nearbyObjects.first else { return }
        let dist = target.distance
        let dir = target.direction
        let lost = (target.distance == nil && target.direction == nil)
        Task { @MainActor in
            self.distance = dist
            self.direction = dir
            self.lastUpdate = Date()
            self.lostLineOfSight = lost
        }
    }

    nonisolated func session(
        _ session: NISession,
        didRemove nearbyObjects: [NINearbyObject],
        reason: NINearbyObject.RemovalReason
    ) {
        Task { @MainActor in
            switch reason {
            case .timeout:
                self.lostLineOfSight = true
            case .peerEnded:
                self.status = .idle
                self.distance = nil
                self.direction = nil
            @unknown default:
                break
            }
        }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {
        Task { @MainActor in
            self.status = .suspended
        }
    }

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        // The framework expects us to re-run the previous config
        // after suspension — but we don't retain it here. Caller
        // must restart via `start*(...)` after observing this state.
        Task { @MainActor in
            self.status = .idle
        }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        let msg = error.localizedDescription
        Task { @MainActor in
            self.status = .failed(msg)
        }
    }
}

// MARK: - mediaRouter (live camera streams)
//
// Mirrors `frontend/server/routers/media.ts`. The router doesn't store
// stream URLs directly — it mints short-TTL signed signaling URLs on
// demand so the iOS client can render a partner NVR or dash-cam feed
// without ever holding the credentials. iOS embeds the signaling URL
// inside a WKWebView; the host page does the WebRTC handshake against
// the partner's stream API and exchanges the SDP/ICE.
//
// Three sources today (all behind the same `startCamSession` shape so
// the iOS picker dispatches them uniformly):
//   • Terminal NVR    — partner publisher (Genetec / Avigilon /
//                        Milestone / RTSP). Source = "terminal-nvr".
//   • Driver dash-cam — fleet vendor (Samsara / Motive / Garmin /
//                        Cipia). Source = "dash-cam".
//   • Trailer dome cam — equipment vendor (Sensata / ORBCOMM /
//                        Spireon). Source = "trailer-dome-cam".
//
// HLS fallback: `streamUrl` field surfaces an .m3u8 URL when the
// partner doesn't speak WebRTC; iOS renders that via AVPlayer
// instead of the WKWebView signaling page. AVPlayer adds ~5-10s of
// latency so WebRTC is the preferred path.

struct MediaAPI {
    unowned let api: EusoTripAPI

    enum Source: String, Codable {
        case terminalNvr     = "terminal-nvr"
        case dashCam         = "dash-cam"
        case trailerDomeCam  = "trailer-dome-cam"
    }

    enum Transport: String, Codable {
        case webrtc
        case hls
    }

    /// Server response for `media.startCamSession`. Either
    /// `signalingUrl` (WebRTC handshake page hosted by EusoTrip's
    /// media gateway) or `streamUrl` (HLS .m3u8 fallback) will be
    /// non-nil — never both, never neither. `transport` mirrors
    /// which one the partner chose.
    struct CamSessionEnvelope: Decodable, Hashable {
        let sessionId: String
        let transport: Transport
        let signalingUrl: String?
        let streamUrl: String?
        let signalingToken: String?    // JWT, embedded in iframe URL
        let expiresAt: String          // ISO8601, ~5min TTL
        let label: String?
    }

    /// Request a fresh stream session. iOS calls this on dock-cam
    /// picker tap. Backend RBAC-gates the call:
    ///   • terminal-nvr   → driver must be assigned to a load
    ///                       bound for that terminal
    ///   • dash-cam       → driver must own/be assigned to the
    ///                       carrier the dash-cam belongs to
    ///   • trailer-dome-cam → driver must be assigned to a load
    ///                       carrying that trailer
    func startCamSession(
        source: Source,
        terminalId: Int? = nil,
        doorNumber: String? = nil,
        carrierId: Int? = nil,
        trailerId: String? = nil
    ) async throws -> CamSessionEnvelope {
        struct Input: Encodable {
            let source: String
            let terminalId: Int?
            let doorNumber: String?
            let carrierId: Int?
            let trailerId: String?
        }
        return try await api.mutation(
            "media.startCamSession",
            input: Input(
                source: source.rawValue,
                terminalId: terminalId,
                doorNumber: doorNumber,
                carrierId: carrierId,
                trailerId: trailerId
            )
        )
    }

    /// Tear down a session early (on sheet dismiss / picker cancel).
    /// Server invalidates the JWT immediately so the partner stream
    /// drops within a few hundred ms — saves quota / billing.
    @discardableResult
    func endCamSession(sessionId: String) async throws -> SimpleResult {
        struct Input: Encodable { let sessionId: String }
        return try await api.mutation(
            "media.endCamSession",
            input: Input(sessionId: sessionId)
        )
    }

    struct SimpleResult: Decodable {
        let success: Bool
    }
}

// =====================================================================
// ReportsAPI — Shipper Reports (207_ShipperReports.swift) wired to real
// server export procedures. Each method returns the rendered file body
// + filename + MIME so the screen can write a tmp file and present
// `UIActivityViewController` (system Share sheet → Save to Files,
// AirDrop, Mail, Messages, etc).
// 2026-05-05 — replaces the prior `openURL("https://app.eusotrip.com/
// shipper/reports/export/...")` web-continuation, which 404'd because
// no `/shipper/reports/export/` route existed. Founder no-stubs
// doctrine: "wire production app, no skeletons no stubs."
// =====================================================================

struct ReportsAPI {
    let api: EusoTripAPI

    /// Server response shape for every export procedure. iOS writes
    /// `body` to a temp file named `filename` and presents the Share
    /// sheet so the user can save / mail / AirDrop the export.
    struct ExportFile: Decodable, Hashable {
        let filename: String
        let mime: String
        let body: String
    }

    /// CSV: spend rolled up per origin → destination lane, for every
    /// load attributed to the signed-in shipper across the union of
    /// possible shipperId resolutions (email-resolved DB id, raw auth
    /// id, companyId, teammates).
    func exportSpendByLane() async throws -> ExportFile {
        try await api.queryNoInput("reports.exportSpendByLane")
    }

    /// CSV: gross / settled / outstanding payable per catalyst.
    func exportCatalystPayable() async throws -> ExportFile {
        try await api.queryNoInput("reports.exportCatalystPayable")
    }

    /// CSV: full hazmat audit log (loads where cargoType == "hazmat")
    /// — UN number, hazmat class, lane, status, rate.
    func exportHazmatAudit() async throws -> ExportFile {
        try await api.queryNoInput("reports.exportHazmatAudit")
    }

    /// CSV: GLEC v3.0 CO₂ statement — distance × weight × emissions
    /// factor per load. Ready to drop into Scope-3 reporting.
    func exportCO2Statement() async throws -> ExportFile {
        try await api.queryNoInput("reports.exportCO2Statement")
    }

    /// CSV: run a saved-report cell. Verb selects how the server
    /// shapes the rows (Q1 spend rollup, catalyst scorecard,
    /// detention & accessorial, hazmat exposure log).
    struct RunSavedInput: Encodable, Hashable {
        let verb: String
        let title: String
    }
    func runSavedReport(verb: String, title: String) async throws -> ExportFile {
        try await api.mutation(
            "reports.runSavedReport",
            input: RunSavedInput(verb: verb, title: title)
        )
    }

    /// CSV: custom builder compose. Picks a metric and a group-by
    /// dimension and ships the rolled-up rows.
    struct ComposeInput: Encodable, Hashable {
        let metric: String   // "spend" | "loads" | "miles"
        let groupBy: String  // "lane" | "equipment" | "catalyst"
    }
    func composeCustom(metric: String, groupBy: String) async throws -> ExportFile {
        try await api.mutation(
            "reports.composeCustom",
            input: ComposeInput(metric: metric, groupBy: groupBy)
        )
    }
}

// MARK: - CredentialScannerAPI
//
// Backs the registration / onboarding wizard's "Scan a document"
// affordance. Posts a base64 image / PDF to the server's
// `credentialScannerRouter` which runs Gemini Vision against a
// type-specific prompt and returns a normalized envelope the
// wizard pre-fills its form with.
//
// Supports every credential the platform accepts across all three
// verticals (truck / rail / vessel) and all three countries (US /
// CA / MX) — see `credentialScannerRouter.CredentialTypes`.

struct CredentialScannerAPI {
    unowned let api: EusoTripAPI

    /// Heterogeneous JSON scalar (string / int / double / bool /
    /// null / string array) — Gemini returns each field's `value`
    /// in its native JSON type so the wizard can preserve the
    /// distinction between e.g. "1000000" (string) and 1000000
    /// (number).
    enum ScalarValue: Decodable, Hashable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)
        case stringArray([String])
        case null

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .null; return }
            if let arr = try? c.decode([String].self) { self = .stringArray(arr); return }
            if let v = try? c.decode(Bool.self) { self = .bool(v); return }
            if let v = try? c.decode(Int.self) { self = .int(v); return }
            if let v = try? c.decode(Double.self) { self = .double(v); return }
            if let v = try? c.decode(String.self) { self = .string(v); return }
            self = .null
        }

        var stringValue: String? {
            switch self {
            case .string(let s): return s
            case .int(let i): return "\(i)"
            case .double(let d): return d == d.rounded() ? String(format: "%.0f", d) : String(format: "%g", d)
            case .bool(let b): return b ? "true" : "false"
            case .stringArray(let arr): return arr.joined(separator: ", ")
            case .null: return nil
            }
        }

        var arrayValue: [String]? {
            if case .stringArray(let arr) = self { return arr }
            return nil
        }
    }

    /// One extracted field. `confidence` is 0..1; UI typically
    /// highlights anything under 0.85 for human review.
    struct ScannedField: Decodable, Hashable {
        let value: ScalarValue?
        let confidence: Double
        let rawText: String?
    }

    struct ScannedCredential: Decodable, Hashable {
        let credentialType: String
        let identifier: ScannedField?
        let holderName: ScannedField?
        let holderDOB: ScannedField?
        let issuingAuthority: ScannedField?
        let issuingJurisdiction: ScannedField?
        let issueDate: ScannedField?
        let expirationDate: ScannedField?
        let licenseClass: ScannedField?
        let endorsements: ScannedField?
        let restrictions: ScannedField?
        let medicalExaminerName: ScannedField?
        let medicalNationalRegistryNumber: ScannedField?
        let insuranceCarrier: ScannedField?
        let policyNumber: ScannedField?
        let autoLiabilityLimit: ScannedField?
        let cargoLiabilityLimit: ScannedField?
        let generalLiabilityLimit: ScannedField?
        let hasMCS90: ScannedField?
        let insuredEntities: ScannedField?
        let usdotNumber: ScannedField?
        let mcNumber: ScannedField?
        let operatingStatus: ScannedField?
        let hazmatAuthorized: ScannedField?
        let vesselName: ScannedField?
        let imoNumber: ScannedField?
        let callSign: ScannedField?
        let locomotiveTerritory: ScannedField?
        let einNumber: ScannedField?
        let rfcNumber: ScannedField?
        let craBusinessNumber: ScannedField?
        let legalEntityName: ScannedField?
        let additional: [String: String]?
        let overallConfidence: Double
        let warnings: [String]
    }

    enum MimeType: String, Encodable {
        case jpeg = "image/jpeg"
        case png = "image/png"
        case webp = "image/webp"
        case heic = "image/heic"
        case pdf = "application/pdf"
    }

    /// Submit a single credential image / PDF for OCR. `documentBase64`
    /// must NOT include the `data:image/...;base64,` prefix — pass
    /// raw base64. The server strips an accidental prefix anyway as
    /// a courtesy.
    func scan(credentialType: String, documentBase64: String, mimeType: MimeType) async throws -> ScannedCredential {
        struct Input: Encodable {
            let credentialType: String
            let documentBase64: String
            let mimeType: String
        }
        return try await api.mutation(
            "credentialScanner.scan",
            input: Input(
                credentialType: credentialType,
                documentBase64: documentBase64,
                mimeType: mimeType.rawValue
            )
        )
    }

    struct BatchInputItem: Encodable {
        let credentialType: String
        let documentBase64: String
        let mimeType: String
        let clientRef: String?
    }

    struct BatchResultItem: Decodable, Hashable {
        let credentialType: String
        let identifier: ScannedField?
        let holderName: ScannedField?
        let expirationDate: ScannedField?
        let overallConfidence: Double
        let warnings: [String]
        let clientRef: String?
    }

    struct BatchResponse: Decodable, Hashable {
        let items: [BatchResultItem]
    }

    /// Batch up to 25 credentials in one request. Server fans out to
    /// Gemini with a small concurrency cap; results are order-
    /// preserving and carry the wizard's `clientRef` so each row
    /// lands back at the right form section.
    func scanBatch(_ items: [BatchInputItem]) async throws -> BatchResponse {
        struct Input: Encodable { let items: [BatchInputItem] }
        return try await api.mutation(
            "credentialScanner.scanBatch",
            input: Input(items: items)
        )
    }

    struct SupportedType: Decodable, Hashable, Identifiable {
        let type: String
        let vertical: String     // "truck" | "rail" | "vessel" | "any"
        let country: String      // "US" | "CA" | "MX" | "INT" | "ANY"
        let label: String
        var id: String { type }
    }
    struct SupportedTypesResponse: Decodable, Hashable {
        let types: [SupportedType]
    }

    /// Render the wizard's "Pick a document type" picker from the
    /// server's authoritative list so iOS doesn't drift out of sync.
    func listSupportedTypes() async throws -> SupportedTypesResponse {
        struct Empty: Encodable {}
        return try await api.query("credentialScanner.listSupportedTypes", input: Empty())
    }
}

// MARK: - FleetRegistrationAPI
//
// Onboarding-time bulk fleet + driver intake. Wraps the server's
// `fleetRegistrationRouter`. Used by:
//   • Carrier (CATALYST / BROKER) registration step 3 — "register
//     your fleet" — VIN scan or CSV upload, seeds vehicles + Zeun
//     maintenance schedules + DVIR baseline.
//   • Carrier registration step 4 — "invite your team" — bulk
//     driver invites via email + deep link.
//   • Rail catalyst — vehicle records hold the company's
//     locomotive / car / chassis VINs and AAR marks.
//   • Vessel operator — the platform-level vehicles row is created
//     with `specialized` type while the USCG vessel doc lives in
//     the vessels table (separate path).

struct FleetRegistrationAPI {
    unowned let api: EusoTripAPI

    // MARK: VIN decode

    struct VinDecoded: Decodable, Hashable {
        let vin: String
        let make: String?
        let model: String?
        let year: Int?
        let manufacturer: String?
        let bodyClass: String?
        let vehicleType: String?
        let gvwrClass: String?
        let fuelType: String?
        let driveType: String?
        let engineCylinders: String?
        let engineDisplacement: String?
        let plant: String?
        let plantCountry: String?
        let brakeSystem: String?
        let axleConfiguration: String?
    }

    struct DecodeVinResponse: Decodable, Hashable {
        let ok: Bool
        let reason: String?
        let decoded: VinDecoded?
        let suggestedVehicleType: String?
        let gvwrClassNumber: Int?
    }

    /// Decode a VIN via NHTSA vPIC without persisting. Use this
    /// behind the iOS DataScannerViewController to confirm
    /// make/model/year before the user taps "Add to fleet".
    func decodeVin(_ vin: String) async throws -> DecodeVinResponse {
        struct Input: Encodable { let vin: String }
        return try await api.mutation("fleetRegistration.decodeVin", input: Input(vin: vin))
    }

    // MARK: Vehicle fleet bulk-register

    struct VehicleInput: Encodable, Hashable {
        let vin: String
        let unitNumber: String?
        let licensePlate: String?
        let mileage: Int?
        let vehicleType: String?
        let make: String?
        let model: String?
        let year: Int?
        let capacity: Double?
        let assignedDriverEmail: String?
    }

    struct AcceptedVehicle: Decodable, Hashable {
        let vin: String
        let vehicleId: Int
        let make: String?
        let model: String?
        let year: Int?
        let vehicleType: String
    }
    struct RejectedVehicle: Decodable, Hashable {
        let vin: String
        let reason: String
    }
    struct FleetRegisterSummary: Decodable, Hashable {
        let totalSubmitted: Int
        let accepted: Int
        let rejected: Int
        let zeunSchedulesSeeded: Int
        let dvirBaselinesSeeded: Int
    }
    struct FleetRegisterResponse: Decodable, Hashable {
        let success: Bool
        let accepted: [AcceptedVehicle]
        let rejected: [RejectedVehicle]
        let summary: FleetRegisterSummary
    }

    func registerVehicleFleet(
        _ vehicles: [VehicleInput],
        seedDvirBaseline: Bool = true,
        seedZeunSchedule: Bool = true
    ) async throws -> FleetRegisterResponse {
        struct Input: Encodable {
            let vehicles: [VehicleInput]
            let seedDvirBaseline: Bool
            let seedZeunSchedule: Bool
        }
        return try await api.mutation(
            "fleetRegistration.registerVehicleFleet",
            input: Input(vehicles: vehicles, seedDvirBaseline: seedDvirBaseline, seedZeunSchedule: seedZeunSchedule)
        )
    }

    // MARK: Driver bulk-invite

    enum InviteVertical: String, Encodable {
        case truck, rail, vessel
    }

    struct DriverInviteInput: Encodable, Hashable {
        let firstName: String
        let lastName: String
        let email: String
        let phone: String?
        let cdlNumber: String?
        let cdlState: String?
        let hireDate: String?     // ISO yyyy-mm-dd
        let vertical: String      // one of InviteVertical.rawValue
        let notes: String?
    }

    struct InviteSent: Decodable, Hashable {
        let email: String
        let code: String
        let signupUrl: String
    }
    struct InviteFailed: Decodable, Hashable {
        let email: String
        let reason: String
    }
    struct InviteSummary: Decodable, Hashable {
        let totalSubmitted: Int
        let sent: Int
        let failed: Int
    }
    struct InviteResponse: Decodable, Hashable {
        let success: Bool
        let sent: [InviteSent]
        let failed: [InviteFailed]
        let summary: InviteSummary
    }

    func bulkInviteDrivers(_ invitees: [DriverInviteInput], message: String? = nil) async throws -> InviteResponse {
        struct Input: Encodable {
            let invitees: [DriverInviteInput]
            let message: String?
        }
        return try await api.mutation(
            "fleetRegistration.bulkInviteDrivers",
            input: Input(invitees: invitees, message: message)
        )
    }

    // MARK: Onboarding progress

    struct OnboardingFleetSummary: Decodable, Hashable {
        let vehicleCount: Int
        let driverCount: Int
        let pendingDvirCount: Int
        let zeunScheduleCount: Int
    }

    /// Backs the wizard's "Fleet ready" progress card. Render the
    /// summary alongside Continue/Skip so the user sees the
    /// platform-side side-effects of their upload (vehicles + DVIR
    /// baselines + Zeun schedule rows).
    func getOnboardingFleetSummary() async throws -> OnboardingFleetSummary {
        struct Empty: Encodable {}
        return try await api.query("fleetRegistration.getOnboardingFleetSummary", input: Empty())
    }
}

// MARK: - DocumentRouterAPI
//
// Master classifier — every upload / bulk-upload affordance on iOS
// calls this first. Returns a typed classification + extracted
// fields + the canonical tRPC procedure to call next. Powered by
// Gemini Vision against the EusoTrip 60-type document taxonomy.
//
// Wherever an iOS surface offers an upload (Shipper Post-Load
// Templates / Bulk, Driver Me·Docs, Catalyst onboarding bundle drop,
// Compliance officer renewal, Wallet pickup-credential photo, etc.)
// route through this first so the user never has to pick a document
// type from a 60-option dropdown.

struct DocumentRouterAPI {
    unowned let api: EusoTripAPI

    enum MimeType: String, Encodable {
        case jpeg = "image/jpeg"
        case png = "image/png"
        case webp = "image/webp"
        case heic = "image/heic"
        case pdf = "application/pdf"
    }

    /// Heterogeneous JSON value — extractedFields are typed at the
    /// document level so we accept whatever the server emits.
    enum FieldValue: Decodable, Hashable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case null

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .null; return }
            if let v = try? c.decode(Bool.self) { self = .bool(v); return }
            if let v = try? c.decode(Double.self) { self = .number(v); return }
            if let v = try? c.decode(String.self) { self = .string(v); return }
            self = .null
        }

        var asString: String? {
            switch self {
            case .string(let s): return s
            case .number(let d): return d == d.rounded() ? String(format: "%.0f", d) : String(d)
            case .bool(let b): return b ? "true" : "false"
            case .null: return nil
            }
        }
    }

    struct ClassifyResponse: Decodable, Hashable {
        /// One of `documentRouter.DocumentTypes` (60+ values).
        let classifiedType: String
        let confidence: Double
        let summary: String
        /// Per-document extracted fields. Keys are doc-type-specific
        /// (e.g. BOL → bolNumber/shipperName/consigneeName, CDL →
        /// identifier/holderName/expirationDate). Caller dispatches
        /// these into the type-specific tRPC procedure.
        let extractedFields: [String: FieldValue]
        /// The canonical tRPC procedure to call next with the
        /// extracted fields. Nil for `unknown` or types without a
        /// platform-side parser.
        let dispatchTarget: String?
        let warnings: [String]
    }

    /// Classify + route a single document. Pass `callerContext`
    /// (e.g. "shipper Post-Load bulk", "driver post-trip BOL",
    /// "carrier registration step 3 docs bundle") to help the
    /// classifier disambiguate when two doc shapes overlap.
    func classifyAndRoute(
        documentBase64: String,
        mimeType: MimeType,
        callerContext: String? = nil
    ) async throws -> ClassifyResponse {
        struct Input: Encodable {
            let documentBase64: String
            let mimeType: String
            let callerContext: String?
        }
        return try await api.mutation(
            "documentRouter.classifyAndRoute",
            input: Input(
                documentBase64: documentBase64,
                mimeType: mimeType.rawValue,
                callerContext: callerContext
            )
        )
    }

    struct BatchItem: Encodable {
        let documentBase64: String
        let mimeType: String
        let clientRef: String?
        let callerContext: String?
    }

    struct BatchResponse: Decodable, Hashable {
        struct Result: Decodable, Hashable {
            let classifiedType: String
            let confidence: Double
            let summary: String
            let extractedFields: [String: FieldValue]
            let dispatchTarget: String?
            let warnings: [String]
            let clientRef: String?
        }
        let items: [Result]
    }

    /// Batch classify up to 30 documents in one round-trip. Carrier
    /// onboarding "drop your full packet" uses this so the user can
    /// dump 10 PDFs and we sort them server-side.
    func classifyBatch(_ items: [BatchItem]) async throws -> BatchResponse {
        struct Input: Encodable { let items: [BatchItem] }
        return try await api.mutation("documentRouter.classifyBatch", input: Input(items: items))
    }

    struct SupportedTypesResponse: Decodable, Hashable {
        struct TypeEntry: Decodable, Hashable, Identifiable {
            let type: String
            let dispatchTarget: String?
            var id: String { type }
        }
        let types: [TypeEntry]
    }

    /// Pulls the full classifier taxonomy from the server so the
    /// iOS Templates picker doesn't drift out of sync.
    func listSupportedTypes() async throws -> SupportedTypesResponse {
        struct Empty: Encodable {}
        return try await api.query("documentRouter.listSupportedTypes", input: Empty())
    }
}

// MARK: - sparkRouter (overnight briefs · Tier 1 #21/#23/#24)
//
// Mirrors `frontend/server/routers/spark.ts`. Three roles
// (shipper / dispatcher / catalyst) each get a 3-child Cortex
// fanout + 1 synthesis call at ~03:00 UTC; the iOS card pulls
// the cached brief on Home and offers a "Run Now" mutation
// when the founder wants a fresh one mid-day.

struct SparkAPI {
    unowned let api: EusoTripAPI

    private struct RoleInput: Encodable {
        let role: String
        init(_ role: SparkRole) { self.role = role.rawValue }
    }
    private struct Empty: Encodable {}

    /// Read the current cached brief for the calling user's
    /// company. Returns `{ brief: SparkBriefPayload?, sampledAt, source }`.
    func getLatest(role: SparkRole) async throws -> SparkGetBriefResponse {
        try await api.queryNoInput(role.getPath)
    }

    /// Fire a fresh fanout. Server takes ~6-8s; the card stays
    /// on the existing brief and swaps when this resolves.
    func run(role: SparkRole) async throws -> SparkRunBriefResponse {
        try await api.mutation(role.runPath, input: Empty())
    }
}

// MARK: - equipmentAgentRouter (Tier 2 #40 · trailer recommendation)
//
// Mirrors `frontend/server/routers/equipmentAgent.ts`.
// 3-child Cortex fanout (perception + memory + planning) plus a
// synthesis pass returning a top pick + 2 alternatives with
// fitScore + redFlags + availableInFleet count.

struct EquipmentAgentAPI {
    unowned let api: EusoTripAPI

    /// Calls `equipmentAgent.recommend`. Response shape mirrors
    /// the server's `RecommendOutput`:
    ///   { generatedAtUtc, topPick, alternatives, synthesis,
    ///     childrenFiredCount }
    func recommend(input: EquipmentRecommendInput) async throws -> EquipmentRecommendResponse {
        try await api.mutation("equipmentAgent.recommend", input: input)
    }

    /// `equipmentAgent.getLatest` — read the most recent
    /// recommendation envelope for the calling user's company.
    /// Use this to hydrate the widget on first render so the
    /// founder sees the prior recommendation instantly while a
    /// fresh fanout runs in the background.
    struct GetLatestInput: Encodable {
        let companyId: Int
    }
    func getLatest(companyId: Int) async throws -> EquipmentRecommendResponse? {
        struct EnvelopeOptional: Decodable {
            let envelope: EquipmentRecommendResponse?
        }
        // Server returns either the recommendation envelope or null;
        // tRPC wraps it as the value itself, not under `envelope`.
        // We accept both shapes here.
        return try? await api.query("equipmentAgent.getLatest",
                                    input: GetLatestInput(companyId: companyId))
    }
}

// MARK: - xrChecklistRouter (Tier 1 #12 / Tier 3 #10 / Tier 3 #11)
//
// Mirrors `frontend/server/routers/xrChecklist.ts`. Surfaces the
// XR HUD endpoints to iOS: streaming reefer status, dock-worker
// POD capture (counter-party to driver POD), USMCA filing
// assistant.

struct XRChecklistAPI {
    unowned let api: EusoTripAPI

    /// `xrChecklist.dockWorkerPodCapture` — counter-party POD sign-off
    /// for the receiver's dock worker. Server chains the audit row
    /// off the driver's existing `load.pod_captured` block when one
    /// exists; returns `chainedToDriverPod: true` in that case.
    func dockWorkerPodCapture(input: DockWorkerPodInput) async throws -> DockWorkerPodResponse {
        try await api.mutation("xrChecklist.dockWorkerPodCapture", input: input)
    }

    /// `xrChecklist.usmcaFilingAssistant` — Tier 3 #11.
    /// 2-child Cortex fanout (perception + guardian) + a synthesis
    /// pass returning the next filing step with citations and a
    /// driver-spoken instruction. Played through ESangTTSPlayer
    /// from the sheet so the driver's eyes stay on the road.
    func usmcaFilingAssistant(input: USMCAFilingInput) async throws -> USMCAFilingResponse {
        try await api.mutation("xrChecklist.usmcaFilingAssistant", input: input)
    }

    /// `xrChecklist.streamReeferStatus` — Tier 1 #12.
    /// Read-only poll endpoint. Returns the latest reefer
    /// observation + breach flag + spoken status + the server-
    /// recommended next-poll interval (30s in breach, 120s normal).
    func streamReeferStatus(input: XRReeferStatusInput) async throws -> XRReeferStatusPayload {
        try await api.query("xrChecklist.streamReeferStatus", input: input)
    }
}

// MARK: - laneAgentRouter (Tier 2 #37 · conversational rate intel)
//
// Mirrors `frontend/server/routers/laneAgent.ts`. 3-child Cortex
// fanout (perception parses the lane query, memory pulls the
// last-90d settlement sample, reasoning emits drivers + surcharges)
// + a synthesis pass returning a single broker advisory paragraph.

struct LaneAgentAPI {
    unowned let api: EusoTripAPI

    /// `laneAgent.query` — fire a conversational lane question.
    func query(input: LaneAgentQueryInput) async throws -> LaneAgentResponse {
        try await api.mutation("laneAgent.query", input: input)
    }

    /// `laneAgent.getRecent` — last N query snapshots for the
    /// founder's company (rendered as the History strip).
    struct GetRecentInput: Encodable {
        let companyId: Int
        let limit: Int
    }
    func getRecent(companyId: Int, limit: Int = 5) async throws -> [LaneAgentHistoryItem] {
        try await api.query("laneAgent.getRecent",
                            input: GetRecentInput(companyId: companyId, limit: limit))
    }
}

// MARK: - carrierVetAgentRouter (Tier 2 #38 · FMCSA + scorecard + guardian)
//
// Mirrors `frontend/server/routers/carrierVetAgent.ts`. 3-child
// Cortex fanout (perception parses FMCSA snapshot, memory pulls
// EusoTrip scorecard, guardian emits the verdict) returning the
// vetting envelope.

// MARK: - railDemurrageAutoRouter (Rail demurrage automation)
//
// Mirrors `frontend/server/routers/railDemurrageAuto.ts`. Automated
// demurrage accrual, bulk reporting, dispute tracking, and waiver
// workflows. Country-specific free-time rules (US 48h, CA 48h, MX 24h).

struct RailDemurrageAutoAPI {
    unowned let api: EusoTripAPI

    /// `railDemurrageAuto.reportByDwellReason` — query dwell reasons
    /// and accrual aggregates. Server returns `{ reasons: [...] }`;
    /// iOS decodes as `[DwellReasonItem]` via custom init(from:).
    struct DwellReasonItem: Decodable {
        let reason: String
        let count: Int
        let totalCharges: Double
        let avgHours: Double
    }

    struct DwellReasonResponse: Decodable {
        let reasons: [DwellReasonItem]
    }

    /// `railDemurrageAuto.reportByDwellReason` — aggregated dwell
    /// reasons over the period.
    struct ReportByDwellReasonInput: Encodable {
        let periodDays: Int?
    }

    func reportByDwellReason(periodDays: Int? = nil) async throws -> [DwellReasonItem] {
        struct Input: Encodable { let periodDays: Int? }
        let resp: DwellReasonResponse = try await api.query(
            "railDemurrageAuto.reportByDwellReason",
            input: Input(periodDays: periodDays)
        )
        return resp.reasons
    }
}

struct CarrierVetAgentAPI {
    unowned let api: EusoTripAPI

    /// `carrierVetAgent.vet` — fire a vetting call for a DOT.
    func vet(input: CarrierVetInput) async throws -> CarrierVetResponse {
        try await api.mutation("carrierVetAgent.vet", input: input)
    }

    struct GetRecentInput: Encodable {
        let companyId: Int
        let limit: Int
    }
    /// `carrierVetAgent.getRecentVettings` — history strip for the
    /// founder's company.
    func getRecentVettings(companyId: Int, limit: Int = 10) async throws -> [CarrierVetHistoryItem] {
        try await api.query("carrierVetAgent.getRecentVettings",
                            input: GetRecentInput(companyId: companyId, limit: limit))
    }
}

// MARK: - vesselShipmentsRouter (ocean live-track surface · 003)
//
// Mirrors the integration-powered procs in
// `frontend/server/routers/vesselShipments.ts`:
//
//   • liveVesselPosition(imoNumber)        :1032 → VesselPosition | null
//        (MarineTraffic/Kpler live AIS — lat/lng/heading/speed/eta/timestamp)
//   • getVesselTrack(imoNumber)            :1085 → RoutePosition[] | null
//        (MarineTraffic historical track — polyline for map plotting)
//   • getVesselPortCalls(imoNumber,days)   :1060 → PortCall[] | null
//        (MarineTraffic scheduled / historical port calls)
//   • getContainerPositions(status?,limit) :950  → { containers, total }
//        (per-box geofence rows; NEVER null — empty arrays on no-db)
//   • liveTrackOceanShipment(referenceNumber):1132 → TrackingEvent[] | null
//        (INTTRA/E2open cross-carrier ocean-shipment track events)
//
// Every integration proc `return null` on a caught error, so the live AIS /
// track / port-call / INTTRA decoders are Optionals — the 003 ocean map
// coalesces nil → [] (or falls back to the booking's authored origin/dest).
// The decoders are typed VERBATIM to the service interfaces
// (`MarineTrafficService.ts` VesselPosition/RoutePosition/PortCall and
// `INTTRAService.ts` TrackingEvent). `shippingContainers` rows are loose
// freeform JSON server-side, so `ContainerPosition` decodes the stable
// subset (id/containerNumber/status/lat/lng/updatedAt) leniently.

struct VesselTrackAPI {
    unowned let api: EusoTripAPI

    // MARK: Decoders (1:1 with the server service interfaces)

    /// `MarineTrafficService.VesselPosition` — live AIS fix. The 003 AIS orb +
    /// callout chip (speed / heading / coords) + ETA strip read off this.
    struct VesselPosition: Decodable, Hashable {
        let imoNumber: String?
        let mmsi: String?
        let lat: Double
        let lng: Double
        let heading: Double?
        let speed: Double?
        let course: Double?
        let destination: String?
        let eta: String?
        let timestamp: String?
        let status: String?
        let draught: Double?
        let navigationalStatus: String?
    }

    /// `MarineTrafficService.RoutePosition` — one historical AIS track vertex.
    /// The ordered array is the great-circle source polyline (origin→current).
    struct RoutePosition: Decodable, Hashable {
        let lat: Double
        let lng: Double
        let speed: Double?
        let heading: Double?
        let course: Double?
        let timestamp: String?
        let status: String?

        /// Projected into the canonical map data contract.
        var coordinate: HereLatLng { HereLatLng(lat, lng) }
    }

    /// `MarineTrafficService.PortCall` — a scheduled / historical port call.
    struct PortCall: Decodable, Hashable {
        let portName: String?
        let portId: String?
        let unlocode: String?
        let arrivalTime: String?
        let departureTime: String?
        let inPort: Bool?
        let draught: Double?
        let country: String?
    }

    /// `INTTRAService.TrackingEvent` — one cross-carrier ocean-track event
    /// (the 003 "AIS EVENTS · EUSOTRIP NETWORK" feed rows).
    struct TrackingEvent: Decodable, Hashable {
        let eventType: String?
        let eventDescription: String?
        let location: String?
        let timestamp: String?
        let vessel: String?
        let voyage: String?
        let containerNumber: String?
        let status: String?
    }

    /// One `shippingContainers` row projected to its map-relevant fields.
    /// Decoded leniently — the server row is a wide freeform record and only
    /// this stable subset is consumed by the per-container positions surface.
    struct ContainerPosition: Decodable, Hashable {
        let id: Int?
        let containerNumber: String?
        let status: String?
        let currentLat: Double?
        let currentLng: Double?
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case containerNumber
            case status
            case currentLat, latitude, lat
            case currentLng, longitude, lng
            case updatedAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(Int.self, forKey: .id)
            containerNumber = try c.decodeIfPresent(String.self, forKey: .containerNumber)
            status = try c.decodeIfPresent(String.self, forKey: .status)
            currentLat = try c.decodeIfPresent(Double.self, forKey: .currentLat)
                ?? c.decodeIfPresent(Double.self, forKey: .latitude)
                ?? c.decodeIfPresent(Double.self, forKey: .lat)
            currentLng = try c.decodeIfPresent(Double.self, forKey: .currentLng)
                ?? c.decodeIfPresent(Double.self, forKey: .longitude)
                ?? c.decodeIfPresent(Double.self, forKey: .lng)
            updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        }

        /// nil unless the row carries a real geofence fix.
        var coordinate: HereLatLng? {
            guard let lat = currentLat, let lng = currentLng else { return nil }
            return HereLatLng(lat, lng)
        }
    }

    struct ContainerPositionsResult: Decodable {
        let containers: [ContainerPosition]
        let total: Int
    }

    // MARK: Inputs

    private struct ImoInput: Encodable { let imoNumber: String }
    private struct PortCallsInput: Encodable { let imoNumber: String; let days: Int }
    private struct RefInput: Encodable { let referenceNumber: String }
    private struct ContainerPositionsInput: Encodable {
        let status: String?
        let limit: Int
    }

    // MARK: Procedures

    /// `vesselShipments.liveVesselPosition` — live AIS fix for the vessel orb,
    /// callout chip (speed / heading / coords), and ETA. `nil` when the AIS
    /// feed is unavailable (server returns `null` on a caught error).
    func liveVesselPosition(imoNumber: String) async throws -> VesselPosition? {
        try await api.query("vesselShipments.liveVesselPosition",
                            input: ImoInput(imoNumber: imoNumber))
    }

    /// `vesselShipments.getVesselTrack` — historical AIS track vertices, the
    /// origin→current source for the great-circle polyline. `nil` on error.
    func getVesselTrack(imoNumber: String) async throws -> [RoutePosition]? {
        try await api.query("vesselShipments.getVesselTrack",
                            input: ImoInput(imoNumber: imoNumber))
    }

    /// `vesselShipments.getVesselPortCalls` — scheduled / historical port
    /// calls (origin / destination pin enrichment). `nil` on error.
    func getVesselPortCalls(imoNumber: String, days: Int = 30) async throws -> [PortCall]? {
        try await api.query("vesselShipments.getVesselPortCalls",
                            input: PortCallsInput(imoNumber: imoNumber, days: days))
    }

    /// `vesselShipments.liveTrackOceanShipment` — INTTRA/E2open cross-carrier
    /// ocean-track events (the 003 AIS-EVENTS feed). `nil` on error.
    func liveTrackOceanShipment(referenceNumber: String) async throws -> [TrackingEvent]? {
        try await api.query("vesselShipments.liveTrackOceanShipment",
                            input: RefInput(referenceNumber: referenceNumber))
    }

    /// `vesselShipments.getContainerPositions` — per-box geofence rows for the
    /// "Per-container positions" surface. Never `null` (empty arrays on no-db).
    func getContainerPositions(status: String? = nil, limit: Int = 100) async throws -> ContainerPositionsResult {
        try await api.query("vesselShipments.getContainerPositions",
                            input: ContainerPositionsInput(status: status, limit: limit))
    }
}
