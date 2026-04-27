//
//  WatchDictation.swift
//  EusoTrip Pulse Watch App
//
//  Root-cause fix for the "Voice input unavailable on this device"
//  error card on the wrist: Apple does not ship `SFSpeechRecognizer`
//  to watchOS, so the `#if canImport(Speech)` branch in
//  `EsangSession.startListening()` falls through to the error path.
//
//  This file replaces that dead-end with a working watchOS dictation
//  pipeline built from two complementary pieces:
//
//    (1) `DictationBroker` — a small `@MainActor ObservableObject`
//        singleton that sits between `EsangSession` and the SwiftUI
//        layer. `EsangSession.startListening(auth:connectivity:)`
//        on watchOS calls `DictationBroker.shared.requestText()`
//        which flips `isPresenting = true` and suspends on a
//        continuation. `HomeView` observes `isPresenting` and shows
//        the dictation sheet; the sheet's `onSubmit / onCancel`
//        hooks fulfil the continuation so the async caller resumes
//        with the transcript (or nil on cancel).
//
//    (2) `WatchDictationSheet` — a one-tap SwiftUI sheet whose only
//        interactive element is a full-width `TextFieldLink` wrapping
//        an orb-styled CTA. Tapping it presents Apple's native
//        dictation UI (watchOS 10+ `TextFieldLink` exposes the
//        dictation + scribble affordance that used to live only on
//        `WKInterfaceController.presentTextInputController`). When
//        dictation completes, the returned text is handed back to
//        `DictationBroker` and the sheet auto-dismisses.
//
//  Why this shape: SwiftUI-only watch apps (using the `App` protocol,
//  no `WKApplicationDelegateAdaptor`) can't reliably reach a non-nil
//  `WKExtension.shared().rootInterfaceController`, so the classic
//  `presentTextInputController(allowedInputMode:)` path is unreachable
//  in practice. `TextFieldLink` is the canonical SwiftUI-native
//  replacement that Apple added in watchOS 10.0 for exactly this
//  use-case.
//

import Foundation
import SwiftUI
import WatchKit
import Combine

// MARK: - DictationBroker

/// Bridges `EsangSession`'s async state machine to the SwiftUI-side
/// dictation sheet presented by `HomeView`. Singleton because
/// dictation is a modal, app-level interaction — only one session in
/// flight at a time, and every entry point (orb tap, long-press,
/// App Intent, complication deep-link) resolves to the same sheet.
@MainActor
final class DictationBroker: ObservableObject {

    /// Shared singleton. Observed by `HomeView` for sheet presentation
    /// and called by `EsangSession` to kick off a dictation session.
    static let shared = DictationBroker()

    /// SwiftUI sheet binding driver. When `true`, `HomeView` presents
    /// `WatchDictationSheet`. Flipped on by `requestText()`, flipped
    /// off by `submit(_:)` / `cancel()` or by the sheet's own
    /// swipe-to-dismiss gesture (which routes through `cancel()`).
    @Published var isPresenting: Bool = false

    /// Pending continuation awaiting the sheet's result. Resumed
    /// exactly once — either by `submit(_:)` with the dictated
    /// transcript, or by `cancel()` with nil.
    private var continuation: CheckedContinuation<String?, Never>?

    private init() {}

    /// Entry point from `EsangSession`. Opens the SwiftUI dictation
    /// sheet — `WatchDictationSheet`'s TextFieldLink with prompt
    /// "Speak to ESANG" gives the system a strong dictation hint, and
    /// crucially the user must EXPLICITLY tap the gradient mic CTA
    /// before the input picker opens. The previous imperative
    /// `presentTextInputController(allowedInputMode: .plain)` path
    /// auto-opened the system input picker after a couple of seconds
    /// — and on watchOS 26 the picker frequently lands on the keyboard
    /// instead of dictation, leaving drivers staring at a wrist
    /// keyboard they can't reasonably type on while driving. The
    /// SwiftUI-sheet path also gives us a clean "Cancel" affordance
    /// that the imperative path lacks.
    /// Re-entrancy guard — one dictation flight at a time.
    func requestText() async -> String? {
        if continuation != nil {
            return nil
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            continuation = cont
            isPresenting = true
        }
    }

    /// Resumes the pending continuation with a submitted transcript.
    /// Called by the sheet when dictation returns a non-empty string.
    func submit(_ text: String) {
        let cont = continuation
        continuation = nil
        isPresenting = false
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cont?.resume(returning: trimmed.isEmpty ? nil : trimmed)
    }

    /// Resumes the pending continuation with nil (dismiss / cancel /
    /// swipe-down). Safe to call when no continuation is pending.
    func cancel() {
        let cont = continuation
        continuation = nil
        isPresenting = false
        cont?.resume(returning: nil)
    }
}

// MARK: - WatchDictationSheet

/// Modal sheet presented by `HomeView` whenever
/// `DictationBroker.shared.isPresenting` flips to true. Renders a
/// single big TextFieldLink styled as an orb + prompt, so a driver
/// glancing at the wrist sees the same gradient visual vocabulary
/// as the main orb screen and understands exactly what to tap.
struct WatchDictationSheet: View {
    @ObservedObject var broker: DictationBroker = .shared
    @Environment(\.dismiss) private var dismiss
    @State private var lastDictated: String = ""

    var body: some View {
        VStack(spacing: 10) {
            // Header — reads as a continuation of the orb screen, not
            // a new "form" metaphor. Caps, tight tracking, brand
            // gradient so the header itself is the identity.
            Text("ASK ESANG")
                .font(.system(size: 13, weight: .heavy)).tracking(1.2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.esangBlue, Color.esangMagenta],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .padding(.top, 4)

            // Primary CTA — direct imperative `presentTextInputController`
            // call instead of `TextFieldLink`. The link wasn't firing
            // on watchOS 26 (user reported "the button isnt working")
            // because `.buttonStyle(.plain)` ate its tap target. The
            // imperative API runs the moment the user actually taps,
            // not on sheet appear, so this fixes both that bug AND
            // the earlier "keyboard auto-opens after 2s" complaint.
            Button {
                presentDictation()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text(lastDictated.isEmpty ? "Tap to speak" : lastDictated)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [Color.esangBlue, Color.esangMagenta],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)

            // Secondary action — skip / cancel. Small, muted, so the
            // CTA keeps primary weight.
            Button {
                broker.cancel()
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        // If the sheet is dismissed by swipe or digital-crown rather
        // than by our buttons, still resolve the continuation so
        // EsangSession isn't stuck awaiting a result that never
        // arrives. No-ops when submit/cancel already ran.
        .onDisappear {
            if broker.isPresenting {
                broker.cancel()
            }
        }
    }

    /// Imperatively open Apple's dictation/scribble input picker on
    /// watchOS. Suggestions list is empty so the controller defaults
    /// to dictation when the user taps the mic icon. Result string
    /// resolves the broker continuation and dismisses the sheet.
    private func presentDictation() {
        #if os(watchOS)
        guard let controller = WKApplication.shared().visibleInterfaceController else {
            return
        }
        controller.presentTextInputController(
            withSuggestions: nil,
            allowedInputMode: .plain
        ) { results in
            Task { @MainActor in
                if let first = results?.first as? String {
                    let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        lastDictated = trimmed
                        broker.submit(trimmed)
                        dismiss()
                        return
                    }
                }
                // User backed out of input picker — keep our sheet up so
                // they can retry without re-summoning the orb.
            }
        }
        #endif
    }
}
