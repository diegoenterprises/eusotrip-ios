//
//  EsangSession.swift
//  EusoTrip Watch App
//
//  Owns the user-facing state machine for a single interaction cycle:
//    idle → listening → thinking → done (speaks reply) → idle
//
//  Pipeline:
//    1. SFSpeechRecognizer captures audio via AVAudioEngine
//    2. Final transcript is POSTed to esang.chat (Gemini-backed brain;
//       the same endpoint iOS + web call). Falls back to the legacy
//       voiceESANG.processVoiceCommand router on a 404.
//    3. Returned `spokenText` is spoken via AVSpeechSynthesizer
//    4. If online:   forwarded to the iPhone via WatchConnectivity
//       If offline:  queued to OfflineQueue for retry when reachable
//    5. Any returned `actions[]` are dispatched to VoiceActionDispatcher
//
//  Emits cumulative transcript rows into `history` so the wrist shows the
//  last few exchanges without having to re-scroll.
//

import Foundation
import Combine
import SwiftUI
#if canImport(Speech)
import Speech
#endif
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

/// Typed classification of whatever caused the last `.error` transition.
/// The human-readable message that sits inside `EsangState.error(String)`
/// is still authoritative for the hint line, but the UI uses this kind
/// to (a) pick the right error icon + action hint ("SETTINGS →
/// PRIVACY…", "TAP ORB TO RETRY"), and (b) let `handleOrbTap` route the
/// recovery — an unauthorized error should kick `requestAuthMirror` and
/// replay the last transcript, a network timeout should just replay,
/// and a permission error should NOT auto-retry (the driver has to
/// toggle Settings first; another tap would just re-prompt for the
/// same denied permission).
enum EsangErrorKind: Equatable {
    case permissionMic
    case permissionSpeech
    case permissionBoth
    case speechUnavailable
    case micHardware
    case unauthorized
    case phonePairing
    case offline
    case networkTimeout
    case unknown

    /// Permission problems require the driver to flip a Settings toggle
    /// — we should never auto-retry past one of these because the
    /// retry will hit the exact same denial and burn another haptic.
    var blocksAutoRetry: Bool {
        switch self {
        case .permissionMic, .permissionSpeech, .permissionBoth, .speechUnavailable, .micHardware:
            return true
        default:
            return false
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
    /// The orb's visible intent. Transient terminal states (`.done` /
    /// `.error`) auto-return to `.idle` on a timer so the watch face
    /// always settles back into the EusoTrip brand gradient + glow.
    /// This is the user-visible contract: after any voice turn the
    /// orb shows its success / failure tint briefly, then breathes.
    @Published var state: EsangState = .idle {
        didSet {
            if state != oldValue { scheduleAutoIdleReset(for: state) }
        }
    }
    /// Cancellable task that flips `.done` / `.error` back to `.idle`
    /// after the configured dwell. Cancelled whenever `state` changes
    /// so a new transition supersedes a pending reset.
    private var autoIdleResetTask: Task<Void, Never>?

    /// Dwell for `.done` before returning to `.idle`. Short enough
    /// that the driver's eyes catch the green "success" ring, long
    /// enough that it registers on a quick glance.
    private let doneDwellSeconds: Double = 2.2

    /// Dwell for `.error` — slightly longer because the driver may
    /// want to read the hint card under the orb before it settles.
    /// Permission errors (`blocksAutoRetry = true`) NEVER auto-reset
    /// — the driver must open Settings first; we don't want the
    /// error hint disappearing from under them.
    private let errorDwellSeconds: Double = 4.5

    private func scheduleAutoIdleReset(for newState: EsangState) {
        autoIdleResetTask?.cancel()
        autoIdleResetTask = nil

        let dwellSeconds: Double
        let guardAgainstPermission: Bool
        switch newState {
        case .done:
            dwellSeconds = doneDwellSeconds
            guardAgainstPermission = false
        case .error:
            // Suppress auto-reset for permission errors so the driver
            // sees a stable hint card explaining what to toggle.
            if let k = lastErrorKind, k.blocksAutoRetry { return }
            dwellSeconds = errorDwellSeconds
            guardAgainstPermission = true
        default:
            return
        }

        autoIdleResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(dwellSeconds * 1_000_000_000))
            guard let self else { return }
            // Only flip if we're still sitting in the same terminal
            // state. If the driver tapped to start another turn mid-
            // dwell, `state` is already `.listening` and we shouldn't
            // clobber it.
            switch (self.state, newState) {
            case (.done, .done):
                self.state = .idle
                self.transcript = ""
                self.replyText = ""
            case (.error, .error):
                // Double-check the permission guard in case the kind
                // was set after the initial check.
                if guardAgainstPermission, let k = self.lastErrorKind, k.blocksAutoRetry {
                    return
                }
                self.state = .idle
                self.transcript = ""
                self.replyText = ""
                self.lastErrorKind = nil
            default:
                return
            }
        }
    }
    @Published var transcript: String = ""
    @Published var replyText: String = ""
    @Published var syncToPhone: Bool = true
    @Published var history: [EsangTurn] = []
    @Published var lastActions: [VoiceAction] = []
    @Published var suggestions: [String] = []
    /// Typed twin of `state.error(String)`. The UI reads this alongside
    /// the `.error` case to render a specific icon + actionable hint
    /// ("SETTINGS → PRIVACY", "TAP ORB TO RETRY") instead of a single
    /// 10pt line the driver can't parse at a glance. Cleared back to
    /// nil any time the session settles into a non-error state.
    @Published private(set) var lastErrorKind: EsangErrorKind? = nil
    /// Last transcript submitted to the backend — retained so
    /// `retryLast` can replay it without re-capturing audio. Cleared
    /// at the start of every new listening cycle.
    private(set) var lastTranscript: String = ""

