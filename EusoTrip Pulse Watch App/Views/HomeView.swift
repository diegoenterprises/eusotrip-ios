//
//  HomeView.swift
//  EusoTrip Pulse Watch App
//
//  Two-page wrist surface.
//
//  PAGE 1 — IDLE ORB (default)
//      The Esang orb floating alone in a dark vignette. No chrome, no
//      chips, no load card. Particles drift continuously; the orb
//      breathes up/down 2 points every 5.6s so it reads as "alive" even
//      when nothing's happening. This is the screen the driver sees when
//      they raise their wrist and glance — nothing to parse, nothing to
//      interpret. Just the brand. Tap the orb → listening. Swipe left to
//      open the instrument panel.
//
//  PAGE 2 — INSTRUMENT PANEL
//      Precision-instrument layout inspired by the segmented-gauge watch
//      face: two vertical gradient HOS gauges hug the bezel (drive
//      remaining left, 14h window remaining right), small circular
//      complications up top (phone link + fatigue tint), active load
//      strip, and three circular action dials at the bottom — HOS /
//      Phone / SOS. Every dial reacts to live state.
//
//  Every surface is driven by live data:
//      AuthStore.firstName                    → greeting / sign-in hint
//      WatchConnectivityManager.isReachable   → phone complication
//      EsangSession.state                     → orb intent
//      ErgoMonitor.fatigueTint/Label          → fatigue complication
//      LoadStore.active                       → load strip (omitted if nil)
//      HOSStore.current                       → vertical gauges + HOS dial
//
//  No placeholders. No synthetic data. If a value is missing, the
//  empty state renders and we wait for WCSession or tRPC to populate it.
//

import SwiftUI
import WatchKit
import Combine

struct HomeView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var esang: EsangSession
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @EnvironmentObject var hos: HOSStore
    @EnvironmentObject var loads: LoadStore
    @EnvironmentObject var ergo: ErgoMonitor

    @State private var page: Int = {
        #if targetEnvironment(simulator)
        ProcessInfo.processInfo.environment["EUSOTRIP_PULSE_VISUAL_STATE"] == "instrument" ? 1 : 0
        #else
        0
        #endif
    }()

    var body: some View {
        TabView(selection: $page) {
            IdleOrbPage()
                .tag(0)
            InstrumentPanel()
                .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .background(brandBackground.ignoresSafeArea())
        // NOTE: previously clipped to ContainerRelativeShape() to keep
        // the magenta halo off the rounded corners, but on hardware the
        // container-shape's inset made the whole UI look like a small
        // square letterboxed inside the watch face. The bezel itself
        // already masks the display, so we let the background extend
        // edge-to-edge again and trust watchOS to do the corner clip.
    }

    private var brandBackground: some View {
        Color.esangBg
    }
}

// MARK: - Page 1 · Idle orb
//
// Only the Esang orb, breathing and floating. This is intentionally
// bare — the whole point of the idle page is that nothing competes with
// the orb for attention. Copy is dimmed to 40% opacity and fades away
// while listening/thinking so the particle field fills the screen.

