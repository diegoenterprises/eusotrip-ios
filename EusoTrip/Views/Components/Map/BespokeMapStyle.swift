//
//  BespokeMapStyle.swift
//  EusoTrip — cartography style tokens for the in-house ("bespoke") native
//  SwiftUI map renderer that drop-in replaces `HereMapWebViewRepresentable`.
//
//  This is the SINGLE source of truth for every color, width, radius, dash,
//  gradient, and marker dimension the native map paints. The renderer reads
//  ONLY these typed tokens — it never hardcodes a hex or a width.
//
//  Registers:
//    .dark         — shipper / catalyst boards, dark
//    .light        — shipper / catalyst boards, light
//    .cosmos       — driver "Active Enroute" (013), dark / first-person tilt
//    .lightDriver  — driver "Active Enroute" (013), light / first-person tilt
//    .darkRail     — rail "Live Tracking" (003), dark hero
//    .lightRail    — rail "Live Tracking" (003), light hero
//    .nav          — driver turn-by-turn (035/116), dark
//    .lightNav     — driver turn-by-turn (035/116), light
//    .ocean        — vessel ocean route (003), dark
//    .lightOcean   — vessel ocean route (003), light
//    .portApproach — vessel port-approach chart (660), navy in BOTH modes
//
//  Doctrine: basemap and marker proportions derive from the authoritative SVG
//  cartography. The current founder-governed EusoLine contract supersedes old
//  SVG route casings and neutral route strokes: every owned route is one
//  uncased #1473FF → #813FF5 → #BE01FF ribbon. Existing Brand/Theme tokens are
//  reused; only map-specific values are added here.
//
//  Each static register is assembled inside an immediately-invoked closure with
//  intermediate `let` bindings (NOT one giant initializer expression) to keep
//  the Swift type-checker well under its solver budget.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - BespokeMapStyle

/// Typed cartography style tokens for the native map renderer.
///
/// A renderer is constructed with exactly one register and reads the nested
/// token structs to paint each layer, in z-order:
///
///   background → grid → silhouettes (roads/coast) → one continuous route →
///   endpoint markers (origin / dest) → live puck (truck / ping) → pills →
///   container chrome.
///
/// All gradient route stops are the canonical brand sweep
/// (#1473FF → #813FF5 → #BE01FF).
struct BespokeMapStyle {

    // MARK: Nested token types

    /// Page backdrop. Either a linear (top→bottom) or radial gradient.
    struct Background {
        /// Ordered gradient color stops (≥2). Painted top→bottom when
        /// `isRadial == false`, or center-out when `isRadial == true`.
        let stops: [Color]
        /// Normalized stop locations matching `stops` 1:1 (0…1).
        let locations: [Double]
        /// When true the renderer paints a `RadialGradient` using
        /// `radialCenter` + `radialRadius`; otherwise a vertical `LinearGradient`.
        let isRadial: Bool
        /// Radial center in unit space (UnitPoint). Ignored when `!isRadial`.
        let radialCenter: UnitPoint
        /// Radial radius as a fraction of the larger view edge. Ignored when `!isRadial`.
        let radialRadius: Double
    }

    /// Abstract lat/long graticule (straight authored lines at fixed spacing).
    struct Grid {
        let color: Color
        let width: CGFloat
    }

    /// Abstract highway / coastline silhouettes painted UNDER the route.
    ///
    /// Replaces the prior single `Roads` / `Coast` pair. Each register that
    /// shows silhouettes supplies a parallel triple of (color, width) — three
    /// strokes at descending opacity / width that read as layered horizons.
    /// `colors` and `widths` are 1:1 and must be the same length (the renderer
    /// iterates the shorter of the two defensively). When the register has no
    /// silhouettes, `silhouettes` is `nil`.
    struct Silhouettes {
        /// Stroke colors, outermost (faintest/widest) first.
        let colors: [Color]
        /// Stroke widths, 1:1 with `colors`.
        let widths: [CGFloat]
    }

    /// A quiet local endpoint bloom. This is marker chrome only: it never
    /// changes route geometry, progress, camera, or hit testing. Hollow rings
    /// use `.ring` so the map remains visible through a Vessel port center.
    struct EndpointBloom {
        enum Treatment { case disc, ring }

        let radius: CGFloat
        let color: Color
        let opacity: Double
        let treatment: Treatment
        let ringWidth: CGFloat

        init(
            radius: CGFloat,
            color: Color,
            opacity: Double,
            treatment: Treatment = .disc,
            ringWidth: CGFloat = 0
        ) {
            self.radius = radius
            self.color = color
            self.opacity = opacity
            self.treatment = treatment
            self.ringWidth = ringWidth
        }
    }

    /// Origin / destination concentric-circle marker spec.
    ///
    /// When `omitted == true` the renderer paints NOTHING for this endpoint
    /// (e.g. the cosmos register has no origin disc on the map). When
    /// `destPill != nil` the renderer paints a glass pill + diamond glyph for
    /// the destination INSTEAD of the concentric circles (cosmos dest).
    struct EndpointMarker {
        let outerRadius: CGFloat
        let innerRadius: CGFloat
        /// Outer ring fill.
        let outerFill: Color
        /// Inner core fill (solid color path).
        let innerFill: Color
        /// Optional gradient inner fill; when non-nil the renderer prefers
        /// this over `innerFill`.
        let innerGradient: [Color]?
        /// When true the renderer skips this endpoint entirely.
        let omitted: Bool
        /// When non-nil, paint this glass-pill + diamond instead of circles.
        let destPill: DestPill?
        /// OCEAN port-pin ring: when non-nil the renderer paints a genuinely
        /// HOLLOW disc with a thick `ringStroke` at `outerRadius` and skips the
        /// inner core entirely, leaving the underlying water visible.
        /// nil on every non-ocean register (standard concentric behavior).
        let ringStroke: Color?
        /// Ring stroke width for the ocean port pin (ignored when `ringStroke == nil`).
        let ringWidth: CGFloat
        /// Optional gradient for a hollow port ring. `ringStroke` remains the
        /// accessible/degraded fallback when gradients are unavailable.
        let ringGradient: [Color]?
        /// Optional local endpoint bloom painted beneath this marker.
        let bloom: EndpointBloom?
        /// Optional hairline stroke on the OUTER disc of a standard concentric
        /// marker (nav maneuver node: #000000@0.10 light / #FFFFFF@0.14 dark;
        /// 660 dest halo ring: #FFFFFF@0.4 on a clear outer). nil = no stroke.
        let outerStroke: Color?
        /// Outer-disc stroke width (ignored when `outerStroke == nil`).
        let outerStrokeWidth: CGFloat

