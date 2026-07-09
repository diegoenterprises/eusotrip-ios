//
//  WeatherSkyEngine.swift
//  EusoTrip — Apple-Weather-grade continuous animated sky scenes.
//
//  The centerpiece of the weather overhaul (build 751). A self-contained,
//  in-house SwiftUI animation engine that renders a CONTINUOUS, layered,
//  z-ordered scene for EVERY condition × time-of-day × season, driven
//  entirely by the live `WeatherSnapshot`. Drifting storm clouds,
//  intensity-scaled rain, lightning strobe + drawn bolt, snow/sleet/hail,
//  sun + rays + lens-flare, MOON WITH PHASE, stars + magnitude-varied
//  twinkle, fog drift, wind shear.
//
//  ── DOCTRINE ────────────────────────────────────────────────────────
//  • In-house SwiftUI `Canvas` + `TimelineView(.animation)` ONLY — never
//    a WKWebView, never a Lottie/JSON player. Same Native-SVG/Canvas idiom
//    as `WeatherCard.swift`'s `SkyBackdrop` (which this supersedes).
//  • ZERO per-frame allocations: every particle field is a `let` array,
//    pre-seeded ONCE via `SeededRNG` (xorshift), so each frame only reads
//    positions and computes deterministic motion — no `.map`/alloc in the
//    render path.
//  • Reduce Motion → ONE representative static frame (no loop, the
//    `TimelineView` is bypassed entirely — we branch on `animated` and call
//    `frame(t: 0)` directly so no schedule is even created).
//  • ZERO fabrication: every scene input is a REAL `WeatherSnapshot` field:
//      condition ← `snapshot.weatherCode`
//      intensity ← `snapshot.precipChancePct` (+ condition floor)
//      wind lean ← `snapshot.windMph`
//      low-vis   ← `snapshot.visibilityMi`
//      day/night ← `snapshot.isNight`        (sunrise/sunset → hour gate)
//      day part  ← `snapshot.dayPart`        (6-band, sun-pair anchored)
//      season    ← `snapshot.season`         (hemisphere-aware)
//      moon      ← `snapshot.moonPhase`      (synodic illumination + limb)
//    The model owns the astronomy (pure, deterministic helpers in
//    `WeatherSnapshot`); this engine is a pure CONSUMER of those values, so
//    the card, a unit test, and a preview all compute identically. The view
//    NEVER recomputes day/season/moon locally — single source of truth.
//
//  ── PERFORMANCE BUDGET ──────────────────────────────────────────────
//  • Atmosphere / celestial / cloud / fog: 30 fps schedules.
//  • Precipitation (rain/sleet/hail/snow): 45 fps for crisp streaks.
//  • Lightning: 20 fps (a strobe doesn't need more, and it keeps the GPU
//    cool during the most expensive — full-frame — composite).
//  • Particle counts are capped per condition (≤ 60 rain, ≤ 64 snow,
//    ≤ 56 sleet/hail, ≤ 80 stars) and scaled DOWN by intensity via
//    `.prefix(n)` over the pre-seeded array — never re-seeded.
//
//  This file is intentionally standalone. `WeatherCard.swift` is wired to
//  it by the Integrate lane (do not edit WeatherCard here).
//

import Foundation
import SwiftUI

// MARK: - SkyConditionV2 — the full 21-code taxonomy

/// The complete weather taxonomy the engine animates. Each case maps to a
/// distinct layered scene (atmosphere + celestial + cloud + precipitation).
/// Mapped from the canonical numeric `weatherCode` (the v2 backbone — same
/// codes `WeatherIcons` + `SkyStageHero` key off, derived from the Apple
/// WeatherKit condition) via `SkyConditionV2(weatherCode:)`.
///
/// Named `…V2` to coexist with `WeatherCard.swift`'s legacy 6-case
/// `SkyCondition` while the Integrate lane rewires the card onto this engine
/// (the two top-level enums would otherwise collide). This is the
/// authoritative, granular taxonomy.
///
/// Granularity matters: the founder bug ("Drizzle / Light-Rain / Rain /
/// Heavy-Rain all render identically") is fixed by making each its OWN case
/// with its OWN particle profile, rather than the old 6-bucket parser.
enum SkyConditionV2: Hashable, CaseIterable {
    // Clear / cloud gradient
    case clear            // 1000
    case mostlyClear      // 1100
    case partlyCloudy     // 1101
    case mostlyCloudy     // 1102
    case cloudy           // 1001
    // Visibility
    case fog              // 2000
    case lightFog         // 2100
    case dust             // out-of-band (smoke/haze/dust); ochre fog
    // Liquid precipitation
    case drizzle          // 4000
    case lightRain        // 4200
    case rain             // 4001
    case heavyRain        // 4201
    // Freezing rain (shimmer/glint)
    case freezingDrizzle  // 6000
    case lightFreezingRain// 6200
    case freezingRain     // 6001
    case heavyFreezingRain// 6201
    // Ice pellets / sleet / hail (bounce)
    case lightSleet       // 7102
    case sleet            // 7000
    case heavySleet       // 7101
    case hail             // out-of-band; large bouncing spheres
    // Snow
    case flurries         // 5001
    case lightSnow        // 5100
    case snow             // 5000
    case heavySnow        // 5101
    case blizzard         // out-of-band; heavy snow + extreme shear
    // Storm
    case thunderstorm     // 8000
    case severeThunderstorm // out-of-band; multi-flash + bolt
    // Atmospheric
    case windy            // out-of-band; streak lines + fast clouds

    /// Map the canonical numeric `weatherCode` → a granular `SkyConditionV2`.
    /// Unknown / 0 falls back to `.partlyCloudy` (a benign, honest neutral
    /// rather than a fake clear sky).
    init(weatherCode: Int) {
        switch weatherCode {
        case 1000:                 self = .clear
        case 1100:                 self = .mostlyClear
        case 1101:                 self = .partlyCloudy
        case 1102:                 self = .mostlyCloudy
        case 1001:                 self = .cloudy
        case 2000:                 self = .fog
        case 2100:                 self = .lightFog
        case 4000:                 self = .drizzle
        case 4200:                 self = .lightRain
        case 4001:                 self = .rain
        case 4201:                 self = .heavyRain
        case 6000:                 self = .freezingDrizzle
        case 6200:                 self = .lightFreezingRain
        case 6001:                 self = .freezingRain
        case 6201:                 self = .heavyFreezingRain
        case 7102:                 self = .lightSleet
        case 7000:                 self = .sleet
        case 7101:                 self = .heavySleet
        case 5001:                 self = .flurries
        case 5100:                 self = .lightSnow
        case 5000:                 self = .snow
        case 5101:                 self = .heavySnow
        case 8000:                 self = .thunderstorm
        default:                   self = .partlyCloudy
        }
    }

    /// Cloud-cover density 0…1 for the drifting-cloud layer.
    var cloudDensity: Double {
        switch self {
        case .clear:                                  return 0.18
        case .mostlyClear:                            return 0.30
        case .partlyCloudy:                           return 0.45
        case .mostlyCloudy:                           return 0.72
        case .cloudy:                                 return 0.90
        case .fog, .dust:                             return 0.85
        case .lightFog:                               return 0.55
        case .drizzle, .lightRain:                    return 0.60
        case .rain:                                   return 0.80
        case .heavyRain:                              return 0.95
        case .freezingDrizzle, .lightFreezingRain:    return 0.55
        case .freezingRain:                           return 0.72
        case .heavyFreezingRain:                      return 0.92
        case .lightSleet:                             return 0.45
        case .sleet:                                  return 0.70
        case .heavySleet:                             return 0.95
        case .hail:                                   return 0.95
        case .flurries:                               return 0.42
        case .lightSnow:                              return 0.55
        case .snow:                                   return 0.72
        case .heavySnow, .blizzard:                   return 0.95
        case .thunderstorm:                           return 0.85
        case .severeThunderstorm:                     return 0.95
        case .windy:                                  return 0.40
        }
    }

