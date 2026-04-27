//
//  ToastView.swift
//  EusoTrip Watch App
//
//  Lightweight confirmation sheet shown when a voice action completes
//  (load accepted, arrival logged, message sent, …). Auto-dismisses
//  after ~1.8 seconds so the wrist isn't stuck on a modal.
//

import SwiftUI
import WatchKit

struct ToastView: View {
    let message: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: S.s2) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.esangGreen)
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, S.s2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.esangCard)
        // The card background fills the whole sheet; clip to the bezel
        // curvature so the card's square corners don't stamp past the
        // rounded display corners as dark rectangles.
        .clipShape(ContainerRelativeShape())
        .onAppear {
            WKInterfaceDevice.current().play(.success)
            Task {
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                dismiss()
            }
        }
    }
}