        init(
            outerRadius: CGFloat,
            innerRadius: CGFloat,
            outerFill: Color,
            innerFill: Color,
            innerGradient: [Color]?,
            omitted: Bool,
            destPill: DestPill?,
            ringStroke: Color? = nil,
            ringWidth: CGFloat = 0,
            ringGradient: [Color]? = nil,
            bloom: EndpointBloom? = nil,
            outerStroke: Color? = nil,
            outerStrokeWidth: CGFloat = 0
        ) {
            self.outerRadius = outerRadius
            self.innerRadius = innerRadius
            self.outerFill = outerFill
            self.innerFill = innerFill
            self.innerGradient = innerGradient
            self.omitted = omitted
            self.destPill = destPill
            self.ringStroke = ringStroke
            self.ringWidth = ringWidth
            self.ringGradient = ringGradient
            self.bloom = bloom
            self.outerStroke = outerStroke
            self.outerStrokeWidth = outerStrokeWidth
        }
    }

    /// Cosmos destination glyph: a glass pill backing + a small rounded
    /// diamond. Used only by the cosmos register's `destMarker`.
    struct DestPill {
        /// Pill fill, e.g. #1C2128@0.85.
        let pillFill: Color
        /// Pill border, e.g. white@0.18.
        let pillBorder: Color
        let pillBorderWidth: CGFloat
        let pillCornerRadius: CGFloat
        /// Diamond side length (square before rotation), e.g. 12.
        let diamondSize: CGFloat
        /// Diamond corner radius, e.g. 2.
        let diamondCornerRadius: CGFloat
        /// Diamond rotation in degrees, e.g. -45.
        let diamondRotation: Double
        /// Diamond gradient fill stops (eusoDiagonal sweep).
        let diamondGradient: [Color]
    }

    /// Live "you are here" puck for the STANDARD registers (.dark / .light):
    /// halo + ring + cab+box glyph. NO status dot (the green only ever appears
    /// in pills/chips, never on the puck).
    struct TruckMarker {
        /// Which live-puck glyph the renderer paints inside the ring.
        enum Glyph {
            /// Cab + box two-rect truck silhouette (standard road registers).
            case cabBox
            /// Solid eusoDiagonal core disc + white hull chevron (the 003 AIS
            /// vessel orb): NO ring stroke / disc, the gradient IS the body.
            case aisHull
            /// Turn-by-turn own-truck puck (035): FLAT eusoDiagonal halo disc
            /// at `haloOpacity` + `ringFill` disc + a heading-up gradient
            /// arrowhead (`M0 -9 L8 9 L0 4 L-8 9 Z` authored at ring r17).
            case navArrow
            /// 660 port-approach AIS vessel: canonical container-vessel
            /// top-down hull (`ringFill` body, `ringStroke` outline, canon
            /// container-slot fills) under a flat #2BE0B0 pulse disc.
            case vesselTopDown
        }
        let haloRadius: CGFloat
        /// Halo fill — gradient stops at low opacity.
        let haloStops: [Color]
        let haloOpacity: Double
        let ringRadius: CGFloat
        /// Ring fill (the disc the glyph sits on). For `.aisHull` this is the
        /// eusoDiagonal-gradient core fill (`coreGradient`), not a flat color.
        let ringFill: Color
        /// Ring stroke color.
        let ringStroke: Color
        let ringWidth: CGFloat
        /// Glyph tint (the cab+box rects, or the hull chevron on `.aisHull`).
        let glyphColor: Color
        /// Which glyph to paint. Defaults to `.cabBox` so existing standard
        /// registers are unchanged; the ocean register selects `.aisHull`.
        let glyph: Glyph
        /// eusoDiagonal core gradient for the `.aisHull` orb body (nil ⇒ ring
        /// stays a flat `ringFill` disc, i.e. the cab+box behavior).
        let coreGradient: [Color]?

        init(
            haloRadius: CGFloat,
            haloStops: [Color],
            haloOpacity: Double,
            ringRadius: CGFloat,
            ringFill: Color,
            ringStroke: Color,
            ringWidth: CGFloat,
            glyphColor: Color,
            glyph: Glyph = .cabBox,
            coreGradient: [Color]? = nil
        ) {
            self.haloRadius = haloRadius
            self.haloStops = haloStops
            self.haloOpacity = haloOpacity
            self.ringRadius = ringRadius
            self.ringFill = ringFill
            self.ringStroke = ringStroke
            self.ringWidth = ringWidth
            self.glyphColor = glyphColor
            self.glyph = glyph
            self.coreGradient = coreGradient
        }
    }

    /// Live "you are here" PING puck for the DRIVER registers (.cosmos /
    /// .lightDriver): soft radial halo + gradient core disc + two concentric
    /// rings. NO chevron, NO status dot.
    struct PingMarker {
        /// Outer pulse halo radius.
        let haloRadius: CGFloat
        /// Halo color (radial center color; fades to clear at the rim).
        let haloColor: Color
        /// Halo center opacity.
        let haloOpacity: Double
        /// Core disc radius.
        let coreRadius: CGFloat
        /// Core disc gradient (eusoDiagonal sweep).
        let coreGradient: [Color]
        /// Inner ring color.
        let ringInnerColor: Color
        let ringInnerWidth: CGFloat
        /// Outer ring color.
        let ringOuterColor: Color
        let ringOuterWidth: CGFloat
    }

    /// Map overlay pill (coordinate readouts, ETA chips, labels).
    struct Pill {
        let fill: Color
        let cornerRadius: CGFloat
        let borderColor: Color
        let borderWidth: CGFloat
        let textPrimary: Color
        let textSecondary: Color
        /// Body text size for pill labels.
        let textSize: CGFloat
        /// Monospaced text size for coordinate readouts.
        let monoTextSize: CGFloat
        /// When true the renderer renders a computed "N MI" scale pill in
        /// addition to the authored `marker.label`. Driver registers only.
        let scalePillEnabled: Bool
    }

    /// Outer map container chrome.
    ///
    /// `square == true` means the renderer must use a square (cornerRadius 0)
    /// full-bleed map band — no rounded clip — and no border. The full-bleed
    /// map band is square in every register per the verbatim spec.
    struct Container {
        let cornerRadius: CGFloat
        let borderColor: Color
        let borderWidth: CGFloat
        /// When true: square corners, no rounded clip, no border.
        let square: Bool
    }

    // MARK: Stored tokens (read by the renderer)