    /// Is this a precipitating/dense condition that should obscure the
    /// celestial body (sun/moon hidden behind the storm or overcast)?
    var hidesCelestial: Bool {
        switch self {
        case .heavyRain, .heavyFreezingRain, .heavySleet, .hail,
             .heavySnow, .blizzard, .thunderstorm, .severeThunderstorm,
             .cloudy, .fog, .dust:
            return true
        default:
            return false
        }
    }

    var isThunder: Bool { self == .thunderstorm || self == .severeThunderstorm }
}

// MARK: - WeatherSkyView — the composed, layered scene

/// The Apple-Weather-grade animated sky. Composes z-ordered layers PER
/// condition, all driven by the live `WeatherSnapshot`:
///
///   1. Atmosphere gradient   (dayPart × season × condition)
///   2. Celestial             (sun + rays + flare  |  moon-with-phase + stars)
///   3. Clouds                (density-scaled drift, wind-aware speed)
///   4. Precipitation         (intensity-scaled rain/snow/sleet/hail/freezing)
///   5. Lightning             (strobe + drawn bolt, thunderstorm only)
///   6. Fog veils             (drifting translucent banks, fog/dust only)
///   7. Wind streaks          (windy, or any high-wind condition)
///   8. Vignette              (horizon grounding, low-vis darkening)
///
/// `animated == false` (Reduce Motion) renders every layer as a single
/// representative static frame — identical composition, zero TimelineView
/// ticks, zero loop.
struct WeatherSkyView: View {
    let snapshot: WeatherSnapshot
    var animated: Bool = true

    init(snapshot: WeatherSnapshot, animated: Bool = true) {
        self.snapshot = snapshot
        self.animated = animated
    }

    // ── Scene inputs — ALL read from the live snapshot (no local astro) ──
    private var condition: SkyConditionV2 { SkyConditionV2(weatherCode: snapshot.weatherCode) }
    private var isNight: Bool { snapshot.isNight }
    private var dayPart: WeatherSnapshot.DayPart { snapshot.dayPart }
    private var season: WeatherSnapshot.Season { snapshot.season }
    private var moon: WeatherSnapshot.MoonPhase { snapshot.moonPhase }

    /// Precipitation intensity 0…1, blended from the condition's base
    /// profile and the LIVE `precipChancePct`. The condition sets the floor
    /// (a "heavy rain" code is dense regardless), the live precip % nudges
    /// within the band so a 90%-chance rain looks heavier than a 30% one.
    private var precipIntensity: Double {
        let live = Double(snapshot.precipChancePct ?? 0) / 100.0
        let base: Double
        switch condition {
        case .drizzle, .freezingDrizzle:                       base = 0.28
        case .lightRain, .lightFreezingRain, .flurries,
             .lightSleet, .lightSnow:                          base = 0.45
        case .rain, .freezingRain, .sleet, .snow:              base = 0.72
        case .heavyRain, .heavyFreezingRain, .heavySleet,
             .heavySnow, .hail, .blizzard:                     base = 1.0
        case .thunderstorm:                                    base = 0.88
        case .severeThunderstorm:                              base = 1.0
        default:                                               base = 0.0
        }
        // Live precip % can only push the band UP toward the cap, never
        // below the condition's own floor (the code is the ground truth).
        return min(1.0, max(base, base * 0.6 + live * 0.55))
    }

    /// Wind shear 0…1 from the LIVE `windMph` — drives the rain/snow lean
    /// angle and the wind-streak layer. 0 mph = vertical, ~35+ mph = sharp.
    private var windShear: Double { min(1.0, Double(snapshot.windMph) / 35.0) }

    /// Lightning warmth: cold-blue in winter, warm-yellow in summer — a
    /// real seasonal cue layered on the storm.
    private var lightningTint: Color {
        switch season {
        case .winter: return Color(red: 0.80, green: 0.92, blue: 1.0)
        case .summer: return Color(red: 1.0, green: 0.96, blue: 0.72)
        default:      return Color(red: 0.96, green: 0.97, blue: 1.0)
        }
    }

    /// Low-visibility darkening 0…1 from the LIVE `visibilityMi` — chokes
    /// the scene as real visibility drops below ~6 mi.
    private var visibilityChoke: Double {
        let v = Double(snapshot.visibilityMi)
        guard v < 6 else { return 0 }
        return min(0.5, (6 - v) / 12.0)
    }

    /// Sun's vertical position in the frame, by season (summer rides high,
    /// winter sits low) — derived from the REAL `snapshot.season`.
    private var sunElevation: CGFloat {
        switch season {
        case .summer: return 0.26
        case .spring: return 0.32
        case .fall:   return 0.36
        case .winter: return 0.44
        }
    }

    /// Star-twinkle amplitude multiplier — crisper, brighter winter skies.
    private var starBrightness: Double {
        switch season {
        case .winter: return 1.20
        case .fall:   return 1.05
        case .spring: return 1.00
        case .summer: return 0.90
        }
    }

    var body: some View {
        ZStack {
            atmosphereLayer
            celestialLayer
            cloudLayer
            precipitationLayer
            lightningLayer
            fogLayer
            windLayer
            vignetteLayer
        }
        .drawingGroup(opaque: false)   // flatten the composite into one GPU layer
        .accessibilityHidden(true)     // decorative; the card owns the a11y text
    }

    // MARK: 1 · Atmosphere gradient

    private var atmosphereLayer: some View {
        let golden = dayPart.isTwilight
        return LinearGradient(
            colors: SkyPalette.atmosphere(condition: condition, isNight: isNight,
                                          twilight: golden, season: season),
            startPoint: .top, endPoint: .bottom
        )
        .overlay(
            // Dusk/dawn warm horizon wash — a low amber band only at the
            // golden hours, multiplied so it grounds the horizon.
            golden
            ? AnyView(LinearGradient(
                colors: [.clear, .clear,
                         Color(red: 1.0, green: 0.55, blue: 0.30).opacity(0.22)],
                startPoint: .top, endPoint: .bottom)
                .blendMode(.plusLighter))
            : AnyView(Color.clear)
        )
    }

    // MARK: 2 · Celestial — sun (day) or moon-with-phase + stars (night)

    @ViewBuilder
    private var celestialLayer: some View {
        if isNight {
            // Stars first (behind the moon), brightness scaled by season +
            // how much the condition obscures the sky.
            let starDensity = condition.hidesCelestial ? 0.18 : (1.0 - condition.cloudDensity * 0.6)
            StarField(density: max(0.1, starDensity),
                      brightness: starBrightness,
                      animated: animated)
            if !condition.hidesCelestial {
                MoonPhaseView(phase: moon, animated: animated)
            }
        } else {
            if !condition.hidesCelestial {
                SunBody(elevation: sunElevation,
                        warmth: dayPart.isTwilight,
                        obscured: condition.cloudDensity > 0.55,
                        animated: animated)
            }
        }
    }

    // MARK: 3 · Clouds

