//
//  LaneIntelSheet.swift
//  EusoTrip — IO 2026 Tier 2 #37 · Lane intelligence + pricing agent
//
//  Conversational rate-intel surface backed by `laneAgent.query`.
//  Broker / Catalyst types a natural-language question like
//  "ATL → MIA dry van 38k Tuesday" and the agent returns:
//
//    parsedLane   → structured fields (origin / dest / trailer / etc.)
//    rateBand     → loSwap / median / hiSwap over last-90d comparables
//    drivers      → 2-4 directional drivers (capacity, fuel, season…)
//    surcharges   → expected line items (FSC, detention, etc.) + $est
//    synthesis    → one-paragraph broker advisory
//
//  History (laneAgent.getRecent) renders below the active query so
//  the founder can revisit prior calls.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire models

struct LaneAgentParsedLane: Decodable, Hashable {
    let origin: String?
    let dest: String?
    let trailerType: String?
    let miles: Double?
    let weightLbs: Double?
    let notes: String?
}

struct LaneRateBand: Decodable, Hashable {
    let loSwap: Double
    let median: Double
    let hiSwap: Double
    let basis: String
    let comparableLoadCount: Int
}

struct LaneSurcharge: Decodable, Hashable {
    let label: String
    let estUsd: Double
    let reason: String
}

struct LaneAgentResponse: Decodable, Hashable {
    let generatedAtUtc: String
    let parsedLane: LaneAgentParsedLane
    let rateBand: LaneRateBand?
    let drivers: [String]
    let surcharges: [LaneSurcharge]
    let synthesis: String
    let childrenFiredCount: Int
}

struct LaneAgentQueryInput: Encodable {
    let question: String
    let originState: String?
    let destState: String?
    let trailerType: String?
    let miles: Double?
    let weightLbs: Double?
    let companyId: Int
    let parentThoughtSignature: String?
}

/// Compact history row returned by `laneAgent.getRecent` — server
/// stores only a preview snapshot in `blockchain_audit_trail`,
/// not the full envelope. We render question + median + timestamp.
struct LaneAgentHistoryItem: Decodable, Hashable, Identifiable {
    var id: String { timestamp ?? UUID().uuidString }
    let question: String?
    let rateBandMedian: Double?
    let synthesisPreview: String?
    let timestamp: String?
}

// MARK: - Sheet

public struct LaneIntelSheet: View {
    /// Broker / Catalyst company id (mandatory for the server call).
    public let companyId: Int

    public init(companyId: Int) { self.companyId = companyId }

