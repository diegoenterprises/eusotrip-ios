//
//  WeatherCard.swift
//  EusoTrip — Driver Home weather card (screen 010)
//
//  Renders a live current-conditions snapshot on top of an animated, scene-
//  aware sky backdrop. The backdrop changes based on:
//    • time of day  — night (stars + moon) vs day (sun + atmosphere)
//    • condition    — clear, cloudy, rain, thunder, snow, fog
//
//  Everything is built from SwiftUI primitives (Canvas, TimelineView, phase
//  animators) so the card stays lightweight on device and animates at 60 fps
//  without pulling external assets.
//
//  Visual spec (aligned with Figma 212:444 + the web twin):
//    • Rounded card, deep saturated sky gradient behind content
//    • Star field with twinkle / sun disk with halo depending on time
//    • Drifting clouds during day, moonlit haze at night
//    • Condition-driven particles (rain drops, snowflakes)
//    • Foreground: glyph badge, city/condition/meta, big temp, next-alert pill
//
//  The card is still driven by `WeatherSnapshot` — no extra state required
//  from the view model. The scene picks the right visuals from `snapshot`.
//

import SwiftUI

struct WeatherCard: View {
    let snapshot: WeatherSnapshot
    @Environment(\.palette) var palette
    @Environment(\.colorScheme) private var scheme

    /// Flip state. Tap the card → rotates 180° on Y, revealing the
    /// 5-day forecast. Tap again → rotates back. We stage two stacked
    /// views with mirrored `rotation3DEffect` so the front/back transition
    /// reads as a single physical card turning rather than a crossfade.
    @State private var flipped: Bool = false

    private var isNight: Bool {
        // Local clock is the *primary* night gate. The previous order
        // ("symbol first, clock fallback") was wrong because the NWS +
        // Open-Meteo fallback paths in WeatherService return day-only
        // SF Symbols (sun.max, cloud.rain.fill, etc.) regardless of
        // local hour — only WeatherKit emits a night-specific symbol
        // (moon.stars, etc.). When WeatherKit fails, the card was
        // painting a sun disk at 1 AM during a storm because the
        // "sun" substring short-circuited the clock check.
        let h = Calendar.current.component(.hour, from: Date())
        let clockSaysNight = h >= 20 || h < 6
        if clockSaysNight { return true }
        // Day hours — let WeatherKit's explicit night symbol still win
        // (e.g. early-evening dusk in winter when WeatherKit ships a
        // moon symbol before 8 PM local).
        if snapshot.symbol.contains("moon") || snapshot.symbol.contains("night") {
            return true
        }
        return false
    }

    private var condition: SkyCondition {
        let s = snapshot.condition.lowercased()
        let sym = snapshot.symbol.lowercased()
        if s.contains("thunder") || sym.contains("bolt") { return .thunder }
        if s.contains("snow") || sym.contains("snow") || sym.contains("snowflake") { return .snow }
        if s.contains("rain") || s.contains("shower") || s.contains("drizzle") || sym.contains("rain") { return .rain }
        if s.contains("fog") || s.contains("haze") || s.contains("smoke") || sym.contains("fog") { return .fog }
        if s.contains("cloud") || sym.contains("cloud") { return .cloudy }
        return .clear
    }

