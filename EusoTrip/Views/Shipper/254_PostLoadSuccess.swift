//
//  254_PostLoadSuccess.swift
//  EusoTrip — Shipper · Post-a-Load · Success.
//
//  F-ANIMATION (2026-06-14) — founder ask: "there needs to be a bespoke
//  professional super-high-quality animation letting the user know it
//  has been posted followed by a back to the beginning of a fresh new
//  load screen."
//
//  This screen is now a fully hand-built, brand-native celebration. ZERO
//  SF Symbols, ZERO emoji, ZERO third-party Lottie. Everything is drawn
//  with SwiftUI Canvas / Path / shape primitives on the house design
//  system (Brand blue→magenta aurora, the OrbeSang orb idiom, the
//  WeatherV3 aurora ring). The sequence:
//
//    1. An aurora ORB BURST — concentric brand-gradient rings expand and
//       fade outward from centre (a conic shimmer underneath).
//    2. A radial spark RAY field fans out once on the burst.
//    3. A route-pulse CHECK strokes itself on (trim-from-0 path draw),
//       seated in a brand-gradient disc that springs in.
//    4. The "Posted to the marketplace" headline + the LD- number + a
//       live "<N> carriers notified" counter fade and rise beneath it.
//
//  Reduce Motion renders the fully-settled frame instantly (no burst,
//  no stroke animation, no counter ramp) per the accessibility mandate.
//
//  On "Post another" the draft is reset and the wizard pushes back to a
//  FRESH Step-1 (screenId "250") via the canonical push-nav swap — the
//  204 single-screen surface performs the equivalent in-place reset in
//  its own submit() success branch.
//

import SwiftUI

struct PostLoadSuccessScreen: View {
    let theme: Theme.Palette
    @ObservedObject var draft: PostLoadDraft
    var body: some View {
        Shell(theme: theme) { SuccessBody(draft: draft) } nav: { shipperLifecycleNav() }
    }
}

// MARK: - Body

private struct SuccessBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var draft: PostLoadDraft

    /// Drives the burst rings, ray fan, and the conic shimmer phase.
    @State private var celebrate = false
    /// Drives the check disc spring + the path self-stroke (0→1 trim).
    @State private var checkDraw: CGFloat = 0
    /// Drives the copy fade/rise.
    @State private var copySettled = false
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            Spacer(minLength: 12)
            celebrationHero
            actionsCard
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, Space.s7)
        .onAppear(perform: run)
    }

    private func run() {
        if reduceMotion {
            celebrate = true
            checkDraw = 1
            copySettled = true
            return
        }
        // Disc + check seat first on a crisp spring.
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
            checkDraw = 1
        }
        // Burst rings + ray fan + conic shimmer run on their own timeline.
        withAnimation(.easeOut(duration: 1.05)) {
            celebrate = true
        }
        // Copy rises a beat after the disc lands.
        withAnimation(.spring(response: 0.55, dampingFraction: 0.85).delay(0.18)) {
            copySettled = true
        }
    }

    // MARK: Hero

    private var celebrationHero: some View {
        VStack(spacing: Space.s5) {
            ZStack {
                // Layer 1 — conic shimmer floor (slow rotation under the burst).
                AuroraBurstHalo(progress: celebrate ? 1 : 0,
                                reduceMotion: reduceMotion)
                    .frame(width: 220, height: 220)
                // Layer 2 — the route-pulse check, seated in a brand disc.
                PostedCheckMark(draw: checkDraw)
                    .frame(width: 108, height: 108)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 224)

            // Copy block.
            VStack(spacing: Space.s2) {
                Text("Posted to the marketplace")
                    .font(EType.h2)
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)

                // LD- number chip — brand-gradient hairline capsule.
                Text(draft.postedLoadNumber ?? "—")
                    .font(EType.mono(.caption))
                    .tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous).fill(palette.bgCardSoft)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(LinearGradient.diagonal, lineWidth: 1)
                    )

                // Live status line — honest, no fabricated count.
                HStack(spacing: 6) {
                    PulseDot()
                    Text("Now live for carriers in this lane")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .opacity(copySettled ? 1 : 0)
            .offset(y: copySettled ? 0 : 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s5)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(palette.iridescentHairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Load posted to the marketplace. \(draft.postedLoadNumber ?? ""). Now live for carriers in this lane.")
    }

    // MARK: Actions

    private var actionsCard: some View {
        VStack(spacing: Space.s2) {
            actionRow(glyph: .track, title: "Track this load",
                      subtitle: "Watch bids land in real time") {
                if let id = draft.postedLoadId {
                    NotificationCenter.default.post(
                        name: .eusoShipperNavSwap, object: nil,
                        userInfo: ["screenId": "260", "loadId": id]
                    )
                }
            }
            actionRow(glyph: .plus, title: "Post another load",
                      subtitle: "Start a fresh load from Step 1", emphasized: true) {
                // Reset the wizard draft and push back to a FRESH Step-1.
                draft.reset()
                NotificationCenter.default.post(
                    name: .eusoShipperNavSwap, object: nil,
                    userInfo: ["screenId": "250"]
                )
            }
            actionRow(glyph: .home, title: "Back to dashboard",
                      subtitle: "Return to your shipper home") {
                draft.reset()
                NotificationCenter.default.post(
                    name: .eusoShipperNavSwap, object: nil,
                    userInfo: ["screenId": "200"]
                )
            }
        }
    }

    private func actionRow(glyph: RowGlyph.Kind,
                           title: String,
                           subtitle: String,
                           emphasized: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                RowGlyph(kind: glyph)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(subtitle)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
                ChevronGlyph()
                    .stroke(palette.textTertiary,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: 8, height: 12)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(emphasized
                                  ? AnyShapeStyle(LinearGradient.diagonal)
                                  : AnyShapeStyle(palette.borderFaint),
                                  lineWidth: emphasized ? 1.2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Aurora burst halo (Canvas)

/// Concentric brand-gradient rings that expand + fade outward, over a
/// slowly-rotating conic shimmer. Hand-drawn; `progress` 0→1 drives the
/// burst, then the shimmer breathes via TimelineView. Reduce Motion shows
/// only the settled (faint, static) shimmer.
private struct AuroraBurstHalo: View {
    var progress: CGFloat
    var reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { tl in
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate

                // — Conic shimmer floor —
                let shimmer = GraphicsContext.Shading.conicGradient(
                    Gradient(colors: [Brand.blue, Brand.magenta,
                                      WeatherV3.auroraC, Brand.blue]),
                    center: c,
                    angle: .degrees((t * 22).truncatingRemainder(dividingBy: 360))
                )
                let floorR = size.width * 0.30
                var floor = Path()
                floor.addEllipse(in: CGRect(x: c.x - floorR, y: c.y - floorR,
                                            width: floorR * 2, height: floorR * 2))
                ctx.opacity = reduceMotion ? 0.18 : (0.14 + 0.06 * (0.5 + 0.5 * sin(t * 1.4)))
                ctx.fill(floor, with: shimmer)
                ctx.opacity = 1

                guard !reduceMotion else { return }

                // — Expanding burst rings —
                let ringCount = 3
                for i in 0..<ringCount {
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

                // — Radial spark rays (fan out once on the burst) —
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

// MARK: - Posted check mark (brand disc + self-stroking check)

/// A brand-gradient disc that springs in (`draw` scales it), wrapped in a
/// glowing rim, with a route-pulse check that strokes itself on via a
/// trim-from-0 path. Pure SwiftUI shapes — no SF Symbol.
private struct PostedCheckMark: View {
    var draw: CGFloat   // 0→1

    var body: some View {
        ZStack {
            // Outer glow rim.
            Circle()
                .strokeBorder(LinearGradient.diagonal, lineWidth: 2)
                .opacity(0.35)
                .scaleEffect(0.78 + 0.22 * draw)

            // Filled brand disc.
            Circle()
                .fill(LinearGradient.diagonal)
                .scaleEffect(0.4 + 0.6 * draw)
                .shadow(color: Brand.magenta.opacity(0.45 * draw), radius: 18, y: 6)

            // Specular highlight (the OrbeSang idiom).
            Circle()
                .fill(RadialGradient(
                    colors: [.white.opacity(0.55), .white.opacity(0)],
                    center: .init(x: 0.34, y: 0.28),
                    startRadius: 0, endRadius: 60))
                .scaleEffect(0.4 + 0.6 * draw)
                .blendMode(.plusLighter)

            // Self-stroking check (route-pulse).
            CheckPath()
                .trim(from: 0, to: draw)
                .stroke(.white,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                .padding(30)
        }
        .compositingGroup()
    }
}

/// The check glyph as a 2-segment path in a unit-ish rect so `.trim`
/// strokes it from the short leg through the long leg.
private struct CheckPath: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: rect.minX + w * 0.04, y: rect.minY + h * 0.55))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.38, y: rect.minY + h * 0.90))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.98, y: rect.minY + h * 0.12))
        return p
    }
}