private struct IdleOrbPage: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var esang: EsangSession
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @ObservedObject private var orb = OrbStateMachine.shared

    // Drift rebased to [-2, +2] instead of [0, -4] so the breathing
    // animation never slides the orb's top arc into the 3:33 / cellular
    // status strip on real 46mm hardware. Same peak-to-peak amplitude,
    // just centered around the vertical midline.
    @State private var drift: CGFloat = 2
    // Halo breathes in lock-step with drift so the whole orb reads "alive"
    // at a glance — the shadow radius cycles 24 → 34, which on 46mm
    // hardware is the difference between a static puck and a gently-lit
    // presence. Matches the 5.6s drift period so they phase together.
    @State private var haloBreath: CGFloat = 24
    @State private var mirrorAttempts: Int = 0
    /// Transient "pairing" flag raised for ~1.5s after a signed-out
    /// tap so the driver sees IMMEDIATE feedback that the tap was
    /// registered and the phone handshake is in flight. Without this,
    /// the signed-out tap was silent — `requestAuthMirror()` fires,
    /// the 2s watchdog ticks invisibly, and the driver reads the orb
    /// as dead. The flag flips false the moment auth.isSignedIn
    /// transitions to true (via onChange below) OR when the escalation
    /// timer lands, whichever comes first.
    @State private var pairingInFlight: Bool = false
    // Fix D — 300ms dedup guard. Double-taps on a bouncy orb were
    // firing two concurrent startListening / stopAndSubmit cycles that
    // raced each other (the second tap would stop the engine before
    // the first tap's recognitionTask had fully attached, ending the
    // turn with an empty transcript). The guard is a wall-clock
    // timestamp (not an in-flight bool) so a dropped Task can't wedge
    // the gate shut.
    @State private var lastOrbTapAt: Date = .distantPast
    /// True only while a chain-group PTT transmission is open from THIS
    /// hold, so the release keys the radio down exactly once and a plain
    /// ESANG hold never sends a stray PTT stop.
    @State private var pttTransmitting: Bool = false
    /// Open-on-iPhone pill state — nil = idle, non-nil = the honest
    /// post-tap message ("Sent — tap the notification…" or the failure
    /// copy). Cleared automatically after a short dwell.
    @State private var openOnPhoneNote: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            EsangOrbWatch(
                intent: orbIntent,
                diameter: 104,
                action: { Task { await handleOrbTap() } },
                longPressAction: { Task { await handleOrbLongPress() } },
                longPressReleaseAction: { Task { await handleOrbPttRelease() } }
            )
            // The unpaired state has a second, truthful action beneath
            // the hint. Lift the orb just enough to reserve a stable
            // footer zone instead of letting the hint ride over its
            // lower arc on 46 mm hardware.
            .offset(y: drift + (auth.isSignedIn ? 0 : -20))
            // When idle + signed in, stack two shadows (cool blue
            // offset up-left, warm magenta offset down-right) so the
            // outer halo reads as the brand gradient rather than a
            // single-color bloom. When the orb enters a mode state
            // (listening / thinking / done / error) we drop back to
            // the single-color mode halo so the state signal stays
            // unmistakable.
            .modifier(IdlePageHalo(haloColor: haloColor,
                                    breath: haloBreath,
                                    gradient: !isModeState))
            .accessibilityLabel(orbAccessibilityLabel)
            .accessibilityAddTraits(.isButton)
            // L1 — unpaired taps are now fully functional (offline
            // VoiceDispatch path), so the VoiceOver hint is the same
            // in both states: double-tap starts listening.
            .accessibilityHint("Double-tap to start listening")
            // Orb animation + tap are ALWAYS live. Previously we gated
            // `allowsHitTesting` and `opacity` on `auth.isSignedIn`,
            // which meant every WCSession reachability flap (phone
            // backgrounds, cellular hop, or the partial-mirror bug that
            // used to wipe the cached token) made the orb dim + stop
            // feeling responsive. The driver read that as "Esang is
            // dead." The orb now breathes, rotates, and accepts taps
            // unconditionally; `handleOrbTap` decides what to DO based
            // on auth + session state.
            //
            // L3/L4 — removed `.allowsHitTesting(esang.state != .thinking)`:
            // when a backend call stalled the session wedged in
            // .thinking, which made the orb geometrically dead. The
            // tap handler already no-ops on .thinking (see the switch
            // at the bottom), so this hit-test guard was pure dead
            // weight that turned the "stuck orb" into a silent one.
            // Halo tint cross-fades when auth flips so the "we're live"
            // moment registers as a visual event even if the driver
            // wasn't reading the hint line.
            .animation(.easeInOut(duration: 0.4), value: auth.isSignedIn)

            VStack {
                Spacer()
                hintLine
                // Pairing gate escape hatch — the old state was a dead
                // end: copy said "Open EusoTrip on iPhone to pair" but
                // NOTHING on the wrist could actually get the iPhone
                // app open. watchOS can't foreground-launch a companion
                // app, so this pill does the honest platform recipe:
                // wake the iPhone in the background (WCSession) → the
                // phone posts an "Open EusoTrip" notification whose tap
                // lands on Home; the Handoff activity published below
                // additionally puts the EusoTrip icon in the iPhone App
                // Switcher / lock screen for instant open.
                if !auth.isSignedIn {
                    openOnPhonePill
                        .padding(.top, 4)
                }
            }
            .padding(.bottom, 8) // was 4 — 46mm rounded corners eat ~2pt

            #if DEBUG
            // Dedicated debug tap surface: an invisible capsule in the
            // top-right of the page (about 30×30pt) that cycles
            // session states on a single tap, stacked OVER the orb so
            // the orb's real tap action (startListening) isn't
            // accidentally triggered together with a state change.
            // Earlier iteration used `.simultaneousGesture` on the
            // orb itself, but that fired BOTH the long-press AND the
            // button tap, which dropped us into stopAndSubmit with
            // the synthetic "Show me my next load" transcript and hit
            // the real backend. This isolated hit-zone makes the
            // cycler side-effect-free. Stripped from release builds.
            VStack {
                HStack {
                    Spacer()
                    Button {
                        esang.debugCycleState()
                        WKInterfaceDevice.current().play(.directionUp)
                    } label: {
                        Image(systemName: "ladybug.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.25))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Debug: cycle Esang state")
                }
                Spacer()
            }
            .padding(.top, 2)
            .padding(.trailing, 4)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // NOTE: previously clipped to ContainerRelativeShape() to stop
        // the orb halo spilling past the rounded corners, but the shape
        // insets the layout and turns the watch face into a visible
        // square. Let the hardware bezel do the final mask.
        //
        // Handoff publisher — while the wrist is unpaired, advertise
        // the continuation activity so the EusoTrip icon appears on the
        // iPhone lock screen / App Switcher for a one-tap continuation.
        // The destination is explicit so iOS opens the real ESANG surface
        // and starts voice capture only after the user foregrounds it.
        .userActivity(EusoTripConfig.handoffActivityType,
                      isActive: !auth.isSignedIn) { activity in
            activity.title = "Continue with ESANG"
            activity.userInfo = [
                "destination": "esang",
                "transcript": "",
                "beginListening": true,
                "autoSubmit": false,
            ]
            activity.isEligibleForHandoff = true
        }
        .onAppear {
            // Preflight permission surface. If Mic or Speech
            // Recognition was denied in a previous session (or in
            // Settings), flip the orb into a visible `.error` card
            // with a Settings hint RIGHT NOW instead of waiting for
            // the first tap to reject. Non-prompting — just reads
            // the authorization status.
            esang.checkPermissionsOnLaunch()

            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 5.6).repeatForever(autoreverses: true)) {
                drift = -2
                haloBreath = 34
            }
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            // Once auth lands, reset the tap counter so future sign-outs
            // start from "Tap to connect" again rather than jumping
            // straight to the longer fallback copy. Also drop the
            // transient pairing hint — the orb's halo will cross-fade
            // from cool blue to magenta, which IS the "paired"
            // celebration, and keeping "Pairing…" on screen past that
            // transition would read as stale.
            if signedIn {
                mirrorAttempts = 0
                withAnimation(.easeInOut(duration: 0.25)) {
                    pairingInFlight = false
                }
                // Clear any stale phone-pairing / unauthorized
                // error card that was up while we were signed out.
                // The auth mirror just resolved those; leaving the
                // red card on screen would read as "still broken"
                // to a driver who just saw the halo bloom magenta.
                if case .error = esang.state,
                   let k = esang.lastErrorKind,
                   k == .phonePairing || k == .unauthorized {
                    esang.resetToIdle()
                }
            }
        }
    }

    private var orbIntent: EsangOrbWatch.Intent {
        switch esang.state {
        case .idle:      return .idle
        case .listening: return .listening
        case .thinking:  return .thinking
        case .done:      return .done
        case .error:     return .error
        }
    }

    /// True whenever the session is in a mode state (listening /
    /// thinking / done / error) so we know to render the mode's
    /// single-color halo instead of the idle brand-gradient halo.
    private var isModeState: Bool {
        switch esang.state {
        case .idle: return false
        default:    return true
        }
    }

    private var haloColor: Color {
        switch esang.state {
        case .listening: return .esangListening
        case .thinking:  return .esangAmber
        case .done:      return .esangGreen
        case .error:     return .esangDanger
        default:
            // When signed out the halo shifts to cool indigo so the
            // orb reads as "not yet live." The moment auth mirrors
            // in, the color crossfades back to the brand magenta —
            // that 400ms transition IS the "paired" celebration,
            // and it's visible even to a driver who never reads the
            // hint line underneath.
            return auth.isSignedIn ? .esangMagenta : .esangBlue
        }
    }

    /// VoiceOver label that reflects the current orb state so a visually
    /// impaired driver hears the same information a glance would convey.
    private var orbAccessibilityLabel: String {
        if !auth.isSignedIn { return "Esang orb — unpaired; tap to ask on Apple Watch" }
        switch esang.state {
        case .idle:      return "Esang orb — idle"
        case .listening: return "Esang orb — listening"
        case .thinking:  return "Esang orb — thinking"
        case .done:      return "Esang orb — done"
        case .error:     return "Esang orb — error"
        }
    }

    /// Bottom hint. The orb stays usable while signed out, so the idle
    /// instruction remains visible beside the separate iPhone continuation.
    /// Once signed in, renders per-state strings (listening / thinking /
    /// done / error) and a whisper mantra while idle.
    @ViewBuilder
    private var hintLine: some View {
        // L1/L3 — single unified hint line driven by OrbStateMachine.
        // No branch reads "Pairing…" past the 1.5 s deadline; the
        // default ("Tap to ask") + OFFLINE capsule means the orb is
        // never silent and never stuck on a pairing spinner. Session-
        // specific copy (listening/thinking/done/error) still wins
        // over the state-machine hint because it carries live
        // transcript + reply context.
        if case .listening = esang.state {
            // Always render the "Listening…" header so there's a clear
            // capture affordance before the first syllable lands. When
            // partial transcription comes in, swap it in underneath.
            VStack(spacing: 2) {
                Text("Listening…")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.esangListening)
                if !esang.transcript.isEmpty {
                    Text(esang.transcript)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .transition(.opacity)
        } else if case .thinking = esang.state {
            Text("Thinking…")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.esangAmber)
                .transition(.opacity)
        } else if case .done = esang.state {
            // Even when the server returned an empty spokenText field
            // (intent dispatched but no reply string), give the driver
            // an explicit confirmation so they can put their wrist
            // down and keep driving.
            Text(esang.replyText.isEmpty ? "Done." : esang.replyText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.esangGreen)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 10)
                .transition(.opacity)
        } else if case .error(let msg) = esang.state {
            // The previous "10pt red text" error line was something
            // the driver could glance past without ever registering
            // — exactly the "easy to miss" failure mode we're
            // chasing. Replaced with a bordered danger card that
            // stamps (a) a kind-specific icon, (b) the message at
            // 11pt, and (c) a capitalized action hint underneath so
            // recovery is obvious without reading the whole line.
            ErrorHintCard(message: msg, kind: esang.lastErrorKind)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else {
            // Default idle / unpaired line — NEVER "Pairing…" past
            // the 1.5 s deadline. OrbStateMachine.hint collapses to
            // "Tap to ask" once the pairing watchdog elapses, with
            // the OFFLINE capsule next to it when the network path is
            // down or we're unpaired. This is the fix for the
            // "stuck on Pairing…" symptom users reported.
            HStack(spacing: 6) {
                Text(orb.hint)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(.white.opacity(auth.isSignedIn ? 0.55 : 0.75))
                if orb.showOfflineCapsule {
                    HStack(spacing: 3) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 8, weight: .heavy))
                        Text("OFFLINE")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .tracking(0.6)
                    }
                    .foregroundStyle(Color.esangAmber.opacity(0.9))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(
                        Capsule().fill(Color.white.opacity(0.08))
                            .overlay(
                                Capsule().strokeBorder(
                                    Color.esangAmber.opacity(0.45),
                                    lineWidth: 0.6
                                )
                            )
                    )
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                orb.showOfflineCapsule
                    ? "\(orb.hint). Offline — transcripts will queue."
                    : orb.hint
            )
        }
    }

    /// The pairing gate's working "Open on iPhone" affordance. Wakes
    /// the iPhone app in the background and reports the TRUTH of what
    /// happened — never a silent tap, never a fake success.
    @ViewBuilder
    private var openOnPhonePill: some View {
        if let note = openOnPhoneNote {
            Text(note)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .transition(.opacity)
        } else {
            Button {
                WKInterfaceDevice.current().play(.click)
                let dispatch = connectivity.requestPhoneActivation(
                    transcript: nil,
                    reply: "Continue with ESANG on your iPhone.",
                    destination: .esang,
                    beginListening: true
                )
                withAnimation(.easeInOut(duration: 0.15)) {
                    switch dispatch {
                    case .sent:
                        openOnPhoneNote = "Sent - tap Continue with ESANG on your iPhone."
                    case .queued:
                        openOnPhoneNote = "Queued for your iPhone."
                    case .unavailable:
                        openOnPhoneNote = "iPhone bridge unavailable - bring it nearby and try again."
                    }
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(6))
                    withAnimation(.easeInOut(duration: 0.2)) { openOnPhoneNote = nil }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "iphone.and.arrow.forward")
                        .font(.system(size: 9, weight: .bold))
                    Text("Continue on iPhone")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color.white.opacity(0.12))
                        .overlay(Capsule().strokeBorder(Color.esangBlue.opacity(0.55), lineWidth: 0.8))
                )
            }
            .buttonStyle(.plain)
            .transition(.opacity)
        }
    }

    private func handleOrbTap() async {
        // Debounce rapid double-taps. Floor relaxed from 300 ms → 150
        // ms (L1): 300 ms ate legitimate rescue taps on bumpy wrists
        // and made the orb feel dead. 150 ms still coalesces accidental
        // bounces without swallowing real user intent.
        let now = Date()
        guard now.timeIntervalSince(lastOrbTapAt) > 0.15 else { return }
        lastOrbTapAt = now

        OrbLog.tap(state: esang.state, signedIn: auth.isSignedIn)

        // L1 — the `guard auth.isSignedIn` gate has been REMOVED.
        // Previously every unpaired tap fell into requestAuthMirror +
        // a 1.5 s watchdog that painted the "phonePairing" error card
        // — effectively a silent loop for drivers who never got a
        // phone handshake. Now the tap flows through to
        // esang.startListening() in all cases. If `auth.token` is
        // empty, EsangSession.performBackendCall's empty-token fast
        // path routes the utterance through VoiceDispatch +
        // OfflineQueue (offline-first per F04). Best-effort mirror is
        // kicked in the background so the NEXT tap may upgrade to
        // the authenticated path, but the current tap is NEVER
        // silent.
        if !auth.isSignedIn {
            connectivity.requestAuthMirror()
            mirrorAttempts = min(mirrorAttempts + 1, 99)
            _ = connectivity.requestPhoneActivation(
                transcript: nil,
                reply: "Continue with ESANG on your iPhone.",
                destination: .esang,
                beginListening: true
            )
        }
        WKInterfaceDevice.current().play(.click)
        switch esang.state {
        case .idle, .done:
            await esang.startListening(auth: auth, connectivity: connectivity)
        case .error:
            // Smart retry. Route by the typed error kind so the tap
            // does the thing the card is hinting the driver to do:
            //   • Permission errors → NEVER auto-retry (the mic/
            //     speech switch is still off, another tap would
            //     just hit the same denial). Do nothing; the hint
            //     card is already telling them to open Settings.
            //   • Unauthorized → kick requestAuthMirror + replay
            //     the last transcript once the token lands. If the
            //     phone doesn't respond in 1s, fall through to a
            //     fresh mic cycle so the driver isn't stuck.
            //   • Offline / timeout → replay the last transcript
            //     straight through; the retry loop in
            //     performBackendCall handles backoff.
            //   • Anything else → fresh mic cycle.
            if let kind = esang.lastErrorKind {
                if kind.blocksAutoRetry {
                    let dispatch = connectivity.requestPhoneActivation(
                        transcript: nil,
                        reply: "Continue with ESANG on your iPhone.",
                        destination: .esang,
                        beginListening: true
                    )
                    if dispatch.accepted {
                        esang.setError(
                            "Watch voice input is unavailable. Continue from the ESANG notification on iPhone.",
                            kind: kind
                        )
                    }
                    return
                }
                switch kind {
                case .unauthorized:
                    connectivity.requestAuthMirror()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if auth.isSignedIn, !esang.lastTranscript.isEmpty {
                        await esang.retryLast(auth: auth, connectivity: connectivity)
                    } else if auth.isSignedIn {
                        await esang.startListening(auth: auth, connectivity: connectivity)
                    } else {
                        _ = connectivity.requestPhoneActivation(
                            transcript: nil,
                            reply: "Continue with ESANG on your iPhone.",
                            destination: .esang,
                            beginListening: true
                        )
                        esang.setError(
                            "Sign in or continue with ESANG from the iPhone notification.",
                            kind: .phonePairing
                        )
                    }
                case .phonePairing:
                    // Re-kick the pairing handshake — this is the
                    // same path the signed-out tap takes; we're
                    // retrying it because the error card told them
                    // to. If the phone mirrors auth within 1.2s,
                    // clear the error silently and start listening.
                    withAnimation(.easeInOut(duration: 0.15)) {
                        pairingInFlight = true
                    }
                    connectivity.requestAuthMirror()
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    withAnimation(.easeInOut(duration: 0.15)) {
                        pairingInFlight = false
                    }
                    if auth.isSignedIn {
                        esang.resetToIdle()
                        await esang.startListening(auth: auth, connectivity: connectivity)
                    } else {
                        _ = connectivity.requestPhoneActivation(
                            transcript: nil,
                            reply: "Continue with ESANG on your iPhone.",
                            destination: .esang,
                            beginListening: true
                        )
                        esang.setError(
                            "Continue with ESANG from the iPhone notification.",
                            kind: .phonePairing
                        )
                    }
                case .offline, .networkTimeout:
                    if !esang.lastTranscript.isEmpty {
                        await esang.retryLast(auth: auth, connectivity: connectivity)
                    } else {
                        await esang.startListening(auth: auth, connectivity: connectivity)
                    }
                default:
                    await esang.startListening(auth: auth, connectivity: connectivity)
                }
            } else {
                await esang.startListening(auth: auth, connectivity: connectivity)
            }
        case .listening:
            // Recorder-owned turn: the Button tap ALSO lands at the
            // long-press release (see EsangOrbWatch's simultaneous
            // gestures). Without this guard the stray tap ran
            // stopAndSubmit with an EMPTY transcript (the recorder
            // path never writes `esang.transcript`) and reset the
            // session to idle mid-turn — killing the hold-to-talk
            // submit before it could run.
            if EsangHoldToTalk.isRecorderTurnActive { return }
            await esang.stopAndSubmit(auth: auth, connectivity: connectivity)
        case .thinking:
            break
        }
    }

    /// Press-and-hold handler for the idle orb page. Bypasses the
    /// complex error-state smart-retry tree so a held orb always
    /// produces an immediate listening session — "ESANG literally on
    /// your wrist."
    /// True when the chain-group walkie-talkie is the correct path for a
    /// hold RIGHT NOW: there's an active load, the phone reports PTT is
    /// available (its restricted entitlement is granted + framework live),
    /// and the phone is joined to THIS load's chain-group. When false the
    /// orb hold stays on the ESANG voice path — today's behavior — so the
    /// driver never meets a broken walkie-talkie button.
    private var pttEngaged: Bool {
        guard connectivity.pttAvailable,
              let active = LoadStore.shared.active else { return false }
        // The phone only advertises a chain-group it has actually joined;
        // require it to match the wrist's active load so we never key up
        // into the wrong haul's channel.
        if let phoneGroup = connectivity.pttChainGroupId {
            return phoneGroup == active.id
        }
        return false
    }

    private func handleOrbLongPress() async {
        // BRANCH: chain-group walkie-talkie vs. ESANG voice.
        //
        // PTT (human → convoy): when `pttEngaged`, the hold keys the
        // load's chain-group radio UP via the phone's PTChannelManager
        // (the wrist can't own one — PushToTalk is iOS-only). The matching
        // key-DOWN fires from `handleOrbPttRelease` when the finger lifts.
        // This is a SEPARATE path from ESANG and never mixes with it.
        if pttEngaged {
            let now = Date()
            guard now.timeIntervalSince(lastOrbTapAt) > 0.15 else { return }
            lastOrbTapAt = now
            WKInterfaceDevice.current().play(.start)
            esang.state = .listening          // reuse the "live mic" orb visual
            pttTransmitting = true
            connectivity.sendPttTransmit(begin: true)
            return
        }

        // ESANG (human → AI): hold-to-talk dictation. The long-press
        // fires when the user has held the orb past EsangOrbWatch's
        // threshold; the finger LIFT lands in `handleOrbPttRelease`
        // (EsangOrbWatch's DragGesture.onEnded → release closure),
        // which stops the recorder and submits. A 30s watchdog Task
        // is the only other exit — and it SUBMITS the capture rather
        // than discarding it, so a stuck gesture still delivers the
        // driver's words.
        let now = Date()
        guard now.timeIntervalSince(lastOrbTapAt) > 0.15 else { return }
        lastOrbTapAt = now
        OrbLog.tap(state: esang.state, signedIn: auth.isSignedIn)
        await EsangHoldToTalk.begin(esang: esang, auth: auth, connectivity: connectivity)
    }

    /// Finger lifted on the orb. Two jobs:
    ///   1. Close a chain-group PTT transmission if one is open —
    ///      keys the radio DOWN via the phone.
    ///   2. End a recorder-owned ESANG hold: stop the AVAudioRecorder
    ///      and submit the capture through transcription → esang.chat.
    ///      This is THE primary submit path for hold-to-talk; before
    ///      this fix nothing stopped the recorder on lift and the
    ///      audio was thrown away.
    private func handleOrbPttRelease() async {
        if pttTransmitting {
            pttTransmitting = false
            connectivity.sendPttTransmit(begin: false)
            WKInterfaceDevice.current().play(.stop)
            // Drop the borrowed "listening" visual back to idle; PTT has no
            // thinking/transcribe phase — the voice already went out live.
            if case .listening = esang.state { esang.resetToIdle() }
            return
        }
        await EsangHoldToTalk.end(esang: esang, auth: auth, connectivity: connectivity)
    }
}

