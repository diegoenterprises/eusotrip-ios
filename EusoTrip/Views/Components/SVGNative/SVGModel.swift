//
//  SVGModel.swift
//  EusoTrip — Native SVG renderer · parsed scene graph.
//
//  The immutable document the parser produces and the renderer walks: the
//  element tree, gradient/symbol/id lookup tables, the viewBox, and the parsed
//  stylesheet (rules + @keyframes + @media buckets).
//
//  Wave E (2026-06-10): every per-frame derivable fact is now BAKED onto the
//  element at parse time (SVGBaker in SVGParser.swift) — parsed Path, bbox,
//  merged cascade per dark/reduced combo, compiled animation specs, compiled
//  SMIL, transform origin, static transform, country group membership. The
//  render hot path is reads-only: zero rule matching, zero string parsing,
//  zero path re-parsing per frame.
//

import SwiftUI
import CoreGraphics

// MARK: - Country toggle

/// Country/jurisdiction for the regulated `.country-US / .country-MX /
/// .country-CA` groups authored across 98 corpus files (placards, carrier
/// credentials, emergency contacts, unit badges). The engine renders EXACTLY
/// ONE country group per pass: a nil country renders the US default — never
/// multiple groups, regardless of what the document's own CSS resolves to
/// (kills the [data-country] selector-reduction double-render at the engine
/// level). Wiring real load regions into this is Wave C.
enum SVGCountry: String, CaseIterable, Hashable {
    case us = "US"
    case mx = "MX"
    case ca = "CA"

    var className: String { "country-\(rawValue)" }

    /// Exact-token match against an element class name.
    static func from(className: String) -> SVGCountry? {
        switch className {
        case "country-US": return .us
        case "country-MX": return .mx
        case "country-CA": return .ca
        default: return nil
        }
    }
}

// MARK: - Element

/// Coarse element classification baked once so the renderer never calls
/// `tag.lowercased()` (or a Set lookup) per element per frame.
enum SVGElementKind: UInt8 {
    case group      // g / svg / a / switch
    case use
    case text
    case tspan
    case textRun    // synthesized "#text" ordered run inside <text>/<tspan>
    case geometry   // path / rect / circle / ellipse / line / polyline / polygon
    case skipped    // defs / style / gradients / symbol / clipPath / mask /
                    // filter / title / desc / metadata / animate* / set /
                    // marker / pattern — drawn only via <use>/pattern tiling
    case other      // unknown tag — attempted as geometry (renders nothing)
}

/// One element in the SVG tree (path, rect, g, use, text, …).
final class SVGElement {
    let tag: String
    var attrs: [String: String]
    var children: [SVGElement] = []
    var text: String? = nil          // textual content for <text>/<tspan>/<style>
    weak var parent: SVGElement?

    init(tag: String, attrs: [String: String]) {
        self.tag = tag
        self.attrs = attrs
    }

    var id: String? { attrs["id"] }
    var classNames: [String] {
        (attrs["class"] ?? "")
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)
    }

    // MARK: Baked render data — written once by SVGBaker at parse time,
    // read-only on the render path (the parse→bake pass completes before the
    // document is published to any view, so no synchronization is needed).

    /// Tag classification (replaces per-frame tag.lowercased() + Set lookups).
    var bakedKind: SVGElementKind = .other
    /// Parsed geometry Path (nil for non-geometry or var()-bearing geometry).
    var bakedStaticPath: Path? = nil
    /// True when a geometry attribute contains `var(` → rebuild per frame.
    var bakedNeedsDynamicPath = false
    /// Geometry bounds including children (bottom-up union, transform-naive —
    /// same semantics the per-frame O(n²) walk had, computed once in O(n)).
    var bakedBBox: CGRect = .zero
    /// Merged static cascade per bucket combo. Index = (dark ? 1 : 0) | (reduced ? 2 : 0).
    /// Identical combos share one dictionary (CoW) so memory stays flat.
    var bakedDecls: [[String: String]] = []
    /// Bit i set ⇢ combo i's decls contain `var(` refs (per-key resolution needed).
    var bakedDeclsVarMask: UInt8 = 0
    /// Pre-parsed `animation:` shorthand per combo (empty = no CSS animation).
    var bakedAnimationSpecs: [[SVGAnimationSpec]] = []
    /// transform-origin per combo, honoring transform-box: fill-box | view-box.
    var bakedOrigins: [CGPoint] = []
    /// Static transform per combo: SVG attr matrix ∘ CSS-decl matrix (about origin).
    var bakedStaticTransforms: [CGAffineTransform] = []
    /// True when the transform attr/decl carries `var(` → compute per frame.
    var bakedTransformHasVar = false
    /// Direct <animate>/<animateTransform>/<set> children (pre-filtered).
    var bakedSMILChildren: [SVGElement] = []
    /// Compiled SMIL parameters (set on the animate elements themselves).
    var bakedSMIL: SVGSMILCompiled? = nil
    /// Country group membership parsed from class tokens (country-US/MX/CA).
    var bakedCountry: SVGCountry? = nil
}