    #if canImport(Speech)
    // Lazy — SFSpeechRecognizer + AVAudioEngine creation can trigger
    // audio-session wiring that isn't safe before the workout session is
    // active. Never instantiate these at @StateObject creation time or
    // the app can hard-crash to the watch home screen on cold launch.
    private lazy var recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private lazy var audioEngine: AVAudioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    #endif
    // Watchdog — if the engine enters .listening but never transitions
    // out (rare: simulator audio-route glitch, or a recognitionTask that
    // silently stalls without emitting error), drop back to .idle after
    // 30s so the orb is never permanently "hot."
    private var listeningWatchdog: Task<Void, Never>?
    // Lazy — AVSpeechSynthesizer init also tries to bind the audio stack;
    // we only need it when a reply is ready to speak.
    private lazy var synth: AVSpeechSynthesizer = AVSpeechSynthesizer()
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

    #if DEBUG
    // MARK: - Debug state cycler
    //
    // Drives the orb through every visual state without a real mic or
    // tRPC round-trip. Bound to long-press-on-the-orb in DEBUG builds so
    // QA (and the product owner) can actually see Listening / Thinking
    // / Done / Error halo colors, gradients, and copy variants on the
    // simulator. No side effects beyond the published state/text;
    // nothing gets sent to the phone or the backend.
    func debugCycleState() {
        switch state {
        case .idle:
            state = .listening
            transcript = "Show me my next load"
        case .listening:
            state = .thinking
            transcript = "Show me my next load"
        case .thinking:
            state = .done
            replyText = "Navigation started on iPhone."
        case .done:
            state = .error("Couldn't reach the network. Try again.")
        case .error:
            state = .idle
            transcript = ""
            replyText = ""
        }
    }
    #endif

    // MARK: - Permissions

    /// Granular permission check so `startListening` can surface a
    /// Settings-actionable error ("Microphone access required — enable
    /// in Settings.") instead of a generic "permission denied" that
    /// leaves the driver with no idea which permission to toggle.
    enum PermissionResult {
        case granted
        case speechDenied
        case micDenied
        case bothDenied
    }