    var body: some View {
        // A classic 3D card-flip: front and back both rotate around the
        // Y axis. At 0° the front is visible; at 180° the back is. We
        // key each face's rotation off `flipped` with a 180° offset so
        // both faces never face the camera at the same time.
        //
        // `.opacity` gates which face is visible during the middle of the
        // turn (SwiftUI renders both views; without opacity gating the
        // mirrored back-face would ghost through the front at 90°).
        ZStack {
            frontFace
                .opacity(flipped ? 0 : 1)
                .rotation3DEffect(.degrees(flipped ? 180 : 0),
                                  axis: (x: 0, y: 1, z: 0),
                                  perspective: 0.55)
            backFace
                .opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(flipped ? 0 : -180),
                                  axis: (x: 0, y: 1, z: 0),
                                  perspective: 0.55)
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .onTapGesture {
            // Spring turn — feels physical because the card overshoots
            // slightly at the end. Response + damping values tuned so
            // the flip completes in ~550ms without visible bounce on
            // the secondary axis.
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                flipped.toggle()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            flipped
            ? "5-day forecast for \(snapshot.city). Tap to return to current conditions."
            : ("Weather, \(snapshot.city), \(snapshot.condition), "
               + "\(snapshot.tempDisplay), \(snapshot.metaDisplay)"
               + (snapshot.nextAlert.map { ", next alert \($0)" } ?? "")
               + ". Tap to see the 5-day forecast.")
        )
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Front — current conditions

    private var frontFace: some View {
        ZStack(alignment: .topLeading) {
            // Animated sky behind everything — sets the mood.
            SkyBackdrop(isNight: isNight,
                        condition: condition,
                        accent: snapshot.accent.color)
                .allowsHitTesting(false)

            // Content.
            HStack(alignment: .top, spacing: Space.s3) {
                glyphBadge

                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.city.uppercased())
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(contentSecondary)
                    Text(snapshot.condition)
                        .font(EType.bodyStrong)
                        .foregroundStyle(contentPrimary)
                        .lineLimit(1)
                    Text(snapshot.metaDisplay)
                        .font(EType.caption)
                        .foregroundStyle(contentSecondary)
                        .padding(.top, 2)
                }

                Spacer(minLength: Space.s2)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(snapshot.tempDisplay)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(contentPrimary)
                        .shadow(color: .black.opacity(isNight ? 0.35 : 0.12), radius: 2, y: 1)
                    if let alert = snapshot.nextAlert {
                        Text(alert.uppercased())
                            .font(EType.micro).tracking(0.6)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(
                                Capsule().fill(snapshot.accent.color.opacity(0.85))
                            )
                            .overlay(
                                Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                            )
                    }
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Tiny flip-hint chevron in the bottom-right so a first-time
            // user knows the card is interactive. Subtle enough not to
            // compete with temperature readability but present enough to
            // signal "turn me over."
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: "arrow.2.squarepath")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(6)
                        .background(
                            Circle().fill(.white.opacity(0.12))
                        )
                        .padding(Space.s3)
                        .allowsHitTesting(false)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.white.opacity(0.06)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        )
        .shadow(color: Color.black.opacity(isNight ? 0.35 : 0.18), radius: 18, y: 10)
    }

    // MARK: Back — 5-day forecast

    private var backFace: some View {
        // The back shares the front's atmospheric backdrop so the card
        // feels like the same object turning rather than a completely
        // different surface — only the foreground content swaps.
        ZStack(alignment: .topLeading) {
            SkyBackdrop(isNight: isNight,
                        condition: condition,
                        accent: snapshot.accent.color)
                .allowsHitTesting(false)
            // Dim the backdrop slightly so the 5 rows of white text
            // always clear the contrast bar against a noisy day sky.
            Color.black.opacity(isNight ? 0.15 : 0.22)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .center, spacing: Space.s2) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("5-day forecast")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Text(snapshot.city)
                        .font(EType.micro).tracking(0.4)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }

                // If the upstream API didn't return daily data (older
                // cached snapshot, Open-Meteo network fail, etc.), show
                // a neutral fallback rather than an empty back face.
                if snapshot.daily.isEmpty {
                    Text("Forecast unavailable")
                        .font(EType.bodyStrong)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.top, 6)
                    if let alert = snapshot.nextAlert {
                        Text(alert)
                            .font(EType.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                } else {
                    VStack(spacing: 4) {
                        ForEach(snapshot.daily.prefix(5)) { day in
                            forecastRow(day: day)
                        }
                    }
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.white.opacity(0.06)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        )
        .shadow(color: Color.black.opacity(isNight ? 0.35 : 0.18), radius: 18, y: 10)
    }

    @ViewBuilder
    private func forecastRow(day: WeatherSnapshot.DailyForecast) -> some View {
        HStack(spacing: Space.s2) {
            Text(day.weekdayLabel)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 48, alignment: .leading)
            Image(systemName: day.symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .frame(width: 22)
            // Precip chip. Hidden when probability is too low to be
            // worth showing so the row stays clean on clear days.
            if let precip = day.precipDisplay {
                HStack(spacing: 2) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text(precip)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(
                    Capsule().fill(Color.white.opacity(0.14))
                )
            }
            Spacer(minLength: Space.s2)
            // Hi/lo pair with the hi in the accent color and lo in a
            // cooler secondary tint so a quick glance reads "warm→cool"
            // without having to parse the labels.
            HStack(spacing: 8) {
                Text(day.highDisplay)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(day.lowDisplay)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Foreground chrome

    private var contentPrimary: Color {
        // Always white-on-sky — the backdrop is deep enough in both schemes.
        .white
    }

    private var contentSecondary: Color {
        Color.white.opacity(0.75)
    }

    private var glyphBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(snapshot.accent.color.opacity(0.25))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
                )
            Image(systemName: snapshot.symbol)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        }
        .frame(width: 44, height: 44)
    }
}