// MARK: - EsangHoldToTalk
//
// Shared hold-to-talk engine for BOTH Home pages (IdleOrbPage +
// InstrumentPanel) so a held orb means the same thing everywhere:
// press → AVAudioRecorder arms; lift → recorder stops and the capture
// rides transcription.transcribeAudio → EsangSession.submitTranscribedText
// → esang.chat. The 30s watchdog SUBMITS (never discards) a capture
// whose release event was eaten by a TabView swipe or wrist-down.
//
// L4 audio-route handling mirrors EsangSession.startListening():
// DrivingSessionManager's HKWorkoutSession can hold the route, so we
// yield before arming the recorder and resume after every stop/cancel
// path.
@MainActor
enum EsangHoldToTalk {

    /// Hard-cap watchdog for the current hold. Cancelled on release.
    private static var watchdog: Task<Void, Never>?

    /// True while a recorder-owned turn is live. Tap handlers consult
    /// this to suppress the Button tap that lands at gesture release —
    /// without the guard, that stray tap ran `stopAndSubmit` with an
    /// EMPTY transcript and reset the session to idle mid-turn.
    static var isRecorderTurnActive: Bool {
        WatchAudioRecorder.shared.isRecording
    }

    /// Arm the recorder for a hold-to-talk turn.
    static func begin(
        esang: EsangSession,
        auth: AuthStore,
        connectivity: WatchConnectivityManager
    ) async {
        // Haptic so the driver knows the recorder armed.
        WKInterfaceDevice.current().play(.start)
        // Kick a best-effort auth mirror when unpaired so a token can
        // land while the driver is still speaking.
        if !auth.isSignedIn { connectivity.requestAuthMirror() }
        // L4a — yield the workout session's audio route + preflight the
        // .playAndRecord activation before arming the recorder.
        DrivingSessionManager.shared.yieldAudioRoute()
        do {
            try AudioSessionPreflight.check()
            try await WatchAudioRecorder.shared.start()
            esang.state = .listening
        } catch {
            DrivingSessionManager.shared.resumeAfterVoice()
            esang.setError("Mic unavailable — check Settings → Privacy → Microphone.",
                           kind: .permissionMic)
            return
        }

        // Watchdog: if the release never lands, stop at 30s and SUBMIT
        // the capture instead of discarding it.
        watchdog?.cancel()
        watchdog = Task {
            try? await Task.sleep(nanoseconds: 30 * NSEC_PER_SEC)
            guard !Task.isCancelled else { return }
            guard WatchAudioRecorder.shared.isRecording else { return }
            let url = WatchAudioRecorder.shared.stop()
            DrivingSessionManager.shared.resumeAfterVoice()
            await submit(url: url, esang: esang, auth: auth, connectivity: connectivity)
        }
    }