    func requestPermissions() async -> PermissionResult {
        #if canImport(Speech)
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
        switch (speechOK, micOK) {
        case (true,  true):  return .granted
        case (false, true):  return .speechDenied
        case (true,  false): return .micDenied
        case (false, false): return .bothDenied
        }
        #else
        return .bothDenied
        #endif
    }

    // MARK: - External error surface
    //
    // Lets callers (e.g. HomeView.handleOrbTap auth-mirror timeout)
    // force the orb into a visible `.error` state with an explicit
    // message instead of it sitting silently in `.idle` forever. All
    // mutations happen on the main actor since the class is
    // @MainActor-annotated.
    func setError(_ message: String, kind: EsangErrorKind = .unknown) {
        fail(message, kind: kind)
    }

    /// Internal error setter. Sets state, stamps the typed kind so the
    /// UI can render the right icon + action hint, and fires a haptic
    /// (overridable — the offline-queued path wants `.retry` not
    /// `.failure` so the driver feels "we'll try again later" instead
    /// of a hard fail).
    private func fail(_ message: String, kind: EsangErrorKind, haptic: WKHapticType = .failure) {
        state = .error(message)
        lastErrorKind = kind
        WKInterfaceDevice.current().play(haptic)
    }

    /// Reset back to idle — useful from the watchdog + the tap handler
    /// to unwind an error state without having to force another tap.
    func resetToIdle() {
        teardownAudio()
        listeningWatchdog?.cancel()
        listeningWatchdog = nil
        transcript = ""
        replyText = ""
        state = .idle
        lastErrorKind = nil
    }

    // MARK: - Preflight permission status
    //
    // Non-prompting check. Reads the current authorization status for
    // Speech + Microphone and flips the orb into a visible `.error`
    // state IF either is already denied — so the driver sees the
    // Settings-actionable hint card the moment the watch app opens,
    // instead of tapping the orb, hearing a single failure haptic,
    // and puzzling at a 10pt line underneath. Does NOT call
    // `requestAuthorization` — that would spawn an iPhone-side
    // permission modal unrelated to the tap. The first real tap still
    // owns the permission PROMPT; this just surfaces a prior denial.
    func checkPermissionsOnLaunch() {
        #if canImport(Speech)
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let micStatus = AVAudioApplication.shared.recordPermission
        let speechDenied = (speechStatus == .denied || speechStatus == .restricted)
        let micDenied = (micStatus == .denied)
        switch (speechDenied, micDenied) {
        case (true, true):
            fail("Mic + Speech blocked — enable in Settings.", kind: .permissionBoth)
        case (true, false):
            fail("Speech Recognition blocked — enable in Settings.", kind: .permissionSpeech)
        case (false, true):
            fail("Microphone blocked — enable in Settings.", kind: .permissionMic)
        case (false, false):
            // Nothing actionable — stay idle. If we're already sitting
            // in a permission error from a previous check, clear it
            // since whatever was wrong is no longer wrong.
            if case .error = state,
               let k = lastErrorKind, k.blocksAutoRetry {
                resetToIdle()
            }
        }
        #endif
    }

    // MARK: - Listening

