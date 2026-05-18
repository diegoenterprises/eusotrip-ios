//
//  eSangParticleBurst.swift
//  EusoTrip — pixel-faithful port of the web ESANG chat-sheet dissolve.
//
//  WEB REFERENCE (dark mode): eSangFloatingButton.tsx
//    - 30 particles spawned from the chat widget's visual bounds
//    - Each particle picks from a 5-color gradient palette:
//        [#1473FF, #BE01FF, #8B5CF6, #6366F1, #A855F7]
//    - Solid color core (3–10pt) + CSS box-shadow glow (size*2 blur)
//    - Duration 0.35–0.7s per particle, delay 0–0.25s stagger
//    - Easing: cubic-bezier(0.6, 0, 0.2, 1)
//    - End state: opacity 0, scale 0, position at the button anchor
//    - Total animation window: ~650ms
//
//  This view runs in lock-step with the chat-sheet's own in-place scale+blur
//  collapse (see DriverHome `dissolveeSang`). The sheet does NOT translate
//  toward the orb — it shrinks in place while these particles carry the
//  visual motion toward the orb, exactly like the web twin.
//

import SwiftUI

struct eSangParticleBurst: View {
    /// The rectangle (in the same coordinate space as `anchor`) from which
    /// particles are seeded — the chat sheet's visible bounds at the
    /// moment the dissolve starts.
    let sourceRect: CGRect
    /// The convergence point — the center of the nav orb.
    let anchor: CGPoint
    /// Total dissolve window. Matches the web's 0.5s sheet collapse plus
    /// 0.15s tail for the last staggered particles to land.
    var duration: Double = 0.65
    /// Called after the animation finishes.
    let onDone: () -> Void

    @State private var particles: [Particle] = []
    @State private var startedAt: Date = .now

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            Canvas { ctx, _ in
                let elapsed = context.date.timeIntervalSince(startedAt)

                for p in particles {
                    // Each particle has its own delay + per-particle
                    // duration, matching the web's `delay` + `dur`.
                    let local = (elapsed - p.delay) / p.duration
                    if local <= 0 { continue }
                    let clamped = min(1, local)
                    let eased = eSangParticleBurst.cubicBezier(
                        clamped, c1x: 0.6, c1y: 0, c2x: 0.2, c2y: 1
                    )

                    // Position: spawn → anchor.
                    let x = p.origin.x + (anchor.x - p.origin.x) * eased
                    let y = p.origin.y + (anchor.y - p.origin.y) * eased

                    // Web uses `opacity: 0, scale: 0` as the end state —
                    // both driven by the same eased progress. Particles
                    // stay bright almost all the way, then fade+shrink at
                    // the arrival. A gentle power curve models this well.
                    let life = 1 - eased
                    let alpha = max(0, min(1, pow(life, 0.9)))
                    let r = p.size * max(0.08, life)   // shrink to 0 at end

                    if alpha <= 0.02 || r <= 0.15 { continue }

                    let core = p.color
                    // CSS box-shadow `0 0 ${size*2}px ${color}` → radial
                    // gradient halo ~3× the core radius.
                    let haloR = r * 3.0
                    ctx.fill(
                        Path(ellipseIn: CGRect(
                            x: x - haloR, y: y - haloR,
                            width: haloR * 2, height: haloR * 2
                        )),
                        with: .color(core.opacity(alpha * 0.35))
                    )
                    // Inner hot halo — adds firefly brightness.
                    let midR = r * 1.7
                    ctx.fill(
                        Path(ellipseIn: CGRect(
                            x: x - midR, y: y - midR,
                            width: midR * 2, height: midR * 2
                        )),
                        with: .color(core.opacity(alpha * 0.55))
                    )
                    // Solid color core.
                    ctx.fill(
                        Path(ellipseIn: CGRect(
                            x: x - r, y: y - r,
                            width: r * 2, height: r * 2
                        )),
                        with: .color(core.opacity(alpha))
                    )
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            // Fallback seed rect guards against a zero frame (e.g. a
            // first-render race before the sheet has measured itself).
            let seedRect: CGRect = sourceRect.width > 0 && sourceRect.height > 0
                ? sourceRect
                : CGRect(x: 0, y: 60, width: 440, height: 820)
            particles = eSangParticleBurst.seed(in: seedRect)
            startedAt = .now
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            #endif
            Task {
                try? await Task.sleep(nanoseconds: UInt64((duration + 0.05) * 1_000_000_000))
                await MainActor.run { onDone() }
            }
        }
    }