    /// Finger lifted — stop the recorder and submit the capture. No-op
    /// when no recorder turn is active (plain tap, PTT hold, or the
    /// watchdog already closed the turn).
    static func end(
        esang: EsangSession,
        auth: AuthStore,
        connectivity: WatchConnectivityManager
    ) async {
        watchdog?.cancel()
        watchdog = nil
        guard WatchAudioRecorder.shared.isRecording else { return }
        let url = WatchAudioRecorder.shared.stop()
        DrivingSessionManager.shared.resumeAfterVoice()
        await submit(url: url, esang: esang, auth: auth, connectivity: connectivity)
    }

    /// Upload the capture to Gemini transcription and feed the verbatim
    /// text into the canonical `esang.chat` pipeline. `url == nil`
    /// means another exit path already owned this turn — nothing to do.
    private static func submit(
        url: URL?,
        esang: EsangSession,
        auth: AuthStore,
        connectivity: WatchConnectivityManager
    ) async {
        guard let url else { return }
        WKInterfaceDevice.current().play(.stop)
        guard auth.isSignedIn else {
            // The wrist can't transcribe locally (no Speech framework
            // on watchOS) and the transcription endpoint needs a
            // bearer. Loud, actionable card — never a silent drop.
            esang.setError("Sign in on your iPhone to use hold-to-talk.",
                           kind: .unauthorized)
            return
        }
        esang.state = .thinking
        do {
            let transcript = try await WatchAudioRecorder.shared
                .transcribe(fileURL: url, auth: auth)
            if transcript.isEmpty {
                esang.setError("Didn't catch that — try again.", kind: .unknown)
                return
            }
            await esang.submitTranscribedText(
                transcript, auth: auth, connectivity: connectivity)
        } catch {
            esang.setError("Couldn't reach the transcription service. Try again.",
                           kind: .networkTimeout)
        }
    }
}

// MARK: - ErrorHintCard
//
// Upgrades the previous 10pt red text line into an unmistakable error
// card with (1) a kind-specific icon, (2) a full-weight message
// string, and (3) a capitalized action hint underneath. The driver's
// glance reads the icon first (mic-slash / wifi-slash / iphone-slash
// / exclamation), confirms the message, and takes the action in the
// caption — all without having to squint at small body text. For
// permission errors the hint points at Settings because watchOS can't
// deep-link into Privacy → Microphone from a third-party app; for
// transient errors the hint reads "TAP TO RETRY" because the orb's
// tap handler (see handleOrbTap) will replay the last transcript or
// kick an auth-mirror refresh based on `lastErrorKind`.
private struct ErrorHintCard: View {
    let message: String
    let kind: EsangErrorKind?

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.esangDanger)
                Text(message)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
            }
            Text(actionHint)
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(Color.esangDanger.opacity(0.95))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.esangDanger.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.esangDanger.opacity(0.55), lineWidth: 0.8)
                )
        )
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message). \(actionHint).")
    }

    private var icon: String {
        switch kind {
        case .permissionMic, .permissionBoth:        return "mic.slash.fill"
        case .permissionSpeech, .speechUnavailable:  return "waveform.slash"
        case .unauthorized, .phonePairing:           return "iphone.slash"
        case .offline, .networkTimeout:              return "wifi.slash"
        case .micHardware:                           return "exclamationmark.mic.fill"
        default:                                     return "exclamationmark.triangle.fill"
        }
    }

    private var actionHint: String {
        switch kind {
        case .permissionMic, .permissionSpeech, .permissionBoth:
            return "SETTINGS → PRIVACY → ALLOW"
        case .speechUnavailable:
            return "TRY AGAIN IN A MOMENT"
        case .micHardware:
            return "TAP TO RETRY"
        case .unauthorized:
            return "OPEN EUSOTRIP ON IPHONE"
        case .phonePairing:
            return "TAP TO RECONNECT"
        case .offline, .networkTimeout:
            return "TAP TO RETRY"
        case .unknown, .none:
            return "TAP TO RETRY"
        }
    }
}

