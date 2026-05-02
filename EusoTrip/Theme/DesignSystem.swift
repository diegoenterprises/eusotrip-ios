//
//  DesignSystem.swift
//  EusoTrip 2027 UI
//
//  Canonical SwiftUI tokens + primitives. Mirrors tokens.css exactly in values.
//  Every Screen in 03_swiftui/ imports from here — no hardcoded hex except the
//  two gradient stops (in LinearGradient.primary).
//
//  Doctrine references live in 00_doctrine/DOCTRINE.md.
//

import SwiftUI

// MARK: - Color hex helper

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >>  8) & 0xFF) / 255.0,
            blue:  Double( hex        & 0xFF) / 255.0,
            opacity: alpha
        )
    }

    /// String initializer — accepts "#RRGGBB", "#RRGGBBAA", "RRGGBB",
    /// or "RRGGBBAA". Falls back to clear on a malformed string so the
    /// app keeps rendering instead of crashing on a bad palette entry.
    init(hex string: String, alpha: Double = 1.0) {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var n: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&n) else {
            self = .clear
            return
        }
        let r, g, b: Double
        var a = alpha
        switch s.count {
        case 6:
            r = Double((n >> 16) & 0xFF) / 255.0
            g = Double((n >>  8) & 0xFF) / 255.0
            b = Double( n        & 0xFF) / 255.0
        case 8:
            r = Double((n >> 24) & 0xFF) / 255.0
            g = Double((n >> 16) & 0xFF) / 255.0
            b = Double((n >>  8) & 0xFF) / 255.0
            a = Double( n        & 0xFF) / 255.0
        default:
            self = .clear
            return
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Brand (immutable across themes)

enum Brand {
    static let blue    = Color(hex: 0x1473FF)
    static let magenta = Color(hex: 0xBE01FF)

    static let success = Color(hex: 0x00C48C)
    static let warning = Color(hex: 0xFFA726)
    static let danger  = Color(hex: 0xF44336)
    static let info    = Color(hex: 0x2196F3)
    static let hazmat  = Color(hex: 0xFFB100)
    static let escort  = Color(hex: 0x9C27B0)
    static let rail    = Color(hex: 0x607D8B)
    static let vessel  = Color(hex: 0x00ACC1)
}

extension LinearGradient {
    static let primary  = LinearGradient(colors: [Brand.blue, Brand.magenta],
                                         startPoint: .leading, endPoint: .trailing)
    static let diagonal = LinearGradient(colors: [Brand.blue, Brand.magenta],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    static let reverse  = LinearGradient(colors: [Brand.magenta, Brand.blue],
                                         startPoint: .leading, endPoint: .trailing)
    static let revenue  = LinearGradient(colors: [Brand.success, Brand.blue],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    static let expense  = LinearGradient(colors: [Brand.danger, Brand.warning],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)

    static let esangSoft = LinearGradient(colors: [Brand.blue.opacity(0.18), Brand.magenta.opacity(0.18)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing)
    static let iridescentHairlineDark = LinearGradient(colors: [Brand.blue.opacity(0.40), Brand.magenta.opacity(0.40)],
                                                       startPoint: .leading, endPoint: .trailing)
    static let iridescentHairlineLight = LinearGradient(colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
                                                        startPoint: .leading, endPoint: .trailing)
}

// MARK: - Theme palette (dark + light)

enum Theme {
    struct Palette {
        let textPrimary:     Color
        let textSecondary:   Color
        let textTertiary:    Color
        let textOnGradient:  Color
        let bgPage:          Color
        let bgPrimary:       Color
        let bgSecondary:     Color
        let bgCard:          Color
        let bgCardSoft:      Color
        let bgNav:           Color
        let bgSheet:         Color
        let borderFaint:     Color
        let borderSoft:      Color
        let borderStrong:    Color
        let tintSuccess:     Color
        let tintWarning:     Color
        let tintDanger:      Color
        let tintInfo:        Color
        let tintHazmat:      Color
        let tintNeutral:     Color
        let iridescentHairline: LinearGradient
        let deviceBezel:     Color
    }

    static let dark = Palette(
        textPrimary:    Color(hex: 0xF5F5F7),
        textSecondary:  Color(hex: 0xAAB2BB),
        textTertiary:   Color(hex: 0x6E7681),
        textOnGradient: .white,
        // Pure ink-black page (was 0x05060A) so the new EusoCard surface
        // reads like volumetric glass floating on obsidian instead of gray
        // squares on a slightly-lighter gray field. The card gradient
        // (see LinearGradient.cardFillDark) is what you actually see — we
        // keep a single flat token here for legacy call-sites only.
        bgPage:         Color(hex: 0x030309),
        bgPrimary:      Color(hex: 0x07070F),
        bgSecondary:    Color(hex: 0x0B0C16),
        // Retained for legacy `.background(palette.bgCard)` call-sites, but
        // tuned to a deep indigo-black — no more neutral gray. Most new
        // code should reach for `.eusoCard()` instead to pick up the full
        // gradient + iridescent hairline + glow.
        bgCard:         Color(hex: 0x0D0E1A),
        bgCardSoft:     Color(hex: 0x131427),
        bgNav:          Color(hex: 0x141928).opacity(0.75),
        bgSheet:        Color(hex: 0x161B22).opacity(0.88),
        borderFaint:    Color.white.opacity(0.08),
        borderSoft:     Color.white.opacity(0.12),
        borderStrong:   Color.white.opacity(0.22),
        tintSuccess:    Brand.success.opacity(0.14),
        tintWarning:    Brand.warning.opacity(0.14),
        tintDanger:     Brand.danger.opacity(0.14),
        tintInfo:       Brand.info.opacity(0.14),
        tintHazmat:     Brand.hazmat.opacity(0.14),
        tintNeutral:    Color.white.opacity(0.08),
        iridescentHairline: .iridescentHairlineDark,
        deviceBezel:    Color(hex: 0x0B0B0F)
    )

    static let light = Palette(
        textPrimary:    Color(hex: 0x0D1117),
        textSecondary:  Color(hex: 0x52606D),
        textTertiary:   Color(hex: 0x8A96A3),
        textOnGradient: .white,
        bgPage:         Color(hex: 0xE9ECF1),
        bgPrimary:      Color(hex: 0xF4F5F7),
        bgSecondary:    Color.white,
        bgCard:         Color.white,
        bgCardSoft:     Color(hex: 0xF4F5F7),
        bgNav:          Color.white.opacity(0.82),
        bgSheet:        Color.white.opacity(0.92),
        borderFaint:    Color.black.opacity(0.06),
        borderSoft:     Color.black.opacity(0.10),
        borderStrong:   Color.black.opacity(0.18),
        tintSuccess:    Brand.success.opacity(0.10),
        tintWarning:    Brand.warning.opacity(0.12),
        tintDanger:     Brand.danger.opacity(0.10),
        tintInfo:       Brand.info.opacity(0.10),
        tintHazmat:     Brand.hazmat.opacity(0.14),
        tintNeutral:    Color.black.opacity(0.05),
        iridescentHairline: .iridescentHairlineLight,
        deviceBezel:    Color(hex: 0x1A1B20)
    )
}

// Palette injected via environment so Screens can switch without prop-drilling
private struct PaletteKey: EnvironmentKey {
    static let defaultValue: Theme.Palette = Theme.dark
}
extension EnvironmentValues {
    var palette: Theme.Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - Typography

enum EType {
    static let display   = Font.system(size: 34, weight: .bold).width(.standard)
    static let h1        = Font.system(size: 28, weight: .bold)
    static let h2        = Font.system(size: 22, weight: .semibold)
    static let title     = Font.system(size: 17, weight: .semibold)
    static let body      = Font.system(size: 15, weight: .regular)
    static let bodyStrong = Font.system(size: 15, weight: .semibold)
    static let caption   = Font.system(size: 12, weight: .regular)
    static let micro     = Font.system(size: 10, weight: .semibold)
    static let numeric   = Font.system(size: 28, weight: .semibold, design: .default).monospacedDigit()

    /// Monospaced variant at a chosen size token — used for tabular
    /// numerics, timestamps, IDs, and hairline metadata rows.
    enum MonoSize { case body, caption, micro }
    static func mono(_ size: MonoSize) -> Font {
        switch size {
        case .body:    return Font.system(size: 13, weight: .medium, design: .monospaced)
        case .caption: return Font.system(size: 11, weight: .medium, design: .monospaced)
        case .micro:   return Font.system(size: 10, weight: .medium, design: .monospaced)
        }
    }
}

// MARK: - Spacing / Radius / Device

enum Space {
    static let s1: CGFloat =  4
    static let s2: CGFloat =  8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s7: CGFloat = 32
    static let s8: CGFloat = 40
}

enum Radius {
    static let sm: CGFloat =  8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
    static let pill: CGFloat = 999
}

enum Device {
    static let width:      CGFloat = 440
    static let height:     CGFloat = 956
    static let safeTop:    CGFloat =  54
    static let safeBottom: CGFloat =  34
    /// Figma 212:428 / 212:444 — measured nav plate height (above the home
    /// indicator). Re-measured 2026-04 against Figma light-mode canvas zoom:
    /// plate spans ~140 Figma-px = 70 device-pt above the safe area so icon
    /// + label have breathing room and the orb rim lines up with the top
    /// of the icon row.
    static let navHeight:  CGFloat =  70
    /// Figma 212:428 — orb physical diameter on the nav plate.  Roughly 16%
    /// of the frame width (≈ 140 Figma-px / 2 = 70 device-pt).  Elevated
    /// (offset) above the plate top by ~40% of its diameter so ~60% of the
    /// disc stays inside the plate for a seated-but-floating feel.
    static let navOrbDiameter: CGFloat = 60
    static let navOrbLift:     CGFloat = 24
    /// Figma top corners on the nav plate — tighter than the 28pt default
    /// used elsewhere in the system.
    static let navCornerRadius: CGFloat = 24
}

// MARK: - OrbESang (doctrine §2.2, §2.3)

struct OrbESang: View {
    /// Interaction-state that drives the orb's visual language.
    ///
    ///   .idle       — slow rotation, soft magenta glow, particles drift
    ///   .listening  — particles lock into travelling horizontal waves,
    ///                 halo pulses in cyan/magenta blend so the driver
    ///                 reads "mic is hot" even without the composer chrome
    ///   .thinking   — rotation snaps to a fast period, particles speed
    ///                 up and the glow intensifies
    enum State { case idle, listening, thinking }

    let state: State
    var diameter: CGFloat = Device.navOrbDiameter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SwiftUI.State private var rotation: Double = 0
    @SwiftUI.State private var hueShift: Double = -12

    private var idlePeriod:      Double { reduceMotion ? 36 : 18 }
    private var listeningPeriod: Double { reduceMotion ? 18 :  6 }
    private var thinkingPeriod:  Double { reduceMotion ?  4 :  2 }

    private var currentPeriod: Double {
        switch state {
        case .idle:      return idlePeriod
        case .listening: return listeningPeriod
        case .thinking:  return thinkingPeriod
        }
    }

    private var glowColor: Color {
        switch state {
        case .idle:      return Brand.magenta
        case .listening: return Brand.blue
        case .thinking:  return Brand.magenta
        }
    }

    private var glowOpacity: Double {
        switch state {
        case .idle:      return 0.40
        case .listening: return 0.55
        case .thinking:  return 0.60
        }
    }

    private var glowRadius: CGFloat {
        switch state {
        case .idle:      return 14
        case .listening: return 20
        case .thinking:  return 22
        }
    }

    private var particleMotion: EsangParticleField.Motion {
        switch state {
        case .idle:      return .idle
        case .listening: return .waving
        case .thinking:  return .intensified
        }
    }

    var body: some View {
        ZStack {
            // Rotating gradient + specular (the "orb" look).
            ZStack {
                Circle().fill(LinearGradient.diagonal)
                // Specular highlight — hue-shifts on its own offset period
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.75), .white.opacity(0)],
                                         center: .init(x: 0.35, y: 0.30),
                                         startRadius: 0, endRadius: diameter * 0.55))
                    .frame(width: diameter * 0.72, height: diameter * 0.72)
                    .hueRotation(.degrees(reduceMotion ? 0 : hueShift))
                    .blendMode(.plusLighter)
            }
            .rotationEffect(.degrees(rotation))

            // ESANG signifier — a field of soft, additively-blended white
            // particles bouncing inside the gradient orb. Rendered OUTSIDE
            // the rotating layer so the swarm drifts under its own physics
            // rather than orbiting as a rigid unit.
            EsangParticleField(diameter: diameter,
                               motion: particleMotion)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .shadow(color: glowColor.opacity(glowOpacity),
                radius: glowRadius, y: 4)
        .accessibilityLabel("ESang AI")
        .accessibilityValue(accessibilityState)
        .onAppear {
            withAnimation(.linear(duration: currentPeriod)
                            .repeatForever(autoreverses: false)) {
                rotation = 360
            }
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                    hueShift = 12
                }
            }
        }
        .onChange(of: state) { _, _ in
            // Re-key the rotation when the state flips so the period
            // transition (idle 18s → listening 6s → thinking 2s) reads
            // as an instant tempo change instead of a slow blend.
            withAnimation(.linear(duration: currentPeriod)
                            .repeatForever(autoreverses: false)) {
                rotation += 360
            }
        }
    }

    private var accessibilityState: String {
        switch state {
        case .idle:      return "Idle"
        case .listening: return "Listening"
        case .thinking:  return "Thinking"
        }
    }
}

