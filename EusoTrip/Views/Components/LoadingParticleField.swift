//
//  LoadingParticleField.swift
//  EusoTrip — Ambient particle field used in place of diagnostic loading text.
//
//  Previously the Driver Home loading state showed plumbing-ish strings like
//  "Contacting EusoTrip tRPC · loads.search · hos.getStatus" — useful for
//  debugging, hostile in production. This view renders a thick cloud of
//  brand-color fireflies drifting through the card, so the loading moment
//  reads as ambient EusoTrip-identity motion instead of server jargon.
//
//  Visual language is the same five-color palette the ESANG dissolve uses
//  (EsangParticleBurst.darkPalette), at reduced saturation and with a slow
//  float motion instead of a convergence motion. The effect is:
//    • dense firefly field (default 120 motes)
//    • each mote drifts on a unique Lissajous-like path
//    • opacity pulses on a per-mote phase so the field "breathes"
//    • no text — the caller's card provides the semantic context
//
//  Callers can optionally supply a `caption` string shown muted + centered
//  under the field — used on full-screen loaders where a non-leaky status
//  line is still helpful ("Loading…" or "One moment"). The Driver Home
//  loader passes nil.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Public view

struct LoadingParticleField: View {

    /// How many particles to render. 120 is tuned for a ~320×200 card —
    /// dense enough to read as a cloud, cheap enough for 60fps on A15+.
    var count: Int = 120
    /// Height of the field. Callers that want the classic "card" shape
    /// pass a bounded height; full-screen users pass `.infinity`.
    var height: CGFloat = 140
    /// Optional friendly status line shown centered on top of the field.
    /// Keep it short + human: "Loading…", "One moment", nil.
    var caption: String? = nil

    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            ParticleCanvas(count: count)
                .frame(height: height == .infinity ? nil : height)
                .frame(maxWidth: .infinity,
                       maxHeight: height == .infinity ? .infinity : height)
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary.opacity(0.9))
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s2)
                    .background(
                        Capsule().fill(palette.bgCardSoft.opacity(0.6))
                    )
            }
        }
        .accessibilityElement()
        .accessibilityLabel(caption ?? "Loading")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Canvas implementation

/// `TimelineView`-driven Canvas that animates N particles in a drift pattern.
/// Particles are seeded once per mount (via `.onAppear` on the backing state)
/// and then re-rendered every animation frame with positions derived from
/// time, so memory and CPU stay flat regardless of duration.
private struct ParticleCanvas: View {

    let count: Int

    /// Particle kinematics. Each particle has:
    ///   • a home position inside the unit rect [0,1]²
    ///   • two amplitudes (ax, ay) describing how far it drifts from home
    ///   • two frequencies (fx, fy) that set the cycle time
    ///   • a phase offset so particles don't all crest at the same moment
    ///   • a size, color, and opacity range
    fileprivate struct Mote {
        var hx: Double
        var hy: Double
        var ax: Double
        var ay: Double
        var fx: Double
        var fy: Double
        var px: Double     // phase x
        var py: Double     // phase y
        var pulse: Double  // phase for opacity pulse
        var baseSize: Double
        var color: Color
    }

    @State private var motes: [Mote] = []
    @State private var startedAt: Date = .now

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            Canvas { ctx, size in
                let t = context.date.timeIntervalSince(startedAt)
                for m in motes {
                    // Drift position from home along two sinusoids — the
                    // ratio of fx/fy matters more than absolute values,
                    // a slight mismatch produces quasi-elliptical paths.
                    let x = (m.hx + m.ax * sin(t * m.fx + m.px)) * size.width
                    let y = (m.hy + m.ay * cos(t * m.fy + m.py)) * size.height

                    // Pulse opacity so the field reads as a "breathing"
                    // constellation — each mote has its own phase so the
                    // whole field never darkens at once.
                    let pulse = 0.55 + 0.35 * sin(t * 0.8 + m.pulse)
                    let alpha = max(0.18, min(0.95, pulse))

                    let r = m.baseSize
                    // Halo — soft outer glow at ~3× radius, 35% alpha.
                    let haloR = r * 3.0
                    ctx.fill(
                        Path(ellipseIn: CGRect(
                            x: x - haloR, y: y - haloR,
                            width: haloR * 2, height: haloR * 2
                        )),
                        with: .color(m.color.opacity(alpha * 0.28))
                    )
                    // Mid — warmer ring at 1.6× radius, 55% alpha.
                    let midR = r * 1.6
                    ctx.fill(
                        Path(ellipseIn: CGRect(
                            x: x - midR, y: y - midR,
                            width: midR * 2, height: midR * 2
                        )),
                        with: .color(m.color.opacity(alpha * 0.5))
                    )
                    // Core.
                    ctx.fill(
                        Path(ellipseIn: CGRect(
                            x: x - r, y: y - r,
                            width: r * 2, height: r * 2
                        )),
                        with: .color(m.color.opacity(alpha))
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            if motes.isEmpty { motes = Self.seed(count: count) }
            startedAt = .now
        }
    }

    // MARK: Seeding

    /// Brand-parity palette — same hues the ESANG dissolve uses, so the
    /// loading state shares visual DNA with the ESANG orb moment.
    private static let palette: [Color] = [
        Color(.sRGB, red: 0x14 / 255.0, green: 0x73 / 255.0, blue: 0xFF / 255.0, opacity: 1), // brand blue
        Color(.sRGB, red: 0xBE / 255.0, green: 0x01 / 255.0, blue: 0xFF / 255.0, opacity: 1), // brand magenta
        Color(.sRGB, red: 0x8B / 255.0, green: 0x5C / 255.0, blue: 0xF6 / 255.0, opacity: 1),
        Color(.sRGB, red: 0x63 / 255.0, green: 0x66 / 255.0, blue: 0xF1 / 255.0, opacity: 1),
        Color(.sRGB, red: 0xA8 / 255.0, green: 0x55 / 255.0, blue: 0xF7 / 255.0, opacity: 1),
    ]

    fileprivate static func seed(count: Int) -> [Mote] {
        (0..<count).map { _ in
            Mote(
                hx: .random(in: 0.05...0.95),
                hy: .random(in: 0.08...0.92),
                ax: .random(in: 0.04...0.18),
                ay: .random(in: 0.04...0.14),
                fx: .random(in: 0.35...1.25),
                fy: .random(in: 0.30...1.10),
                px: .random(in: 0...(.pi * 2)),
                py: .random(in: 0...(.pi * 2)),
                pulse: .random(in: 0...(.pi * 2)),
                baseSize: .random(in: 0.9...2.1),
                color: palette.randomElement() ?? palette[0]
            )
        }
    }
}

// MARK: - Previews

#Preview("Loading field · dark") {
    ZStack {
        Color.black.ignoresSafeArea()
        LoadingParticleField(count: 160, height: 220)
            .padding(24)
    }
}

#Preview("Loading field · with caption") {
    ZStack {
        Color.black.ignoresSafeArea()
        LoadingParticleField(count: 120, height: 180, caption: "Loading…")
            .padding(24)
    }
}
