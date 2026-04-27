//
//  OutboxStatusView.swift
//  EusoTrip Pulse Watch App
//
//  Five-lane Unified Outbox monitor. Reachable from the settings
//  surface + from Esang via "show queued messages". The driver sees
//  what's pending by priority; dispatch can use a screenshot to
//  diagnose stuck retries without pulling logs.
//
//  Each row: lane label · pending count · oldest age · top error.
//  Stale / in-backoff entries carry an amber tint.
//

import SwiftUI

struct OutboxStatusView: View {
    @StateObject private var outbox = OfflineQueue.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(OutboxLane.allCases, id: \.self) { lane in
                    laneRow(lane)
                }
                if outbox.entries.isEmpty {
                    Text("All synced")
                        .font(.caption2)
                        .foregroundStyle(Color.esangGreen)
                        .padding(.top, 16)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .navigationTitle("Outbox")
        // Outbox rows use a subtle white-overlay card that reaches the
        // edge; clip to the bezel so the card corners don't show
        // through the rounded display corners.
        .clipShape(ContainerRelativeShape())
    }

    @ViewBuilder
    private func laneRow(_ lane: OutboxLane) -> some View {
        let entries = outbox.entries(in: lane)
        let count = entries.count
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(lane.label)
                    .font(.caption.bold())
                    .foregroundStyle(laneTint(lane))
                Spacer()
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(count > 0 ? Color.esangAmber : .secondary)
            }
            if let oldest = entries.min(by: { $0.enqueuedAt < $1.enqueuedAt }) {
                let mins = Int(-oldest.enqueuedAt.timeIntervalSinceNow / 60)
                Text("oldest: \(mins)m · retries: \(oldest.attempts)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                if let err = oldest.lastError {
                    Text(err)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.esangDanger)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func laneTint(_ lane: OutboxLane) -> Color {
        switch lane {
        case .sos:     return .esangDanger
        case .hos:     return .esangAmber
        case .load:    return .esangBlue
        case .voice:   return .esangListening
        case .message: return .secondary
        }
    }
}