// MARK: - Gradients

struct SVGGradientStop {
    var offset: CGFloat
    var color: Color
    var opacity: CGFloat
}

struct SVGGradient {
    enum Kind {
        case linear(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat)
        case radial(cx: CGFloat, cy: CGFloat, r: CGFloat)
    }
    var kind: Kind
    var stops: [SVGGradientStop]
    /// gradientUnits == "userSpaceOnUse" → true; else objectBoundingBox (0…1).
    var userSpace: Bool
    var transform: CGAffineTransform
    /// Pre-built SwiftUI gradient (stops sorted + stop-opacity premultiplied)
    /// so paint() never rebuilds the stop array per frame.
    var ui: Gradient = Gradient(stops: [])

    /// Build the SwiftUI Gradient, premultiplying each stop's stop-opacity.
    static func buildUI(_ stops: [SVGGradientStop]) -> Gradient {
        let sorted = stops.sorted { $0.offset < $1.offset }
        guard !sorted.isEmpty else { return Gradient(colors: [.clear, .clear]) }
        return Gradient(stops: sorted.map {
            Gradient.Stop(color: $0.color.opacity($0.opacity), location: $0.offset)
        })
    }
}

// MARK: - Animated value primitives

/// Numeric RGBA color used for keyframed `fill:` interpolation (SwiftUI Color
/// exposes no components to lerp).
struct SVGRGBA {
    var r: Double, g: Double, b: Double, a: Double

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    func lerp(to other: SVGRGBA, _ t: CGFloat) -> SVGRGBA {
        let k = Double(min(1, max(0, t)))
        return SVGRGBA(r: r + (other.r - r) * k,
                       g: g + (other.g - g) * k,
                       b: b + (other.b - b) * k,
                       a: a + (other.a - a) * k)
    }

    /// Parse #hex / rgb() / rgba() / a tiny named subset. Returns nil for
    /// gradients/url() — keyframed fill never references paints in the corpus.
    static func parse(_ raw: String) -> SVGRGBA? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("#") {
            var hh = String(s.dropFirst())
            if hh.count == 3 || hh.count == 4 { hh = hh.map { "\($0)\($0)" }.joined() }
            guard hh.count == 6 || hh.count == 8, let v = UInt64(hh, radix: 16) else { return nil }
            if hh.count == 8 {
                return SVGRGBA(r: Double((v >> 24) & 0xff) / 255, g: Double((v >> 16) & 0xff) / 255,
                               b: Double((v >> 8) & 0xff) / 255, a: Double(v & 0xff) / 255)
            }
            return SVGRGBA(r: Double((v >> 16) & 0xff) / 255, g: Double((v >> 8) & 0xff) / 255,
                           b: Double(v & 0xff) / 255, a: 1)
        }
        if s.hasPrefix("rgb") {
            guard let open = s.firstIndex(of: "("), let close = s.lastIndex(of: ")") else { return nil }
            let parts = s[s.index(after: open)..<close]
                .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).map(String.init)
            guard parts.count >= 3 else { return nil }
            func comp(_ str: String) -> Double {
                if str.hasSuffix("%") { return (Double(str.dropLast()) ?? 0) / 100 * 255 }
                return Double(str) ?? 0
            }
            var a = 1.0
            if parts.count >= 4 {
                let ap = parts[3]
                a = ap.hasSuffix("%") ? (Double(ap.dropLast()) ?? 100) / 100 : (Double(ap) ?? 1)
            }
            return SVGRGBA(r: comp(parts[0]) / 255, g: comp(parts[1]) / 255, b: comp(parts[2]) / 255, a: a)
        }
        switch s {
        case "black": return SVGRGBA(r: 0, g: 0, b: 0, a: 1)
        case "white": return SVGRGBA(r: 1, g: 1, b: 1, a: 1)
        case "transparent", "none": return SVGRGBA(r: 0, g: 0, b: 0, a: 0)
        default: return nil
        }
    }
}

