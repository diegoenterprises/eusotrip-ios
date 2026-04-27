//
//  ConvoyView.swift
//  EusoTrip Pulse Watch App
//
//  F13 — Driver-facing convoy surface.
//
//  Three zones, top to bottom:
//
//    1. Header — leader badge, member count, live mesh state pill.
//       The leader badge says "YOU LEAD" if we're elected; otherwise
//       it shows the short suffix of the leader's driver id. The
//       driver cares about this because the leader is the one whose
//       ETA the whole group adopts, and because leader election
//       decides who the dispatch radio dial usually talks to first.
//
//    2. Body — an SOS banner (if active) over the confirmed-members
//       list. Each member row shows short id, speed mph, cardinal
//       heading, and a trust dot (unknown/confirmed/suspect). The
//       trust state is surfaced on purpose: a "suspect" dot means
//       the fleet-roster check rejected this pubkey and the driver
//       should know NOT to act on that peer's coordination messages.
//       Candidates are grouped underneath at 50% opacity with a
//       "joining" badge — they don't count as convoy yet.
//
//    3. Actions — a single "PROPOSE STOP" button, and the pending
//       stop-proposal card with YES / NO pill buttons when another
//       member has an outstanding proposal.
//
//  The view is reachable from Esang ("show convoy"), from the home
//  screen settings surface, and from any upstream route that pushes
//  .convoy onto `VoiceActionDispatcher.currentRoute`.
//

import SwiftUI
import Combine
import CoreLocation
import WatchKit

struct ConvoyView: View {
    @ObservedObject private var coordinator = ConvoyCoordinator.shared
    @ObservedObject private var mesh = MeshRelay.shared
    @ObservedObject private var signature = ConvoySignatureObservable.shared

