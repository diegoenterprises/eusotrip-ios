//
//  ShipperAppIntents.swift
//  EusoTrip — `AppIntent` conformers that route Siri / Spotlight /
//  Shortcuts triggers INTO ESANG AI rather than firing tRPC mutations
//  directly.
//
//  Doctrine ([feedback_esang_branding]): ESANG AI is the canonical
//  voice + assistant surface for the app. Siri is a wake-word that
//  hands off to ESANG — every voice request flows through
//  `EusoTripAPI.shared.esang.chat(...)` so the user gets one
//  consistent assistant identity regardless of whether they tapped
//  the orb in-app, talked to their watch, or said "Hey Siri."
//
//  Why route through ESANG instead of firing mutations directly:
//    · ESANG can ask follow-up questions ("Which lane?" / "What
//      rate?") via its server-side conversation state — a direct
//      AppIntent.perform() that calls `shippers.create` would either
//      fail on missing parameters or fabricate values.
//    · ESANG returns natural-language confirmations the user
//      recognizes ("Posted LD-260427-… to your shipper board.")
//      instead of generic Siri dialog strings.
//    · ESANG decides side-effects (notifications, escalations,
//      Continuity advertisement, haptic playback) — keeping that
//      logic server-side means voice commands behave the same
//      whether they came from the in-app orb, the watch, Siri, or
//      a future channel like CarPlay.
//
//  Surfaces wired (mirrors the 237 doctrine, but every leaf is
//  ESANG, not a direct mutation):
//    1. AskeSangIntent              — generic "Ask ESANG ___"
//    2. eSangPostLoadIntent         — "post a load" → ESANG
//    3. eSangCheckLoadStatusIntent  — "load status" → ESANG
//    4. eSangShowExceptionsIntent   — "show exceptions" → ESANG
//    5. eSangGetBidsIntent          — "get bids" → ESANG
//    6. OpeneSangIntent             — "Open ESANG" deep-link
//    7. OpenLoadsIntent             — "Open Loads" deep-link
//    8. OpenControlTowerIntent      — "Open Control Tower" deep-link
//
//  Deep-link intents (6/7/8) post the canonical
//  `eusoShipperNavSwap` / `eusoShippereSangTapped` notifications
//  that `RoleSurfaceRouter.ShipperSurface` already listens for. ESANG
//  intents (1-5) return ESANG's reply text in the Siri dialog so the
//  user hears what ESANG said.
//

import Foundation
import AppIntents

// MARK: - 1. AskeSangIntent (the canonical "Ask ESANG ___" entry)

/// "Ask ESANG to find me a return load out of Dallas."
/// "Hey Siri, ask ESANG how many bids are on LD-...".
/// The catch-all conduit — any phrase that starts with "ask ESANG"
/// or "tell ESANG" routes here. ESANG's reply comes back as the
/// Siri dialog so the user hears the same voice they hear in-app.
@available(iOS 17.0, *)
struct AskeSangIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask ESANG"
    static var description = IntentDescription(
        "Sends a question or command to ESANG AI and reads its reply.",
        categoryName: "ESANG"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "What should I ask ESANG?") var prompt: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let resp = try await EusoTripAPI.shared.esang.chat(
            message: prompt,
            currentPage: "siri",
            loadId: nil
        )
        return .result(dialog: IntentDialog(stringLiteral: resp.message))
    }
}

// MARK: - 2. eSangPostLoadIntent

/// "Hey Siri, post a load on EusoTrip from Houston to Dallas at 1900 dollars."
/// Routes to ESANG with a structured prompt so the AI can fill in
/// missing fields server-side (cargo type defaulting, weight estimate
/// via lane history, pickup-window from the user's calendar) instead
/// of forcing the user to recite every required parameter to Siri.
@available(iOS 17.0, *)
struct eSangPostLoadIntent: AppIntent {
    static var title: LocalizedStringResource = "Post a Load with ESANG"
    static var description = IntentDescription(
        "Asks ESANG AI to post a load to your shipper board.",
        categoryName: "ESANG"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Origin (city, state)") var origin: String
    @Parameter(title: "Destination (city, state)") var destination: String
    @Parameter(title: "Rate (USD, optional)") var rate: Double?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var prompt = "Post a load from \(origin) to \(destination)"
        if let r = rate {
            prompt += " at $\(Int(r))"
        }
        prompt += "."
        let resp = try await EusoTripAPI.shared.esang.chat(
            message: prompt,
            currentPage: "siri.post_load",
            loadId: nil
        )
        return .result(dialog: IntentDialog(stringLiteral: resp.message))
    }
}

// MARK: - 3. eSangCheckLoadStatusIntent

@available(iOS 17.0, *)
struct eSangCheckLoadStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Load Status with ESANG"
    static var description = IntentDescription(
        "Asks ESANG AI for the current lifecycle stage and ETA of a load.",
        categoryName: "ESANG"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Load number") var loadNumber: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let resp = try await EusoTripAPI.shared.esang.chat(
            message: "What's the status of \(loadNumber)?",
            currentPage: "siri.load_status",
            loadId: loadNumber
        )
        return .result(dialog: IntentDialog(stringLiteral: resp.message))
    }
}

