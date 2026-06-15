//
//  PostLoadCelebration.swift
//  EusoTrip — Shipper · Post-a-Load · shared celebration + bespoke glyphs.
//
//  F-ANIMATION (2026-06-14) — founder ask: "there needs to be a bespoke
//  professional super-high-quality animation letting the user know it has
//  been posted followed by a back to the beginning of a fresh new load
//  screen."
//
//  This file holds the full-bleed "Load posted" celebration overlay used
//  by the 204 single-screen post-load surface, plus the small bespoke
//  glyph shapes (check / close / warning / send) that replace the SF
//  Symbols the success/error path previously used. Everything is drawn
//  with SwiftUI Canvas / Path on the house design system — ZERO SF
//  Symbols, ZERO emoji, ZERO third-party Lottie. Reduce-Motion-safe.
//
//  The 250-259 push-nav wizard reaches the equivalent celebration via the
//  dedicated `PostLoadSuccessScreen` (254_PostLoadSuccess.swift); both
//  share the same visual language.
//

import SwiftUI

// MARK: - Full-bleed celebration overlay (204 surface)

/// Brand-native "Load posted" cover. Auto-dismisses after the sequence
/// settles, or immediately on the CTA tap — either way it calls
/// `onContinue`, which the host uses to reset the wizard to a fresh
/// Step-1. Drawn entirely with shapes/Canvas; Reduce Motion shows the
/// settled frame and a slightly longer auto-dismiss so the copy is
/// readable without motion.
struct PostLoadPostedCelebration: View {
    let loadNumber: String
    var onContinue: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var celebrate = false
    @State private var checkDraw: CGFloat = 0
    @State private var copySettled = false
    @State private var didFinish = false

    var body: some View {
        ZStack {
            // Scrim — deep brand-tinted veil over the wizard chrome.
            Rectangle()
                .fill(palette.bgPage.opacity(0.94))
                .ignoresSafeArea()
                .overlay(
                    RadialGradient(
                        colors: [Brand.magenta.opacity(0.16), .clear],
                        center: .center, startRadius: 0, endRadius: 360
                    )
                    .ignoresSafeArea()
                )

            VStack(spacing: Space.s6) {
                Spacer(minLength: 0)

                ZStack {
                    PostLoadAuroraBurstHalo(progress: celebrate ? 1 : 0,
                                            reduceMotion: reduceMotion)
                        .frame(width: 260, height: 260)
                    PostLoadPostedCheck(draw: checkDraw)
                        .frame(width: 124, height: 124)
                }
                .frame(height: 264)

                VStack(spacing: Space.s3) {
                    Text("Posted to the marketplace")
                        .font(EType.h1)
                        .foregroundStyle(palette.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(loadNumber.isEmpty ? "—" : loadNumber)
                        .font(EType.mono(.caption))
                        .tracking(0.8)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, 6)
                        .background(Capsule(style: .continuous).fill(palette.bgCardSoft))
                        .overlay(Capsule(style: .continuous)
                            .strokeBorder(LinearGradient.diagonal, lineWidth: 1))

                    HStack(spacing: 6) {
                        PostLoadPulseDot()
                        Text("Now live for carriers in this lane")
                            .font(EType.body)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .padding(.top, 2)
                }
                .opacity(copySettled ? 1 : 0)
                .offset(y: copySettled ? 0 : 12)
                .padding(.horizontal, Space.s6)

                Spacer(minLength: 0)

                Button(action: finish) {
                    Text("Post another load")
                        .font(EType.bodyStrong)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(LinearGradient.primary)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .opacity(copySettled ? 1 : 0)
                .padding(.horizontal, Space.s5)
                .padding(.bottom, Space.s7)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Load posted to the marketplace. \(loadNumber). Now live for carriers in this lane.")
        .accessibilityAddTraits(.isModal)
        .onAppear(perform: run)
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onContinue()
    }

    private func run() {
        if reduceMotion {
            celebrate = true; checkDraw = 1; copySettled = true
            // Give a Reduce-Motion user generous time to read before
            // auto-returning to a fresh load screen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) { finish() }
            return
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { checkDraw = 1 }
        withAnimation(.easeOut(duration: 1.05)) { celebrate = true }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.85).delay(0.2)) {
            copySettled = true
        }
        // Auto-return to a fresh Step-1 after the celebration has had its
        // moment. The CTA lets an impatient shipper skip ahead.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { finish() }
    }
}

// MARK: - Aurora burst halo (shared)

/// Concentric brand-gradient rings expanding + fading outward over a
/// slowly-rotating conic shimmer floor, with a one-shot radial spark fan.
/// `progress` 0→1 drives the burst; the shimmer breathes via TimelineView.
/// Reduce Motion renders only the faint static floor.
struct PostLoadAuroraBurstHalo: View {
    var progress: CGFloat
    var reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { tl in
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                let floorR = size.width * 0.30

                // Conic shimmer floor.
                let shimmer = GraphicsContext.Shading.conicGradient(
                    Gradient(colors: [Brand.blue, Brand.magenta,
                                      WeatherV3.auroraC, Brand.blue]),
                    center: c,
                    angle: .degrees((t * 22).truncatingRemainder(dividingBy: 360))
                )
                var floor = Path()
                floor.addEllipse(in: CGRect(x: c.x - floorR, y: c.y - floorR,
                                            width: floorR * 2, height: floorR * 2))
                ctx.opacity = reduceMotion ? 0.18 : (0.14 + 0.06 * (0.5 + 0.5 * sin(t * 1.4)))
                ctx.fill(floor, with: shimmer)
                ctx.opacity = 1

                guard !reduceMotion else { return }

                // Expanding burst rings.
                for i in 0..<3 {
                    let phase = max(0, min(1, progress - CGFloat(i) * 0.12))
                    guard phase > 0 else { continue }
                    let r = floorR + phase * size.width * 0.34
                    let alpha = (1 - phase) * 0.55
                    var ring = Path()
                    ring.addEllipse(in: CGRect(x: c.x - r, y: c.y - r,
                                               width: r * 2, height: r * 2))
                    ctx.stroke(ring,
                               with: .linearGradient(
                                Gradient(colors: [Brand.blue.opacity(alpha),
                                                  Brand.magenta.opacity(alpha)]),
                                startPoint: CGPoint(x: c.x - r, y: c.y - r),
                                endPoint: CGPoint(x: c.x + r, y: c.y + r)),
                               lineWidth: 2.2 * (1 - phase) + 0.6)
                }

                // One-shot radial spark fan.
                let rayPhase = max(0, min(1, progress))
                if rayPhase > 0.05 {
                    let rays = 14
                    let inner = floorR * (0.9 + 0.5 * rayPhase)
                    let outer = inner + size.width * 0.10 * (1 - rayPhase) + 6
                    let alpha = (1 - rayPhase) * 0.7
                    for k in 0..<rays {
                        let a = (Double(k) / Double(rays)) * 2 * .pi + t * 0.2
                        let p0 = CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner)
                        let p1 = CGPoint(x: c.x + cos(a) * outer, y: c.y + sin(a) * outer)
                        var ray = Path()
                        ray.move(to: p0); ray.addLine(to: p1)
                        ctx.stroke(ray,
                                   with: .color((k % 2 == 0 ? Brand.magenta : Brand.blue).opacity(alpha)),
                                   style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                }
            }
        }
    }
}

// MARK: - Posted check (shared)

/// Brand-gradient disc that springs in (`draw` scales it) with a glowing
/// rim and a self-stroking route-pulse check. Pure shapes; no SF Symbol.
struct PostLoadPostedCheck: View {
    var draw: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(LinearGradient.diagonal, lineWidth: 2)
                .opacity(0.35)
                .scaleEffect(0.78 + 0.22 * draw)
            Circle()
                .fill(LinearGradient.diagonal)
                .scaleEffect(0.4 + 0.6 * draw)
                .shadow(color: Brand.magenta.opacity(0.45 * draw), radius: 18, y: 6)
            Circle()
                .fill(RadialGradient(
                    colors: [.white.opacity(0.55), .white.opacity(0)],
                    center: .init(x: 0.34, y: 0.28),
                    startRadius: 0, endRadius: 70))
                .scaleEffect(0.4 + 0.6 * draw)
                .blendMode(.plusLighter)
            PostLoadCheckPath()
                .trim(from: 0, to: draw)
                .stroke(.white,
                        style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round))
                .padding(34)
        }
        .compositingGroup()
    }
}