    let background: Background
    let grid: Grid
    /// Layered horizon silhouettes painted under the route (nil = none).
    let silhouettes: Silhouettes?
    let originMarker: EndpointMarker
    let destMarker: EndpointMarker
    /// Standard-register live puck (nil in the driver registers, which use `ping`).
    let truckMarker: TruckMarker?
    /// Driver-register live puck (nil in the standard registers, which use `truckMarker`).
    let ping: PingMarker?
    let pill: Pill
    let container: Container

    // MARK: Brand route sweep (reused tokens)

    /// Canonical route-order gradient: #1473FF → #813FF5 → #BE01FF.
    /// The 52% midpoint is part of the shared iOS/web renderer contract.
    static let routeMidpoint = Color(hex: 0x813FF5)
    static let routeGradientStops: [Color] = [Brand.blue, routeMidpoint, Brand.magenta]
    static let routeGradient = Gradient(stops: [
        .init(color: Brand.blue, location: 0),
        .init(color: routeMidpoint, location: 0.52),
        .init(color: Brand.magenta, location: 1),
    ])

    static func routeGradient(opacity: Double) -> Gradient {
        Gradient(stops: [
            .init(color: Brand.blue.opacity(opacity), location: 0),
            .init(color: routeMidpoint.opacity(opacity), location: 0.52),
            .init(color: Brand.magenta.opacity(opacity), location: 1),
        ])
    }

    /// Canonical full-bleed square container (no border) shared by every
    /// register — the map band is always square per the verbatim spec.
    static let squareContainer = Container(
        cornerRadius: 0,
        borderColor: .clear,
        borderWidth: 0,
        square: true
    )

    // MARK: - DARK  (shipper / catalyst boards, dark)

    static let dark: BespokeMapStyle = {
        // bg: linear vertical gradient #232932 (top) → #05060A (bottom).
        let bg = Background(
            stops: [Color(hex: 0x232932), Color(hex: 0x05060A)],
            locations: [0.0, 1.0],
            isRadial: false,
            radialCenter: .center,
            radialRadius: 0.85
        )
        // grid: white@0.06 stroke 0.8.
        let grid = Grid(color: .white.opacity(0.06), width: 0.8)
        // abstract road silhouettes #3B4148 stroke 0.8.
        let silhouettes = Silhouettes(
            colors: [Color(hex: 0x3B4148)],
            widths: [0.8]
        )
        // origin: outer r6 #1C2128, inner r4 eusoDiagonal gradient.
        let originMarker = EndpointMarker(
            outerRadius: 6, innerRadius: 4,
            outerFill: Color(hex: 0x1C2128),
            innerFill: Brand.blue,
            innerGradient: routeGradientStops,
            omitted: false, destPill: nil,
            bloom: EndpointBloom(
                radius: 16,
                color: Brand.blue,
                opacity: 0.16
            )
        )
        // dest: outer r6 #1C2128, inner r4 #BE01FF.
        let destMarker = EndpointMarker(
            outerRadius: 6, innerRadius: 4,
            outerFill: Color(hex: 0x1C2128),
            innerFill: Brand.magenta,
            innerGradient: nil,
            omitted: false, destPill: nil,
            bloom: EndpointBloom(
                radius: 16,
                color: Brand.magenta,
                opacity: 0.16
            )
        )
        // live truck: halo r22 (eusoDiagonal@0.24) + ring r14 fill #1C2128
        // stroke eusoPrimary w1.6 + cab+box glyph. NO green dot.
        let truck = TruckMarker(
            haloRadius: 22,
            haloStops: routeGradientStops,
            haloOpacity: 0.24,
            ringRadius: 14,
            ringFill: Color(hex: 0x1C2128),
            ringStroke: Brand.blue,
            ringWidth: 1.6,
            glyphColor: .white
        )
        // pills: #1C2128 fill, radius 11, border white@0.12, text #F5F5F7/#AAB2BB.
        let pill = Pill(
            fill: Color(hex: 0x1C2128),
            cornerRadius: 11,
            borderColor: .white.opacity(0.12),
            borderWidth: 1,
            textPrimary: Color(hex: 0xF5F5F7),
            textSecondary: Color(hex: 0xAAB2BB),
            textSize: 10,
            monoTextSize: 10,
            scalePillEnabled: false
        )
        return BespokeMapStyle(
            background: bg,
            grid: grid,
            silhouettes: silhouettes,
            originMarker: originMarker,
            destMarker: destMarker,
            truckMarker: truck,
            ping: nil,
            pill: pill,
            container: squareContainer
        )
    }()

    // MARK: - LIGHT  (shipper / catalyst boards, light)

    static let light: BespokeMapStyle = {
        // bg: shipper/catalyst 2-stop #F4F5F7 → #E9ECF1.
        let bg = Background(
            stops: [Color(hex: 0xF4F5F7), Color(hex: 0xE9ECF1)],
            locations: [0.0, 1.0],
            isRadial: false,
            radialCenter: .center,
            radialRadius: 0.85
        )
        // grid: black@0.06 stroke 0.8.
        let grid = Grid(color: .black.opacity(0.06), width: 0.8)
        // coastlines: #9AA5B5 stroke 0.8 (single silhouette stroke).
        let silhouettes = Silhouettes(
            colors: [Color(hex: 0x9AA5B5)],
            widths: [0.8]
        )
        // origin: outer r6 #FFFFFF, inner r4 eusoDiagonal gradient.
        let originMarker = EndpointMarker(
            outerRadius: 6, innerRadius: 4,
            outerFill: Color(hex: 0xFFFFFF),
            innerFill: Brand.blue,
            innerGradient: routeGradientStops,
            omitted: false, destPill: nil,
            bloom: EndpointBloom(
                radius: 16,
                color: Brand.blue,
                opacity: 0.12
            )
        )
        // dest: outer r6 #FFFFFF, inner r4 #BE01FF solid.
        let destMarker = EndpointMarker(
            outerRadius: 6, innerRadius: 4,
            outerFill: Color(hex: 0xFFFFFF),
            innerFill: Brand.magenta,
            innerGradient: nil,
            omitted: false, destPill: nil,
            bloom: EndpointBloom(
                radius: 16,
                color: Brand.magenta,
                opacity: 0.12
            )
        )
        // live truck: halo r22 @0.18 + ring r9 fill #FFFFFF stroke eusoPrimary
        // w1.6 + cab+box glyph #0D1117. NO green dot.
        let truck = TruckMarker(
            haloRadius: 22,
            haloStops: routeGradientStops,
            haloOpacity: 0.18,
            ringRadius: 14,
            ringFill: Color(hex: 0xFFFFFF),
            ringStroke: Brand.blue,
            ringWidth: 1.6,
            glyphColor: Color(hex: 0x0D1117)
        )
        // labels: glass pills #FFFFFF@0.78 border #0D1117@0.12.
        let pill = Pill(
            fill: Color(hex: 0xFFFFFF, alpha: 0.78),
            cornerRadius: 11,
            borderColor: Color(hex: 0x0D1117, alpha: 0.12),
            borderWidth: 1,
            textPrimary: Color(hex: 0x0D1117),
            textSecondary: Color(hex: 0x52606D),
            textSize: 10,
            monoTextSize: 10,
            scalePillEnabled: false
        )
        return BespokeMapStyle(
            background: bg,
            grid: grid,
            silhouettes: silhouettes,
            originMarker: originMarker,
            destMarker: destMarker,
            truckMarker: truck,
            ping: nil,
            pill: pill,
            container: squareContainer
        )
    }()