    private var cloudLayer: some View {
        let night = isNight
        let tint: Color = {
            switch condition {
            case .thunderstorm, .severeThunderstorm, .heavyRain, .heavyFreezingRain:
                return Color(white: night ? 0.22 : 0.42).opacity(0.92)   // thunder-dark
            case .rain, .freezingRain, .sleet, .heavySleet, .hail:
                return Color(white: night ? 0.30 : 0.58).opacity(0.85)
            case .snow, .heavySnow, .blizzard, .flurries, .lightSnow:
                return Color(white: night ? 0.40 : 0.92).opacity(0.85)
            case .fog, .lightFog:
                return Color(white: night ? 0.34 : 0.78).opacity(0.55)
            case .dust:
                return Color(red: 0.62, green: 0.52, blue: 0.36).opacity(0.55)
            default:
                return Color.white.opacity(night ? 0.14 : 0.72)
            }
        }()
        return DriftingClouds(
            density: condition.cloudDensity,
            tint: tint,
            // Wind speeds up the drift; storms churn faster than fair-weather cumulus.
            speedScale: 1.0 + windShear * 1.6 + (condition.isThunder ? 0.8 : 0),
            turbulent: condition.isThunder || condition == .heavyRain || condition == .blizzard,
            animated: animated
        )
    }

    // MARK: 4 · Precipitation

    @ViewBuilder
    private var precipitationLayer: some View {
        switch condition {
        case .drizzle, .lightRain, .rain, .heavyRain:
            RainLayer(intensity: precipIntensity, windShear: windShear,
                      splash: condition == .heavyRain || condition == .rain,
                      tint: rainTint, animated: animated)

        case .thunderstorm, .severeThunderstorm:
            RainLayer(intensity: precipIntensity, windShear: max(windShear, 0.35),
                      splash: true, tint: rainTint, animated: animated)

        case .freezingDrizzle, .lightFreezingRain, .freezingRain, .heavyFreezingRain:
            FreezingRainLayer(intensity: precipIntensity, windShear: windShear,
                              animated: animated)

        case .lightSleet, .sleet, .heavySleet:
            SleetLayer(intensity: precipIntensity, windShear: windShear,
                       hail: false, animated: animated)

        case .hail:
            SleetLayer(intensity: precipIntensity, windShear: windShear,
                       hail: true, animated: animated)

        case .flurries, .lightSnow, .snow, .heavySnow, .blizzard:
            SnowLayer(intensity: precipIntensity,
                      windShear: condition == .blizzard ? max(windShear, 0.6) : windShear,
                      flakeScale: season == .winter ? 1.2 : 0.85,
                      animated: animated)

        case .clear, .mostlyClear, .partlyCloudy, .mostlyCloudy, .cloudy,
             .fog, .lightFog, .dust, .windy:
            EmptyView()
        }
    }

    /// Rain droplet tint: cool in winter, neutral-warm in summer.
    private var rainTint: Color {
        switch season {
        case .winter: return Color(red: 0.78, green: 0.86, blue: 0.98)
        case .summer: return Color(red: 0.90, green: 0.94, blue: 1.0)
        default:      return Color(red: 0.85, green: 0.91, blue: 1.0)
        }
    }

    // MARK: 5 · Lightning (thunderstorm only)

    @ViewBuilder
    private var lightningLayer: some View {
        if animated && condition.isThunder {
            LightningLayer(severe: condition == .severeThunderstorm,
                           tint: lightningTint)
        }
    }

    // MARK: 6 · Fog / mist / dust veils

    @ViewBuilder
    private var fogLayer: some View {
        switch condition {
        case .fog:
            FogVeils(intensity: 0.8, tint: Color.white.opacity(0.55),
                     driftSpeed: 0.40, animated: animated)
        case .lightFog:
            FogVeils(intensity: 0.45, tint: Color.white.opacity(0.42),
                     driftSpeed: 0.26, animated: animated)
        case .dust:
            FogVeils(intensity: 0.7, tint: Color(red: 0.74, green: 0.62, blue: 0.42).opacity(0.55),
                     driftSpeed: 0.20, animated: animated)
        default:
            EmptyView()
        }
    }

    // MARK: 7 · Wind streaks

    @ViewBuilder
    private var windLayer: some View {
        // The dedicated windy condition, OR any condition where the LIVE
        // wind is genuinely hazardous (≥ 25 mph) — show motion of the air.
        if condition == .windy || (snapshot.windHazard && !condition.isThunder) {
            WindStreaks(strength: max(0.35, windShear), animated: animated)
        }
    }

    // MARK: 8 · Vignette + low-visibility choke

