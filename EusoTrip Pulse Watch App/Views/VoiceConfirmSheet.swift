//
//  VoiceConfirmSheet.swift
//  EusoTrip Pulse Watch App
//
//  F04 — Confirmation sheet for destructive voice intents hit on the
//  offline path (no server-side policy check available).
//
//  The offline grammar in `VoiceDispatch.resolve(_:loadId:)` parks
//  destructive actions (emergency_sos, accept_load, decline_load)
//  behind a confirm slot in `VoiceActionDispatcher.confirmSlots`
//  keyed by UUID. This sheet reads the prompt, shows a two-button
//  confirm/cancel UI sized for the 41mm + 45mm wrist forms, and on
//  tap calls back into the dispatcher.
//
//  Why not just inline this into the dispatcher: the dispatcher is
//  `@MainActor` but view-agnostic. Keeping the sheet in its own file
//  preserves that separation — a future "hardware button confirm"
//  path (long-press crown, double-tap) can hook the same slot id.
//

import SwiftUI
import WatchKit

struct VoiceConfirmSheet: View {
    let prompt: String
    let confirmId: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(LinearGradient.esangPrimary)
                    .padding(.top, 6)

                Text("Confirm voice action")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                Text(prompt)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)

                Button(role: .destructive) {
                    Task { @MainActor in
                        WKInterfaceDevice.current().play(.success)
                        await VoiceActionDispatcher.shared.confirmVoiceAction(confirmId)
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("Confirm")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button {
                    WKInterfaceDevice.current().play(.click)
                    VoiceActionDispatcher.shared.cancelVoiceAction(confirmId)
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.gray)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .navigationTitle("Voice")
        .onDisappear {
            // Safety: if the sheet was swipe-dismissed rather than
            // tapped, drop the slot. `cancelVoiceAction` is idempotent
            // so this is safe even when Confirm already fired.
            VoiceActionDispatcher.shared.cancelVoiceAction(confirmId)
        }
    }
}
