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
//    .dark        — shipper / catalyst boards, dark
//    .light       — shipper / catalyst boards, light
//    .cosmos      — driver "Active Enroute" (013), dark / first-person tilt
//    .lightDriver — driver "Active Enroute" (013), light / first-person tilt
//    .lightRail   — rail light skin (background-only swap off .light)
//
//  Doctrine: every value below is reproduced VERBATIM from the SVG cartography
//  spec (design-authority ground truth, per _MAP_VERBATIM_FIXSPEC.md). Where a
//  token already exists in `Theme/DesignSystem.swift` (Brand.*, Color(hex:))
//  it is REUSED; only map-specific values are added here.
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
///   background → grid → silhouettes (roads/coast) → route (pending, active) →
///   endpoint markers (origin / dest) → live puck (truck / ping) → pills →
///   container chrome.
///
/// All gradient route stops are the canonical brand sweep
/// (#1473FF → #BE01FF == `Brand.blue` → `Brand.magenta`).
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

    /// The traveled ("active") portion of a route — solid, round-capped,
    /// painted with the brand gradient. The gradient direction is FIXED in
    /// map space (bottom-leading → top-trailing), NOT first→last polyline point.
    struct RouteActive {
        /// Gradient stops painted bottom-leading → top-trailing.
        let stops: [Color]
        let width: CGFloat
    }

    /// The remaining ("pending") portion of a route — dashed, round-capped.
    /// Painted either as a faded gradient (`stops`) or a flat `color`.
    struct RoutePending {
        /// Flat fallback color (used when `stops == nil`).
        let color: Color
        /// Optional faded gradient stops; when non-nil the renderer prefers
        /// these over `color`. Gradient direction matches `RouteActive`.
        let stops: [Color]?
        let width: CGFloat
        /// Dash pattern in points, e.g. [2, 4]. Pairs with round caps.
        let dashPattern: [CGFloat]
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
        /// OCEAN port-pin ring: when non-nil the renderer paints a HOLLOW disc
        /// (filled `outerFill` = page bg) with a thick `ringStroke` ring of
        /// `ringWidth` AT `outerRadius`, and skips the inner core entirely
        /// (matches the 003 origin/dest port pins: `fill=#05060A stroke=… w3`).
        /// nil on every non-ocean register (standard concentric behavior).
        let ringStroke: Color?
        /// Ring stroke width for the ocean port pin (ignored when `ringStroke == nil`).
        let ringWidth: CGFloat

        init(
            outerRadius: CGFloat,
            innerRadius: CGFloat,
            outerFill: Color,
            innerFill: Color,
            innerGradient: [Color]?,
            omitted: Bool,
            destPill: DestPill?,
            ringStroke: Color? = nil,
            ringWidth: CGFloat = 0
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
    let routeActive: RouteActive
    let routePending: RoutePending
    let originMarker: EndpointMarker
    let destMarker: EndpointMarker
    /// Standard-register live puck (nil in the driver registers, which use `ping`).
    let truckMarker: TruckMarker?
    /// Driver-register live puck (nil in the standard registers, which use `truckMarker`).
    let ping: PingMarker?
    let pill: Pill
    let container: Container

    // MARK: Brand route sweep (reused tokens)

    /// Canonical traveled-route gradient: #1473FF → #BE01FF.
    /// Reuses `Brand.blue` / `Brand.magenta` from DesignSystem.swift.
    static let routeGradientStops: [Color] = [Brand.blue, Brand.magenta]

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
        // ROUTE traveled: gradient #1473FF→#BE01FF stroke 3 solid round.
        let routeActive = RouteActive(stops: routeGradientStops, width: 3)
        // ROUTE remaining: 222 Dark past-trail — gradient @0.50 stroke 2 dash [2,4] round.
        let routePending = RoutePending(
            color: Color(hex: 0x6E7681),
            stops: [Brand.blue.opacity(0.50), Brand.magenta.opacity(0.50)],
            width: 2,
            dashPattern: [2, 4]
        )
        // origin: outer r6 #1C2128, inner r4 eusoDiagonal gradient.
        let originMarker = EndpointMarker(
            outerRadius: 6, innerRadius: 4,
            outerFill: Color(hex: 0x1C2128),
            innerFill: Brand.blue,
            innerGradient: routeGradientStops,
            omitted: false, destPill: nil
        )
        // dest: outer r6 #1C2128, inner r4 #BE01FF.
        let destMarker = EndpointMarker(
            outerRadius: 6, innerRadius: 4,
            outerFill: Color(hex: 0x1C2128),
            innerFill: Brand.magenta,
            innerGradient: nil,
            omitted: false, destPill: nil
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
            routeActive: routeActive,
            routePending: routePending,
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
        // ROUTE active: #1473FF→#BE01FF stroke 3 solid round.
        let routeActive = RouteActive(stops: routeGradientStops, width: 3)
        // ROUTE pending: eusoPrimary GRADIENT @0.45 dash [2,4] width 2.
        let routePending = RoutePending(
            color: Color(hex: 0x8A96A3),
            stops: [Brand.blue.opacity(0.45), Brand.magenta.opacity(0.45)],
            width: 2,
            dashPattern: [2, 4]
        )
        // origin: outer r6 #FFFFFF, inner r4 eusoDiagonal gradient.
        let originMarker = EndpointMarker(
            outerRadius: 6, innerRadius: 4,
            outerFill: Color(hex: 0xFFFFFF),
            innerFill: Brand.blue,
            innerGradient: routeGradientStops,
            omitted: false, destPill: nil
        )
        // dest: outer r6 #FFFFFF, inner r4 #BE01FF solid.
        let destMarker = EndpointMarker(
            outerRadius: 6, innerRadius: 4,
            outerFill: Color(hex: 0xFFFFFF),
            innerFill: Brand.magenta,
            innerGradient: nil,
            omitted: false, destPill: nil
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
            routeActive: routeActive,
            routePending: routePending,
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
        // ROUTE traveled: brand gradient stroke 4, fixed bottom-left→top-right.
        let routeActive = RouteActive(stops: routeGradientStops, width: 4)
        // ROUTE remaining: eusoPrimary gradient @0.72 width 4 dash [2,8].
        let routePending = RoutePending(
            color: Color(hex: 0x6E7681),
            stops: [Brand.blue.opacity(0.72), Brand.magenta.opacity(0.72)],
            width: 4,
            dashPattern: [2, 8]
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
            routeActive: routeActive,
            routePending: routePending,
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
        // ROUTE active: brand gradient stroke 4.
        let routeActive = RouteActive(stops: routeGradientStops, width: 4)
        // ROUTE pending: 013 Light past-trail is IDENTICAL to dark —
        // eusoPrimary gradient @0.72 dash [2,8] width 4.
        let routePending = RoutePending(
            color: Color(hex: 0x8A96A3),
            stops: [Brand.blue.opacity(0.72), Brand.magenta.opacity(0.72)],
            width: 4,
            dashPattern: [2, 8]
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
            routeActive: routeActive,
            routePending: routePending,
            originMarker: originMarker,
            destMarker: destMarker,
            truckMarker: nil,
            ping: ping,
            pill: pill,
            container: squareContainer
        )
    }()

    // MARK: - LIGHT RAIL  (rail light skin — background-only swap off .light)
    //
    // Inherits every token from `.light` verbatim and swaps ONLY the
    // background to the rail solid skin (#E7ECF3).

    static let lightRail: BespokeMapStyle = {
        let base = light
        let bg = Background(
            stops: [Color(hex: 0xE7ECF3), Color(hex: 0xE7ECF3)],
            locations: [0.0, 1.0],
            isRadial: false,
            radialCenter: .center,
            radialRadius: 0.85
        )
        return BespokeMapStyle(
            background: bg,
            grid: base.grid,
            silhouettes: base.silhouettes,
            routeActive: base.routeActive,
            routePending: base.routePending,
            originMarker: base.originMarker,
            destMarker: base.destMarker,
            truckMarker: base.truckMarker,
            ping: base.ping,
            pill: base.pill,
            container: base.container
        )
    }()

    // MARK: - OCEAN  (Vessel 003 "Live Tracking", dark — great-circle AIS map)
    //
    // VERBATIM from `06 Vessel/Dark-SVG/003 Vessel Live Tracking.svg`. The map
    // card is a stylized great-circle ocean schematic: a deep navy basemap
    // (#0A1422 + #1473FF@0.06), three faint white@0.06 latitude lines, two
    // #27465F coast hints, the eusoPrimary solid traveled → white@0.14 dashed
    // remaining great-circle route, hollow port pins (origin eusoPrimary ring /
    // dest #6E7681 ring on a #05060A center), the AIS vessel orb (r20 #BE01FF
    // @0.22 glow + r11 eusoDiagonal core + white hull chevron), and the
    // location callout chip (#1C2128, #6E7681 mono coords / #F5F5F7 speed·hdg).

    static let ocean: BespokeMapStyle = {
        // basemap: #0A1422 navy (the #1473FF@0.06 overlay is folded by lifting
        // the bottom stop a hair toward blue so the wash reads top→bottom).
        let bg = Background(
            stops: [Color(hex: 0x0C1726), Color(hex: 0x0A1422)],
            locations: [0.0, 1.0],
            isRadial: false,
            radialCenter: .center,
            radialRadius: 0.85
        )
        // latitude grid: white@0.06 stroke 1.
        let grid = Grid(color: .white.opacity(0.06), width: 1)
        // coast hints: #27465F stroke 2.
        let silhouettes = Silhouettes(
            colors: [Color(hex: 0x27465F)],
            widths: [2]
        )
        // route traveled: eusoPrimary #1473FF→#BE01FF stroke 3.5 solid round.
        let routeActive = RouteActive(stops: routeGradientStops, width: 3.5)
        // route remaining: white@0.14 stroke 3.5 dash [2,7] round.
        let routePending = RoutePending(
            color: .white.opacity(0.14),
            stops: nil,
            width: 3.5,
            dashPattern: [2, 7]
        )
        // origin port pin: hollow r6 #05060A center, eusoPrimary ring w3.
        let originMarker = EndpointMarker(
            outerRadius: 6, innerRadius: 0,
            outerFill: Color(hex: 0x05060A),
            innerFill: .clear,
            innerGradient: nil,
            omitted: false, destPill: nil,
            ringStroke: Brand.blue, ringWidth: 3
        )
        // dest port pin: hollow r6 #05060A center, #6E7681 ring w3.
        let destMarker = EndpointMarker(
            outerRadius: 6, innerRadius: 0,
            outerFill: Color(hex: 0x05060A),
            innerFill: .clear,
            innerGradient: nil,
            omitted: false, destPill: nil,
            ringStroke: Color(hex: 0x6E7681), ringWidth: 3
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
            routeActive: routeActive,
            routePending: routePending,
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
    // VERBATIM from `06 Vessel/Light-SVG/003 Vessel Live Tracking.svg`. Same
    // great-circle schematic on a light water basemap: #CFE0F0 + #1473FF@0.05,
    // white@0.55 latitude lines, #9DB4C9@0.7 coast hints, eusoPrimary solid →
    // black@0.12 dashed route, white port pins (origin eusoPrimary ring / dest
    // #8A96A3 ring), the AIS orb (r20 #BE01FF@0.18 glow + r11 core + hull), and
    // the #FFFFFF callout chip (#8A96A3 mono coords / #0D1117 speed·hdg).

    static let lightOcean: BespokeMapStyle = {
        // water basemap: #CFE0F0 (#1473FF@0.05 overlay folded toward blue top).
        let bg = Background(
            stops: [Color(hex: 0xCBDDEE), Color(hex: 0xCFE0F0)],
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
        // route traveled: eusoPrimary stroke 3.5 solid round.
        let routeActive = RouteActive(stops: routeGradientStops, width: 3.5)
        // route remaining: black@0.12 stroke 3.5 dash [2,7] round.
        let routePending = RoutePending(
            color: .black.opacity(0.12),
            stops: nil,
            width: 3.5,
            dashPattern: [2, 7]
        )
        // origin port pin: hollow r6 #FFFFFF center, eusoPrimary ring w3.
        let originMarker = EndpointMarker(
            outerRadius: 6, innerRadius: 0,
            outerFill: Color(hex: 0xFFFFFF),
            innerFill: .clear,
            innerGradient: nil,
            omitted: false, destPill: nil,
            ringStroke: Brand.blue, ringWidth: 3
        )
        // dest port pin: hollow r6 #FFFFFF center, #8A96A3 ring w3.
        let destMarker = EndpointMarker(
            outerRadius: 6, innerRadius: 0,
            outerFill: Color(hex: 0xFFFFFF),
            innerFill: .clear,
            innerGradient: nil,
            omitted: false, destPill: nil,
            ringStroke: Color(hex: 0x8A96A3), ringWidth: 3
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
            routeActive: routeActive,
            routePending: routePending,
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
    /// caller signals the ocean great-circle surface via `style: .ocean`.
    static func ocean(isDark: Bool) -> BespokeMapStyle {
        isDark ? .ocean : .lightOcean
    }
}