    private var vignetteLayer: some View {
        ZStack {
            // Horizon grounding — bottom always reads a touch heavier.
            LinearGradient(
                colors: [.clear, Color.black.opacity(isNight ? 0.28 : 0.16)],
                startPoint: .center, endPoint: .bottom
            )
            .blendMode(.multiply)
            // Live low-visibility darkening (real `visibilityMi`).
            if visibilityChoke > 0 {
                RadialGradient(
                    colors: [.clear, Color.black.opacity(visibilityChoke)],
                    center: .center, startRadius: 40, endRadius: 280
                )
                .blendMode(.multiply)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - SkyPalette — atmosphere gradients (condition × dayPart × season)

/// All atmosphere gradients in one honest table. The base palette is keyed
/// off condition (storms are purple-electric, rain cool-slate, snow pale,
/// fog monochrome, clear blue) and then SHIFTED by day part (warm at the
/// golden hours, navy at night) and nudged by season.
private enum SkyPalette {
    static func atmosphere(condition: SkyConditionV2,
                           isNight: Bool,
                           twilight: Bool,
                           season: WeatherSnapshot.Season) -> [Color] {
        let night = isNight
        let golden = twilight && !isNight

        switch condition {
        // ── Clear / mostly-clear ───────────────────────────────────────
        case .clear, .mostlyClear:
            if night {
                return [rgb(0.04, 0.05, 0.18), rgb(0.09, 0.08, 0.30), rgb(0.18, 0.12, 0.38)]
            } else if golden {
                return [rgb(0.18, 0.30, 0.60), rgb(0.62, 0.46, 0.58), rgb(1.0, 0.66, 0.42)]
            } else {
                let warm: CGFloat = season == .summer ? 0.04 : 0
                return [rgb(0.13 + warm, 0.53, 0.92), rgb(0.40, 0.74, 0.98), rgb(0.80, 0.90, 0.99)]
            }

        // ── Partly / mostly cloudy ─────────────────────────────────────
        case .partlyCloudy, .mostlyCloudy:
            if night {
                return [rgb(0.06, 0.08, 0.19), rgb(0.12, 0.13, 0.26), rgb(0.22, 0.22, 0.34)]
            } else if golden {
                return [rgb(0.26, 0.32, 0.50), rgb(0.58, 0.52, 0.56), rgb(0.92, 0.70, 0.52)]
            } else {
                return [rgb(0.22, 0.48, 0.78), rgb(0.50, 0.68, 0.86), rgb(0.80, 0.88, 0.94)]
            }

        // ── Overcast ───────────────────────────────────────────────────
        case .cloudy:
            if night {
                return [rgb(0.07, 0.08, 0.14), rgb(0.13, 0.14, 0.20), rgb(0.22, 0.23, 0.28)]
            } else {
                let cool: CGFloat = season == .winter ? -0.04 : 0
                return [rgb(0.40 + cool, 0.46, 0.54), rgb(0.60, 0.66, 0.72), rgb(0.80, 0.84, 0.88)]
            }

        // ── Fog / mist ─────────────────────────────────────────────────
        case .fog, .lightFog:
            if night {
                return [rgb(0.10, 0.11, 0.15), rgb(0.18, 0.19, 0.23), rgb(0.30, 0.31, 0.35)]
            } else {
                return [rgb(0.52, 0.55, 0.58), rgb(0.66, 0.68, 0.70), rgb(0.80, 0.81, 0.82)]
            }

        // ── Dust / smoke (ochre) ───────────────────────────────────────
        case .dust:
            return night
                ? [rgb(0.18, 0.14, 0.10), rgb(0.28, 0.22, 0.15), rgb(0.38, 0.30, 0.20)]
                : [rgb(0.62, 0.50, 0.34), rgb(0.74, 0.62, 0.44), rgb(0.86, 0.76, 0.58)]

        // ── Drizzle / light rain ───────────────────────────────────────
        case .drizzle, .lightRain:
            return night
                ? [rgb(0.06, 0.09, 0.16), rgb(0.12, 0.16, 0.24), rgb(0.22, 0.27, 0.36)]
                : [rgb(0.34, 0.44, 0.54), rgb(0.50, 0.60, 0.68), rgb(0.70, 0.78, 0.82)]

        // ── Rain / heavy rain ──────────────────────────────────────────
        case .rain, .heavyRain:
            return night
                ? [rgb(0.03, 0.05, 0.12), rgb(0.08, 0.11, 0.20), rgb(0.16, 0.20, 0.30)]
                : [rgb(0.20, 0.30, 0.40), rgb(0.34, 0.44, 0.54), rgb(0.52, 0.62, 0.68)]

        // ── Freezing rain (icy steel) ──────────────────────────────────
        case .freezingDrizzle, .lightFreezingRain, .freezingRain, .heavyFreezingRain:
            return night
                ? [rgb(0.05, 0.09, 0.16), rgb(0.11, 0.18, 0.26), rgb(0.22, 0.32, 0.42)]
                : [rgb(0.40, 0.50, 0.60), rgb(0.56, 0.66, 0.74), rgb(0.74, 0.82, 0.88)]

        // ── Sleet / ice pellets / hail ─────────────────────────────────
        case .lightSleet, .sleet, .heavySleet, .hail:
            return night
                ? [rgb(0.06, 0.08, 0.13), rgb(0.13, 0.16, 0.22), rgb(0.24, 0.28, 0.34)]
                : [rgb(0.42, 0.48, 0.54), rgb(0.58, 0.64, 0.70), rgb(0.76, 0.80, 0.84)]

        // ── Snow (pale cold) ───────────────────────────────────────────
        case .flurries, .lightSnow, .snow, .heavySnow, .blizzard:
            if night {
                return [rgb(0.10, 0.14, 0.28), rgb(0.20, 0.26, 0.42), rgb(0.34, 0.40, 0.56)]
            } else {
                return [rgb(0.66, 0.74, 0.86), rgb(0.82, 0.88, 0.94), rgb(0.94, 0.96, 0.99)]
            }

        // ── Thunderstorm (electric purple) ─────────────────────────────
        case .thunderstorm, .severeThunderstorm:
            if night {
                return [rgb(0.08, 0.06, 0.18), rgb(0.14, 0.11, 0.28), rgb(0.20, 0.16, 0.36)]
            } else {
                let warm: CGFloat = season == .summer ? 0.03 : 0
                return [rgb(0.15 + warm, 0.12, 0.30), rgb(0.24, 0.20, 0.40), rgb(0.36, 0.32, 0.50)]
            }

        // ── Windy (clear-ish but moving) ───────────────────────────────
        case .windy:
            return night
                ? [rgb(0.07, 0.10, 0.20), rgb(0.14, 0.18, 0.30), rgb(0.24, 0.30, 0.42)]
                : [rgb(0.30, 0.52, 0.74), rgb(0.52, 0.68, 0.84), rgb(0.78, 0.86, 0.92)]
        }
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> Color {
        Color(red: r, green: g, blue: b)
    }
}

// MARK: - SunBody — disc + breathing halo + rotating rays + lens flare

/// The day-time sun. A layered Canvas: a wide radial halo that BREATHES,
/// 12 rays that slowly ROTATE (180° / 60 s — steady, not pulsing), a hot
/// core disc, and a diagonal LENS-FLARE chain of soft circles. Positioned
/// by the season's `elevation` (summer high, winter low). When `obscured`
/// (sun behind thick cloud), the rays/flare fade and the halo dims.
private struct SunBody: View {
    let elevation: CGFloat
    let warmth: Bool        // dawn/dusk golden tint
    let obscured: Bool
    var animated: Bool = true

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                frame(t: ctx.date.timeIntervalSinceReferenceDate)
            }
        } else {
            frame(t: 0)
        }
    }

    private var core: Color {
        warmth ? Color(red: 1.0, green: 0.74, blue: 0.42)
               : Color(red: 1.0, green: 0.92, blue: 0.66)
    }
    private var glow: Color {
        warmth ? Color(red: 1.0, green: 0.62, blue: 0.34)
               : Color(red: 1.0, green: 0.84, blue: 0.46)
    }

    private func frame(t: TimeInterval) -> some View {
        let breath = 1 + 0.05 * sin(t * 1.4)
        let rayAngle = t.truncatingRemainder(dividingBy: 60) / 60 * .pi   // 180°/60s
        let rayAlpha = obscured ? 0.10 : 0.34
        let flareAlpha = obscured ? 0.0 : 0.5

        return Canvas { gc, size in
            let cx = size.width * 0.80
            let cy = size.height * elevation
            let center = CGPoint(x: cx, y: cy)
            let coreR: CGFloat = 22 * breath

            // ── Wide breathing halo ──
            let haloR = coreR * (obscured ? 3.0 : 4.6)
            gc.fill(
                Path(ellipseIn: CGRect(x: cx - haloR, y: cy - haloR, width: haloR * 2, height: haloR * 2)),
                with: .radialGradient(
                    Gradient(colors: [glow.opacity(obscured ? 0.18 : 0.40),
                                      glow.opacity(0.08), .clear]),
                    center: center, startRadius: 0, endRadius: haloR)
            )

            // ── Rotating rays (12 tapered spokes) ──
            if rayAlpha > 0.05 {
                for i in 0..<12 {
                    let a = rayAngle + Double(i) * (.pi / 6)
                    let inner = coreR * 1.3
                    let outer = coreR * (2.4 + 0.5 * sin(t * 0.8 + Double(i)))
                    var ray = Path()
                    ray.move(to: CGPoint(x: cx + cos(a) * inner, y: cy + sin(a) * inner))
                    ray.addLine(to: CGPoint(x: cx + cos(a) * outer, y: cy + sin(a) * outer))
                    gc.stroke(ray, with: .color(core.opacity(rayAlpha)),
                              style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
                }
            }

            // ── Hot core disc ──
            gc.fill(
                Path(ellipseIn: CGRect(x: cx - coreR, y: cy - coreR, width: coreR * 2, height: coreR * 2)),
                with: .radialGradient(
                    Gradient(colors: [.white, core, glow]),
                    center: center, startRadius: 0, endRadius: coreR)
            )

            // ── Diagonal lens-flare chain ──
            if flareAlpha > 0 {
                let dx = (size.width * 0.5 - cx)
                let dy = (size.height * 0.5 - cy)
                let spots: [(CGFloat, CGFloat)] = [(0.45, 6), (0.85, 10), (1.25, 4), (1.7, 14)]
                for (k, r) in spots {
                    let px = cx + dx * k
                    let py = cy + dy * k
                    gc.fill(
                        Path(ellipseIn: CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)),
                        with: .radialGradient(
                            Gradient(colors: [core.opacity(flareAlpha * 0.5), .clear]),
                            center: CGPoint(x: px, y: py), startRadius: 0, endRadius: r))
                }
            }
        }
    }
}

// MARK: - MoonPhaseView — disc with terminator-shaded crescent → full

/// The night-time moon, rendered AT ITS REAL PHASE. Binds directly to the
/// snapshot's `MoonPhase` (illumination + waxing/waning limb). The lit disc
/// is masked by a shadow circle slid along the synodic cycle: at low
/// illumination the shadow covers the disc (new), at full it's pushed clear,
/// and in-between offsets carve the crescent/gibbous terminator. Waxing
/// lights the right limb, waning the left. A soft halo + a few maria sell it.
private struct MoonPhaseView: View {
    let phase: WeatherSnapshot.MoonPhase
    var animated: Bool = true

    var body: some View {
        // The moon's phase changes over days, not seconds, so it has no
        // per-frame animation — a single static draw is correct in BOTH
        // motion modes (only the halo's faint shimmer animates, and it's
        // suppressed under Reduce Motion).
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                frame(shimmer: 0.5 + 0.5 * sin(ctx.date.timeIntervalSinceReferenceDate * 0.6))
            }
        } else {
            frame(shimmer: 0.5)
        }
    }