// MARK: - Sky scene

enum SkyCondition {
    case clear
    case cloudy
    case rain
    case thunder
    case snow
    case fog
}

/// Animated sky backdrop. A stack of:
///   • atmosphere gradient (night vs day, tinted by condition)
///   • celestial body (moon + stars, or sun + haze)
///   • drifting clouds (condition-dependent density)
///   • precipitation particles (rain / snow / thunder flashes)
private struct SkyBackdrop: View {
    let isNight: Bool
    let condition: SkyCondition
    let accent: Color

    var body: some View {
        ZStack {
            atmosphereGradient
            celestialLayer
            cloudLayer
            precipitationLayer
            // Subtle vignette so the top reads sky and the bottom reads horizon.
            LinearGradient(
                colors: [
                    Color.black.opacity(isNight ? 0.0 : 0.0),
                    Color.black.opacity(isNight ? 0.25 : 0.15)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .blendMode(.multiply)
        }
    }

    // MARK: Atmosphere gradient

    private var atmosphereGradient: some View {
        let colors: [Color]
        switch (isNight, condition) {
        case (true, .clear):
            colors = [
                Color(red: 0.04, green: 0.06, blue: 0.20),   // deep navy
                Color(red: 0.10, green: 0.09, blue: 0.32),   // indigo
                Color(red: 0.20, green: 0.12, blue: 0.40)    // plum twilight
            ]
        case (true, .cloudy), (true, .fog):
            colors = [
                Color(red: 0.06, green: 0.08, blue: 0.17),
                Color(red: 0.12, green: 0.14, blue: 0.23),
                Color(red: 0.22, green: 0.22, blue: 0.32)
            ]
        case (true, .rain), (true, .thunder):
            colors = [
                Color(red: 0.03, green: 0.05, blue: 0.13),
                Color(red: 0.08, green: 0.10, blue: 0.22),
                Color(red: 0.15, green: 0.18, blue: 0.35)
            ]
        case (true, .snow):
            colors = [
                Color(red: 0.08, green: 0.12, blue: 0.28),
                Color(red: 0.18, green: 0.22, blue: 0.42),
                Color(red: 0.34, green: 0.38, blue: 0.58)
            ]
        case (false, .clear):
            colors = [
                Color(red: 0.14, green: 0.55, blue: 0.92),   // sky blue
                Color(red: 0.40, green: 0.74, blue: 0.98),
                Color(red: 0.78, green: 0.89, blue: 0.99)    // soft horizon
            ]
        case (false, .cloudy), (false, .fog):
            colors = [
                Color(red: 0.40, green: 0.52, blue: 0.66),
                Color(red: 0.62, green: 0.72, blue: 0.82),
                Color(red: 0.82, green: 0.86, blue: 0.90)
            ]
        case (false, .rain), (false, .thunder):
            colors = [
                Color(red: 0.22, green: 0.30, blue: 0.42),
                Color(red: 0.36, green: 0.46, blue: 0.58),
                Color(red: 0.56, green: 0.64, blue: 0.72)
            ]
        case (false, .snow):
            colors = [
                Color(red: 0.66, green: 0.74, blue: 0.85),
                Color(red: 0.82, green: 0.88, blue: 0.94),
                Color(red: 0.94, green: 0.96, blue: 0.99)
            ]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    // MARK: Celestial layer (moon + stars, or sun + halo)

    @ViewBuilder
    private var celestialLayer: some View {
        if isNight {
            StarsField(density: condition == .clear ? 1.0 : (condition == .cloudy || condition == .fog ? 0.25 : 0.55))
            if condition == .clear || condition == .snow {
                Moon()
            }
        } else {
            if condition == .clear || condition == .snow {
                Sun(accent: accent)
            }
        }
    }

    // MARK: Clouds

    @ViewBuilder
    private var cloudLayer: some View {
        switch condition {
        case .clear:
            DriftingClouds(density: isNight ? 0.25 : 0.35, tint: Color.white.opacity(isNight ? 0.08 : 0.65))
        case .cloudy, .fog:
            DriftingClouds(density: 0.9, tint: Color.white.opacity(isNight ? 0.18 : 0.75))
        case .rain, .thunder:
            DriftingClouds(density: 0.8, tint: Color.white.opacity(isNight ? 0.15 : 0.60))
        case .snow:
            DriftingClouds(density: 0.7, tint: Color.white.opacity(isNight ? 0.22 : 0.80))
        }
    }

    // MARK: Precipitation

    @ViewBuilder
    private var precipitationLayer: some View {
        switch condition {
        case .rain:
            RainStreaks(intensity: 0.85)
        case .thunder:
            ZStack {
                RainStreaks(intensity: 1.0)
                LightningFlash()
            }
        case .snow:
            SnowField(intensity: 0.8)
        default:
            EmptyView()
        }
    }
}

// MARK: Star field — twinkling points rendered in Canvas.

private struct StarsField: View {
    let density: Double  // 0…1

    // Pre-seeded star positions so layout is stable across frames.
    private let stars: [Star] = (0..<70).map { i in
        var rng = SeededRNG(seed: UInt64(0x5EED + i * 17))
        return Star(
            x: rng.next01(),
            y: rng.next01() * 0.72,       // bias upward
            radius: 0.4 + rng.next01() * 1.6,
            phase: rng.next01() * .pi * 2,
            speed: 0.8 + rng.next01() * 1.6
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            Canvas { ctx, size in
                let t = context.date.timeIntervalSinceReferenceDate
                let keepCount = Int(Double(stars.count) * density)
                for star in stars.prefix(keepCount) {
                    let twinkle = (sin(t * star.speed + star.phase) + 1) / 2     // 0…1
                    let alpha = 0.35 + twinkle * 0.65
                    let r = star.radius * (0.85 + 0.3 * twinkle)
                    let cx = star.x * size.width
                    let cy = star.y * size.height
                    let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
                    // Crisp cross glint on the 3 largest stars for a little magic.
                    if r > 1.4 {
                        var cross = Path()
                        cross.move(to: CGPoint(x: cx - r * 3, y: cy))
                        cross.addLine(to: CGPoint(x: cx + r * 3, y: cy))
                        cross.move(to: CGPoint(x: cx, y: cy - r * 3))
                        cross.addLine(to: CGPoint(x: cx, y: cy + r * 3))
                        ctx.stroke(cross, with: .color(.white.opacity(alpha * 0.35)), lineWidth: 0.4)
                    }
                }
            }
        }
    }

    private struct Star {
        let x: Double
        let y: Double
        let radius: Double
        let phase: Double
        let speed: Double
    }
}

// MARK: Moon — subtle disc with halo.

private struct Moon: View {
    var body: some View {
        GeometryReader { geo in
            let r: CGFloat = 22
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.18), Color.white.opacity(0.0)],
                            center: .center, startRadius: 0, endRadius: r * 2.8
                        )
                    )
                    .frame(width: r * 5.6, height: r * 5.6)
                    .blur(radius: 6)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.95), Color(red: 0.92, green: 0.93, blue: 0.99)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: r * 2, height: r * 2)
                    .overlay(
                        Circle()
                            .fill(Color.black.opacity(0.08))
                            .frame(width: r * 0.7, height: r * 0.7)
                            .offset(x: 4, y: -3)
                            .blur(radius: 2)
                    )
                    .shadow(color: .white.opacity(0.4), radius: 8)
            }
            .position(x: geo.size.width * 0.82, y: geo.size.height * 0.38)
        }
    }
}