// MARK: - Page 2 · Instrument panel
//
// Precision-instrument layout inspired by the multi-gauge watch face.
// Left + right bezel-hugging vertical gauges render HOS drive and 14h
// window remaining as segmented gradient tape. Top row = two small
// circular complications (phone link, fatigue). Middle = the Esang orb
// at 54pt — still the flagship, but compact. Bottom = three circular
// dials: HOS status, Phone handoff, SOS.

private struct InstrumentPanel: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var esang: EsangSession
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @EnvironmentObject var hos: HOSStore
    @EnvironmentObject var loads: LoadStore
    @EnvironmentObject var ergo: ErgoMonitor
    @ObservedObject private var inbox = InboxStore.shared
    // F13 — convoy indicator slot. Observed here (not inside the child
    // pill) so the whole InstrumentPanel diffs when peers enter/leave
    // and the strip can animate in/out without lifting `.shared` into
    // every render of a dormant indicator.
    @ObservedObject private var convoy = ConvoyCoordinator.shared
    @ObservedObject private var convoySig = ConvoySignatureObservable.shared

    @State private var pingPhoneTimestamp: Date?
    @State private var phoneActivationDispatch: PhoneActivationDispatch?
    @State private var showDebugHealth: Bool = false
    /// See IdleOrbPage: open only while THIS hold's chain-group PTT
    /// transmission is live, so release keys the radio down exactly once.
    @State private var pttTransmitting: Bool = false

    var body: some View {
        ZStack {
            // Bezel tapes — 8pt HOS vertical gauges sitting tight to
            // the rounded edges. Slim enough to keep the orb + load
            // strip out of the old letterbox column, thick enough to
            // read as deliberate instrument-panel rails (rather than
            // hairlines that look like rendering glitches). The bezel
            // hardware does the corner mask.
            if let currentHOS {
                HStack(spacing: 0) {
                    HOSVerticalGauge(
                        title: "Drive",
                        valueText: currentHOS.driveHoursText,
                        fill: currentHOS.drivePct,
                        gradient: driveGradient,
                        side: .leading
                    )
                    .frame(width: 6)
                    .padding(.leading, 8)
                    .padding(.top, 24)
                    .padding(.bottom, 18)
                    Spacer(minLength: 0)
                    HOSVerticalGauge(
                        title: "Window",
                        valueText: currentHOS.windowHoursText,
                        fill: currentHOS.windowPct,
                        gradient: windowGradient,
                        side: .trailing
                    )
                    .frame(width: 6)
                    .padding(.trailing, 14)
                    .padding(.top, 24)
                    .padding(.bottom, 18)
                }
            }

            // Content column — uses the whole face. Horizontal padding
            // clears the 8pt + 3pt edge stack with a small visual
            // buffer. No more 26pt center-column letterbox.
            VStack(spacing: 4) {
                topComplications
                heroOrb
                convoyStrip
                loadStrip
                actionDialRow
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 0)
        }
        // NOTE: previously clipped to ContainerRelativeShape() to keep
        // glows off the rounded corners, but the shape's inset made the
        // instrument panel sit inside a visible square instead of
        // filling the watch face. Trust the hardware bezel to do the
        // final mask.
    }

    // MARK: Top row — small instrument-style complications.

    private var topComplications: some View {
        HStack(spacing: 6) {
            // Left complication: iPhone link when paired + reachable,
            // otherwise pivots to the Inbox dial so the driver never
            // sees a dim placeholder — the wrist always shows something
            // actionable. Once phone link is solid, we stamp the
            // unread-messages count on it as a top-right badge so the
            // driver sees both signals at a glance.
            if connectivity.isReachable {
                MiniDial(
                    symbol: "iphone",
                    tint: .esangGreen,
                    pulse: true,
                    caption: inbox.unreadTotal > 0 ? "INBOX" : "LINK",
                    badgeCount: inbox.unreadTotal
                )
            } else if inbox.unreadTotal > 0 {
                MiniDial(
                    symbol: "message.fill",
                    tint: .esangBlue,
                    pulse: false,
                    caption: "INBOX",
                    badgeCount: inbox.unreadTotal
                )
            } else {
                MiniDial(
                    symbol: "iphone",
                    tint: .esangTextDim,
                    pulse: false,
                    caption: "AWAY"
                )
            }
            Spacer()
            VStack(spacing: 1) {
                Text("HOS")
                    .font(.system(size: 7, weight: .heavy, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.tertiary)
                Text(currentHOS?.driveHoursText ?? "UNVERIFIED")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(currentHOS == nil ? Color.esangAmber : Color.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
                // L5c — triple-tap the HOS evidence label to open DebugHealth.
                // DEBUG-only so production drivers can't stumble into
                // the diagnostic surface.
                #if DEBUG
                .onTapGesture(count: 3) {
                    showDebugHealth = true
                }
                .sheet(isPresented: $showDebugHealth) {
                    DebugHealthView()
                }
                #endif
            Spacer()
            MiniDial(
                symbol: "waveform.path.ecg",
                tint: ergo.fatigueTint,
                pulse: false,
                caption: ergo.fatigueLabel.uppercased()
            )
        }
    }

    // MARK: Hero orb — compact twin of the idle page.

    private var heroOrb: some View {
        HStack(spacing: 4) {
            #if DEBUG
            // Dedicated debug cycler, scoped inline with the hero orb
            // so it's near the element it drives but physically
            // separate from the button itself — same side-effect-free
            // contract as the idle-page cycler. QA can step
            // idle → listening → thinking → done → error → idle and
            // watch the miniature orb + gauges + action dials react.
            Button {
                esang.debugCycleState()
                WKInterfaceDevice.current().play(.directionUp)
            } label: {
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.25))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Debug: cycle Esang state")
            #endif

            EsangOrbWatch(
                intent: orbIntent,
                diameter: 54,
                action: { Task { await handleOrbTap() } },
                longPressAction: { Task { await handleOrbLongPress() } },
                longPressReleaseAction: { Task { await handleOrbPttRelease() } }
            )
            // See the IdleOrbPage rationale — the `allowsHitTesting`
            // gate has been removed. handleOrbTap still no-ops on
            // `.thinking`, so the only behavior change here is that a
            // wedged session doesn't leave the hero orb geometrically
            // dead.

            #if DEBUG
            // Balance the layout — invisible spacer the same width
            // as the debug button so the orb stays visually centered
            // in its row. The ladybug only takes a few pt anyway, so
            // this is purely optical, not functional.
            Color.clear.frame(width: 18, height: 18)
            #endif
        }
    }

    // MARK: Convoy strip.
    //
    // F13 — compact peer indicator. Dormant by default (renders a
    // zero-height shim), lights up the moment ConvoyCoordinator has
    // members, candidates, or an active SOS. Tapping routes to the
    // detail view via VoiceActionDispatcher so voice-opened and
    // tile-opened paths share the same sheet presenter in RootView.
    //
    // Visual language stays aligned with the rest of the instrument
    // panel: capsule pill, rounded-design typography, brand gradient
    // outline. Trust dot (green/amber/red) summarizes the worst peer
    // trust state so a single red peer visibly taints the group without
    // needing to open the detail.
    @ViewBuilder
    private var convoyStrip: some View {
        let peerCount = convoy.members.count + convoy.candidates.count
        let sosActive = convoy.activeConvoySOS != nil
        if peerCount > 0 || sosActive {
            Button {
                WKInterfaceDevice.current().play(.click)
                VoiceActionDispatcher.shared.currentRoute = .convoy
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: sosActive ? "exclamationmark.triangle.fill" : "dot.radiowaves.left.and.right")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(sosActive ? Color.esangDanger : Color.esangMagenta)
                    Text(sosActive ? "SOS" : "CONVOY")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(sosActive ? Color.esangDanger : Color.white.opacity(0.85))
                    Text("\(convoy.members.count)")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    if convoy.candidates.count > 0 {
                        Text("+\(convoy.candidates.count)")
                            .font(.system(size: 7, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.esangAmber)
                    }
                    Spacer(minLength: 0)
                    // Worst-trust dot. Any suspect → red. Any unknown →
                    // amber. All confirmed (or no peers yet) → green.
                    Circle()
                        .fill(convoyTrustDotColor)
                        .frame(width: 6, height: 6)
                        .shadow(color: convoyTrustDotColor.opacity(0.6), radius: 2)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule(style: .continuous)
                        .fill(sosActive
                              ? Color.esangDanger.opacity(0.18)
                              : Color.white.opacity(0.05))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    sosActive
                                        ? AnyShapeStyle(Color.esangDanger.opacity(0.8))
                                        : AnyShapeStyle(LinearGradient.esangPrimary.opacity(0.55)),
                                    lineWidth: 0.7
                                )
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(convoyAccessibility(peerCount: peerCount, sos: sosActive))
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }

    private var convoyTrustDotColor: Color {
        // Walk the pinned trust states for the actual peers we're
        // displaying. If any member resolved to .suspect, the group is
        // compromised until the roster verifier upgrades them. If any
        // member is still .unknown (first sighting, roster call hasn't
        // landed yet), the group is cautious-amber. Otherwise green.
        let ids = convoy.members.map(\.driverId) + convoy.candidates.map(\.driverId)
        var sawUnknown = false
        for id in ids {
            switch convoySig.trustStates[id] ?? .unknown {
            case .suspect:   return .esangDanger
            case .unknown:   sawUnknown = true
            case .confirmed: break
            }
        }
        return sawUnknown ? .esangAmber : .esangGreen
    }

    private func convoyAccessibility(peerCount: Int, sos: Bool) -> String {
        if sos { return "Convoy SOS active. Tap for details." }
        let member = convoy.members.count == 1 ? "member" : "members"
        if convoy.candidates.count > 0 {
            return "Convoy with \(convoy.members.count) \(member), \(convoy.candidates.count) joining. Tap for details."
        }
        return "Convoy with \(convoy.members.count) \(member). Tap for details."
    }

    // MARK: Active load strip.

    @ViewBuilder
    private var loadStrip: some View {
        if let load = loads.active {
            Button {
                WKInterfaceDevice.current().play(.click)
                VoiceActionDispatcher.shared.currentRoute = .loadDetail(loadId: load.id)
            } label: {
                HStack(spacing: 4) {
                    Text(load.displayId)
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.esangPrimary)
                        .lineLimit(1)
                        .layoutPriority(2)
                    Text(load.originShort)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.esangMagenta)
                        .layoutPriority(1)
                    Text(load.destShort)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(LinearGradient.esangPrimary.opacity(0.55), lineWidth: 0.7)
                        )
                )
            }
            .buttonStyle(.plain)
        } else {
            // Silent empty row. Preserves layout height so the orb +
            // action dock don't shift when a load gets assigned.
            Color.clear.frame(height: 20)
        }
    }

    // MARK: Bottom row — three circular action dials.

    private var actionDialRow: some View {
        HStack(spacing: 4) {
            // HOS dial — inner segmented ring visualises drive remaining.
            InstrumentDial(
                size: 40,
                ringFill: currentHOS?.drivePct,
                ringGradient: driveGradient,
                fillBody: currentHOS?.status == .driving,
                bodyColor: hosAccent,
                accessibilityText: hosDialA11y,
                content: {
                    VStack(spacing: 0) {
                        Image(systemName: currentHOS?.status.symbol ?? "questionmark.circle")
                            .font(.system(size: 12, weight: .bold))
                        Text(currentHOS?.status.short ?? "—")
                            .font(.system(size: 7, weight: .heavy))
                            .tracking(0.6)
                    }
                    .foregroundStyle(currentHOS?.status == .driving ? Color.white : hosAccent)
                },
                action: {
                    Task {
                        guard let status = currentHOS?.status else {
                            WKInterfaceDevice.current().play(.click)
                            VoiceActionDispatcher.shared.currentRoute = .hos
                            return
                        }
                        let next: HOSStatus = status == .driving ? .onDuty : .driving
                        await hos.changeStatus(to: next, auth: auth, connectivity: connectivity)
                        WKInterfaceDevice.current().play(.click)
                    }
                }
            )

            // Phone handoff dial — ping the paired iPhone.
            // Ring runs the full brand gradient (blue → magenta). The
            // body color stays `.esangBlue` so the glyph still reads as
            // the iPhone affordance — only the outer ring is branded.
            InstrumentDial(
                size: 40,
                ringFill: connectivity.isReachable ? 1.0 : 0.0,
                ringGradient: LinearGradient(
                    colors: [.esangBlue, .esangMagenta],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                fillBody: false,
                bodyColor: .esangBlue,
                accessibilityText: phoneDialA11y,
                content: {
                    VStack(spacing: 0) {
                        Image(systemName: phoneSymbol)
                            .font(.system(size: 12, weight: .bold))
                        Text(phoneTileLabel)
                            .font(.system(size: 7, weight: .heavy))
                            .tracking(0.5)
                    }
                    .foregroundStyle(Color.esangBlue)
                },
                action: {
                    WKInterfaceDevice.current().play(.click)
                    phoneActivationDispatch = connectivity.requestPhoneActivation(
                        transcript: nil,
                        reply: "Open EusoTrip on your iPhone.",
                        destination: .home
                    )
                    pingPhoneTimestamp = Date()
                }
            )

            // SOS dial — body + emphasis halo remain danger-red so the
            // emergency affordance is unmistakable, but the ring itself
            // now runs the brand gradient so all three bottom dials
            // share a visually consistent outer rim. The emergency
            // semantic lives in the red body fill + the breathing
            // danger-tinted halo around it.
            InstrumentDial(
                size: 40,
                ringFill: 1.0,
                ringGradient: LinearGradient(
                    colors: [.esangBlue, .esangMagenta],
                    startPoint: .top, endPoint: .bottom
                ),
                fillBody: false,
                bodyColor: .esangDanger,
                emphasize: true,
                accessibilityText: "Emergency SOS. Tap to start the emergency relay.",
                content: {
                    VStack(spacing: 0) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("SOS")
                            .font(.system(size: 7, weight: .heavy))
                            .tracking(0.6)
                    }
                    .foregroundStyle(Color.esangDanger)
                },
                action: {
                    WKInterfaceDevice.current().play(.failure)
                    Task {
                        await EmergencyController.shared.activate(
                            reason: "manual-home",
                            auth: auth,
                            connectivity: connectivity
                        )
                    }
                }
            )
        }
    }

    /// VoiceOver description for the HOS dial — describes current
    /// status + remaining drive clock so blind drivers get the same
    /// at-a-glance read as the sighted gauges.
    private var hosDialA11y: String {
        guard let observation = currentHOS else {
            return "HOS evidence unavailable. Tap to open Hours of Service and request current provider data."
        }
        let status: String
        switch observation.status {
        case .driving: status = "driving"
        case .onDuty:  status = "on duty"
        case .sleeper: status = "sleeper berth"
        case .off:     status = "off duty"
        }
        let next: String = observation.status == .driving ? "on duty" : "driving"
        return "HOS status: \(status). \(observation.driveHoursText) drive remaining. Tap to switch to \(next)."
    }

    /// VoiceOver description for the phone handoff dial — surfaces
    /// reachability + last-ping state so the SENT / PING / — glyph
    /// has a spoken twin.
    private var phoneDialA11y: String {
        if let ts = pingPhoneTimestamp, Date().timeIntervalSince(ts) < 2.5 {
            switch phoneActivationDispatch {
            case .sent: return "Phone activation sent. Tap to send again."
            case .queued: return "Phone activation queued. Tap to queue again."
            case .unavailable: return "Phone bridge unavailable. Tap to retry."
            case nil: break
            }
        }
        return connectivity.isReachable
            ? "iPhone reachable. Tap to ping the phone."
            : "iPhone unreachable. Tap to wake it."
    }

    // MARK: Derived

    private var currentHOS: WatchHOS? { hos.currentObservation }

    private var orbIntent: EsangOrbWatch.Intent {
        switch esang.state {
        case .idle:      return .idle
        case .listening: return .listening
        case .thinking:  return .thinking
        case .done:      return .done
        case .error:     return .error
        }
    }

    private var phoneSymbol: String {
        if let ts = pingPhoneTimestamp, Date().timeIntervalSince(ts) < 2.5 {
            switch phoneActivationDispatch {
            case .sent: return "checkmark"
            case .queued: return "clock.arrow.circlepath"
            case .unavailable: return "exclamationmark"
            case nil: break
            }
        }
        return connectivity.isReachable ? "iphone.and.arrow.forward" : "iphone.slash"
    }

    private var phoneTileLabel: String {
        if let ts = pingPhoneTimestamp, Date().timeIntervalSince(ts) < 2.5 {
            switch phoneActivationDispatch {
            case .sent: return "SENT"
            case .queued: return "QUEUED"
            case .unavailable: return "FAILED"
            case nil: break
            }
        }
        return connectivity.isReachable ? "PING" : "AWAY"
    }

    private var hosAccent: Color {
        guard let status = currentHOS?.status else { return .esangTextDim }
        switch status {
        case .driving: return .esangBlue
        case .onDuty:  return .esangAmber
        case .sleeper: return .esangMagenta
        case .off:     return .esangTextDim
        }
    }

    // Both bezel gauges now render in the pure EusoTrip brand gradient.
    // Previously the drive gauge included a coral midpoint and the
    // 14-hour window gauge started in amber — the combined wrist read
    // leaned pink/orange and undercut the brand. Switching both to a
    // clean blue → magenta sweep keeps the instrument-panel tapes
    // visually synchronized and lets the mode tints (pink Listening,
    // amber Thinking, green Done, red Error) stand out on the orb
    // without competing with the bezel.
    private var driveGradient: LinearGradient {
        LinearGradient(
            colors: [.esangBlue, .esangMagenta],
            startPoint: .bottom, endPoint: .top
        )
    }
    // Window gauge runs the gradient in reverse so the two tapes hug
    // the bezel as a mirrored pair — drive fills blue-up-to-magenta,
    // window fills magenta-up-to-blue. Same brand, visibly distinct
    // sides.
    private var windowGradient: LinearGradient {
        LinearGradient(
            colors: [.esangMagenta, .esangBlue],
            startPoint: .bottom, endPoint: .top
        )
    }

    private func handleOrbTap() async {
        OrbLog.tap(state: esang.state, signedIn: auth.isSignedIn)
        // L1 — same policy as IdleOrbPage: the `guard auth.isSignedIn`
        // early-return has been removed. Unpaired taps now flow
        // through to startListening, whose empty-token fast-path
        // routes to VoiceDispatch + OfflineQueue.
        if !auth.isSignedIn {
            connectivity.requestAuthMirror()
            _ = connectivity.requestPhoneActivation(
                transcript: nil,
                reply: "Continue with ESANG on your iPhone.",
                destination: .esang,
                beginListening: true
            )
        }
        WKInterfaceDevice.current().play(.click)
        switch esang.state {
        case .idle, .error, .done:
            await esang.startListening(auth: auth, connectivity: connectivity)
        case .listening:
            // Suppress the stray Button tap that lands at the release
            // of a recorder-owned hold (same guard as IdleOrbPage) —
            // otherwise it commits an empty transcript and kills the
            // in-flight hold-to-talk turn.
            if EsangHoldToTalk.isRecorderTurnActive { return }
            await esang.stopAndSubmit(auth: auth, connectivity: connectivity)
        case .thinking:
            break
        }
    }

    /// Press-and-hold handler. "ESANG on your wrist." Unified with
    /// IdleOrbPage: a hold means the same thing on every Home page —
    /// the WatchAudioRecorder hold-to-talk pipeline (EsangHoldToTalk).
    /// Previously this page routed the hold into the dictation SHEET,
    /// so the two copies of the same gesture took two different
    /// pipelines. The tap path continues to route through
    /// EsangSession.startListening → DictationBroker as the deliberate
    /// no-audio fallback.
    /// Same gate as IdleOrbPage.pttEngaged, resolved against THIS panel's
    /// injected `loads` store: PTT is the right path only on an active
    /// load whose chain-group the phone has joined and reports available.
    private var pttEngaged: Bool {
        guard connectivity.pttAvailable, let active = loads.active else { return false }
        if let phoneGroup = connectivity.pttChainGroupId {
            return phoneGroup == active.id
        }
        return false
    }

    private func handleOrbLongPress() async {
        // BRANCH: chain-group walkie-talkie (human → convoy) vs. ESANG
        // (human → AI). Held on an active-load chain-group with PTT live →
        // key the radio UP via the phone. Otherwise → ESANG hold-to-talk.
        if pttEngaged {
            WKInterfaceDevice.current().play(.start)
            esang.state = .listening
            pttTransmitting = true
            connectivity.sendPttTransmit(begin: true)
            return
        }

        OrbLog.tap(state: esang.state, signedIn: auth.isSignedIn)
        // If mid-listen on a dictation-sheet turn, commit it first so the
        // driver can hold-and-speak from any state.
        if case .listening = esang.state, !EsangHoldToTalk.isRecorderTurnActive {
            await esang.stopAndSubmit(auth: auth, connectivity: connectivity)
            return
        }
        await EsangHoldToTalk.begin(esang: esang, auth: auth, connectivity: connectivity)
    }

    /// Finger lifted — close a chain-group PTT transmission (key down) if
    /// one is open, or end a recorder-owned ESANG hold (stop + submit).
    private func handleOrbPttRelease() async {
        if pttTransmitting {
            pttTransmitting = false
            connectivity.sendPttTransmit(begin: false)
            WKInterfaceDevice.current().play(.stop)
            if case .listening = esang.state { esang.resetToIdle() }
            return
        }
        await EsangHoldToTalk.end(esang: esang, auth: auth, connectivity: connectivity)
    }
}

