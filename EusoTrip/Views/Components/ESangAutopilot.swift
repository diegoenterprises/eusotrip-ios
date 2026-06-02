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
    /// Reverse the last autopilot-applied mutation(s). Role-agnostic.
    static let esangUndoAll = Notification.Name("esangUndoAll")
    /// Execute a server-named action on the active surface. `object` is
    /// the action key (String); `userInfo["path"]` carries an optional
    /// target path. Surfaces that own a matching CTA observe this and
    /// fire the same code path the on-screen button does.
    static let esangExecuteAction = Notification.Name("esangExecuteAction")
}

@MainActor
enum eSangRoleDispatcher {

    /// The role's screen-swap notification + its home screen id. Driver
    /// is intentionally absent — the Driver surface dispatches its own
    /// typed `eSangRoute` through `ContentView.handleeSangAction`.
    private static func navSwap(for role: EusoRole) -> (name: Notification.Name, home: String)? {
        switch role {
        case .shipper, .railShipper, .vesselShipper:
            return (.eusoShipperNavSwap, "200")
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
            return (.eusoDispatchNavSwap, "Dpch700")
        case .compliance:
            return (.eusoComplianceNavSwap, "900")
        case .railEngineer:
            return (.eusoRailNavSwap, "Rail550")
        case .vesselOperator:
            return (.eusoVesselNavSwap, "Vesl650")
        // Driver + the web-continuation-only roles have no push-nav
        // swap notification on iOS.
        case .driver, .safety, .factoring,
             .railDispatch, .railConductor, .shipCaptain:
            return nil
        }
    }

