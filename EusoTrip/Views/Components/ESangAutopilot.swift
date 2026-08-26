//
//  eSangAutopilot.swift
//  EusoTrip — ESANG autopilot protocol (iOS implementation)
//
//  ESANG is EusoTrip's in-cab copilot. In addition to answering questions,
//  ESANG can drive the UI on the driver's behalf: the assistant reply can
//  carry inline commands the client parses and executes — "take me to the
//  marketplace" → ESANG replies "Sure, opening Eusoboards…" followed by a
//  `<<<ACTION:navigate:/marketplace>>>` token that the client converts into
//  a real tab switch.
//
//  Protocol:
//
//      <<<ACTION:<verb>:<arg>>>>
//
//  Verbs currently recognized (web parity):
//    navigate:<path>         Drive the surface to <path>. On the DRIVER
//                            surface the path collapses onto a BottomNav
//                            tab; on every OTHER role the raw path is
//                            resolved against that role's push-nav
//                            registry by `eSangRoleDispatcher` (so
//                            `/dispatch/planner`, `/shipper/settlements`,
//                            `/rail/marketplace` actually land in-role).
//    open-chat               Expand the ESANG coach sheet (no-op when
//                            already open; kept for web parity).
//    close-chat              Dissolve the ESANG coach sheet.
//    back                    Pop one level off the role's push-nav stack.
//    select:<loadId>         Present a Load Detail surface for the id.
//    refresh                 Re-run the current surface's loader.
//    execute:<key>           Fire a server-named CTA on the active surface
//    smart_assign / accept   (e.g. accept-load, smart_assign). Verb-as-key
//      / approve / confirm    forms are also accepted.
//    autopilot               Enter hands-free autopilot mode.
//    undo_all                Reverse the last autopilot-applied action(s).
//
//  Role-aware dispatch:
//    `eSangRoleDispatcher.dispatch(_:role:dismissSheet:)` converts a
//    parsed action into the right push-nav notification for the signed-in
//    role (Shipper/Carrier/Broker/Escort/Terminal/Admin/Dispatch/
//    Compliance/Rail/Vessel), RBAC-gated. The Driver surface keeps its
//    own typed `eSangRoute` → `currentTab` handler in ContentView.
//
//  Navigation paths understood:
//    /, /home, /dashboard         → Home
//    /marketplace, /eusoboards,
//    /loads/search, /trips        → Trips (Eusoboards)
//    /loads, /my-loads            → My Loads
//    /me, /profile, /account      → Me
//    /esang, /copilot, /chat      → ESANG coach (opens the sheet)
//
//  The parser is deliberately forgiving — trailing query strings, trailing
//  slashes, and case are all normalized before lookup. Unknown paths return
//  `nil` and the client does nothing (the stripped reply text still renders,
//  so the driver isn't left confused).
//
//  Powered by ESANG AI™.
//

import Foundation
import SwiftUI

// MARK: - Intent enum

/// A parsed, client-recognized ESANG action. Unrecognized verbs, or verbs
/// whose argument doesn't map to an iOS surface, are never constructed —
/// the parser returns `nil` in that case.
enum eSangAction: Equatable {
    /// Switch the BottomNav to a top-level tab. DRIVER-surface typed
    /// route — the Driver surface owns `DriverNavController` tabs and
    /// resolves these to a `currentTab` flip + optional Me deep-link.
    case navigate(eSangRoute)
    /// Role-agnostic navigation by raw server SPA path (`/shipper/loads`,
    /// `/dispatch/planner`, `/rail/marketplace`, …). Carries the path
    /// verbatim so `eSangRoleDispatcher` can resolve it against the
    /// SIGNED-IN role's push-nav registry instead of collapsing it onto
    /// a Driver tab. The web/voice server emits role-prefixed SPA paths;
    /// this is the action that lets a Shipper / Carrier / Dispatcher /
    /// Rail / Vessel / etc. command actually drive THEIR surface.
    case navigatePath(String)
    /// Open the ESANG coach sheet. Web-side only fires this from outside
    /// the sheet; iOS ignores it when the sheet is already up.
    case openChat
    /// Dissolve the ESANG coach sheet back to the orb.
    case closeChat
    /// Present the Load Detail sheet for a specific load.
    case selectLoad(String)
    /// Re-run the current surface's loader (pull-to-refresh equivalent).
    case refresh
    /// Pop one level off the current role's push-nav stack (the
    /// `BespokeBackBar` / surface back-overlay equivalent). Maps onto
    /// the role's NavBack notification.
    case back
    /// Execute a server-named action on the current surface (e.g.
    /// `accept-load`, `smart-assign`, `approve-settlement`). The arg is
    /// the action key the destination surface listens for; we broadcast
    /// it as a role-scoped notification so a spoken "accept this load"
    /// actually fires the same code path the on-screen CTA does. The
    /// optional path lets `execute:/loads/123:accept` carry a target.
    case execute(key: String, path: String?)
    /// Enter hands-free autopilot mode (founder press-and-hold spec).
    /// Broadcasts the enter-autopilot signal; the orb / surface own the
    /// actual continuous-listening state machine.
    case autopilot
    /// Reverse the last autopilot-applied action(s). Broadcasts an
    /// undo-all signal any surface that applied an autopilot mutation
    /// listens for to roll back.
    case undoAll
    /// ESANG VISION GROUNDING — tap a visible on-screen control. `x`/`y`
    /// are NORMALIZED (0…1, top-left origin) coordinates into the key
    /// window, as returned by the server's vision model from the captured
    /// screenshot (`<<<ACTION:tap:CX x CY>>>`). The actual hit-test +
    /// accessibility activation lives in `ContentView` (it owns the key
    /// window + overlay); the dispatcher just posts `.esangTapAtPoint`
    /// carrying the normalized point. Both values are clamped to 0…1 at
    /// parse time so a bad model output can never index off-screen.
    case tapAt(x: Double, y: Double)
}

