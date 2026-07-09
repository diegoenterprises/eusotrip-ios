//
//  AskEsangIntent.swift
//  EusoTrip Watch App
//
//  App Intents entry points so Siri and the Action Button can fire Esang
//  without launching the app UI. Two intents:
//
//    AskEsangIntent         — "Hey Siri, ask Esang [query]"
//    EsangSOSIntent         — "Hey Siri, Esang SOS"  (duress phrase)
//    HOSStatusIntent        — "Hey Siri, what are my HOS hours?"
//
//  Each intent is exposed to `App Shortcuts` with a suggested phrase so
//  users see them in the Shortcuts app and the Action Button settings.
//

import AppIntents
import SwiftUI

// MARK: - Ask Esang

struct AskEsangIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Esang"
    static var description: IntentDescription = IntentDescription(
        "Send a question to Esang AI and hear the reply on your wrist.",
        categoryName: "Esang"
    )
    static var openAppWhenRun: Bool = true

    @Parameter(
        title: "Question",
        description: "What you want to ask Esang.",
        requestValueDialog: "What would you like to ask Esang?"
    )
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // `AuthStore.shared` is nil until RootView's first frame — an
        // intent with openAppWhenRun can perform BEFORE that commits.
        // Bounded wait for the live store, then fall back to a
        // keychain-restored store so a valid token never reads as
        // "signed out" just because Siri beat the scene.
        let auth = await AskEsangIntentSupport.resolveAuth()
        // Route the turn through the app's LIVE session when it exists
        // so the orb history / suggestions / spoken reply all land on
        // the surface the driver is looking at. A fresh session is the
        // last-resort fallback for a pre-frame perform.
        let session = EsangSession.shared ?? EsangSession()
        let connectivity = WatchConnectivityManager.shared
        await session.submitTranscribedText(query, auth: auth, connectivity: connectivity)
        let reply = session.replyText.isEmpty ? "Esang is processing." : session.replyText
        return .result(dialog: IntentDialog(stringLiteral: reply))
    }
}

/// Shared store-resolution helpers for the App Intents entry points.
@MainActor
enum AskEsangIntentSupport {
    /// Wait up to ~2s for the app-owned AuthStore, then fall back to a
    /// keychain-backed instance. The returned store always reflects
    /// whatever token the wrist actually holds.
    static func resolveAuth() async -> AuthStore {
        for _ in 0..<20 {
            if let live = AuthStore.shared { return live }
            try? await Task.sleep(for: .milliseconds(100))
        }
        let fallback = AuthStore()
        fallback.restore()
        return fallback
    }
}

// MARK: - Emergency SOS

struct EsangSOSIntent: AppIntent {
    static var title: LocalizedStringResource = "Esang SOS"
    static var description: IntentDescription = IntentDescription(
        "Immediately escalate an emergency to Esang dispatch and place an E911 call on the paired phone.",
        categoryName: "Esang"
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Same store-race guard as AskEsangIntent: never bounce an SOS
        // because Siri performed before the first frame assigned
        // `AuthStore.shared`.
        let auth = await AskEsangIntentSupport.resolveAuth()
        await EmergencyController.shared.activate(
            reason: "siri-sos",
            auth: auth,
            connectivity: WatchConnectivityManager.shared
        )
        return .result(dialog: "Emergency services are being contacted.")
    }
}

// MARK: - HOS Status

struct HOSStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check HOS"
    static var description: IntentDescription = IntentDescription(
        "Ask Esang for your remaining drive hours, duty window, and cycle.",
        categoryName: "Esang"
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let hos = HOSStore.shared.current
        return .result(
            dialog: IntentDialog(stringLiteral:
                "You're \(hos.status.label). " +
                "\(hos.driveHoursText) drive, " +
                "\(hos.windowHoursText) window remaining."
            )
        )
    }
}

// MARK: - App Shortcuts provider

struct EusoTripAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskEsangIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask Esang on \(.applicationName)",
                "Talk to Esang on \(.applicationName)"
            ],
            shortTitle: "Ask Esang",
            systemImageName: "waveform.circle.fill"
        )
        AppShortcut(
            intent: EsangSOSIntent(),
            phrases: [
                "\(.applicationName) SOS",
                "\(.applicationName) emergency",
                "Emergency on \(.applicationName)"
            ],
            shortTitle: "Esang SOS",
            systemImageName: "exclamationmark.triangle.fill"
        )
        AppShortcut(
            intent: HOSStatusIntent(),
            phrases: [
                "Check my HOS on \(.applicationName)",
                "\(.applicationName) hours",
                "How much drive time do I have on \(.applicationName)"
            ],
            shortTitle: "Check HOS",
            systemImageName: "clock.fill"
        )
    }
}

/// Called from EusoTripWatchApp on launch to make sure Siri/Shortcuts
/// pick up the latest set on each cold boot.
enum AskEsangIntentRegistrar {
    static func register() {
        EusoTripAppShortcuts.updateAppShortcutParameters()
    }
}