// MARK: - EsangFlowerMark (doctrine §2.2 — ESANG AI signifier)
//
// Six tapered white petals radiating at 60° from a small center hub —
// this is the mark shown inside the BottomNav center orb in Figma 212:428
// (026 Off Duty) and 212:444 (010 Driver Home).

struct EsangFlowerMark: View {
    let diameter: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(Color.white)
                    .frame(width: diameter * 0.08, height: diameter * 0.46)
                    .offset(y: -diameter * 0.14)
                    .rotationEffect(.degrees(Double(i) * 60))
            }
            Circle()
                .fill(Color.white)
                .frame(width: diameter * 0.12, height: diameter * 0.12)
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - EsangParticleField (live particle system in the orb)
//
// Renders ~90 soft-white, additively-blended particles that drift with
// bounded kinetic motion inside the orb. Each particle has a velocity, a
// twinkle phase, and a soft halo; collisions with the circular boundary
// reflect velocity along the inward normal so the swarm stays permanently
// on-screen without pop-in. Drawn with SwiftUI Canvas + TimelineView so
// there is exactly one GPU pass per frame regardless of particle count.
//
// Why a class-in-@State for the engine:
//   - Physics needs per-frame mutation without rebuilding a struct array
//   - TimelineView re-evaluates the render closure every tick; the closure
//     steps the engine and draws — no state invalidation round-trip
//
// Accessibility: when `UIAccessibility.isReduceMotionEnabled` is true, the
// particles freeze at their seeded positions (still visible, no motion).
// This is honored by the driving TimelineView — if reduceMotion is on we
// still render but with a static schedule.