/// The iOS top-level tab names ESANG can navigate to. These are the four
/// surfaces reachable from `BottomNav`; deep-links from the web that point
/// at sub-pages collapse onto their parent tab here (e.g. `/loads/12345`
/// → `.myLoads`, and the load-id is surfaced via `selectLoad` instead).
///
/// `meDetail(...)` is a deep-link into the Me tab — the dispatcher switches
/// to `.me` and then posts a notification so `DriverMePane` opens the right
/// sub-sheet. Voice commands like "open ELD" or "fleet management" route
/// here.
enum eSangRoute: Equatable {
    case home
    case trips          // Eusoboards (marketplace)
    case myLoads        // "Loads" tab (DriverLoadsPane)
    case me
    case meDetail(String)   // raw value of MeDetailRoute (e.g. "eld", "fleet", "zeun")
}

// MARK: - Parser

/// Parses the raw assistant reply. Returns (cleaned text, actions[]).
/// The cleaned text has every `<<<ACTION:...>>>` token stripped so the
/// chat bubble never shows plumbing tokens.
enum eSangAutopilot {

    /// Press-and-hold latch. The orb long-press fires `.esangEnterAutopilot`
    /// AND sets this flag, because the global autopilot engine (mounted at
    /// the ContentView root) may not yet be subscribed at long-press time —
    /// the role surface / overlay presents a frame later. The engine reads
    /// and clears this flag in its own `.onAppear` so a hold that lands
    /// before the observer is live still activates. The live
    /// `.onReceive(.esangEnterAutopilot)` path covers in-session triggers
    /// (e.g. a chat reply that carries `<<<ACTION:autopilot>>>`).
    @MainActor static var pendingAutopilotActivation: Bool = false

    /// Read-and-clear helper so callers don't have to remember to reset
    /// the latch. Returns `true` exactly once per pending activation.
    @MainActor static func consumePendingAutopilotActivation() -> Bool {
        guard pendingAutopilotActivation else { return false }
        pendingAutopilotActivation = false
        return true
    }