    private func frame(shimmer: Double) -> some View {
        Canvas { gc, size in
            let r: CGFloat = 22
            let cx = size.width * 0.80
            let cy = size.height * 0.32
            let illum = phase.illumination
            let waxing = phase.isWaxing

            // ── Halo ──
            let haloR = r * 3.0
            gc.fill(
                Path(ellipseIn: CGRect(x: cx - haloR, y: cy - haloR, width: haloR * 2, height: haloR * 2)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.10 + 0.06 * illum * shimmer), .clear]),
                    center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: haloR)
            )

            let discRect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
            let discPath = Path(ellipseIn: discRect)
            let shadowColor = Color(red: 0.16, green: 0.17, blue: 0.24)

            // ── Dark side of the disc (earthshine) — always faintly drawn ──
            gc.fill(discPath, with: .color(shadowColor.opacity(0.9)))

            // ── Lit portion ──
            // Clip to the disc, fill the bright body, then subtract a shadow
            // circle offset by the illumination. illum 1 (full) → shadow
            // off-frame; illum 0 (new) → shadow centred (covers).
            gc.drawLayer { layer in
                layer.clip(to: discPath)
                let bright = Color(red: 0.96, green: 0.96, blue: 0.99)
                layer.fill(discPath,
                           with: .radialGradient(
                            Gradient(colors: [.white, bright]),
                            center: CGPoint(x: cx - r * 0.25, y: cy - r * 0.25),
                            startRadius: 0, endRadius: r * 1.4))
                let slide = (1 - illum) * r * 2.0
                let dir: CGFloat = waxing ? -1 : 1   // waxing: shadow exits left
                let shadowCx = cx + dir * slide
                let shadowRect = CGRect(x: shadowCx - r, y: cy - r, width: r * 2, height: r * 2)
                layer.fill(Path(ellipseIn: shadowRect), with: .color(shadowColor.opacity(0.96)))
            }

            // ── Maria (a few soft dark dimples on the lit face) ──
            if illum > 0.25 {
                let maria: [(CGFloat, CGFloat, CGFloat)] = [(-0.3, -0.1, 0.30), (0.18, 0.28, 0.22), (0.05, -0.32, 0.16)]
                gc.drawLayer { layer in
                    layer.clip(to: discPath)
                    for (mx, my, ms) in maria {
                        let mr = r * ms
                        let mcx = cx + mx * r
                        let mcy = cy + my * r
                        layer.fill(
                            Path(ellipseIn: CGRect(x: mcx - mr, y: mcy - mr, width: mr * 2, height: mr * 2)),
                            with: .color(Color.black.opacity(0.06)))
                    }
                }
            }
        }
    }
}

// MARK: - StarField — magnitude-varied twinkle

/// Pre-seeded star positions with continuous magnitude (faint → bright).
/// Brighter stars are larger, twinkle slower, and get a cross glint.
/// `density` thins the field (cloud cover hides stars), `brightness`
/// scales the twinkle amplitude (winter skies are crisper).
private struct StarField: View {
    let density: Double
    let brightness: Double
    var animated: Bool = true

    private let stars: [Star] = (0..<80).map { i in
        var rng = SeededRNG(seed: UInt64(0x57A8 + i * 17))
        let mag = rng.next01()                       // 0 faint … 1 bright
        return Star(
            x: rng.next01(),
            y: rng.next01() * 0.70,                  // bias upper sky
            radius: 0.4 + mag * mag * 1.8,           // bright stars markedly larger
            phase: rng.next01() * .pi * 2,
            speed: 0.5 + (1 - mag) * 2.2,            // faint stars scintillate faster
            magnitude: mag
        )
    }

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                frame(t: ctx.date.timeIntervalSinceReferenceDate)
            }
        } else {
            frame(t: 0)
        }
    }

    private func frame(t: TimeInterval) -> some View {
        let keep = Int(Double(stars.count) * max(0.05, min(1, density)))
        return Canvas { gc, size in
            for star in stars.prefix(keep) {
                let tw = (sin(t * star.speed + star.phase) + 1) / 2
                let alpha = min(1, (0.30 + tw * 0.70 * brightness) * (0.55 + star.magnitude * 0.45))
                let r = star.radius * (0.85 + 0.30 * tw)
                let cx = star.x * size.width
                let cy = star.y * size.height
                gc.fill(
                    Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                    with: .color(.white.opacity(alpha)))
                // Bright stars get a crisp cross glint.
                if star.magnitude > 0.82 {
                    var cross = Path()
                    cross.move(to: CGPoint(x: cx - r * 3.2, y: cy))
                    cross.addLine(to: CGPoint(x: cx + r * 3.2, y: cy))
                    cross.move(to: CGPoint(x: cx, y: cy - r * 3.2))
                    cross.addLine(to: CGPoint(x: cx, y: cy + r * 3.2))
                    gc.stroke(cross, with: .color(.white.opacity(alpha * 0.4)), lineWidth: 0.4)
                }
            }
        }
    }

    private struct Star {
        let x, y, radius, phase, speed, magnitude: Double
    }
}

// MARK: - DriftingClouds — density-scaled, wind-aware, turbulent for storms

private struct DriftingClouds: View {
    let density: Double
    let tint: Color
    var speedScale: Double = 1.0
    var turbulent: Bool = false
    var animated: Bool = true

