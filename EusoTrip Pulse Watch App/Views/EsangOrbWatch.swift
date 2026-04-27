//
//  EsangOrbWatch.swift
//  EusoTrip Pulse Watch App
//
//  Wrist-scale port of the iOS Esang orb. Keeps the exact same visual
//  grammar as DesignSystem.OrbESang / EsangParticleField on the phone:
//
//    • Rotating LinearGradient(esangBlue → esangMagenta) disc
//    • Specular highlight with hue-shift drift
//    • Additive-white particle swarm bouncing inside the disc
//    • Brand-tinted drop shadow that intensifies with state
//
//  States (drives shadow + halo intensity + particle speed):
//      .idle        — slow rotation, soft magenta shadow
//      .listening   — coral outer ring pulse, tighter gradient, haptic-in-sync
//      .thinking    — amber tint, intensified swarm, fastest rotation
//      .done        — green check-in shadow, particles settle
//      .error       — danger red tint
//
//  Tap target: full view. Parent provides the action. We draw at ~82pt
//  diameter by default — the sweet spot between Ultra 49mm and S4 40mm
//  where the swarm still reads without crowding the HUD.
//

import SwiftUI
import WatchKit

struct EsangOrbWatch: View {
    enum Intent { case idle, listening, thinking, done, error }

    let intent: Intent
    var diameter: CGFloat = 82
    var action: () -> Void = {}
    /// Invoked on press-and-hold (≥ `longPressMinimum` seconds). The
    /// canonical use is force-fresh voice listening — ESANG literally
    /// on your wrist — that bypasses the standard tap-handler's
    /// error-state smart-retry logic and skips the tap debounce.
    /// Defaulted to a no-op so existing call-sites keep compiling.
    var longPressAction: () -> Void = {}
    /// Seconds the finger must stay down before `longPressAction`
    /// fires. 0.55s is the watchOS-native feel — anything shorter
    /// collides with Force-Touch-era muscle memory; anything longer
    /// feels dead. Tunable per caller for edge screens where a
    /// shorter hold is preferable (e.g. an emergency flow).
    var longPressMinimum: Double = 0.55

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0
    @State private var hueShift: Double = -12
    @State private var pulseRing: CGFloat = 1.0
    /// Tap-acknowledgement feedback. Flips true for ~0.45s every time
    /// `action()` fires (tap, long-press, or the accessibility action)
    /// so the driver sees an instantaneous ring + scale pulse regardless
    /// of whether `handleOrbTap` produced a visible state change. Without
    /// this, a tap while signed-out (which silently fires
    /// `connectivity.requestAuthMirror()`) felt like a dead button.
    @State private var tapFlash: Bool = false
    /// Scale pulse for the whole orb on tap. 0.93 then back to 1.0 is the
    /// watchOS-native "button press" feel — Apple uses the same scale on
    /// first-party complications.
    @State private var pressScale: CGFloat = 1.0
    /// Debounce anchor for `invokeLongPress` so a held gesture that
    /// wobbles within the LongPressGesture's tolerance doesn't re-fire.
    @State private var lastLongPressAt: Date = .distantPast

    private var rotationPeriod: Double {
        switch intent {
        case .thinking:  return reduceMotion ? 3 : 1.8
        case .listening: return reduceMotion ? 6 : 3.0
        default:         return reduceMotion ? 28 : 14
        }
    }

    private var glowColor: Color {
        switch intent {
        case .idle:      return .esangMagenta
        case .listening: return .esangListening
        case .thinking:  return .esangAmber
        case .done:      return .esangGreen
        case .error:     return .esangDanger
        }
    }

    private var glowRadius: CGFloat {
        switch intent {
        case .listening, .thinking: return 22
        case .error:                return 18
        default:                    return 14
        }
    }

