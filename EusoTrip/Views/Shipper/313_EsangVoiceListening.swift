//
//  313_eSangVoiceListening.swift
//  EusoTrip — Shipper · ESANG · Voice listening (Arc I).
//
//  Real mic capture surface. The prior version was decorative — a
//  pulsing mic icon with no AVAudioRecorder underneath, so tapping
//  "Stop & transcribe" navigated to 314 with an empty `audioBase64`
//  payload and the transcription always failed.
//
//  Now: requests mic permission on appear, starts recording into a
//  temp .m4a, pulses the mic ring during capture, and on stop reads
//  the file → base64 → calls `voiceESANG.transcribeAudio` → routes
//  the transcript through ESANG chat (311) so the copilot answers.
//  ESANG canonical voice surface per founder doctrine.
//

import SwiftUI
import AVFoundation
import UIKit

struct eSangVoiceListeningScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VoiceListeningBody() } nav: { shipperLifecycleNav() }
    }
}

@MainActor
private final class VoiceCaptureController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case permissionDenied
        case recording
        case transcribing
        case done(transcript: String)
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsedSeconds: Int = 0

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var timer: Timer?

    func startIfPermitted() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                if granted { self.beginRecording() }
                else       { self.phase = .permissionDenied }
            }
        }
    }

    private func beginRecording() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord, mode: .default,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            phase = .error("Mic session failed: \(error.localizedDescription)")
            return
        }
        let fname = "esang_\(Int(Date().timeIntervalSince1970)).m4a"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fname)
        let settings: [String: Any] = [
            AVFormatIDKey:            Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey:          16000,
            AVNumberOfChannelsKey:    1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.isMeteringEnabled = true
            rec.prepareToRecord()
            rec.record()
            recorder = rec
            fileURL = url
            phase = .recording
            elapsedSeconds = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.phase == .recording else { return }
                    self.elapsedSeconds += 1
                    if self.elapsedSeconds >= 300 { self.stopAndTranscribe() }
                }
            }
        } catch {
            phase = .error("Couldn't start recording: \(error.localizedDescription)")
        }
    }

    func stopAndTranscribe() {
        timer?.invalidate(); timer = nil
        guard let rec = recorder else {
            phase = .error("Recorder unavailable.")
            return
        }
        rec.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              !data.isEmpty else {
            phase = .error("Recorded audio file was empty.")
            return
        }
        let b64 = data.base64EncodedString()
        phase = .transcribing
        Task { await runTranscription(audioBase64: b64) }
    }

    private func runTranscription(audioBase64: String) async {
        struct In: Encodable { let audioBase64: String; let mime: String }
        struct Out: Decodable { let transcript: String? }
        do {
            let r: Out = try await EusoTripAPI.shared.mutation(
                "voiceESANG.transcribeAudio",
                input: In(audioBase64: audioBase64, mime: "audio/mp4")
            )
            let text = (r.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                if text.isEmpty {
                    self.phase = .error("Couldn't transcribe that — try again with less background noise.")
                } else {
                    self.phase = .done(transcript: text)
                }
            }
        } catch let apiErr as EusoTripAPIError {
            await MainActor.run {
                self.phase = .error(apiErr.errorDescription ?? "Transcription failed.")
            }
        } catch {
            await MainActor.run {
                self.phase = .error(error.localizedDescription)
            }
        }
    }

    func cleanup() {
        timer?.invalidate(); timer = nil
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private struct VoiceListeningBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var ctrl = VoiceCaptureController()
    @State private var pulse: Bool = false

    var body: some View {
        VStack(spacing: Space.s4) {
            Spacer()
            phaseOrb
            phaseTitle
            phaseCopy
            Spacer()
            phaseFooter
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            ctrl.startIfPermitted()
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse.toggle() }
            }
        }
        .onDisappear { ctrl.cleanup() }
    }

    private var phaseOrb: some View {
        ZStack {
            Circle().stroke(LinearGradient.diagonal, lineWidth: 2)
                .frame(width: pulse ? 220 : 160, height: pulse ? 220 : 160)
                .opacity(pulse ? 0.0 : 0.7)
            Circle().fill(LinearGradient.diagonal).frame(width: 120, height: 120)
                .shadow(color: Brand.magenta.opacity(0.5), radius: 20)
            Group {
                switch ctrl.phase {
                case .transcribing:
                    ProgressView().scaleEffect(1.6).tint(.white)
                case .done:
                    Image(systemName: "checkmark").font(.system(size: 44, weight: .heavy)).foregroundStyle(.white)
                case .error, .permissionDenied:
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 44, weight: .heavy)).foregroundStyle(.white)
                default:
                    Image(systemName: "mic.fill").font(.system(size: 44, weight: .heavy)).foregroundStyle(.white)
                }
            }
        }
    }

    private var phaseTitle: some View {
        let label: String
        switch ctrl.phase {
        case .idle:              label = "Starting…"
        case .recording:         label = "Listening · \(formattedElapsed)"
        case .transcribing:      label = "Transcribing…"
        case .done:              label = "Got it"
        case .permissionDenied:  label = "Microphone access needed"
        case .error:             label = "Voice failed"
        }
        return Text(label)
            .font(.system(size: 22, weight: .heavy))
            .foregroundStyle(palette.textPrimary)
    }

    @ViewBuilder
    private var phaseCopy: some View {
        switch ctrl.phase {
        case .idle, .recording:
            Text("Ask anything: \"Where's my UN1203 load?\", \"Take Eusotrans LLC at $2,150\", \"Post a load Houston to Dallas.\"")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
        case .transcribing:
            Text("ESANG AI is decoding what you said via Gemini.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        case .done(let transcript):
            Text("\u{201C}\(transcript)\u{201D}")
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
        case .permissionDenied:
            Text("Open Settings → EusoTrip → Microphone to enable ESANG voice commands.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        case .error(let msg):
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(Brand.danger)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var phaseFooter: some View {
        switch ctrl.phase {
        case .recording:
            Button { ctrl.stopAndTranscribe() } label: {
                pillCTA("Stop & transcribe", gradient: true)
            }
            .buttonStyle(.plain)
        case .transcribing:
            pillCTA("Transcribing…", gradient: false).opacity(0.5)
        case .done(let transcript):
            HStack(spacing: 10) {
                Button {
                    // Write the transcript into the shared bus FIRST,
                    // then navigate. 311's `.onAppear` drains the bus
                    // so the composer prefills correctly — without
                    // the bus, RoleSurfaceRouter swaps to 311 before
                    // any per-view onReceive can register and the
                    // userInfo prefill is lost.
                    EsangComposerPrefill.shared.pending = transcript
                    NotificationCenter.default.post(
                        name: .eusoShipperNavSwap,
                        object: nil,
                        userInfo: ["screenId": "311"]
                    )
                } label: {
                    pillCTA("Ask ESANG", gradient: true)
                }
                .buttonStyle(.plain)
                Button { ctrl.startIfPermitted() } label: {
                    pillCTA("Try again", gradient: false)
                }
                .buttonStyle(.plain)
            }
        case .error, .permissionDenied:
            Button {
                if ctrl.phase == .permissionDenied {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } else {
                    ctrl.startIfPermitted()
                }
            } label: {
                pillCTA(
                    ctrl.phase == .permissionDenied ? "Open Settings" : "Try again",
                    gradient: true
                )
            }
            .buttonStyle(.plain)
        case .idle:
            EmptyView()
        }
    }

    private func pillCTA(_ text: String, gradient: Bool) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .heavy))
            .tracking(0.4)
            .foregroundStyle(gradient ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textPrimary))
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(
                gradient
                    ? AnyShapeStyle(LinearGradient.diagonal)
                    : AnyShapeStyle(palette.bgCardSoft)
            )
            .overlay(
                gradient
                    ? AnyView(EmptyView())
                    : AnyView(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderSoft)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var formattedElapsed: String {
        let m = ctrl.elapsedSeconds / 60
        let s = ctrl.elapsedSeconds % 60
        return String(format: "%01d:%02d", m, s)
    }
}

#Preview("313 · Listening · Night") { eSangVoiceListeningScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("313 · Listening · Afternoon") { eSangVoiceListeningScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