    // MARK: - Cubic bezier easing (matches the web's [0.6, 0, 0.2, 1])

    /// Newton-step approximation of a CSS cubic-bezier easing curve.
    fileprivate static func cubicBezier(_ t: Double,
                                        c1x: Double, c1y: Double,
                                        c2x: Double, c2y: Double) -> Double {
        func bezier(_ u: Double, _ a: Double, _ b: Double) -> Double {
            let oneMinusU = 1 - u
            return 3 * oneMinusU * oneMinusU * u * a
                + 3 * oneMinusU * u * u * b
                + u * u * u
        }
        func bezierDeriv(_ u: Double, _ a: Double, _ b: Double) -> Double {
            let oneMinusU = 1 - u
            return 3 * oneMinusU * oneMinusU * a
                + 6 * oneMinusU * u * (b - a)
                + 3 * u * u * (1 - b)
        }
        var u = t
        for _ in 0..<6 {
            let x = bezier(u, c1x, c2x) - t
            let dx = bezierDeriv(u, c1x, c2x)
            if abs(dx) < 1e-6 { break }
            u -= x / dx
            u = max(0, min(1, u))
        }
        return bezier(u, c1y, c2y)
    }

    // MARK: - Seeding

    fileprivate struct Particle {
        let origin: CGPoint
        let size: Double      // core radius (web's diameter / 2)
        let color: Color
        let delay: Double     // seconds
        let duration: Double  // seconds
    }

    /// Dark-mode palette (matches eSangFloatingButton.tsx exactly).
    static let darkPalette: [Color] = [
        Color(.sRGB, red: 0x14 / 255.0, green: 0x73 / 255.0, blue: 0xFF / 255.0, opacity: 1),
        Color(.sRGB, red: 0xBE / 255.0, green: 0x01 / 255.0, blue: 0xFF / 255.0, opacity: 1),
        Color(.sRGB, red: 0x8B / 255.0, green: 0x5C / 255.0, blue: 0xF6 / 255.0, opacity: 1),
        Color(.sRGB, red: 0x63 / 255.0, green: 0x66 / 255.0, blue: 0xF1 / 255.0, opacity: 1),
        Color(.sRGB, red: 0xA8 / 255.0, green: 0x55 / 255.0, blue: 0xF7 / 255.0, opacity: 1),
    ]

    fileprivate static func seed(in rect: CGRect) -> [Particle] {
        // 30 particles — matches web exactly. Each carries a 3× glow halo
        // so the cloud still reads as dense at phone scale.
        (0..<30).map { _ in
            let x = rect.minX + CGFloat.random(in: 0...1) * rect.width
            let y = rect.minY + CGFloat.random(in: 0...1) * rect.height
            // Web: size 3 + random(0..7) → 3–10pt core diameter.
            let size = (3.0 + Double.random(in: 0...7.0)) / 2.0
            let delay = Double.random(in: 0...0.25)
            let dur = 0.35 + Double.random(in: 0...0.35)
            let color = darkPalette.randomElement() ?? darkPalette[0]
            return Particle(
                origin: CGPoint(x: x, y: y),
                size: size,
                color: color,
                delay: delay,
                duration: dur
            )
        }
    }
}

#Preview("Dissolve") {
    ZStack {
        Color.black.ignoresSafeArea()
        eSangParticleBurst(
            sourceRect: CGRect(x: 40, y: 200, width: 320, height: 480),
            anchor: CGPoint(x: 220, y: 800),
            onDone: {}
        )
    }
}
