//
//  CarrierVetSheet.swift
//  EusoTrip — IO 2026 Tier 2 #38 · Carrier vetting agent
//
//  Backed by `carrierVetAgent.vet`. Caller types a DOT number
//  (and optionally a follow-up question — "can they haul hazmat
//  in TX?") and ESANG returns a guarded verdict:
//
//    perception → parse FMCSA snapshot (authority + insurance +
//                 BASIC + hazmat authority)
//    memory     → summarize EusoTrip historical scorecard
//    guardian   → verdict {pass | needs_review | fail}
//                 + redFlags[] + citations[] (FMCSA §, 49 CFR §)
//
//  Recent vettings show below the active result so the broker
//  can re-glance a DOT they already vetted today.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire models

enum CarrierVetVerdict: String, Codable, Hashable {
    case pass
    case needsReview = "needs_review"
    case fail
}

struct CarrierVetScorecard: Decodable, Hashable {
    let pastLoadCount: Int
    let onTimePct: Double?
    let defectsCount: Int
    let avgRating: Double?
}

struct CarrierVetResponse: Decodable, Hashable {
    let generatedAtUtc: String
    let dotNumber: String
    let verdict: CarrierVetVerdict
    let eusotripScorecard: CarrierVetScorecard?
    let redFlags: [String]
    let citations: [String]
    let synthesis: String
    let childrenFiredCount: Int
}

struct CarrierVetInput: Encodable {
    let dotNumber: String
    let question: String?
    let companyId: Int
}

struct CarrierVetHistoryItem: Decodable, Hashable, Identifiable {
    var id: String { (dotNumber ?? "") + (timestamp ?? UUID().uuidString) }
    let dotNumber: String?
    let verdict: String?
    let redFlagsCount: Int?
    let synthesisPreview: String?
    let timestamp: String?
}

// MARK: - Sheet

public struct CarrierVetSheet: View {
    public let companyId: Int
    public let prefillDot: String?

    public init(companyId: Int, prefillDot: String? = nil) {
        self.companyId = companyId
        self.prefillDot = prefillDot
    }

