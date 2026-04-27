//
//  UWBDockingCoachView.swift
//  EusoTrip Pulse Watch App
//
//  Q3 — Coach view for Ultra-Wideband docking. Three entry points:
//
//    1. Home shortcut ("Couple Trailer") → .trailerCoupling
//    2. Home shortcut ("Back to Dock")    → .dockBackin
//    3. POD flow ("Confirm Signer")        → .dockhandHandoff
//
//  The view itself is deliberately sparse — one big distance readout,
//  a bearing arrow when we have direction data, and a state pill on
//  top. The haptic ticker (driven by UWBDocking.hapticCadenceSeconds)
//  is the primary coaching signal; the driver should be able to use
//  their mirrors, not the wrist, to position the vehicle.
//

import SwiftUI
import WatchKit

struct UWBDockingCoachView: View {
    @ObservedObject private var docking = UWBDocking.shared

    let scenario: UWBDockingScenario

    init(scenario: UWBDockingScenario = .trailerCoupling) {
        self.scenario = scenario
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                statePill
                distanceReadout
                bearingArrow
                hintLine
                actionButton
                // Show the live scenario band + haptic cadence so the
                // driver can diagnose silent-tick failures without
                // pulling logs.
                metaFooter
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .navigationTitle(titleFor(scenario))
        .onAppear {
            // Kick the session on view appearance. Safe to call
            // repeatedly — beginDiscovery re-uses an existing NISession
            // rather than churning the discovery token.
            docking.beginDiscovery(scenario: scenario)
        }
        .onDisappear {
            // Handoff scenarios are one-shot; coupling + dock-backin
            // stay alive while the driver is positioning, but we still
            // collapse the session when the coach view goes away so
            // we don't hold a U1 session open across home-screen hops.
            docking.endRanging()
        }
    }

    // MARK: - State pill