    @Environment(\.dismiss) private var dismiss
    @State private var question: String = ""
    @State private var submitting: Bool = false
    @State private var current: LaneAgentResponse?
    @State private var history: [LaneAgentHistoryItem] = []
    @State private var error: String?

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    promptCard
                    questionField
                    submitButton
                    if submitting {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("ESANG is reading the lane…")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    if let error {
                        Text(error).font(.callout).foregroundStyle(.red)
                    }
                    if let current {
                        responseCard(current)
                    }
                    historySection
                }
                .padding(16)
            }
            .navigationTitle("Lane Intel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadHistory() }
        }
    }

    // MARK: subviews

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.caption.weight(.bold))
                Text("ESANG · LANE INTEL")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
            }
            .foregroundStyle(.secondary)
            Text("Type a lane question. ESANG parses + rates against the last 90 days of comparable settlements.")
                .font(.callout)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var questionField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("YOUR QUESTION").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
            TextField("e.g. ATL → MIA dry van 38k next Tuesday", text: $question, axis: .vertical)
                .lineLimit(3...4)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if submitting { ProgressView().controlSize(.small) }
                Text(submitting ? "Asking ESANG…" : "Ask")
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).count < 4 || submitting)
    }

    @ViewBuilder
    private func responseCard(_ r: LaneAgentResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Parsed lane chip
            parsedLaneChip(r.parsedLane)
            // Rate band
            if let band = r.rateBand {
                rateBandView(band)
            } else {
                Text("No comparable settlements in last 90 days — rate band unavailable.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            // Synthesis paragraph
            Text(r.synthesis)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
            // Drivers
            if !r.drivers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DRIVERS").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.tertiary)
                    ForEach(r.drivers, id: \.self) { d in
                        Text("• \(d)").font(.footnote).foregroundStyle(.primary)
                    }
                }
            }
            // Surcharges
            if !r.surcharges.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SURCHARGES").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.tertiary)
                    ForEach(Array(r.surcharges.enumerated()), id: \.offset) { _, s in
                        HStack {
                            Text(s.label).font(.footnote.weight(.semibold))
                            Spacer()
                            Text("$\(Int(s.estUsd))")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if !s.reason.isEmpty {
                            Text(s.reason).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            Text("Generated \(r.generatedAtUtc) · \(r.childrenFiredCount) Cortex children")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func parsedLaneChip(_ p: LaneAgentParsedLane) -> some View {
        HStack(spacing: 6) {
            chip(p.origin ?? "?", icon: "mappin.circle")
            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
            chip(p.dest ?? "?", icon: "mappin.and.ellipse")
            if let tt = p.trailerType {
                chip(tt.replacingOccurrences(of: "_", with: " ").capitalized, icon: "truck.box")
            }
            if let m = p.miles, m > 0 {
                chip("\(Int(m)) mi", icon: "ruler")
            }
            if let w = p.weightLbs, w > 0 {
                chip("\(Int(w)) lb", icon: "scalemass")
            }
        }
    }

    private func chip(_ label: String, icon: String) -> some View {
        Label(label, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    private func rateBandView(_ band: LaneRateBand) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RATE BAND")
                    .font(.caption2.weight(.bold)).tracking(0.8)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(band.comparableLoadCount) comparable")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                rateCol(label: "LOW",    usd: band.loSwap,  emphasis: Color.secondary)
                rateCol(label: "MEDIAN", usd: band.median,  emphasis: Color.primary)
                rateCol(label: "HIGH",   usd: band.hiSwap,  emphasis: Color.secondary)
            }
            // Visual band
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(
                            colors: [.green, .yellow, .red],
                            startPoint: .leading, endPoint: .trailing
                        ).opacity(0.4))
                        .frame(height: 6)
                    // Median marker
                    if band.hiSwap > band.loSwap {
                        let frac = (band.median - band.loSwap) / (band.hiSwap - band.loSwap)
                        Circle()
                            .fill(Color.primary)
                            .frame(width: 10, height: 10)
                            .offset(x: max(0, min(1, frac)) * (geo.size.width - 10))
                    }
                }
            }
            .frame(height: 12)
            if !band.basis.isEmpty {
                Text(band.basis).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    private func rateCol(label: String, usd: Double, emphasis: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.tertiary)
            Text("$\(Int(usd))")
                .font(.title3.weight(.heavy).monospacedDigit())
                .foregroundStyle(emphasis)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var historySection: some View {
        if !history.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("RECENT")
                    .font(.caption2.weight(.bold)).tracking(0.8)
                    .foregroundStyle(.tertiary)
                ForEach(history) { item in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.question ?? "—")
                                .font(.footnote.weight(.semibold))
                                .lineLimit(2)
                            if let prev = item.synthesisPreview, !prev.isEmpty {
                                Text(prev).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer(minLength: 4)
                        if let m = item.rateBandMedian, m > 0 {
                            Text("$\(Int(m))")
                                .font(.footnote.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
            }
        }
    }

    // MARK: pipeline

    private func submit() async {
        submitting = true
        defer { submitting = false }
        error = nil
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = LaneAgentQueryInput(
            question: trimmed,
            originState: nil,
            destState: nil,
            trailerType: nil,
            miles: nil,
            weightLbs: nil,
            companyId: companyId,
            parentThoughtSignature: nil
        )
        do {
            let resp: LaneAgentResponse = try await EusoTripAPI.shared
                .laneAgent.query(input: payload)
            self.current = resp
            await loadHistory()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func loadHistory() async {
        do {
            let items: [LaneAgentHistoryItem] = try await EusoTripAPI.shared
                .laneAgent.getRecent(companyId: companyId, limit: 5)
            self.history = items
        } catch {
            // Silent: history is optional context.
        }
    }
}

// MARK: - Previews

#Preview("Empty · Dark") {
    LaneIntelSheet(companyId: 1)
        .preferredColorScheme(.dark)
}

#Preview("Empty · Light") {
    LaneIntelSheet(companyId: 1)
        .preferredColorScheme(.light)
}
