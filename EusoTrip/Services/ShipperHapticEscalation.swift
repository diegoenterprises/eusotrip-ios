//
//  ShipperHapticEscalation.swift
//  EusoTrip — Real Taptic Engine + CoreHaptics playback for the
//  per-category haptic patterns previewed in
//  `234_ShipperHapticEscalation.swift`.
//
//  Each of the 7 push categories from the 231 routing taxonomy maps
//  to a specific haptic signature. The app calls
//  `ShipperHapticPlayer.shared.play(category:)` from the push handler
//  / live activity update / ESANG escalation site so the user feels
//  the right wrist signature for each event class.
//
//  No new entitlement needed — Taptic Engine + CoreHaptics are both
//  system-vended. CoreHaptics requires iOS 13+ (project deploys
//  iOS 17). On devices without a Taptic Engine
//  (iPad / older iPhone) the call gracefully no-ops.
//

import Foundation
import UIKit
import CoreHaptics

/// Push-routing categories from `231_ShipperPushNotificationLanding.swift`.
public enum ShipperHapticCategory: String, CaseIterable {
    case loadAccepted        // bid accepted
    case bolReady            // BOL ready for sign-off
    case driverArrived       // driver at gate / dock
    case escortDivergence    // hazmat escort divergence (ALERT)
    case settlementReady     // settlement ready to fund
    case exceptionTriage     // platform exception needs human
    case dailyDigest         // soft 09:00 morning digest
}

@MainActor
public final class ShipperHapticPlayer {
    public static let shared = ShipperHapticPlayer()
    private let engine: CHHapticEngine?

    private init() {
        // CoreHaptics engine for the divergence pattern (heavy 3-tap
        // sharp transient). Falls back to UIImpactFeedbackGenerator
        // if engine init fails (older iPad / simulator).
        if CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            self.engine = try? CHHapticEngine()
            try? self.engine?.start()
        } else {
            self.engine = nil
        }
    }

    /// Play the wrist signature for a category. Idempotent — fire
    /// from any thread; the actor-isolated wrapper marshals back to
    /// the main thread.
    public func play(category: ShipperHapticCategory) {
        switch category {
        case .loadAccepted:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .bolReady:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .driverArrived:
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
        case .escortDivergence:
            // Hero pattern from 234 doctrine: 3 sharp heavy taps
            // with 80ms gaps. Plays through CoreHaptics when the
            // engine is up; falls back to 3 timed `.heavy` impacts
            // when not.
            playEscortDivergencePattern()
        case .settlementReady:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .exceptionTriage:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .dailyDigest:
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func playEscortDivergencePattern() {
        guard let engine else {
            // CoreHaptics unavailable — fallback path: 3 heavy
            // impacts at 80ms intervals on the main run loop. Same
            // perceived signature, lower fidelity.
            let gen = UIImpactFeedbackGenerator(style: .heavy)
            gen.prepare()
            for i in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.08) {
                    gen.impactOccurred()
                }
            }
            return
        }
        // CoreHaptics path: 3 sharp transients, intensity 1.0,
        // sharpness 1.0, 80ms apart.
        var events: [CHHapticEvent] = []
        for i in 0..<3 {
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0),
                ],
                relativeTime: Double(i) * 0.08
            )
            events.append(event)
        }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player  = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            // Quietly fall through — haptics are best-effort.
        }
    }
}
