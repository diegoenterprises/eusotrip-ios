//
//  USMCAFilingAssistantSheet.swift
//  EusoTrip — IO 2026 Tier 3 #11 · XR USMCA Filing Assistant
//
//  Driver approaches a US-MX or US-CA crossing. Caller passes the
//  cert + commodity + lane + carrier fields; the assistant runs a
//  2-child Cortex fanout server-side (perception parses the cert,
//  guardian emits the filing next-step verdict) and synthesises a
//  1-2 sentence spoken instruction.
//
//  The sheet:
//    1. Renders the form (cert number / lane / HS code / criterion /
//       invoice total / FAST toggle).
//    2. Submits to `xrChecklist.usmcaFilingAssistant`.
//    3. Surfaces the verdict + plays the spoken instruction through
//       ESangTTSPlayer (P0-4 dialect-aware) so the driver hears the
//       guidance at the border without needing to read the screen.
//
//  Wired into 427_CrossBorderWaitForecast as a CTA below the
//  alternates list.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire models

struct USMCAFilingInput: Encodable {
    let loadId: String?
    let certNumber: String
    let shipperCountry: String     // "US" | "MX" | "CA"
    let receiverCountry: String    // "US" | "MX" | "CA"
    let commodityHsCode: String
    let originatingCriterion: String?
    let commercialInvoiceTotalUsd: Double?
    let isFastEligibleCarrier: Bool
}

struct USMCAFilingResponse: Decodable, Hashable {
    let certComplete: Bool
    let missingFields: [String]
    let nextStep: String         // PARS_filing | PAPS_filing | FAST_lane | broker_handoff | hold_for_correction
    let stepDetail: String
    let brokerContactNeeded: Bool
    let citations: [String]
    let spokenInstruction: String
    let auditId: Int?
    let observedAt: String
}

// MARK: - Sheet

public struct USMCAFilingAssistantSheet: View {
    public let loadId: String?
    /// When true, the spoken instruction is played through
    /// ESangTTSPlayer immediately on response. Default true since
    /// this surface fires at the border where the driver's eyes
    /// should stay on the road.
    public let speakInstructionAutomatically: Bool

    public init(loadId: String? = nil, speakInstructionAutomatically: Bool = true) {
        self.loadId = loadId
        self.speakInstructionAutomatically = speakInstructionAutomatically
    }

    @Environment(\.dismiss) private var dismiss

    @State private var certNumber: String = ""
    @State private var shipperCountry: String = "US"
    @State private var receiverCountry: String = "MX"
    @State private var commodityHsCode: String = ""
    @State private var originatingCriterion: String = "" // "" | A | B | C | D
    @State private var invoiceUsdText: String = ""
    @State private var fastEligible: Bool = false

    @State private var submitting: Bool = false
    @State private var result: USMCAFilingResponse?
    @State private var error: String?

