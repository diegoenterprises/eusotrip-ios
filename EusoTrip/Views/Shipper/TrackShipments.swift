//
//  TrackShipments.swift
//  Conversational shipment status agent — IO 2026 P0-9.
//
//  Replaces the legacy "search by load ID" pattern. Driver / shipper
//  / dispatcher asks anything in plain language; agent matches up
//  to 6 candidate loads in their scope, composes a Gemini-grounded
//  reply, returns the related load cards inline.
//
//  Hosted under the Shipper Loads tab (and re-used on the Catalyst /
//  Dispatch / Driver tabs since the server scopes per-role).
//
//  Drop into: EusoTrip/Views/Shipper/TrackShipments.swift
//

import SwiftUI

public struct TrackShipmentsView: View {
    @State private var question: String = ""
    @State private var thread: [AgentTurn] = []
    @State private var lastCards: [RelatedLoadCard] = []
    @State private var isAsking: Bool = false
    @State private var errorMessage: String? = nil

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if thread.isEmpty {
                        emptyHint
                    } else {
                        ForEach(thread) { turn in
                            agentTurnRow(turn)
                        }
                    }
                    if !lastCards.isEmpty {
                        cardsBlock
                    }
                    if let err = errorMessage {
                        Text(err)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
            askBar
        }
        .navigationTitle("Track Shipments")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(LinearGradient(
                        colors: [.cyan, .green],
                        startPoint: .leading, endPoint: .trailing
                    ))
                Text("ESANG · SHIPMENT AGENT")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
            Text("Ask anything about your shipments.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var emptyHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try:")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach([
                "Where's my Houston load?",
                "Any of my reefers running warm?",
                "What's blocking settlement on load 1077?",
                "Will it hit the dock before 5pm tomorrow?",
            ], id: \.self) { example in
                Button {
                    question = example
                    Task { await ask() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 10))
                        Text(example)
                            .font(.callout)
                    }
                    .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(.gray.opacity(0.06)))
    }

    @ViewBuilder
    private func agentTurnRow(_ turn: AgentTurn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(turn.question)
                    .font(.callout)
                    .foregroundStyle(.primary)
            }
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(LinearGradient(
                        colors: [.cyan, .green],
                        startPoint: .leading, endPoint: .trailing
                    ))
                Text(turn.answer)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var cardsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Related loads")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(lastCards) { card in
                RelatedLoadRow(card: card)
            }
        }
    }

    private var askBar: some View {
        HStack(spacing: 8) {
            TextField("Ask ESang…", text: $question, axis: .horizontal)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.send)
                .onSubmit { Task { await ask() } }
            Button {
                Task { await ask() }
            } label: {
                if isAsking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.body)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(LinearGradient(
                            colors: [.cyan, .green],
                            startPoint: .leading, endPoint: .trailing
                        ), in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || isAsking)
        }
        .padding(12)
        .background(.bar)
    }

    @MainActor
    private func ask() async {
        let q = question.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isAsking = true
        errorMessage = nil
        defer { isAsking = false }
        do {
            let reply = try await ShipmentAgentService.shared.ask(q)
            thread.append(AgentTurn(question: q, answer: reply.answer))
            lastCards = reply.related ?? []
            question = ""
        } catch {
            errorMessage = "Couldn't reach ESang: \((error as NSError).localizedDescription)"
        }
    }

    private struct AgentTurn: Identifiable, Hashable {
        let id: UUID = UUID()
        let question: String
        let answer: String
    }
}

// MARK: - Related load row

private struct RelatedLoadRow: View {
    let card: RelatedLoadCard

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: equipmentSystemImage)
                .font(.system(size: 16))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(card.displayId)
                        .font(.system(size: 14, weight: .semibold))
                    if let st = card.status {
                        Text(st.uppercased())
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(statusColor.opacity(0.18), in: Capsule())
                            .foregroundStyle(statusColor)
                    }
                    if card.ePodLockEnabled {
                        Label("ePOD lock", systemImage: "lock.shield.fill")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.orange)
                    }
                    Spacer(minLength: 0)
                }
                Text(card.laneLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let cargo = card.cargoType {
                    Text(cargo)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .background(.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private var equipmentSystemImage: String {
        switch card.transportMode ?? "truck" {
        case "rail":   return "tram.fill"
        case "vessel": return "ferry.fill"
        case "barge":  return "ferry"
        default:       return "truck.box.fill"
        }
    }

    private var statusColor: Color {
        guard let s = card.status?.lowercased() else { return .secondary }
        if s.contains("delivered") || s.contains("settled") { return .green }
        if s.contains("transit") || s.contains("en_route") || s.contains("loaded") { return .blue }
        if s.contains("exception") || s.contains("hold") || s.contains("dispute") { return .orange }
        if s.contains("cancel") { return .red }
        return .secondary
    }
}

// MARK: - Previews

#Preview("Track Shipments · Dark") {
    NavigationStack { TrackShipmentsView() }
        .preferredColorScheme(.dark)
}

#Preview("Track Shipments · Light") {
    NavigationStack { TrackShipmentsView() }
        .preferredColorScheme(.light)
}
