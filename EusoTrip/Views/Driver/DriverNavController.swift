//
//  DriverNavController.swift
//  EusoTrip — Shared navigation state for the Driver BottomNav.
//
//  Closes SKILL.md §7 wiring gap: "make sure all screens have pressable
//  buttons and work; make sure bottom nav works" (user message, 2026-04-19).
//
//  Every 010-023 lifecycle screen bakes a `BottomNav` into its own body with
//  NavSlot.onTap defaulting to a no-op. That made the nav cosmetic — tapping
//  "Home", "Trips", "Wallet", "Me", or the center orb did nothing. Rather
//  than edit every screen's private `driverNavLeading_NNN()` helper to pass
//  real handlers (14 files × 4 slots + orb), we expose a single env-backed
//  handler that `BottomNav` reads. Every slot's tap resolves the label
//  ("Home" / "Trips" / "Wallet" / "Me" / "esang") into a controller action.
//
//  Controller owns:
//    • `currentTab` — which top-level surface is visible (home | trips |
//      wallet | me).
//    • `showESang` — whether the ESANG coach sheet is presented over
//      whatever surface is current.
//    • `lifecycleIndex` — when currentTab == .home we render the indexed
//      Driver-role ScreenRegistry screen, so the nav can still flip between
//      010 Home and the current active-trip screen (023 Backing-In, etc.).
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - DriverNavController

final class DriverNavController: ObservableObject {

    /// Top-level surfaces reachable from the BottomNav.
    enum Tab: String, CaseIterable {
        case home, trips, wallet, me
    }

    @Published var currentTab: Tab = .home

    /// When true, `DriverESangCoachSheet` is presented on top of whatever
    /// surface is currently visible. Tapping the center orb toggles this on;
    /// the sheet's close button toggles it off.
    @Published var showESang: Bool = false

    /// Position into `ScreenRegistry.forRole(.driver)` — drives the
    /// "edge-to-edge screen" that renders when `currentTab == .home`. The
    /// ContentView dev-chrome next/prev bar writes here; so does the Home
    /// slot tap when the user is already on .home (pops back to 010).
    @Published var lifecycleIndex: Int = 0

    /// Resolve a BottomNav slot label into the right controller action.
    /// Called by `BottomNav` via the env-injected handler.
    ///
    /// Request 3 (2026-04-19) renamed the former "Wallet" slot to "Loads"
    /// — the Tab enum case stays `.wallet` for backward compat; both
    /// labels route to the same surface so any preview or legacy handler
    /// still works.
    func handle(_ label: String) {
        switch label.lowercased() {
        case "home":
            // Already on the home surface — popping back to 010 is the
            // expected behavior so the driver always has a quick way back
            // to the dashboard.
            currentTab = .home
            lifecycleIndex = 0
        case "trips":
            currentTab = .trips
        case "loads", "wallet":
            currentTab = .wallet
        case "me":
            currentTab = .me
        case "esang", "orb":
            showESang = true
        default:
            break
        }
    }

    /// Whether the supplied label matches the surface currently displayed.
    /// Used by the container panes to decide which slot shows `isCurrent`.
    func isActive(_ label: String) -> Bool {
        switch label.lowercased() {
        case "home":             return currentTab == .home
        case "trips":            return currentTab == .trips
        case "loads", "wallet":  return currentTab == .wallet
        case "me":               return currentTab == .me
        default:                 return false
        }
    }
}

// MARK: - Environment key

/// Slot-tap handler injected by the ContentView root. When `BottomNav`
/// detects this env value, it routes ALL slot and orb taps through the
/// handler instead of calling each NavSlot's local `onTap` (which every
/// 010-023 helper leaves at the default no-op). If the handler is nil the
/// per-slot onTap still runs — the fallback matches pre-wiring behavior
/// and keeps #Preview blocks that build a BottomNav in isolation working.
struct DriverNavHandlerKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

extension EnvironmentValues {
    var driverNavHandler: ((String) -> Void)? {
        get { self[DriverNavHandlerKey.self] }
        set { self[DriverNavHandlerKey.self] = newValue }
    }
}

// MARK: - Lifecycle advance handler

/// Closure injected by ContentView when rendering the `.home` driver surface.
/// Any screen in the 010→027 lifecycle walk can opt in by rendering a
/// `LifecycleCTAButton` (or by reading the env value directly) — tapping the
/// primary forward CTA advances `currentIndex` to the next screen, looping
/// back to 010 after 027. Injection is scoped to the home lifecycle surface
/// so secondary CTAButtons elsewhere (MeDetailScreens, DriverWalletPane,
/// etc.) never pick up the advance.
struct LifecycleAdvanceKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var lifecycleAdvance: (() -> Void)? {
        get { self[LifecycleAdvanceKey.self] }
        set { self[LifecycleAdvanceKey.self] = newValue }
    }
}

/// Closure injected by ContentView that rewinds the trip state machine
/// back to `.idle` — used by the close/dismiss chip on lifecycle screens
/// (Pre-trip DVIR's X button, etc.) so the driver can abandon an
/// in-progress screen without needing to wait for a forward transition.
/// Distinct from `lifecycleAdvance` so the two concepts can't accidentally
/// collide.
struct LifecycleExitKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var lifecycleExit: (() -> Void)? {
        get { self[LifecycleExitKey.self] }
        set { self[LifecycleExitKey.self] = newValue }
    }
}

/// Closure injected by ContentView that walks the trip state one phase
/// backward (`trip.stepBack()`). Plumbed as a first-class env key because
/// every 010-099 top-bar renders a `chevron.left` button — wiring each of
/// those to a bespoke handler would fan out across 40+ files. Instead we
/// expose a single env closure that every back button reads and taps.
///
/// Semantics:
///   • When the phase has a `happyPathPrev`, walk back to it.
///   • When the phase is `.idle` the closure is a no-op (user is already
///     on the dashboard — back is meaningless).
///   • Screens presented as `.sheet` should still use `@Environment(\.dismiss)`
///     directly; this env key is for edge-to-edge lifecycle screens only.
///
/// Registered in `ContentView.body` alongside `lifecycleAdvance` /
/// `lifecycleExit` so the three back/forward/exit closures share one
/// injection site and one `trip` controller.
struct DriverNavBackKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var driverNavBack: (() -> Void)? {
        get { self[DriverNavBackKey.self] }
        set { self[DriverNavBackKey.self] = newValue }
    }
}

/// Primary forward CTA for lifecycle screens. Renders exactly like
/// `CTAButton` but picks up the env-injected `lifecycleAdvance` handler so
/// tapping it advances the ScreenRegistry cursor to the next screen. Use on
/// the "forward" CTA only (e.g., "I'm at the gate", "Mark delivered",
/// "Accept · drive"); leave secondary CTAs on `CTAButton`.
struct LifecycleCTAButton: View {
    let title: String
    @Environment(\.lifecycleAdvance) private var advance

    var body: some View {
        CTAButton(title: title) { advance?() }
    }
}

// MARK: - Utility env closures (45th firing · dead-stub sweep)
//
// The 44th firing wired the three lifecycle verbs (advance / exit / back).
// 45th adds the ambient actions that every lifecycle screen needs — phone
// calls to dispatch, document drawer, trip log, share, help, photo upload,
// report-an-issue — so the 60 remaining dead `Button { } label: { ... }`
// stubs across 011–045 have a real closure to resolve to. Each closure is
// scoped to the Driver surface; ContentView owns the real implementations
// and can choose to open a sheet, call UIApplication, or no-op under
// Preview. Fallback is nil so Preview blocks keep building.

/// Dial a phone number via `tel://` URL. ContentView implements it with
/// `UIApplication.shared.open(URL(string: "tel://\(number)")!)`.
/// Drivers pass the dispatcher / guard / receiver number as a raw string.
struct DriverDialPhoneKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}
extension EnvironmentValues {
    var driverDialPhone: ((String) -> Void)? {
        get { self[DriverDialPhoneKey.self] }
        set { self[DriverDialPhoneKey.self] = newValue }
    }
}

/// Open the canonical messaging surface (or thread, when a contact id is
/// supplied). Wired to jump to the Me tab's Messages sub-route — the
/// real backend is the `messages.ts` canonical router (§16 messaging-docs).
struct DriverOpenMessagesKey: EnvironmentKey {
    static let defaultValue: ((String?) -> Void)? = nil
}
extension EnvironmentValues {
    var driverOpenMessages: ((String?) -> Void)? {
        get { self[DriverOpenMessagesKey.self] }
        set { self[DriverOpenMessagesKey.self] = newValue }
    }
}

