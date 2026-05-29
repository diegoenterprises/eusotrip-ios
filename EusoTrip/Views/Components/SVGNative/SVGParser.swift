//
//  SVGParser.swift
//  EusoTrip — Native SVG renderer · XML → SVGDocument.
//
//  Builds the element tree with a push-based XMLParser, then post-processes:
//  resolves the viewBox, harvests <style> CSS, builds the gradient table
//  (with xlink:href stop inheritance), and indexes every id'd element so
//  <use> can resolve its referent.
//

import Foundation
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

        let stylesheet = SVGCSSParser.parse(styleText)
        let builtGradients = buildGradients(gradients)
        let viewBox = resolveViewBox(root)

        return SVGDocument(root: root, viewBox: viewBox, gradients: builtGradients,
                           defsById: defsById, stylesheet: stylesheet)
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
            out[id] = SVGGradient(kind: kind, stops: ownStops, userSpace: userSpace, transform: transform)
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
            let v = chunk[chunk.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !k.isEmpty && !v.isEmpty { out[k] = v }
        }
        return out
    }
}
