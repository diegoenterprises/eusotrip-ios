//
//  WatchAudioRecorder.swift
//  EusoTrip Pulse Watch App
//
//  Walkie-talkie hold-to-talk for the orb. AVAudioRecorder records
//  speech-quality AAC into a temp .m4a, then uploads the file as
//  base64 to `transcription.transcribeAudio` on the backend, which
//  runs it through Gemini and returns the verbatim text. The text
//  is then fed into the existing `EsangSession.submitTranscribedText`
//  pipeline so action dispatch + phone mirror + voice reply all
//  run unchanged.
//
//  Why not SFSpeechRecognizer: not shipped on watchOS.
//  Why not WKAudioRecorderController: it presents a modal mic UI
//  with a manual stop button — fights the press-and-hold gesture
//  drivers expect. Direct AVAudioRecorder gives us programmatic
//  start/stop tied to the long-press lifecycle.
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class WatchAudioRecorder: NSObject, ObservableObject {

    static let shared = WatchAudioRecorder()

    /// Live recording state — bound by HomeView so the orb can show a
    /// pulsing "RECORDING" indicator while the user holds.
    @Published private(set) var isRecording: Bool = false

    /// True while the captured audio is round-tripping through the
    /// Gemini transcription endpoint. Drives the orb's "transcribing…"
    /// hint between release and the chat response landing.
    @Published private(set) var isTranscribing: Bool = false

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var session: AVAudioSession {
        AVAudioSession.sharedInstance()
    }

    private override init() { super.init() }

    /// Begin recording. Configures `playAndRecord` so the system
    /// duckers the existing audio (e.g. car play, navigation prompts)
    /// without tearing the route. Caller (HomeView's long-press)
    /// invokes this on press start.
    func start() async throws {
        if isRecording { return }
        // .defaultToSpeaker is iOS-only — watchOS routes audio to
        // the wrist speaker / paired Bluetooth automatically. Mode
        // .voiceChat already biases for handsfree speech capture.
        // .allowBluetooth was deprecated in watchOS 11.0 — replaced
        // with .allowBluetoothHFP (Hands-Free Profile, the route a
        // mic-bearing headset uses). A2DP is play-only so it doesn't
        // help recording sessions.
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.duckOthers, .allowBluetoothHFP]
        )
        try session.setActive(true, options: [])

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("esang-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            // 16kHz mono is the speech-recognition standard. Keeps
            // the file small (~16 KB/sec) so a 6-second tap-and-hold
            // round-trips through Gemini in well under 2s on cellular.
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            AVEncoderBitRateKey: 32_000,
        ]
        let r = try AVAudioRecorder(url: url, settings: settings)
        r.delegate = self
        r.isMeteringEnabled = false
        guard r.record() else {
            throw NSError(domain: "WatchAudioRecorder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "failed_to_start_recording"])
        }
        recorder = r
        fileURL = url
        isRecording = true
    }

    /// Stop recording and return the .m4a temp URL ready to upload.
    /// Returns nil when there's no active recording. Safe to call
    /// from the long-press release handler.
    func stop() -> URL? {
        guard let r = recorder, isRecording else { return nil }
        r.stop()
        let captured = fileURL
        recorder = nil
        fileURL = nil
        isRecording = false
        // Release the audio session so other apps (Maps, Music, the
        // dispatcher's call) can resume their normal routing.
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        return captured
    }

    /// Cancel an in-flight recording without uploading. Used when the
    /// user releases too quickly (< 250ms) so we don't spam Gemini
    /// with empty buffers, and when the gesture is invalidated.
    func cancel() {
        guard let r = recorder else { return }
        r.stop()
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        recorder = nil
        fileURL = nil
        isRecording = false
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// Read the recorded file, base64-encode the bytes, and post to
    /// `transcription.transcribeAudio`. Returns the verbatim
    /// transcript, or empty string when Gemini heard no speech.
    /// Caller cleans up the temp file after upload regardless.
    func transcribe(fileURL: URL, auth: AuthStore) async throws -> String {
        guard let token = auth.token else {
            throw NSError(domain: "WatchAudioRecorder", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "not_signed_in"])
        }
        isTranscribing = true
        defer { isTranscribing = false }

        let data = try Data(contentsOf: fileURL)
        let base64 = data.base64EncodedString()

        // Cleanup as soon as we have the bytes in memory — the temp
        // file's only purpose was the AVAudioRecorder write target.
        try? FileManager.default.removeItem(at: fileURL)

        struct Input: Encodable {
            let audioBase64: String
            let mimeType: String
        }
        struct Envelope: Decodable {
            struct Result: Decodable {
                struct DataContainer: Decodable {
                    struct Body: Decodable { let transcript: String }
                    let json: Body
                }
                let data: DataContainer
            }
            let result: Result
        }

        var url = URL(string: EusoTripConfig.apiBaseURL)!
        url.appendPathComponent("/api/trpc/transcription.transcribeAudio")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 25

        let payload: [String: Any] = [
            "json": [
                "audioBase64": base64,
                "mimeType": "audio/mp4",
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (respData, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "WatchAudioRecorder", code: (resp as? HTTPURLResponse)?.statusCode ?? 0,
                          userInfo: [NSLocalizedDescriptionKey: "transcription_http_error"])
        }
        let env = try JSONDecoder().decode(Envelope.self, from: respData)
        return env.result.data.json.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - AVAudioRecorderDelegate

extension WatchAudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // Nothing to do here — `stop()` is the canonical exit path.
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in self.cancel() }
    }
}
