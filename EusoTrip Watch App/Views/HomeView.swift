//
//  HomeView.swift
//  EusoTrip Watch App
//
//  Home surface — the thing the driver sees when they raise their wrist.
//  Composition:
//    - Phone-link badge
//    - Active load card (tap → details)
//    - Big push-to-talk button (Esang)
//    - Rotating greeting / last reply
//    - Quick actions: HOS toggle · Message dispatch · Emergency
//    - Fatigue chip (ErgoMonitor)
//

import SwiftUI
import WatchKit

struct HomeView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var esang: EsangSession
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @EnvironmentObject var hos: HOSStore
    @EnvironmentObject var loads: LoadStore
    @EnvironmentObject var ergo: ErgoMonitor
    @State private var greeting: String = WatchESangGreeting.pick()

    var body: some View {
        ScrollView {
            VStack(spacing: S.s2) {
                connectivityBadge
                if let load = loads.active {
                    activeLoadCard(load)
                }
                micButton
                Text(esang.displayText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 4)
                if !auth.isSignedIn {
                    Text("Sign in on your iPhone to link this watch.")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                } else {
                    Text(greeting)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
                fatigueChip
                quickActions
            }
            .padding(.vertical, S.s1)
        }
        .navigationTitle("Esang")
    }

    private var connectivityBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(connectivity.isReachable ? Color.esangGreen : Color.esangTextDim)
                .frame(width: 6, height: 6)
            Text(connectivity.isReachable ? "Phone linked" : "Standalone")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var micButton: some View {
        Button(action: { Task { await handleTap() } }) {
            ZStack {
                Circle()
                    .fill(esang.state.color.gradient)
                    .frame(width: 110, height: 110)
                    .shadow(
                        color: esang.state.color.opacity(0.6),
                        radius: esang.state == .listening ? 12 : 4
                    )
                    .scaleEffect(esang.state == .listening ? 1.05 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.4).repeatForever(autoreverses: true),
                        value: esang.state == .listening
                    )
                Image(systemName: esang.state.iconName)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(!auth.isSignedIn || esang.state == .thinking)
    }

    private var fatigueChip: some View {
        HStack(spacing: 4) {
            Circle().fill(ergo.fatigueTint).frame(width: 6, height: 6)
            Text(ergo.fatigueLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            Text("· \(ergo.minutesSinceBreak)m since break")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.esangCard, in: Capsule())
    }

    @ViewBuilder
    private var quickActions: some View {
        HStack(spacing: S.s2) {
            quickActionButton(systemImage: "clock.fill", label: "HOS") {
                // Cycle drive ↔ on-duty
                Task {
                    let next: HOSStatus = hos.current.status == .driving ? .onDuty : .driving
                    await hos.changeStatus(to: next, auth: auth, connectivity: connectivity)
                }
            }
            quickActionButton(systemImage: "iphone.and.arrow.forward", label: "Phone") {
                WKInterfaceDevice.current().play(.click)
                connectivity.requestPhoneActivation(transcript: nil, reply: nil)
            }
            quickActionButton(systemImage: "exclamationmark.triangle.fill", label: "SOS", tint: .esangDanger) {
                Task {
                    await EmergencyController.shared.activate(
                        reason: "manual-home",
                        auth: auth,
                        connectivity: connectivity
                    )
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func quickActionButton(
        systemImage: String,
        label: String,
        tint: Color = .esangBlue,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
            }
            .frame(width: 50, height: 42)
            .background(tint.opacity(0.20), in: RoundedRectangle(cornerRadius: R.sm))
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func activeLoadCard(_ load: WatchLoad) -> some View {
        Button {
            VoiceActionDispatcher.shared.currentRoute = .loadDetail(loadId: load.id)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(load.displayId)
                        .font(.system(size: 11, weight: .bold))
                    if load.hazmat {
                        Text("HZ")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color.esangHazmat, in: Capsule())
                    }
                    Spacer()
                    Text(load.status.replacingOccurrences(of: "_", with: " "))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text("\(load.originShort) → \(load.destShort)")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if let rate = load.totalRate {
                    Text("$\(Int(rate)) · \(Int(load.miles ?? 0))mi")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.md))
        }
        .buttonStyle(.plain)
    }

    private func handleTap() async {
        WKInterfaceDevice.current().play(.click)
        switch esang.state {
        case .idle, .error, .done:
            await esang.startListening()
        case .listening:
            await esang.stopAndSubmit(auth: auth, connectivity: connectivity)
        case .thinking:
            break
        }
    }
}