    // MARK: - COSMOS  (Driver 013 "Active Enroute", dark — tilt>0 / firstPerson)

    static let cosmos: BespokeMapStyle = {
        // bg radial #0F1626@0 → #0B0F17@0.55 → #07090D@1.0 center(0.6,0.4) r0.85.
        let bg = Background(
            stops: [Color(hex: 0x0F1626), Color(hex: 0x0B0F17), Color(hex: 0x07090D)],
            locations: [0.0, 0.55, 1.0],
            isRadial: true,
            radialCenter: UnitPoint(x: 0.6, y: 0.4),
            radialRadius: 0.85
        )
        // grid white@0.04 width 1.0.
        let grid = Grid(color: .white.opacity(0.04), width: 1.0)
        // 3 highway silhouettes white @0.05/@0.04/@0.035 widths 14/10/8.
        let silhouettes = Silhouettes(
            colors: [.white.opacity(0.05), .white.opacity(0.04), .white.opacity(0.035)],
            widths: [14, 10, 8]
        )
        // NO origin disc on the map (013 has none).
        let originMarker = EndpointMarker(
            outerRadius: 0, innerRadius: 0,
            outerFill: .clear,
            innerFill: .clear,
            innerGradient: nil,
            omitted: true, destPill: nil
        )
        // dest = glass pill (#1C2128@0.85, border white@0.18, rx11) + 12×12
        // rounded-2 diamond eusoDiagonal rotated −45°.
        let destPill = DestPill(
            pillFill: Color(hex: 0x1C2128, alpha: 0.85),
            pillBorder: .white.opacity(0.18),
            pillBorderWidth: 1,
            pillCornerRadius: 11,
            diamondSize: 12,
            diamondCornerRadius: 2,
            diamondRotation: -45,
            diamondGradient: routeGradientStops
        )
        let destMarker = EndpointMarker(
            outerRadius: 0, innerRadius: 0,
            outerFill: .clear,
            innerFill: .clear,
            innerGradient: nil,
            omitted: false, destPill: destPill
        )
        // ping: halo r26 radial #1473FF@0.75→0; core r9 eusoDiagonal disc;
        // rings #05060A w2 + #FFFFFF@0.45 w0.5. NO green dot, NO chevron.
        let ping = PingMarker(
            haloRadius: 26,
            haloColor: Brand.blue,
            haloOpacity: 0.75,
            coreRadius: 9,
            coreGradient: routeGradientStops,
            ringInnerColor: Color(hex: 0x05060A),
            ringInnerWidth: 2,
            ringOuterColor: .white.opacity(0.45),
            ringOuterWidth: 0.5
        )
        // pills: #1C2128@0.85 fill, border white@0.18; authored label + scale pill.
        let pill = Pill(
            fill: Color(hex: 0x1C2128, alpha: 0.85),
            cornerRadius: 11,
            borderColor: .white.opacity(0.18),
            borderWidth: 1,
            textPrimary: Color(hex: 0xF5F5F7),
            textSecondary: Color(hex: 0xAAB2BB),
            textSize: 10,
            monoTextSize: 10,
            scalePillEnabled: true
        )
        return BespokeMapStyle(
            background: bg,
            grid: grid,
            silhouettes: silhouettes,
            originMarker: originMarker,
            destMarker: destMarker,
            truckMarker: nil,
            ping: ping,
            pill: pill,
            container: squareContainer
        )
    }()

    // MARK: - LIGHT DRIVER  (Driver 013 "Active Enroute", light — tilt>0 / firstPerson)

    static let lightDriver: BespokeMapStyle = {
        // bg 3-stop #E9F0F8@0 → #EFF3F7@0.5 → #F2F4F6@1.0.
        let bg = Background(
            stops: [Color(hex: 0xE9F0F8), Color(hex: 0xEFF3F7), Color(hex: 0xF2F4F6)],
            locations: [0.0, 0.5, 1.0],
            isRadial: false,
            radialCenter: .center,
            radialRadius: 0.85
        )
        // grid #0D1117@0.045 width 1.0.
        let grid = Grid(color: Color(hex: 0x0D1117, alpha: 0.045), width: 1.0)
        // 3 silhouettes #0D1117 @0.06/@0.05/@0.04 widths 14/10/8 (NOT coastlines).
        let silhouettes = Silhouettes(
            colors: [
                Color(hex: 0x0D1117, alpha: 0.06),
                Color(hex: 0x0D1117, alpha: 0.05),
                Color(hex: 0x0D1117, alpha: 0.04)
            ],
            widths: [14, 10, 8]
        )
        // NO origin disc (driver register mirrors cosmos: none on the map).
        let originMarker = EndpointMarker(
            outerRadius: 0, innerRadius: 0,
            outerFill: .clear,
            innerFill: .clear,
            innerGradient: nil,
            omitted: true, destPill: nil
        )
        // dest = light glass pill + diamond (light-tuned chrome).
        let destPill = DestPill(
            pillFill: Color(hex: 0xFFFFFF, alpha: 0.85),
            pillBorder: Color(hex: 0x0D1117, alpha: 0.12),
            pillBorderWidth: 1,
            pillCornerRadius: 11,
            diamondSize: 12,
            diamondCornerRadius: 2,
            diamondRotation: -45,
            diamondGradient: routeGradientStops
        )
        let destMarker = EndpointMarker(
            outerRadius: 0, innerRadius: 0,
            outerFill: .clear,
            innerFill: .clear,
            innerGradient: nil,
            omitted: false, destPill: destPill
        )
        // ping: halo r22 #1473FF@0.55, core r9 eusoDiagonal,
        // rings #E9ECF1 w2 + #1473FF@0.45 w0.5.
        let ping = PingMarker(
            haloRadius: 22,
            haloColor: Brand.blue,
            haloOpacity: 0.55,
            coreRadius: 9,
            coreGradient: routeGradientStops,
            ringInnerColor: Color(hex: 0xE9ECF1),
            ringInnerWidth: 2,
            ringOuterColor: Brand.blue.opacity(0.45),
            ringOuterWidth: 0.5
        )
        // pills: light glass + scale pill.
        let pill = Pill(
            fill: Color(hex: 0xFFFFFF, alpha: 0.85),
            cornerRadius: 11,
            borderColor: Color(hex: 0x0D1117, alpha: 0.12),
            borderWidth: 1,
            textPrimary: Color(hex: 0x0D1117),
            textSecondary: Color(hex: 0x52606D),
            textSize: 10,
            monoTextSize: 10,
            scalePillEnabled: true
        )
        return BespokeMapStyle(
            background: bg,
            grid: grid,
            silhouettes: silhouettes,
            originMarker: originMarker,
            destMarker: destMarker,
            truckMarker: nil,
            ping: ping,
            pill: pill,
            container: squareContainer
        )
    }()