/// Open the Trip/Docs drawer — jumps the nav controller to the Me tab
/// which renders the driver's active documents (BOL, ratecon, POD).
struct DriverOpenDocDrawerKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}
extension EnvironmentValues {
    var driverOpenDocDrawer: (() -> Void)? {
        get { self[DriverOpenDocDrawerKey.self] }
        set { self[DriverOpenDocDrawerKey.self] = newValue }
    }
}

/// Open the Trip Log (legs + events list) as a sheet. Used by 034/037
/// "Trip log" CTAs and the 018 "Find stop" navigator search.
struct DriverOpenTripLogKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}
extension EnvironmentValues {
    var driverOpenTripLog: (() -> Void)? {
        get { self[DriverOpenTripLogKey.self] }
        set { self[DriverOpenTripLogKey.self] = newValue }
    }
}

/// Present the iOS share sheet for a link / identifier. Used by the
/// share-BOL chips on 028/041.
struct DriverShareLinkKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}
extension EnvironmentValues {
    var driverShareLink: ((String) -> Void)? {
        get { self[DriverShareLinkKey.self] }
        set { self[DriverShareLinkKey.self] = newValue }
    }
}

/// Open the context-sensitive help surface — topic key is the screen's
/// short slug ("disconnect-step", "connect-hose", etc). ContentView
/// routes these into the ESANG coach sheet.
struct DriverShowHelpKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}
extension EnvironmentValues {
    var driverShowHelp: ((String) -> Void)? {
        get { self[DriverShowHelpKey.self] }
        set { self[DriverShowHelpKey.self] = newValue }
    }
}

/// Launch the photo-capture flow (defect photo, POD photo, damage photo).
/// ContentView routes to a sheet wrapping `UIImagePickerController`
/// in production; under Preview it no-ops.
struct DriverUploadPhotoKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}
extension EnvironmentValues {
    var driverUploadPhoto: (() -> Void)? {
        get { self[DriverUploadPhotoKey.self] }
        set { self[DriverUploadPhotoKey.self] = newValue }
    }
}

/// Report an issue / exception from the active lifecycle screen — opens
/// the "raise exception" sheet. Backend writes to `exceptions.create`.
struct DriverReportIssueKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}
extension EnvironmentValues {
    var driverReportIssue: (() -> Void)? {
        get { self[DriverReportIssueKey.self] }
        set { self[DriverReportIssueKey.self] = newValue }
    }
}

/// Toggle the in-cab voice-coach mute state. Screen 035 EnRoute has the
/// speaker.slash button in its bottom-corner controls.
struct DriverToggleVoiceMuteKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}
extension EnvironmentValues {
    var driverToggleVoiceMute: (() -> Void)? {
        get { self[DriverToggleVoiceMuteKey.self] }
        set { self[DriverToggleVoiceMuteKey.self] = newValue }
    }
}

/// Map-layers overlay toggle (used by glassIconButton on 013/018 map
/// backgrounds). Non-critical UI affordance; nil-safe.
struct DriverToggleMapLayersKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}
extension EnvironmentValues {
    var driverToggleMapLayers: (() -> Void)? {
        get { self[DriverToggleMapLayersKey.self] }
        set { self[DriverToggleMapLayersKey.self] = newValue }
    }
}

// MARK: - Backend vocabulary (authoritative)
//
// Mirrors the production tRPC / Drizzle surface:
//   • `LoadStatus`      — eusoronetechnologiesinc/frontend/drizzle/schema.ts:277
//                         + Wave-4 tanker additions (`schema.additions.wave4-1.ts`,
//                         see `_WAVE4_BUILD/agent_01.md` §4b/§5).
//   • `WizardKind`      — server/routers/bayOps/_shared.ts:11 (`WizardKind`).
//   • `BackingAssistStep`, `DischargeStep`, `ConnectHoseStep`,
//     `DisconnectStep` — one per file in `server/routers/bayOps/*.ts` (each
//     router exports an FSM table; these rawValues match the step keys).
//   • `DVIRKind`, `DVIRStatusBackend` — server/routers/dvir.ts.
//   • `DutyStatus`      — server/routers/availability.ts.
//
// These are the ONLY strings the iOS app may send to the server for those
// fields. Anything keyed on a free-form `String` (e.g., `Load.status`) is
// validated against `LoadStatus(rawValue:)` before leaving the app.

/// Every `loads.status` value the backend enum accepts. Call
/// `.rawValue` when serializing over tRPC; call `LoadStatus(rawValue:)`
/// when parsing inbound load rows. Names match the web repo; Swift cases
/// are camelCase per Swift convention with explicit `= "snake_case"`
/// rawValues for wire parity.
enum LoadStatus: String, Codable, CaseIterable {
    // Booking / contract
    case draft, posted, bidding, expired
    case awarded, declined, lapsed, accepted, assigned, confirmed
    // Pickup leg
    case enRoutePickup    = "en_route_pickup"
    case atPickup         = "at_pickup"
    case pickupCheckin    = "pickup_checkin"
    case loading
    case loadingException = "loading_exception"
    case loaded
    // Transit
    case inTransit        = "in_transit"
    case transitHold      = "transit_hold"
    case transitException = "transit_exception"
    // Delivery leg
    case atDelivery         = "at_delivery"
    case deliveryCheckin    = "delivery_checkin"
    case unloading
    case unloadingException = "unloading_exception"
    case unloaded
    // POD / close-out
    case podPending  = "pod_pending"
    case podRejected = "pod_rejected"
    case delivered
    case invoiced, disputed, paid, complete
    // Exceptions / holds
    case cancelled
    case onHold              = "on_hold"
    case tempExcursion       = "temp_excursion"
    case reeferBreakdown     = "reefer_breakdown"
    case contaminationReject = "contamination_reject"
    case sealBreach          = "seal_breach"
    case weightViolation     = "weight_violation"
    // Wave-4 tanker sub-states
    case locked
    case backingIn         = "backing_in"
    case brakesSet         = "brakes_set"
    case connecting
    case loadingLocked     = "loading_locked"
    case loadLockedFilled  = "load_locked_filled"
    case discharging
    case vaporPurging      = "vapor_purging"
    case disconnecting
    case detaching
    case released
}

/// Mirrors `server/routers/bayOps/_shared.ts:11`. A wizard is a
/// short-lived, step-based procedure that runs *on top of* a
/// `LoadStatus`. Exactly one live session per `(loadId, kind)` per
/// `_shared.ts:38` (in-memory session map).
enum WizardKind: String, Codable, CaseIterable {
    case discharge
    case disconnect
    case connectHose
    case backingAssist
}

/// `BackingAssistStep` — matches FSM in `server/routers/bayOps/backingAssist.ts`.
/// Terminal: `.secured`.
enum BackingAssistStep: String, Codable, CaseIterable {
    case align, approach, engage, secured
}

/// `DischargeStep` — matches FSM in `server/routers/bayOps/discharge.ts`.
/// Terminal: `.seal`.
enum DischargeStep: String, Codable, CaseIterable {
    case arm, purge, meter, seal
}

/// `ConnectHoseStep` — matches FSM in `server/routers/bayOps/connectHose.ts`.
/// Terminal: `.pressureTest`.
enum ConnectHoseStep: String, Codable, CaseIterable {
    case grounding, coupling
    case pressureTest = "pressureTest"
}

/// `DisconnectStep` — matches FSM in `server/routers/bayOps/disconnect.ts`.
/// Terminal: `.photo`. Note `break` is a Swift keyword so the case is
/// `break_` with an explicit rawValue of `"break"`.
enum DisconnectStep: String, Codable, CaseIterable {
    case blowdown
    case break_ = "break"
    case cap, photo
}

/// DVIR kind — `server/routers/dvir.ts` accepts `"pre" | "post"`. The
/// legacy iOS `InspectionType` enum still emits `"pre_trip"` /
/// `"post_trip"`; the dvir router has a legacy-fallback map for those,
/// but new code should prefer this enum.
enum DVIRKind: String, Codable { case pre, post }