struct EsangParticleField: View {
    /// Motion mode the particle field is running in.
    ///
    ///   .idle        — slow reject-sample drift; the default resting swarm
    ///   .intensified — the "thinking" mode: faster bounce + punchier halos
    ///   .waving      — the "listening" mode: particles keep their kinetic
    ///                  drift but are RENDERED along a travelling sinusoid.
    ///                  The underlying physics keep updating so when we
    ///                  leave .waving they resume without a pop; only the
    ///                  displayed y-position is modulated.
    enum Motion: Equatable { case idle, intensified, waving }

    let diameter: CGFloat
    var motion: Motion = .idle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SwiftUI.State private var engine = ParticleEngine(count: 90)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas(opaque: false,
                   colorMode: .extendedLinear,
                   rendersAsynchronously: false) { context, size in

                if !reduceMotion {
                    engine.advance(to: t, intensified: motion == .intensified)
                }

                let w = size.width, h = size.height
                let cx = w / 2, cy = h / 2
                let R = min(w, h) / 2

                // Additive glow — each particle contributes light, stacking
                // brightness where they cluster.
                context.blendMode = .plusLighter

                // Listening-wave parameters. When motion == .waving we
                // overlay a travelling sinusoid on top of the physics
                // positions so the whole swarm reads as an audio
                // waveform flowing across the orb. The wave is expressed
                // in NORMALIZED coordinates (unit-disk space), then
                // scaled by R at paint time — keeps the amplitude
                // proportional across 56pt chat headers and 88pt
                // Driver-Home hero orbs.
                //
                //   amp   — peak vertical displacement as a fraction
                //           of the orb radius (0.18 ≈ ~8pt on a 88pt orb)
                //   k     — spatial frequency; ~2.4 produces ~1.2 full
                //           wavelengths visible across the orb
                //   omega — temporal frequency; 3.2 rad/s is fast enough
                //           to feel alive without looking frantic
                let waving = (motion == .waving) && !reduceMotion
                let amp: Double   = 0.18
                let k: Double     = 2.4
                let omega: Double = 3.2

                for p in engine.particles {
                    let waveOffset: Double = waving
                        ? amp * sin(k * p.x + omega * t + p.phase * 0.25)
                        : 0

                    let px = cx + p.x * R
                    let py = cy + (p.y + waveOffset) * R
                    let pr = max(p.r * R, 0.5)

                    // Twinkle cadence: listening beats slightly faster
                    // than idle so the brightness dance mirrors audio
                    // amplitude; thinking is the punchiest.
                    let twinkleRate: Double = {
                        switch motion {
                        case .idle:        return 1.7
                        case .waving:      return 2.2
                        case .intensified: return 2.6
                        }
                    }()
                    let twinkle = 0.55 + 0.45 * sin(p.phase + t * twinkleRate)

                    // In listening mode, particles near the wave crest
                    // brighten — this is what turns the drift into a
                    // visible moving waveform. Weighted by |wave offset|
                    // normalized to [0,1] so the peaks light up without
                    // blowing out the troughs.
                    let crestBoost: Double = waving
                        ? 1.0 + 0.85 * (abs(waveOffset) / amp)
                        : 1.0

                    // Outer halo — large, soft, low-alpha
                    let haloR = pr * 4.2
                    context.fill(
                        Circle().path(in: CGRect(x: px - haloR, y: py - haloR,
                                                 width: haloR * 2, height: haloR * 2)),
                        with: .color(.white.opacity(0.055 * twinkle * crestBoost))
                    )

                    // Mid glow
                    let midR = pr * 2.1
                    context.fill(
                        Circle().path(in: CGRect(x: px - midR, y: py - midR,
                                                 width: midR * 2, height: midR * 2)),
                        with: .color(.white.opacity(0.18 * twinkle * crestBoost))
                    )

                    // Bright core — clamp alpha at 1.0 so the crest boost
                    // can't produce an out-of-range color value.
                    context.fill(
                        Circle().path(in: CGRect(x: px - pr, y: py - pr,
                                                 width: pr * 2, height: pr * 2)),
                        with: .color(.white.opacity(min(0.92 * twinkle * crestBoost, 1.0)))
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

// MARK: - ParticleEngine (physics for EsangParticleField)

/// Reference-type physics store held in @State. Each call to `advance(to:)`
/// integrates one frame using a delta-time derived from the previous tick,
/// clamped to avoid runaway jumps when the view returns from the background.
final class ParticleEngine {

    struct Particle {
        var x: Double   // normalized in [-1, 1] (unit disk)
        var y: Double
        var vx: Double  // velocity in unit-disk coords per second
        var vy: Double
        var r: Double   // radius as fraction of the orb radius
        var phase: Double
    }

    private(set) var particles: [Particle]
    private var lastTime: Double = 0

    init(count: Int) {
        self.particles = (0..<count).map { _ in Self.seed() }
    }

    /// Reject-sample a start position inside a ~0.82 disk so particles
    /// spawn comfortably away from the wall.
    private static func seed() -> Particle {
        var x = 0.0, y = 0.0
        repeat {
            x = Double.random(in: -1...1)
            y = Double.random(in: -1...1)
        } while (x * x + y * y) > 0.82 * 0.82

        let speed = Double.random(in: 0.06...0.22)   // slow drift
        let angle = Double.random(in: 0...(2 * .pi))
        return Particle(
            x: x, y: y,
            vx: cos(angle) * speed,
            vy: sin(angle) * speed,
            r: Double.random(in: 0.012...0.030),
            phase: Double.random(in: 0...(2 * .pi))
        )
    }

    /// Integrate one frame. `intensified` scales speed for the thinking state.
    func advance(to time: Double, intensified: Bool) {
        // First tick: establish baseline, no integration yet.
        if lastTime == 0 { lastTime = time; return }

        // Clamp dt so returning from background doesn't fling particles.
        let rawDt = time - lastTime
        let dt = max(0.0, min(rawDt, 1.0 / 30.0))
        lastTime = time

        let speedScale = intensified ? 1.55 : 1.0

        for i in particles.indices {
            var p = particles[i]

            // Integrate position
            p.x += p.vx * dt * speedScale
            p.y += p.vy * dt * speedScale

            // Soft circular containment with reflect-and-project:
            //   - compute distance from center
            //   - if outside the soft boundary, reflect velocity along the
            //     outward normal (angle of incidence = angle of reflection)
            //   - project the position exactly onto the boundary so the
            //     particle never sits outside the orb for even one frame
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

                    // Tiny energy loss on bounce so the field doesn't slowly
                    // accrete velocity over time from numerical drift.
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

// MARK: - BottomNav (5 slots + center orb)

struct NavSlot: Identifiable {
    let id = UUID()
    let label: String
    let systemImage: String
    let isCurrent: Bool
    /// Tap handler — defaults to no-op so existing call-sites compile unchanged.
    var onTap: () -> Void = {}
}

struct BottomNav: View {
    let leading: [NavSlot]   // exactly 2
    let trailing: [NavSlot]  // exactly 2
    var orbState: OrbESang.State = .idle
    var onTapOrb: () -> Void = {}

    @Environment(\.palette) var palette
    @Environment(\.colorScheme) var scheme
    /// Driver-mode tap router — when injected (by ContentView at the
    /// Driver surface root), every slot and orb tap resolves through
    /// this handler instead of each NavSlot's local `onTap` closure.
    /// This fixes the wiring gap where all 14 `driverNavLeading_NNN()`
    /// helpers create NavSlots with the default no-op `onTap`, making
    /// the nav cosmetic.  When `nil` (e.g. #Preview blocks in isolation),
    /// the per-slot `onTap` still runs so previews remain unchanged.
    @Environment(\.driverNavHandler) var driverNavHandler
    /// Shipper-mode tap router. Mirror of `driverNavHandler` —
    /// same signature, same fallback ladder. Lets the shipper-side
    /// 200-210 BottomNav slots actually navigate (Home / Create
    /// Load / Loads / Me) instead of being cosmetic. Defined in
    /// `Views/Shipper/ShipperNavController.swift`.
    @Environment(\.shipperNavHandler) var shipperNavHandler
    /// Per-role tap routers for the other native chrome buckets the
    /// app ships (Carrier / Broker / Escort / Terminal / Admin /
    /// Compliance / Dispatch). Each one is injected by the matching
    /// surface in `RoleSurfaceRouter` so its bottom-nav slot taps
    /// fire through the role's `XxxNavDispatcher.handle(_:)` →
    /// `eusoXxxNavSwap` notification chain. Without these, a Carrier
    /// (or any non-driver/shipper) user tapped slots and nothing
    /// fired — the slot's local `s.onTap` defaulted to a no-op.
    @Environment(\.carrierNavHandler)    var carrierNavHandler
    @Environment(\.brokerNavHandler)     var brokerNavHandler
    @Environment(\.escortNavHandler)     var escortNavHandler
    @Environment(\.terminalNavHandler)   var terminalNavHandler
    @Environment(\.adminNavHandler)      var adminNavHandler
    @Environment(\.complianceNavHandler) var complianceNavHandler
    @Environment(\.dispatchNavHandler)   var dispatchNavHandler

    /// Resolves the first injected handler in priority order. Only
    /// one role's handler is ever in the env at a time (each surface
    /// injects exactly one), so this just returns the active one
    /// without ambiguity.
    private var activeNavHandler: ((String) -> Void)? {
        driverNavHandler
        ?? shipperNavHandler
        ?? carrierNavHandler
        ?? brokerNavHandler
        ?? escortNavHandler
        ?? terminalNavHandler
        ?? adminNavHandler
        ?? complianceNavHandler
        ?? dispatchNavHandler
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Glassmorphism plate: translucent material backdrop so the
            // page content blurs through, a subtle palette tint for depth,
            // and a gradient hairline along the top edge to catch light.
            // Shadow lifts the plate above the page surface below.
            BottomNav.topRoundedShape
                // Was .ultraThinMaterial — too transparent in light mode, so
                // payment-method rows scrolling under the pill stayed
                // crisp. .regularMaterial has noticeably stronger blur and
                // frosts the nav properly without making it opaque.
                .fill(.regularMaterial)
                .background(
                    BottomNav.topRoundedShape
                        .fill(palette.bgNav.opacity(scheme == .dark ? 0.55 : 0.70))
                )
                .overlay(
                    BottomNav.topRoundedShape
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(scheme == .dark ? 0.22 : 0.55),
                                    Color.white.opacity(0.02)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                // Gradient-glow shadow stack. SwiftUI's .shadow takes a
                // Color, not a gradient — so we layer two brand-tinted
                // shadows (blue biased left, magenta biased right) to read
                // as a blue→magenta halo, then add a very faint neutral
                // shadow underneath for subtle depth. In light mode the
                // solid black drop shadow from before (0.10 opacity) looked
                // dirty against cream backgrounds; the brand glow keeps the
                // nav lifted without the harsh halo.
                .shadow(color: Brand.blue.opacity(scheme == .dark ? 0.38 : 0.28),
                        radius: 20, x: -6, y: -2)
                .shadow(color: Brand.magenta.opacity(scheme == .dark ? 0.38 : 0.28),
                        radius: 20, x: 6, y: -2)
                .shadow(color: .black.opacity(scheme == .dark ? 0.22 : 0.06),
                        radius: 10, y: 4)

            HStack(spacing: 0) {
                ForEach(leading) { slot(for: $0) }
                // Center slot reserves an equal fifth of the width so the
                // flanking slots land at their Figma-true x-positions (20 %
                // | 40 % | 60 % | 80 %).  The orb itself is rendered on top
                // of the plate in a separate overlay so its lift shadow can
                // live above the plate without being clipped by the HStack.
                Color.clear
                    .frame(maxWidth: .infinity)
                ForEach(trailing) { slot(for: $0) }
            }
            .frame(height: Device.navHeight)

            // Elevated orb — floats ~40 % above the plate top, casts a
            // brand-colored glow onto the plate.
            // If a driver-mode handler is in the environment, route the
            // orb tap through it (opens ESANG coach sheet); otherwise
            // fall back to the call-site-provided `onTapOrb` closure so
            // isolated previews keep working.
            Button(action: {
                if let h = activeNavHandler {
                    h("esang")
                } else {
                    onTapOrb()
                }
            }) {
                OrbESang(state: orbState,
                         diameter: Device.navOrbDiameter)
            }
            .buttonStyle(.plain)
            .offset(y: -Device.navOrbLift)
            .frame(maxWidth: .infinity)
        }
        .frame(height: Device.navHeight, alignment: .top)
        // Floating-dock inset: lift the pill off the screen edges and
        // above the home-indicator strip so every rounded corner is
        // visible.
        .padding(.horizontal, Space.s4)
        .padding(.bottom, Device.safeBottom + Space.s2)
        // Bottom blur veil — rendered as a sibling layer underneath the
        // pill so it can ignore the bottom safe area independently and
        // extend all the way to the physical screen edge. When the veil
        // was attached as a `.background` modifier on the padded pill it
        // inherited the padded view's bottom edge (= safe-area boundary),
        // leaving a sliver of sharp page content visible beneath the
        // pill on Wallet / Eusoboards / Driver Home.
        .background(alignment: .bottom) {
            // Shift the veil down by safeBottom so its bottom edge reaches
            // the physical screen edge instead of stopping at the safe-area
            // boundary. `.background` bottom-aligns the veil to the padded
            // pill's frame (which ends at the safe-area boundary), so we
            // need an explicit offset to cover the home-indicator strip.
            bottomVeil
                .offset(y: Device.safeBottom)
                .ignoresSafeArea(.container, edges: .bottom)
        }
    }

    /// Veil backing the floating pill. Extends from the pill's top-fade
    /// region all the way through the home-indicator strip so every
    /// piece of page content that scrolls past the nav is blurred. Top
    /// edge softly fades into the page, bottom is fully opaque so the
    /// home indicator reads crisp.
    private var bottomVeil: some View {
        ZStack(alignment: .bottom) {
            // Heavy blur that clamps content visibility below the pill.
            // Upgraded from .ultraThinMaterial — ultraThin barely blurs
            // in light mode, which let crisp payment rows show through.
            Rectangle().fill(.regularMaterial)
            // Palette tint reinforces the nav surface without being
            // opaque — stops any remaining page color from bleeding.
            Rectangle().fill(palette.bgNav.opacity(scheme == .dark ? 0.65 : 0.80))
        }
        .frame(height: Device.navHeight + Device.safeBottom * 2 + Space.s4)
        .mask(
            LinearGradient(
                colors: [
                    Color.black.opacity(0),
                    Color.black.opacity(0.9),
                    Color.black
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
        .allowsHitTesting(false)
    }

    /// Shared shape used for the plate background so the corner radius
    /// stays in perfect agreement between fill, blur, and shadow.
    /// Rounded top corners plus a semicircular notch cut out of the top
    /// edge at the horizontal center, sized to cradle the floating orb.
    static var topRoundedShape: BottomNavPlateShape {
        BottomNavPlateShape(
            cornerRadius: Device.navCornerRadius,
            notchRadius: (Device.navOrbDiameter / 2) + 6  // 6pt breathing gap
        )
    }

    /// Nav slot — rounded-square gradient/glass button housing the tab's
    /// SF Symbol icon. Matches the ESANG coach sheet's close-button and
    /// keyboard "Done" button treatment so the whole app reads with one
    /// consistent button language. Active slot fills with the diagonal
    /// brand gradient; inactive slots use a translucent palette-tinted
    /// glass with a soft border hairline.
    ///
    /// Geometry tuned to Figma 212:428: 52×44 rounded rect (radius 14)
    /// with a 22pt icon centered — visually equivalent to the "Done" key
    /// the user referenced.
    @ViewBuilder
    private func slot(for s: NavSlot) -> some View {
        // Route through the env-injected driver-mode handler when present
        // (resolves the label into a controller action). Otherwise fall
        // through to the slot's local `onTap` — this keeps per-slot
        // closures (and the default no-op) working in isolation.
        Button(action: {
            if let h = activeNavHandler {
                h(s.label)
            } else {
                s.onTap()
            }
        }) {
            NavSlotButton(
                systemImage: s.systemImage,
                isCurrent: s.isCurrent
            )
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(s.label)
    }
}

/// Rounded-square icon button used inside `BottomNav`. Leans on Apple's
/// native Liquid Glass APIs (iOS 26+) so the look matches first-party
/// controls pixel-for-pixel: active state uses `.glassProminent` with a
/// brand-tinted fill; inactive state uses the plain `.glass` style.
/// Falls back to a hand-rolled glass card on pre-iOS-26 runtimes.
private struct NavSlotButton: View {
    let systemImage: String
    let isCurrent: Bool

    @Environment(\.palette) var palette
    @Environment(\.colorScheme) var scheme

    var body: some View {
        if #available(iOS 26.0, *) {
            liquidGlass
        } else {
            fallback
        }
    }

    // MARK: Native Liquid Glass (iOS 26+)
    //
    // Active slot: a brand blue→magenta gradient sits underneath the
    // Liquid Glass material so the glass reads as tinted by the full
    // EusoTrip gradient rather than a single flat color. `.glassEffect`
    // only accepts a `Color` tint, so we layer a filled shape below and
    // let the clear-glass specular highlights ride on top — this matches
    // how Apple's own tinted glass controls (Weather widgets, Now
    // Playing) are composed.
    @available(iOS 26.0, *)
    @ViewBuilder
    private var liquidGlass: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        ZStack {
            if isCurrent {
                // Gradient base — the "tint" the glass picks up.
                shape
                    .fill(LinearGradient.diagonal)
                    .frame(width: 52, height: 44)
                // Clear Liquid Glass pane on top: keeps Apple's native
                // highlights, refraction, and press interaction, while the
                // gradient shows through as the tint.
                Color.clear
                    .frame(width: 52, height: 44)
                    .glassEffect(.clear.interactive(), in: shape)
            } else {
                // Inactive: plain regular glass, untinted.
                Color.clear
                    .frame(width: 52, height: 44)
                    .glassEffect(.regular.interactive(), in: shape)
            }
            // Icon tint: selected → white (rides the gradient pill);
            // unselected → full brand gradient so the nav reads blue→magenta
            // in both Night and Afternoon instead of flattening to the
            // palette's textPrimary (black on white, too heavy in light).
            // §6.5 — every tab icon bounces on selection. SF Symbols'
            // native `.symbolEffect(.bounce, value:)` triggers when
            // `isCurrent` flips, paired with the standard selection
            // haptic so taps feel kinetic.
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(
                    isCurrent
                        ? AnyShapeStyle(Color.white)
                        : AnyShapeStyle(LinearGradient.diagonal)
                )
                .symbolEffect(.bounce, value: isCurrent)
        }
        .frame(width: 52, height: 44)
        .overlay {
            if isCurrent {
                // Gradient hairline border reinforces the identity so the
                // button still reads blue→magenta even on bright wallpapers.
                shape.stroke(LinearGradient.diagonal, lineWidth: 1.2)
                    .opacity(0.9)
            }
        }
        .shadow(
            color: isCurrent ? Brand.magenta.opacity(0.30) : .clear,
            radius: 10, y: 4
        )
    }

    // MARK: Pre-iOS 26 fallback
    @ViewBuilder
    private var fallback: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(isCurrent ? Color.white : palette.textPrimary)
            // §6.5 — bounce on selection (also on the pre-iOS-26
            // fallback path so older runtimes get the same kinetic
            // tab-bar feel).
            .symbolEffect(.bounce, value: isCurrent)
            .frame(width: 52, height: 44)
            .background {
                if isCurrent {
                    shape
                        .fill(LinearGradient.diagonal)
                        .overlay(
                            shape.stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.55),
                                             Color.white.opacity(0.05)],
                                    startPoint: .top, endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                        )
                        .shadow(color: Brand.blue.opacity(0.35),
                                radius: 10, y: 4)
                } else {
                    shape
                        .fill(.ultraThinMaterial)
                        .background(
                            shape.fill(palette.bgCard.opacity(scheme == .dark ? 0.45 : 0.70))
                        )
                        .overlay(
                            shape.strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(scheme == .dark ? 0.22 : 0.50),
                                             Color.white.opacity(0.02)],
                                    startPoint: .top, endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                        )
                }
            }
    }
}

// MARK: - BottomNavPlateShape (scalloped notch)

/// Shape for the BottomNav plate: rounded top corners with a semicircular
/// notch cut out of the top edge at the horizontal center, sized to cradle
/// the floating center orb. The notch dips downward (into the plate) so
/// the orb, which is offset upward, reads as seated in the cradle.
///
/// SwiftUI Path uses a Y-down coordinate system, so the parameter names
/// below refer to screen-visual directions. The `clockwise` flag on
/// `addArc` follows SwiftUI's documented "mathematical" convention (angles
/// increase counter-clockwise in math coords, which appears clockwise on
/// screen because Y is flipped); the comments below describe the on-screen
/// motion for each arc.
struct BottomNavPlateShape: Shape {
    let cornerRadius: CGFloat
    let notchRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        let cr = cornerRadius
        let nr = notchRadius

        // Start on the left edge, just below the top-leading rounded corner.
        p.move(to: CGPoint(x: 0, y: cr))

        // Top-leading corner: arc from the left edge up to the top edge.
        p.addArc(
            center: CGPoint(x: cr, y: cr),
            radius: cr,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        // Top edge: straight run to the notch's left lip.
        p.addLine(to: CGPoint(x: cx - nr, y: 0))

        // Notch: semicircular dip into the plate. Arc center sits on the
        // top edge (y = 0); the arc passes through (cx, nr) below it, which
        // is downward on screen because Y is flipped.
        p.addArc(
            center: CGPoint(x: cx, y: 0),
            radius: nr,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: true
        )

        // Top edge: straight run from the notch's right lip to the top-
        // trailing rounded corner.
        p.addLine(to: CGPoint(x: w - cr, y: 0))

        // Top-trailing corner: arc from the top edge down to the right edge.
        p.addArc(
            center: CGPoint(x: w - cr, y: cr),
            radius: cr,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )

        // Right edge down to the start of the bottom-trailing rounded
        // corner. The pill is fully rounded on all four corners so the
        // plate reads as a floating dock — matching iOS dock aesthetics.
        p.addLine(to: CGPoint(x: w, y: h - cr))

        // Bottom-trailing corner: arc from the right edge across to the
        // bottom edge. On screen this curls the corner inward toward the
        // center.
        p.addArc(
            center: CGPoint(x: w - cr, y: h - cr),
            radius: cr,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )

        // Bottom edge: straight run to the start of the bottom-leading
        // rounded corner.
        p.addLine(to: CGPoint(x: cr, y: h))

        // Bottom-leading corner: arc from the bottom edge up to the
        // left edge.
        p.addArc(
            center: CGPoint(x: cr, y: h - cr),
            radius: cr,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        // Close back up the left edge to the starting point (0, cr).
        p.closeSubpath()
        return p
    }
}

// MARK: - ActiveCard (gradient-rimmed)

struct ActiveCard<Content: View>: View {
    @Environment(\.palette) var palette
    @Environment(\.colorScheme) var scheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(Space.s5)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            )
            // Subtle gradient glow instead of a hard black drop. The old
            // .black@0.28 radius 10 looked dirty on cream/white surfaces in
            // light mode — it read as "grubby card" rather than "elevated
            // card". Replaced with a pair of brand-tinted shadows (blue on
            // the left, magenta on the right) at low opacity + small radius,
            // so cards lift cleanly without muddying the background.
            .shadow(color: Brand.blue.opacity(scheme == .dark ? 0.20 : 0.10),
                    radius: 6, x: -2, y: 2)
            .shadow(color: Brand.magenta.opacity(scheme == .dark ? 0.20 : 0.10),
                    radius: 6, x: 2, y: 2)
    }
}

// MARK: - MetricTile

struct MetricTile: View {
    let label: String
    let value: String
    var gradientNumeral: Bool = false
    /// Optional accent — when set, the tile renders a tinted soft fill
    /// + saturated stroke instead of the slate `bgCard` washout. Used
    /// by surfaces (HotZones detail, market chips) where every tile
    /// has a distinct semantic color (red=critical, green=safe, etc.)
    /// and the slate background was reading as "inactive / gray".
    var accent: Color? = nil
    @Environment(\.palette) var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label.uppercased())
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(accent.map { $0.opacity(0.85) } ?? palette.textTertiary)
            Group {
                if gradientNumeral {
                    Text(value).foregroundStyle(LinearGradient.diagonal)
                } else if let accent {
                    Text(value).foregroundStyle(accent)
                } else {
                    Text(value).foregroundStyle(palette.textPrimary)
                }
            }
            // The canonical EType.numeric (28pt) wrapped 3-up layouts on
            // iPhone widths ($2,44 / 0). Drop the tile font to 20pt and let
            // it auto-shrink further on narrower devices (iPhone SE, split
            // view) so numbers always sit on a single line, regardless of
            // rail (2-up hero · 3-up wallet · 4-up comparison).
            .font(.system(size: 20, weight: .semibold, design: .default))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Group {
                if let accent {
                    accent.opacity(0.10)
                } else {
                    palette.bgCard
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(
                    accent.map { $0.opacity(0.5) } ?? palette.borderFaint,
                    lineWidth: accent == nil ? 1 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }
}

// MARK: - StatusPill

struct StatusPill: View {
    enum Kind { case success, warning, danger, info, hazmat, neutral }
    let text: String
    let kind: Kind
    @Environment(\.palette) var palette

    private var color: Color {
        switch kind {
        case .success: return Brand.success
        case .warning: return Brand.warning
        case .danger:  return Brand.danger
        case .info:    return Brand.info
        case .hazmat:  return Brand.hazmat
        case .neutral: return palette.textSecondary
        }
    }
    private var tint: Color {
        switch kind {
        case .success: return palette.tintSuccess
        case .warning: return palette.tintWarning
        case .danger:  return palette.tintDanger
        case .info:    return palette.tintInfo
        case .hazmat:  return palette.tintHazmat
        case .neutral: return palette.tintNeutral
        }
    }

    var body: some View {
        Text(text.uppercased())
            .font(EType.micro).tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(tint))
    }
}

// MARK: - CTA Button (with iridescent press hue-shift)

struct CTAButton: View {
    let title: String
    var action: () -> Void = {}
    /// Optional trailing icon — used by lifecycle screens that need
    /// "Submit DVIR →" patterns. When nil, the button renders title-
    /// only (the original signature). When non-nil, the icon paints
    /// to the right of the title at the same weight + brightness.
    var trailingIcon: String? = nil
    /// Optional leading icon — used by mode-switch buttons like
    /// "Off-duty" with a moon glyph. Mirrors `trailingIcon` semantics.
    var leadingIcon: String? = nil
    /// Optional caption rendered under the title at small caps. Used
    /// by lifecycle screens that pair a CTA with route/dispatch
    /// context ("Confirm 15-min notify" / "→ dispatch · 38 min ETA").
    var subtitle: String? = nil
    /// When true the button renders at 60% opacity + ignores taps.
    /// Replaces the inline `.opacity(isLoading ? 0.6 : 1).disabled(...)`
    /// that every lifecycle screen used to ship.
    var isLoading: Bool = false

    @SwiftUI.State private var pressed = false
    /// Bumps every primary CTA tap to drive `.sensoryFeedback(.success)`
    /// per the 2026 UX motion doc §6.10. Increment is fired in the
    /// button action so the haptic pairs with the visible press.
    @SwiftUI.State private var tapCount: Int = 0

    /// Web-platform parity: rounded rectangle, not oval.
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
    }

    var body: some View {
        Button(action: {
            guard !isLoading else { return }
            tapCount &+= 1
            action()
        }) {
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    if let leadingIcon {
                        Image(systemName: leadingIcon)
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(title)
                        .font(EType.title)
                    if let trailingIcon {
                        Image(systemName: trailingIcon)
                            .font(.system(size: 13, weight: .bold))
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.8)
                        .opacity(0.85)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.vertical, 4)
        }
        .background(
            LinearGradient.primary
                .hueRotation(.degrees(pressed ? -8 : 0))
                .saturation(pressed ? 1.08 : 1.0)
        )
        .clipShape(shape)
        .scaleEffect(pressed ? 0.985 : 1.0)
        .opacity(isLoading ? 0.6 : 1.0)
        .animation(.easeOut(duration: 0.12), value: pressed)
        .animation(.easeOut(duration: 0.18), value: isLoading)
        // §6.10 — Success haptic on every primary CTA tap. Pairs with
        // the gradient ring bloom (rendered by the caller's success
        // toast) and the §B.4 press scale above. `.success` reads as
        // a confident "you did the thing" thump rather than the
        // selection chirp `.sensoryFeedback(.selection, …)` produces.
        .sensoryFeedback(.success, trigger: tapCount)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isLoading { pressed = true } }
                .onEnded   { _ in pressed = false }
        )
        .disabled(isLoading)
    }
}

// MARK: - IridescentHairline

struct IridescentHairline: View {
    @Environment(\.palette) var palette
    var body: some View {
        palette.iridescentHairline
            .frame(height: 1)
    }
}

// MARK: - Shell (the device frame wrapper — every Screen lives inside one)

struct Shell<Content: View, Nav: View>: View {
    let theme: Theme.Palette
    @ViewBuilder var content: () -> Content
    @ViewBuilder var nav: () -> Nav