    // MARK: - LIGHT RAIL  (Rail 003 "Live Tracking", light hero)
    //
    // Inherits the 003 Rail basemap and endpoint proportions. The runtime
    // route applies the newer binding EusoLine-only contract, including the
    // planned remainder; the old flat rail-gray route stroke is not rendered.

    static let lightRail: BespokeMapStyle = {
        let base = light
        // bg: rail hero 2-stop #F4F5F7 → #E6EAF0.
        let bg = Background(
            stops: [Color(hex: 0xF4F5F7), Color(hex: 0xE6EAF0)],
            locations: [0.0, 1.0],
            isRadial: false,
            radialCenter: .center,
            radialRadius: 0.85
        )
        // 003 Rail terminal grammar: a larger white shell and 5.5 pt core.
        // The local bloom reads as a terminal node, never extra topology.
        let originMarker = EndpointMarker(
            outerRadius: 7.5, innerRadius: 5.5,
            outerFill: .white,
            innerFill: Brand.blue,
            innerGradient: routeGradientStops,
            omitted: false, destPill: nil,
            bloom: EndpointBloom(radius: 15, color: Brand.blue, opacity: 0.11)
        )
        let destMarker = EndpointMarker(
            outerRadius: 7.5, innerRadius: 5.5,
            outerFill: .white,
            innerFill: Brand.magenta,
            innerGradient: nil,
            omitted: false, destPill: nil,
            bloom: EndpointBloom(radius: 15, color: Brand.magenta, opacity: 0.11)
        )
        return BespokeMapStyle(
            background: bg,
            grid: base.grid,
            silhouettes: base.silhouettes,
            originMarker: originMarker,
            destMarker: destMarker,
            truckMarker: base.truckMarker,
            ping: base.ping,
            pill: base.pill,
            container: base.container
        )
    }()

    // MARK: - DARK RAIL  (Rail 003 "Live Tracking", dark hero)
    //
    // Dark 003 Rail basemap and terminal proportions, with the same binding
    // EusoLine-only route contract as Light.

    static let darkRail: BespokeMapStyle = {
        let base = dark
        // bg: rail dark hero 2-stop #11161D → #0A0D12.
        let bg = Background(
            stops: [Color(hex: 0x11161D), Color(hex: 0x0A0D12)],
            locations: [0.0, 1.0],
            isRadial: false,
            radialCenter: .center,
            radialRadius: 0.85
        )
        let originMarker = EndpointMarker(
            outerRadius: 7.5, innerRadius: 5.5,
            outerFill: .white,
            innerFill: Brand.blue,
            innerGradient: routeGradientStops,
            omitted: false, destPill: nil,
            bloom: EndpointBloom(radius: 15, color: Brand.blue, opacity: 0.14)
        )
        let destMarker = EndpointMarker(
            outerRadius: 7.5, innerRadius: 5.5,
            outerFill: .white,
            innerFill: Brand.magenta,
            innerGradient: nil,
            omitted: false, destPill: nil,
            bloom: EndpointBloom(radius: 15, color: Brand.magenta, opacity: 0.14)
        )
        return BespokeMapStyle(
            background: bg,
            grid: base.grid,
            silhouettes: base.silhouettes,
            originMarker: originMarker,
            destMarker: destMarker,
            truckMarker: base.truckMarker,
            ping: base.ping,
            pill: base.pill,
            container: base.container
        )
    }()

    // MARK: - OCEAN  (Vessel 003 "Live Tracking", dark — sourced ocean route)
    //
    // VERBATIM from `06 Vessel/Dark-SVG/003 Vessel Live Tracking.svg` (the
    // 2026-06-02 LIVE SUPER-INTELLIGENCE recon — _MAP_DESIGN_LANGUAGE
    // 2026-06-09 §1a/§1b/§2). The map card is a stylized ocean
    // schematic: a deep navy basemap (#0C1A2A → #0A1320), three faint
    // white@0.07 latitude lines, two #27425E@0.8 coast hints, one owned
    // gradient route, hollow port rings (origin eusoPrimary / destination
    // #6E7681), the AIS vessel orb (r20 #BE01FF@0.22 glow + r11 eusoDiagonal
    // core + white hull chevron), and the location callout chip (#1C2128,
    // #6E7681 mono coords / #F5F5F7 speed·hdg).