    private let clouds: [CloudPuff] = (0..<8).map { i in
        var rng = SeededRNG(seed: UInt64(0xC100 + i * 31))
        return CloudPuff(
            y: 0.10 + rng.next01() * 0.55,
            width: 0.34 + rng.next01() * 0.60,
            speed: 0.006 + rng.next01() * 0.012,
            phase: rng.next01() * 1.4,
            opacity: 0.55 + rng.next01() * 0.45,
            bob: rng.next01()
        )
    }

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                frame(t: ctx.date.timeIntervalSinceReferenceDate)
            }
        } else {
            frame(t: 0)
        }
    }

    private func frame(t: TimeInterval) -> some View {
        let visible = max(1, Int(Double(clouds.count) * density))
        return Canvas { gc, size in
            for puff in clouds.prefix(visible) {
                let travel = (t * puff.speed * speedScale + puff.phase)
                    .truncatingRemainder(dividingBy: 1.4) - 0.2
                let cx = CGFloat(travel) * size.width
                // Storm clouds churn vertically; fair-weather clouds sit still.
                let bob = turbulent ? CGFloat(sin(t * 0.6 + puff.bob * 6) * 8) : 0
                let cy = CGFloat(puff.y) * size.height + bob
                let w = CGFloat(puff.width) * size.width
                drawCloud(gc, center: CGPoint(x: cx, y: cy), width: w,
                          tint: tint.opacity(puff.opacity), turbulent: turbulent)
            }
        }
    }

    private func drawCloud(_ gc: GraphicsContext, center: CGPoint, width: CGFloat,
                           tint: Color, turbulent: Bool) {
        let h = width * (turbulent ? 0.34 : 0.26)
        let base = CGRect(x: center.x - width / 2, y: center.y - h / 2, width: width, height: h)
        let r1 = h * 0.9, r2 = h * 1.15, r3 = h * 0.85, r4 = h * 0.7
        var path = Path()
        path.addEllipse(in: CGRect(x: base.minX, y: base.midY - r1, width: r1 * 2, height: r1 * 2))
        path.addEllipse(in: CGRect(x: base.midX - r2 * 1.2, y: base.midY - r2 * 1.2, width: r2 * 2, height: r2 * 2))
        path.addEllipse(in: CGRect(x: base.midX, y: base.midY - r4, width: r4 * 2, height: r4 * 2))
        path.addEllipse(in: CGRect(x: base.maxX - r3 * 2, y: base.midY - r3, width: r3 * 2, height: r3 * 2))
        gc.fill(path, with: .color(tint))
    }

    private struct CloudPuff {
        let y, width, speed, phase, opacity, bob: Double
    }
}

// MARK: - RainLayer — intensity-scaled streaks, wind-shear lean, splash

private struct RainLayer: View {
    let intensity: Double       // 0…1
    let windShear: Double       // 0…1 lateral lean
    var splash: Bool = false
    var tint: Color = Color(red: 0.85, green: 0.91, blue: 1.0)
    var animated: Bool = true

    private let drops: [Drop] = (0..<60).map { i in
        var rng = SeededRNG(seed: UInt64(0xDEAD + i * 23))
        return Drop(x: rng.next01(), len: rng.next01(), speed: rng.next01(), phase: rng.next01())
    }

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 45.0)) { ctx in
                frame(t: ctx.date.timeIntervalSinceReferenceDate)
            }
        } else {
            frame(t: 0)
        }
    }

    private func frame(t: TimeInterval) -> some View {
        // Intensity scales count (18 → 60), length band, speed band, opacity.
        let count = max(6, Int(Double(drops.count) * (0.30 + intensity * 0.70)))
        let lenMin = 4 + intensity * 10                 // drizzle short, heavy long
        let lenSpan = 6 + intensity * 12
        let speedMin = 70 + intensity * 130             // drizzle slow, heavy fast
        let speedSpan = 50 + intensity * 110
        let alpha = 0.32 + intensity * 0.40
        let lean = CGFloat(windShear) * 14              // px of horizontal run per drop

        return Canvas { gc, size in
            for drop in drops.prefix(count) {
                let len = lenMin + drop.len * lenSpan
                let speed = speedMin + drop.speed * speedSpan
                let travel = (t * speed / Double(size.height) + drop.phase)
                    .truncatingRemainder(dividingBy: 1.0)
                let y = CGFloat(travel) * size.height
                let x = CGFloat(drop.x) * size.width
                var p = Path()
                p.move(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x + lean, y: y + CGFloat(len)))
                gc.stroke(p, with: .color(tint.opacity(alpha)),
                          style: StrokeStyle(lineWidth: 0.9 + intensity * 0.6, lineCap: .round))

                // ── Splash at the base for heavier rain ──
                if splash && travel > 0.93 {
                    let sy = size.height - 4
                    let sr = 1.0 + intensity * 1.6
                    gc.stroke(
                        Path(ellipseIn: CGRect(x: x - sr, y: sy - sr * 0.4, width: sr * 2, height: sr * 0.8)),
                        with: .color(tint.opacity(alpha * 0.6)), lineWidth: 0.6)
                }
            }
        }
    }

    private struct Drop { let x, len, speed, phase: Double }
}

// MARK: - FreezingRainLayer — icy streaks with a screen-blend glint

/// Freezing rain / drizzle. Same fall as rain, but every streak carries a
/// bright cyan glint rendered with `.screen` so the ice catches light. The
/// shimmer intensifies with the condition's intensity.
private struct FreezingRainLayer: View {
    let intensity: Double
    let windShear: Double
    var animated: Bool = true

    private let drops: [Drop] = (0..<55).map { i in
        var rng = SeededRNG(seed: UInt64(0x1CE0 + i * 29))
        return Drop(x: rng.next01(), len: rng.next01(), speed: rng.next01(),
                    phase: rng.next01(), glint: rng.next01())
    }

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 45.0)) { ctx in
                frame(t: ctx.date.timeIntervalSinceReferenceDate)
            }
        } else {
            frame(t: 0)
        }
    }

    private func frame(t: TimeInterval) -> some View {
        let count = max(8, Int(Double(drops.count) * (0.30 + intensity * 0.70)))
        let lenMin = 6 + intensity * 8
        let lenSpan = 6 + intensity * 8
        let speed = 90 + intensity * 90
        let lean = CGFloat(windShear) * 12
        let cyan = Color(red: 0.72, green: 0.92, blue: 1.0)

        return Canvas { gc, size in
            for drop in drops.prefix(count) {
                let len = lenMin + drop.len * lenSpan
                let travel = (t * (speed + drop.speed * 40) / Double(size.height) + drop.phase)
                    .truncatingRemainder(dividingBy: 1.0)
                let y = CGFloat(travel) * size.height
                let x = CGFloat(drop.x) * size.width
                var p = Path()
                p.move(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x + lean, y: y + CGFloat(len)))
                // Base icy streak.
                gc.stroke(p, with: .color(cyan.opacity(0.35 + intensity * 0.25)), lineWidth: 1.0)
                // Bright glint head with screen blend — the ice sparkle.
                let gr = 1.0 + intensity * 1.4
                var glint = gc
                glint.blendMode = .screen
                glint.fill(
                    Path(ellipseIn: CGRect(x: x - gr, y: y - gr, width: gr * 2, height: gr * 2)),
                    with: .color(Color.white.opacity(0.4 + 0.4 * drop.glint)))
            }
        }
    }

    private struct Drop { let x, len, speed, phase, glint: Double }
}

// MARK: - SleetLayer — bouncing pellets (ice) or large spheres (hail)

/// Ice pellets / sleet (and hail when `hail == true`). Particles fall fast
/// and BOUNCE off the base: the vertical position follows an asymmetric arc
/// that snaps up ~55% on contact. Hail uses larger spheres with a
/// screen-blend glint, an underside shadow (spin), and an impact sparkle.
private struct SleetLayer: View {
    let intensity: Double
    let windShear: Double
    var hail: Bool = false
    var animated: Bool = true