// MARK: Sun — warm disc with halo.

private struct Sun: View {
    let accent: Color

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let pulse = 1 + 0.05 * sin(t * 1.6)
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.55),
                                    Color(red: 1.0, green: 0.86, blue: 0.45).opacity(0.25),
                                    Color.clear
                                ],
                                center: .center, startRadius: 0, endRadius: 90
                            )
                        )
                        .frame(width: 180, height: 180)
                        .blur(radius: 8)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.98, blue: 0.82),
                                    Color(red: 1.0, green: 0.84, blue: 0.42)
                                ],
                                center: .center, startRadius: 0, endRadius: 28
                            )
                        )
                        .frame(width: 44 * pulse, height: 44 * pulse)
                        .shadow(color: Color(red: 1.0, green: 0.84, blue: 0.42).opacity(0.55), radius: 14)
                }
                .position(x: geo.size.width * 0.82, y: geo.size.height * 0.38)
            }
        }
    }
}

// MARK: Drifting clouds — soft blobs moving horizontally.

private struct DriftingClouds: View {
    let density: Double
    let tint: Color

    private let clouds: [CloudPuff] = (0..<5).map { i in
        var rng = SeededRNG(seed: UInt64(0xC100 + i * 31))
        return CloudPuff(
            y: 0.15 + rng.next01() * 0.55,
            width: 0.35 + rng.next01() * 0.55,
            speed: 0.008 + rng.next01() * 0.012,
            phase: rng.next01(),
            opacity: 0.6 + rng.next01() * 0.4
        )
    }