    static let ocean: BespokeMapStyle = {
        // basemap: navy wash #0C1A2A (top) → #0A1320 (bottom) — 003 recon.
        let bg = Background(
            stops: [Color(hex: 0x0C1A2A), Color(hex: 0x0A1320)],
            locations: [0.0, 1.0],
            isRadial: false,
            radialCenter: .center,
            radialRadius: 0.85
        )
        // latitude grid: white@0.07 stroke 1.
        let grid = Grid(color: .white.opacity(0.07), width: 1)
        // coast hints: #27425E@0.8 stroke 1.5.
        let silhouettes = Silhouettes(
            colors: [Color(hex: 0x27425E, alpha: 0.8)],
            widths: [1.5]
        )
        // 003 Vessel port grammar: hollow 6.5 pt rings. The restrained ring
        // bloom stays outside the port center, so navigable water remains
        // visible through it.
        let originMarker = EndpointMarker(
            outerRadius: 6.5, innerRadius: 0,
            outerFill: Color(hex: 0x0D0E1A),
            innerFill: .clear,
            innerGradient: nil,
            omitted: false, destPill: nil,
            ringStroke: Brand.blue, ringWidth: 3,
            ringGradient: routeGradientStops,
            bloom: EndpointBloom(
                radius: 13,
                color: Brand.blue,
                opacity: 0.13,
                treatment: .ring,
                ringWidth: 5
            )
        )
        // Destination remains a neutral hollow port ring until arrival.
        let destMarker = EndpointMarker(
            outerRadius: 6.5, innerRadius: 0,
            outerFill: Color(hex: 0x0D0E1A),
            innerFill: .clear,
            innerGradient: nil,
            omitted: false, destPill: nil,
            ringStroke: Color(hex: 0x6E7681), ringWidth: 3,
            bloom: EndpointBloom(
                radius: 13,
                color: Color(hex: 0x6E7681),
                opacity: 0.12,
                treatment: .ring,
                ringWidth: 5
            )
        )
        // AIS vessel orb: halo r20 #BE01FF@0.22 + r11 eusoDiagonal core +
        // white hull chevron. ringStroke/ringWidth are unused for .aisHull.
        let ais = TruckMarker(
            haloRadius: 20,
            haloStops: [Brand.magenta, Brand.magenta],
            haloOpacity: 0.22,
            ringRadius: 11,
            ringFill: Brand.magenta,
            ringStroke: .clear,
            ringWidth: 0,
            glyphColor: .white,
            glyph: .aisHull,
            coreGradient: routeGradientStops
        )
        // callout chip: #1C2128, mono coords #6E7681 / body #F5F5F7.
        let pill = Pill(
            fill: Color(hex: 0x1C2128),
            cornerRadius: 8,
            borderColor: .clear,
            borderWidth: 0,
            textPrimary: Color(hex: 0xF5F5F7),
            textSecondary: Color(hex: 0x6E7681),
            textSize: 11,
            monoTextSize: 9,
            scalePillEnabled: false
        )
        return BespokeMapStyle(
            background: bg,
            grid: grid,
            silhouettes: silhouettes,
            originMarker: originMarker,
            destMarker: destMarker,
            truckMarker: ais,
            ping: nil,
            pill: pill,
            container: squareContainer
        )
    }()

    // MARK: - LIGHT OCEAN  (Vessel 003 "Live Tracking", light)
    //
    // VERBATIM from `06 Vessel/Light-SVG/003 Vessel Live Tracking.svg` (the
    // 2026-06-02 recon — _MAP_DESIGN_LANGUAGE 2026-06-09 §1a/§2). Same
    // sourced-route schematic on a light water basemap: #DCEAF7 → #C3D8EC,
    // white@0.55 latitude lines, #9DB4C9@0.7 coast hints, one owned gradient
    // route, hollow port rings (origin eusoPrimary / destination #8A96A3),
    // the AIS orb (r20 #BE01FF@0.18 glow + r11 core +
    // hull), and the #FFFFFF callout chip (#8A96A3 mono / #0D1117 speed·hdg).

    static let lightOcean: BespokeMapStyle = {
        // water basemap: #DCEAF7 (top) → #C3D8EC (bottom) — 003 recon.
        let bg = Background(
            stops: [Color(hex: 0xDCEAF7), Color(hex: 0xC3D8EC)],
            locations: [0.0, 1.0],
            isRadial: false,
            radialCenter: .center,
            radialRadius: 0.85
        )
        // latitude grid: white@0.55 stroke 1.
        let grid = Grid(color: .white.opacity(0.55), width: 1)
        // coast hints: #9DB4C9@0.7 stroke 2.
        let silhouettes = Silhouettes(
            colors: [Color(hex: 0x9DB4C9, alpha: 0.7)],
            widths: [2]
        )
        // Hollow 003 port rings; ring-only blooms keep water visible.
        let originMarker = EndpointMarker(
            outerRadius: 6.5, innerRadius: 0,
            outerFill: Color(hex: 0xFFFFFF),
            innerFill: .clear,
            innerGradient: nil,
            omitted: false, destPill: nil,
            ringStroke: Brand.blue, ringWidth: 3,
            ringGradient: routeGradientStops,
            bloom: EndpointBloom(
                radius: 13,
                color: Brand.blue,
                opacity: 0.10,
                treatment: .ring,
                ringWidth: 5
            )
        )
        // Destination is neutral until the source-backed arrival state.
        let destMarker = EndpointMarker(
            outerRadius: 6.5, innerRadius: 0,
            outerFill: Color(hex: 0xFFFFFF),
            innerFill: .clear,
            innerGradient: nil,
            omitted: false, destPill: nil,
            ringStroke: Color(hex: 0x8A96A3), ringWidth: 3,
            bloom: EndpointBloom(
                radius: 13,
                color: Color(hex: 0x8A96A3),
                opacity: 0.10,
                treatment: .ring,
                ringWidth: 5
            )
        )
        // AIS vessel orb: halo r20 #BE01FF@0.18 + r11 eusoDiagonal + hull.
        let ais = TruckMarker(
            haloRadius: 20,
            haloStops: [Brand.magenta, Brand.magenta],
            haloOpacity: 0.18,
            ringRadius: 11,
            ringFill: Brand.magenta,
            ringStroke: .clear,
            ringWidth: 0,
            glyphColor: .white,
            glyph: .aisHull,
            coreGradient: routeGradientStops
        )
        // callout chip: #FFFFFF, mono coords #8A96A3 / body #0D1117.
        let pill = Pill(
            fill: Color(hex: 0xFFFFFF),
            cornerRadius: 8,
            borderColor: .clear,
            borderWidth: 0,
            textPrimary: Color(hex: 0x0D1117),
            textSecondary: Color(hex: 0x8A96A3),
            textSize: 11,
            monoTextSize: 9,
            scalePillEnabled: false
        )
        return BespokeMapStyle(
            background: bg,
            grid: grid,
            silhouettes: silhouettes,
            originMarker: originMarker,
            destMarker: destMarker,
            truckMarker: ais,
            ping: nil,
            pill: pill,
            container: squareContainer
        )
    }()

    // MARK: - NAV  (Driver 035/116 turn-by-turn, dark)
    //
    // VERBATIM from `01 Driver/Dark-SVG/035 En Route Drive.svg`: bg #0B0C16 →
    // #07070F, road grid white@0.05 w1 (73pt cols / 96pt rows), raised dark
    // road ribbons #161B27 w9, the uncased active EusoLine gradient w9
    // (single solid leg — the maneuver node terminates it), the
    // upcoming-maneuver node (r9 #0D0E1A + white@0.14 hairline + r4.5 #BE01FF
    // core), and the own-truck puck (r26 eusoDiagonal@0.20 flat halo + r17
    // #0D0E1A disc + eusoDiagonal heading-up arrowhead).