// MARK: - 4. eSangShowExceptionsIntent

/// "Hey Siri, show me my exceptions on EusoTrip." ESANG narrates the
/// top open exceptions instead of dumping the user into the control
/// tower screen — they can ask follow-ups by speaking again.
@available(iOS 17.0, *)
struct eSangShowExceptionsIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Exceptions with ESANG"
    static var description = IntentDescription(
        "Asks ESANG AI to summarize your open platform exceptions.",
        categoryName: "ESANG"
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let resp = try await EusoTripAPI.shared.esang.chat(
            message: "Summarize my open exceptions.",
            currentPage: "siri.exceptions",
            loadId: nil
        )
        return .result(dialog: IntentDialog(stringLiteral: resp.message))
    }
}

// MARK: - 5. eSangGetBidsIntent

@available(iOS 17.0, *)
struct eSangGetBidsIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Bids with ESANG"
    static var description = IntentDescription(
        "Asks ESANG AI for the bid count and best price on a posted load.",
        categoryName: "ESANG"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Load number") var loadNumber: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let resp = try await EusoTripAPI.shared.esang.chat(
            message: "What bids are on \(loadNumber)?",
            currentPage: "siri.bids",
            loadId: loadNumber
        )
        return .result(dialog: IntentDialog(stringLiteral: resp.message))
    }
}

// MARK: - 6. OpeneSangIntent

/// "Hey Siri, open ESANG." Brings the app forward and presents the
/// ESANG coach sheet immediately so the user can keep the
/// conversation going by voice from inside the app.
@available(iOS 17.0, *)
struct OpeneSangIntent: AppIntent {
    static var title: LocalizedStringResource = "Open ESANG"
    static var description = IntentDescription(
        "Opens ESANG AI inside the app.",
        categoryName: "ESANG"
    )
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .eusoShippereSangTapped,
                object: nil
            )
        }
        return .result()
    }
}

// MARK: - 7. OpenLoadsIntent (in-app deep-link, not an ESANG call)

@available(iOS 17.0, *)
struct OpenLoadsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Loads"
    static var description = IntentDescription(
        "Opens the loads board.",
        categoryName: "Navigation"
    )
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .eusoShipperNavSwap,
                object: nil,
                userInfo: ["screenId": "201"]
            )
        }
        return .result()
    }
}

// MARK: - 8. OpenControlTowerIntent

@available(iOS 17.0, *)
struct OpenControlTowerIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Control Tower"
    static var description = IntentDescription(
        "Opens the platform control tower.",
        categoryName: "Navigation"
    )
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .eusoShipperNavSwap,
                object: nil,
                userInfo: ["screenId": "212"]
            )
        }
        return .result()
    }
}

// MARK: - AppShortcutsProvider

/// Siri phrases all start with "ask ESANG" / "tell ESANG" / "open
/// ESANG" so the brand stays consistent when the user speaks. The
/// system phrase
/// `\(.applicationName)` resolves to "EusoTrip" — Siri reads
/// "Ask ESANG on EusoTrip…" which puts ESANG's name first in the
/// utterance, matching the in-app voice.
@available(iOS 17.0, *)
struct EusoTripAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskeSangIntent(),
            phrases: [
                "Ask ESANG on \(.applicationName)",
                "Tell ESANG on \(.applicationName)",
            ],
            shortTitle: "Ask ESANG",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: eSangPostLoadIntent(),
            phrases: [
                "Post a load with ESANG on \(.applicationName)",
                "Have ESANG post a load on \(.applicationName)",
            ],
            shortTitle: "Post Load via ESANG",
            systemImageName: "plus.rectangle.on.rectangle"
        )
        AppShortcut(
            intent: eSangCheckLoadStatusIntent(),
            phrases: [
                "Ask ESANG for load status on \(.applicationName)",
            ],
            shortTitle: "Load Status via ESANG",
            systemImageName: "shippingbox.fill"
        )
        AppShortcut(
            intent: eSangShowExceptionsIntent(),
            phrases: [
                "Ask ESANG for exceptions on \(.applicationName)",
            ],
            shortTitle: "Exceptions via ESANG",
            systemImageName: "exclamationmark.triangle.fill"
        )
        AppShortcut(
            intent: eSangGetBidsIntent(),
            phrases: [
                "Ask ESANG for bids on \(.applicationName)",
            ],
            shortTitle: "Bids via ESANG",
            systemImageName: "hand.raised.fill"
        )
        AppShortcut(
            intent: OpeneSangIntent(),
            phrases: [
                "Open ESANG on \(.applicationName)",
            ],
            shortTitle: "Open ESANG",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: OpenLoadsIntent(),
            phrases: [
                "Open loads on \(.applicationName)",
            ],
            shortTitle: "Loads",
            systemImageName: "shippingbox"
        )
        AppShortcut(
            intent: OpenControlTowerIntent(),
            phrases: [
                "Open control tower on \(.applicationName)",
            ],
            shortTitle: "Control Tower",
            systemImageName: "tower.broadcast"
        )
    }
}
