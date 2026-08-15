//
//  ESangTTSPlayer.swift
//  Dialect-aware text-to-speech player — IO 2026 P0-4.
//
//  Pipeline:
//    1. Server-side TTS (preferred) — when the ESang voice reply
//       comes back with embedded base64 audio (Kokoro voice picked
//       by the server using the user's `voiceDialect`), we just play
//       the bytes.
//    2. On-device AVSpeechSynthesizer fallback — when the server
//       didn't ship audio (no API access, region without that voice,
//       offline), we synthesize using
//       `AVSpeechSynthesisVoice(language: UserVoicePreference.shared.effectiveLocaleIdentifier)`.
//
//  Either way the dialect the user picked in Settings is honored —
//  the server picks the matching cloud voice when it can, and the
//  on-device synth picks the same BCP-47 language locale when it can't.
//
//  Drop into: EusoTrip/Services/ESangTTSPlayer.swift
//

import Foundation
import AVFoundation

/// Single playback surface used by every ESang voice reply on iOS.
/// Owns one AVAudioPlayer (for server-shipped audio) AND one
/// AVSpeechSynthesizer (for on-device fallback) so consecutive
/// replies can't overlap — the player cancels the previous reply
/// before starting the next.
public final class ESangTTSPlayer: NSObject, @unchecked Sendable {
    public static let shared = ESangTTSPlayer()

    private var audioPlayer: AVAudioPlayer?
    private let synthesizer = AVSpeechSynthesizer()

    /// Are we currently speaking? Bound by view-models so the ESang
    /// orb can pulse during playback.
    public private(set) var isSpeaking: Bool = false

    private override init() { super.init() }

    /// Speak a reply. Priority:
    ///   1. If `serverAudioBase64` is non-nil → decode + play the
    ///      server-shipped audio (dialect already baked in by the
    ///      cloud TTS).
    ///   2. Else → fall back to AVSpeechSynthesizer with the user's
    ///      effective locale identifier (`UserVoicePreference.shared.effectiveLocaleIdentifier`).
    ///
    /// Cancels any currently-playing audio first so consecutive
    /// turns don't overlap.
    @MainActor
    public func speak(_ text: String, serverAudioBase64: String? = nil) async {
        stop()
        guard !text.isEmpty else { return }
        guard UserVoicePreference.shared.isVoiceEnabled else { return }

        // ─── Path A: server-shipped audio ──────────────────────────
        if let b64 = serverAudioBase64, playAudio(base64: b64) {
            return
        }

        // The shared server profile is authoritative for the selected Kokoro
        // voice. A network or TTS outage falls through to the device voice.
        if serverAudioBase64 == nil {
            struct Input: Encodable {
                let text: String
                let voiceId: String?
            }
            struct Output: Decodable {
                let audio: String?
                let voiceName: String
                let voiceId: String
                let error: String?
            }
            do {
                let reply: Output = try await EusoTripAPI.shared.mutation(
                    "esangVoice.speak",
                    input: Input(
                        text: String(text.prefix(2_000)),
                        voiceId: UserVoicePreference.shared.selectedVoiceProfile
                    )
                )
                if let audio = reply.audio, playAudio(base64: audio) {
                    return
                }
            } catch {
                // Device speech below is the explicit degraded provider state.
            }
        }

        // ─── Path B: on-device AVSpeechSynthesizer fallback ────────
        let utterance = AVSpeechUtterance(string: text)
        let preferredLocale = UserVoicePreference.shared.effectiveLocaleIdentifier
        // AVSpeechSynthesisVoice(language:) returns nil for unsupported
        // tags — fall back to the closest root (drop region refinement)
        // when that happens.
        let voice = AVSpeechSynthesisVoice(language: preferredLocale)
                 ?? AVSpeechSynthesisVoice(language: String(preferredLocale.prefix(2)))
                 ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        do {
            try Self.activateAudioSession()
        } catch { /* speak anyway */ }
        synthesizer.delegate = self
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    @MainActor
    private func playAudio(base64: String) -> Bool {
        guard !base64.isEmpty,
              let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
            return false
        }
        do {
            try Self.activateAudioSession()
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.prepareToPlay()
            guard player.play() else { return false }
            audioPlayer = player
            isSpeaking = true
            return true
        } catch {
            return false
        }
    }

    /// Stop both pipelines immediately. Idempotent.
    public func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        audioPlayer?.stop()
        audioPlayer = nil
        isSpeaking = false
    }

    /// Convenience for the Settings dialect picker — speak the
    /// dialect's canonical preview phrase.
    @MainActor
    public func preview(_ dialect: VoiceDialect) async {
        await speak(dialect.previewPhrase, serverAudioBase64: nil)
    }

    // MARK: - Audio session

    private static func activateAudioSession() throws {
        #if canImport(AVFoundation) && !targetEnvironment(macCatalyst)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true, options: [])
        #endif
    }
}

extension ESangTTSPlayer: AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isSpeaking = false
        audioPlayer = nil
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
}
