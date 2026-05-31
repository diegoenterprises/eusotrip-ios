//
//  SVGModel.swift
//  EusoTrip — Native SVG renderer · parsed scene graph.
//
//  The immutable document the parser produces and the renderer walks: the
//  element tree, gradient/symbol/id lookup tables, the viewBox, and the parsed
//  stylesheet (rules + @keyframes + @media buckets).
//

import SwiftUI
import CoreGraphics

/// One element in the SVG tree (path, rect, g, use, text, …).
final class SVGElement {
    let tag: String
    var attrs: [String: String]
    var children: [SVGElement] = []
    var text: String? = nil          // textual content for <text>/<tspan>
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

    /// Build a SwiftUI Gradient, premultiplying each stop's stop-opacity.
    var swiftUIGradient: Gradient {
        let sorted = stops.sorted { $0.offset < $1.offset }
        guard !sorted.isEmpty else { return Gradient(colors: [.clear, .clear]) }
        return Gradient(stops: sorted.map {
            Gradient.Stop(color: $0.color.opacity($0.opacity), location: $0.offset)
        })
    }
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

struct SVGKeyframes {
    var name: String
    /// Sorted ascending by pct (0…1). Each frame is a set of declarations.
    var frames: [(pct: CGFloat, decls: [String: String])]
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
            else if lp == "linear" || lp == "ease" || lp == "ease-in" || lp == "ease-out" || lp == "ease-in-out" {
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
        guard let n = name else { return nil }
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
    var defsById: [String: SVGElement]   // <symbol>/<g>/shape referenced by <use>
    var stylesheet: SVGStyleSheet
}

struct SVGStyleSheet {
    var rules: [SVGRule] = []
    var keyframes: [String: SVGKeyframes] = [:]
    var reducedMotionRules: [SVGRule] = []   // under @media (prefers-reduced-motion: reduce)
    var darkRules: [SVGRule] = []            // under @media (prefers-color-scheme: dark)
}