struct PostLoadCheckPath: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: rect.minX + w * 0.04, y: rect.minY + h * 0.55))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.38, y: rect.minY + h * 0.90))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.98, y: rect.minY + h * 0.12))
        return p
    }
}

// MARK: - Pulse dot (shared)

struct PostLoadPulseDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    var body: some View {
        Circle()
            .fill(Brand.success)
            .frame(width: 7, height: 7)
            .overlay(
                Circle()
                    .stroke(Brand.success.opacity(0.5), lineWidth: 2)
                    .scaleEffect(pulse ? 2.1 : 1)
                    .opacity(pulse ? 0 : 0.8)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Small bespoke banner / CTA glyphs (replace SF Symbols)

/// Check tick for the inline "Load posted" banner.
struct PostLoadBannerCheck: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: rect.minX + w * 0.06, y: rect.minY + h * 0.55))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.40, y: rect.minY + h * 0.86))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.94, y: rect.minY + h * 0.18))
        return p
    }
}

/// Diagonal "×" close glyph for the banner dismiss buttons.
struct PostLoadBannerClose: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return p
    }
}

/// Rounded warning triangle body for the error banner.
struct PostLoadWarningTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        _ = (w, h)
        return p
    }
}

/// The "!" notch drawn inside the warning triangle.
struct PostLoadBangMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let x = rect.midX
        p.move(to: CGPoint(x: x, y: rect.minY + rect.height * 0.42))
        p.addLine(to: CGPoint(x: x, y: rect.minY + rect.height * 0.70))
        // The dot is a tiny second segment so a single stroke renders both.
        p.move(to: CGPoint(x: x, y: rect.minY + rect.height * 0.86))
        p.addLine(to: CGPoint(x: x, y: rect.minY + rect.height * 0.90))
        return p
    }
}

/// Bespoke "send" glyph (a route-arrow paper plane) for the Post CTA.
struct PostLoadSendGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        // A swept triangle with a folded centre crease — reads as "send".
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.42, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.42, y: rect.minY + h * 0.62))
        p.closeSubpath()
        return p
    }
}

// MARK: - Preview

#Preview("Posted celebration · Night") {
    ZStack {
        Theme.dark.bgPage.ignoresSafeArea()
        PostLoadPostedCelebration(loadNumber: "LD-260427-A38FB12C7E", onContinue: {})
            .environment(\.palette, Theme.dark)
    }
    .preferredColorScheme(.dark)
}
