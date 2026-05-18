//
//  314_eSangTranscribing.swift
//  EusoTrip — Shipper · eSang · Transcribing (Arc I).
//

import SwiftUI

struct eSangTranscribingScreen: View {
    let theme: Theme.Palette
    /// base64 audio data the prior screen captured. iOS-side recorder
    /// is the producer (313). Empty string surfaces an honest error.
    var audioBase64: String = ""
    var body: some View {
        Shell(theme: theme) { TranscribingBody(audioBase64: audioBase64) } nav: { shipperLifecycleNav() }
    }
}

private struct TranscribingBody: View {
    @Environment(\.palette) private var palette
    let audioBase64: String
    @State private var transcript: String = ""
    @State private var processing: Bool = true
    @State private var actionError: String? = nil

    var body: some View {
        VStack(spacing: Space.s4) {
            Spacer()
            Image(systemName: "waveform").font(.system(size: 36, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text(processing ? "Transcribing…" : "Transcribed").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            if !transcript.isEmpty {
                LifecycleCard {
                    Text(transcript).font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                }
            } else if let err = actionError {
                LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
            }
            Spacer()
            HStack(spacing: 10) {
                Button {
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "313"])
                } label: {
                    Text("Re-record").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(palette.tintNeutral).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }.buttonStyle(.plain)
                Button {
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "311", "draft": transcript])
                } label: {
                    Text("Send").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }.buttonStyle(.plain).disabled(transcript.isEmpty)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await transcribe() }
    }

    private func transcribe() async {
        processing = true; actionError = nil
        if audioBase64.isEmpty {
            actionError = "No audio captured. Tap Re-record."
            processing = false; return
        }
        struct In: Encodable { let audioBase64: String; let mime: String }
        struct Out: Decodable { let text: String? }
        do {
            let r: Out = try await EusoTripAPI.shared.mutation("transcription.transcribeAudio", input: In(audioBase64: audioBase64, mime: "audio/mp4"))
            transcript = r.text ?? ""
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        processing = false
    }
}

#Preview("314 · Transcribing · Night") { eSangTranscribingScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("314 · Transcribing · Afternoon") { eSangTranscribingScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