    var body: some View {
        let visible = max(1, Int(Double(clouds.count) * density))
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for puff in clouds.prefix(visible) {
                    let travel = (t * puff.speed + puff.phase).truncatingRemainder(dividingBy: 1.2) - 0.1
                    let cx = CGFloat(travel) * size.width
                    let cy = CGFloat(puff.y) * size.height
                    let w = CGFloat(puff.width) * size.width
                    drawCloud(ctx: ctx, center: CGPoint(x: cx, y: cy), width: w, tint: tint.opacity(puff.opacity))
                }
            }
        }
    }

    private func drawCloud(ctx: GraphicsContext, center: CGPoint, width: CGFloat, tint: Color) {
        let h = width * 0.28
        let base = CGRect(x: center.x - width / 2, y: center.y - h / 2, width: width, height: h)
        // 3-lobe blob.
        let r1 = h * 0.9
        let r2 = h * 1.1
        let r3 = h * 0.8
        var path = Path()
        path.addEllipse(in: CGRect(x: base.minX, y: base.midY - r1, width: r1 * 2, height: r1 * 2))
        path.addEllipse(in: CGRect(x: base.midX - r2, y: base.midY - r2 * 1.15, width: r2 * 2, height: r2 * 2))
        path.addEllipse(in: CGRect(x: base.maxX - r3 * 2, y: base.midY - r3, width: r3 * 2, height: r3 * 2))
        ctx.fill(path, with: .color(tint))
    }

    private struct CloudPuff {
        let y: Double
        let width: Double
        let speed: Double
        let phase: Double
        let opacity: Double
    }
}

// MARK: Rain streaks.

private struct RainStreaks: View {
    let intensity: Double
    private let drops: [Drop] = (0..<60).map { i in
        var rng = SeededRNG(seed: UInt64(0xDEAD + i * 23))
        return Drop(
            x: rng.next01(),
            len: 8 + rng.next01() * 14,
            speed: 140 + rng.next01() * 120,
            phase: rng.next01()
        )
    }