    private let pellets: [Pellet] = (0..<56).map { i in
        var rng = SeededRNG(seed: UInt64(0x5EE7 + i * 37))
        return Pellet(x: rng.next01(), size: rng.next01(), speed: rng.next01(),
                      phase: rng.next01(), bounce: rng.next01(),
                      streak: rng.next01() > 0.5)
    }

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 45.0)) { ctx in
                frame(t: ctx.date.timeIntervalSinceReferenceDate)
            }
        } else {
            frame(t: 0)
        }
    }

    private func frame(t: TimeInterval) -> some View {
        let count = max(8, Int(Double(pellets.count) * (0.30 + intensity * 0.70)))
        let sizeMin: CGFloat = hail ? 3.0 : 1.4
        let sizeSpan: CGFloat = hail ? 6.0 : 2.4
        let speed = (hail ? 200.0 : 150.0) + intensity * (hail ? 140 : 90)
        let lean = CGFloat(windShear) * (hail ? 10 : 14)

        return Canvas { gc, size in
            for pellet in pellets.prefix(count) {
                let raw = (t * (speed + pellet.speed * 60) / Double(size.height) + pellet.phase)
                    .truncatingRemainder(dividingBy: 1.0)
                // Bounce arc: below 0.9 it falls; above it rebounds upward ~55%.
                let yFrac: CGFloat
                if raw < 0.9 {
                    yFrac = CGFloat(raw / 0.9)
                } else {
                    let b = (raw - 0.9) / 0.1
                    yFrac = 1 - CGFloat(b) * 0.55 * CGFloat(pellet.bounce)   // kick back up
                }
                let y = yFrac * size.height
                let x = CGFloat(pellet.x) * size.width + lean * yFrac
                let r = sizeMin + CGFloat(pellet.size) * sizeSpan

                if pellet.streak && !hail {
                    // Mixed sleet shows some short angled streaks too.
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x + lean * 0.5, y: y + r * 2.2))
                    gc.stroke(p, with: .color(.white.opacity(0.55)), lineWidth: 0.9)
                } else {
                    // Solid pellet / hailstone.
                    gc.fill(
                        Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)),
                        with: .color(.white.opacity(hail ? 0.92 : 0.85)))
                    if hail {
                        // Bright spin glint (screen) + soft shadow underside.
                        var glint = gc
                        glint.blendMode = .screen
                        glint.fill(
                            Path(ellipseIn: CGRect(x: x - r / 2 + r * 0.18, y: y - r / 2 + r * 0.12,
                                                   width: r * 0.5, height: r * 0.5)),
                            with: .color(Color.white.opacity(0.8)))
                        gc.fill(
                            Path(ellipseIn: CGRect(x: x - r / 2, y: y, width: r, height: r * 0.5)),
                            with: .color(.black.opacity(0.10)))
                    }
                    // Impact sparkle at the bounce point.
                    if raw >= 0.9 {
                        let sr = r * 0.8
                        gc.stroke(
                            Path(ellipseIn: CGRect(x: x - sr, y: y - sr * 0.3, width: sr * 2, height: sr * 0.6)),
                            with: .color(.white.opacity(0.5)), lineWidth: 0.6)
                    }
                }
            }
        }
    }

    private struct Pellet {
        let x, size, speed, phase, bounce: Double
        let streak: Bool
    }
}

// MARK: - SnowLayer — density-scaled flakes, sine sway, wind shear

private struct SnowLayer: View {
    let intensity: Double
    let windShear: Double
    var flakeScale: Double = 1.0
    var animated: Bool = true

    private let flakes: [Flake] = (0..<64).map { i in
        var rng = SeededRNG(seed: UInt64(0xF10A + i * 19))
        return Flake(x: rng.next01(), size: rng.next01(), speed: rng.next01(),
                     sway: rng.next01(), phase: rng.next01())
    }

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                frame(t: ctx.date.timeIntervalSinceReferenceDate)
            }
        } else {
            frame(t: 0)
        }
    }

    private func frame(t: TimeInterval) -> some View {
        let count = max(8, Int(Double(flakes.count) * (0.30 + intensity * 0.70)))
        let sizeMin = (1.0 + intensity * 1.2) * flakeScale
        let sizeSpan = (1.4 + intensity * 1.6) * flakeScale
        let speed = 18 + intensity * 42                     // gentle → blizzard descent
        let swayBase = 4 + intensity * 12
        let drift = CGFloat(windShear) * 0.18               // blizzard lateral push

        return Canvas { gc, size in
            for flake in flakes.prefix(count) {
                let travel = (t * (speed + flake.speed * 24) / Double(size.height) + flake.phase)
                    .truncatingRemainder(dividingBy: 1.0)
                let y = CGFloat(travel) * size.height
                let sway = sin(t * 1.1 + flake.phase * .pi * 2) * (swayBase + flake.sway * 8)
                let x = CGFloat(flake.x + Double(drift) * travel) * size.width + CGFloat(sway)
                let r = CGFloat(sizeMin + flake.size * sizeSpan)
                gc.fill(
                    Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)),
                    with: .color(.white.opacity(0.85)))
            }
        }
    }

    private struct Flake { let x, size, speed, sway, phase: Double }
}

// MARK: - LightningLayer — full-frame strobe + an occasional drawn bolt

/// The thunderstorm finale. A deterministic strobe fires the full-frame
/// flash on a cycle (severe storms cycle faster and fire a double-flash),
/// and on a slower cadence an actual forked BOLT is drawn — a jagged Path
/// with a bright core + soft glow. All deterministic (no `Date`-seeded
/// randomness in the render path); the bolt geometry is pre-seeded once.
private struct LightningLayer: View {
    let severe: Bool
    let tint: Color

    /// One pre-seeded bolt geometry (normalized 0…1 points down the frame).
    /// Re-positioned horizontally each strike but the jag is stable.
    private let bolt: [CGPoint] = {
        var rng = SeededRNG(seed: 0xB01D)
        var pts: [CGPoint] = []
        var x = 0.5
        let steps = 9
        for i in 0...steps {
            let y = Double(i) / Double(steps)
            x += (rng.next01() - 0.5) * 0.16
            pts.append(CGPoint(x: x, y: y))
        }
        return pts
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { ctx in
            scene(t: ctx.date.timeIntervalSinceReferenceDate)
        }
    }

