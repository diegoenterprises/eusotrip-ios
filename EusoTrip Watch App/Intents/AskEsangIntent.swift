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
        guard let auth = AuthStore.shared else {
            return .result(dialog: "Sign in on your iPhone to use Esang.")
        }
        let session = EsangSession()
        let connectivity = WatchConnectivityManager.shared
        await session.submitTranscribedText(query, auth: auth, connectivity: connectivity)
        let reply = session.replyText.isEmpty ? "Esang is processing." : session.replyText
        return .result(dialog: IntentDialog(stringLiteral: reply))
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
        guard let auth = AuthStore.shared else {
            return .result(dialog: "Sign in on your iPhone to use Esang.")
        }
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
                "Ask Esang",
                "Talk to Esang",
                "Ask Esang \(\.$query)"
            ],
            shortTitle: "Ask Esang",
            systemImageName: "waveform.circle.fill"
        )
        AppShortcut(
            intent: EsangSOSIntent(),
            phrases: [
                "Esang SOS",
                "\(.applicationName) emergency",
                "Esang emergency"
            ],
            shortTitle: "Esang SOS",
            systemImageName: "exclamationmark.triangle.fill"
        )
        AppShortcut(
            intent: HOSStatusIntent(),
            phrases: [
                "Check my HOS",
                "\(.applicationName) hours",
                "How much drive time do I have"
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
