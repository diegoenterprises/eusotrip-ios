//
//  EmergencyView.swift
//  EusoTrip Watch App
//
//  Full-screen SOS overlay driven by EmergencyController. Shows a
//  30-second countdown (or a benign "Location saved" confirmation when
//  in duress mode) with a prominent Cancel button. Triggered by:
//    - Long-press SOS from HomeView
//    - CrashDetection 6g spike
//    - Voice action `emergency_sos`
//    - Duress phrase ("Esang I'm in trouble") — silent escalation
//

import SwiftUI
import WatchKit

struct EmergencyView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @StateObject private var controller = EmergencyController.shared

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: S.s2) {
                if controller.silent {
                    silentCard
                } else {
                    loudCard
                }
            }
            .padding(.horizontal, S.s2)
        }
        // The danger-red gradient covers the full screen via
        // .ignoresSafeArea(); clip the entire overlay to the container
        // shape so the red fill can't bleed past the rounded bezel at
        // the four corners of the physical watch face.
        .clipShape(ContainerRelativeShape())
        .onAppear {
            if !controller.silent {
                WKInterfaceDevice.current().play(.failure)
            }
        }
    }

    private var backdrop: some View {
        LinearGradient.esangDanger
            .ignoresSafeArea()
            .overlay(Color.black.opacity(0.15).ignoresSafeArea())
    }

    private var loudCard: some View {
        VStack(spacing: S.s2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
            Text("EMERGENCY")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.white)
                .tracking(1.5)
            Text(controller.reason.isEmpty ? "SOS triggered" : controller.reason)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text("\(controller.countdownSeconds)")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text("Dispatch + E911 on iPhone")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.8))

            Button(role: .cancel) {
                controller.cancel()
            } label: {
                Text("Cancel")
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: R.sm))
                    .foregroundStyle(Color.esangDanger)
            }
            .buttonStyle(.plain)
        }
    }

    private var silentCard: some View {
        VStack(spacing: S.s2) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white)
            Text("Location Saved")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
            Text("We're with you.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.85))
            Button {
                controller.cancel()
            } label: {
                Text("Dismiss")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .background(Color.white.opacity(0.25), in: RoundedRectangle(cornerRadius: R.sm))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }
}