    private func scene(t: TimeInterval) -> some View {
        let cycle = severe ? 2.6 : 3.6
        let phase = t.truncatingRemainder(dividingBy: cycle)

        // Flash envelope. Severe storms double-pulse.
        var flash: Double = 0
        if phase < 0.10 { flash = (1 - phase / 0.10) }
        else if severe && phase > 0.16 && phase < 0.24 { flash = (1 - (phase - 0.16) / 0.08) * 0.7 }
        let flashAlpha = flash * (severe ? 0.78 : 0.55)

        // Bolt fires once per cycle, on its own window, horizontally placed
        // by the cycle index (deterministic, stable per strike).
        let strikeIndex = floor(t / cycle)
        let boltActive = phase < 0.16
        let boltAlpha = boltActive ? (1 - phase / 0.16) : 0
        let xOffset = CGFloat((strikeIndex.truncatingRemainder(dividingBy: 5)) / 5 - 0.5) * 0.4

        return Canvas { gc, size in
            // ── Full-frame strobe ──
            if flashAlpha > 0.01 {
                gc.fill(Path(CGRect(origin: .zero, size: size)),
                        with: .color(tint.opacity(flashAlpha)))
            }
            // ── Drawn forked bolt ──
            if boltAlpha > 0.02 {
                var p = Path()
                for (i, pt) in bolt.enumerated() {
                    let cx = (pt.x + xOffset) * size.width
                    let cy = pt.y * size.height * 0.78
                    if i == 0 { p.move(to: CGPoint(x: cx, y: cy)) }
                    else { p.addLine(to: CGPoint(x: cx, y: cy)) }
                }
                // Soft outer glow.
                gc.stroke(p, with: .color(tint.opacity(boltAlpha * 0.5)),
                          style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                // Bright core.
                gc.stroke(p, with: .color(.white.opacity(boltAlpha)),
                          style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
        .blendMode(.plusLighter)
    }
}

// MARK: - FogVeils — layered translucent banks, opacity sway, drift

private struct FogVeils: View {
    let intensity: Double
    let tint: Color
    var driftSpeed: Double = 0.3
    var animated: Bool = true

    private let veils: [Veil] = (0..<4).map { i in
        var rng = SeededRNG(seed: UInt64(0xF06A + i * 41))
        return Veil(y: 0.25 + rng.next01() * 0.6,
                    scale: 1.2 + rng.next01() * 1.0,
                    speed: 0.4 + rng.next01() * 0.8,
                    phase: rng.next01() * .pi * 2)
    }

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                frame(t: ctx.date.timeIntervalSinceReferenceDate)
            }
        } else {
            frame(t: 0)
        }
    }

    private func frame(t: TimeInterval) -> some View {
        Canvas { gc, size in
            for veil in veils {
                let sway = (sin(t * driftSpeed * veil.speed + veil.phase) + 1) / 2
                let op = (0.30 + 0.50 * sway) * intensity
                let drift = CGFloat(sin(t * driftSpeed * 0.5 * veil.speed + veil.phase)) * size.width * 0.12
                let bandH = size.height * CGFloat(0.30 * veil.scale)
                let cy = CGFloat(veil.y) * size.height + CGFloat(sin(t * driftSpeed * 0.3 + veil.phase)) * 10
                let rect = CGRect(x: -size.width * 0.2 + drift, y: cy - bandH / 2,
                                  width: size.width * 1.4, height: bandH)
                gc.fill(Path(ellipseIn: rect), with: .color(tint.opacity(op)))
            }
            // Soft edge vignette so the fog reads as enveloping.
            gc.fill(Path(CGRect(origin: .zero, size: size)),
                    with: .radialGradient(
                        Gradient(colors: [.clear, tint.opacity(0.25 * intensity)]),
                        center: CGPoint(x: size.width / 2, y: size.height / 2),
                        startRadius: size.width * 0.2, endRadius: size.width * 0.7))
        }
    }

    private struct Veil { let y, scale, speed, phase: Double }
}

// MARK: - WindStreaks — fast horizontal air-motion lines

private struct WindStreaks: View {
    let strength: Double        // 0…1
    var animated: Bool = true

    private let lines: [Line] = (0..<14).map { i in
        var rng = SeededRNG(seed: UInt64(0x817D + i * 47))
        return Line(y: rng.next01() * 0.85,
                    len: 0.18 + rng.next01() * 0.34,
                    speed: 0.4 + rng.next01() * 0.9,
                    phase: rng.next01())
    }

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                frame(t: ctx.date.timeIntervalSinceReferenceDate)
            }
        } else {
            frame(t: 0)
        }
    }

    private func frame(t: TimeInterval) -> some View {
        let count = max(4, Int(Double(lines.count) * (0.4 + strength * 0.6)))
        return Canvas { gc, size in
            for line in lines.prefix(count) {
                let run = (t * line.speed * (0.6 + strength) + line.phase)
                    .truncatingRemainder(dividingBy: 1.3) - 0.15
                let x0 = CGFloat(run) * size.width
                let w = CGFloat(line.len) * size.width
                let y = CGFloat(line.y) * size.height
                var p = Path()
                p.move(to: CGPoint(x: x0, y: y))
                // Slight downward droop so it reads as a gust, not a laser.
                p.addQuadCurve(to: CGPoint(x: x0 + w, y: y + 4),
                               control: CGPoint(x: x0 + w * 0.5, y: y - 3))
                gc.stroke(p, with: .color(.white.opacity(0.10 + strength * 0.18)),
                          style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
        }
    }

    private struct Line { let y, len, speed, phase: Double }
}

// MARK: - SeededRNG — stable xorshift (matches WeatherCard idiom)

/// Tiny deterministic RNG so every particle field lays out identically on
/// every launch and across frames. Seeded ONCE at array build; never called
/// in the per-frame render path.
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

// MARK: - Previews — a representative sweep of the taxonomy

#if DEBUG
/// Build a snapshot with explicit sky-geometry so the preview pins a chosen
/// time-of-day, season, and moon phase without waiting for the clock —
/// using the SAME real model fields the live pipeline populates (latitude
/// for hemisphere/season, an `observedAt` clock instant, an `isNightHint`).
private func skyPreview(code: Int, precip: Int, wind: Int, temp: Int,
                        vis: Int = 10, night: Bool, monthDay: (Int, Int),
                        lat: Double = 40) -> WeatherSnapshot {
    var s = WeatherSnapshot(
        city: "Preview", tempF: temp, windMph: wind, visibilityMi: vis,
        condition: "—", symbol: "cloud.fill",
        nextAlert: nil, accent: .calm
    )
    s.weatherCode = code
    s.precipChancePct = precip
    s.latitude = lat
    s.isNightHint = night
    var comps = DateComponents()
    comps.year = 2026; comps.month = monthDay.0; comps.day = monthDay.1
    comps.hour = night ? 22 : 13
    s.observedAt = Calendar.current.date(from: comps)
    return s
}

#Preview("Thunderstorm · Day · Summer") {
    WeatherSkyView(snapshot: skyPreview(code: 8000, precip: 100, wind: 22, temp: 84, vis: 3,
                                        night: false, monthDay: (7, 15)))
        .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 20)).padding()
        .preferredColorScheme(.dark)
}

#Preview("Clear · Night · Winter (moon + stars)") {
    WeatherSkyView(snapshot: skyPreview(code: 1000, precip: 0, wind: 4, temp: 28,
                                        night: true, monthDay: (1, 20)))
        .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 20)).padding()
        .preferredColorScheme(.dark)
}

#Preview("Heavy Snow · Day · Winter") {
    WeatherSkyView(snapshot: skyPreview(code: 5101, precip: 90, wind: 18, temp: 24,
                                        night: false, monthDay: (1, 10)))
        .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 20)).padding()
        .preferredColorScheme(.dark)
}

#Preview("Hail · Day · Spring") {
    WeatherSkyView(snapshot: skyPreview(code: 7101, precip: 80, wind: 14, temp: 38,
                                        night: false, monthDay: (4, 5)))
        .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 20)).padding()
        .preferredColorScheme(.dark)
}

#Preview("Fog · Night · Autumn") {
    WeatherSkyView(snapshot: skyPreview(code: 2000, precip: 10, wind: 3, temp: 52, vis: 1,
                                        night: true, monthDay: (10, 12)))
        .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 20)).padding()
        .preferredColorScheme(.dark)
}

#Preview("Clear · Night · full moon (reduce motion static)") {
    WeatherSkyView(snapshot: skyPreview(code: 1000, precip: 0, wind: 2, temp: 72,
                                        night: true, monthDay: (6, 21)),
                   animated: false)
        .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 20)).padding()
        .preferredColorScheme(.dark)
}
#endif
