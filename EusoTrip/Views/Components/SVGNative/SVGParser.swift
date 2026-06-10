//
//  SVGParser.swift
//  EusoTrip — Native SVG renderer · XML → SVGDocument.
//
//  Builds the element tree with a push-based XMLParser, then post-processes:
//  resolves the viewBox, harvests <style> CSS, builds the gradient table
//  (with xlink:href stop inheritance), indexes every id'd element so <use>
//  can resolve its referent — and runs SVGBaker, the Wave E compile pass that
//  pre-computes EVERYTHING the renderer used to derive per frame: parsed
//  paths, bboxes, merged cascades per dark/reduced combo, animation specs,
//  compiled keyframes/SMIL, transform origins (transform-box aware), static
//  transforms, and country group membership. After bake the render path is
//  read-only — no string parsing, no rule matching, no path re-parsing.
//

import Foundation
import SwiftUI
import CoreGraphics

enum SVGParser {

    static func parse(data: Data) -> SVGDocument? {
        let delegate = TreeBuilder()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse(), let root = delegate.root else { return nil }
        return finish(root: root)
    }

    static func parse(string: String) -> SVGDocument? {
        guard let data = string.data(using: .utf8) else { return nil }
        return parse(data: data)
    }

    // MARK: Tree builder

    private final class TreeBuilder: NSObject, XMLParserDelegate {
        var root: SVGElement?
        private var stack: [SVGElement] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            let tag = localName(elementName)
            let el = SVGElement(tag: tag, attrs: attributeDict)
            el.parent = stack.last
            if let top = stack.last {
                top.children.append(el)
            } else {
                root = el
            }
            stack.append(el)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            if !stack.isEmpty { stack.removeLast() }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard let top = stack.last else { return }
            top.text = (top.text ?? "") + string
            // Ordered mixed-content runs — the tspan pipeline needs to know
            // that "<tspan>78,500 LBS</tspan> · <tspan>50</tspan>%" is
            // run·tspan·run·tspan·run IN ORDER, which flat `text` loses.
            let t = top.tag.lowercased()
            if t == "text" || t == "tspan" {
                if let last = top.children.last, last.tag == "#text" {
                    last.text = (last.text ?? "") + string
                } else {
                    let run = SVGElement(tag: "#text", attrs: [:])
                    run.text = string
                    run.parent = top
                    top.children.append(run)
                }
            }
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            guard let top = stack.last, let s = String(data: CDATABlock, encoding: .utf8) else { return }
            top.text = (top.text ?? "") + s
        }