/// Fixed-width SMIL value vector (≤3 numeric args in the corpus:
/// rotate(angle cx cy)). Avoids per-frame array allocation.
struct SVGSMILVec {
    var a: CGFloat = 0, b: CGFloat = 0, c: CGFloat = 0
    var count: Int = 0

    init() {}
    init(_ list: [CGFloat]) {
        count = min(3, list.count)
        if count > 0 { a = list[0] }
        if count > 1 { b = list[1] }
        if count > 2 { c = list[2] }
    }

    static func lerp(_ x: SVGSMILVec, _ y: SVGSMILVec, _ t: CGFloat) -> SVGSMILVec {
        var out = SVGSMILVec()
        out.count = max(x.count, y.count)
        out.a = x.a + (y.a - x.a) * t
        out.b = x.b + (y.b - x.b) * t
        out.c = x.c + (y.c - x.c) * t
        return out
    }
}

/// Compiled <animate>/<animateTransform>/<set> — all string parsing done at
/// parse time; per-frame work is pure numeric sampling.
struct SVGSMILCompiled {
    enum Kind { case animate, animateTransform, set }
    var kind: Kind
    var attributeName: String      // lowercased: r / cy / cx / x / y / opacity / stroke-dashoffset / …
    var transformType: String      // animateTransform: translate / rotate / scale
    var dur: Double
    var begin: Double
    var repeats: Bool
    var freeze: Bool
    var frames: [SVGSMILVec]       // ≥2 when animating (from/to compile to 2)
    var keyTimes: [CGFloat]?
}

// MARK: - CSS

enum SVGSelector: Equatable {
    case cls(String)
    case tag(String)
    case id(String)
    case universal
}

struct SVGRule {
    var selectors: [SVGSelector]   // comma-separated group; rightmost key used to match
    var decls: [String: String]
    var specificity: Int           // crude: id=100, class=10, tag=1 (last-wins on tie)
    var order: Int
}

/// One transform operation kept un-collapsed so it can be interpolated
/// (rotate(0)→rotate(360) interpolates the angle, not the matrix).
struct SVGTransformOp {
    var name: String               // lowercased: translate / rotate / scale / scalex / …
    var args: [CGFloat]
}

/// One compiled @keyframes frame — transform pre-parsed to ops, numeric
/// geometry/paint properties pre-extracted, fill pre-parsed to RGBA.
struct SVGCompiledFrame {
    var pct: CGFloat
    var ops: [SVGTransformOp]?     // parsed transform (nil = no transform decl)
    var transformRaw: String?      // var()-bearing transform → resolve per frame
    var opacity: CGFloat?
    var x: CGFloat?
    var y: CGFloat?
    var r: CGFloat?
    var cx: CGFloat?
    var cy: CGFloat?
    var width: CGFloat?
    var height: CGFloat?
    var dashoffset: CGFloat?
    var fill: SVGRGBA?
}