    @Environment(\.dismiss) private var dismiss
    @State private var dotNumber: String = ""
    @State private var question: String = ""
    @State private var submitting: Bool = false
    @State private var current: CarrierVetResponse?
    @State private var history: [CarrierVetHistoryItem] = []
    @State private var error: String?

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    promptCard
                    dotField
                    questionField
                    submitButton
                    if submitting {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("ESANG is vetting…")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    if let error {
                        Text(error).font(.callout).foregroundStyle(.red)
                    }
                    if let current {
                        verdictCard(current)
                    }
                    historySection
                }
                .padding(16)
            }
            .navigationTitle("Carrier Vet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if let p = prefillDot, !p.isEmpty, dotNumber.isEmpty {
                    dotNumber = p
                }
                await loadHistory()
            }
        }
    }

    private var canSubmit: Bool {
        let d = dotNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return d.count >= 3 && !submitting
    }

    // MARK: subviews

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.caption.weight(.bold))
                Text("ESANG · CARRIER VET")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
            }
            .foregroundStyle(.secondary)
            Text("Type a DOT number. ESANG pulls FMCSA + your scorecard and emits a guarded verdict with citations.")
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

    private var dotField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DOT NUMBER").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
            TextField("e.g. 123456", text: $dotNumber)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var questionField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FOLLOW-UP QUESTION (OPTIONAL)").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
            TextField("e.g. Can they haul hazmat in TX?", text: $question)
                .textInputAutocapitalization(.sentences)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if submitting { ProgressView().controlSize(.small) }
                Text(submitting ? "Vetting…" : "Run Vet")
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canSubmit)
    }

    @ViewBuilder
    private func verdictCard(_ r: CarrierVetResponse) -> some View {
        let color = verdictColor(r.verdict)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: verdictSymbol(r.verdict))
                    .foregroundStyle(color)
                Text(verdictLabel(r.verdict))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(color)
                Spacer()
                Text("DOT \(r.dotNumber)")
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(.tertiary)
            }
            Text(r.synthesis)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
            if let s = r.eusotripScorecard {
                scorecardRow(s)
            } else {
                Text("No prior loads with this carrier — scorecard not available.")
                    .font(.footnote).foregroundStyle(.tertiary)
            }
            if !r.redFlags.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RED FLAGS")
                        .font(.caption2.weight(.bold)).tracking(0.8)
                        .foregroundStyle(.tertiary)
                    ForEach(r.redFlags, id: \.self) { f in
                        Label(f, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }
            if !r.citations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CITATIONS").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.tertiary)
                    ForEach(r.citations, id: \.self) { c in
                        Text("• \(c)").font(.caption2).foregroundStyle(.secondary)
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
                .fill(color.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color.opacity(0.4), lineWidth: 1.0)
        )
    }

    private func scorecardRow(_ s: CarrierVetScorecard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("EUSOTRIP SCORECARD (LAST 365D)")
                .font(.caption2.weight(.bold)).tracking(0.8)
                .foregroundStyle(.tertiary)
            HStack(spacing: 14) {
                stat(label: "LOADS",    value: "\(s.pastLoadCount)")
                if let pct = s.onTimePct {
                    stat(label: "ON-TIME", value: "\(Int(pct))%")
                }
                stat(label: "DEFECTS",  value: "\(s.defectsCount)")
                if let r = s.avgRating {
                    stat(label: "RATING", value: String(format: "%.1f", r))
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
            Text(value).font(.body.weight(.heavy).monospacedDigit()).foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var historySection: some View {
        if !history.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("RECENT VETTINGS")
                    .font(.caption2.weight(.bold)).tracking(0.8)
                    .foregroundStyle(.tertiary)
                ForEach(history) { item in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("DOT \(item.dotNumber ?? "?")")
                                    .font(.footnote.weight(.bold))
                                if let v = item.verdict, !v.isEmpty {
                                    Text(v.uppercased())
                                        .font(.caption2.weight(.bold))
                                        .tracking(0.8)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(historyVerdictColor(v).opacity(0.18)))
                                        .foregroundStyle(historyVerdictColor(v))
                                }
                            }
                            if let s = item.synthesisPreview {
                                Text(s).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer(minLength: 4)
                        if let r = item.redFlagsCount, r > 0 {
                            Label("\(r)", systemImage: "exclamationmark.triangle")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.orange)
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

    // MARK: rendering helpers

    private func verdictLabel(_ v: CarrierVetVerdict) -> String {
        switch v {
        case .pass:        return "PASS"
        case .needsReview: return "NEEDS REVIEW"
        case .fail:        return "FAIL"
        }
    }
    private func verdictSymbol(_ v: CarrierVetVerdict) -> String {
        switch v {
        case .pass:        return "checkmark.seal.fill"
        case .needsReview: return "exclamationmark.circle.fill"
        case .fail:        return "xmark.octagon.fill"
        }
    }
    private func verdictColor(_ v: CarrierVetVerdict) -> Color {
        switch v {
        case .pass:        return .green
        case .needsReview: return .orange
        case .fail:        return .red
        }
    }
    private func historyVerdictColor(_ raw: String) -> Color {
        switch raw.lowercased() {
        case "pass":          return .green
        case "fail":          return .red
        case "needs_review":  return .orange
        default:              return .secondary
        }
    }

    // MARK: pipeline

    private func submit() async {
        submitting = true
        defer { submitting = false }
        error = nil
        let trimmedDot = dotNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = CarrierVetInput(
            dotNumber: trimmedDot,
            question: q.isEmpty ? nil : q,
            companyId: companyId
        )
        do {
            let resp: CarrierVetResponse = try await EusoTripAPI.shared
                .carrierVetAgent.vet(input: payload)
            self.current = resp
            await loadHistory()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func loadHistory() async {
        do {
            let items: [CarrierVetHistoryItem] = try await EusoTripAPI.shared
                .carrierVetAgent.getRecentVettings(companyId: companyId, limit: 8)
            self.history = items
        } catch {
            // Silent — history is optional context.
        }
    }
}

// MARK: - Previews

#Preview("Empty · Dark") {
    CarrierVetSheet(companyId: 1)
        .preferredColorScheme(.dark)
}

#Preview("Pre-filled · Light") {
    CarrierVetSheet(companyId: 1, prefillDot: "123456")
        .preferredColorScheme(.light)
}