    private let countries = ["US", "MX", "CA"]
    private let criteria  = ["", "A", "B", "C", "D"]

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    promptCard
                    certField
                    laneRow
                    hsField
                    criterionPicker
                    invoiceField
                    fastToggle
                    if let result {
                        verdictCard(result)
                    }
                    if let error {
                        Text(error).font(.callout).foregroundStyle(.red)
                    }
                    submitButton
                }
                .padding(16)
            }
            .navigationTitle("USMCA Filing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var canSubmit: Bool {
        let c = certNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let hs = commodityHsCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return c.count >= 2 && hs.count >= 2 && hs.count <= 20 && !submitting && shipperCountry != receiverCountry
    }

    // MARK: subviews

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.caption.weight(.bold))
                Text("ESANG · USMCA FILING ASSIST")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
            }
            .foregroundStyle(.secondary)
            Text("Fill in the cert + lane + commodity. ESANG parses, validates, and tells you the next filing step — out loud.")
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

    private var certField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("USMCA CERT NUMBER").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
            TextField("e.g. USMCA-2026-04412", text: $certNumber)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
        }
    }

    private var laneRow: some View {
        HStack(spacing: 10) {
            countryPicker(label: "FROM", binding: $shipperCountry)
            Image(systemName: "arrow.right")
                .font(.callout.weight(.bold))
                .foregroundStyle(.secondary)
            countryPicker(label: "TO", binding: $receiverCountry)
        }
    }

    private func countryPicker(label: String, binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
            Picker("", selection: binding) {
                ForEach(countries, id: \.self) { c in
                    Text(c).tag(c)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var hsField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("COMMODITY HS CODE").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
            TextField("e.g. 8703.23", text: $commodityHsCode)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
        }
    }

    private var criterionPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ORIGINATING CRITERION (OPTIONAL)").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
            Picker("", selection: $originatingCriterion) {
                ForEach(criteria, id: \.self) { c in
                    Text(c.isEmpty ? "—" : c).tag(c)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var invoiceField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("COMMERCIAL INVOICE (USD, OPTIONAL)").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
            TextField("e.g. 24500", text: $invoiceUsdText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var fastToggle: some View {
        Toggle(isOn: $fastEligible) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Carrier is FAST-eligible").font(.callout.weight(.semibold))
                Text("Enables the FAST lane recommendation when the cert is clean.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if submitting { ProgressView().controlSize(.small) }
                Text(submitting ? "Asking ESANG…" : "Get Next Step")
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canSubmit)
    }

    private func verdictCard(_ r: USMCAFilingResponse) -> some View {
        let color = verdictColor(r.nextStep)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: verdictSymbol(r.nextStep))
                    .foregroundStyle(color)
                Text(prettyStep(r.nextStep))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(color)
                Spacer()
                if r.brokerContactNeeded {
                    Text("BROKER NEEDED")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                        .foregroundStyle(Color.orange)
                }
            }
            Text(r.spokenInstruction)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
            if !r.stepDetail.isEmpty {
                Text(r.stepDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !r.certComplete {
                Label("Cert incomplete: \(r.missingFields.joined(separator: ", "))",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            if !r.citations.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CITATIONS").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.tertiary)
                    ForEach(r.citations, id: \.self) { c in
                        Text("• \(c)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if let id = r.auditId {
                Text("Audit row #\(id) · Ed25519 verified")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
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

    // MARK: pipeline

    private func submit() async {
        submitting = true
        defer { submitting = false }
        error = nil
        let payload = USMCAFilingInput(
            loadId: loadId,
            certNumber: certNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            shipperCountry: shipperCountry,
            receiverCountry: receiverCountry,
            commodityHsCode: commodityHsCode.trimmingCharacters(in: .whitespacesAndNewlines),
            originatingCriterion: originatingCriterion.isEmpty ? nil : originatingCriterion,
            commercialInvoiceTotalUsd: Double(invoiceUsdText),
            isFastEligibleCarrier: fastEligible
        )
        do {
            let resp: USMCAFilingResponse = try await EusoTripAPI.shared
                .xrChecklist.usmcaFilingAssistant(input: payload)
            self.result = resp
            if speakInstructionAutomatically {
                Task.detached { @MainActor in
                    await ESangTTSPlayer.shared.speak(resp.spokenInstruction)
                }
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    // MARK: rendering helpers

    private func prettyStep(_ raw: String) -> String {
        switch raw {
        case "PARS_filing":         return "PARS Filing"
        case "PAPS_filing":         return "PAPS Filing"
        case "FAST_lane":           return "Use FAST Lane"
        case "broker_handoff":      return "Hand Off to Broker"
        case "hold_for_correction": return "Hold for Correction"
        default:                    return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func verdictSymbol(_ raw: String) -> String {
        switch raw {
        case "FAST_lane":           return "bolt.fill"
        case "PARS_filing":         return "doc.text.fill"
        case "PAPS_filing":         return "doc.text.fill"
        case "broker_handoff":      return "person.crop.circle.badge.exclamationmark"
        case "hold_for_correction": return "pause.circle.fill"
        default:                    return "checkmark.shield.fill"
        }
    }

    private func verdictColor(_ raw: String) -> Color {
        switch raw {
        case "FAST_lane":           return .green
        case "PARS_filing", "PAPS_filing": return .blue
        case "broker_handoff":      return .orange
        case "hold_for_correction": return .red
        default:                    return .secondary
        }
    }
}

// MARK: - Previews

#Preview("Empty · Dark") {
    USMCAFilingAssistantSheet(loadId: "load_1077")
        .preferredColorScheme(.dark)
}

#Preview("Empty · Light") {
    USMCAFilingAssistantSheet(loadId: nil, speakInstructionAutomatically: false)
        .preferredColorScheme(.light)
}