    /// Regex that matches the full `<<<ACTION:verb:arg>>>` grammar.
    /// Arg is optional for verbs like `refresh` — the parser falls
    /// back to an empty string when no `:arg` is present.
    ///
    /// The regex is lenient on trailing `>` counts (we want to strip 2+
    /// trailing chevrons because the web sometimes emits 4 closers).
    private static let regex: NSRegularExpression = {
        // `<<<ACTION:<verb>(:<arg>)?>>>+`
        let pattern = "<<<\\s*ACTION\\s*:\\s*([a-zA-Z_-]+)(?:\\s*:\\s*([^>]*?))?\\s*>{2,}"
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: pattern,
                                        options: [.caseInsensitive])
    }()

    /// Split a raw assistant reply into the text the driver should see
    /// and the zero-or-more actions the client should dispatch.
    static func parse(_ raw: String) -> (cleaned: String, actions: [eSangAction]) {
        guard !raw.isEmpty else { return ("", []) }
        let ns = raw as NSString
        let matches = regex.matches(
            in: raw,
            options: [],
            range: NSRange(location: 0, length: ns.length)
        )
        guard !matches.isEmpty else { return (tidy(raw), []) }

        var actions: [eSangAction] = []
        for m in matches {
            guard m.numberOfRanges >= 2 else { continue }
            let verb = ns.substring(with: m.range(at: 1))
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let arg: String = {
                guard m.numberOfRanges >= 3,
                      m.range(at: 2).location != NSNotFound else { return "" }
                return ns.substring(with: m.range(at: 2))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }()
            if let action = buildAction(verb: verb, arg: arg) {
                actions.append(action)
            }
        }

        // Strip every match (iterate back-to-front so indices stay
        // valid as we shorten the string).
        var cleaned = raw
        for m in matches.reversed() {
            if let r = Range(m.range, in: cleaned) {
                cleaned.removeSubrange(r)
            }
        }
        return (tidy(cleaned), actions)
    }

    /// FAST ON-DEVICE INTENT — resolve the common spoken NAVIGATION
    /// commands locally so autopilot acts INSTANTLY and RELIABLY, with no
    /// dependence on the ESANG server round-trip emitting a perfectly
    /// formatted control token (a stale/slow/coach server reply was leaving
    /// autopilot "capturing voice but doing nothing"). Returns a
    /// navigate/back action for an obvious command; nil routes the turn
    /// through the full ESANG round-trip (complex / non-navigation asks).
    /// Paths here mirror the ones `eSangRoleDispatcher.screenId` resolves.
    static func localNavIntent(for raw: String) -> eSangAction? {
        let t = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        func has(_ keys: String...) -> Bool { keys.contains { t.contains($0) } }

        if t == "back" || has("go back", "back up", "previous screen", "take me back") { return .back }
        // Create/post a load — checked BEFORE the bare "loads" rule so
        // "post a load" never collapses to the loads list.
        if has("post a load", "post load", "new load", "create a load", "create load",
               "post a new load", "post my load", "add a load", "post freight") {
            return .navigatePath("/loads/create")
        }
        if has("market intelligence", "market intel", "marketplace", "market pricing",
               "rate intelligence", "rate intel", "commodit", "stock", "ticker") {
            return .navigatePath("/market-intelligence")
        }
        if t == "loads" || has("my loads", "go to loads", "show loads", "open loads",
                               "view loads", "see my loads", "load board", "my shipments", "shipments") {
            return .navigatePath("/loads")
        }
        if t == "home" || has("go home", "home screen", "dashboard", "main screen", "take me home") {
            return .navigatePath("/home")
        }
        if has("wallet", "my money", "my earnings", "settlements", "my payments", "payouts") {
            return .navigatePath("/wallet")
        }
        if t == "profile" || t == "me" || has("my profile", "profile page", "go to profile",
               "account settings", "my settings", "my account", "open settings") {
            return .navigatePath("/me")
        }
        if has("browse carriers", "find carriers", "find a carrier", "carriers", "partner directory") {
            return .navigatePath("/carriers")
        }
        if has("messages", "my messages", "open chat", "my chats", "inbox") {
            return .navigatePath("/messages")
        }
        if has("compliance", "my documents", "my docs", "document center") {
            return .navigatePath("/compliance")
        }
        if has("post a load") { return .navigatePath("/loads/create") }
        return nil
    }

    /// Cosmetic fixups on the visible reply: collapse the double spaces
    /// left behind by a stripped token, trim leading/trailing whitespace,
    /// and remove stray trailing punctuation that now has nothing to cling
    /// to ("Sure, let me take you there. ." → "Sure, let me take you there.").
    private static func tidy(_ s: String) -> String {
        var out = s
        // Collapse runs of whitespace (preserving single newlines).
        let lines = out.split(separator: "\n", omittingEmptySubsequences: false)
        let normalized = lines.map { line -> String in
            var l = String(line)
            while l.contains("  ") {
                l = l.replacingOccurrences(of: "  ", with: " ")
            }
            return l.trimmingCharacters(in: .whitespaces)
        }
        out = normalized.joined(separator: "\n")
        // Remove double punctuation runs (". ." or ".." at the tail).
        while out.hasSuffix(" .") || out.hasSuffix("..") {
            out = String(out.dropLast())
            out = out.trimmingCharacters(in: .whitespaces)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Map (verb, arg) onto a typed `eSangAction`. Returns `nil` for any
    /// verb or argument the iOS client doesn't understand — we prefer a
    /// silent skip to a hallucinated side-effect.
    private static func buildAction(verb: String, arg: String) -> eSangAction? {
        switch verb {
        case "navigate", "goto", "go", "open", "show":
            // ALWAYS preserve the raw path. The Driver surface still gets
            // its typed `eSangRoute` (collapse to a Driver tab) via
            // `route(for:)` inside the Driver dispatcher, but every OTHER
            // role needs the verbatim server path to resolve against its
            // own push-nav registry — collapsing `/dispatch/planner` onto
            // a Driver `.home` tab was the E1/E2 no-op. Emit the path and
            // let `eSangRoleDispatcher` resolve it per-role.
            let path = arg.trimmingCharacters(in: .whitespaces)
            return path.isEmpty ? nil : .navigatePath(path)
        case "open-chat", "open_chat", "openchat":
            return .openChat
        case "close-chat", "close_chat", "closechat":
            return .closeChat
        case "select", "open-load", "open_load":
            let id = arg.trimmingCharacters(in: .whitespaces)
            return id.isEmpty ? nil : .selectLoad(id)
        case "refresh", "reload":
            return .refresh
        case "back", "pop", "go-back", "go_back":
            return .back
        case "execute", "do", "act", "smart_assign", "smart-assign",
             "smartassign", "accept", "approve", "confirm", "commit":
            // `smart_assign` / `accept` / etc. are verb-as-action: the
            // verb itself IS the action key when no `arg` carries one.
            // `execute:accept-load` carries the key in `arg`. Allow a
            // `key:/path` composite split on the LAST `:` so
            // `execute:accept:/loads/123` carries both.
            let key: String
            let path: String?
            if verb == "execute" || verb == "do" || verb == "act" {
                // arg is the action key (optionally key|path with a
                // pipe, or just the key). Empty arg → nothing to do.
                let raw = arg.trimmingCharacters(in: .whitespaces)
                if raw.isEmpty { return nil }
                if let pipe = raw.firstIndex(of: "|") {
                    key = String(raw[..<pipe]).trimmingCharacters(in: .whitespaces)
                    path = String(raw[raw.index(after: pipe)...]).trimmingCharacters(in: .whitespaces)
                } else {
                    key = raw
                    path = nil
                }
                return key.isEmpty ? nil : .execute(key: key, path: path)
            } else {
                // Normalize `smart-assign` → `smart_assign`; the verb is
                // the key, and any `arg` is the target path.
                key = verb.replacingOccurrences(of: "-", with: "_")
                path = arg.isEmpty ? nil : arg.trimmingCharacters(in: .whitespaces)
                return .execute(key: key, path: path)
            }
        case "tap", "tap-at", "tap_at", "tapat", "click", "press":
            // ESANG VISION GROUNDING. Arg is "CX x CY" — two normalized
            // coordinates (0…1, top-left origin) split on a literal `x`
            // (e.g. "0.52 x 0.83"). Be forgiving about the separator and
            // whitespace; also accept a comma-separated pair as a fallback
            // ("0.52, 0.83"). Both components are clamped to 0…1 so a stray
            // model output can never drive a tap off the key window. A pair
            // we can't parse into two Doubles is a silent skip (never a
            // hallucinated tap).
            let lowered = arg.lowercased()
            let pieces: [Substring]
            if lowered.contains("x") {
                pieces = lowered.split(separator: "x", maxSplits: 1,
                                       omittingEmptySubsequences: true)
            } else if lowered.contains(",") {
                pieces = lowered.split(separator: ",", maxSplits: 1,
                                       omittingEmptySubsequences: true)
            } else {
                pieces = lowered.split(separator: " ", maxSplits: 1,
                                       omittingEmptySubsequences: true)
            }
            guard pieces.count == 2,
                  let cx = Double(pieces[0].trimmingCharacters(in: .whitespaces)),
                  let cy = Double(pieces[1].trimmingCharacters(in: .whitespaces)),
                  cx.isFinite, cy.isFinite else { return nil }
            let clamp: (Double) -> Double = { min(max($0, 0), 1) }
            return .tapAt(x: clamp(cx), y: clamp(cy))
        case "autopilot", "auto-pilot", "auto_pilot", "handsfree", "hands-free":
            return .autopilot
        case "undo_all", "undo-all", "undoall", "undo", "revert", "rollback":
            return .undoAll
        default:
            return nil
        }
    }

    /// Normalize a web-style path onto an iOS top-level tab. Strips query
    /// strings, fragments, and trailing slashes before matching.
    static func route(for rawPath: String) -> eSangRoute? {
        var p = rawPath.trimmingCharacters(in: .whitespaces).lowercased()
        if p.isEmpty { return nil }
        // Drop query + fragment.
        if let q = p.firstIndex(of: "?") { p = String(p[..<q]) }
        if let h = p.firstIndex(of: "#") { p = String(p[..<h]) }
        // Drop trailing slash.
        while p.count > 1 && p.hasSuffix("/") { p = String(p.dropLast()) }
        // Ensure leading slash for parity with the web.
        if !p.hasPrefix("/") { p = "/" + p }

        // Exact map — first segment matters most.
        let first = p.split(separator: "/", maxSplits: 1,
                            omittingEmptySubsequences: true).first.map(String.init) ?? ""

        switch first {
        case "", "home", "dashboard", "driver":
            return .home
        case "marketplace", "eusoboards", "board", "loads-search":
            return .trips
        case "trips":
            // /trips/new → Trips (Eusoboards); /trips alone → Trips
            return .trips
        case "loads":
            // /loads → My Loads; /loads/search → Trips (handled above).
            // /loads/:id isn't a tab — higher-level parser turns it into
            // selectLoad, but if we get here treat it as MyLoads.
            let tail = p.dropFirst("/loads".count)
            if tail == "/search" || tail.hasPrefix("/search") {
                return .trips
            }
            return .myLoads
        case "my-loads", "mine":
            return .myLoads
        case "me", "profile", "account":
            return .me
        case "settings":
            return .meDetail("settings")
        // ─── Me-tab deep-links (voice parity with web sub-routes) ───
        case "eld", "hos", "duty-status", "dutystatus", "logs", "log-book", "logbook":
            return .meDetail("eld")
        case "fleet", "fleet-management", "vehicles", "vehicle", "equipment", "assets":
            return .meDetail("fleet")
        case "zeun", "zeun-mechanics", "mechanics", "diagnostics", "dvir", "maintenance":
            return .meDetail("zeun")
        case "eusowallet", "wallet", "earnings", "pay", "paycheck":
            return .meDetail("earnings")
        case "tax", "taxes", "1099", "w9", "w-9":
            return .meDetail("tax")
        case "carrier", "my-carrier", "company", "employer", "motor-carrier", "dispatch-company":
            return .meDetail("carrier")
        case "rate-sheet", "rate-sheets", "schedule-a", "scheduleA", "rates-calculator", "pay-calculator", "reconciliation", "reconcile", "rate-tier", "rate-tiers":
            return .meDetail("rateSheet")
        case "availability", "schedule", "home-time", "hometime":
            return .meDetail("availability")
        case "missions", "mission", "quests", "quest":
            return .meDetail("missions")
        case "rewards", "reward", "redeem", "redemption", "points", "claim", "crates", "crate":
            return .meDetail("rewards")
        case "badges", "badge", "achievements", "achievement":
            return .meDetail("badges")
        case "referrals", "refer", "referral", "invite":
            return .meDetail("referrals")
        case "haul", "the-haul", "leaderboard", "lobby", "chat-room", "chatroom", "community":
            return .meDetail("haul")
        case "esang", "copilot", "chat":
            // ESANG route is handled by openChat; still legal to call
            // `navigate:/esang` — we collapse to .home so the caller can
            // still layer openChat on top.
            return .home
        default:
            return nil
        }
    }
}

// MARK: - Dispatcher env key

/// Closure the ESANG chat sheet fires for every parsed action. Injected by
/// `DriverHomeScreen` so the chat sheet doesn't hard-couple to a specific
/// navigation store — previews and tests can stub it to `nil`.
struct eSangActionHandlerKey: EnvironmentKey {
    static let defaultValue: ((eSangAction) -> Void)? = nil
}

extension EnvironmentValues {
    var esangActionHandler: ((eSangAction) -> Void)? {
        get { self[eSangActionHandlerKey.self] }
        set { self[eSangActionHandlerKey.self] = newValue }
    }
}

// MARK: - Role-aware autopilot dispatcher
//
// The Driver surface owns a typed `eSangRoute` → `currentTab` flip (see
// `ContentView.handleeSangAction`). Every OTHER role is a push-nav
// surface (`RoleSurfaceRouter`): a screen swap is a notification post
// (`.eusoShipperNavSwap` / `.eusoCarrierNavSwap` / `.eusoDispatchNavSwap`
// / … carrying `userInfo["screenId"]`), a back is `.eusoShipperNavBack`
// or the shared `.eusoRoleNavBack`, and the ESANG sheet is dismissed via
// the surface's own `showeSang` toggle.
//
// `eSangRoleDispatcher` converts a parsed `eSangAction` into the RIGHT
// notification for the SIGNED-IN role, RBAC-gated through
// `RoleAccess.canRender`. This is the wiring that closes E1/E2: a spoken
// command on any role now resolves the server SPA path against the
// role's push-nav registry and actually drives the screen — instead of
// collapsing `/dispatch/planner` onto a Driver `.home` tab and dropping
// `execute` / `autopilot` / `undo_all` on the floor.

extension Notification.Name {
    /// Enter hands-free autopilot mode. Role-agnostic — the orb /
    /// surface state machine listens. Parameterless.
    static let esangEnterAutopilot = Notification.Name("esangEnterAutopilot")
    /// Leave hands-free autopilot mode (stop continuous listening, drop
    /// the HUD). Posted by the global engine on tear-down and by any
    /// surface that wants to cancel autopilot. Parameterless.
    static let esangExitAutopilot = Notification.Name("esangExitAutopilot")
    /// Reverse the last autopilot-applied mutation(s). Role-agnostic.
    static let esangUndoAll = Notification.Name("esangUndoAll")
    /// Execute a server-named action on the active surface. `object` is
    /// the action key (String); `userInfo["path"]` carries an optional
    /// target path. Surfaces that own a matching CTA observe this and
    /// fire the same code path the on-screen button does.
    static let esangExecuteAction = Notification.Name("esangExecuteAction")
    /// ESANG VISION GROUNDING — tap a visible control at a NORMALIZED
    /// point. `userInfo["x"]` / `userInfo["y"]` are Doubles in 0…1
    /// (top-left origin). Posted by the dispatcher on a `.tapAt` action;
    /// `ContentView` observes it, hit-tests the key window's accessibility
    /// tree, and activates the deepest activatable element at that point
    /// (with a visible pulse). Role-agnostic.
    static let esangTapAtPoint = Notification.Name("esangTapAtPoint")
    /// HONEST UNHANDLED COMMAND. Posted by the dispatcher when a parsed
    /// `.navigatePath` could NOT be resolved to a real, in-role screen —
    /// the surface fell back to HOME so the app still responds, but the
    /// command didn't land where asked. `object` carries the raw path
    /// (String) the model emitted. The autopilot engine observes this to
    /// surface an honest HUD line + speak "I heard '<x>' but couldn't open
    /// it here." instead of leaving the operator staring at an unchanged
    /// (or merely home-bounced) screen with no feedback. Role-agnostic.
    static let esangUnhandledCommand = Notification.Name("esangUnhandledCommand")
}

@MainActor
enum eSangRoleDispatcher {

    /// The role's screen-swap notification + its home screen id. Driver
    /// is intentionally absent — the Driver surface dispatches its own
    /// typed `eSangRoute` through `ContentView.handleeSangAction`.
    private static func navSwap(for role: EusoRole) -> (name: Notification.Name, home: String)? {
        switch role {
        case .shipper, .railShipper:
            return (.eusoShipperNavSwap, "200")
        case .vesselShipper:
            return (.eusoVesselShipperNavSwap, "Vesl001")
        case .catalyst, .railCatalyst:
            return (.eusoCarrierNavSwap, "300")
        case .broker, .railBroker, .vesselBroker, .customsBroker:
            return (.eusoBrokerNavSwap, "400")
        case .escort:
            return (.eusoEscortNavSwap, "600")
        case .terminal, .portMaster:
            return (.eusoTerminalNavSwap, "700")
        case .admin, .superAdmin:
            return (.eusoAdminNavSwap, "800")
        case .dispatch:
            return (.eusoDispatchNavSwap, "Disp400")
        case .compliance:
            return (.eusoComplianceNavSwap, "900")
        case .railEngineer:
            return (.eusoRailNavSwap, "Rail550")
        case .vesselOperator:
            return (.eusoVesselNavSwap, "Vesl650")
        // Driver + the web-continuation-only roles have no push-nav
        // swap notification on iOS.
        case .driver, .safety, .factoring,
             .railDispatch, .railConductor, .shipCaptain, .serviceProvider:
            return nil
        }
    }

    /// The role's back notification. Shipper uses its own dedicated
    /// `.eusoShipperNavBack`; every other push-nav surface listens to
    /// the shared `.eusoRoleNavBack`.
    private static func backNotification(for role: EusoRole) -> Notification.Name? {
        switch role {
        case .shipper, .railShipper:
            return .eusoShipperNavBack
        case .vesselShipper:
            return .eusoVesselShipperNavBack
        case .catalyst, .railCatalyst, .broker, .railBroker, .vesselBroker,
             .customsBroker, .escort, .terminal, .portMaster, .admin,
             .superAdmin, .dispatch, .compliance, .railEngineer, .vesselOperator:
            return .eusoRoleNavBack
        case .driver, .safety, .factoring,
             .railDispatch, .railConductor, .shipCaptain, .serviceProvider:
            return nil
        }
    }

    /// True when `action` carries NAVIGATION intent (drive the surface to
    /// some screen) for a non-Driver role — i.e. the kinds of command the
    /// operator means when they say "take me to X". Used by the autopilot
    /// engine to tell, after parsing a reply, whether the turn was supposed
    /// to MOVE the screen at all (vs. a pure back / refresh / execute / tap
    /// that legitimately changes nothing about which screen is shown).
    static func isNavigational(_ action: eSangAction) -> Bool {
        switch action {
        case .navigatePath, .navigate, .selectLoad: return true
        default:                                    return false
        }
    }

    /// True when a NAVIGATIONAL `action` resolves to a REAL, in-role,
    /// RBAC-renderable screen for `role` — i.e. the dispatch will actually
    /// land somewhere the operator asked for, not silently fall back to the
    /// role home. The engine uses this to surface an honest "I heard '<x>'
    /// but couldn't open it here." line when EVERY navigational action in a
    /// turn fails to resolve. Mirrors the resolution `dispatch` performs.
    static func resolvesToRealScreen(_ action: eSangAction, role: EusoRole) -> Bool {
        guard role != .driver, navSwap(for: role) != nil else { return false }
        switch action {
        case .navigatePath(let path):
            guard let id = screenId(for: path, role: role) else { return false }
            return RoleAccess.canRender(role: role, screenId: id)
        case .navigate(let route):
            // Only the universal `/home` collapses cleanly onto a non-Driver
            // home; everything else is a Driver-typed route that doesn't
            // resolve to a real non-Driver screen.
            if case .home = route { return true }
            return false
        case .selectLoad(let id):
            // Shipper has a dedicated load-open path; others resolve the
            // load-detail screen against the registry.
            if role == .vesselShipper {
                return !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if role == .shipper || role == .railShipper {
                return true
            }
            guard let detail = screenId(for: "/load/\(id)", role: role) else { return false }
            return RoleAccess.canRender(role: role, screenId: detail)
        default:
            return false
        }
    }

    /// Dispatch a parsed action for a NON-DRIVER role. Returns `true`
    /// when the action was handled here (the caller should NOT also run
    /// the Driver path). Driver always returns `false` so its existing
    /// typed handler runs untouched.
    ///
    /// `dismissSheet` is the surface's own close closure (sets
    /// `showeSang = false`) so navigation lands ON the destination as
    /// the coach sheet slides away — the same fix the Driver path got
    /// 2026-05-30.
    @discardableResult
    static func dispatch(_ action: eSangAction,
                         role: EusoRole,
                         dismissSheet: @escaping () -> Void) -> Bool {
        // Driver keeps its own typed dispatcher.
        guard role != .driver else { return false }

        switch action {
        case .navigatePath(let path):
            guard let swap = navSwap(for: role) else { return true }
            // Resolve the server SPA path against this role's registry.
            // `screenId` returns nil when the path names no in-role surface.
            let resolved = screenId(for: path, role: role)
            // RBAC: a resolved id must be renderable for the role. If the
            // path resolved to nothing, or to a cross-role id the role
            // can't see, we DON'T silently swallow the command (the old
            // bug — the screen never changed and the user got no feedback).
            // Instead we fall back to the role HOME so the app still
            // RESPONDS, and signal an unhandled-command so the engine can
            // speak/log an honest "couldn't open it here" line.
            let canRender = resolved.map { RoleAccess.canRender(role: role, screenId: $0) } ?? false
            let target = canRender ? resolved! : swap.home
            dismissSheet()
            // Defer the swap a beat so the sheet dismissal animation and
            // the screen swap don't fight (matches the Driver path's
            // 0.45s Me-detail defer).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
                NotificationCenter.default.post(
                    name: swap.name, object: nil,
                    userInfo: ["screenId": target]
                )
                // Honest fallback: we landed on HOME because the command
                // didn't resolve to a real in-role screen. Tell the engine
                // so it can surface "I heard '<x>' but couldn't open it
                // here." rather than implying the navigation succeeded.
                if !canRender {
                    NotificationCenter.default.post(
                        name: .esangUnhandledCommand, object: path
                    )
                }
            }
            return true

        case .navigate(let route):
            // A Driver-typed route arrived on a non-Driver surface (the
            // server occasionally emits a bare `/home`). Map the handful
            // of universal routes onto the role's home / nothing.
            guard let swap = navSwap(for: role) else { return true }
            if case .home = route {
                dismissSheet()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
                    NotificationCenter.default.post(
                        name: swap.name, object: nil,
                        userInfo: ["screenId": swap.home]
                    )
                }
            }
            return true

        case .back:
            guard let back = backNotification(for: role) else { return true }
            NotificationCenter.default.post(name: back, object: nil)
            return true

        case .openChat:
            // The surface owns `showeSang`; the orb-tap notification is
            // the canonical "open the sheet" path. No-op when already up.
            return true

        case .closeChat:
            dismissSheet()
            return true

        case .selectLoad(let id):
            // Route a load-open through the role's load-open path where
            // one exists; otherwise resolve `/load/:id` against the
            // registry. Shipper has a dedicated load-open notification.
            if role == .vesselShipper {
                let reference = id.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !reference.isEmpty else { return true }
                dismissSheet()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
                    NotificationCenter.default.post(
                        name: .eusoVesselShipperNavSwap,
                        object: nil,
                        userInfo: ["screenId": "Vesl003", "bookingNumber": reference]
                    )
                }
                return true
            }
            if role == .shipper || role == .railShipper {
                NotificationCenter.default.post(
                    name: .eusoShipperLoadOpen, object: nil,
                    userInfo: ["loadId": id]
                )
                return true
            }
            // Generic: navigate to the role's load-detail screen if the
            // path resolver knows one.
            if let detail = screenId(for: "/load/\(id)", role: role),
               let swap = navSwap(for: role),
               RoleAccess.canRender(role: role, screenId: detail) {
                dismissSheet()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
                    NotificationCenter.default.post(
                        name: swap.name, object: nil,
                        userInfo: ["screenId": detail, "loadId": id]
                    )
                }
            }
            return true

        case .refresh:
            NotificationCenter.default.post(name: .esangRefreshSurface, object: nil)
            return true

        case .execute(let key, let path):
            NotificationCenter.default.post(
                name: .esangExecuteAction, object: key,
                userInfo: path.map { ["path": $0] } ?? [:]
            )
            return true

        case .autopilot:
            NotificationCenter.default.post(name: .esangEnterAutopilot, object: nil)
            return true

        case .undoAll:
            NotificationCenter.default.post(name: .esangUndoAll, object: nil)
            return true

        case .tapAt(let x, let y):
            // ESANG VISION GROUNDING. Hand the normalized point to the
            // key-window activator in ContentView (role-agnostic — it
            // hit-tests whatever surface is on top). We only marshal the
            // notification here; the activation + visible pulse + honest
            // "couldn't tap there" feedback live there.
            NotificationCenter.default.post(
                name: .esangTapAtPoint, object: nil,
                userInfo: ["x": x, "y": y]
            )
            return true
        }
    }

    /// Resolve a server SPA path to a push-nav screen id for `role`.
    /// Strips the role prefix (`/shipper/…`, `/dispatch/…`, `/rail/…`,
    /// `/vessel/…`, `/carrier|catalyst/…`, `/broker/…`, …), then maps
    /// the remaining surface segment onto the role's registry id. Reuses
    /// the role NavRoute maps for the bottom-nav roots and adds the
    /// common sub-surfaces the voice/web server addresses. Returns `nil`
    /// for a segment this role doesn't surface natively.
    static func screenId(for rawPath: String, role: EusoRole) -> String? {
        var p = rawPath.trimmingCharacters(in: .whitespaces).lowercased()
        if p.isEmpty { return nil }
        if let q = p.firstIndex(of: "?") { p = String(p[..<q]) }
        if let h = p.firstIndex(of: "#") { p = String(p[..<h]) }
        while p.count > 1 && p.hasSuffix("/") { p = String(p.dropLast()) }
        if !p.hasPrefix("/") { p = "/" + p }

        var segs = p.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if segs.isEmpty { return nil }

        // Strip a leading role-prefix segment so `/shipper/loads`,
        // `/dispatch/planner`, `/rail/marketplace` all reduce to their
        // surface segment. Keep the rest for sub-routing.
        let rolePrefixes: Set<String> = [
            "shipper", "carrier", "catalyst", "broker", "dispatch",
            "dispatcher", "escort", "terminal", "admin", "compliance",
            "rail", "vessel", "driver", "app"
        ]
        if let first = segs.first, rolePrefixes.contains(first) {
            segs.removeFirst()
        }
        // After stripping, an empty list means "the role home". `surface`
        // is the FIRST surface segment; `sub` is the SECOND (when present),
        // so multi-segment web routes like `/loads/create` resolve to the
        // ACTION screen (Post-a-Load) and not the list. Every sub-map gets
        // the full `segs` so it can special-case these routes by purpose.
        let surface = segs.first ?? "home"
        let homeIds: [EusoRole: String] = [
            .shipper: "200", .railShipper: "200", .vesselShipper: "Vesl001",
            .catalyst: "300", .railCatalyst: "300",
            .broker: "400", .railBroker: "400", .vesselBroker: "400", .customsBroker: "400",
            .escort: "600", .terminal: "700", .portMaster: "700",
            .admin: "800", .superAdmin: "800",
            .dispatch: "Disp400", .compliance: "900",
            .railEngineer: "Rail550", .vesselOperator: "Vesl650"
        ]
        // Universal home aliases the server emits across every role.
        if surface == "home" || surface == "dashboard"
            || surface == "index" || surface == "overview" {
            return homeIds[role]
        }

        switch role {
        case .shipper, .railShipper:
            return shipperScreen(for: surface, segs: segs)
        case .vesselShipper:
            return vesselShipperScreen(for: surface, segs: segs)
        case .catalyst, .railCatalyst:
            return carrierScreen(for: surface, segs: segs)
        case .broker, .railBroker, .vesselBroker, .customsBroker:
            return brokerScreen(for: surface, segs: segs)
        case .escort:
            // Unknown surface → nil, so `dispatch` falls back to HOME AND
            // signals an honest unhandled-command (rather than masking the
            // miss by silently resolving to home here).
            return escortScreen(for: surface, segs: segs)
        case .terminal, .portMaster:
            return terminalScreen(for: surface, segs: segs)
        case .admin, .superAdmin:
            return adminScreen(for: surface, segs: segs)
        case .dispatch:
            return dispatchScreen(for: surface, segs: segs)
        case .compliance:
            return complianceScreen(for: surface, segs: segs)
        case .railEngineer:
            return railScreen(for: surface, segs: segs)
        case .vesselOperator:
            return vesselScreen(for: surface, segs: segs)
        case .driver, .safety, .factoring,
             .railDispatch, .railConductor, .shipCaptain, .serviceProvider:
            return nil
        }
    }

    /// True when the path's SECOND segment names a load CREATE/POST action
    /// (`/loads/create`, `/loads/new`, `/loads/post`, `/load/create`, …) —
    /// the multi-segment web route that the old single-`surface` mapper
    /// mis-resolved to the loads LIST. Used by the role sub-maps that own a
    /// dedicated Post-a-Load surface.
    private static func isCreateLoadRoute(_ segs: [String]) -> Bool {
        guard segs.count >= 2 else { return false }
        let head = segs[0]
        let sub = segs[1]
        let loadHeads: Set<String> = ["loads", "load", "my-loads"]
        let createSubs: Set<String> = ["create", "new", "post", "post-a-load", "compose"]
        return loadHeads.contains(head) && createSubs.contains(sub)
    }

    // Per-role surface → screen-id sub-maps. Bottom-nav roots come from
    // each role's NavRoute.map; the extra entries cover the sub-surfaces
    // the voice/web server addresses by name (parity with
    // ShipperWebToNativeMap + the role NavRoute deep-link keys).

    private static func shipperScreen(for s: String, segs: [String]) -> String? {
        // Multi-segment CREATE route first — `/loads/create`, `/loads/new`,
        // `/load/post` must hit Post-a-Load (204), NOT the loads list (201).
        if isCreateLoadRoute(segs) { return "204" }
        // `/load/:id` and `/loads/:id` are handled by selectLoad; here we
        // resolve named surfaces. Reuse ShipperWebToNativeMap's coverage.
        switch s {
        case "loads", "my-loads", "shipments": return "201"
        case "create-load", "post-load", "post-a-load",
             "post", "create", "new-load",
             "new":                         return "204"
        case "me", "account", "profile",
             "settings":                    return "320"
        case "allocations", "allocation":   return "229"
        case "agreements", "agreement":     return "223"
        case "partner-directory", "partners", "partner",
             "carriers", "browse-carriers": return "224"
        case "recurring-loads", "recurring":return "221"
        case "documents", "document-center",
             "docs":                        return "226"
        case "settlements", "settlement":   return "206"
        case "bol", "bols":                 return "228"
        case "rfp", "rfps", "bidding",
             "bids":                        return "215"
        case "messages", "messaging",
             "inbox", "chat", "esang":      return "310"
        case "control-tower":               return "212"
        case "compliance":                  return "216"
        case "sustainability":              return "214"
        case "reports":                     return "207"
        case "analytics":                   return "210"
        case "live-tracking", "tracking",
             "track":                       return "222"
        case "rate-board", "rates":         return "220"
        case "wallet", "eusowallet",
             "payments":                    return "290"
        case "market-intelligence", "market-pricing",
             "market", "pricing", "rate-intelligence",
             "marketplace":                 return "330"
        default:                            return nil
        }
    }

    private static func carrierScreen(for s: String, segs: [String]) -> String? {
        switch s {
        case "loads", "load-board", "loadboard",
             "marketplace", "board", "find-loads",
             "search-loads":                return "301"
        case "drivers", "fleet":            return "304"
        case "vehicles", "trucks":          return "320"
        case "me", "account", "profile",
             "settings":                    return "350"
        case "matches", "spectramatch":     return "501"
        case "bids", "bidding", "my-bids":  return "309"
        case "settlements", "settlement",
             "earnings":                    return "313"
        case "compliance":                  return "316"
        case "dispatch", "dispatch-board",
             "board-dispatch":              return "303"
        // NOTE: no carrier-chrome `/wallet` — the catalyst Wallet (319) is
        // shadowed by carrier Drivers List (319) in CarrierSurface's pool,
        // so a `/wallet` here falls back to home + signals unhandled rather
        // than silently opening the Drivers List.
        default:                            return nil
        }
    }

    private static func brokerScreen(for s: String, segs: [String]) -> String? {
        switch s {
        case "tenders", "tender":           return "401"
        case "loads", "load-board", "loadboard",
             "marketplace", "board",
             "my-loads":                    return "401b"
        case "carriers", "carrier",
             "carrier-vetting", "vetting":  return "402b"
        case "me", "account", "profile",
             "settings":                    return "404B"
        default:                            return nil
        }
    }

    private static func dispatchScreen(for s: String, segs: [String]) -> String? {
        switch s {
        case "drivers", "fleet", "roster":  return "Dpch701"
        case "loads", "board", "load-board",
             "planner", "dispatch-board",
             "assignment", "assignments",
             "marketplace":                 return "Dpch702"
        case "me", "account", "profile",
             "settings":                    return "Dpch713"
        case "exceptions", "triage":        return "Dpch703"
        case "kanban":                      return "Disp401"
        case "messages", "messaging",
             "comms", "chat", "inbox":      return "Dpch721"
        case "reports", "analytics":        return "Dpch712"
        default:                            return nil
        }
    }

    private static func railScreen(for s: String, segs: [String]) -> String? {
        switch s {
        case "shipments", "marketplace",
             "consists", "consist", "loads": return "Rail551"
        case "compliance":                  return "Rail552"
        case "tracking", "live-tracking",
             "track":                       return "Rail560"
        case "me", "account", "profile",
             "settings":                    return "Rail550"
        default:                            return nil
        }
    }

    private static func vesselScreen(for s: String, segs: [String]) -> String? {
        switch s {
        case "shipments", "bookings", "booking",
             "loads", "marketplace":        return "Vesl651"
        case "compliance":                  return "Vesl652"
        case "tracking", "live-tracking",
             "track", "position":           return "Vesl660"
        case "me", "account", "profile",
             "settings":                    return "Vesl656"
        default:                            return nil
        }
    }

    private static func vesselShipperScreen(for s: String, segs: [String]) -> String? {
        if isCreateLoadRoute(segs) { return "Vesl010" }
        switch s {
        case "create-booking", "new-booking", "create-load", "post-load",
             "post-a-load", "create", "new":
            return "Vesl010"
        case "shipments", "bookings", "booking", "loads", "marketplace":
            return "Vesl011"
        case "tracking", "live-tracking", "track", "position":
            return "Vesl012"
        case "compliance", "customs", "isf":
            return "Vesl006"
        case "me", "account", "profile", "settings":
            return "320"
        case "wallet", "eusowallet", "payments":
            return "290"
        default:
            return nil
        }
    }

    private static func escortScreen(for s: String, segs: [String]) -> String? {
        switch s {
        case "assignments", "assignment",
             "loads", "jobs":               return "601"
        case "corridor", "map", "route":    return "602"
        case "me", "account", "profile",
             "settings":                    return "600"
        default:                            return nil
        }
    }

    private static func terminalScreen(for s: String, segs: [String]) -> String? {
        switch s {
        case "movements", "gate", "queue",
             "gate-queue":                  return "701"
        case "yard", "yard-map", "map":     return "702"
        case "me", "account", "profile",
             "settings":                    return "700"
        default:                            return nil
        }
    }

    private static func adminScreen(for s: String, segs: [String]) -> String? {
        switch s {
        case "tickets", "control-tower":    return "801"
        case "tenants", "tenant":           return "802"
        case "me", "account", "profile",
             "settings":                    return "800"
        default:                            return nil
        }
    }

    private static func complianceScreen(for s: String, segs: [String]) -> String? {
        switch s {
        case "drivers", "expiring",
             "expiring-docs", "docs":       return "901"
        case "audits", "violations",
             "audit":                       return "902"
        case "me", "account", "profile",
             "settings":                    return "900"
        default:                            return nil
        }
    }
}
