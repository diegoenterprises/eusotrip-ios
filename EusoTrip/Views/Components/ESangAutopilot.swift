//
//  ESangAutopilot.swift
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
//    navigate:<path>         Switch the BottomNav surface.
//    open-chat               Expand the ESANG coach sheet (no-op when
//                            already open; kept for web parity).
//    close-chat              Dissolve the ESANG coach sheet.
//    select:<loadId>         Present a Load Detail sheet for the given id.
//    refresh                 Re-run the current surface's loader.
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
enum ESangAction: Equatable {
    /// Switch the BottomNav to a top-level tab.
    case navigate(ESangRoute)
    /// Open the ESANG coach sheet. Web-side only fires this from outside
    /// the sheet; iOS ignores it when the sheet is already up.
    case openChat
    /// Dissolve the ESANG coach sheet back to the orb.
    case closeChat
    /// Present the Load Detail sheet for a specific load.
    case selectLoad(String)
    /// Re-run the current surface's loader (pull-to-refresh equivalent).
    case refresh
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
enum ESangRoute: Equatable {
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
enum ESangAutopilot {

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
    static func parse(_ raw: String) -> (cleaned: String, actions: [ESangAction]) {
        guard !raw.isEmpty else { return ("", []) }
        let ns = raw as NSString
        let matches = regex.matches(
            in: raw,
            options: [],
            range: NSRange(location: 0, length: ns.length)
        )
        guard !matches.isEmpty else { return (tidy(raw), []) }

        var actions: [ESangAction] = []
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

    /// Map (verb, arg) onto a typed `ESangAction`. Returns `nil` for any
    /// verb or argument the iOS client doesn't understand — we prefer a
    /// silent skip to a hallucinated side-effect.
    private static func buildAction(verb: String, arg: String) -> ESangAction? {
        switch verb {
        case "navigate", "goto", "go":
            if let route = route(for: arg) { return .navigate(route) }
            return nil
        case "open-chat", "open_chat", "openchat":
            return .openChat
        case "close-chat", "close_chat", "closechat":
            return .closeChat
        case "select", "open-load", "open_load":
            let id = arg.trimmingCharacters(in: .whitespaces)
            return id.isEmpty ? nil : .selectLoad(id)
        case "refresh", "reload":
            return .refresh
        default:
            return nil
        }
    }

    /// Normalize a web-style path onto an iOS top-level tab. Strips query
    /// strings, fragments, and trailing slashes before matching.
    static func route(for rawPath: String) -> ESangRoute? {
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
struct ESangActionHandlerKey: EnvironmentKey {
    static let defaultValue: ((ESangAction) -> Void)? = nil
}

extension EnvironmentValues {
    var esangActionHandler: ((ESangAction) -> Void)? {
        get { self[ESangActionHandlerKey.self] }
        set { self[ESangActionHandlerKey.self] = newValue }
    }
}
