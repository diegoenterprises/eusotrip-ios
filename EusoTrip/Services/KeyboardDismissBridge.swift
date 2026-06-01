//
//  KeyboardDismissBridge.swift
//  EusoTrip — global tap-outside-to-dismiss for the iOS software keyboard.
//
//  Founder bug 2026-05-31: the keyboard would activate (text fields,
//  search bars, sign-in forms) and the only way to dismiss was the
//  `keyboardDismissMode = .interactive` swipe-down already wired in
//  EusoTripApp.init(). Users expected the iOS-standard pattern: TAP
//  anywhere off the keyboard (or off the focused field) to dismiss it.
//
//  Implementation: install a `UITapGestureRecognizer` on every UIWindow
//  the moment it becomes key. The recognizer:
//
//    • cancelsTouchesInView = false  — every button, row, link still
//                                       receives the tap; the recognizer
//                                       only piggybacks for keyboard
//                                       dismissal.
//    • delaysTouchesBegan   = false  — no extra latency on the touch
//                                       reaching the underlying view.
//    • shouldReceive(touch:) skips    — if the tap lands on a UITextField
//                                       or UITextView the recognizer
//                                       declines, so the text field
//                                       continues to own the focus.
//    • shouldRecognizeSimultaneously  — runs alongside SwiftUI / UIKit
//                                       gestures rather than competing.
//
//  Apply via `KeyboardDismissBridge.shared.install()` from
//  `EusoTripApp.init()`. Idempotent — second/third installs are no-ops.
//

#if canImport(UIKit)
import UIKit

@MainActor
final class KeyboardDismissBridge: NSObject {
    static let shared = KeyboardDismissBridge()

    private var installed = false

    private override init() { super.init() }

    func install() {
        guard !installed else { return }
        installed = true

        // Attach to any windows that already exist at install time.
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for window in ws.windows { attach(to: window) }
        }

        // Attach to any window that becomes key after launch (sheets,
        // alerts, RemoteCommandCenter overlays all create new windows).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: UIWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @objc private func windowDidBecomeKey(_ note: Notification) {
        guard let window = note.object as? UIWindow else { return }
        attach(to: window)
    }

    private func attach(to window: UIWindow) {
        // Idempotent: don't double-attach to the same window.
        let existing = window.gestureRecognizers?.contains { $0 is _EusoKeyboardDismissTap } ?? false
        if existing { return }
        let tap = _EusoKeyboardDismissTap(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan   = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
    }

    @objc private func handleTap(_ recognizer: UIGestureRecognizer) {
        guard let window = recognizer.view as? UIWindow else { return }
        // `endEditing(true)` walks the responder chain and resigns the
        // first responder if there is one; if nothing is editing this
        // is a cheap no-op. No allocation, no animation jank.
        window.endEditing(true)
    }
}

extension KeyboardDismissBridge: UIGestureRecognizerDelegate {
    // Run alongside the destination view's own gesture recognizers
    // (SwiftUI taps, scroll, swipes) rather than blocking them.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    // Decline taps that land on a text input — the text field still
    // owns the touch, becomes first responder, shows the keyboard.
    // Taps that land anywhere ELSE (background, button row, list cell)
    // do reach this recognizer AND continue through to their target.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        var view: UIView? = touch.view
        while let current = view {
            if current is UITextField || current is UITextView {
                return false
            }
            view = current.superview
        }
        return true
    }
}

/// Private marker class so we can detect our own recognizer and avoid
/// double-attaching on subsequent `attach(to:)` calls.
private final class _EusoKeyboardDismissTap: UITapGestureRecognizer {}
#endif