    /// Convenience overload that accepts auth / connectivity so the
    /// OrbStateMachine can drive listening from a single call point.
    ///
    /// On platforms where the Speech framework is shipped (iOS + sim),
    /// this forwards to the parameterless form which uses
    /// `SFSpeechRecognizer` + `AVAudioEngine`.
    ///
    /// On watchOS the Speech framework is NOT available (Apple does
    /// not ship `SFSpeechRecognizer` to the wrist), so the
    /// parameterless form would fall through to the error branch.
    /// Instead we route through `WatchDictation.present()` which
    /// wraps `WKInterfaceController.presentTextInputController` with
    /// `.plain` input mode — that's the canonical one-tap dictation
    /// flow on watchOS. The returned transcript is piped straight
    /// into `submitTranscribedText` so the existing `esang.chat`
    /// pipeline, action dispatch, and phone mirror all run
    /// unchanged.
    func startListening(auth: AuthStore, connectivity: WatchConnectivityManager) async {
        OrbLog.info("startListening auth=\(auth.isSignedIn) wc=\(connectivity.isReachable)")
        #if canImport(Speech)
        await startListening()
        #else
        // watchOS path — the Speech framework is not shipped on the
        // wrist, so SFSpeechRecognizer is unavailable. Route through
        // `DictationBroker`, which asks `HomeView` to present
        // `WatchDictationSheet`; its TextFieldLink pipes the driver
        // into Apple's native dictation UI (watchOS 10+) and hands
        // back a transcript. The rest of the pipeline
        // (submitTranscribedText → performBackendCall → speak) is
        // unchanged.
        transcript = ""
        replyText = ""
        lastActions = []
        suggestions = []
        lastErrorKind = nil
        state = .listening
        WKInterfaceDevice.current().play(.start)
        let dictated = await DictationBroker.shared.requestText()
        guard let text = dictated else {
            state = .idle
            return
        }
        await submitTranscribedText(text, auth: auth, connectivity: connectivity)
        #endif
    }