    private var gradient: LinearGradient {
        switch intent {
        case .listening:
            return LinearGradient(
                colors: [.esangListening, .esangMagenta, .esangBlue],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .thinking:
            return LinearGradient(
                colors: [.esangBlue, .esangMagenta, .esangAmber],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .error:
            return LinearGradient(
                colors: [.esangDanger, .esangMagenta],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .done:
            return LinearGradient(
                colors: [.esangGreen, .esangBlue],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .idle:
            // Pure two-stop EusoTrip brand gradient. A previous pass
            // added a coral (esangListening) midpoint to "balance the
            // axis," but on-wrist that read as pink — the driver called
            // it out as "you got this app looking like a woman's app."
            // The brand is blue → magenta, full stop; coral is reserved
            // for the Listening mode so it stays semantically
            // distinctive. The diagonal topLeading→bottomTrailing sweep
            // still reads clearly with two stops because the orb is
            // always either rotating or breathing.
            return LinearGradient(
                colors: [.esangBlue, .esangMagenta],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    var body: some View {
        // TAP RELIABILITY ON watchOS 26.4 — fourth pass.
        //
        // Background. The EusoTrip Pulse orb lives at the bottom of TWO
        // nested TabViews: RootView wraps a vertical crown-driven TabView
        // (Home / HOS / Inbox / Convoy / Settings) and HomeView wraps a
        // horizontal `.page` TabView (idle orb / instrument panel). Both
        // TabViews install their own DragGesture at a higher layer than
        // any gesture we attach to the orb body, so a naive tap gesture
        // gets eaten by the page swipe recognizer.
        //
        // Earlier passes:
        //  · #1 — wrapped Button. Canvas+TimelineView inside the label
        //    starved the Button's internal gesture on device.
        //  · #2 — `.onTapGesture` + `.onLongPressGesture`. Both sit below
        //    ancestor DragGestures in resolution, so they lost on device.
        //  · #3 — `.highPriorityGesture(TapGesture)` + `.simultaneousGesture
        //    (LongPressGesture)`. Sounded right, but on the v4 user
        //    report the orb still felt dead under quick taps.
        //
        // This pass (#4) combines three belt-and-suspenders techniques:
        //
        //   1. Primary hit surface is a real `Button` whose LABEL is the
        //      orb visuals. Button taps are the most reliable watchOS
        //      control, and the Canvas is fenced off from gesture
        //      resolution below (`allowsHitTesting(false)` on the core
        //      visual stack + a bottom-layer invisible hit-catcher
        //      circle) so the Button's gesture isn't starved.
        //
        //   2. Press-hold is handled by `.onLongPressGesture(minimumDuration:
        //      maximumDistance:)` — the canonical SwiftUI API — with a
        //      reasonable 0.30s minimum that's still forgiving to driver
        //      muscle memory.
        //
        //   3. EVERY successful tap fires a short visible ack —
        //      `tapFlash` pulses a ring, and `pressScale` does a 0.93
        //      → 1.0 bounce — regardless of what `handleOrbTap` does
        //      downstream. This is what fixes the "I tap but nothing
        //      happens" feel when the watch is signed out and the
        //      outer handler silently kicks off `requestAuthMirror`.
        //      The orb ALWAYS tells you it received the tap.
        // TEAM C — Stock Button only. All gesture modifiers removed so
        // watchOS's native Button tap handling is the ONLY gesture
        // recognizer on the orb. The Button's own label (ZStack below)
        // is the hit surface; `.contentShape(Circle())` at the label
        // level scopes hits to the circle. No `.allowsHitTesting(false)`
        // on the interactive ZStack — Button needs hit testing on its
        // own label to resolve the tap.
        Button(action: invokeAction) {
            ZStack {
                // Outer listening ring — purely decorative.
                if intent == .listening {
                    Circle()
                        .stroke(Color.esangListening.opacity(0.55), lineWidth: 2)
                        .frame(width: diameter * pulseRing, height: diameter * pulseRing)
                        .opacity(2 - Double(pulseRing))
                        .animation(
                            .easeOut(duration: 1.2).repeatForever(autoreverses: false),
                            value: pulseRing
                        )
                        .allowsHitTesting(false)
                }

                // Tap-ack ring. Not conditional on intent — we want
                //    to see this pulse EVERY time the user taps, even
                //    when the outer handler is a silent no-op (e.g.
                //    signed-out → requestAuthMirror). A bright white
                //    ring flashes out past the orb's edge and fades.
                if tapFlash {
                    Circle()
                        .stroke(Color.white.opacity(0.85), lineWidth: 2.5)
                        .frame(width: diameter * 1.25, height: diameter * 1.25)
                        .blendMode(.plusLighter)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }

                // Core orb: rotating gradient + specular + particle
                // swarm. The inner Canvas/TimelineView keeps its own
                // `.allowsHitTesting(false)` (see WatchEsangParticleField
                // below) so the per-frame animation host can't eat the
                // Button's tap — but this outer ZStack MUST remain
                // hit-testable so the Button's label actually receives
                // hits. (Previously we had `.allowsHitTesting(false)`
                // here; that's what was making taps feel dead.)
                ZStack {
                    ZStack {
                        Circle().fill(gradient)
                        Circle()
                            .fill(RadialGradient(
                                colors: [.white.opacity(0.75), .white.opacity(0)],
                                center: .init(x: 0.35, y: 0.30),
                                startRadius: 0,
                                endRadius: diameter * 0.55
                            ))
                            .frame(width: diameter * 0.72, height: diameter * 0.72)
                            .hueRotation(.degrees(reduceMotion ? 0 : hueShift))
                            .blendMode(.plusLighter)
                    }
                    .rotationEffect(.degrees(rotation))

                    WatchEsangParticleField(
                        diameter: diameter,
                        intensified: intent == .thinking || intent == .listening
                    )
                }
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
                // Gradient halo on idle — two stacked shadows (blue
                // offset up-left, magenta offset down-right) read as a
                // brand-gradient bloom rather than the single-color
                // shadow a lone `.shadow(color:)` produces. Mode states
                // still use their single-color halos (coral for
                // Listening, amber for Thinking, green for Done,
                // danger for Error) so the mode signal is preserved.
                .modifier(OrbHalo(intent: intent, radius: glowRadius, single: glowColor))
            }
            // The ZStack tightly hugs the diameter so the hit region and
            // the visuals match 1:1. `.contentShape(Circle())` is set so
            // SwiftUI uses the circular shape when routing taps at the
            // Button label level.
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .scaleEffect(pressScale)
        }
        .buttonStyle(.plain)
        // ── Long-press recognizer ──
        //
        // Ships alongside the Button's native tap handler via
        // `.simultaneousGesture` rather than `.onLongPressGesture`.
        // `simultaneousGesture` runs in parallel with the Button's
        // recognizer rather than racing it, so:
        //
        //   • A quick tap still routes through Button.action (no
        //     regression vs. the TEAM-C tap-only build).
        //   • A hold ≥ `longPressMinimum` fires `invokeLongPress`
        //     WITHOUT cancelling the Button — the tap lands at
        //     release too, which is fine because `invokeLongPress`
        //     is idempotent and debounced against the tap via a
        //     shared `lastLongPressAt` timestamp. If the caller
        //     leaves `longPressAction` at its default no-op, this
        //     recognizer still fires but does nothing visible
        //     beyond the stronger haptic — matching user intent
        //     (they clearly held on purpose).
        //
        // The earlier pass that removed all extra gestures did so
        // because `.onLongPressGesture` was competing with the
        // ancestor TabView's DragGesture — that competition came
        // from `.onLongPressGesture` being a PRIMARY recognizer on
        // the Button subtree. `.simultaneousGesture` is a SIDE
        // recognizer and doesn't conflict with the TabView swipes.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: longPressMinimum, maximumDistance: 24)
                .onEnded { _ in invokeLongPress() }
        )
        .onAppear {
            withAnimation(.linear(duration: rotationPeriod).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                    hueShift = 12
                }
            }
            pulseRing = 1.45
        }
        .onChange(of: intent) { _, _ in
            // Re-key the rotation so period transitions between states
            // (idle 14s → thinking 1.8s) feel instant rather than blending.
            withAnimation(.linear(duration: rotationPeriod).repeatForever(autoreverses: false)) {
                rotation += 360
            }
        }
        .accessibilityLabel("Esang")
        .accessibilityValue(accessibilityState)
        .accessibilityAddTraits(.isButton)
    }

    /// Single entry-point for both the tap and the long-press paths.
    /// Runs the visible ack animation (press-scale + flash ring + haptic)
    /// then hands off to the owner-provided `action()`. Because the ack
    /// is unconditional, the driver ALWAYS sees feedback even when
    /// `action()` is a silent background request.
    private func invokeAction() {
        // Haptic confirmation — `.click` is the subtle "button pressed"
        // tick used across watchOS first-party controls.
        WKInterfaceDevice.current().play(.click)

        // Scale bounce: dip to 0.93 for 80ms, spring back to 1.0.
        withAnimation(.easeOut(duration: 0.08)) { pressScale = 0.93 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                pressScale = 1.0
            }
        }

        // Flash ring: fade in, hold for ~0.3s, fade out.
        withAnimation(.easeOut(duration: 0.12)) { tapFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
            withAnimation(.easeIn(duration: 0.25)) { tapFlash = false }
        }

        action()
    }

    /// Long-press handler. Stronger haptic than the tap click so the
    /// driver can feel the difference on a bumpy road without looking,
    /// then a wider white flash ring, then the caller's
    /// `longPressAction` — typically force-fresh voice listening.
    /// Debounced against the last long-press so a held gesture that
    /// drifts doesn't re-fire.
    private func invokeLongPress() {
        let now = Date()
        guard now.timeIntervalSince(lastLongPressAt) > 0.40 else { return }
        lastLongPressAt = now

        // `.notification(.success)` is the watchOS "committed action"
        // haptic — distinct from the softer `.click` used for taps.
        WKInterfaceDevice.current().play(.notification)

        withAnimation(.easeOut(duration: 0.10)) { pressScale = 0.88 }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.5).delay(0.12)) {
            pressScale = 1.0
        }
        withAnimation(.easeOut(duration: 0.14)) { tapFlash = true }
        withAnimation(.easeIn(duration: 0.32).delay(0.32)) { tapFlash = false }

        longPressAction()
    }

    private var accessibilityState: String {
        switch intent {
        case .idle:      return "Idle"
        case .listening: return "Listening"
        case .thinking:  return "Thinking"
        case .done:      return "Done"
        case .error:     return "Error"
        }
    }
}

// MARK: - WatchEsangParticleField
//
// Scaled-down twin of iOS EsangParticleField. Same physics (unit-disk
// reject-sample seed, reflect-and-project containment, twinkle phase),
// but we drop the count to ~34 and let the TimelineView run at 30Hz so
// the watch GPU doesn't spike when the orb is the only visible layer.

struct WatchEsangParticleField: View {
    let diameter: CGFloat
    var intensified: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var engine = WatchParticleEngine(count: 34)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas(opaque: false,
                   colorMode: .extendedLinear,
                   rendersAsynchronously: false) { ctx, size in

                if !reduceMotion {
                    engine.advance(to: t, intensified: intensified)
                }

                let w = size.width, h = size.height
                let cx = w / 2, cy = h / 2
                let R = min(w, h) / 2

                ctx.blendMode = .plusLighter

                for p in engine.particles {
                    let px = cx + p.x * R
                    let py = cy + p.y * R
                    let pr = max(p.r * R, 0.4)

                    let twinkle = 0.55 + 0.45 * sin(p.phase + t * (intensified ? 2.6 : 1.7))

                    let haloR = pr * 4.2
                    ctx.fill(
                        Circle().path(in: CGRect(x: px - haloR, y: py - haloR,
                                                 width: haloR * 2, height: haloR * 2)),
                        with: .color(.white.opacity(0.06 * twinkle))
                    )
                    let midR = pr * 2.1
                    ctx.fill(
                        Circle().path(in: CGRect(x: px - midR, y: py - midR,
                                                 width: midR * 2, height: midR * 2)),
                        with: .color(.white.opacity(0.20 * twinkle))
                    )
                    ctx.fill(
                        Circle().path(in: CGRect(x: px - pr, y: py - pr,
                                                 width: pr * 2, height: pr * 2)),
                        with: .color(.white.opacity(0.95 * twinkle))
                    )
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Watch particle physics
//
// Plain reference class — deliberately NOT @Observable. An @Observable
// engine mutated inside `Canvas` (which runs inside a TimelineView body)
// registers per-frame observation reads on `particles`, and the
// `particles[i] = p` write inside `advance(...)` then invalidates the
// enclosing view. Under watchOS 26.4's tightened observation tracking
// this manifested as a runaway render loop: launch pegged CPU at >100%
// while memory climbed linearly from 70MB until the watchdog killed the
// app ("loads the logo then boots out"). TimelineView already ticks the
// frame cadence; Canvas reads `engine.particles` imperatively during
// draw — we do NOT need SwiftUI to observe the engine.

final class WatchParticleEngine {

    struct Particle {
        var x: Double
        var y: Double
        var vx: Double
        var vy: Double
        var r: Double
        var phase: Double
    }

    private(set) var particles: [Particle]
    private var lastTime: Double = 0

    init(count: Int) {
        self.particles = (0..<count).map { _ in Self.seed() }
    }

    private static func seed() -> Particle {
        var x = 0.0, y = 0.0
        repeat {
            x = Double.random(in: -1...1)
            y = Double.random(in: -1...1)
        } while (x * x + y * y) > 0.82 * 0.82

        let speed = Double.random(in: 0.08...0.24)
        let angle = Double.random(in: 0...(2 * .pi))
        return Particle(
            x: x, y: y,
            vx: cos(angle) * speed,
            vy: sin(angle) * speed,
            r: Double.random(in: 0.016...0.034),
            phase: Double.random(in: 0...(2 * .pi))
        )
    }

    func advance(to time: Double, intensified: Bool) {
        if lastTime == 0 { lastTime = time; return }
        let raw = time - lastTime
        let dt  = max(0, min(raw, 1.0 / 20.0))
        lastTime = time
        let speedScale = intensified ? 1.55 : 1.0

        for i in particles.indices {
            var p = particles[i]
            p.x += p.vx * dt * speedScale
            p.y += p.vy * dt * speedScale

            let d2 = p.x * p.x + p.y * p.y
            let boundary = 0.90
            if d2 > boundary * boundary {
                let d = sqrt(d2)
                let nx = p.x / d
                let ny = p.y / d
                let dot = p.vx * nx + p.vy * ny
                if dot > 0 {
                    p.vx -= 2 * dot * nx
                    p.vy -= 2 * dot * ny
                    p.vx *= 0.995
                    p.vy *= 0.995
                }
                p.x = nx * boundary
                p.y = ny * boundary
            }
            particles[i] = p
        }
    }
}

// MARK: - OrbHalo
//
// SwiftUI's `.shadow(color:)` accepts a single color, so a "gradient
// halo" has to be faked by layering two offset shadows in
// complementary brand hues. When idle, we render a cool blue shadow
// offset up-and-left and a warm magenta shadow offset down-and-right;
// together they blend into the diagonal EusoTrip sweep. When the orb
// transitions into a mode state (listening/thinking/done/error), we
// fall back to the single-color mode shadow so the driver reads the
// state change as a distinctive tint rather than a mushy bi-color
// bloom.

private struct OrbHalo: ViewModifier {
    let intent: EsangOrbWatch.Intent
    let radius: CGFloat
    let single: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        switch intent {
        case .idle:
            content
                .shadow(color: Color.esangBlue.opacity(0.55),
                        radius: radius * 1.1, x: -2, y: -2)
                .shadow(color: Color.esangMagenta.opacity(0.55),
                        radius: radius * 1.1, x: 2, y: 4)
        default:
            content.shadow(color: single.opacity(0.55), radius: radius, y: 4)
        }
    }
}

// MARK: - IridescentHairlineWatch
//
// 1pt blue→magenta gradient rule — the signature "iridescent hairline"
// from the iOS design language. Watch screens are narrow enough that we
// render it inline in the home header.

struct IridescentHairlineWatch: View {
    var body: some View {
        LinearGradient(
            colors: [
                .esangBlue.opacity(0.35),
                .esangMagenta.opacity(0.55),
                .esangBlue.opacity(0.35)
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 0.75)
        .blendMode(.plusLighter)
    }
}
