//
//  DockWorkerPodSheet.swift
//  EusoTrip — IO 2026 Tier 3 #10 · Dock Worker POD capture
//
//  Counter-party POD sign-off for the receiver's dock worker.
//  Driver hands the phone to the dock worker at delivery (or
//  the receiver's terminal manager opens the sheet from their
//  own role surface); the worker enters their name + title +
//  seal verification + optional notes and submits.
//
//  The server (`xrChecklist.dockWorkerPodCapture`) chains the
//  resulting audit row off the driver's existing `load.pod_captured`
//  block when one exists. The sheet surfaces `chainedToDriverPod`
//  so the worker sees "✓ matched to driver POD" inline.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Wire models

struct DockWorkerPodInput: Encodable {
    let loadId: String
    let dockWorkerName: String
    let dockWorkerTitle: String?
    let sealVerified: Bool
    let osdReportRef: String?
    let notes: String?
}

public struct DockWorkerPodResponse: Decodable, Hashable {
    public let loadId: Int
    public let auditId: Int?
    public let observedAt: String
    public let chainedToDriverPod: Bool
    public let signature: XRSignatureBlock
}

/// Mirrors the canonical Ed25519 signature envelope the server
/// emits across every audit-chain row.
public struct XRSignatureBlock: Codable, Hashable {
    public let digestSha256B64: String
    public let signatureBytesB64: String
    public let publicKeyB64: String
}

// MARK: - Sheet

public struct DockWorkerPodSheet: View {
    /// Resolved load identifier — accepts numeric ("1077") or
    /// load-number ("load_1077"); the server normalizes either.
    public let loadId: String
    /// Optional Astra OS&D audit-row reference. Pass the digest
    /// from a recent OS&D capture so this POD row chains to
    /// both the driver POD and the OS&D evidence in one tree.
    public let osdReportRef: String?
    /// Called when the audit row lands so the parent screen can
    /// dismiss + flip its FSM gate.
    public let onSigned: ((DockWorkerPodResponse) -> Void)?

    public init(
        loadId: String,
        osdReportRef: String? = nil,
        onSigned: ((DockWorkerPodResponse) -> Void)? = nil
    ) {
        self.loadId = loadId
        self.osdReportRef = osdReportRef
        self.onSigned = onSigned
    }

    @Environment(\.dismiss) private var dismiss

    @State private var workerName: String = ""
    @State private var workerTitle: String = ""
    @State private var sealVerified: Bool = false
    @State private var notes: String = ""
    @State private var submitting: Bool = false
    @State private var result: DockWorkerPodResponse?
    @State private var error: String?

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    promptCard
                    nameField
                    titleField
                    sealToggle
                    notesField
                    if let result {
                        verdictCard(result)
                    }
                    if let error {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                    submitButton
                }
                .padding(16)
            }
            .navigationTitle("Dock Worker POD")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var canSubmit: Bool {
        let trimmed = workerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 2 && trimmed.count <= 120 && !submitting && result == nil
    }

    // MARK: subviews

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.badge.shield.checkmark")
                    .font(.caption.weight(.bold))
                Text("RECEIVER · DOCK WORKER SIGN-OFF")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
            }
            .foregroundStyle(.secondary)
            Text("Confirm load \(loadId) was received. This signature chains off the driver's POD on the audit ledger.")
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

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("YOUR NAME").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
            TextField("e.g. Jamal Reyes", text: $workerName)
                .textInputAutocapitalization(.words)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TITLE (OPTIONAL)").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
            TextField("e.g. Receiving Supervisor", text: $workerTitle)
                .textInputAutocapitalization(.words)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var sealToggle: some View {
        Toggle(isOn: $sealVerified) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Seal verified")
                    .font(.callout.weight(.semibold))
                Text("Seal number on the BOL matches the one on the trailer.")
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

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NOTES (OPTIONAL)").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
            TextEditor(text: $notes)
                .frame(minHeight: 80)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
        }
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if submitting {
                    ProgressView().controlSize(.small)
                }
                Text(submitting ? "Signing…" : "Sign POD")
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canSubmit)
    }

    private func verdictCard(_ resp: DockWorkerPodResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Color.green)
                Text("POD signed")
                    .font(.headline)
                    .foregroundStyle(Color.green)
                Spacer()
                if resp.chainedToDriverPod {
                    Text("MATCHED TO DRIVER POD")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.green.opacity(0.18)))
                        .foregroundStyle(Color.green)
                } else {
                    Text("STANDALONE")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.orange.opacity(0.18)))
                        .foregroundStyle(Color.orange)
                }
            }
            if let id = resp.auditId {
                Text("Audit row #\(id) · Ed25519 verified")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.green.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.green.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: submit

    private func submit() async {
        submitting = true
        defer { submitting = false }
        error = nil
        let payload = DockWorkerPodInput(
            loadId: loadId,
            dockWorkerName: workerName.trimmingCharacters(in: .whitespacesAndNewlines),
            dockWorkerTitle: workerTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : workerTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            sealVerified: sealVerified,
            osdReportRef: osdReportRef,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            let resp: DockWorkerPodResponse = try await EusoTripAPI.shared
                .xrChecklist.dockWorkerPodCapture(input: payload)
            self.result = resp
            onSigned?(resp)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}

// MARK: - Previews

#Preview("Empty · Dark") {
    DockWorkerPodSheet(loadId: "load_1077")
        .preferredColorScheme(.dark)
}

#Preview("Pre-filled · Light") {
    DockWorkerPodSheet(loadId: "1077", osdReportRef: "abc123digestB64")
        .preferredColorScheme(.light)
}