    @State private var showingProposeSheet = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 6) {
                    header
                    if let sos = coordinator.activeConvoySOS {
                        sosBanner(sos)
                    }
                    if let proposal = coordinator.pendingStopProposal {
                        proposalCard(proposal)
                    }
                    memberSection
                    candidateSection
                    Spacer(minLength: 2)
                    proposeButton
                    meshFooter
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }

            // Modular Ultra bezel — convoy summary in the four corner
            // labels. Leader id, peer count, SOS state, signature trust.
            ModularTickBezel(
                corners: .init(
                    topLeading:     convoyCornerPeers,
                    topTrailing:    convoyCornerLeader,
                    bottomLeading:  convoyCornerSig,
                    bottomTrailing: convoyCornerAlert
                )
            )
            .allowsHitTesting(false)
        }
        .navigationTitle("Convoy")
        .task {
            // Kick a roster pass so the trust-state pills next to each
            // member reflect the current fleet state by the time the
            // user scrolls to them.
            ConvoyRosterReconciler.shared.reconcileNow()
        }
        .sheet(isPresented: $showingProposeSheet) {
            ProposeStopSheet(
                onSubmit: { reason in
                    coordinator.proposeStop(reason: reason, coordinate: nil)
                    WKInterfaceDevice.current().play(.click)
                    showingProposeSheet = false
                },
                onCancel: { showingProposeSheet = false }
            )
        }
    }

    // MARK: - Modular Ultra corner labels

    private var convoyCornerPeers: String {
        let n = coordinator.members.count
        if n == 0 { return "SOLO" }
        return n == 1 ? "1 PEER" : "\(n) PEERS"
    }

    private var convoyCornerLeader: String {
        guard let leader = coordinator.leaderDriverId else { return "NO LEAD" }
        // Short 4-char suffix of the leader's driver id, uppercased —
        // the in-body header handles "YOU LEAD" vs peer-lead branching;
        // the bezel just surfaces the tail so both look like the same
        // identity at a glance.
        let tail = leader.filter { $0.isLetter || $0.isNumber }.suffix(4).uppercased()
        return tail.isEmpty ? "LEAD" : "LDR·\(tail)"
    }

    private var convoyCornerSig: String {
        signature.isReady ? "SIGNED" : "OPEN"
    }

    private var convoyCornerAlert: String {
        if coordinator.activeConvoySOS != nil { return "SOS" }
        if coordinator.pendingStopProposal != nil { return "VOTE" }
        return "CALM"
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                // Member count gauge.
                Text("\(coordinator.members.count)")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.esangPrimary)
                    .frame(minWidth: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text("IN CONVOY")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.55))
                    Text(leaderLabel)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(leaderTint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
                // Signing readiness pill. A dim pill means we booted on
                // a SEP-less device and inbound verification fell through;
                // mis-signed envelopes are still dropped in that case.
                signatureBadge
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.06))
            )
        }
    }

    private var leaderLabel: String {
        guard let leader = coordinator.leaderDriverId else { return "No leader yet" }
        if leader == localDriverId {
            return "YOU LEAD"
        }
        return "Leader: \(shortId(leader))"
    }

    private var leaderTint: Color {
        guard let leader = coordinator.leaderDriverId else { return .esangTextDim }
        return leader == localDriverId ? .esangMagenta : .esangBlue
    }

    private var signatureBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: signature.isReady ? "lock.fill" : "lock.slash")
                .font(.system(size: 8, weight: .bold))
            Text(signature.isReady ? "SIGNED" : "UNSIGNED")
                .font(.system(size: 7, weight: .heavy))
                .tracking(0.5)
        }
        .foregroundStyle(signature.isReady ? Color.esangGreen : Color.esangAmber)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(Color.white.opacity(0.08))
        )
    }

    // MARK: - SOS banner

    private func sosBanner(_ env: ConvoyEnvelope) -> some View {
        let reason = env.fields["reason"] ?? "unknown"
        return HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold))
            VStack(alignment: .leading, spacing: 0) {
                Text("SOS — \(shortId(env.fromDriverId))")
                    .font(.system(size: 10, weight: .heavy))
                Text(reason)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer()
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.esangDanger.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.esangDanger, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Convoy SOS from \(shortId(env.fromDriverId)): \(reason)")
    }

    // MARK: - Stop proposal card

    private func proposalCard(_ p: ConvoyCoordinator.StopProposal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.esangAmber)
                Text("\(shortId(p.proposerDriverId)) proposes \(p.reason)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            HStack(spacing: 4) {
                Button {
                    coordinator.voteOnStop(true)
                    WKInterfaceDevice.current().play(.click)
                } label: {
                    Text("YES")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.6)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.esangGreen.opacity(0.25))
                                .overlay(Capsule().strokeBorder(Color.esangGreen, lineWidth: 0.8))
                        )
                        .foregroundStyle(Color.esangGreen)
                }
                .buttonStyle(.plain)
                Button {
                    coordinator.voteOnStop(false)
                    WKInterfaceDevice.current().play(.click)
                } label: {
                    Text("NO")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.6)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.esangDanger.opacity(0.25))
                                .overlay(Capsule().strokeBorder(Color.esangDanger, lineWidth: 0.8))
                        )
                        .foregroundStyle(Color.esangDanger)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.esangAmber.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.esangAmber.opacity(0.4), lineWidth: 0.7)
                )
        )
    }

    // MARK: - Members

    @ViewBuilder
    private var memberSection: some View {
        if coordinator.members.isEmpty && coordinator.candidates.isEmpty {
            emptyPlaceholder
        } else if !coordinator.members.isEmpty {
            VStack(spacing: 3) {
                HStack {
                    Text("MEMBERS")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                }
                ForEach(coordinator.members) { m in
                    memberRow(m, dimmed: false)
                }
            }
        }
    }

    @ViewBuilder
    private var candidateSection: some View {
        if !coordinator.candidates.isEmpty {
            VStack(spacing: 3) {
                HStack {
                    Text("JOINING")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                }
                ForEach(coordinator.candidates) { c in
                    memberRow(c, dimmed: true)
                }
            }
            .padding(.top, 2)
        }
    }

    private func memberRow(_ m: ConvoyMember, dimmed: Bool) -> some View {
        let trust = signature.trustStates[m.driverId] ?? .unknown
        return HStack(spacing: 5) {
            Circle()
                .fill(trustColor(trust))
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 0) {
                Text(shortId(m.driverId))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(dimmed ? 0.55 : 0.95))
                    .lineLimit(1)
                Text("\(mphLabel(m.lastSpeedMPS)) · \(cardinalLabel(m.lastHeadingDeg))")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(dimmed ? 0.35 : 0.55))
                    .monospacedDigit()
            }
            Spacer()
            if dimmed {
                Text("JOINING")
                    .font(.system(size: 7, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            } else if coordinator.leaderDriverId == m.driverId {
                Text("LEAD")
                    .font(.system(size: 7, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(Color.esangMagenta)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.esangMagenta.opacity(0.15)))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(dimmed ? 0.03 : 0.06))
        )
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 4) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.esangTextDim)
            Text("No peers in range")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
            Text("Wrist will form a convoy when another\nEusoTrip driver runs alongside.")
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private var proposeButton: some View {
        Button {
            showingProposeSheet = true
            WKInterfaceDevice.current().play(.click)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("PROPOSE STOP")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(LinearGradient.esangPrimary)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(coordinator.members.isEmpty)
        .opacity(coordinator.members.isEmpty ? 0.35 : 1.0)
        .accessibilityLabel("Propose a group stop")
    }

    private var meshFooter: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(mesh.lastBluetoothState.contains("poweredOn") ? Color.esangGreen : Color.esangTextDim)
                .frame(width: 5, height: 5)
            Text("mesh: \(mesh.lastBluetoothState)")
                .font(.system(size: 7))
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text("peers: \(mesh.peersInRange.count)")
                .font(.system(size: 7))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.top, 2)
    }

    // MARK: - Helpers

    private var localDriverId: String {
        // Mirror of ConvoyCoordinator's private localDriverId. Pulled
        // from AuthStore via the singleton so we don't depend on an
        // @EnvironmentObject bind — this view must render from a sheet
        // where the environment isn't always inherited.
        AuthStore.shared?.userId ?? "unpaired"
    }

    private func shortId(_ id: String) -> String {
        // "pulse-7d3f1e12-…" → "…1e12"
        let tail = id.suffix(6)
        return "…\(tail)"
    }

    private func mphLabel(_ mps: Double) -> String {
        let mph = mps * 2.23693629
        return String(format: "%dmph", Int(mph.rounded()))
    }

    private func cardinalLabel(_ deg: Double) -> String {
        let d = (deg.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        switch d {
        case 0..<22.5, 337.5...360: return "N"
        case 22.5..<67.5:           return "NE"
        case 67.5..<112.5:          return "E"
        case 112.5..<157.5:         return "SE"
        case 157.5..<202.5:         return "S"
        case 202.5..<247.5:         return "SW"
        case 247.5..<292.5:         return "W"
        case 292.5..<337.5:         return "NW"
        default:                    return "—"
        }
    }

    private func trustColor(_ state: ConvoySignature.PeerTrustState) -> Color {
        switch state {
        case .confirmed: return .esangGreen
        case .suspect:   return .esangDanger
        case .unknown:   return .esangAmber
        }
    }
}