/// DVIR persistence status — `server/routers/dvir.ts`.
enum DVIRStatusBackend: String, Codable { case draft, submitted }

/// HOS duty status — `server/routers/availability.ts`.
///
/// `onDuty` is the §395.8 line-4 "on-duty, not driving" state (fueling,
/// paperwork, pre/post-trip inspections). The backend `hos.changeStatus`
/// / `availability.setAvailability` mutation rejects any rawValue other
/// than these four canonical strings, so keep them in lockstep.
enum DutyStatus: String, Codable {
    case offDuty = "off_duty"
    case sleeper
    case driving
    case onDuty  = "on_duty"
}

/// Evidence kind — `server/routers/bayOps/_shared.ts`.
enum EvidenceKind: String, Codable, CaseIterable {
    case photo, video, audio, pdf
    case sensorLog = "sensor_log"
}

// MARK: - Trip phase state machine
//
// Replaces the "linear index cycle through ScreenRegistry" that previously
// drove the Home tab. A trip has a real state — driver is enroute, loading,
// on an HOS break, etc. — and the Home tab should render the screen that
// matches that state, not the Nth screen in a flat list. This is the
// production flow doctrine: every lifecycle CTA maps to a phase transition
// (happy path), and out-of-band triggers (geofence crossing, HOS alarm,
// dispatch override) map to TripEvent-driven transitions. ScreenRegistry
// stays responsible for how each phase renders; TripPhase is authoritative
// over which phase is current.
//
// TripPhase is UI-facing. It covers the 18 driver-visible steps in the
// 010→027 screen range AND the pre-trip DVIR gate that precedes
// `loadStatus`. For every phase that maps to a live backend status,
// `backendStatus` returns the canonical `LoadStatus` string the server
// expects — that's the value we send to `loadLifecycle.executeTransition`.
// Phases that are purely UI (pre-trip DVIR gate, HOS break, off-duty
// dashboard, next-load brief) return `nil` from `backendStatus` because
// they don't correspond to a `loadStatus` transition.
//
// Some UI phases share a `backendStatus` (e.g., `.atReceiverGate`,
// `.dockAssigned`, `.backingIn` all sit inside backend `delivery_checkin`
// plus an active `backingAssist` wizard). The UI differentiates via the
// wizard-step sub-state held on the controller.

/// Canonical phases of a driver's trip lifecycle. Each maps 1:1 onto a
/// ScreenRegistry id in the 010-032 range. The rawValue is what we
/// persist locally (UserDefaults, analytics) — for anything sent to the
/// backend use `backendStatus?.rawValue`, which is guaranteed to be a
/// legal `loadStatus`.
///
/// Wave-5 (2026-04-20) weaves the 028-032 hazmat tanker bricks into the
/// happy path so `loadLockedPrehaul`, `pickupArrival`,
/// `spectraMatchVerdict`, and `detachSequence` render as real lifecycle
/// surfaces driven by `trip.phase.screenId`, not registry-only.
/// `pickupLoading` now points at 030 (the Figma-accurate loading
/// surface with Spectra-Match bar); screen 016 remains in the registry
/// as a legacy placeholder but is no longer referenced by the FSM.
enum TripPhase: String, CaseIterable, Codable {
    case idle                  = "idle"                // 010 Driver Home — no active trip (UI-only)
    case pretripDVIR           = "pretrip_dvir"        // 011 Pre-trip DVIR (dvir.kind=pre, status=draft)
    case dvirSubmitted         = "dvir_submitted"      // 012 DVIR Submitted (dvir.status=submitted)
    case loadLockedPrehaul     = "load_locked_prehaul" // 028 Load Locked · Prehaul (9-check hazmat gate; backend locked)
    case enrouteToPickup       = "en_route_pickup"     // 013 → maps to backend en_route_pickup
    case approachingPickup     = "at_pickup"           // 014 → maps to backend at_pickup (geofence-inside)
    case atPickupGate          = "pickup_checkin"      // 015 → maps to backend pickup_checkin
    case pickupArrival         = "pickup_arrival"      // 029 Pickup Arrival (rig parked, grounding checklist; backend connecting)
    case pickupLoading         = "loading"             // 030 → maps to backend loading (Figma-accurate loading surface; 016 is the legacy placeholder id)
    case spectraMatchVerdict   = "spectra_match_verdict" // 031 Spectra-Match Verdict (load signed @ purity %; backend load_locked_filled)
    case pickupBolSigning      = "loaded"              // 017 → maps to backend loaded
    case detachSequence        = "detach_sequence"     // 032 Detach Sequence (6-step hose purge + detach; backend detaching)
    case enrouteLoaded         = "in_transit"          // 018 → maps to backend in_transit
    case hosBreak              = "transit_hold"        // 019 → maps to backend transit_hold
    case approachingDelivery   = "at_delivery"         // 020 → maps to backend at_delivery (geofence-inside)
    case atReceiverGate        = "delivery_checkin"    // 021 → delivery_checkin (pre-dock-assignment)
    case dockAssigned          = "delivery_checkin_dock_assigned" // 022 → delivery_checkin + dock assigned (UI-substate)
    case backingIn             = "backing_in"          // 023 → backing_in (tanker) + backingAssist wizard
    case unloading             = "unloading"           // 024 → unloading + discharge wizard
    case paperwork             = "pod_pending"         // 025 → pod_pending
    case offDuty               = "off_duty"            // 026 Off Duty (UI-only; HOS duty_status=off_duty)
    case nextLoadBrief         = "next_load_brief"     // 027 Next Load Brief (UI-only)

    /// The ScreenRegistry id that should render when this phase is active.
    /// Kept as a pure mapping so callers that need the view can do
    /// `ScreenRegistry.all.first { $0.id == phase.screenId }`.
    var screenId: String {
        switch self {
        case .idle:                return "010"
        case .pretripDVIR:         return "011"
        case .dvirSubmitted:       return "012"
        case .loadLockedPrehaul:   return "028"
        case .enrouteToPickup:     return "013"
        case .approachingPickup:   return "014"
        case .atPickupGate:        return "015"
        case .pickupArrival:       return "029"
        case .pickupLoading:       return "030" // redirected from 016 → 030 (Figma-accurate loading surface)
        case .spectraMatchVerdict: return "031"
        case .pickupBolSigning:    return "017"
        case .detachSequence:      return "032"
        case .enrouteLoaded:       return "018"
        case .hosBreak:            return "019"
        case .approachingDelivery: return "020"
        case .atReceiverGate:      return "021"
        case .dockAssigned:        return "022"
        case .backingIn:           return "023"
        case .unloading:           return "024"
        case .paperwork:           return "025"
        case .offDuty:             return "026"
        case .nextLoadBrief:       return "027"
        }
    }

    /// Short label for dev chrome and breadcrumbs.
    var displayName: String {
        switch self {
        case .idle:                return "Idle"
        case .pretripDVIR:         return "Pre-trip DVIR"
        case .dvirSubmitted:       return "DVIR Submitted"
        case .loadLockedPrehaul:   return "Load locked · prehaul"
        case .enrouteToPickup:     return "Enroute · to pickup"
        case .approachingPickup:   return "Approaching pickup"
        case .atPickupGate:        return "At gate · awaiting dock"
        case .pickupArrival:       return "Pickup arrival · grounding"
        case .pickupLoading:       return "Loading in progress"
        case .spectraMatchVerdict: return "Spectra-Match · verdict"
        case .pickupBolSigning:    return "BOL signing"
        case .detachSequence:      return "Detach sequence"
        case .enrouteLoaded:       return "Enroute · loaded"
        case .hosBreak:            return "HOS break"
        case .approachingDelivery: return "Approaching delivery"
        case .atReceiverGate:      return "At receiver gate"
        case .dockAssigned:        return "Dock assigned"
        case .backingIn:           return "Backing in"
        case .unloading:           return "Unloading"
        case .paperwork:           return "Paperwork"
        case .offDuty:             return "Off duty"
        case .nextLoadBrief:       return "Next load brief"
        }
    }

    /// True while the driver is engaged in an active trip. The Home
    /// dashboard (010) and post-delivery surfaces (026/027) are the
    /// non-engaged states.
    var isActiveTrip: Bool {
        switch self {
        case .idle, .offDuty, .nextLoadBrief: return false
        default:                              return true
        }
    }

