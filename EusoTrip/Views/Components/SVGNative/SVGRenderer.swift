//
//  SVGRenderer.swift
//  EusoTrip — Native SVG renderer · scene graph → SwiftUI Canvas.
//
//  Walks the SVGDocument and paints it into a GraphicsContext at a given time.
//  Honors the SVG/CSS cascade (presentation attrs < stylesheet < dark <
//  reduced-motion < inline), viewBox → fit transform (xMidYMid meet), nested
//  group transforms/opacity, gradients (object-bbox + userSpace), <pattern>
//  tile fills, <use>/<symbol> resolution, dashed/capped strokes (with
//  animated dashPhase), <text>/<tspan> ordered runs, and per-element animation
//  including SMIL/keyframed geometry (r/cy/cx/x/y/width/height) and fill.
//
//  Native equivalents of the old WKWebView data-binding layer:
//    • bindings  — `data-bind="key"` <text>/<tspan> nodes render the live value
//    • placardId — `<use href="#commodityPlacard">` remaps to the hazmat class
//    • cssVars   — `var(--load-progress)` etc. resolve before parsing
//    • country   — exactly ONE of .country-US/-MX/-CA renders (nil = US)
//
//  Wave E perf: the hot path reads only SVGBaker-baked data — no per-frame
//  rule matching, path parsing, tag lowercasing, or animation-shorthand
//  splitting. Per-frame work is animation evaluation + Canvas draw calls.
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
    var strokeDashoffset: CGFloat = 0
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
    let country: SVGCountry?
    /// Baked-cascade combo index: bit 0 = dark, bit 1 = reduced-motion.
    let comboMask: Int
}

enum SVGRenderer {

    static func render(document: SVGDocument, into ctx: GraphicsContext, size: CGSize,
                       time: Double, reduceMotion: Bool, dark: Bool,
                       bindings: [String: String] = [:], placardId: String? = nil,
                       cssVars: [String: String] = [:], country: SVGCountry? = nil) {
        let vb = document.viewBox
        guard vb.width > 0, vb.height > 0 else { return }
        let scale = min(size.width / vb.width, size.height / vb.height)
        let tx = (size.width - vb.width * scale) / 2 - vb.minX * scale
        let ty = (size.height - vb.height * scale) / 2 - vb.minY * scale
        var base = ctx
        base.concatenate(CGAffineTransform(translationX: tx, y: ty).scaledBy(x: scale, y: scale))

        let env = SVGRenderEnv(doc: document, time: time, reduceMotion: reduceMotion, dark: dark,
                               bindings: bindings, placardId: placardId, cssVars: cssVars,
                               country: country,
                               comboMask: (dark ? 1 : 0) | (reduceMotion ? 2 : 0))
        var inherited = SVGComputedStyle()
        inherited = resolve(document.root, base: inherited, env: env)
        for child in document.root.children {
            draw(child, into: base, inherited: inherited.inheritable(), accumulatedOpacity: 1, env: env, depth: 0)
        }
    }

    // MARK: Recursive draw

