//
//  ProximityHandoffView.swift
//  EusoTrip Pulse Watch App
//
//  F16 — Wrist-side UI for Proximity Handoff.
//
//  Two modes on a single screen:
//    1. BROADCAST — driver is the sender; wrist advertises a short-
//       lived BLE beacon carrying the active load context. Countdown
//       ring + haptic tick every 10s so the driver knows the beacon
//       is live without glancing at the wrist.
//    2. CAPTURE — driver is the receiver; wrist scans for a nearby
//       beacon + paints the captured payload with a verified/unverified
//       badge the moment it lands.
//
//  UX principles:
//    • One tap to go live. No confirmation sheet, no stepper — the
//      driver is standing at a dock and every second costs.
//    • Clear trust signal. A green "verified" badge means the HMAC
//      matched the local fleet key. A yellow "unsigned" badge means
//      the payload arrived but trust couldn't be established — the
//      driver decides whether to proceed.
//    • Haptic, not visual, confirms. Drivers don't stare at the wrist
//      while transferring loads; WKInterfaceDevice `.start`, `.stop`,
//      `.success`, `.notification` carry the state changes.
//

import SwiftUI
import Combine
import WatchKit

struct ProximityHandoffView: View {
    @ObservedObject private var handoff = ProximityHandoff.shared
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var loads: LoadStore