    @ViewBuilder
    private var statePill: some View {
        let (label, tint) = pillFor(docking.state)
        Text(label)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(tint.opacity(0.22))
            )
            .overlay(
                Capsule().stroke(tint.opacity(0.6), lineWidth: 1)
            )
            .foregroundStyle(tint)
    }

    private func pillFor(_ s: UWBDockingState) -> (String, Color) {
        switch s {
        case .unsupported:   return ("NO U1 CHIP", .esangDanger)
        case .idle:          return ("OFF", .secondary)
        case .awaitingPeer:  return ("PAIRING", .esangAmber)
        case .discovering:   return ("LOCATING", .esangAmber)
        case .ranging:       return ("LIVE", .esangGreen)
        case .handoff:       return ("DONE", .esangGreen)
        case .error(let m):  return (m.uppercased().prefix(12) + "", .esangDanger)
        }
    }

    // MARK: - Distance readout

    @ViewBuilder
    private var distanceReadout: some View {
        let meters: Float? = {
            if case .ranging(let d, _) = docking.state { return d }
            return nil
        }()
        VStack(spacing: 0) {
            if let m = meters {
                Text(formatDistance(m))
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tintFor(m))
                Text(m < 0.914 ? "IN" : "FT")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("—")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }

    private func formatDistance(_ meters: Float) -> String {
        // Switch to inches under 3 feet — the kingpin is the one place
        // on a truck where feet-and-inches is wrong (you want pure
        // inches in the last foot).
        let feet = meters * 3.28084
        if feet < 3 {
            let inches = feet * 12
            return String(format: "%.0f", max(0, inches))
        }
        return String(format: "%.1f", feet)
    }

    private func tintFor(_ m: Float) -> Color {
        switch scenario {
        case .trailerCoupling:
            if m <= 0.15 { return .esangGreen }
            if m <= 0.40 { return .esangAmber }
            return .primary
        case .dockBackin:
            if m <= 0.6 { return .esangGreen }
            if m <= 1.5 { return .esangAmber }
            return .primary
        case .dockhandHandoff:
            if m <= 0.6 { return .esangGreen }
            return .primary
        }
    }

    // MARK: - Bearing arrow

    @ViewBuilder
    private var bearingArrow: some View {
        let bearing: Float? = {
            if case .ranging(_, let b) = docking.state { return b }
            return nil
        }()
        if let b = bearing {
            Image(systemName: "arrow.up")
                .font(.system(size: 28, weight: .bold))
                .rotationEffect(.degrees(Double(b)))
                .foregroundStyle(Color.esangAmber)
                .padding(4)
                .background(
                    Circle().fill(Color.white.opacity(0.06))
                )
        }
    }

    // MARK: - Hint line

    @ViewBuilder
    private var hintLine: some View {
        let text: String = {
            switch docking.state {
            case .awaitingPeer:  return "Waiting on \(peerLabel())…"
            case .discovering:   return "Locating \(peerLabel())"
            case .ranging(let d, _):
                switch scenario {
                case .trailerCoupling:
                    if d <= 0.15 { return "Kingpin set. Bite it." }
                    if d <= 0.40 { return "Ease back." }
                    return "Line up the fifth wheel."
                case .dockBackin:
                    if d <= 0.6 { return "Bumper kissing. Stop." }
                    if d <= 1.5 { return "Crawl speed." }
                    return "Straighten the trailer."
                case .dockhandHandoff:
                    if d <= 0.6 { return "Signer verified." }
                    return "Bring your wrists together."
                }
            case .handoff(let r):
                return "Handoff logged · \(r)"
            case .error(let m):
                return m
            default:
                return ""
            }
        }()
        if !text.isEmpty {
            Text(text)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func peerLabel() -> String {
        switch scenario {
        case .trailerCoupling:  return "trailer beacon"
        case .dockBackin:       return "dock bumper"
        case .dockhandHandoff:  return "dockhand"
        }
    }

    // MARK: - Action

    @ViewBuilder
    private var actionButton: some View {
        if scenario == .dockhandHandoff, case .ranging(let d, _) = docking.state, d <= 0.6 {
            Button {
                docking.completeHandoff(recipient: "dockhand")
            } label: {
                Text("CONFIRM SIGNER")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
            }
            .tint(.esangGreen)
            .padding(.top, 4)
        } else if case .handoff = docking.state {
            // Nothing — handoff complete; navigation will pop on timer.
            EmptyView()
        } else {
            Button {
                WKInterfaceDevice.current().play(.stop)
                docking.endRanging()
            } label: {
                Text("CANCEL")
                    .font(.caption2)
                    .frame(maxWidth: .infinity)
            }
            .tint(.secondary)
            .padding(.top, 4)
        }
    }

    // MARK: - Meta footer

    @ViewBuilder
    private var metaFooter: some View {
        let cadence = docking.hapticCadenceSeconds()
        HStack(spacing: 8) {
            Label(bandLabel(scenario), systemImage: "dot.radiowaves.left.and.right")
            Spacer()
            if let c = cadence {
                Text("\(Int(1.0 / max(0.05, c)))/s")
                    .monospacedDigit()
            } else {
                Text("—")
            }
        }
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
        .padding(.top, 6)
    }

    private func bandLabel(_ s: UWBDockingScenario) -> String {
        switch s {
        case .trailerCoupling:  return "kingpin band"
        case .dockBackin:       return "dock band"
        case .dockhandHandoff:  return "signer band"
        }
    }

    private func titleFor(_ s: UWBDockingScenario) -> String {
        switch s {
        case .trailerCoupling:  return "Couple"
        case .dockBackin:       return "Back In"
        case .dockhandHandoff:  return "Handoff"
        }
    }
}

#if DEBUG
struct UWBDockingCoachView_Previews: PreviewProvider {
    static var previews: some View {
        UWBDockingCoachView(scenario: .trailerCoupling)
    }
}
#endif