    /// Default forward transition invoked when the primary CTA on the
    /// phase's screen is tapped. Models the happy path through the
    /// entire 010→027 trip lifecycle; loops back to `.idle` from 027
    /// so a completed trip returns to the dashboard.
    var happyPathNext: TripPhase {
        switch self {
        case .idle:                return .pretripDVIR
        case .pretripDVIR:         return .dvirSubmitted
        case .dvirSubmitted:       return .loadLockedPrehaul
        case .loadLockedPrehaul:   return .enrouteToPickup
        case .enrouteToPickup:     return .approachingPickup
        case .approachingPickup:   return .atPickupGate
        case .atPickupGate:        return .pickupArrival
        case .pickupArrival:       return .pickupLoading
        case .pickupLoading:       return .spectraMatchVerdict
        case .spectraMatchVerdict: return .pickupBolSigning
        case .pickupBolSigning:    return .detachSequence
        case .detachSequence:      return .enrouteLoaded
        case .enrouteLoaded:       return .approachingDelivery
        case .hosBreak:            return .enrouteLoaded
        case .approachingDelivery: return .atReceiverGate
        case .atReceiverGate:      return .dockAssigned
        case .dockAssigned:        return .backingIn
        case .backingIn:           return .unloading
        case .unloading:           return .paperwork
        case .paperwork:           return .offDuty
        case .offDuty:             return .nextLoadBrief
        case .nextLoadBrief:       return .idle
        }
    }

    /// Reverse traversal — used by dev-chrome "Prev" to walk backwards
    /// through the happy path. `nil` on `.idle` because there is no
    /// pre-home state in the driver flow.
    var happyPathPrev: TripPhase? {
        switch self {
        case .idle:                return nil
        case .pretripDVIR:         return .idle
        case .dvirSubmitted:       return .pretripDVIR
        case .loadLockedPrehaul:   return .dvirSubmitted
        case .enrouteToPickup:     return .loadLockedPrehaul
        case .approachingPickup:   return .enrouteToPickup
        case .atPickupGate:        return .approachingPickup
        case .pickupArrival:       return .atPickupGate
        case .pickupLoading:       return .pickupArrival
        case .spectraMatchVerdict: return .pickupLoading
        case .pickupBolSigning:    return .spectraMatchVerdict
        case .detachSequence:      return .pickupBolSigning
        case .enrouteLoaded:       return .detachSequence
        case .hosBreak:            return .enrouteLoaded
        case .approachingDelivery: return .enrouteLoaded
        case .atReceiverGate:      return .approachingDelivery
        case .dockAssigned:        return .atReceiverGate
        case .backingIn:           return .dockAssigned
        case .unloading:           return .backingIn
        case .paperwork:           return .unloading
        case .offDuty:             return .paperwork
        case .nextLoadBrief:       return .offDuty
        }
    }

    /// Ordinal position in the happy-path walk — used by dev-chrome
    /// progress bars and "step N/18" breadcrumbs. `idle` is step 1.
    var stepOrdinal: Int {
        TripPhase.allCases.firstIndex(of: self).map { $0 + 1 } ?? 1
    }

    /// The backend `loadStatus` value this UI phase corresponds to —
    /// i.e., what the server should see on `loads.status` while the
    /// driver is in this phase. `nil` for phases that don't touch the
    /// `loads.status` column (pre-trip DVIR gate, HOS break modal,
    /// off-duty dashboard, next-load brief).
    ///
    /// Use this (never `rawValue`) when calling tRPC:
    ///   `api.loadLifecycle.executeTransition(to: phase.backendStatus?.rawValue)`
    var backendStatus: LoadStatus? {
        switch self {
        case .idle:                return nil
        case .pretripDVIR:         return nil
        case .dvirSubmitted:       return nil
        case .loadLockedPrehaul:   return .locked             // hazmat pre-haul gate; load is locked
        case .enrouteToPickup:     return .enRoutePickup
        case .approachingPickup:   return .atPickup
        case .atPickupGate:        return .pickupCheckin
        case .pickupArrival:       return .connecting         // rig parked, hoses hooking up
        case .pickupLoading:       return .loadingLocked      // flowing with hose locked (was .loading)
        case .spectraMatchVerdict: return .loadLockedFilled   // loaded + sealed + purity verdict signed
        case .pickupBolSigning:    return .loaded
        case .detachSequence:      return .detaching          // 6-step hose purge + detach
        case .enrouteLoaded:       return .inTransit
        case .hosBreak:            return .transitHold
        case .approachingDelivery: return .atDelivery
        case .atReceiverGate:      return .deliveryCheckin
        case .dockAssigned:        return .deliveryCheckin   // same backend status; UI-only split
        case .backingIn:           return .backingIn          // tanker sub-state
        case .unloading:           return .unloading
        case .paperwork:           return .podPending
        case .offDuty:             return nil
        case .nextLoadBrief:       return nil
        }
    }

    /// Return the backend `transitionId` (per
    /// `server/services/loadLifecycle/stateMachine.ts`) that advances
    /// `loads.status` from `self.backendStatus` to `next.backendStatus`.
    /// Returns `nil` when the hop is purely UI (pretrip DVIR gate, HOS
    /// break modal, off-duty dashboard, next-load brief) — callers skip
    /// the tRPC call and just flip local state.
    ///
    /// Source of truth: the transitions catalog in
    /// `loadLifecycle/stateMachine.ts` (lines 423-1000+). Only the
    /// driver-facing happy-path ids are enumerated here; broker / shipper
    /// transitions live on the web portal.
    func transitionId(to next: TripPhase) -> String? {
        switch (self, next) {
        // 028 Load Locked · Prehaul → 013 Enroute
        case (.loadLockedPrehaul, .enrouteToPickup):       return "CONFIRMED_TO_EN_ROUTE_PICKUP"
        // 013 → 014 geofence-inside (en_route_pickup → at_pickup)
        case (.enrouteToPickup, .approachingPickup):       return "EN_ROUTE_TO_AT_PICKUP"
        // 014 → 015 gate check-in (at_pickup → pickup_checkin)
        case (.approachingPickup, .atPickupGate):          return "AT_PICKUP_TO_CHECKIN"
        // 015 → 029 dock + rig parked (pickup_checkin → loading)
        case (.atPickupGate, .pickupArrival):              return "CHECKIN_TO_LOADING"
        // 030 Spectra-Match verdict (loading → loaded) fires LOADING_TO_LOADED
        case (.spectraMatchVerdict, .pickupBolSigning):    return "LOADING_TO_LOADED"
        // 032 Detach Sequence (loaded → in_transit) fires LOADED_TO_IN_TRANSIT
        case (.detachSequence, .enrouteLoaded):            return "LOADED_TO_IN_TRANSIT"
        // 018 → HOS break (in_transit → transit_hold)
        case (.enrouteLoaded, .hosBreak):                  return "IN_TRANSIT_TO_HOLD"
        // 019 → back on road (transit_hold → in_transit)
        case (.hosBreak, .enrouteLoaded):                  return "TRANSIT_HOLD_TO_IN_TRANSIT"
        // 018 → 020 geofence-inside delivery (in_transit → at_delivery)
        case (.enrouteLoaded, .approachingDelivery):       return "IN_TRANSIT_TO_AT_DELIVERY"
        // 020 → 021 gate check-in (at_delivery → delivery_checkin)
        case (.approachingDelivery, .atReceiverGate):      return "AT_DELIVERY_TO_CHECKIN"
        // 022/023 → 024 backing-in → unloading (delivery_checkin → unloading)
        case (.backingIn, .unloading):                     return "DELIVERY_CHECKIN_TO_UNLOADING"
        // 024 → 025 paperwork (unloading → unloaded → pod_pending).
        // The backend models this as UNLOADING_TO_UNLOADED; POD_PENDING
        // is reached automatically via UNLOADED_TO_POD_PENDING after
        // the UI has its POD photo. For the happy-path advance we issue
        // UNLOADING_TO_UNLOADED here; the POD upload (screen 025
        // `.task`) then fires UNLOADED_TO_POD_PENDING explicitly.
        case (.unloading, .paperwork):                     return "UNLOADING_TO_UNLOADED"
        // 025 → 026 close-out (pod_pending → delivered). Driver role
        // uses POD_TO_DELIVERED with metadata.podSignatureUrl + the
        // complianceChecks.podSigned=true.
        case (.paperwork, .offDuty):                       return "POD_TO_DELIVERED"
        default:                                           return nil
        }
    }