        private func localName(_ name: String) -> String {
            if let colon = name.firstIndex(of: ":") { return String(name[name.index(after: colon)...]) }
            return name
        }
    }

    // MARK: Post-processing

    private static func finish(root: SVGElement) -> SVGDocument {
        var gradients: [String: SVGElement] = [:]
        var defsById: [String: SVGElement] = [:]
        var styleText = ""

        func walk(_ el: SVGElement) {
            if let id = el.id { defsById[id] = el }
            switch el.tag {
            case "style": styleText += (el.text ?? "")
            case "linearGradient", "radialGradient":
                if let id = el.id { gradients[id] = el }
            default: break
            }
            for c in el.children { walk(c) }
        }
        walk(root)

        var stylesheet = SVGCSSParser.parse(styleText)
        let builtGradients = buildGradients(gradients)
        let viewBox = resolveViewBox(root)

        // Wave E — the bake pass. Must run before the document is published.
        let facts = SVGBaker.bake(root: root, viewBox: viewBox, stylesheet: &stylesheet)

        return SVGDocument(root: root, viewBox: viewBox, gradients: builtGradients,
                           defsById: defsById, stylesheet: stylesheet,
                           isAnimated: facts.isAnimated,
                           bindKeys: facts.bindKeys,
                           usesCSSVars: facts.usesCSSVars,
                           hasCountryGroups: facts.hasCountryGroups)
    }

    private static func resolveViewBox(_ root: SVGElement) -> CGRect {
        if let vb = root.attrs["viewBox"] ?? root.attrs["viewbox"] {
            let n = SVGNum.list(vb)
            if n.count == 4 { return CGRect(x: n[0], y: n[1], width: n[2], height: n[3]) }
        }
        let w = SVGNum.parse(root.attrs["width"]) ?? 100
        let h = SVGNum.parse(root.attrs["height"]) ?? 100
        return CGRect(x: 0, y: 0, width: w, height: h)
    }

    private static func buildGradients(_ raw: [String: SVGElement]) -> [String: SVGGradient] {
        // First pass: own stops. Second pass: inherit stops/attrs via xlink:href.
        func stops(of el: SVGElement) -> [SVGGradientStop] {
            el.children.compactMap { c -> SVGGradientStop? in
                guard c.tag == "stop" else { return nil }
                let style = inlineStyle(c.attrs["style"])
                let offRaw = c.attrs["offset"] ?? "0"
                let offset: CGFloat
                if offRaw.hasSuffix("%") { offset = (SVGNum.parse(Substring(offRaw.dropLast())) ?? 0) / 100 }
                else { offset = SVGNum.parse(offRaw) ?? 0 }
                let colorStr = style["stop-color"] ?? c.attrs["stop-color"] ?? "#000"
                let opacityStr = style["stop-opacity"] ?? c.attrs["stop-opacity"]
                let color = SVGColor.parse(colorStr) ?? .black
                let opacity = SVGNum.parse(opacityStr) ?? 1
                return SVGGradientStop(offset: min(1, max(0, offset)), color: color, opacity: opacity)
            }
        }
        func href(of el: SVGElement) -> String? {
            let h = el.attrs["xlink:href"] ?? el.attrs["href"]
            return h?.hasPrefix("#") == true ? String(h!.dropFirst()) : nil
        }

        var out: [String: SVGGradient] = [:]
        for (id, el) in raw {
            var ownStops = stops(of: el)
            // resolve inherited stops one level (corpus depth is ≤1)
            var attrSource = el
            if ownStops.isEmpty, let hid = href(of: el), let parent = raw[hid] {
                ownStops = stops(of: parent)
                attrSource = parent
            }
            let userSpace = (el.attrs["gradientUnits"] ?? attrSource.attrs["gradientUnits"]) == "userSpaceOnUse"
            let transform = SVGTransform.parse(el.attrs["gradientTransform"] ?? attrSource.attrs["gradientTransform"])

            func coord(_ key: String, _ fallback: CGFloat) -> CGFloat {
                let v = el.attrs[key] ?? attrSource.attrs[key]
                guard let v = v else { return fallback }
                if v.hasSuffix("%") { return (SVGNum.parse(Substring(v.dropLast())) ?? 0) / 100 * (userSpace ? 1 : 1) }
                return SVGNum.parse(v) ?? fallback
            }

            let kind: SVGGradient.Kind
            if el.tag == "radialGradient" {
                kind = .radial(cx: coord("cx", 0.5), cy: coord("cy", 0.5), r: coord("r", 0.5))
            } else {
                kind = .linear(x1: coord("x1", 0), y1: coord("y1", 0),
                               x2: coord("x2", 1), y2: coord("y2", 0))
            }
            out[id] = SVGGradient(kind: kind, stops: ownStops, userSpace: userSpace,
                                  transform: transform, ui: SVGGradient.buildUI(ownStops))
        }
        return out
    }

    /// Parse an inline `style="a:b;c:d"` attribute into a dictionary.
    static func inlineStyle(_ raw: String?) -> [String: String] {
        guard let raw = raw else { return [:] }
        var out: [String: String] = [:]
        for chunk in raw.split(separator: ";") {
            guard let colon = chunk.firstIndex(of: ":") else { continue }
            let k = chunk[chunk.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            var v = chunk[chunk.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if v.hasSuffix("!important") {
                v = String(v.dropLast("!important".count)).trimmingCharacters(in: .whitespaces)
            }
            if !k.isEmpty && !v.isEmpty { out[k] = v }
        }
        return out
    }
}

// MARK: - SVGBaker · the parse-time compile pass (Wave E)

/// Pre-computes every per-frame derivable fact onto the element tree so the
/// render hot path allocates nothing and parses nothing. Runs exactly once,
/// before the document is published to any view — render-path access is
/// read-only and needs no locking.
enum SVGBaker {

    struct DocFacts {
        var isAnimated = false
        var bindKeys: Set<String> = []
        var usesCSSVars = false
        var hasCountryGroups = false
    }

    /// Combo index layout: bit 0 = dark, bit 1 = reduced-motion.
    static let comboCount = 4

    static func bake(root: SVGElement, viewBox: CGRect, stylesheet: inout SVGStyleSheet) -> DocFacts {
        // 1) Compile every @keyframes block (transform strings → ops, numeric
        //    channels extracted, fill → RGBA) so frames lerp numerically.
        for (name, kf) in stylesheet.keyframes {
            var compiled = kf
            compiled.compiled = compileFrames(kf.frames)
            stylesheet.keyframes[name] = compiled
        }
        var facts = DocFacts()
        bakeElement(root, viewBox: viewBox, sheet: stylesheet, facts: &facts)
        return facts
    }

    // MARK: per-element bake (post-order so bboxes union bottom-up)

    private static func bakeElement(_ el: SVGElement, viewBox: CGRect,
                                    sheet: SVGStyleSheet, facts: inout DocFacts) {
        el.bakedKind = kind(for: el.tag)

        // data-bind census + var() census (DEBUG silent-fail diagnostics).
        if let bind = el.attrs["data-bind"], !bind.isEmpty { facts.bindKeys.insert(bind) }
        if !facts.usesCSSVars {
            for v in el.attrs.values where v.contains("var(") { facts.usesCSSVars = true; break }
        }

        // Country group membership (exact class-token match).
        for cls in el.classNames {
            if let c = SVGCountry.from(className: cls) {
                el.bakedCountry = c
                facts.hasCountryGroups = true
                break
            }
        }

        // SMIL: compile animate params on the animate element itself; collect
        // the pre-filtered child list on the animated element.
        el.bakedSMIL = compileSMIL(el)
        var smilKids: [SVGElement] = []
        for c in el.children {
            switch c.tag.lowercased() {
            case "animate", "animatetransform", "set": smilKids.append(c)
            default: break
            }
        }
        el.bakedSMILChildren = smilKids
        if !smilKids.isEmpty { facts.isAnimated = true }

        // Recurse children first (bbox unions bottom-up).
        for c in el.children {
            bakeElement(c, viewBox: viewBox, sheet: sheet, facts: &facts)
        }

        // Geometry: static path unless a geometry attribute carries var().
        if el.bakedKind == .geometry || el.bakedKind == .other {
            el.bakedNeedsDynamicPath = geometryAttrsHaveVar(el)
            if !el.bakedNeedsDynamicPath {
                el.bakedStaticPath = SVGRenderer.buildGeometryPath(el, overrides: nil, cssVars: nil)
            }
        }

        // BBox — same transform-naive union semantics the per-frame walk had.
        if let p = el.bakedStaticPath {
            let b = p.boundingRect
            el.bakedBBox = (b.isNull || b.isInfinite) ? .zero : b
        } else {
            var rect: CGRect? = nil
            for c in el.children {
                let cb = c.bakedBBox
                if cb.width > 0 || cb.height > 0 { rect = rect.map { $0.union(cb) } ?? cb }
            }
            el.bakedBBox = rect ?? .zero
        }

        // Cascade per combo. Identical combos share one dictionary (CoW).
        let normalRules = matching(sheet.rules, el)
        let darkRules = matching(sheet.darkRules, el)
        let reducedRules = matching(sheet.reducedMotionRules, el)
        let inline = SVGParser.inlineStyle(el.attrs["style"])

        let base = merged(el, normal: normalRules, dark: nil, reduced: nil, inline: inline)
        var decls = [base, base, base, base]
        if !darkRules.isEmpty {
            decls[1] = merged(el, normal: normalRules, dark: darkRules, reduced: nil, inline: inline)
        }
        if !reducedRules.isEmpty {
            decls[2] = merged(el, normal: normalRules, dark: nil, reduced: reducedRules, inline: inline)
        }
        if !darkRules.isEmpty || !reducedRules.isEmpty {
            decls[3] = merged(el, normal: normalRules,
                              dark: darkRules.isEmpty ? nil : darkRules,
                              reduced: reducedRules.isEmpty ? nil : reducedRules,
                              inline: inline)
        }
        el.bakedDecls = decls

        var varMask: UInt8 = 0
        for i in 0..<comboCount {
            if decls[i].values.contains(where: { $0.contains("var(") }) { varMask |= UInt8(1 << i) }
        }
        el.bakedDeclsVarMask = varMask
        if varMask != 0 { facts.usesCSSVars = true }

        // Animation specs per combo (var() in animation shorthand does not
        // occur in the corpus; if it ever does, fallback values apply).
        var specs: [[SVGAnimationSpec]] = [[], [], [], []]
        for i in 0..<comboCount {
            if i > 0, decls[i]["animation"] == decls[0]["animation"] {
                specs[i] = specs[0]
                continue
            }
            specs[i] = parseSpecs(decls[i]["animation"])
        }
        el.bakedAnimationSpecs = specs
        if !specs[0].isEmpty || !specs[1].isEmpty { facts.isAnimated = true }

        // Transform origin per combo (transform-box: fill-box | view-box).
        var origins: [CGPoint] = []
        origins.reserveCapacity(comboCount)
        for i in 0..<comboCount {
            origins.append(origin(for: el, decls: decls[i], viewBox: viewBox))
        }
        el.bakedOrigins = origins

        // Static transform per combo: SVG attr matrix (coordinate-origin
        // semantics, unchanged) ∘ CSS-decl matrix about the transform-origin
        // (calm poses in the reduced bucket; zero normal-bucket transform
        // decls exist in the corpus, so normal renders are bit-identical).
        let attrRaw = el.attrs["transform"]
        let anyDeclVar = (0..<comboCount).contains { decls[$0]["transform"]?.contains("var(") == true }
        if (attrRaw?.contains("var(") ?? false) || anyDeclVar {
            el.bakedTransformHasVar = true
            el.bakedStaticTransforms = [.identity, .identity, .identity, .identity]
        } else {
            let attrMatrix = SVGTransform.parse(attrRaw)
            var statics: [CGAffineTransform] = []
            statics.reserveCapacity(comboCount)
            for i in 0..<comboCount {
                var m = attrMatrix
                if let d = decls[i]["transform"], d != attrRaw {
                    m = m.concatenating(SVGAnimation.matrix(from: d, origin: origins[i]))
                }
                statics.append(m)
            }
            el.bakedStaticTransforms = statics
        }
    }

    // MARK: classification

    private static func kind(for tag: String) -> SVGElementKind {
        switch tag.lowercased() {
        case "g", "svg", "a", "switch": return .group
        case "use": return .use
        case "text": return .text
        case "tspan": return .tspan
        case "#text": return .textRun
        case "path", "rect", "circle", "ellipse", "line", "polyline", "polygon": return .geometry
        case "defs", "style", "lineargradient", "radialgradient", "symbol", "clippath",
             "mask", "filter", "title", "desc", "metadata", "animate", "animatetransform",
             "animatemotion", "set", "marker", "pattern", "stop":
            return .skipped
        default: return .other
        }
    }

    private static func geometryAttrsHaveVar(_ el: SVGElement) -> Bool {
        for key in ["d", "x", "y", "width", "height", "rx", "ry", "cx", "cy", "r",
                    "x1", "y1", "x2", "y2", "points"] {
            if el.attrs[key]?.contains("var(") == true { return true }
        }
        return false
    }

    // MARK: cascade

    static let presentationKeys: Set<String> = [
        "fill", "stroke", "stroke-width", "opacity", "fill-opacity", "stroke-opacity",
        "fill-rule", "stroke-dasharray", "stroke-dashoffset", "stroke-linecap", "stroke-linejoin",
        "font-size", "font-weight", "font-family", "text-anchor", "color", "display",
        "visibility", "transform-origin", "transform-box", "transform",
    ]

    private static func matching(_ rules: [SVGRule], _ el: SVGElement) -> [SVGRule] {
        guard !rules.isEmpty else { return [] }
        let classes = el.classNames
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

    private static func merged(_ el: SVGElement, normal: [SVGRule], dark: [SVGRule]?,
                               reduced: [SVGRule]?, inline: [String: String]) -> [String: String] {
        var d: [String: String] = [:]
        for (k, v) in el.attrs where presentationKeys.contains(k.lowercased()) {
            d[k.lowercased()] = v
        }
        for r in normal { for (k, v) in r.decls { d[k] = v } }
        if let dark = dark { for r in dark { for (k, v) in r.decls { d[k] = v } } }
        if let reduced = reduced { for r in reduced { for (k, v) in r.decls { d[k] = v } } }
        for (k, v) in inline { d[k] = v }
        return d
    }

    private static func parseSpecs(_ animationValue: String?) -> [SVGAnimationSpec] {
        guard let a = animationValue, a.lowercased() != "none" else { return [] }
        return SVGAnimation.splitAnimations(a).compactMap { SVGAnimationSpec.parse($0) }
    }

    // MARK: transform origin (transform-box aware)

    private static func origin(for el: SVGElement, decls: [String: String], viewBox: CGRect) -> CGPoint {
        // Reference box: fill-box (default, = element bbox) or view-box
        // (= the document viewBox — fixes the petro loading-arm pivots and
        // the 36/37/38/39 boom/bed articulations).
        let box: CGRect
        if decls["transform-box"]?.lowercased() == "view-box" {
            box = viewBox
        } else {
            box = el.bakedBBox
        }
        guard let raw = decls["transform-origin"] else {
            return CGPoint(x: box.midX, y: box.midY)
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
        return CGPoint(x: axis(xt, span: box.width, base: box.minX, isX: true),
                       y: axis(yt, span: box.height, base: box.minY, isX: false))
    }

    // MARK: keyframes compile

    private static func compileFrames(_ frames: [(pct: CGFloat, decls: [String: String])]) -> [SVGCompiledFrame] {
        frames.map { f in
            var c = SVGCompiledFrame(pct: f.pct)
            if let t = f.decls["transform"] {
                if t.contains("var(") { c.transformRaw = t } else { c.ops = SVGAnimation.parseOps(t) }
            }
            c.opacity = SVGNum.parse(f.decls["opacity"])
            c.x = SVGNum.parse(f.decls["x"])
            c.y = SVGNum.parse(f.decls["y"])
            c.r = SVGNum.parse(f.decls["r"])
            c.cx = SVGNum.parse(f.decls["cx"])
            c.cy = SVGNum.parse(f.decls["cy"])
            c.width = SVGNum.parse(f.decls["width"])
            c.height = SVGNum.parse(f.decls["height"])
            c.dashoffset = SVGNum.parse(f.decls["stroke-dashoffset"])
            if let fill = f.decls["fill"] { c.fill = SVGRGBA.parse(fill) }
            return c
        }
    }

    // MARK: SMIL compile

    private static func compileSMIL(_ el: SVGElement) -> SVGSMILCompiled? {
        let kind: SVGSMILCompiled.Kind
        switch el.tag.lowercased() {
        case "animate": kind = .animate
        case "animatetransform": kind = .animateTransform
        case "set": kind = .set
        default: return nil
        }
        var frames: [SVGSMILVec] = []
        var keyTimes: [CGFloat]? = nil
        if let valuesStr = el.attrs["values"] {
            frames = valuesStr.split(separator: ";").map { SVGSMILVec(SVGNum.list(String($0))) }
            if frames.count >= 2, let kt = el.attrs["keyTimes"] {
                // keyTimes are SEMICOLON-separated per SMIL ("0;0.5;1") — the
                // generic list scanner never split them, so they were dropped.
                let parsed = kt.split(separator: ";").compactMap { SVGNum.parse($0) }
                if parsed.count == frames.count { keyTimes = parsed }
            }
        } else if let from = el.attrs["from"], let to = el.attrs["to"] {
            frames = [SVGSMILVec(SVGNum.list(from)), SVGSMILVec(SVGNum.list(to))]
        } else if let to = el.attrs["to"] {
            frames = [SVGSMILVec(SVGNum.list(to))]
        }
        return SVGSMILCompiled(
            kind: kind,
            attributeName: (el.attrs["attributeName"] ?? "").lowercased(),
            transformType: (el.attrs["type"] ?? "translate").lowercased(),
            dur: SVGAnimation.parseClock(el.attrs["dur"]) ?? 0,
            begin: SVGAnimation.parseClock(el.attrs["begin"]) ?? 0,
            repeats: el.attrs["repeatCount"]?.lowercased() == "indefinite",
            freeze: (el.attrs["fill"] ?? "remove") == "freeze",
            frames: frames,
            keyTimes: keyTimes
        )
    }
}