// MARK: - Small bespoke glyphs (zero SF Symbols)

private struct ChevronGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return p
    }
}

/// A soft pulsing brand dot for the "carriers notified" live line.
private struct PulseDot: View {
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

/// Bespoke action-row glyph — a track ring / plus / home, each drawn with
/// Path on a brand-tinted tile. No SF Symbols.
private struct RowGlyph: View {
    enum Kind { case track, plus, home }
    @Environment(\.palette) private var palette
    let kind: Kind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(LinearGradient.esangSoft)
            glyph
                .padding(9)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    private var stroke: StrokeStyle {
        StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
    }

    @ViewBuilder private var glyph: some View {
        switch kind {
        case .track: TrackGlyph().stroke(LinearGradient.diagonal, style: stroke)
        case .plus:  PlusGlyph().stroke(LinearGradient.diagonal, style: stroke)
        case .home:  HomeGlyph().stroke(LinearGradient.diagonal, style: stroke)
        }
    }
}

private struct TrackGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // A radar ring with a centre node + a sweep tick.
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) * 0.42
        p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        p.addEllipse(in: CGRect(x: c.x - r * 0.16, y: c.y - r * 0.16,
                                width: r * 0.32, height: r * 0.32))
        p.move(to: c)
        p.addLine(to: CGPoint(x: c.x + r * 0.72, y: c.y - r * 0.72))
        return p
    }
}

private struct PlusGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

private struct HomeGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        // Roof.
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.46))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.46))
        // Walls.
        p.move(to: CGPoint(x: rect.minX + w * 0.14, y: rect.minY + h * 0.40))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.14, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - w * 0.14, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - w * 0.14, y: rect.minY + h * 0.40))
        return p
    }
}

// MARK: - Previews

#Preview("254 · Success · Night") {
    let d = PostLoadDraft(); d.postedLoadNumber = "LD-260427-A38FB12C7E"
    d.postedLoadId = "9001"
    return PostLoadSuccessScreen(theme: Theme.dark, draft: d)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("254 · Success · Afternoon") {
    let d = PostLoadDraft(); d.postedLoadNumber = "LD-260427-A38FB12C7E"
    d.postedLoadId = "9001"
    return PostLoadSuccessScreen(theme: Theme.light, draft: d)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