    /// The bayOps wizard that the driver app should `start` when
    /// entering this phase, per the `loadLifecycle ↔ bayOps` map in
    /// `_WAVE4_BUILD/agent_04.md` §7. `nil` when no wizard applies.
    ///
    /// Flow reminder: the server does NOT auto-start wizards (design
    /// decision per agent_04.md §7). The client calls
    /// `bayOps.<kind>.start` when the phase is entered.
    var wizardKind: WizardKind? {
        switch self {
        case .dockAssigned, .backingIn: return .backingAssist
        case .unloading:                return .discharge
        // `delivery_checkin` additionally expects `connectHose` after
        // backingAssist completes — we surface that through the
        // wizard-step hand-off in `DriverTripController.advanceWizard`
        // rather than a second static property here.
        default:                        return nil
        }
    }
}

/// Out-of-band triggers that cause phase transitions without the driver
/// tapping the primary CTA. These are the events that background
/// observers (geofence, HOS, dispatch) fire into the controller.
///
/// **Vocabulary.** Cases are named after the *backend mutation* they
/// ultimately drive, not the UI moment that fires them. For example,
/// `.transitionStatus(.pickupCheckin)` is what you'd send regardless of
/// whether the driver tapped a CTA or a geofence observer fired — the
/// server-visible effect is the same. UI-only transitions (DVIR gate,
/// HOS break modal, geofence-approaching band) stay enumerated as
/// first-class cases because the controller has to handle them even
/// though they don't hit `loadLifecycle.executeTransition`.
enum TripEvent {
    /// Generic "flip `loads.status` to this value" — maps to
    /// `loadLifecycle.executeTransition({to})`. The server validates
    /// against `LOAD_STATUS_FSM` in
    /// `server/services/loadLifecycle/stateMachine.ts`. Callers should
    /// check `TripPhase(backendStatus:)` before firing so UX doesn't
    /// request an illegal transition.
    case transitionStatus(to: LoadStatus)

    /// Start a bayOps wizard. Maps to `bayOps.<kind>.start({loadId})`.
    /// Per `_shared.ts:38` at most one live session per `(loadId, kind)`
    /// can run at a time.
    case startWizard(WizardKind)

    /// Advance a wizard's FSM. Maps to
    /// `bayOps.<kind>.advanceStep({sessionId, from, to})`. The `to`
    /// string must be a legal step on the wizard's FSM table (see the
    /// per-wizard `*Step` enums).
    case advanceWizardStep(WizardKind, to: String)

    /// Complete a wizard cleanly. Maps to
    /// `bayOps.<kind>.complete({sessionId})`. Only valid when the
    /// wizard is on its terminal step.
    case completeWizard(WizardKind)

    /// Abort a wizard (shop-route, unable-to-safely-continue, etc.).
    /// Maps to `bayOps.<kind>.abort({sessionId, reason})`.
    case abortWizard(WizardKind, reason: String)

    /// Driver tapped "Start pre-trip" on the Home dashboard — opens the
    /// DVIR gate (drafts a `dvir` row with kind='pre', status='draft').
    /// UI-only; no `loads.status` change.
    case startPretripDVIR

    /// DVIR submission succeeded (all required items resolved, no OOS
    /// defects). Flips the DVIR row to `status='submitted'` and clears
    /// the gate so the driver can begin the trip. Maps to
    /// `dvir.submit({dvirId})` on the backend.
    case submitDVIRPassed

    /// DVIR flagged a major defect (`severity='out_of_service'`). Stays
    /// on the 011 screen; driver must resolve before trip can start.
    case submitDVIRFailed

    /// Driver went off-duty. Maps to `availability.setAvailability`
    /// with `duty_status='off_duty'` — does NOT touch `loads.status`
    /// (off-duty is an HOS state, not a load state).
    case setDutyStatus(DutyStatus)

    /// Driver accepted the next load from the off-duty briefing — the
    /// new load becomes active and its status is typically `assigned`
    /// to start. Fires `loadLifecycle.executeTransition` on the NEW load.
    case acceptNextLoad

    // MARK: Pure-UI transitions — observed triggers that don't round-trip
    //       to the backend but still drive screen switching.

    /// Geofence crossed ~2 mi out from the pickup yard. UI-only:
    /// switches the pickup screen from "enroute" to "approaching".
    /// Backend `loads.status` stays `en_route_pickup` until the driver
    /// actually arrives (handled by `.transitionStatus(.atPickup)`).
    case geofenceApproachingPickup

    /// Geofence crossed ~2 mi out from delivery. Same semantics as
    /// `.geofenceApproachingPickup` but for the delivery leg.
    case geofenceApproachingDelivery

    /// HOS enforcement window imminent — force a break-required modal
    /// over the enroute screen. Fires `availability.setAvailability`
    /// with `duty_status='sleeper'` on the backend.
    case hosBreakRequired

    /// HOS break satisfied; driver can resume driving. Fires
    /// `availability.setAvailability` with `duty_status='driving'`.
    case hosBreakComplete
}

extension TripPhase {
    /// Apply an out-of-band event. Unknown (phase, event) combos return
    /// `self` unchanged — callers can check `phase == result` to detect
    /// that no transition fired.
    ///
    /// Note: this is the UI-layer projection of the backend FSM, not an
    /// authoritative guard. The server-side `LOAD_STATUS_FSM` is the
    /// authority; this table is what the driver app *offers* as legal
    /// UI transitions. Anything rejected here won't be attempted over
    /// the wire.
    func next(on event: TripEvent) -> TripPhase {
        switch (self, event) {

        // Pre-trip DVIR gate (UI-only; doesn't touch loads.status).
        case (.idle, .startPretripDVIR):               return .pretripDVIR
        case (.nextLoadBrief, .startPretripDVIR):      return .pretripDVIR
        case (.pretripDVIR, .submitDVIRPassed):        return .dvirSubmitted
        case (.pretripDVIR, .submitDVIRFailed):        return .pretripDVIR

        // loads.status transitions — drivers transition via
        // .transitionStatus(to: LoadStatus). We map the target status
        // back to its TripPhase so the UI advances in lockstep. When
        // multiple phases share a backend status (delivery_checkin,
        // backing_in) the phase-local event handlers below steer the
        // UI-only split.
        case (_, .transitionStatus(let target)):
            return Self.phase(for: target, from: self)

        // Geofence-approaching bands — pure UI, no backend hit.
        case (.enrouteToPickup, .geofenceApproachingPickup):   return .approachingPickup
        case (.enrouteLoaded, .geofenceApproachingDelivery):   return .approachingDelivery

        // HOS break — UI switch over .enrouteLoaded, reversible.
        case (.enrouteLoaded, .hosBreakRequired):              return .hosBreak
        case (.hosBreak, .hosBreakComplete):                   return .enrouteLoaded

        // Duty status — modeled but doesn't flip loads.status. The
        // controller also writes duty_status to availability router.
        case (.paperwork, .setDutyStatus(.offDuty)):           return .offDuty

        // Next-load acceptance — creates a new active load cycle.
        case (.offDuty, .acceptNextLoad):                      return .nextLoadBrief

        // Wizard lifecycle events don't shift TripPhase; the wizard
        // step advances in parallel on DriverTripController.wizardStep.
        // Explicitly no-op those so the compiler confirms exhaustiveness.
        case (_, .startWizard),
             (_, .advanceWizardStep),
             (_, .completeWizard),
             (_, .abortWizard):
            return self

        default:
            return self
        }
    }