// MARK: - HOSVerticalGauge
//
// Segmented vertical tape that hugs the watch bezel. The fill level is
// animated between values so a status change from driving → on-duty
// slides the brand gradient down instead of snapping. Matches the
// "battery peg + colored segments" aesthetic from the inspiration face.

private struct HOSVerticalGauge: View {
    let title: String
    let valueText: String
    let fill: Double?        // 0...1 when current evidence exists
    let gradient: LinearGradient
    /// Which side of the bezel this rail hugs. Drives the arc curl
    /// direction so the leading rail bows out left and the trailing
    /// rail bows out right, matching the Apple Watch Ultra Modular
    /// face's symmetric tick rails.
    var side: BezelSide = .leading

    enum BezelSide { case leading, trailing }

    @State private var animatedFill: Double?

    var body: some View {
        GeometryReader { geo in
                let W = geo.size.width
                let H = geo.size.height
                // Corner radius mirrors the bezel curve. Apple Watch
                // hardware rounds at ~30pt on 41/45/46 and ~74pt on
                // Ultra; we render in points so the rail naturally
                // matches whichever device the app runs on by hugging
                // a generous radius that bows correctly on every size.
                let cornerR = min(W * 0.9, H * 0.32)

                ZStack {
                    // Dim scaffold rail — full arc at low opacity.
                    BezelRailShape(side: side, cornerRadius: cornerR)
                        .stroke(
                            Color.white.opacity(0.10),
                            style: StrokeStyle(lineWidth: W, lineCap: .round)
                        )
                    // Lit rail — same arc trimmed to the fill ratio so
                    // the gradient grows from the bottom toward the
                    // top, curling around the bezel corners.
                    if let animatedFill {
                        BezelRailShape(side: side, cornerRadius: cornerR)
                            .trim(from: 1.0 - animatedFill, to: 1.0)
                            .stroke(
                                gradient,
                                style: StrokeStyle(lineWidth: W, lineCap: .round)
                            )
                            .shadow(color: .white.opacity(0.18), radius: 1)
                    }
                }
        }
        .onAppear { animatedFill = fill }
        .onChange(of: fill) { _, new in
            withAnimation(.easeInOut(duration: 0.6)) { animatedFill = new }
        }
        .accessibilityLabel("\(title): \(valueText)")
    }
}