    var body: some View {
        // The app runs inside a real device (or the Simulator's own chrome),
        // so Shell must render edge-to-edge here. Previously Shell drew its
        // own fake iPhone bezel — cornerRadius 55 clip + 10pt strokeBorder +
        // a fixed Device.width×Device.height frame — which looked right in
        // SwiftUI previews but produced a "screen inside a screen" effect
        // on-device AND caused BottomNav to anchor at a different vertical
        // position than the pane tabs (Trips/Wallet/Me) use in
        // `paneWithNav`, which wrap their content in a full-screen ZStack.
        // Dropping the bezel here unifies the anchor so BottomNav doesn't
        // jump when the user switches between Home and the panes.
        ZStack(alignment: .bottom) {
            theme.bgPrimary
                .ignoresSafeArea()
            ScrollView(.vertical, showsIndicators: false) {
                content()
                Color.clear.frame(height: Device.navHeight + Device.safeBottom + Space.s4)
            }
            nav()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.palette, theme)
    }
}

// MARK: - Palette semantic-color convenience
//
// Several screens reference semantic colors and an elevated surface through
// the palette (e.g. `palette.success`, `palette.bgElev`). These thin
// conveniences map to the canonical Brand and background tokens so callers
// don't have to remember whether a color lives on Brand vs. Palette.
extension Theme.Palette {
    var success: Color { Brand.success }
    var warning: Color { Brand.warning }
    var danger:  Color { Brand.danger  }
    var info:    Color { Brand.info    }