    /// The role's back notification. Shipper uses its own dedicated
    /// `.eusoShipperNavBack`; every other push-nav surface listens to
    /// the shared `.eusoRoleNavBack`.
    private static func backNotification(for role: EusoRole) -> Notification.Name? {
        switch role {
        case .shipper, .railShipper, .vesselShipper:
            return .eusoShipperNavBack
        case .catalyst, .railCatalyst, .broker, .railBroker, .vesselBroker,
             .customsBroker, .escort, .terminal, .portMaster, .admin,
             .superAdmin, .dispatch, .compliance, .railEngineer, .vesselOperator:
            return .eusoRoleNavBack
        case .driver, .safety, .factoring,
             .railDispatch, .railConductor, .shipCaptain:
            return nil
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
            guard let id = screenId(for: path, role: role) else {
                // Unknown path for this role — silently no-op rather than
                // bouncing the user somewhere wrong. The reply text still
                // rendered, so the user isn't confused.
                return true
            }
            guard let swap = navSwap(for: role) else { return true }
            // RBAC: deny cross-role IDs. If the resolved id isn't in the
            // role's registry, fall back to the role's home so the
            // command still lands somewhere coherent (and in-role).
            let target = RoleAccess.canRender(role: role, screenId: id) ? id : swap.home
            dismissSheet()
            // Defer the swap a beat so the sheet dismissal animation and
            // the screen swap don't fight (matches the Driver path's
            // 0.45s Me-detail defer).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
                NotificationCenter.default.post(
                    name: swap.name, object: nil,
                    userInfo: ["screenId": target]
                )
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
            if role == .shipper || role == .railShipper || role == .vesselShipper {
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
        // After stripping, an empty list means "the role home".
        let surface = segs.first ?? "home"
        let homeIds: [EusoRole: String] = [
            .shipper: "200", .railShipper: "200", .vesselShipper: "200",
            .catalyst: "300", .railCatalyst: "300",
            .broker: "400", .railBroker: "400", .vesselBroker: "400", .customsBroker: "400",
            .escort: "600", .terminal: "700", .portMaster: "700",
            .admin: "800", .superAdmin: "800",
            .dispatch: "Dpch700", .compliance: "900",
            .railEngineer: "Rail550", .vesselOperator: "Vesl650"
        ]
        if surface == "home" || surface == "dashboard" {
            return homeIds[role]
        }

        switch role {
        case .shipper, .railShipper, .vesselShipper:
            return shipperScreen(for: surface, segs: segs)
        case .catalyst, .railCatalyst:
            return carrierScreen(for: surface)
        case .broker, .railBroker, .vesselBroker, .customsBroker:
            return brokerScreen(for: surface)
        case .escort:
            return ["assignments": "601", "corridor": "602",
                    "me": "600"][surface] ?? homeIds[role]
        case .terminal, .portMaster:
            return ["movements": "701", "yard": "702",
                    "me": "700"][surface] ?? homeIds[role]
        case .admin, .superAdmin:
            return ["tickets": "801", "tenants": "802",
                    "me": "800"][surface] ?? homeIds[role]
        case .dispatch:
            return dispatchScreen(for: surface)
        case .compliance:
            return ["drivers": "901", "audits": "902", "violations": "902",
                    "me": "900"][surface] ?? homeIds[role]
        case .railEngineer:
            return railScreen(for: surface)
        case .vesselOperator:
            return ["shipments": "Vesl651", "bookings": "Vesl651",
                    "compliance": "Vesl652", "me": "Vesl650"][surface] ?? homeIds[role]
        case .driver, .safety, .factoring,
             .railDispatch, .railConductor, .shipCaptain:
            return nil
        }
    }

    // Per-role surface → screen-id sub-maps. Bottom-nav roots come from
    // each role's NavRoute.map; the extra entries cover the sub-surfaces
    // the voice/web server addresses by name (parity with
    // ShipperWebToNativeMap + the role NavRoute deep-link keys).

    private static func shipperScreen(for s: String, segs: [String]) -> String? {
        // `/load/:id` and `/loads/:id` are handled by selectLoad; here we
        // resolve named surfaces. Reuse ShipperWebToNativeMap's coverage.
        switch s {
        case "loads", "my-loads":           return "201"
        case "create-load", "post-load",
             "post", "create", "new-load":  return "204"
        case "me", "account", "profile":    return "320"
        case "allocations", "allocation":   return "229"
        case "agreements", "agreement":     return "223"
        case "partner-directory", "partners", "partner",
             "carriers", "browse-carriers": return "224"
        case "recurring-loads", "recurring":return "221"
        case "documents", "document-center",
             "docs":                        return "226"
        case "settlements", "settlement":   return "206"
        case "bol", "bols":                 return "228"
        case "rfp", "rfps", "marketplace",
             "bidding":                     return "215"
        case "control-tower":               return "212"
        case "compliance":                  return "216"
        case "sustainability":              return "214"
        case "reports":                     return "207"
        case "analytics":                   return "210"
        case "live-tracking", "tracking",
             "track":                       return "222"
        case "rate-board", "rates":         return "220"
        case "wallet", "eusowallet":        return "290"
        default:                            return nil
        }
    }

    private static func carrierScreen(for s: String) -> String? {
        switch s {
        case "loads", "load-board", "loadboard",
             "marketplace", "board":        return "301"
        case "drivers", "fleet":            return "304"
        case "me", "account", "profile":    return "350"
        case "matches", "spectramatch":     return "501"
        case "bids", "bidding":             return "309"
        default:                            return nil
        }
    }

    private static func brokerScreen(for s: String) -> String? {
        switch s {
        case "loads", "tenders", "tender":  return "401"
        case "carriers", "carrier":         return "402b"
        case "me", "account", "profile":    return "404"
        default:                            return nil
        }
    }

    private static func dispatchScreen(for s: String) -> String? {
        switch s {
        case "drivers", "fleet":            return "Dpch701"
        case "loads", "board", "load-board",
             "planner", "dispatch-board":   return "Dpch702"
        case "me", "account", "profile":    return "Dpch713"
        case "exceptions", "triage":        return "Dpch703"
        default:                            return nil
        }
    }

    private static func railScreen(for s: String) -> String? {
        switch s {
        case "shipments", "marketplace",
             "consists", "consist":         return "Rail551"
        case "compliance":                  return "Rail552"
        case "me", "account", "profile":    return "Rail550"
        default:                            return nil
        }
    }
}