    static let nav: BespokeMapStyle = {
        // bg: linear #0B0C16 (top) → #07070F (bottom).
        let bg = Background(
            stops: [Color(hex: 0x0B0C16), Color(hex: 0x07070F)],
            locations: [0.0, 1.0],
            isRadial: false,
            radialCenter: .center,
            radialRadius: 0.85
        )
        // road grid hint: white@0.05 stroke 1.
        let grid = Grid(color: .white.opacity(0.05), width: 1)
        // road ribbons: #161B27 stroke 9 round (raised dark ribbons).
        let silhouettes = Silhouettes(
            colors: [Color(hex: 0x161B27)],
            widths: [9]
        )
        // NO origin disc on the nav map (035 has none).
        let originMarker = EndpointMarker(
            outerRadius: 0, innerRadius: 0,
            outerFill: .clear,
            innerFill: .clear,
            innerGradient: nil,
            omitted: true, destPill: nil
        )
        // dest = upcoming maneuver node: r9 #0D0E1A (white@0.14 hairline) +
        // r4.5 #BE01FF core.
        let destMarker = EndpointMarker(
            outerRadius: 9, innerRadius: 4.5,
            outerFill: Color(hex: 0x0D0E1A),
            innerFill: Brand.magenta,
            innerGradient: nil,
            omitted: false, destPill: nil,
            outerStroke: .white.opacity(0.14),
            outerStrokeWidth: 1
        )
        // own-truck puck: flat halo r26 eusoDiagonal@0.20 + r17 #0D0E1A disc
        // (white@0.14 hairline) + eusoDiagonal heading-up arrowhead.
        let truck = TruckMarker(
            haloRadius: 26,
            haloStops: routeGradientStops,
            haloOpacity: 0.20,
            ringRadius: 17,
            ringFill: Color(hex: 0x0D0E1A),
            ringStroke: .white.opacity(0.14),
            ringWidth: 1,
            glyphColor: .white,
            glyph: .navArrow,
            coreGradient: routeGradientStops
        )
        // pills: 035 dark card chrome — #0D0E1A, border white@0.08.
        let pill = Pill(
            fill: Color(hex: 0x0D0E1A),
            cornerRadius: 11,
            borderColor: .white.opacity(0.08),
            borderWidth: 1,
            textPrimary: Color(hex: 0xF5F5F7),
            textSecondary: Color(hex: 0xAAB2BB),
            textSize: 10,
            monoTextSize: 10,
            scalePillEnabled: false
        )
        return BespokeMapStyle(
            background: bg,
            grid: grid,
            silhouettes: silhouettes,
            originMarker: originMarker,
            destMarker: destMarker,
            truckMarker: truck,
            ping: nil,
            pill: pill,
            container: squareContainer
        )
    }()

    // MARK: - LIGHT NAV  (Driver 035/116 turn-by-turn, light)
    //
    // VERBATIM from `01 Driver/Light-SVG/035 En Route Drive.svg`: bg #F4F5F7 →
    // #E2E6EC, road grid black@0.05 w1, road ribbons #FFFFFF w9 with a
    // #000000@0.05 w9 tint pass on the SAME geometry (grey ribbons), an
    // uncased eusoPrimary route w9, maneuver node (r9 #FFFFFF +
    // black@0.10 hairline + r4.5 #BE01FF), own-truck puck (r26 @0.16 halo +
    // r17 #FFFFFF disc + eusoDiagonal arrowhead).

    static let lightNav: BespokeMapStyle = {
        // bg: linear #F4F5F7 (top) → #E2E6EC (bottom).
        let bg = Background(
            stops: [Color(hex: 0xF4F5F7), Color(hex: 0xE2E6EC)],
            locations: [0.0, 1.0],
            isRadial: false,
            radialCenter: .center,
            radialRadius: 0.85
        )
        // road grid hint: black@0.05 stroke 1.
        let grid = Grid(color: .black.opacity(0.05), width: 1)
        // road ribbons: #FFFFFF w9 + #000000@0.05 w9 painted over the SAME
        // paths (the renderer's nav branch strokes them in order, un-staggered).
        let silhouettes = Silhouettes(
            colors: [Color(hex: 0xFFFFFF), .black.opacity(0.05)],
            widths: [9, 9]
        )
        // NO origin disc on the nav map.
        let originMarker = EndpointMarker(
            outerRadius: 0, innerRadius: 0,
            outerFill: .clear,
            innerFill: .clear,
            innerGradient: nil,
            omitted: true, destPill: nil
        )
        // dest = maneuver node: r9 #FFFFFF (black@0.10 hairline) + r4.5 #BE01FF.
        let destMarker = EndpointMarker(
            outerRadius: 9, innerRadius: 4.5,
            outerFill: Color(hex: 0xFFFFFF),
            innerFill: Brand.magenta,
            innerGradient: nil,
            omitted: false, destPill: nil,
            outerStroke: .black.opacity(0.10),
            outerStrokeWidth: 1
        )
        // own-truck puck: flat halo r26 eusoDiagonal@0.16 + r17 #FFFFFF disc
        // (#0D1117@0.10 hairline) + eusoDiagonal heading-up arrowhead.
        let truck = TruckMarker(
            haloRadius: 26,
            haloStops: routeGradientStops,
            haloOpacity: 0.16,
            ringRadius: 17,
            ringFill: Color(hex: 0xFFFFFF),
            ringStroke: Color(hex: 0x0D1117, alpha: 0.10),
            ringWidth: 1,
            glyphColor: Color(hex: 0x0D1117),
            glyph: .navArrow,
            coreGradient: routeGradientStops
        )
        // pills: light glass — #FFFFFF, border #000000@0.10 (§4 ETA pill).
        let pill = Pill(
            fill: Color(hex: 0xFFFFFF),
            cornerRadius: 11,
            borderColor: .black.opacity(0.10),
            borderWidth: 1,
            textPrimary: Color(hex: 0x0D1117),
            textSecondary: Color(hex: 0x52606D),
            textSize: 10,
            monoTextSize: 10,
            scalePillEnabled: false
        )
        return BespokeMapStyle(
            background: bg,
            grid: grid,
            silhouettes: silhouettes,
            originMarker: originMarker,
            destMarker: destMarker,
            truckMarker: truck,
            ping: nil,
            pill: pill,
            container: squareContainer
        )
    }()

