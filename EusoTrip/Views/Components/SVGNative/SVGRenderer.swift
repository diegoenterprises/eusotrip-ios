//
//  SVGRenderer.swift
//  EusoTrip — Native SVG renderer · scene graph → SwiftUI Canvas.
//
//  Walks the SVGDocument and paints it into a GraphicsContext at a given time.
//  Honors the SVG/CSS cascade (presentation attrs < stylesheet < dark < reduced-
//  motion < inline), viewBox → fit transform (xMidYMid meet), nested group
//  transforms/opacity, gradients (object-bbox + userSpace), <use>/<symbol>
//  resolution, dashed/capped strokes, text, and per-element animation.
//
//  Native equivalents of the old WKWebView data-binding layer:
//    • bindings  — `data-bind="key"` <text> nodes render the live value
//    • placardId — `<use href="#commodityPlacard">` remaps to the hazmat class
//    • cssVars   — `var(--load-progress)` etc. resolve before parsing
//

import SwiftUI
import CoreGraphics

struct SVGComputedStyle {
    var fill: String? = "black"          // raw paint string ("#fff", "url(#g)", "none")
    var stroke: String? = "none"
    var strokeWidth: CGFloat = 1
    var opacity: CGFloat = 1
    var fillOpacity: CGFloat = 1
    var strokeOpacity: CGFloat = 1
    var fillRuleEvenOdd: Bool = false
    var strokeDash: [CGFloat]? = nil
    var lineCap: CGLineCap = .butt
    var lineJoin: CGLineJoin = .miter
    var fontSize: CGFloat = 16
    var fontWeight: Font.Weight = .regular
    var textAnchor: String = "start"
    var currentColor: Color = .black
    var display: Bool = true

    /// Inheritable subset passed to children (per SVG: paint + font inherit;
    /// element `opacity` does NOT inherit — it composes via the context).
    func inheritable() -> SVGComputedStyle {
        var s = self
        s.opacity = 1
        return s
    }
}

/// Invariant render context threaded through the recursive walk.
struct SVGRenderEnv {
    let doc: SVGDocument
    let time: Double
    let reduceMotion: Bool
    let dark: Bool
    let bindings: [String: String]
    let placardId: String?
    let cssVars: [String: String]
}

enum SVGRenderer {

    static func render(document: SVGDocument, into ctx: GraphicsContext, size: CGSize,
                       time: Double, reduceMotion: Bool, dark: Bool,
                       bindings: [String: String] = [:], placardId: String? = nil,
                       cssVars: [String: String] = [:]) {
        let vb = document.viewBox
        guard vb.width > 0, vb.height > 0 else { return }
        let scale = min(size.width / vb.width, size.height / vb.height)
        let tx = (size.width - vb.width * scale) / 2 - vb.minX * scale
        let ty = (size.height - vb.height * scale) / 2 - vb.minY * scale
        var base = ctx
        base.concatenate(CGAffineTransform(translationX: tx, y: ty).scaledBy(x: scale, y: scale))

        let env = SVGRenderEnv(doc: document, time: time, reduceMotion: reduceMotion, dark: dark,
                               bindings: bindings, placardId: placardId, cssVars: cssVars)
        var inherited = SVGComputedStyle()
        inherited = resolve(document.root, base: inherited, env: env)
        for child in document.root.children {
            draw(child, into: base, inherited: inherited.inheritable(), accumulatedOpacity: 1, env: env, depth: 0)
        }
    }

    // MARK: Recursive draw

    private static let skipTags: Set<String> = [
        "defs", "style", "lineargradient", "radialgradient", "symbol", "clippath",
        "mask", "filter", "title", "desc", "metadata", "animate", "animatetransform",
        "animatemotion", "set", "marker", "pattern",
    ]

