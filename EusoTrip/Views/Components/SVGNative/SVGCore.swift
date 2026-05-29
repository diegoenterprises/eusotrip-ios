//
//  SVGCore.swift
//  EusoTrip — Native SVG renderer · low-level primitives.
//
//  Parsing helpers shared by the whole engine: numbers, lengths, colors
//  (named / #hex / rgb()/rgba() / hsl()), transform lists → CGAffineTransform,
//  and the CSS/SMIL timing-function family. Pure value code, no SwiftUI views,
//  so it compiles and unit-reasons in isolation.
//

import SwiftUI
import Foundation

// MARK: - Number scanning

enum SVGNum {
    /// Parse a leading floating-point number (handles +/-, exponent, leading dot).
    static func parse(_ s: Substring) -> CGFloat? {
        let str = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = Double(str) { return CGFloat(d) }
        // strip a trailing unit (px, %, deg, etc.) if Double() failed
        var end = str.startIndex
        var seenDot = false, seenE = false
        var i = str.startIndex
        while i < str.endIndex {
            let c = str[i]
            if c == "-" || c == "+" {
                if i != str.startIndex {
                    // sign only allowed right after an exponent marker
                    let prev = str[str.index(before: i)]
                    if prev != "e" && prev != "E" { break }
                }
            } else if c == "." {
                if seenDot { break }; seenDot = true
            } else if c == "e" || c == "E" {
                if seenE { break }; seenE = true
            } else if !c.isNumber {
                break
            }
            i = str.index(after: i)
            end = i
        }
        let head = String(str[str.startIndex..<end])
        return Double(head).map { CGFloat($0) }
    }

    static func parse(_ s: String?) -> CGFloat? {
        guard let s = s else { return nil }
        return parse(Substring(s))
    }

    /// Parse a list of numbers separated by commas and/or whitespace.
    static func list(_ s: String) -> [CGFloat] {
        var out: [CGFloat] = []
        var cur = ""
        func flush() {
            let t = cur.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, let v = Double(t) { out.append(CGFloat(v)) }
            cur = ""
        }
        var prevWasDigit = false
        for c in s {
            if c == "," || c == " " || c == "\n" || c == "\t" || c == "\r" {
                flush(); prevWasDigit = false
            } else if (c == "-" || c == "+") && prevWasDigit {
                // a sign that starts a new number (e.g. "10-5")
                flush(); cur.append(c); prevWasDigit = false
            } else {
                cur.append(c)
                prevWasDigit = c.isNumber || c == "."
            }
        }
        flush()
        return out
    }

    /// Length possibly suffixed with a unit or "%". Percentages resolve against `base`.
    static func length(_ s: String?, relativeTo base: CGFloat = 0) -> CGFloat? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.hasSuffix("%") {
            if let v = Double(s.dropLast()) { return CGFloat(v) / 100.0 * base }
            return nil
        }
        return parse(Substring(s))
    }
}

// MARK: - Color