    @State private var now: Date = Date()
    @State private var breathe: Bool = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                header
                switch handoff.state {
                case .unsupported:  unsupportedBlock
                case .idle:         idleBlock
                case .broadcasting(let expiresAt):
                    broadcastingBlock(expiresAt: expiresAt)
                case .receiving:    receivingBlock
                case .captured(let payload, let verified):
                    capturedBlock(payload, verified: verified)
                case .error(let msg):
                    errorBlock(msg)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .navigationTitle("Handoff")
        .onReceive(tick) { now = $0 }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 2) {
            Text("PROXIMITY")
                .font(.system(size: 9, weight: .medium))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            if let lid = loads.active?.displayId {
                Text(lid)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
            } else {
                Text("No active load")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Idle

    @ViewBuilder
    private var idleBlock: some View {
        VStack(spacing: 8) {
            primaryButton(
                label: "Broadcast",
                icon: "dot.radiowaves.left.and.right",
                gradient: true,
                enabled: loads.active != nil
            ) {
                WKInterfaceDevice.current().play(.click)
                handoff.startBroadcast(auth: auth, loads: loads)
            }
            secondaryButton(
                label: "Capture",
                icon: "antenna.radiowaves.left.and.right"
            ) {
                WKInterfaceDevice.current().play(.click)
                handoff.startCapture()
            }
            if loads.active == nil {
                Text("Pick a load first to broadcast.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Broadcasting

    @ViewBuilder
    private func broadcastingBlock(expiresAt: Date) -> some View {
        let remaining = max(0, expiresAt.timeIntervalSince(now))
        let total = EusoTripConfig.proximityHandoffWindowSeconds
        let ratio = CGFloat(min(1.0, remaining / total))
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.esangAmber.opacity(0.2), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: ratio)
                    .stroke(Color.esangAmber, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: ratio)
                VStack(spacing: 0) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.esangAmber)
                    Text("\(Int(remaining.rounded()))s")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
            .frame(width: 78, height: 78)

            Text("Hold near terminal")
                .font(.system(size: 11, weight: .semibold))
                .multilineTextAlignment(.center)

            secondaryButton(label: "Stop", icon: "stop.fill") {
                WKInterfaceDevice.current().play(.click)
                handoff.stopBroadcast()
            }
        }
    }

    // MARK: - Receiving

    @ViewBuilder
    private var receivingBlock: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.esangBlue.opacity(0.3), lineWidth: 2)
                    .frame(width: 64, height: 64)
                Circle()
                    .stroke(Color.esangBlue.opacity(0.15), lineWidth: 2)
                    .frame(width: 84, height: 84)
                    .scaleEffect(breathe ? 1.08 : 0.92)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: breathe
                    )
                    .onAppear { breathe = true }
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.esangBlue)
            }
            Text("Listening for a handoff…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            secondaryButton(label: "Cancel", icon: "xmark") {
                WKInterfaceDevice.current().play(.click)
                handoff.stopCapture()
            }
        }
    }

    // MARK: - Captured

    @ViewBuilder
    private func capturedBlock(_ p: HandoffPayload, verified: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: verified ? "checkmark.seal.fill" : "questionmark.seal")
                    .foregroundStyle(verified ? Color.esangGreen : Color.esangAmber)
                Text(verified ? "VERIFIED" : "UNSIGNED")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(verified ? Color.esangGreen : Color.esangAmber)
                Spacer()
            }
            if let dn = p.dn, !dn.isEmpty {
                fieldRow("From", dn)
            }
            fieldRow("Driver", shortId(p.did))
            if let lid = p.lid { fieldRow("Load", lid) }
            fieldRow("Issued", relative(p.ts))
            HStack {
                secondaryButton(label: "Done", icon: "checkmark") {
                    WKInterfaceDevice.current().play(.click)
                    handoff.stopCapture()
                    // Dropping back to idle is handled by the service
                    // layer the next time startCapture / startBroadcast
                    // runs — but we also want the screen to reset so
                    // a second capture can start cleanly.
                    resetToIdle()
                }
                if !verified {
                    secondaryButton(label: "Retry", icon: "arrow.clockwise") {
                        WKInterfaceDevice.current().play(.click)
                        handoff.startCapture()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: R.sm)
                .fill((verified ? Color.esangGreen : Color.esangAmber).opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: R.sm)
                .stroke((verified ? Color.esangGreen : Color.esangAmber).opacity(0.5),
                        lineWidth: 1)
        )
    }

    private func resetToIdle() {
        // ProximityHandoff has no public `reset()` — calling stop*
        // from `.idle` is a no-op, so re-entering the view effectively
        // goes through the idle branch as soon as SwiftUI diffs on the
        // next published state change.
        handoff.stopBroadcast()
        handoff.stopCapture()
    }

    // MARK: - Unsupported + error

    @ViewBuilder
    private var unsupportedBlock: some View {
        VStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text("Bluetooth not available")
                .font(.caption.bold())
            Text("This wrist can't broadcast a handoff beacon.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func errorBlock(_ msg: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "exclamationmark.octagon")
                .foregroundStyle(Color.esangDanger)
            Text(msg)
                .font(.caption2)
                .foregroundStyle(Color.esangDanger)
                .multilineTextAlignment(.center)
            secondaryButton(label: "Dismiss", icon: "xmark") {
                resetToIdle()
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Bits + pieces

    @ViewBuilder
    private func primaryButton(
        label: String,
        icon: String,
        gradient: Bool,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                gradient
                    ? AnyShapeStyle(LinearGradient.esangPrimary)
                    : AnyShapeStyle(Color.esangCard),
                in: RoundedRectangle(cornerRadius: R.sm)
            )
            .foregroundStyle(gradient ? .white : .primary)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }

    @ViewBuilder
    private func secondaryButton(
        label: String, icon: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(Color.esangCard, in: RoundedRectangle(cornerRadius: R.sm))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func fieldRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Formatters

    private func shortId(_ id: String) -> String {
        // Drivers recognize their own id by the trailing 6 chars. Full
        // strings don't fit on a 42mm screen without truncating mid-
        // segment, which looks worse than a clean tail slice.
        if id.count > 8 {
            return "…" + String(id.suffix(6))
        }
        return id
    }

    private func relative(_ ts: Int) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ts))
        let s = -d.timeIntervalSinceNow
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60))m ago" }
        return "\(Int(s / 3600))h ago"
    }
}

#if DEBUG
struct ProximityHandoffView_Previews: PreviewProvider {
    static var previews: some View {
        ProximityHandoffView()
            .environmentObject(AuthStore())
            .environmentObject(LoadStore.shared)
    }
}
#endif