    private static func draw(_ el: SVGElement, into ctx: GraphicsContext, inherited: SVGComputedStyle,
                             accumulatedOpacity: CGFloat, env: SVGRenderEnv, depth: Int) {
        if depth > 64 { return }   // cycle/recursion guard for <use>
        let tag = el.tag.lowercased()
        if skipTags.contains(tag) { return }

        let style = resolve(el, base: inherited, env: env)
        if !style.display { return }

        let bbox = geometryBounds(el, doc: env.doc)
        let origin = transformOrigin(el, env: env, bbox: bbox)
        let staticT = SVGTransform.parse(resolveVars(el.attrs["transform"], env.cssVars))

        var anim = AnimatedState()
        if !env.reduceMotion {
            let decls = computedDecls(el, env: env)
            anim = SVGAnimation.cssState(decls: decls, keyframes: env.doc.stylesheet.keyframes, time: env.time, origin: origin)
            let smil = SVGAnimation.smilState(element: el, time: env.time, origin: origin)
            anim.extraTransform = anim.extraTransform.concatenating(smil.extraTransform)
            anim.opacityMultiplier *= smil.opacityMultiplier
        }

        let elementOpacity = accumulatedOpacity * style.opacity * anim.opacityMultiplier
        var sub = ctx
        sub.concatenate(staticT)
        sub.concatenate(anim.extraTransform)
        sub.opacity = elementOpacity

        switch tag {
        case "g", "svg", "a", "switch":
            for c in el.children {
                draw(c, into: sub, inherited: style.inheritable(), accumulatedOpacity: 1, env: env, depth: depth + 1)
            }
        case "use":
            drawUse(el, into: sub, style: style, env: env, depth: depth)
        case "text", "tspan":
            drawText(el, into: sub, style: style, env: env)
        default:
            if let path = geometryPath(el, doc: env.doc) {
                paint(path, style: style, into: sub, doc: env.doc, bbox: bbox)
            }
        }
    }

    private static func drawUse(_ el: SVGElement, into ctx: GraphicsContext, style: SVGComputedStyle,
                                env: SVGRenderEnv, depth: Int) {
        let rawHref = el.attrs["xlink:href"] ?? el.attrs["href"] ?? ""
        guard rawHref.hasPrefix("#") else { return }
        var id = String(rawHref.dropFirst())
        // Hazmat placard swap — native equivalent of the WKWebView use-href rewrite.
        if id == "commodityPlacard", let placard = env.placardId, !placard.isEmpty {
            id = placard
        }
        guard let referent = env.doc.defsById[id] else { return }
        var sub = ctx
        let x = SVGNum.parse(el.attrs["x"]) ?? 0
        let y = SVGNum.parse(el.attrs["y"]) ?? 0
        if x != 0 || y != 0 { sub.concatenate(CGAffineTransform(translationX: x, y: y)) }
        if referent.tag.lowercased() == "symbol" {
            for c in referent.children {
                draw(c, into: sub, inherited: style.inheritable(), accumulatedOpacity: 1, env: env, depth: depth + 1)
            }
        } else {
            draw(referent, into: sub, inherited: style.inheritable(), accumulatedOpacity: 1, env: env, depth: depth + 1)
        }
    }

    // MARK: Painting

    private static func paint(_ path: Path, style: SVGComputedStyle, into ctx: GraphicsContext,
                              doc: SVGDocument, bbox: CGRect) {
        if let fill = style.fill, fill.lowercased() != "none" {
            if let shading = shading(for: fill, opacity: style.fillOpacity, style: style, doc: doc, bbox: bbox) {
                ctx.fill(path, with: shading, style: FillStyle(eoFill: style.fillRuleEvenOdd))
            }
        }
        if let stroke = style.stroke, stroke.lowercased() != "none", style.strokeWidth > 0 {
            if let shading = shading(for: stroke, opacity: style.strokeOpacity, style: style, doc: doc, bbox: bbox) {
                let strokeStyle = StrokeStyle(
                    lineWidth: style.strokeWidth,
                    lineCap: style.lineCap,
                    lineJoin: style.lineJoin,
                    dash: style.strokeDash ?? []
                )
                ctx.stroke(path, with: shading, style: strokeStyle)
            }
        }
    }

