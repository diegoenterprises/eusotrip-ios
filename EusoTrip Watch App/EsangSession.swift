//
//  EsangSession.swift
//  EusoTrip Watch App
//
//  Owns the user-facing state machine for a single interaction cycle:
//    idle → listening → thinking → done (speaks reply) → idle
//
//  Pipeline:
//    1. SFSpeechRecognizer captures audio via AVAudioEngine
//    2. Final transcript is POSTed to voiceESANG.processVoiceCommand
//       (or esang.chat as a fallback)
//    3. Returned `spokenText` is spoken via AVSpeechSynthesizer
//    4. If online:   forwarded to the iPhone via WatchConnectivity
//       If offline:  queued to OfflineQueue for retry when reachable
//    5. Any returned `actions[]` are dispatched to VoiceActionDispatcher
//
//  Emits cumulative transcript rows into `history` so the wrist shows the
//  last few exchanges without having to re-scroll.
//

import Foundation
import SwiftUI
import Speech
import AVFoundation
import WatchKit

enum EsangState: Equatable {
    case idle
    case listening
    case thinking
    case done
    case error(String)

    var iconName: String {
        switch self {
        case .idle:      return "waveform.circle.fill"
        case .listening: return "mic.fill"
        case .thinking:  return "ellipsis"
        case .done:      return "checkmark"
        case .error:     return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle:      return Color.esangBlue
        case .listening: return Color.esangListening
        case .thinking:  return Color.esangAmber
        case .done:      return Color.esangGreen
        case .error:     return Color.esangDanger
        }
    }
}

struct EsangTurn: Identifiable, Equatable {
    let id = UUID()
    let transcript: String
    let reply: String
    let intent: String
    let timestamp: Date
}

@MainActor
final class EsangSession: ObservableObject {
    @Published var state: EsangState = .idle
    @Published var transcript: String = ""
    @Published var replyText: String = ""
    @Published var syncToPhone: Bool = true
    @Published var history: [EsangTurn] = []
    @Published var lastActions: [VoiceAction] = []
    @Published var suggestions: [String] = []

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let synth = AVSpeechSynthesizer()
    private let maxHistory = 8

    var displayText: String {
        switch state {
        case .idle:           return "Tap to ask Esang"
        case .listening:      return transcript.isEmpty ? "Listening…" : transcript
        case .thinking:       return "Thinking…"
        case .done:           return replyText.isEmpty ? "Done" : replyText
        case .error(let msg): return msg
        }
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let speechOK = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        let micOK = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        return speechOK && micOK
    }

    // MARK: - Listening

    func startListening() async {
        guard await requestPermissions() else {
            state = .error("Mic or Speech permission denied")
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            state = .error("Speech recognizer unavailable")
            return
        }

        transcript = ""
        replyText = ""
        lastActions = []
        suggestions = []
        state = .listening
        WKInterfaceDevice.current().play(.start)

        do {
            try configureAudioSession()
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            request = req

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buffer, _ in
                req?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    Task { @MainActor in
                        self.transcript = result.bestTranscription.formattedString
                    }
                }
                if error != nil {
                    Task { @MainActor in self.teardownAudio() }
                }
            }
        } catch {
            state = .error("Couldn't start mic: \(error.localizedDescription)")
            teardownAudio()
        }
    }

    func stopAndSubmit(auth: AuthStore, connectivity: WatchConnectivityManager) async {
        teardownAudio()
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            state = .idle
            return
        }
        await submitTranscribedText(text, auth: auth, connectivity: connectivity)
    }

    // MARK: - Direct text submission (also used by App Intent / complication tap)

    func submitTranscribedText(_ text: String, auth: AuthStore, connectivity: WatchConnectivityManager) async {
        transcript = text
        state = .thinking
        WKInterfaceDevice.current().play(.click)

        do {
            let client = EsangClient(auth: auth)
            let response = try await client.processVoiceCommand(
                text: text,
                currentPage: "watch",
                loadId: LoadStore.shared.active?.id
            )
            replyText = response.spokenText.isEmpty ? response.text : response.spokenText
            lastActions = response.actions
            suggestions = response.suggestions
            appendHistory(transcript: text, reply: replyText, intent: response.intent)

            // Dispatch any structured actions (accept load, navigate, etc.)
            await VoiceActionDispatcher.shared.dispatch(
                response.actions,
                auth: auth,
                connectivity: connectivity
            )

            if syncToPhone {
                connectivity.forwardToPhone(
                    transcript: text,
                    reply: replyText,
                    intent: response.intent,
                    actions: response.actions
                )
            }

            state = .done
            WKInterfaceDevice.current().play(.success)
            speak(replyText)
        } catch EsangError.unauthorized {
            state = .error("Sign in on your iPhone to use Esang.")
            WKInterfaceDevice.current().play(.failure)
        } catch {
            // Offline / network — queue for retry
            OfflineQueue.shared.enqueueVoice(text: text, loadId: LoadStore.shared.active?.id)
            state = .error("No connection — queued.")
            WKInterfaceDevice.current().play(.retry)
        }
    }

    // MARK: - History

    private func appendHistory(transcript: String, reply: String, intent: String) {
        history.insert(
            EsangTurn(transcript: transcript, reply: reply, intent: intent, timestamp: Date()),
            at: 0
        )
        if history.count > maxHistory { history.removeLast(history.count - maxHistory) }
    }

    // MARK: - Audio helpers

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func teardownAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    private func speak(_ text: String) {
        guard !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(utterance)
    }
}