struct SVGKeyframes {
    var name: String
    /// Sorted ascending by pct (0…1). Each frame is a set of declarations.
    var frames: [(pct: CGFloat, decls: [String: String])]
    /// Compiled form (same order) — built by SVGBaker; the render path only
    /// touches this.
    var compiled: [SVGCompiledFrame] = []
}

struct SVGAnimationSpec {
    enum Direction { case normal, reverse, alternate, alternateReverse }
    var name: String
    var duration: Double
    var easing: SVGEasing
    var delay: Double
    var iterationCount: Double      // .infinity for "infinite"
    var direction: Direction

    /// Parse a CSS `animation:` shorthand value, e.g.
    /// "spin 2s linear infinite", "pulse 1.5s ease-in-out 0.2s alternate".
    static func parse(_ value: String) -> SVGAnimationSpec? {
        let parts = value.split(whereSeparator: { $0 == " " }).map { String($0) }
        guard !parts.isEmpty else { return nil }
        var name: String? = nil
        var times: [Double] = []         // first = duration, second = delay
        var easing: SVGEasing = .ease
        var iter: Double = 1
        var dir: Direction = .normal
        var i = 0
        while i < parts.count {
            let p = parts[i]
            let lp = p.lowercased()
            if lp == "infinite" {
                iter = .infinity
            } else if lp == "normal" { dir = .normal }
            else if lp == "reverse" { dir = .reverse }
            else if lp == "alternate" { dir = .alternate }
            else if lp == "alternate-reverse" { dir = .alternateReverse }
            else if lp == "!important" {
                // importance is a cascade concern (handled by bucket order)
            } else if lp == "linear" || lp == "ease" || lp == "ease-in" || lp == "ease-out" || lp == "ease-in-out" {
                easing = SVGEasing.parse(lp)
            } else if lp.hasPrefix("cubic-bezier") || lp.hasPrefix("steps") {
                // shorthand may split a function across spaces — rejoin until ')'
                var fn = p
                while !fn.contains(")") && i + 1 < parts.count {
                    i += 1; fn += parts[i]
                }
                easing = SVGEasing.parse(fn)
            } else if lp.hasSuffix("ms"), let v = Double(lp.dropLast(2)) {
                times.append(v / 1000)
            } else if lp.hasSuffix("s"), let v = Double(lp.dropLast()) {
                times.append(v)
            } else if let v = Double(lp) {
                iter = v
            } else if !lp.isEmpty {
                if name == nil { name = p }
            }
            i += 1
        }
        guard let n = name, n.lowercased() != "none" else { return nil }
        return SVGAnimationSpec(
            name: n,
            duration: times.first ?? 1,
            easing: easing,
            delay: times.count > 1 ? times[1] : 0,
            iterationCount: iter,
            direction: dir
        )
    }
}

// MARK: - Document

struct SVGDocument {
    var root: SVGElement
    var viewBox: CGRect
    var gradients: [String: SVGGradient]
    var defsById: [String: SVGElement]   // <symbol>/<g>/shape/<pattern> referenced by <use>/paint
    var stylesheet: SVGStyleSheet

    // Baked document-level facts (SVGBaker):
    /// False when the document has no @keyframes-driven specs and no SMIL —
    /// the host can render a single static Canvas (no TimelineView clock).
    var isAnimated: Bool = true
    /// Every `data-bind` key authored in the document (DEBUG diagnostics —
    /// the decode-shape silent-fail trap analog).
    var bindKeys: Set<String> = []
    /// True when any attribute or declaration references `var(`.
    var usesCSSVars: Bool = false
    /// True when any element carries a .country-US/-MX/-CA class.
    var hasCountryGroups: Bool = false
}

struct SVGStyleSheet {
    var rules: [SVGRule] = []
    var keyframes: [String: SVGKeyframes] = [:]
    var reducedMotionRules: [SVGRule] = []   // under @media (prefers-reduced-motion: reduce)
    var darkRules: [SVGRule] = []            // under @media (prefers-color-scheme: dark)
}
