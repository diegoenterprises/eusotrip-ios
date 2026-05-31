//
//  SVGCSSParser.swift
//  EusoTrip — Native SVG renderer · CSS <style> parser.
//
//  Parses the inline <style> block into style rules, @keyframes, and the two
//  @media buckets the corpus actually uses: (prefers-reduced-motion: reduce)
//  and (prefers-color-scheme: dark). Brace-matched so nested @media/@keyframes
//  blocks parse correctly; unknown at-rules and media queries are skipped.
//

import Foundation
import CoreGraphics

enum SVGCSSParser {

    private enum Bucket { case normal, reducedMotion, dark, ignored }

    static func parse(_ raw: String) -> SVGStyleSheet {
        var sheet = SVGStyleSheet()
        var order = 0
        parseRuleList(stripComments(raw), into: &sheet, bucket: .normal, order: &order)
        return sheet
    }

    private static func stripComments(_ s: String) -> String {
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "/", s.index(after: i) < s.endIndex, s[s.index(after: i)] == "*" {
                // skip to */
                var j = s.index(i, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex
                while j < s.endIndex {
                    if s[j] == "*", s.index(after: j) < s.endIndex, s[s.index(after: j)] == "/" {
                        j = s.index(j, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex
                        break
                    }
                    j = s.index(after: j)
                }
                i = j
            } else {
                out.append(s[i]); i = s.index(after: i)
            }
        }
        return out
    }

    /// Walk a sequence of `prelude { body }` blocks at one nesting level.
    private static func parseRuleList(_ css: String, into sheet: inout SVGStyleSheet, bucket: Bucket, order: inout Int) {
        var i = css.startIndex
        while i < css.endIndex {
            // gather prelude up to the next '{'
            guard let open = css[i...].firstIndex(of: "{") else { break }
            let prelude = css[i..<open].trimmingCharacters(in: .whitespacesAndNewlines)
            // capture the balanced body
            guard let closeIndex = balancedBody(css, openBrace: open) else { break }
            let body = String(css[css.index(after: open)..<closeIndex])
            i = css.index(after: closeIndex)

            if prelude.hasPrefix("@keyframes") {
                let name = prelude.replacingOccurrences(of: "@keyframes", with: "").trimmingCharacters(in: .whitespaces)
                if !name.isEmpty, bucket == .normal {
                    sheet.keyframes[name] = parseKeyframes(name: name, body: body)
                }
            } else if prelude.hasPrefix("@media") {
                let inner = mediaBucket(prelude)
                if inner != .ignored {
                    parseRuleList(body, into: &sheet, bucket: inner, order: &order)
                }
            } else if prelude.hasPrefix("@") {
                // @font-face / @supports / @import — ignore
            } else {
                // a plain style rule
                let decls = parseDecls(body)
                guard !decls.isEmpty else { continue }
                let selectors = prelude.split(separator: ",").compactMap { selector(String($0)) }
                guard !selectors.isEmpty else { continue }
                order += 1
                let rule = SVGRule(selectors: selectors, decls: decls,
                                   specificity: selectors.map(specificity).max() ?? 0, order: order)
                switch bucket {
                case .normal: sheet.rules.append(rule)
                case .reducedMotion: sheet.reducedMotionRules.append(rule)
                case .dark: sheet.darkRules.append(rule)
                case .ignored: break
                }
            }
        }
    }

    /// Index of the `}` that closes the `{` at `openBrace`, honoring nesting.
    private static func balancedBody(_ s: String, openBrace: String.Index) -> String.Index? {
        var depth = 0
        var i = openBrace
        while i < s.endIndex {
            let c = s[i]
            if c == "{" { depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0 { return i }
            }
            i = s.index(after: i)
        }
        return nil
    }

    private static func mediaBucket(_ prelude: String) -> Bucket {
        let p = prelude.lowercased()
        if p.contains("prefers-reduced-motion") && p.contains("reduce") { return .reducedMotion }
        if p.contains("prefers-color-scheme") && p.contains("dark") { return .dark }
        // light / width / orientation queries — not modelled, skip safely
        return .ignored
    }

    private static func parseKeyframes(name: String, body: String) -> SVGKeyframes {
        var frames: [(pct: CGFloat, decls: [String: String])] = []
        var i = body.startIndex
        while i < body.endIndex {
            guard let open = body[i...].firstIndex(of: "{") else { break }
            let sel = body[i..<open].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let close = body[open...].firstIndex(of: "}") else { break }
            let decls = parseDecls(String(body[body.index(after: open)..<close]))
            i = body.index(after: close)
            for token in sel.split(separator: ",") {
                let t = token.trimmingCharacters(in: .whitespaces).lowercased()
                let pct: CGFloat?
                if t == "from" { pct = 0 }
                else if t == "to" { pct = 1 }
                else if t.hasSuffix("%"), let v = Double(t.dropLast()) { pct = CGFloat(v) / 100 }
                else { pct = nil }
                if let pct = pct { frames.append((pct, decls)) }
            }
        }
        frames.sort { $0.pct < $1.pct }
        return SVGKeyframes(name: name, frames: frames)
    }

    private static func parseDecls(_ body: String) -> [String: String] {
        var out: [String: String] = [:]
        for chunk in body.split(separator: ";") {
            guard let colon = chunk.firstIndex(of: ":") else { continue }
            let key = chunk[chunk.startIndex..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let val = chunk[chunk.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty && !val.isEmpty { out[key] = val }
        }
        return out
    }

    /// Reduce a (possibly compound/descendant) selector to its rightmost key.
    /// Enough for the corpus, which keys animation on a single class/tag/id.
    private static func selector(_ raw: String) -> SVGSelector? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let last = s.split(whereSeparator: { $0 == " " || $0 == ">" || $0 == "+" || $0 == "~" }).last.map(String.init) ?? s
        // strip pseudo-classes/elements
        let core = last.split(whereSeparator: { $0 == ":" }).first.map(String.init) ?? last
        if core == "*" || core.isEmpty { return .universal }
        if core.hasPrefix(".") { return .cls(String(core.dropFirst())) }
        if core.hasPrefix("#") { return .id(String(core.dropFirst())) }
        // could be tag.class — prefer the class if present
        if let dot = core.firstIndex(of: ".") {
            return .cls(String(core[core.index(after: dot)...]))
        }
        return .tag(core.lowercased())
    }

    private static func specificity(_ sel: SVGSelector) -> Int {
        switch sel {
        case .id: return 100
        case .cls: return 10
        case .tag: return 1
        case .universal: return 0
        }
    }
}