/// Path that traces the bezel curve on one side of the watch face.
/// On the leading side the path starts at the top, arcs into the
/// top-left corner, runs straight down the left edge, then arcs out
/// of the bottom-left corner. The trailing side mirrors that on the
/// right edge. Trimming this path from the bottom up yields a
/// gradient rail that grows toward the top while hugging the
/// bezel's rounded corners — matching the Modular Ultra design
/// language without forcing a Canvas + per-frame redraw.
private struct BezelRailShape: Shape {
    let side: HOSVerticalGauge.BezelSide
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))

        switch side {
        case .leading:
            // Start at top-center of the rail, arc toward the top-
            // left corner, run down the left edge, arc out of the
            // bottom-left corner ending at bottom-center.
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addArc(
                center: CGPoint(x: rect.minX + r, y: rect.minY + r),
                radius: r,
                startAngle: .degrees(-90),
                endAngle: .degrees(180),
                clockwise: true
            )
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
            p.addArc(
                center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                radius: r,
                startAngle: .degrees(180),
                endAngle: .degrees(90),
                clockwise: true
            )
        case .trailing:
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addArc(
                center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                radius: r,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            p.addArc(
                center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                radius: r,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        }
        return p
    }
}

// MARK: - MiniDial
//
// Tiny circular complication used in the top-row status strip. A gradient
// ring around a monochrome glyph — precision-instrument vibe at 24pt.