    /// Slightly elevated surface — used for inline banners (e.g. the
    /// turn-by-turn header) that should read one step above the page
    /// background but below a full card.
    var bgElev: Color { bgSecondary }
}

// MARK: - EusoCard surface
//
// Kills the generic "gray rounded rectangle on dark page" look that made
// the app read like every other AI-assisted design. Two changes only:
//   1. The card fill matches the page skin exactly — near-black in dark
//      mode, pure matte white in light mode. No gray, no offwhite, no
//      gradient-fill. The card "melts into" the surface it sits on.
//   2. The only decorative element is the full iridescent blue→magenta
//      gradient outline the user already liked on the Hot Zones card.
//      Its weight and glow scale with intensity.
//
// Usage:
//     .eusoCard()                       // standard radius + gradient outline
//     .eusoCard(radius: Radius.xl)      // bigger feature cards
//     .eusoCard(intensity: .feature)    // thicker gradient + stronger glow
//     .eusoCard(intensity: .whisper)    // tight nested rows
//

enum EusoCardIntensity {
    case whisper   // nested / secondary groups
    case standard  // default
    case feature   // hero surfaces (Hot Zones, active load, etc.)
}

extension Color {
    /// Pure-black card skin for dark mode — matches Theme.dark.bgPage so
    /// the card dissolves into the page and the gradient outline is the
    /// only thing drawing the shape. If you want the card to sit *above*
    /// the page, reach for a different modifier; the whole point of this
    /// one is "same skin, gradient outline."
    static let eusoCardFillDark = Color(hex: 0x030309)
    /// Pure matte white — no cream, no offwhite. The old 0xF7F8FB read
    /// as "dirty white" against pure white page elements, so this is
    /// intentionally #FFFFFF.
    static let eusoCardFillLight = Color.white
}

struct EusoCardModifier: ViewModifier {
    let radius: CGFloat
    let intensity: EusoCardIntensity
    @Environment(\.palette) private var palette