    private static func shading(for paint: String, opacity: CGFloat, style: SVGComputedStyle,
                                doc: SVGDocument, bbox: CGRect) -> GraphicsContext.Shading? {
        let p = paint.trimmingCharacters(in: .whitespaces)
        if p.lowercased().hasPrefix("url(") {
            if let open = p.firstIndex(of: "#"), let close = p.lastIndex(of: ")") {
                let id = String(p[p.index(after: open)..<close]).trimmingCharacters(in: CharacterSet(charactersIn: " )\"'"))
                if let grad = doc.gradients[id] {
                    return gradientShading(grad, opacity: opacity, bbox: bbox)
                }
            }
            return nil
        }
        let color: Color
        if p.lowercased() == "currentcolor" { color = style.currentColor }
        else { color = SVGColor.parse(p) ?? style.currentColor }
        return .color(color.opacity(opacity))
    }

    private static func gradientShading(_ grad: SVGGradient, opacity: CGFloat, bbox: CGRect) -> GraphicsContext.Shading {
        let g = scaleOpacity(grad.swiftUIGradient, by: opacity)
        func mapPoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let raw: CGPoint
            if grad.userSpace { raw = CGPoint(x: x, y: y) }
            else { raw = CGPoint(x: bbox.minX + x * bbox.width, y: bbox.minY + y * bbox.height) }
            return raw.applying(grad.transform)
        }
        switch grad.kind {
        case .linear(let x1, let y1, let x2, let y2):
            return .linearGradient(g, startPoint: mapPoint(x1, y1), endPoint: mapPoint(x2, y2))
        case .radial(let cx, let cy, let r):
            let center = mapPoint(cx, cy)
            let radius = grad.userSpace ? r : r * max(bbox.width, bbox.height)
            return .radialGradient(g, center: center, startRadius: 0, endRadius: max(0.01, radius))
        }
    }

    private static func scaleOpacity(_ gradient: Gradient, by o: CGFloat) -> Gradient {
        guard o < 1 else { return gradient }
        return Gradient(stops: gradient.stops.map {
            Gradient.Stop(color: $0.color.opacity(o), location: $0.location)
        })
    }

    private static func drawText(_ el: SVGElement, into ctx: GraphicsContext, style: SVGComputedStyle, env: SVGRenderEnv) {
        // data-bind: live value overrides the baked default; empty/missing keeps default.
        var content = (el.text ?? "")
        if let key = el.attrs["data-bind"], let bound = env.bindings[key], !bound.isEmpty {
            content = bound
        }
        content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        let x = SVGNum.parse(el.attrs["x"]) ?? 0
        let y = SVGNum.parse(el.attrs["y"]) ?? 0
        let colorStr = style.fill ?? "black"
        let color = (colorStr.lowercased() == "currentcolor") ? style.currentColor : (SVGColor.parse(colorStr) ?? .black)
        let text = Text(content)
            .font(.system(size: style.fontSize, weight: style.fontWeight))
            .foregroundColor(color.opacity(style.fillOpacity))
        let anchor: UnitPoint
        switch style.textAnchor {
        case "middle": anchor = .center
        case "end": anchor = .trailing
        default: anchor = .leading
        }
        ctx.draw(text, at: CGPoint(x: x, y: y), anchor: UnitPoint(x: anchor.x, y: 0.75))
    }

    // MARK: Geometry

    private static func geometryPath(_ el: SVGElement, doc: SVGDocument) -> Path? {
        switch el.tag.lowercased() {
        case "path":
            guard let d = el.attrs["d"] else { return nil }
            return SVGPathParser.path(from: d)
        case "rect":
            let x = SVGNum.parse(el.attrs["x"]) ?? 0
            let y = SVGNum.parse(el.attrs["y"]) ?? 0
            let w = SVGNum.parse(el.attrs["width"]) ?? 0
            let h = SVGNum.parse(el.attrs["height"]) ?? 0
            guard w > 0, h > 0 else { return nil }
            let rx = SVGNum.parse(el.attrs["rx"])
            let ry = SVGNum.parse(el.attrs["ry"])
            let rect = CGRect(x: x, y: y, width: w, height: h)
            if let r = rx ?? ry, r > 0 {
                return Path(roundedRect: rect, cornerSize: CGSize(width: rx ?? ry ?? 0, height: ry ?? rx ?? 0))
            }
            return Path(rect)
        case "circle":
            let cx = SVGNum.parse(el.attrs["cx"]) ?? 0
            let cy = SVGNum.parse(el.attrs["cy"]) ?? 0
            let r = SVGNum.parse(el.attrs["r"]) ?? 0
            guard r > 0 else { return nil }
            return Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
        case "ellipse":
            let cx = SVGNum.parse(el.attrs["cx"]) ?? 0
            let cy = SVGNum.parse(el.attrs["cy"]) ?? 0
            let rx = SVGNum.parse(el.attrs["rx"]) ?? 0
            let ry = SVGNum.parse(el.attrs["ry"]) ?? 0
            guard rx > 0, ry > 0 else { return nil }
            return Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry))
        case "line":
            let x1 = SVGNum.parse(el.attrs["x1"]) ?? 0
            let y1 = SVGNum.parse(el.attrs["y1"]) ?? 0
            let x2 = SVGNum.parse(el.attrs["x2"]) ?? 0
            let y2 = SVGNum.parse(el.attrs["y2"]) ?? 0
            var p = Path()
            p.move(to: CGPoint(x: x1, y: y1))
            p.addLine(to: CGPoint(x: x2, y: y2))
            return p
        case "polyline", "polygon":
            let nums = SVGNum.list(el.attrs["points"] ?? "")
            guard nums.count >= 4 else { return nil }
            var p = Path()
            p.move(to: CGPoint(x: nums[0], y: nums[1]))
            var i = 2
            while i + 1 < nums.count { p.addLine(to: CGPoint(x: nums[i], y: nums[i + 1])); i += 2 }
            if el.tag.lowercased() == "polygon" { p.closeSubpath() }
            return p
        default:
            return nil
        }
    }

    private static func geometryBounds(_ el: SVGElement, doc: SVGDocument) -> CGRect {
        if let p = geometryPath(el, doc: doc) {
            let b = p.boundingRect
            return b.isNull || b.isInfinite ? .zero : b
        }
        var rect: CGRect? = nil
        for c in el.children {
            let cb = geometryBounds(c, doc: doc)
            if cb.width > 0 || cb.height > 0 { rect = rect.map { $0.union(cb) } ?? cb }
        }
        return rect ?? .zero
    }

    private static func transformOrigin(_ el: SVGElement, env: SVGRenderEnv, bbox: CGRect) -> CGPoint {
        let decls = computedDecls(el, env: env)
        guard let raw = decls["transform-origin"] else {
            return CGPoint(x: bbox.midX, y: bbox.midY)
        }
        let tokens = raw.lowercased().split(separator: " ").map(String.init)
        func axis(_ t: String, span: CGFloat, base: CGFloat, isX: Bool) -> CGFloat {
            switch t {
            case "center": return base + span / 2
            case "left": return isX ? base : base + span / 2
            case "right": return isX ? base + span : base + span / 2
            case "top": return isX ? base + span / 2 : base
            case "bottom": return isX ? base + span / 2 : base + span
            default:
                if t.hasSuffix("%"), let v = Double(t.dropLast()) { return base + CGFloat(v) / 100 * span }
                return base + (SVGNum.parse(t) ?? span / 2)
            }
        }
        let xt = tokens.first ?? "center"
        let yt = tokens.count > 1 ? tokens[1] : "center"
        return CGPoint(x: axis(xt, span: bbox.width, base: bbox.minX, isX: true),
                       y: axis(yt, span: bbox.height, base: bbox.minY, isX: false))
    }

    // MARK: Cascade

    private static func computedDecls(_ el: SVGElement, env: SVGRenderEnv) -> [String: String] {
        var decls: [String: String] = [:]
        for (k, v) in el.attrs where presentationKeys.contains(k.lowercased()) {
            decls[k.lowercased()] = resolveVars(v, env.cssVars)
        }
        let normal = matchingRules(env.doc.stylesheet.rules, el)
        for r in normal { for (k, v) in r.decls { decls[k] = resolveVars(v, env.cssVars) } }
        if env.dark {
            for r in matchingRules(env.doc.stylesheet.darkRules, el) { for (k, v) in r.decls { decls[k] = resolveVars(v, env.cssVars) } }
        }
        for (k, v) in SVGParser.inlineStyle(el.attrs["style"]) { decls[k] = resolveVars(v, env.cssVars) }
        return decls
    }

    private static func matchingRules(_ rules: [SVGRule], _ el: SVGElement) -> [SVGRule] {
        let classes = Set(el.classNames)
        let tag = el.tag.lowercased()
        let id = el.id
        return rules.filter { rule in
            rule.selectors.contains { sel in
                switch sel {
                case .cls(let c): return classes.contains(c)
                case .tag(let t): return t == tag
                case .id(let i): return i == id
                case .universal: return true
                }
            }
        }.sorted { ($0.specificity, $0.order) < ($1.specificity, $1.order) }
    }

    private static func resolve(_ el: SVGElement, base: SVGComputedStyle, env: SVGRenderEnv) -> SVGComputedStyle {
        var s = base
        let d = computedDecls(el, env: env)
        if let v = d["color"], let c = SVGColor.parse(v) { s.currentColor = c }
        if let v = d["fill"] { s.fill = v }
        if let v = d["stroke"] { s.stroke = v }
        if let v = SVGNum.parse(d["stroke-width"]) { s.strokeWidth = v }
        if let v = SVGNum.parse(d["opacity"]) { s.opacity = v }
        if let v = SVGNum.parse(d["fill-opacity"]) { s.fillOpacity = v }
        if let v = SVGNum.parse(d["stroke-opacity"]) { s.strokeOpacity = v }
        if let v = d["fill-rule"] { s.fillRuleEvenOdd = (v.lowercased() == "evenodd") }
        if let v = d["stroke-dasharray"], v.lowercased() != "none" {
            let arr = SVGNum.list(v); if !arr.isEmpty { s.strokeDash = arr }
        }
        if let v = d["stroke-linecap"]?.lowercased() {
            s.lineCap = v == "round" ? .round : (v == "square" ? .square : .butt)
        }
        if let v = d["stroke-linejoin"]?.lowercased() {
            s.lineJoin = v == "round" ? .round : (v == "bevel" ? .bevel : .miter)
        }
        if let v = SVGNum.parse(d["font-size"]) { s.fontSize = v }
        if let v = d["font-weight"]?.lowercased() { s.fontWeight = fontWeight(v) }
        if let v = d["text-anchor"]?.lowercased() { s.textAnchor = v }
        if let v = d["display"]?.lowercased() { s.display = (v != "none") }
        if let v = d["visibility"]?.lowercased(), v == "hidden" || v == "collapse" { s.display = false }
        return s
    }

    private static func fontWeight(_ s: String) -> Font.Weight {
        switch s {
        case "bold", "700": return .bold
        case "600": return .semibold
        case "500": return .medium
        case "800", "900": return .heavy
        case "300": return .light
        case "200", "100": return .thin
        default: return .regular
        }
    }

    /// Resolve CSS `var(--name)` / `var(--name, fallback)` references in a value.
    static func resolveVars(_ value: String?, _ vars: [String: String]) -> String? {
        guard let value = value else { return nil }
        guard value.contains("var(") else { return value }
        var out = value
        while let range = out.range(of: "var(") {
            guard let close = out[range.upperBound...].firstIndex(of: ")") else { break }
            let inner = String(out[range.upperBound..<close])
            let parts = inner.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let name = parts.first ?? ""
            let fallback = parts.count > 1 ? parts[1] : "0"
            let replacement = vars[name] ?? fallback
            out.replaceSubrange(range.lowerBound...close, with: replacement)
        }
        return out
    }

    private static let presentationKeys: Set<String> = [
        "fill", "stroke", "stroke-width", "opacity", "fill-opacity", "stroke-opacity",
        "fill-rule", "stroke-dasharray", "stroke-linecap", "stroke-linejoin",
        "font-size", "font-weight", "font-family", "text-anchor", "color", "display",
        "visibility", "transform-origin", "transform",
    ]
}