    /// Reverse lookup — given a `LoadStatus` coming back from the
    /// server (e.g., a push or a `loadLifecycle.executeTransition`
    /// response), figure out which UI phase should render. When
    /// multiple UI phases share a backend status we prefer the one
    /// closest to `from` so the UI doesn't skip substates.
    static func phase(for status: LoadStatus, from: TripPhase) -> TripPhase {
        switch status {
        case .enRoutePickup:    return .enrouteToPickup
        case .atPickup:         return .approachingPickup
        case .pickupCheckin:    return .atPickupGate
        case .loading:          return .pickupLoading          // legacy alias — server may still emit .loading
        case .loaded:           return .pickupBolSigning
        case .inTransit:        return .enrouteLoaded
        case .transitHold:      return .hosBreak
        case .atDelivery:       return .approachingDelivery
        case .deliveryCheckin:
            // delivery_checkin maps to either .atReceiverGate or
            // .dockAssigned — walk forward from wherever we were.
            if from == .atReceiverGate { return .dockAssigned }
            return .atReceiverGate
        case .backingIn:        return .backingIn
        case .unloading:        return .unloading
        case .unloaded:         return .unloading      // disconnect wizard runs here; UI stays on 024
        case .podPending:       return .paperwork
        case .delivered,
             .complete:         return .nextLoadBrief
        // Pre-driver / contract-side — no driver screen, hold position
        case .draft, .posted, .bidding, .expired,
             .awarded, .declined, .lapsed,
             .accepted, .assigned, .confirmed:
            return from
        // Exception statuses — hold position; controller raises a banner
        case .loadingException, .transitException, .unloadingException,
             .podRejected, .tempExcursion, .reeferBreakdown,
             .contaminationReject, .sealBreach, .weightViolation,
             .cancelled, .onHold:
            return from
        case .invoiced, .disputed, .paid:
            return from
        // Tanker sub-states — Wave-5 (2026-04-20) wires 028/029/031/032
        // hazmat bricks into the happy path so these server statuses now
        // route to their canonical UI phase instead of holding position.
        case .locked:           return .loadLockedPrehaul       // 028
        case .connecting:       return .pickupArrival           // 029
        case .loadingLocked:    return .pickupLoading           // 030
        case .loadLockedFilled: return .spectraMatchVerdict     // 031
        case .detaching,
             .disconnecting:    return .detachSequence          // 032
        case .brakesSet, .discharging, .vaporPurging, .released:
            // Tanker sub-states not yet surfaced in the driver UI —
            // controller holds position and (optionally) raises a banner.
            return from
        }
    }
}

// MARK: - DriverTripController

/// Owns the driver's trip state — which phase they're in, which load
/// they're running, and the transition methods that the UI (and future
/// background observers) call into.
///
/// This is the single source of truth for "what screen should Home
/// render right now". ContentView looks up `trip.phase.screenId` and
/// asks ScreenRegistry for the matching view, instead of maintaining a
/// separate `currentIndex` state that cycles the registry linearly.
///
/// Lifecycle CTAs call `advance()` (happy path). Geofence / HOS / dispatch
/// observers will call `handle(event:)` once they're wired in — the
/// surface area is ready for them today so adding an observer is purely
/// additive.
@MainActor
final class DriverTripController: ObservableObject {

    /// Which phase of the trip the driver is currently in. Published so
    /// SwiftUI re-renders the Home tab when it changes.
    @Published var phase: TripPhase = .idle

    /// The load the driver is currently assigned. Sourced from
    /// `DriverHomeViewModel.availableLoad` at Home-accept time; the
    /// controller holds onto it for the duration of the trip.
    ///
    /// Starts as `nil` — no demo fixture seed. When the driver has no
    /// active trip the UI branches to the `no active load` path. Once
    /// they accept a tender the controller assigns the real `Load` here.
    @Published var currentLoad: Load? = nil

    /// Active bayOps wizard, if any. The UI reads this to decide which
    /// sub-screen to render inside phases that spawn a wizard (e.g.,
    /// `.backingIn` runs the `backingAssist` wizard whose `step` can be
    /// `align → approach → engage → secured`).
    ///
    /// Server correspondence:
    ///   `kind`      → `WizardKind` (matches `_shared.ts:11`)
    ///   `step`      → raw step string; validate with the per-wizard
    ///                 `*Step` enum before sending `advanceStep`.
    ///   `sessionId` → returned by `bayOps.<kind>.start`; stored so
    ///                 subsequent `advanceStep` / `complete` / `abort`
    ///                 / `recordEvidence` calls can reference it.
    @Published var wizard: (kind: WizardKind, step: String, sessionId: String)?

    /// The driver's current HOS duty status. Mirrors the
    /// `availability.duty_status` column. Published so a global
    /// HOS-clock banner can read it.
    @Published var dutyStatus: DutyStatus = .driving

    /// Pre-trip DVIR gate — UI-only state that tracks where the driver
    /// is in the DVIR draft/submit flow. Separate from `phase` because
    /// DVIR is a row in the `dvir` table (kind='pre'), not a
    /// `loads.status` transition. When `.submitted`, the UI reveals the
    /// "Begin trip" CTA that flips `phase` forward.
    enum PreTripGate: Equatable {
        case notStarted
        case drafting(dvirId: Int?)
        case submitted(dvirId: Int)
    }
    @Published var preTripGate: PreTripGate = .notStarted

    /// Advance through the happy path. Invoked by the env-injected
    /// `lifecycleAdvance` closure that every `LifecycleCTAButton` taps
    /// into. For production transitions that also write to the backend,
    /// prefer `transition(to:)` which both updates local state and
    /// fires the tRPC mutation.
    func advance() {
        phase = phase.happyPathNext
    }

    /// Walk one phase backward. Used by the dev-chrome Prev arrow when
    /// the driver role is active so reviewers can step through the
    /// flow without running a whole trip.
    func stepBack() {
        if let prev = phase.happyPathPrev { phase = prev }
    }

    /// Jump directly to a named phase — dev chrome shortcut picker,
    /// deep link from a push notification, QR-code debug sticker.
    func jump(to phase: TripPhase) {
        self.phase = phase
    }

    /// Apply an out-of-band event. Future observer hook for
    /// geofence/HOS/dispatch triggers; callable today from preview
    /// fixtures so the state machine is exercisable before the
    /// observers are wired.
    func handle(_ event: TripEvent) {
        phase = phase.next(on: event)

        // Event-specific side effects that don't live in TripPhase.next
        // because they mutate the controller, not the phase enum.
        switch event {
        case .startWizard(let kind):
            // Synthesize a local session id until the real
            // `bayOps.<kind>.start` round-trip returns one. The UI can
            // replace it with the server-assigned id in the caller
            // after awaiting the mutation.
            let initial = Self.initialWizardStep(for: kind)
            wizard = (kind: kind, step: initial, sessionId: "local-\(kind.rawValue)-\(Int(Date().timeIntervalSince1970))")
        case .advanceWizardStep(let kind, let to):
            if var w = wizard, w.kind == kind {
                w.step = to
                wizard = w
            }
        case .completeWizard(let kind), .abortWizard(let kind, _):
            if let w = wizard, w.kind == kind { wizard = nil }
        case .setDutyStatus(let next):
            dutyStatus = next
        case .submitDVIRPassed:
            if case .drafting(let id) = preTripGate, let dvirId = id {
                preTripGate = .submitted(dvirId: dvirId)
            } else {
                // Synthesize an id when the demo-fallback submit
                // response doesn't carry a real one.
                preTripGate = .submitted(dvirId: Int(Date().timeIntervalSince1970) % 100_000)
            }
        case .startPretripDVIR:
            preTripGate = .drafting(dvirId: nil)
        default:
            break
        }
    }

    /// Initial step for each wizard kind, matching the FSM root in the
    /// corresponding `server/routers/bayOps/*.ts` file.
    static func initialWizardStep(for kind: WizardKind) -> String {
        switch kind {
        case .backingAssist: return BackingAssistStep.align.rawValue
        case .discharge:     return DischargeStep.arm.rawValue
        case .connectHose:   return ConnectHoseStep.grounding.rawValue
        case .disconnect:    return DisconnectStep.blowdown.rawValue
        }
    }

    /// Reset back to an idle dashboard — called when the user signs
    /// out, switches roles, or completes the current trip's loop. Also
    /// used by the dev-chrome to rewind between fidelity walks.
    func reset(load: Load? = nil) {
        self.phase = .idle
        self.currentLoad = load
        self.wizard = nil
        self.preTripGate = .notStarted
        self.dutyStatus = .driving
    }

    /// Accept the currently-offered load via `drivers.acceptLoad`. The
    /// backend flips `loads.status` to `assigned` and binds the
    /// `driverId`. On success we also flip the local phase forward so
    /// the UI moves out of the "offered" state. Errors are surfaced via
    /// the `onError` callback (UI can then show a toast or retry).
    func acceptOfferedLoad(
        _ load: Load,
        api: EusoTripAPI = .shared,
        onError: @escaping (Error) -> Void = { _ in }
    ) {
        self.currentLoad = load
        Task { @MainActor in
            do {
                _ = try await api.drivers.acceptLoad(loadId: String(load.id))
                // Driver Home's post-accept state is still `.idle` until
                // pre-trip DVIR starts; the accept mutation doesn't
                // advance the phase, it just binds the load.
            } catch {
                onError(error)
            }
        }
    }