    private var isDark: Bool {
        palette.bgPage == Theme.dark.bgPage
    }

    /// Intensity of the iridescent outline — how present the blue→magenta
    /// gradient reads. Whispers are subtle (list rows), features are
    /// full-strength (Hot Zones-grade hero cards).
    private var outlineOpacity: Double {
        switch intensity {
        case .whisper:  return 0.35
        case .standard: return 0.70
        case .feature:  return 1.00
        }
    }

    private var outlineWeight: CGFloat {
        switch intensity {
        case .whisper:  return 1.0
        case .standard: return 1.25
        case .feature:  return 1.75
        }
    }

    /// Outer ambient glow — lifts the card off the page in dark mode,
    /// stays invisible in light mode (a white card with a colored halo
    /// reads as a cheap "dirty drop shadow").
    private var outerGlowRadius: CGFloat {
        switch intensity {
        case .whisper:  return 0
        case .standard: return 10
        case .feature:  return 18
        }
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let outline = LinearGradient(
            colors: [
                Brand.blue.opacity(outlineOpacity),
                Brand.magenta.opacity(outlineOpacity)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        content
            // Base fill — same color as the surrounding page so the card
            // skin matches. No gradient, no gray.
            .background(
                shape.fill(isDark ? Color.eusoCardFillDark : Color.eusoCardFillLight)
            )
            // The signature iridescent gradient outline — the only
            // decorative element on the card.
            .overlay(
                shape.strokeBorder(outline, lineWidth: outlineWeight)
            )
            // Ambient blue/magenta glow beneath the card in dark mode
            // only. Adds the same "neon-lifted" quality the Hot Zones
            // card has without painting anything onto the card itself.
            .background(
                Group {
                    if isDark && intensity != .whisper {
                        shape
                            .stroke(outline, lineWidth: outlineWeight)
                            .blur(radius: outerGlowRadius)
                            .opacity(0.75)
                            .allowsHitTesting(false)
                    }
                }
            )
            .compositingGroup()
            .clipShape(shape)
    }
}

extension View {
    /// Primary card surface. In dark mode: card skin matches the page
    /// (pure near-black) and the only decoration is the iridescent
    /// blue→magenta gradient outline + glow. In light mode: matte
    /// white, no offwhite / cream, same gradient outline.
    func eusoCard(
        radius: CGFloat = Radius.lg,
        intensity: EusoCardIntensity = .standard
    ) -> some View {
        modifier(EusoCardModifier(radius: radius, intensity: intensity))
    }

    /// Row-level variant — whisper intensity, used for nested rows
    /// inside an already-carded container so they pick up the outline
    /// without compounding glow halos.
    func eusoRow(radius: CGFloat = Radius.md) -> some View {
        modifier(EusoCardModifier(radius: radius, intensity: .whisper))
    }
}