private struct MiniDial: View {
    let symbol: String
    let tint: Color
    let pulse: Bool
    let caption: String
    /// Optional top-right numeric badge (e.g. unread message count).
    /// Rendered as a blue pill capped at "9+" so it doesn't eat the 20pt
    /// dial. Zero suppresses the badge entirely — the dial renders as-is.
    var badgeCount: Int = 0

    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 1) {
            ZStack {
                if pulse {
                    Circle()
                        .fill(tint.opacity(0.35))
                        .frame(width: 20 * pulseScale, height: 20 * pulseScale)
                        .opacity(2 - Double(pulseScale))
                        .animation(
                            .easeOut(duration: 1.4).repeatForever(autoreverses: false),
                            value: pulseScale
                        )
                }
                Circle()
                    .stroke(tint.opacity(0.65), lineWidth: 1)
                    .frame(width: 20, height: 20)
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                if badgeCount > 0 {
                    Text(badgeCount > 9 ? "9+" : "\(badgeCount)")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .frame(minWidth: 12, minHeight: 12)
                        .background(Capsule().fill(Color.esangBlue))
                        .overlay(
                            Capsule().strokeBorder(Color.black.opacity(0.45), lineWidth: 0.5)
                        )
                        .offset(x: 8, y: -8)
                        .accessibilityLabel("\(badgeCount) unread messages")
                }
            }
            Text(caption)
                .font(.system(size: 7, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .onAppear { pulseScale = pulse ? 1.8 : 1.0 }
    }
}

// MARK: - InstrumentDial
//
// Circular action button that looks like a precision gauge. An outer
// progress ring (filled fraction of the brand gradient) wraps a dark
// body with an inner gradient stroke and a glyph/label stack. Used for
// HOS status, phone handoff, and SOS.

private struct InstrumentDial<Content: View>: View {
    let size: CGFloat
    let ringFill: Double?         // 0...1 when the represented fact is tracked
    let ringGradient: LinearGradient
    var fillBody: Bool = false
    let bodyColor: Color
    var emphasize: Bool = false
    /// VoiceOver label surfaced for each dial. Default empty — callers
    /// should supply one so the dial row isn't a string of "Button,
    /// Button, Button" under VoiceOver.
    var accessibilityText: String = ""
    @ViewBuilder let content: () -> Content
    let action: () -> Void

    @State private var pressed: Bool = false
    /// Emphasize ring breathing — tints the halo under the SOS dial so
    /// the driver's eye is drawn to it without the dial having to be
    /// physically larger than its siblings.
    @State private var emphasisPulse: CGFloat = 1.0

    var body: some View {
        Button(action: action) {
            ZStack {
                // Emphasis halo — ONLY renders on SOS/emphasize dials so
                // the attention pull is surgical, not every dial.
                if emphasize {
                    Circle()
                        .fill(bodyColor.opacity(0.25))
                        .scaleEffect(emphasisPulse)
                        .blur(radius: 4)
                        .animation(
                            .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                            value: emphasisPulse
                        )
                }

                // Outer arc track (dim)
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 3)

                // Progress arc
                if let ringFill {
                    Circle()
                        .trim(from: 0, to: max(0, ringFill))
                        .stroke(
                            ringGradient,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(color: bodyColor.opacity(0.4), radius: 3)
                        .animation(.easeInOut(duration: 0.45), value: ringFill)
                }

                // Body
                Circle()
                    .fill(bodyFill)
                    .padding(5)
                    .overlay(
                        Circle()
                            .strokeBorder(bodyStroke, lineWidth: 0.8)
                            .padding(5)
                    )
                    .shadow(color: bodyColor.opacity(emphasize ? 0.45 : 0.0), radius: emphasize ? 6 : 0)

                content()
            }
            .frame(width: size, height: size)
            .scaleEffect(pressed ? 0.92 : 1.0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.easeOut(duration: 0.1)) { pressed = true } }
                .onEnded { _ in withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { pressed = false } }
        )
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .onAppear {
            // Kick the emphasis-breath off on mount. Harmless on
            // non-emphasize dials — the pulse view isn't rendered
            // for them anyway.
            if emphasize { emphasisPulse = 1.18 }
        }
    }

    private var bodyFill: AnyShapeStyle {
        fillBody
            ? AnyShapeStyle(LinearGradient.esangPrimary)
            : AnyShapeStyle(Color.esangCard.opacity(0.85))
    }

    private var bodyStroke: AnyShapeStyle {
        fillBody
            ? AnyShapeStyle(Color.white.opacity(0.25))
            : AnyShapeStyle(bodyColor.opacity(emphasize ? 0.55 : 0.28))
    }
}

// MARK: - IdlePageHalo
//
// SwiftUI's `.shadow(color:)` accepts a single color, so a
// "gradient halo" is faked by stacking two offset shadows in the
// two brand hues. The Idle-page orb owns a large breathing halo
// (diameter grows from 24pt → 34pt every 5.6s), and previously
// that halo rendered as a solid magenta bloom, which pushed the
// screen pink — the very "woman's app" read the driver called
// out. Splitting the halo into a cool blue puff offset up-and-left
// plus a warm magenta puff offset down-and-right produces a
// diagonal brand-gradient glow that matches the orb's own
// rotating gradient disc. The moment the session enters a mode
// state (listening / thinking / done / error) we collapse back
// to the single mode-tinted halo so the state change reads
// unambiguously (coral = listening, amber = thinking, green =
// done, red = error).
private struct IdlePageHalo: ViewModifier {
    let haloColor: Color
    let breath: CGFloat
    let gradient: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if gradient {
            content
                .shadow(color: Color.esangBlue.opacity(0.45),
                        radius: breath, x: -3, y: -2)
                .shadow(color: Color.esangMagenta.opacity(0.45),
                        radius: breath, x: 3, y: 4)
        } else {
            content.shadow(color: haloColor.opacity(0.45),
                           radius: breath, y: 4)
        }
    }
}