    func startListening() async {
        OrbLog.info("startListening entry state=\(String(describing: state))")
        #if canImport(Speech)
        // EXPLICIT permission prompt. Previously a single boolean bubble
        // that dead-ended at "Mic or Speech permission denied" — the
        // driver had no idea which switch to flip. Now we map the
        // specific denial to a Settings-actionable message so support
        // can say "open Settings → Privacy → Microphone" instead of
        // guessing.
        switch await requestPermissions() {
        case .granted:
            break
        case .micDenied:
            fail("Microphone access required — enable in Settings.", kind: .permissionMic)
            return
        case .speechDenied:
            fail("Speech Recognition required — enable in Settings.", kind: .permissionSpeech)
            return
        case .bothDenied:
            fail("Mic + Speech required — enable in Settings.", kind: .permissionBoth)
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            fail("Speech recognizer unavailable.", kind: .speechUnavailable)
            return
        }

        transcript = ""
        replyText = ""
        lastActions = []
        suggestions = []
        lastErrorKind = nil
        state = .listening
        WKInterfaceDevice.current().play(.start)

        do {
            // L4a — preflight + workout yield. The HKWorkoutSession
            // owned by DrivingSessionManager can hold the audio route;
            // pauseForVoice() yields it for the duration of capture.
            // AudioSessionPreflight.check() does the .playAndRecord /
            // .spokenAudio / HFP activation in one place so we don't
            // install a tap onto a 0-channel format (ObjC exception,
            // not a Swift throw).
            DrivingSessionManager.shared.yieldAudioRoute()
            try AudioSessionPreflight.check()
            try configureAudioSession()
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            request = req

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            // L4b — guard against a 0-channel input format. watchOS
            // 26.4 can hand us a format with channelCount == 0 when
            // the HKWorkoutSession is still contending for the route;
            // installTap on that is an ObjC exception that crashes
            // the app. Surface a typed error instead.
            guard format.channelCount > 0 else {
                OrbLog.audio("installTap: 0-ch format — aborting")
                throw EsangError.audioRouteUnavailable
            }
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

            // Fix C — watchdog. If for any reason we're still in
            // .listening 30s from now (simulator audio-route fluke,
            // task silently stalled, tap never came), force back to
            // .idle so the orb isn't permanently hot.
            listeningWatchdog?.cancel()
            listeningWatchdog = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30 * NSEC_PER_SEC)
                guard let self else { return }
                await MainActor.run {
                    if case .listening = self.state {
                        self.teardownAudio()
                        self.state = .idle
                    }
                }
            }
        } catch EsangError.audioRouteUnavailable {
            fail("Microphone busy — try again in a moment.", kind: .micHardware)
            teardownAudio()
            DrivingSessionManager.shared.resumeAfterVoice()
        } catch {
            fail("Couldn't start mic: \(error.localizedDescription)", kind: .micHardware)
            teardownAudio()
            DrivingSessionManager.shared.resumeAfterVoice()
        }
        #else
        fail("Voice input unavailable on this device.", kind: .speechUnavailable)
        #endif
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
        lastTranscript = text
        lastErrorKind = nil
        state = .thinking
        WKInterfaceDevice.current().play(.click)
        await performBackendCall(text: text, auth: auth, connectivity: connectivity, attempt: 1)
    }

    /// Retry the last transcript without re-capturing audio. Used by
    /// the orb tap handler when the driver taps an `.error` state
    /// whose kind is recoverable (unauthorized → auth refresh + retry,
    /// offline / networkTimeout → straight retry). Does nothing if
    /// there is no prior transcript — the tap handler falls back to
    /// `startListening` in that case.
    func retryLast(auth: AuthStore, connectivity: WatchConnectivityManager) async {
        guard !lastTranscript.isEmpty else { return }
        lastErrorKind = nil
        state = .thinking
        WKInterfaceDevice.current().play(.click)
        await performBackendCall(text: lastTranscript, auth: auth, connectivity: connectivity, attempt: 1)
    }

    /// Core backend-call routine.
    ///
    /// Retry logic:
    /// • attempt 1 + 401 → silent `requestAuthMirror`, wait ~1.5s for
    ///   the phone to mirror a fresher token, retry once (attempt 2).
    /// • attempt 1 + generic network/timeout → 600ms backoff, retry
    ///   once (attempt 2). Most watch-radio dropouts self-heal in
    ///   under a second; this rescues the wrist without bouncing
    ///   through "queued" UX.
    /// • attempt 2 failures drop to the existing offline dispatch /
    ///   queue fallback and surface a Settings-actionable error card.
    private func performBackendCall(
        text: String,
        auth: AuthStore,
        connectivity: WatchConnectivityManager,
        attempt: Int
    ) async {
        // B2 fast-path: empty token → skip HTTP, route through the
        // on-device VoiceDispatch grammar + OfflineQueue. Keeps the
        // orb working on a never-paired / expired-token watch and
        // prevents the 401 → .unauthorized error card. This is the
        // offline-first contract from EusoTrip_Offline_Mode_Encyclopedia
        // Chapter 06 F04 — voice ALWAYS resolves locally when unpaired.
        if (auth.token ?? "").isEmpty {
            OrbLog.info("perform.emptyToken fastpath text=\(text.prefix(40))")
            if EusoTripConfig.voiceDispatchOfflineEnabled,
               let intent = VoiceDispatch.resolve(text, loadId: LoadStore.shared.active?.id) {
                replyText = intent.reply.isEmpty ? "Logged offline." : intent.reply
                lastActions = intent.actions
                appendHistory(transcript: text, reply: replyText, intent: intent.label)
                await VoiceActionDispatcher.shared.dispatchOffline(
                    intent.actions,
                    prompt: intent.reply.isEmpty ? intent.label : intent.reply,
                    auth: auth, connectivity: connectivity
                )
                if intent.enqueueOnline {
                    OfflineQueue.shared.enqueueVoice(
                        text: text, loadId: LoadStore.shared.active?.id
                    )
                }
            } else {
                OfflineQueue.shared.enqueueVoice(
                    text: text, loadId: LoadStore.shared.active?.id
                )
                replyText = "Queued — will send when signed in."
                appendHistory(transcript: text, reply: replyText, intent: "queued_offline")
            }
            state = .done
            lastErrorKind = nil
            WKInterfaceDevice.current().play(.success)
            if !replyText.isEmpty { speak(replyText) }
            return
        }

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
            lastErrorKind = nil
            WKInterfaceDevice.current().play(.success)
            speak(replyText)
        } catch EsangError.unauthorized {
            // Silent auth refresh before giving up. Watch token
            // expiry mid-trip is common (phone rotates, watch
            // lags) — ask the phone to re-mirror and retry once
            // with whatever lands in the ~1.5s window. If no
            // fresher token arrives, surface a Settings-actionable
            // error so the driver knows to open the phone.
            if attempt == 1 {
                let oldToken = auth.token
                connectivity.requestAuthMirror()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if let newToken = auth.token, !newToken.isEmpty, newToken != oldToken {
                    await performBackendCall(
                        text: text, auth: auth,
                        connectivity: connectivity, attempt: attempt + 1
                    )
                    return
                }
            }
            fail("Sign in on your iPhone to use Esang.", kind: .unauthorized)
        } catch {
            // One silent retry on network/timeout before declaring
            // defeat. Watch radio dropouts typically clear in under
            // a second; replaying once in-band avoids bouncing the
            // wrist into "queued" when we would have succeeded.
            if attempt == 1 {
                try? await Task.sleep(nanoseconds: 600_000_000)
                await performBackendCall(
                    text: text, auth: auth,
                    connectivity: connectivity, attempt: attempt + 1
                )
                return
            }

            // Offline / network — try the local voice-dispatch grammar
            // (F04) for a low-latency confirmation. The dispatch step
            // below runs every emitted action through
            // VoiceActionDispatcher, whose downstream handlers
            // (HOSStore.changeStatus, EmergencyController.activate,
            // loadBidding.accept, log_arrival, message_reply) each
            // enqueue into the right *typed* outbox lane on network
            // failure — so SOS / HOS / Load events land in priority
            // lanes (SOS > HOS > Load > Voice > Message) and a
            // life-safety "mayday" drains ahead of a five-minute-old
            // "what's my battery?" transcript.
            if EusoTripConfig.voiceDispatchOfflineEnabled,
               let intent = VoiceDispatch.resolve(text, loadId: LoadStore.shared.active?.id) {
                replyText = intent.reply.isEmpty ? "Logged offline." : intent.reply
                lastActions = intent.actions
                appendHistory(transcript: text, reply: replyText, intent: intent.label)

                // Route through the offline-specialized dispatcher:
                // non-destructive actions (change_hos, log_arrival,
                // message_reply) fire immediately, destructive ones
                // (emergency_sos, accept_load, decline_load) are
                // held behind a confirm sheet since there's no
                // server policy check to bounce the intent against.
                await VoiceActionDispatcher.shared.dispatchOffline(
                    intent.actions,
                    prompt: intent.reply.isEmpty ? intent.label : intent.reply,
                    auth: auth,
                    connectivity: connectivity
                )

                // Belt-and-suspenders: also drop the raw utterance into
                // the voice lane so the server sees the original audio
                // for training + audit. The typed outbox entries are
                // already enqueued inside VoiceActionDispatcher /
                // HOSStore / EmergencyController on network failure
                // (one per canonical action type) — that's the path
                // that carries the authoritative payload for sync.
                if intent.enqueueOnline {
                    OfflineQueue.shared.enqueueVoice(
                        text: text,
                        loadId: LoadStore.shared.active?.id
                    )
                }
                state = .done
                lastErrorKind = nil
                WKInterfaceDevice.current().play(.success)
                speak(replyText)
                return
            }

            OfflineQueue.shared.enqueueVoice(text: text, loadId: LoadStore.shared.active?.id)
            fail("No connection — queued. Tap to retry.", kind: .offline, haptic: .retry)
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

    #if canImport(Speech)
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
    #endif

    private func teardownAudio() {
        #if canImport(Speech)
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        #endif
        // Cancel the listening watchdog — stopAndSubmit / error paths
        // all run through here, so this is the single choke point for
        // killing the 30s safety timer.
        listeningWatchdog?.cancel()
        listeningWatchdog = nil
        // L4 — the mic route is ours to yield. Give it back to the
        // workout session so GPS / heart-rate / background execution
        // resume. Safe even when pauseForVoice was never called.
        DrivingSessionManager.shared.resumeAfterVoice()
    }

    private func speak(_ text: String) {
        guard !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(utterance)
    }
}