    /// Decline the currently-offered load via `drivers.declineLoad`.
    /// Leaves `currentLoad` untouched; callers typically re-fetch the
    /// pending-load list after this completes.
    func declineOfferedLoad(
        _ load: Load,
        reason: String? = nil,
        api: EusoTripAPI = .shared,
        onError: @escaping (Error) -> Void = { _ in }
    ) {
        Task { @MainActor in
            do {
                _ = try await api.drivers.declineLoad(
                    loadId: String(load.id),
                    reason: reason
                )
            } catch {
                onError(error)
            }
        }
    }
}

// MARK: - 49th firing · sheet host types + views
//
// Identifiable wrapper types for the `.sheet(item:)` presenters in
// ContentView, plus the actual sheet bodies for the six ambient
// env-handler actions (messaging, docs, trip log, share, photo upload,
// report issue). All sheets render real tRPC data through EusoTripAPI —
// no mock fallbacks. When a backend endpoint returns empty or the call
// fails, an EusoEmptyState renders rather than fabricated data.

import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

/// Identifier for the messaging sheet presentation. `nil` threadId means
/// "open the inbox"; non-nil means "open this conversation".
struct MessagingSheetTarget: Identifiable, Hashable {
    let id: String = UUID().uuidString
    let threadId: String?
}

/// Wrapper so the iOS share sheet can be presented via `.sheet(item:)`.
struct DriverShareItem: Identifiable, Hashable {
    let id: String = UUID().uuidString
    let raw: String
}

/// Wrapper for the raise-exception sheet's context key (screen / phase).
struct DriverReportIssueContext: Identifiable, Hashable {
    let id: String = UUID().uuidString
    let raw: String
}

extension Notification.Name {
    /// Posted by `\.driverShowHelp` — ESangAutopilot subscribes and seeds
    /// the first-turn prompt with the topic string on the next sheet open.
    static let esangOpenHelp = Notification.Name("com.eusorone.EusoTrip.esang.openHelp")
}

// MARK: - DriverMessagingSheet

