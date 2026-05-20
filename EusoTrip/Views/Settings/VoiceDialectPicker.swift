//
//  VoiceDialectPicker.swift
//  Settings — regional dialect picker (IO 2026 P0-4).
//
//  Lets the user pick their preferred regional dialect (es-MX,
//  fr-CA, en-AU, en-US-SW, en-US-SE, pt-BR…). Saves to both local
//  UserDefaults (offline-first) and server-side
//  `freight_ai_profiles.preferred_voice_dialect` (cross-device parity).
//
//  Hosted from `211_ShipperSettings`, `319_EsangSettings`, and the
//  driver Settings hub. Same component on every surface — single
//  truth, no per-role drift.
//
//  Drop into: EusoTrip/Views/Settings/VoiceDialectPicker.swift
//

import SwiftUI

public struct VoiceDialectPicker: View {
    @ObservedObject private var pref = UserVoicePreference.shared
    @State private var savingDialect: VoiceDialect? = nil
    @State private var errorMessage: String? = nil
    @State private var previewingDialect: VoiceDialect? = nil

    public init() {}

    public var body: some View {
        List {
            Section {
                ForEach(VoiceDialect.allCases) { dialect in
                    Button {
                        Task { await pick(dialect) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: dialect.systemImage)
                                .frame(width: 24)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dialect.displayName)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text(dialect.previewPhrase)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)

                            // Saving indicator on the row being saved.
                            if savingDialect == dialect {
                                ProgressView()
                                    .controlSize(.small)
                            } else if pref.current == dialect {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }

                            // Preview button — speaks the dialect's
                            // preview phrase using the on-device synth.
                            Button {
                                Task {
                                    previewingDialect = dialect
                                    await ESangTTSPlayer.shared.preview(dialect)
                                    previewingDialect = nil
                                }
                            } label: {
                                Image(systemName: previewingDialect == dialect
                                      ? "speaker.wave.2.fill"
                                      : "speaker.wave.2")
                                    .foregroundStyle(.tint)
                            }
                            .buttonStyle(.plain)
                            .disabled(previewingDialect != nil)
                            .accessibilityLabel("Preview \(dialect.displayName)")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(savingDialect != nil)
                }
            } header: {
                Text("ESang voice dialect")
            } footer: {
                Text("ESang speaks replies in the dialect you choose. Voice transcription also uses this language. Pick \"System default\" to follow your device language.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                } header: {
                    Text("Couldn't save")
                }
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Reconcile with server's stored value when the picker opens.
            await pref.reconcileFromServer()
        }
    }

    @MainActor
    private func pick(_ dialect: VoiceDialect) async {
        guard pref.current != dialect else { return }
        savingDialect = dialect
        errorMessage = nil
        do {
            try await pref.set(dialect)
            // Audible confirmation — speak the preview in the new dialect.
            await ESangTTSPlayer.shared.preview(dialect)
        } catch {
            errorMessage = "Couldn't save dialect. \(error.localizedDescription)"
        }
        savingDialect = nil
    }
}

// MARK: - Previews

#Preview("Voice Dialect Picker · Dark") {
    NavigationStack {
        VoiceDialectPicker()
    }
    .preferredColorScheme(.dark)
}

#Preview("Voice Dialect Picker · Light") {
    NavigationStack {
        VoiceDialectPicker()
    }
    .preferredColorScheme(.light)
}