    // MARK: - PORT APPROACH  (Vessel 660 "Live Position" — navy in BOTH modes)
    //
    // VERBATIM from `06 Vessel/Light-SVG/660 Vessel Live Position.svg` (the
    // 660 chart is deep navy even in Light — _MAP_DESIGN_LANGUAGE 2026-06-09
    // §1a/§7 delta 14): #0E1726 panel, #1B3050 w1 grid (72pt cols / 32pt
    // rows), landmass #15233A with #27406A w1.3 coastline, the eusoPrimary
    // w2.6 approach polyline with the #5570A0@0.7 w2.2 dash [3,4] history
    // wake, white port pins (origin r4 / dest r4.5 + white@0.4 halo ring r8),
    // the canonical container-vessel top-down hull (#0B1220 / #5FE0C0 1.2 +
    // canon slot fills) under the #2BE0B0@0.35 AIS pulse, and the #0B1220
    // AIS-tinted micro-chip (#2BE0B0 border@0.5 / #B9D4F2 mono).

    static let portApproach: BespokeMapStyle = {
        // panel: solid #0E1726 (no gradient — same in Light and Dark).
        let bg = Background(
            stops: [Color(hex: 0x0E1726), Color(hex: 0x0E1726)],
            locations: [0.0, 1.0],
            isRadial: false,
            radialCenter: .center,
            radialRadius: 0.85
        )
        // chart grid: #1B3050 stroke 1.
        let grid = Grid(color: Color(hex: 0x1B3050), width: 1)
        // no abstract silhouettes — the landmass renders via the basemap
        // rings (#15233A fill / #27406A w1.3 coast, renderer port flags).
        // origin port pin: solid #FFFFFF r4 disc.
        let originMarker = EndpointMarker(
            outerRadius: 4, innerRadius: 0,
            outerFill: Color(hex: 0xFFFFFF),
            innerFill: .clear,
            innerGradient: nil,
            omitted: false, destPill: nil
        )
        // dest port pin: #FFFFFF r4.5 core + white@0.4 halo ring r8.
        let destMarker = EndpointMarker(
            outerRadius: 8, innerRadius: 4.5,
            outerFill: .clear,
            innerFill: Color(hex: 0xFFFFFF),
            innerGradient: nil,
            omitted: false, destPill: nil,
            outerStroke: .white.opacity(0.4),
            outerStrokeWidth: 1
        )
        // AIS vessel: canonical container-vessel top-down hull — #0B1220 body,
        // #5FE0C0 stroke 1.2, half-length 14 — under the flat #2BE0B0@0.35
        // pulse disc (r7→15 over 2.4 s, renderer-driven). Bridge #F5F5F7.
        let ais = TruckMarker(
            haloRadius: 15,
            haloStops: [Color(hex: 0x2BE0B0), Color(hex: 0x2BE0B0)],
            haloOpacity: 0.35,
            ringRadius: 14,
            ringFill: Color(hex: 0x0B1220),
            ringStroke: Color(hex: 0x5FE0C0),
            ringWidth: 1.2,
            glyphColor: Color(hex: 0xF5F5F7),
            glyph: .vesselTopDown
        )
        // micro-chip: #0B1220 fill rx8.5, #2BE0B0@0.5 border, status-tinted
        // 8/800 text (#2BE0B0) with #B9D4F2 mono secondary.
        let pill = Pill(
            fill: Color(hex: 0x0B1220),
            cornerRadius: 8.5,
            borderColor: Color(hex: 0x2BE0B0, alpha: 0.5),
            borderWidth: 1,
            textPrimary: Color(hex: 0x2BE0B0),
            textSecondary: Color(hex: 0xB9D4F2),
            textSize: 8,
            monoTextSize: 8,
            scalePillEnabled: false
        )
        return BespokeMapStyle(
            background: bg,
            grid: grid,
            silhouettes: nil,
            originMarker: originMarker,
            destMarker: destMarker,
            truckMarker: ais,
            ping: nil,
            pill: pill,
            container: squareContainer
        )
    }()

    // MARK: - Light decoration tokens (breadcrumbs / hazard glyphs)
    //
    // Surfaced as static tokens because they're sprinkled along the route
    // rather than being a single layer the renderer reads per-style.

    /// Breadcrumb dots dropped along a traveled light route: #1473FF@0.55 r2.5.
    static let lightBreadcrumbColor  = Brand.blue.opacity(0.55)
    static let lightBreadcrumbRadius: CGFloat = 2.5

    /// Hazmat diamond glyph: #FFB100 stroke 1.4 rotated 45°. (== Brand.hazmat)
    static let hazmatColor  = Brand.hazmat            // #FFB100
    static let hazmatStroke: CGFloat = 1.4

    /// Reefer snowflake glyph: #1473FF stroke 1.4. (== Brand.blue)
    static let reeferColor  = Brand.blue
    static let reeferStroke: CGFloat = 1.4

    // MARK: - Resolver

    /// Picks the standard cartography register for a renderer's `isDark` flag.
    /// The driver registers (`.cosmos` / `.lightDriver`) are selected by the
    /// renderer when `tilt > 0 || firstPerson` — see `driver(isDark:)`.
    static func standard(isDark: Bool) -> BespokeMapStyle {
        isDark ? .dark : .light
    }

    /// Picks the DRIVER ("Active Enroute") register for a renderer's `isDark`
    /// flag. The renderer must call this (NOT `standard`) whenever
    /// `tilt > 0 || firstPerson`.
    static func driver(isDark: Bool) -> BespokeMapStyle {
        isDark ? .cosmos : .lightDriver
    }

    /// Picks the OCEAN ("Vessel Live Tracking" / 003) register for a renderer's
    /// `isDark` flag. The renderer must call this (NOT `standard`) when the
    /// caller signals the ocean route surface via `style: .ocean`.
    static func ocean(isDark: Bool) -> BespokeMapStyle {
        isDark ? .ocean : .lightOcean
    }

    /// Picks the RAIL ("Rail Live Tracking" / 003) hero register for a
    /// renderer's `isDark` flag. Callers signal the rail surface via
    /// `style: .rail`.
    static func rail(isDark: Bool) -> BespokeMapStyle {
        isDark ? .darkRail : .lightRail
    }

    /// Picks the turn-by-turn NAV register (035/116) for a renderer's
    /// `isDark` flag. Callers signal the nav surface via `style: .nav`.
    static func nav(isDark: Bool) -> BespokeMapStyle {
        isDark ? .nav : .lightNav
    }
}