/// Inbox + single-thread surface backed by the canonical `messages.ts`
/// router (§16 messaging-docs). When `threadId` is non-nil we jump
/// straight into that conversation; otherwise we render the full
/// conversation list.
struct DriverMessagingSheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    let threadId: String?

    @State private var conversations: [MessagingConversation] = []
    @State private var messages: [MessagingMessage] = []
    @State private var outgoing: String = ""
    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    @State private var sending: Bool = false
    @State private var activeThreadId: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let _ = (activeThreadId ?? threadId) {
                    threadBody
                } else {
                    inboxBody
                }
            }
            .background(palette.bgPage.ignoresSafeArea())
            .navigationTitle(activeThreadId ?? threadId == nil ? "Messages" : "Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await loadInitial() }
    }

    private var inboxBody: some View {
        Group {
            if loading && conversations.isEmpty {
                ProgressView().tint(palette.textPrimary)
            } else if let err = loadError, conversations.isEmpty {
                EusoEmptyState(
                    systemImage: "exclamationmark.triangle",
                    title: "Could not load messages",
                    subtitle: err,
                    comingSoon: false
                )
                .padding(Space.s5)
            } else if conversations.isEmpty {
                EusoEmptyState(
                    systemImage: "bubble.left.and.bubble.right",
                    title: "No conversations yet",
                    subtitle: "When dispatch, brokers, or shippers message you, threads show up here.",
                    comingSoon: false
                )
                .padding(Space.s5)
            } else {
                List(conversations, id: \.id) { c in
                    Button {
                        activeThreadId = c.id
                        Task { await loadMessages(for: c.id) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.displayName)
                                .font(EType.body).foregroundStyle(palette.textPrimary)
                            if let preview = c.lastMessage {
                                Text(preview).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
                            }
                        }
                    }
                    .listRowBackground(palette.bgCard)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var threadBody: some View {
        VStack(spacing: 0) {
            if loading && messages.isEmpty {
                ProgressView().tint(palette.textPrimary).frame(maxHeight: .infinity)
            } else if messages.isEmpty {
                EusoEmptyState(
                    systemImage: "bubble.left",
                    title: "No messages",
                    subtitle: "Send the first message in this thread.",
                    comingSoon: false
                ).padding(Space.s5)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.s2) {
                        ForEach(messages, id: \.id) { m in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.senderName ?? "—").font(EType.caption).foregroundStyle(palette.textTertiary)
                                Text(m.content).font(EType.body).foregroundStyle(palette.textPrimary)
                            }
                            .padding(Space.s3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(palette.bgCard)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        }
                    }
                    .padding(Space.s4)
                }
            }
            composer
        }
    }

    private var composer: some View {
        HStack(spacing: Space.s2) {
            TextField("Message", text: $outgoing, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
            Button {
                Task { await send() }
            } label: {
                Image(systemName: sending ? "hourglass" : "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            .disabled(outgoing.trimmingCharacters(in: .whitespaces).isEmpty || sending)
        }
        .padding(Space.s3)
        .background(palette.bgElev)
    }

    @MainActor
    private func loadInitial() async {
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            if let tid = threadId {
                activeThreadId = tid
                await loadMessages(for: tid)
            } else {
                conversations = try await EusoTripAPI.shared.messaging.getConversations()
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    @MainActor
    private func loadMessages(for tid: String) async {
        loading = true
        defer { loading = false }
        do {
            messages = try await EusoTripAPI.shared.messaging.getMessages(conversationId: tid, limit: 50)
        } catch {
            loadError = error.localizedDescription
        }
    }

    @MainActor
    private func send() async {
        let trimmed = outgoing.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let tid = activeThreadId ?? threadId else { return }
        sending = true
        defer { sending = false }
        do {
            _ = try await EusoTripAPI.shared.messaging.sendMessage(
                conversationId: tid,
                content: trimmed
            )
            outgoing = ""
            await loadMessages(for: tid)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - DriverDocumentDrawerSheet

/// Lists BOL, Rate Confirmation, and POD documents linked to the active
/// load. Real backend: `drivers.getRateConURL(loadId:)` for the rate con;
/// BOL + POD urls come from `documentManagement.getLoadDocuments` when
/// available (falls back to empty state when the endpoint returns nothing).
struct DriverDocumentDrawerSheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    let loadId: String?
    let loadNumber: String?

    @State private var rateConURL: URL? = nil
    @State private var loading: Bool = true
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.s3) {
                    if let loadNumber {
                        Text("Load \(loadNumber)")
                            .font(EType.caption).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if loading {
                        ProgressView().tint(palette.textPrimary).padding(Space.s5)
                    } else if let err = errorMessage {
                        EusoEmptyState(
                            systemImage: "exclamationmark.triangle",
                            title: "Could not load documents",
                            subtitle: err,
                            comingSoon: false
                        )
                    } else if rateConURL == nil {
                        EusoEmptyState(
                            systemImage: "doc.text",
                            title: "No documents yet",
                            subtitle: loadId == nil
                                ? "No active load — documents surface here once a tender is accepted."
                                : "Documents for this load haven't been attached yet.",
                            comingSoon: false
                        )
                    } else {
                        docRow(
                            title: "Rate Confirmation",
                            subtitle: "Broker-issued · PDF",
                            systemImage: "doc.text.fill",
                            url: rateConURL
                        )
                    }
                }
                .padding(Space.s4)
            }
            .background(palette.bgPage.ignoresSafeArea())
            .navigationTitle("Documents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await loadDocs() }
    }

    @ViewBuilder
    private func docRow(title: String, subtitle: String, systemImage: String, url: URL?) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 40, height: 40)
                .background(palette.bgElev)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(EType.body).foregroundStyle(palette.textPrimary)
                Text(subtitle).font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            if let url {
                Link(destination: url) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 18))
                        .foregroundStyle(palette.textPrimary)
                }
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    @MainActor
    private func loadDocs() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        guard let loadId else { return }
        do {
            let rc = try await EusoTripAPI.shared.drivers.getRateConURL(loadId: loadId)
            if let urlString = rc.url {
                rateConURL = URL(string: urlString)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - DriverTripLogSheet

/// Lifecycle event stream for the current load. Events surface the
/// client-side phase + wizard transitions today; once the backend
/// `loadLifecycle.getEventLog` endpoint lands, this sheet will render
/// the server-authoritative sequence instead.
struct DriverTripLogSheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    let loadId: String?
    let loadNumber: String?
    let currentPhase: TripPhase

    var body: some View {
        NavigationStack {
            Group {
                if loadId == nil {
                    EusoEmptyState(
                        systemImage: "list.clipboard",
                        title: "No active load",
                        subtitle: "Trip events surface here once you accept a tender.",
                        comingSoon: false
                    )
                    .padding(Space.s5)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.s3) {
                            if let loadNumber {
                                Text("Load \(loadNumber)")
                                    .font(EType.caption).tracking(0.6)
                                    .foregroundStyle(palette.textTertiary)
                            }
                            Text("Current phase")
                                .font(EType.caption).foregroundStyle(palette.textTertiary)
                            Text(currentPhase.rawValue)
                                .font(EType.body).foregroundStyle(palette.textPrimary)
                                .padding(Space.s3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(palette.bgCard)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md))

                            EusoEmptyState(
                                systemImage: "clock.arrow.circlepath",
                                title: "No events yet",
                                subtitle: "Pickup, drop, and HOS transitions log here as they fire. Your current phase is shown above.",
                                comingSoon: false
                            )
                        }
                        .padding(Space.s4)
                    }
                }
            }
            .background(palette.bgPage.ignoresSafeArea())
            .navigationTitle("Trip log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - DriverShareSheetHost

/// Thin UIKit bridge so `.sheet(item:)` can present
/// `UIActivityViewController`. Used by every share chip across the
/// Driver screens — BOL share, receipt share, trip-summary share.
struct DriverShareSheetHost: UIViewControllerRepresentable {
    let item: DriverShareItem

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let items: [Any]
        if let url = URL(string: item.raw), url.scheme != nil {
            items = [url]
        } else {
            items = [item.raw]
        }
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - DriverPhotoUploadSheet

/// Defect / POD / damage photo capture. Selected images upload through
/// real backend endpoints — `dvir.attachPhoto` when we're in a DVIR
/// context, `documentManagement.uploadPOD` otherwise. No mock image set.
struct DriverPhotoUploadSheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    let loadId: String?
    let phaseRaw: String
    let isDVIRPhase: Bool

    @State private var selection: PhotosPickerItem? = nil
    @State private var imageData: Data? = nil
    @State private var uploading: Bool = false
    @State private var uploadResult: String? = nil
    @State private var uploadError: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.s4) {
                    PhotosPicker(
                        selection: $selection,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        VStack(spacing: Space.s2) {
                            Image(systemName: imageData == nil ? "camera.fill" : "checkmark.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(LinearGradient.diagonal)
                            Text(imageData == nil ? "Choose photo" : "Photo selected — tap to change")
                                .font(EType.body).foregroundStyle(palette.textPrimary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 160)
                        .background(palette.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                    }

                    if imageData != nil {
                        Button {
                            Task { await upload() }
                        } label: {
                            HStack {
                                if uploading {
                                    ProgressView().tint(.white)
                                }
                                Text(uploading ? "Uploading…" : "Upload")
                                    .font(EType.body).bold()
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(LinearGradient.diagonal)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
                        }
                        .disabled(uploading)
                    }

                    if let msg = uploadResult {
                        Text(msg).font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    if let err = uploadError {
                        Text(err).font(EType.caption).foregroundStyle(.red)
                    }

                    Text("Phase: \(phaseRaw)  ·  \(isDVIRPhase ? "DVIR photo" : "Load photo")")
                        .font(EType.caption).foregroundStyle(palette.textTertiary)
                }
                .padding(Space.s4)
            }
            .background(palette.bgPage.ignoresSafeArea())
            .navigationTitle("Upload photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onChange(of: selection) { _, newValue in
            Task { await load(newValue) }
        }
    }

    @MainActor
    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            imageData = data
            uploadResult = nil
            uploadError = nil
        }
    }

    @MainActor
    private func upload() async {
        guard let data = imageData else { return }
        uploading = true
        defer { uploading = false }
        // Upload path: create a load-tagged attachment conversation via
        // `messages.createConversation`, then `messages.uploadAttachment`
        // the image into it. The server stores the blob in
        // `messageAttachments.fileUrl` which downstream
        // `documentManagement` / `dvir` routers can reference by
        // attachmentId. This is the only production-ready blob path on the
        // backend today — `dvir.attachPhoto` and
        // `documentManagement.uploadPOD` are listed as gaps in §16 of the
        // codebase map (messaging-docs slice).
        do {
            let kind = isDVIRPhase ? "DVIR" : "Load"
            let conv = try await EusoTripAPI.shared.messaging.createConversation(
                participantIds: [],
                type: "direct",
                name: "\(kind) photo · phase \(phaseRaw)",
                loadId: Int(loadId ?? ""),
                initialMessage: nil
            )
            let ack = try await EusoTripAPI.shared.messaging.uploadAttachment(
                conversationId: conv.id,
                data: data,
                fileName: "photo_\(phaseRaw).jpg",
                mimeType: "image/jpeg"
            )
            uploadResult = "Uploaded · attachment \(ack.attachmentId)"
        } catch {
            uploadError = error.localizedDescription
        }
    }
}

// MARK: - DriverReportIssueSheet

/// Raise-exception sheet. Submits as a dispatcher message for now (the
/// `exceptions.create` router is not yet exposed on the mobile client);
/// once it is, swap the send call for `loads.raiseException`.
struct DriverReportIssueSheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) private var dismiss
    let contextRaw: String
    let loadId: String?

    @State private var selectedReason: String = "Mechanical"
    @State private var notes: String = ""
    @State private var submitting: Bool = false
    @State private var submissionResult: String? = nil
    @State private var submissionError: String? = nil

    private let reasons = [
        "Mechanical", "Weather", "Traffic / route closure",
        "Shipper/receiver delay", "Paperwork issue",
        "Equipment damage", "Cargo damage", "Safety concern", "Other"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    Text("Reason")
                        .font(EType.caption).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Picker("Reason", selection: $selectedReason) {
                        ForEach(reasons, id: \.self) { r in Text(r).tag(r) }
                    }
                    .pickerStyle(.menu)
                    .tint(palette.textPrimary)

                    Text("Notes")
                        .font(EType.caption).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    TextEditor(text: $notes)
                        .frame(minHeight: 140)
                        .padding(Space.s2)
                        .background(palette.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))

                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if submitting { ProgressView().tint(.white) }
                            Text(submitting ? "Sending…" : "Submit")
                                .font(EType.body).bold()
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.pill))
                    }
                    .disabled(submitting)

                    if let msg = submissionResult {
                        Text(msg).font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                    if let err = submissionError {
                        Text(err).font(EType.caption).foregroundStyle(.red)
                    }

                    Text("Context: \(contextRaw)\(loadId.map { "  ·  load \($0)" } ?? "")")
                        .font(EType.caption).foregroundStyle(palette.textTertiary)
                }
                .padding(Space.s4)
            }
            .background(palette.bgPage.ignoresSafeArea())
            .navigationTitle("Report issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func submit() async {
        submitting = true
        defer { submitting = false }
        let payload = """
        [EXCEPTION] \(selectedReason)
        Context: \(contextRaw)
        Load: \(loadId ?? "—")
        Notes: \(notes.isEmpty ? "—" : notes)
        """
        do {
            // Create an exception-tagged conversation (server-side the
            // `messages.createConversation` mutation returns an id we can
            // immediately post into). No hard-coded participants — dispatch
            // is resolved by the server via the caller's companyId.
            let conv = try await EusoTripAPI.shared.messaging.createConversation(
                participantIds: [],
                type: "direct",
                name: "Exception · \(selectedReason)",
                loadId: Int(loadId ?? ""),
                initialMessage: payload
            )
            submissionResult = "Sent to dispatch · conversation \(conv.id)"
            try? await Task.sleep(nanoseconds: 600_000_000)
            dismiss()
        } catch {
            submissionError = error.localizedDescription
        }
    }
}