    var body: some View {
        let count = Int(Double(drops.count) * intensity)
        TimelineView(.animation(minimumInterval: 1.0 / 45.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for drop in drops.prefix(count) {
                    let travel = (t * drop.speed / Double(size.height) + drop.phase).truncatingRemainder(dividingBy: 1.0)
                    let y = CGFloat(travel) * size.height
                    let x = CGFloat(drop.x) * size.width
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x + 2, y: y + drop.len))
                    ctx.stroke(p, with: .color(.white.opacity(0.55)), lineWidth: 1.1)
                }
            }
        }
    }

    private struct Drop {
        let x: Double
        let len: Double
        let speed: Double
        let phase: Double
    }
}

// MARK: Snow field.

private struct SnowField: View {
    let intensity: Double
    private let flakes: [Flake] = (0..<55).map { i in
        var rng = SeededRNG(seed: UInt64(0xF10A + i * 19))
        return Flake(
            x: rng.next01(),
            size: 1.2 + rng.next01() * 2.4,
            speed: 18 + rng.next01() * 30,
            sway: 4 + rng.next01() * 10,
            phase: rng.next01()
        )
    }

    var body: some View {
        let count = Int(Double(flakes.count) * intensity)
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for flake in flakes.prefix(count) {
                    let travel = (t * flake.speed / Double(size.height) + flake.phase).truncatingRemainder(dividingBy: 1.0)
                    let y = CGFloat(travel) * size.height
                    let sway = sin(t * 1.2 + flake.phase * .pi * 2) * flake.sway
                    let x = CGFloat(flake.x) * size.width + CGFloat(sway)
                    let r = CGFloat(flake.size)
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)),
                        with: .color(.white.opacity(0.85))
                    )
                }
            }
        }
    }

    private struct Flake {
        let x: Double
        let size: Double
        let speed: Double
        let sway: Double
        let phase: Double
    }
}

// MARK: Lightning flash — slow random strobe.

private struct LightningFlash: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // Deterministic strobe: fire a flash every 3.2 s, 120 ms wide.
            let cycle = t.truncatingRemainder(dividingBy: 3.2)
            let intensity: Double = cycle < 0.12 ? (1 - cycle / 0.12) : 0
            Rectangle()
                .fill(Color.white.opacity(intensity * 0.5))
                .blendMode(.plusLighter)
        }
    }
}

// MARK: - Tiny seeded RNG so star/cloud layouts are stable.

private struct SeededRNG {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xDEADBEEF : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
    mutating func next01() -> Double {
        Double(next() & 0xFFFFFFFF) / Double(UInt32.max)
    }
}

// MARK: - Previews

#Preview("Night · Clear") {
    WeatherCard(snapshot: WeatherSnapshot(
        city: "Dallas, TX",
        tempF: 58,
        windMph: 7,
        visibilityMi: 10,
        condition: "Clear",
        symbol: "moon.stars.fill",
        nextAlert: "tonight · low 48°",
        accent: .calm
    ))
    .padding()
    .background(Theme.dark.bgPage)
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("Day · Rain") {
    WeatherCard(snapshot: WeatherSnapshot(
        city: "Meridian, MS",
        tempF: 68,
        windMph: 14,
        visibilityMi: 4,
        condition: "Heavy rain",
        symbol: "cloud.heavyrain.fill",
        nextAlert: "3h · storms ease",
        accent: .watch
    ))
    .padding()
    .background(Theme.light.bgPage)
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}

#Preview("Day · Clear") {
    WeatherCard(snapshot: WeatherSnapshot(
        city: "Phoenix, AZ",
        tempF: 96,
        windMph: 6,
        visibilityMi: 10,
        condition: "Sunny",
        symbol: "sun.max.fill",
        nextAlert: nil,
        accent: .calm
    ))
    .padding()
    .background(Theme.light.bgPage)
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
