//
//  ESangVoiceInput.swift
//  EusoTrip — Push-and-hold voice input for the ESANG chat composer.
//
//  Wraps `Speech.framework` + `AVAudioEngine` behind a tiny observable
//  controller and a `VoiceInputButton` the composer drops in next to its
//  send button. Tap-and-hold (or tap-to-toggle on shorter utterances) to
//  record; on release the final transcript is handed back via the
//  `onFinalTranscript` closure and the composer ships it to `send(_:)`.
//
//  Permission model:
//    • Microphone — iOS 17 prompt + AVAudioSession permission.
//    • Speech recognition — SFSpeechRecognizer authorization (shared set).
//
//  Both are requested on first tap so the driver sees a clear prompt rather
//  than a silent no-op. If either is denied we surface an inline toast and
//  the button reverts to a disabled state (still tappable; tap again to
//  retry the prompt).
//
//  This is the moniker ESANG voice feature the user called out:
//    > also add voice command to esang chat in the app. its missing
//  and it closes that gap for iOS parity with the web platform's mic mode.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import AVFoundation
import Speech

// MARK: - Controller

/// `@MainActor` observable wrapper around the Speech/AudioEngine pipeline.
/// The ESANG composer owns one instance per sheet-mount via `@StateObject`
/// so permission state + audio engine lifetime stay tied to the sheet.
@MainActor
final class ESangVoiceInputController: ObservableObject {

    enum Status: Equatable {
        /// No recording in progress.
        case idle
        /// Recording is live — partial transcripts are streaming in.
        case recording
        /// Briefly held immediately after the user released, while the
        /// engine flushes the final buffer. UI shows a subtle "sending"
        /// state during this window.
        case finalizing
        /// Permission was denied in Settings. UI can show guidance.
        case denied(reason: String)
        /// Engine error. UI can surface `message` as a toast.
        case error(message: String)
    }

    /// Live transcript — partial results overwrite this as the driver
    /// keeps talking. The composer binds its TextField to this value while
    /// `status == .recording` so the text you see IS what ESANG will
    /// receive. On stop, the value is cleared and the final transcript is
    /// handed to `onFinalTranscript`.
    @Published var transcript: String = ""
    @Published var status: Status = .idle

    // MARK: Private plumbing
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Closure invoked with the final transcript once recording stops.
    /// Called exactly once per record cycle; empty strings are not
    /// delivered (quick accidental taps become no-ops).
    var onFinalTranscript: ((String) -> Void)?

    // MARK: Public API

    var isRecording: Bool { status == .recording }

    /// Toggle — starts recording if idle, stops if already recording.
    /// Handles permission bootstrapping on the first tap.
    func toggle() {
        switch status {
        case .idle, .denied, .error:
            Task { await start() }
        case .recording:
            stop()
        case .finalizing:
            break  // let the buffer drain before responding to taps
        }
    }

    /// Explicit start — requests permission if needed, then opens the mic.
    private func start() async {
        // Short-circuit if the recognizer isn't available (simulator + non-US
        // locales can land here).
        guard let recognizer, recognizer.isAvailable else {
            status = .error(message: "Voice input isn't available on this device.")
            return
        }

        // Request Speech authorization.
        let authed: Bool = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { auth in
                cont.resume(returning: auth == .authorized)
            }
        }
        guard authed else {
            status = .denied(reason: "Speech recognition permission is required.")
            return
        }

        // Request microphone authorization (AVAudioSession — iOS 17 API).
        let micAuthed: Bool = await withCheckedContinuation { cont in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }
        guard micAuthed else {
            status = .denied(reason: "Microphone permission is required.")
            return
        }

        do {
            try openMic()
            status = .recording
        } catch {
            status = .error(message: "Couldn't open the microphone.")
            cleanup()
        }
    }

    /// Stop recording, finalize the transcript, and hand it to the caller.
    func stop() {
        guard status == .recording else { return }
        status = .finalizing
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        // Give Speech a beat to emit the final best result, then wrap up.
        Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            await MainActor.run { self.finish() }
        }
    }

    /// Tear down engine + task without delivering a transcript. Used when
    /// the sheet dismisses mid-recording.
    func cancel() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        cleanup()
        transcript = ""
        status = .idle
    }

    // MARK: Audio pipeline

    private func openMic() throws {
        // Start a fresh request each cycle — `SFSpeechAudioBufferRecognitionRequest`
        // is single-use per recognition session.
        request?.endAudio()
        task?.cancel()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement,
                                options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            req.addsPunctuation = true
        }
        self.request = req

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finish()
                    }
                } else if let error {
                    self.status = .error(message: error.localizedDescription)
                    self.cleanup()
                }
            }
        }
    }

    private func finish() {
        let final = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanup()
        transcript = ""
        status = .idle
        if !final.isEmpty { onFinalTranscript?(final) }
    }

    private func cleanup() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request = nil
        task = nil
        // Drop the audio session so the system ringer / music can resume.
        try? AVAudioSession.sharedInstance().setActive(false,
                                                      options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Button

/// Mic button sized to sit beside the send arrow. Shows a pulsing gradient
/// ring while recording so the driver can tell at a glance that the mic is
/// hot. Tap to start; tap again (or tap send) to stop.
struct ESangVoiceInputButton: View {

    @ObservedObject var controller: ESangVoiceInputController
    @Environment(\.palette) private var palette

    var body: some View {
        Button {
            controller.toggle()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(background)
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(border, lineWidth: controller.isRecording ? 1.5 : 1)
                Image(systemName: controller.isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(icon)
                    .symbolEffect(.variableColor.iterative.hideInactiveLayers,
                                  options: .repeating,
                                  isActive: controller.isRecording)
            }
            .frame(width: 40, height: 40)
            .overlay(alignment: .topTrailing) {
                // Tiny live dot while recording, matching web parity.
                if controller.isRecording {
                    Circle()
                        .fill(Brand.magenta)
                        .frame(width: 6, height: 6)
                        .offset(x: -4, y: 4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(controller.isRecording ? "Stop voice input" : "Voice input")
        .accessibilityAddTraits(controller.isRecording ? .isSelected : [])
    }

    private var background: Color {
        controller.isRecording ? palette.bgCard : palette.bgCardSoft
    }

    private var border: Color {
        controller.isRecording ? Brand.magenta.opacity(0.65) : palette.borderFaint
    }

    private var icon: Color {
        controller.isRecording ? Brand.magenta : palette.textPrimary
    }
}
