//
//  EmergencyView.swift
//  EusoTrip Watch App
//
//  Full-screen evidence surface for an SOS already in progress. It never
//  offers a false cancellation after relay work has begun. Silent duress
//  keeps a benign check-in presentation while preserving truthful sync state.
//

import SwiftUI
import WatchKit

struct EmergencyView: View {
    @StateObject private var controller = EmergencyController.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if controller.silent {
                silentSurface
            } else {
                loudSurface
            }
        }
        .clipShape(ContainerRelativeShape())
        .onAppear {
            if !controller.silent {
                WKInterfaceDevice.current().play(.failure)
            }
        }
    }

    private var loudSurface: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sos.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.red)
                    Text("PULSE SOS")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(String(controller.eventId.prefix(8)).uppercased())
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }

                VStack(spacing: 7) {
                    serverSymbol
                    Text(serverTitle)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(displayReason)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(serverAccent.opacity(0.8), lineWidth: 1)
                )

                VStack(spacing: 0) {
                    evidenceRow(
                        icon: controller.relayRoute == .iPhone ? "iphone" : "applewatch",
                        label: controller.relayRoute == .iPhone ? "iPhone relay" : "Watch relay"
                    )
                    Divider().overlay(Color.white.opacity(0.12))
                    evidenceRow(icon: callIcon, label: callTitle)
                    Divider().overlay(Color.white.opacity(0.12))
                    evidenceRow(
                        icon: "location.fill",
                        label: controller.locationCoordinate == nil ? "Location unavailable" : "GPS evidence attached"
                    )
                }
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Button {
                    controller.dismiss()
                } label: {
                    Label("Dismiss screen", systemImage: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(.white)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private var silentSurface: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 29, weight: .semibold))
                .foregroundStyle(Color.esangGreen)
            Text("Check-in captured")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
            Text(silentSyncTitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
            Button {
                controller.dismiss()
            } label: {
                Text("Dismiss")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(Color.white.opacity(0.10))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var serverSymbol: some View {
        switch controller.serverEvidence {
        case .contacting:
            ProgressView()
                .tint(.white)
                .frame(width: 26, height: 26)
        case .acknowledged:
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 27))
                .foregroundStyle(Color.esangGreen)
        case .queued:
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 27))
                .foregroundStyle(Color.orange)
        case .notAcknowledged:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 27))
                .foregroundStyle(Color.red)
        }
    }

    private func evidenceRow(icon: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 18)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
    }

    private var displayReason: String {
        let value = controller.reason.replacingOccurrences(of: "-", with: " ")
        return value.isEmpty ? "Driver-initiated emergency" : value.capitalized
    }

    private var serverTitle: String {
        switch controller.serverEvidence {
        case .contacting: return "Contacting emergency service"
        case .acknowledged: return "Server acknowledged"
        case .queued: return "Queued securely on Watch"
        case .notAcknowledged: return "No server receipt"
        }
    }

    private var serverAccent: Color {
        switch controller.serverEvidence {
        case .contacting: return .blue
        case .acknowledged: return .esangGreen
        case .queued: return .orange
        case .notAcknowledged: return .red
        }
    }

    private var callIcon: String {
        switch controller.callEvidence {
        case .opening: return "phone.arrow.up.right.fill"
        case .opened: return "phone.fill"
        case .notRequested: return "phone.down.fill"
        case .unavailable: return "phone.down.circle.fill"
        }
    }

    private var callTitle: String {
        switch controller.callEvidence {
        case .opening: return "Opening Emergency Call on iPhone"
        case .opened: return "Emergency Call handoff opened"
        case .notRequested: return "Emergency Call not requested"
        case .unavailable: return "iPhone call handoff unavailable"
        }
    }

    private var silentSyncTitle: String {
        switch controller.serverEvidence {
        case .contacting: return "Syncing"
        case .acknowledged: return "Synced"
        case .queued: return "Saved for sync"
        case .notAcknowledged: return "Sync not confirmed"
        }
    }
}