    private static func draw(_ el: SVGElement, into ctx: GraphicsContext, inherited: SVGComputedStyle,
                             accumulatedOpacity: CGFloat, env: SVGRenderEnv, depth: Int) {
        if depth > 64 { return }   // cycle/recursion guard for <use>/<pattern>
        let kind = el.bakedKind
        if kind == .skipped || kind == .textRun { return }

        let style = resolve(el, base: inherited, env: env)
        if !style.display { return }

        let mask = env.comboMask
        var anim = AnimatedState()
        if !env.reduceMotion {
            let specs = el.bakedAnimationSpecs.isEmpty ? [] : el.bakedAnimationSpecs[mask]
            if !specs.isEmpty {
                SVGAnimation.cssState(specs: specs, keyframes: env.doc.stylesheet.keyframes,
                                      time: env.time, origin: el.bakedOrigins[mask],
                                      cssVars: env.cssVars, into: &anim)
            }
            if !el.bakedSMILChildren.isEmpty {
                SVGAnimation.smilState(element: el, time: env.time,
                                       origin: el.bakedOrigins.isEmpty ? CGPoint(x: el.bakedBBox.midX, y: el.bakedBBox.midY) : el.bakedOrigins[mask],
                                       into: &anim)
            }
        }

        let staticT: CGAffineTransform
        if el.bakedTransformHasVar {
            staticT = dynamicTransform(el, env: env)
        } else {
            staticT = el.bakedStaticTransforms.isEmpty ? .identity : el.bakedStaticTransforms[mask]
        }

        let elementOpacity = accumulatedOpacity * style.opacity * anim.opacityMultiplier
        var sub = ctx
        sub.concatenate(staticT)
        sub.concatenate(anim.extraTransform)
        sub.opacity = elementOpacity

        switch kind {
        case .group:
            for c in el.children {
                draw(c, into: sub, inherited: style.inheritable(), accumulatedOpacity: 1, env: env, depth: depth + 1)
            }
        case .use:
            drawUse(el, into: sub, style: style, env: env, depth: depth)
        case .text, .tspan:
            drawText(el, into: sub, style: style, env: env, anim: anim)
        case .geometry, .other:
            let path: Path?
            if anim.hasGeometryOverride || el.bakedNeedsDynamicPath {
                path = buildGeometryPath(el, overrides: anim, cssVars: env.cssVars)
            } else {
                path = el.bakedStaticPath
            }
            if let path = path {
                paint(path, style: style, anim: anim, elementOpacity: elementOpacity,
                      into: sub, env: env, bbox: el.bakedBBox, depth: depth)
            }
        case .skipped, .textRun:
            break
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

    /// Per-frame transform for elements whose transform attr/decl carries
    /// `var(` refs (e.g. the authored `scaleX(var(--load-progress))` channel).
    private static func dynamicTransform(_ el: SVGElement, env: SVGRenderEnv) -> CGAffineTransform {
        let mask = env.comboMask
        let decls = el.bakedDecls.isEmpty ? [:] : el.bakedDecls[mask]
        let attrRaw = el.attrs["transform"]
        var m = SVGTransform.parse(resolveVars(attrRaw, env.cssVars))
        if let d = decls["transform"], d != attrRaw {
            let resolved = resolveVars(d, env.cssVars) ?? d
            let origin = el.bakedOrigins.isEmpty ? CGPoint(x: el.bakedBBox.midX, y: el.bakedBBox.midY) : el.bakedOrigins[mask]
            m = m.concatenating(SVGAnimation.matrix(from: resolved, origin: origin))
        }
        return m
    }

    // MARK: Painting

    private static func paint(_ path: Path, style: SVGComputedStyle, anim: AnimatedState,
                              elementOpacity: CGFloat, into ctx: GraphicsContext,
                              env: SVGRenderEnv, bbox: CGRect, depth: Int) {
        let doc = env.doc
        // FILL — animated fill override wins; then pattern; then color/gradient.
        if let override = anim.fillOverride {
            ctx.fill(path, with: .color(override.color.opacity(style.fillOpacity)),
                     style: FillStyle(eoFill: style.fillRuleEvenOdd))
        } else if let fill = style.fill, !isNone(fill) {
            if let patternEl = patternRef(fill, doc: doc) {
                paintPattern(patternEl, clipPath: path, eoFill: style.fillRuleEvenOdd,
                             fillOpacity: style.fillOpacity, elementOpacity: elementOpacity,
                             into: ctx, env: env, depth: depth)
            } else if let shading = shading(for: fill, opacity: style.fillOpacity, style: style, doc: doc, bbox: bbox) {
                ctx.fill(path, with: shading, style: FillStyle(eoFill: style.fillRuleEvenOdd))
            }
        }
        // STROKE — with static/animated dash phase (the hose-flow visuals).
        if let stroke = style.stroke, !isNone(stroke), style.strokeWidth > 0 {
            if let shading = shading(for: stroke, opacity: style.strokeOpacity, style: style, doc: doc, bbox: bbox) {
                let strokeStyle = StrokeStyle(
                    lineWidth: style.strokeWidth,
                    lineCap: style.lineCap,
                    lineJoin: style.lineJoin,
                    dash: style.strokeDash ?? [],
                    dashPhase: anim.dashoffset ?? style.strokeDashoffset
                )
                ctx.stroke(path, with: shading, style: strokeStyle)
            }
        }
    }

    /// Case-insensitive "none" check without allocating a lowercased copy of
    /// (potentially long) url() paint strings on the per-frame paint path.
    private static func isNone(_ s: String) -> Bool {
        s == "none" || s.caseInsensitiveCompare("none") == .orderedSame
    }

    /// Resolve a `url(#id)` paint to a <pattern> element, if that's what it names.
    private static func patternRef(_ paint: String, doc: SVGDocument) -> SVGElement? {
        let p = (paint.first == " " || paint.last == " ")
            ? paint.trimmingCharacters(in: .whitespaces) : paint
        guard p.hasPrefix("url(") || p.hasPrefix("URL(") else { return nil }
        guard let open = p.firstIndex(of: "#"), let close = p.lastIndex(of: ")") else { return nil }
        let id = String(p[p.index(after: open)..<close]).trimmingCharacters(in: CharacterSet(charactersIn: " )\"'"))
        guard let el = doc.defsById[id], el.bakedKind == .skipped, el.tag.lowercased() == "pattern" else { return nil }
        return el
    }

    /// Tile a <pattern> (userSpaceOnUse, the only unit the corpus authors)
    /// into the clip region of `clipPath`. DOT conspicuity tape, hazard
    /// striping, diamond plate, shrink wrap — regulated visuals that used to
    /// vanish because shading() returned nil for pattern refs.
    private static func paintPattern(_ pattern: SVGElement, clipPath: Path, eoFill: Bool,
                                     fillOpacity: CGFloat, elementOpacity: CGFloat,
                                     into ctx: GraphicsContext, env: SVGRenderEnv, depth: Int) {
        guard depth < 60 else { return }
        let pw = SVGNum.parse(pattern.attrs["width"]) ?? 0
        let ph = SVGNum.parse(pattern.attrs["height"]) ?? 0
        guard pw > 0, ph > 0 else { return }
        let px = SVGNum.parse(pattern.attrs["x"]) ?? 0
        let py = SVGNum.parse(pattern.attrs["y"]) ?? 0
        let patternT = SVGTransform.parse(pattern.attrs["patternTransform"])

        let bounds = clipPath.boundingRect
        guard !bounds.isNull, !bounds.isInfinite, bounds.width > 0, bounds.height > 0 else { return }

        var layer = ctx
        layer.clip(to: clipPath, style: FillStyle(eoFill: eoFill))
        layer.concatenate(patternT)

        // Coverage of the clip region expressed in pattern space.
        let coverage = bounds.applying(patternT.inverted())
        let c0 = Int(floor((coverage.minX - px) / pw))
        let c1 = Int(ceil((coverage.maxX - px) / pw))
        let r0 = Int(floor((coverage.minY - py) / ph))
        let r1 = Int(ceil((coverage.maxY - py) / ph))
        guard c1 > c0, r1 > r0, (c1 - c0) * (r1 - r0) <= 8192 else { return }   // pathological-area guard

        let inherited = SVGComputedStyle()
        let tileOpacity = elementOpacity * fillOpacity
        for row in r0..<r1 {
            for col in c0..<c1 {
                var tile = layer
                tile.translateBy(x: px + CGFloat(col) * pw, y: py + CGFloat(row) * ph)
                for child in pattern.children {
                    draw(child, into: tile, inherited: inherited.inheritable(),
                         accumulatedOpacity: tileOpacity, env: env, depth: depth + 1)
                }
            }
        }
    }

    private static func shading(for paint: String, opacity: CGFloat, style: SVGComputedStyle,
                                doc: SVGDocument, bbox: CGRect) -> GraphicsContext.Shading? {
        let p = (paint.first == " " || paint.last == " ")
            ? paint.trimmingCharacters(in: .whitespaces) : paint
        if p.hasPrefix("url(") || p.hasPrefix("URL(") {
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
        let g = scaleOpacity(grad.ui, by: opacity)
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

    // MARK: Text — ordered <tspan> runs (Wave E gap #1)

    private struct TextRun {
        var content: String
        var style: SVGComputedStyle
        var explicitX: CGFloat?
        var explicitY: CGFloat?
    }

    private static func drawText(_ el: SVGElement, into ctx: GraphicsContext, style: SVGComputedStyle,
                                 env: SVGRenderEnv, anim: AnimatedState) {
        var runs: [TextRun] = []
        collectRuns(el, style: style, env: env, pendingX: nil, pendingY: nil, into: &runs, depth: 0)
        normalizeWhitespace(&runs)
        guard !runs.isEmpty else { return }

        let baseX = anim.x ?? SVGNum.parse(el.attrs["x"]) ?? 0
        let baseY = anim.y ?? SVGNum.parse(el.attrs["y"]) ?? 0

        // Resolve + measure each run, then lay segments out per text-anchor.
        // A run with an explicit x starts a new segment (SVG <tspan x="…">).
        var resolved: [GraphicsContext.ResolvedText] = []
        var widths: [CGFloat] = []
        resolved.reserveCapacity(runs.count)
        widths.reserveCapacity(runs.count)
        let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        for run in runs {
            let color = textColor(run.style)
            let t = Text(run.content)
                .font(.system(size: run.style.fontSize, weight: run.style.fontWeight))
                .foregroundColor(color.opacity(run.style.fillOpacity))
            let r = ctx.resolve(t)
            resolved.append(r)
            widths.append(r.measure(in: unbounded).width)
        }

        var i = 0
        var penY = baseY
        while i < runs.count {
            // segment = [i, j)
            var j = i + 1
            while j < runs.count && runs[j].explicitX == nil { j += 1 }
            let segWidth = widths[i..<j].reduce(0, +)
            let anchorX = runs[i].explicitX ?? baseX
            if let y = runs[i].explicitY { penY = y }
            var penX: CGFloat
            switch style.textAnchor {
            case "middle": penX = anchorX - segWidth / 2
            case "end": penX = anchorX - segWidth
            default: penX = anchorX
            }
            for k in i..<j {
                let y = runs[k].explicitY ?? penY
                ctx.draw(resolved[k], at: CGPoint(x: penX, y: y), anchor: UnitPoint(x: 0, y: 0.75))
                penX += widths[k]
            }
            i = j
        }
    }

    /// Walk the ordered mixed content of a <text>/<tspan>: literal "#text"
    /// runs + nested tspans (with their own cascade + data-bind overrides).
    private static func collectRuns(_ el: SVGElement, style: SVGComputedStyle, env: SVGRenderEnv,
                                    pendingX: CGFloat?, pendingY: CGFloat?,
                                    into runs: inout [TextRun], depth: Int) {
        if depth > 8 { return }
        // data-bind: a live value replaces this element's ENTIRE content;
        // empty/missing bindings keep the authored default.
        if let key = el.attrs["data-bind"], let bound = env.bindings[key], !bound.isEmpty {
            runs.append(TextRun(content: bound, style: style, explicitX: pendingX, explicitY: pendingY))
            return
        }
        if el.children.isEmpty {
            let content = el.text ?? ""
            if !content.isEmpty {
                runs.append(TextRun(content: content, style: style, explicitX: pendingX, explicitY: pendingY))
            }
            return
        }
        var px = pendingX, py = pendingY
        for c in el.children {
            switch c.bakedKind {
            case .textRun:
                let content = c.text ?? ""
                if !content.isEmpty {
                    runs.append(TextRun(content: content, style: style, explicitX: px, explicitY: py))
                    px = nil; py = nil
                }
            case .tspan:
                let childStyle = resolve(c, base: style.inheritable(), env: env)
                guard childStyle.display else { continue }
                let cx = SVGNum.parse(c.attrs["x"]) ?? px
                let cy = SVGNum.parse(c.attrs["y"]) ?? py
                collectRuns(c, style: childStyle, env: env, pendingX: cx, pendingY: cy,
                            into: &runs, depth: depth + 1)
                px = nil; py = nil
            default:
                continue
            }
        }
    }

    /// Collapse internal whitespace to single spaces (xml:space default) and
    /// trim the boundary runs, dropping any that end up empty.
    private static func normalizeWhitespace(_ runs: inout [TextRun]) {
        for i in runs.indices {
            runs[i].content = collapseWhitespace(runs[i].content)
        }
        if var first = runs.first {
            while first.content.hasPrefix(" ") { first.content.removeFirst() }
            runs[0] = first
        }
        if var last = runs.last {
            while last.content.hasSuffix(" ") { last.content.removeLast() }
            runs[runs.count - 1] = last
        }
        runs.removeAll { $0.content.isEmpty }
    }

    private static func collapseWhitespace(_ s: String) -> String {
        guard s.contains(where: { $0 == "\n" || $0 == "\t" || $0 == "\r" || $0 == " " }) else { return s }
        var out = ""
        out.reserveCapacity(s.count)
        var lastWS = false
        for ch in s {
            if ch == " " || ch == "\n" || ch == "\t" || ch == "\r" {
                if !lastWS { out.append(" ") }
                lastWS = true
            } else {
                out.append(ch)
                lastWS = false
            }
        }
        return out
    }

    private static func textColor(_ style: SVGComputedStyle) -> Color {
        let colorStr = style.fill ?? "black"
        if colorStr.lowercased() == "currentcolor" { return style.currentColor }
        return SVGColor.parse(colorStr) ?? .black
    }

    // MARK: Geometry (bake-time + animated-override builds)

    /// Build a geometry Path from attributes, with optional animated overrides
    /// (SMIL r/cy/cx, keyframed x/y/width/height) and optional var() resolution.
    /// Called at bake time (overrides nil) and per frame only for the few
    /// elements that animate geometry or carry var()-bearing attrs.
    static func buildGeometryPath(_ el: SVGElement, overrides: AnimatedState?, cssVars: [String: String]?) -> Path? {
        func attr(_ key: String) -> String? {
            guard let v = el.attrs[key] else { return nil }
            if let vars = cssVars, v.contains("var(") { return resolveVars(v, vars) }
            return v
        }
        switch el.tag.lowercased() {
        case "path":
            guard let d = attr("d") else { return nil }
            return SVGPathParser.path(from: d)
        case "rect":
            let x = overrides?.x ?? SVGNum.parse(attr("x")) ?? 0
            let y = overrides?.y ?? SVGNum.parse(attr("y")) ?? 0
            let w = overrides?.width ?? SVGNum.parse(attr("width")) ?? 0
            let h = overrides?.height ?? SVGNum.parse(attr("height")) ?? 0
            guard w > 0, h > 0 else { return nil }
            let rx = SVGNum.parse(attr("rx"))
            let ry = SVGNum.parse(attr("ry"))
            let rect = CGRect(x: x, y: y, width: w, height: h)
            if let r = rx ?? ry, r > 0 {
                return Path(roundedRect: rect, cornerSize: CGSize(width: rx ?? ry ?? 0, height: ry ?? rx ?? 0))
            }
            return Path(rect)
        case "circle":
            let cx = overrides?.cx ?? SVGNum.parse(attr("cx")) ?? 0
            let cy = overrides?.cy ?? SVGNum.parse(attr("cy")) ?? 0
            let r = overrides?.r ?? SVGNum.parse(attr("r")) ?? 0
            guard r > 0 else { return nil }
            return Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
        case "ellipse":
            let cx = overrides?.cx ?? SVGNum.parse(attr("cx")) ?? 0
            let cy = overrides?.cy ?? SVGNum.parse(attr("cy")) ?? 0
            let rx = SVGNum.parse(attr("rx")) ?? 0
            let ry = SVGNum.parse(attr("ry")) ?? 0
            guard rx > 0, ry > 0 else { return nil }
            return Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry))
        case "line":
            let x1 = SVGNum.parse(attr("x1")) ?? 0
            let y1 = SVGNum.parse(attr("y1")) ?? 0
            let x2 = SVGNum.parse(attr("x2")) ?? 0
            let y2 = SVGNum.parse(attr("y2")) ?? 0
            var p = Path()
            p.move(to: CGPoint(x: x1, y: y1))
            p.addLine(to: CGPoint(x: x2, y: y2))
            return p
        case "polyline", "polygon":
            let nums = SVGNum.list(attr("points") ?? "")
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

    // MARK: Style resolution (baked cascade → computed style)

    private static func resolve(_ el: SVGElement, base: SVGComputedStyle, env: SVGRenderEnv) -> SVGComputedStyle {
        var s = base
        let mask = env.comboMask
        let d: [String: String] = el.bakedDecls.isEmpty ? [:] : el.bakedDecls[mask]
        let hasVars = (el.bakedDeclsVarMask & UInt8(1 << mask)) != 0

        func dv(_ key: String) -> String? {
            guard let v = d[key] else { return nil }
            if hasVars, v.contains("var(") { return resolveVars(v, env.cssVars) }
            return v
        }

        if let v = dv("color"), let c = SVGColor.parse(v) { s.currentColor = c }
        if let v = dv("fill") { s.fill = v }
        if let v = dv("stroke") { s.stroke = v }
        if let v = SVGNum.parse(dv("stroke-width")) { s.strokeWidth = v }
        if let v = SVGNum.parse(dv("opacity")) { s.opacity = v }
        if let v = SVGNum.parse(dv("fill-opacity")) { s.fillOpacity = v }
        if let v = SVGNum.parse(dv("stroke-opacity")) { s.strokeOpacity = v }
        if let v = dv("fill-rule") { s.fillRuleEvenOdd = (v.lowercased() == "evenodd") }
        if let v = dv("stroke-dasharray"), v.lowercased() != "none" {
            let arr = SVGNum.list(v); if !arr.isEmpty { s.strokeDash = arr }
        }
        if let v = SVGNum.parse(dv("stroke-dashoffset")) { s.strokeDashoffset = v }
        if let v = dv("stroke-linecap")?.lowercased() {
            s.lineCap = v == "round" ? .round : (v == "square" ? .square : .butt)
        }
        if let v = dv("stroke-linejoin")?.lowercased() {
            s.lineJoin = v == "round" ? .round : (v == "bevel" ? .bevel : .miter)
        }
        if let v = SVGNum.parse(dv("font-size")) { s.fontSize = v }
        if let v = dv("font-weight")?.lowercased() { s.fontWeight = fontWeight(v) }
        if let v = dv("text-anchor")?.lowercased() { s.textAnchor = v }
        if let v = dv("display")?.lowercased() { s.display = (v != "none") }
        if let v = dv("visibility")?.lowercased(), v == "hidden" || v == "collapse" { s.display = false }

        // COUNTRY-GROUP TOGGLE (Wave E API; Wave C wires real load regions).
        // Exactly one of country-US / country-MX / country-CA renders per
        // pass: the override is applied AFTER the document's own cascade so a
        // broken [data-country] selector reduction can never hide the US set
        // or double-render MX+CA. nil country = the US default.
        if let cc = el.bakedCountry {
            s.display = (cc == (env.country ?? .us))
        }
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
}