enum SVGColor {
    static func parse(_ raw: String?) -> Color? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !s.isEmpty else { return nil }
        if s == "none" || s == "transparent" { return .clear }
        if s == "currentcolor" { return nil } // resolved by caller against inherited color
        if s.hasPrefix("#") {
            return hex(String(s.dropFirst()))
        }
        if s.hasPrefix("rgb") {
            return functional(s)
        }
        if s.hasPrefix("hsl") {
            return hslFunctional(s)
        }
        if let named = named[s] { return named }
        return nil
    }

    static func hex(_ h: String) -> Color? {
        var hh = h
        if hh.count == 3 || hh.count == 4 {
            hh = hh.map { "\($0)\($0)" }.joined()
        }
        guard hh.count == 6 || hh.count == 8, let v = UInt64(hh, radix: 16) else { return nil }
        let r, g, b, a: Double
        if hh.count == 8 {
            r = Double((v >> 24) & 0xff) / 255
            g = Double((v >> 16) & 0xff) / 255
            b = Double((v >> 8) & 0xff) / 255
            a = Double(v & 0xff) / 255
        } else {
            r = Double((v >> 16) & 0xff) / 255
            g = Double((v >> 8) & 0xff) / 255
            b = Double(v & 0xff) / 255
            a = 1
        }
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    private static func functional(_ s: String) -> Color? {
        guard let open = s.firstIndex(of: "("), let close = s.lastIndex(of: ")") else { return nil }
        let inside = String(s[s.index(after: open)..<close])
        let parts = inside.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).map { String($0) }
        func comp(_ str: String) -> Double {
            if str.hasSuffix("%") { return (Double(str.dropLast()) ?? 0) / 100 * 255 }
            return Double(str) ?? 0
        }
        guard parts.count >= 3 else { return nil }
        let r = comp(parts[0]) / 255, g = comp(parts[1]) / 255, b = comp(parts[2]) / 255
        var a = 1.0
        if parts.count >= 4 {
            let ap = parts[3]
            a = ap.hasSuffix("%") ? (Double(ap.dropLast()) ?? 100) / 100 : (Double(ap) ?? 1)
        }
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    private static func hslFunctional(_ s: String) -> Color? {
        guard let open = s.firstIndex(of: "("), let close = s.lastIndex(of: ")") else { return nil }
        let inside = String(s[s.index(after: open)..<close])
        let parts = inside.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).map { String($0) }
        guard parts.count >= 3 else { return nil }
        let h = (Double(parts[0].replacingOccurrences(of: "deg", with: "")) ?? 0)
        let sat = (Double(parts[1].replacingOccurrences(of: "%", with: "")) ?? 0) / 100
        let li = (Double(parts[2].replacingOccurrences(of: "%", with: "")) ?? 0) / 100
        var a = 1.0
        if parts.count >= 4 {
            let ap = parts[3]
            a = ap.hasSuffix("%") ? (Double(ap.dropLast()) ?? 100) / 100 : (Double(ap) ?? 1)
        }
        let (r, g, b) = hslToRgb(h: h.truncatingRemainder(dividingBy: 360) / 360, s: sat, l: li)
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    private static func hslToRgb(h: Double, s: Double, l: Double) -> (Double, Double, Double) {
        if s == 0 { return (l, l, l) }
        func hue2rgb(_ p: Double, _ q: Double, _ tIn: Double) -> Double {
            var t = tIn
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1/6 { return p + (q - p) * 6 * t }
            if t < 1/2 { return q }
            if t < 2/3 { return p + (q - p) * (2/3 - t) * 6 }
            return p
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        return (hue2rgb(p, q, h + 1/3), hue2rgb(p, q, h), hue2rgb(p, q, h - 1/3))
    }

    /// The CSS/SVG named-color subset that actually appears in the corpus plus
    /// the common ones, so a stray `fill="white"` resolves.
    static let named: [String: Color] = [
        "black": .black, "white": .white, "red": .red, "green": Color(.sRGB, red: 0, green: 0.5, blue: 0, opacity: 1),
        "blue": .blue, "yellow": .yellow, "orange": .orange, "purple": .purple, "gray": .gray, "grey": .gray,
        "silver": Color(.sRGB, red: 0.75, green: 0.75, blue: 0.75, opacity: 1),
        "lightgray": Color(.sRGB, red: 0.83, green: 0.83, blue: 0.83, opacity: 1),
        "lightgrey": Color(.sRGB, red: 0.83, green: 0.83, blue: 0.83, opacity: 1),
        "darkgray": Color(.sRGB, red: 0.66, green: 0.66, blue: 0.66, opacity: 1),
        "dimgray": Color(.sRGB, red: 0.41, green: 0.41, blue: 0.41, opacity: 1),
        "navy": Color(.sRGB, red: 0, green: 0, blue: 0.5, opacity: 1),
        "maroon": Color(.sRGB, red: 0.5, green: 0, blue: 0, opacity: 1),
        "olive": Color(.sRGB, red: 0.5, green: 0.5, blue: 0, opacity: 1),
        "teal": Color(.sRGB, red: 0, green: 0.5, blue: 0.5, opacity: 1),
        "cyan": .cyan, "magenta": Color(.sRGB, red: 1, green: 0, blue: 1, opacity: 1),
        "lime": Color(.sRGB, red: 0, green: 1, blue: 0, opacity: 1),
        "gold": Color(.sRGB, red: 1, green: 0.84, blue: 0, opacity: 1),
        "darkred": Color(.sRGB, red: 0.55, green: 0, blue: 0, opacity: 1),
        "darkgreen": Color(.sRGB, red: 0, green: 0.39, blue: 0, opacity: 1),
        "darkblue": Color(.sRGB, red: 0, green: 0, blue: 0.55, opacity: 1),
        "steelblue": Color(.sRGB, red: 0.27, green: 0.51, blue: 0.71, opacity: 1),
        "transparent": .clear, "none": .clear,
        "whitesmoke": Color(.sRGB, red: 0.96, green: 0.96, blue: 0.96, opacity: 1),
        "ghostwhite": Color(.sRGB, red: 0.97, green: 0.97, blue: 1, opacity: 1),
    ]
}

// MARK: - Transform list

enum SVGTransform {
    /// Parse an SVG/CSS transform list ("translate(10 5) rotate(45) ...")
    /// into a single CGAffineTransform applied left-to-right (SVG order).
    static func parse(_ s: String?) -> CGAffineTransform {
        guard let s = s, !s.isEmpty else { return .identity }
        var result = CGAffineTransform.identity
        var idx = s.startIndex
        while idx < s.endIndex {
            // function name
            guard let open = s[idx...].firstIndex(of: "(") else { break }
            let name = s[idx..<open].trimmingCharacters(in: CharacterSet(charactersIn: " ,\n\t")).lowercased()
            guard let close = s[open...].firstIndex(of: ")") else { break }
            let argStr = String(s[s.index(after: open)..<close])
            let a = SVGNum.list(argStr)
            let t = matrix(for: name, args: a)
            result = result.concatenating(t)
            idx = s.index(after: close)
        }
        return result
    }

    private static func matrix(for name: String, args a: [CGFloat]) -> CGAffineTransform {
        switch name {
        case "translate":
            return CGAffineTransform(translationX: a.first ?? 0, y: a.count > 1 ? a[1] : 0)
        case "translatex": return CGAffineTransform(translationX: a.first ?? 0, y: 0)
        case "translatey": return CGAffineTransform(translationX: 0, y: a.first ?? 0)
        case "scale":
            let sx = a.first ?? 1
            return CGAffineTransform(scaleX: sx, y: a.count > 1 ? a[1] : sx)
        case "scalex": return CGAffineTransform(scaleX: a.first ?? 1, y: 1)
        case "scaley": return CGAffineTransform(scaleX: 1, y: a.first ?? 1)
        case "rotate":
            let deg = a.first ?? 0
            let rad = deg * .pi / 180
            if a.count >= 3 {
                let cx = a[1], cy = a[2]
                return CGAffineTransform(translationX: cx, y: cy)
                    .rotated(by: rad)
                    .translatedBy(x: -cx, y: -cy)
            }
            return CGAffineTransform(rotationAngle: rad)
        case "skewx":
            return CGAffineTransform(a: 1, b: 0, c: tan((a.first ?? 0) * .pi / 180), d: 1, tx: 0, ty: 0)
        case "skewy":
            return CGAffineTransform(a: 1, b: tan((a.first ?? 0) * .pi / 180), c: 0, d: 1, tx: 0, ty: 0)
        case "matrix":
            guard a.count >= 6 else { return .identity }
            return CGAffineTransform(a: a[0], b: a[1], c: a[2], d: a[3], tx: a[4], ty: a[5])
        default:
            return .identity
        }
    }
}

// MARK: - Timing functions (CSS + SMIL)

enum SVGEasing {
    case linear
    case ease, easeIn, easeOut, easeInOut
    case cubicBezier(CGFloat, CGFloat, CGFloat, CGFloat)
    case steps(Int)

    static func parse(_ raw: String?) -> SVGEasing {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !s.isEmpty else { return .ease }
        switch s {
        case "linear": return .linear
        case "ease": return .ease
        case "ease-in": return .easeIn
        case "ease-out": return .easeOut
        case "ease-in-out": return .easeInOut
        default: break
        }
        if s.hasPrefix("cubic-bezier"), let open = s.firstIndex(of: "("), let close = s.lastIndex(of: ")") {
            let n = SVGNum.list(String(s[s.index(after: open)..<close]))
            if n.count >= 4 { return .cubicBezier(n[0], n[1], n[2], n[3]) }
        }
        if s.hasPrefix("steps"), let open = s.firstIndex(of: "("), let close = s.lastIndex(of: ")") {
            let n = SVGNum.list(String(s[s.index(after: open)..<close]))
            if let c = n.first { return .steps(max(1, Int(c))) }
        }
        return .ease
    }

    /// Map linear progress t∈[0,1] through the easing curve.
    func apply(_ t: CGFloat) -> CGFloat {
        let x = min(1, max(0, t))
        switch self {
        case .linear: return x
        case .ease: return Self.bezier(x, 0.25, 0.1, 0.25, 1)
        case .easeIn: return Self.bezier(x, 0.42, 0, 1, 1)
        case .easeOut: return Self.bezier(x, 0, 0, 0.58, 1)
        case .easeInOut: return Self.bezier(x, 0.42, 0, 0.58, 1)
        case .cubicBezier(let a, let b, let c, let d): return Self.bezier(x, a, b, c, d)
        case .steps(let n): return CGFloat(Int(x * CGFloat(n))) / CGFloat(n)
        }
    }

    /// Solve a cubic-bezier easing y for a given x using Newton/bisection.
    private static func bezier(_ x: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> CGFloat {
        func sampleX(_ t: CGFloat) -> CGFloat {
            let u = 1 - t
            return 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t
        }
        func sampleY(_ t: CGFloat) -> CGFloat {
            let u = 1 - t
            return 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t
        }
        // find t such that sampleX(t) ≈ x via bisection (robust, no derivative blowups)
        var lo: CGFloat = 0, hi: CGFloat = 1, t: CGFloat = x
        for _ in 0..<24 {
            let xt = sampleX(t)
            if abs(xt - x) < 0.0005 { break }
            if xt < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return sampleY(t)
    }
}