// MARK: - Propose-stop sheet

private struct ProposeStopSheet: View {
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    private let reasons = ["fuel", "rest", "hos", "food"]

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text("Propose stop for:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.top, 4)
                ForEach(reasons, id: \.self) { r in
                    Button {
                        onSubmit(r)
                    } label: {
                        Text(r.uppercased())
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(Color.white.opacity(0.08))
                                    .overlay(Capsule().strokeBorder(
                                        LinearGradient.esangPrimary.opacity(0.6),
                                        lineWidth: 0.8
                                    ))
                            )
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Observable signature adapter
//
// ConvoySignature itself holds trust state as a plain Dictionary because
// the vast majority of its consumers are backend-y (verify() on the
// ingest path, trustState(for:) called once when a peer is rendered).
// But SwiftUI needs an @Published hook to redraw when a peer flips from
// unknown → confirmed after the fleet-roster check lands. This thin
// @MainActor ObservableObject wraps the signer's public surface so
// ConvoyView can bind to it without pushing ObservableObject into the
// crypto layer itself (which would drag in Combine on a file that's
// otherwise pure Foundation + CryptoKit).

@MainActor
final class ConvoySignatureObservable: ObservableObject {
    static let shared = ConvoySignatureObservable()

    @Published private(set) var isReady: Bool = false
    @Published private(set) var trustStates: [String: ConvoySignature.PeerTrustState] = [:]

    private var pollingTask: Task<Void, Never>?

    func startObserving() {
        pollingTask?.cancel()
        // Poll at 2Hz — trust state changes from roster verification are
        // infrequent (once per peer per minute at the fastest) so even
        // this is far more frequent than needed, and cheaper than
        // instrumenting a publisher into the signer.
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stopObserving() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func refresh() {
        let wasReady = isReady
        let nowReady = ConvoySignature.shared.isReady
        if nowReady != wasReady { isReady = nowReady }

        // Refresh trust states for every confirmed member + candidate.
        var next: [String: ConvoySignature.PeerTrustState] = [:]
        for m in ConvoyCoordinator.shared.members {
            next[m.driverId] = ConvoySignature.shared.trustState(for: m.driverId)
        }
        for c in ConvoyCoordinator.shared.candidates {
            next[c.driverId] = ConvoySignature.shared.trustState(for: c.driverId)
        }
        if next != trustStates { trustStates = next }
    }
}
