//
//  SVGAnimation.swift
//  EusoTrip — Native SVG renderer · time → animated transform/opacity.
//
//  Evaluates CSS @keyframes (driven by the `animation:` shorthand) and SMIL
//  (<animate>/<animateTransform>) at a wall-clock time, producing the extra
//  transform + opacity multiplier + visibility to apply to an element. Animated
//  rotate/scale are taken about the element's transform-origin (default = bbox
//  center) so wheels, gauges, and pulses spin/scale about the right point.
//

import Foundation
import CoreGraphics

struct AnimatedState {
    var extraTransform: CGAffineTransform = .identity
    var opacityMultiplier: CGFloat = 1
    var hidden: Bool = false
}

/// A single transform operation kept un-collapsed so it can be interpolated
/// (rotate(0)→rotate(360) interpolates the angle, not the matrix).
private struct TOp {
    var name: String
    var args: [CGFloat]
}

enum SVGAnimation {

    // MARK: CSS @keyframes

    static func cssState(decls: [String: String],
                         keyframes: [String: SVGKeyframes],
                         time: Double,
                         origin: CGPoint) -> AnimatedState {
        guard let anim = decls["animation"], anim.lowercased() != "none" else { return AnimatedState() }
        var state = AnimatedState()
        for spec in splitAnimations(anim).compactMap({ SVGAnimationSpec.parse($0) }) {
            guard let kf = keyframes[spec.name], !kf.frames.isEmpty else { continue }
            let e = progress(spec: spec, time: time)
            let frame = interpolateFrame(kf, at: e)
            if let t = frame.transform {
                state.extraTransform = state.extraTransform.concatenating(matrix(from: t, origin: origin))
            }
            if let o = frame.opacity {
                state.opacityMultiplier *= o
            }
        }
        return state
    }

    /// Eased progress 0…1 for the current iteration, honoring delay /
    /// iteration-count / direction.
    private static func progress(spec: SVGAnimationSpec, time: Double) -> CGFloat {
        guard spec.duration > 0 else { return 1 }
        let elapsed = time - spec.delay
        if elapsed <= 0 { return spec.easing.apply(directionStart(spec)) }
        let cycles = elapsed / spec.duration
        var local: CGFloat
        var iteration = Int(floor(cycles))
        if spec.iterationCount != .infinity && Double(iteration) >= spec.iterationCount {
            // settle on the final frame of the last iteration
            iteration = max(0, Int(spec.iterationCount.rounded(.up)) - 1)
            local = 1
        } else {
            local = CGFloat(cycles - floor(cycles))
        }
        let directed: CGFloat
        switch spec.direction {
        case .normal: directed = local
        case .reverse: directed = 1 - local
        case .alternate: directed = (iteration % 2 == 0) ? local : 1 - local
        case .alternateReverse: directed = (iteration % 2 == 0) ? 1 - local : local
        }
        return spec.easing.apply(directed)
    }

    private static func directionStart(_ spec: SVGAnimationSpec) -> CGFloat {
        switch spec.direction {
        case .normal, .alternate: return 0
        case .reverse, .alternateReverse: return 1
        }
    }

    private struct FrameValue { var transform: String?; var opacity: CGFloat? }

    private static func interpolateFrame(_ kf: SVGKeyframes, at e: CGFloat) -> FrameValue {
        let frames = kf.frames
        guard let first = frames.first else { return FrameValue(transform: nil, opacity: nil) }
        if e <= first.pct { return FrameValue(transform: first.decls["transform"], opacity: SVGNum.parse(first.decls["opacity"])) }
        guard let last = frames.last else { return FrameValue() }
        if e >= last.pct { return FrameValue(transform: last.decls["transform"], opacity: SVGNum.parse(last.decls["opacity"])) }

        var lo = frames[0], hi = frames[0]
        for f in frames {
            if f.pct <= e { lo = f }
            if f.pct >= e { hi = f; break }
        }
        let span = hi.pct - lo.pct
        let t = span > 0 ? (e - lo.pct) / span : 0

        // opacity
        var opacity: CGFloat? = nil
        if let o0 = SVGNum.parse(lo.decls["opacity"]), let o1 = SVGNum.parse(hi.decls["opacity"]) {
            opacity = o0 + (o1 - o0) * t
        } else {
            opacity = SVGNum.parse(lo.decls["opacity"]) ?? SVGNum.parse(hi.decls["opacity"])
        }

        // transform: interpolate matching op lists
        var transformStr: String? = nil
        if let s0 = lo.decls["transform"], let s1 = hi.decls["transform"] {
            transformStr = interpolateTransformStrings(s0, s1, t)
        } else {
            transformStr = lo.decls["transform"] ?? hi.decls["transform"]
        }
        return FrameValue(transform: transformStr, opacity: opacity)
    }

    // MARK: SMIL

    static func smilState(element: SVGElement, time: Double, origin: CGPoint) -> AnimatedState {
        var state = AnimatedState()
        for child in element.children {
            switch child.tag {
            case "animateTransform":
                applyAnimateTransform(child, time: time, origin: origin, into: &state)
            case "animate":
                applyAnimate(child, time: time, into: &state)
            case "set":
                applySet(child, time: time, into: &state)
            default: break
            }
        }
        return state
    }

    private static func smilProgress(_ el: SVGElement, time: Double) -> (p: CGFloat, active: Bool) {
        let dur = parseClock(el.attrs["dur"]) ?? 0
        let begin = parseClock(el.attrs["begin"]) ?? 0
        let repeats = (el.attrs["repeatCount"]?.lowercased() == "indefinite")
        guard dur > 0 else { return (1, true) }
        let elapsed = time - begin
        if elapsed < 0 { return (0, false) }
        let cycles = elapsed / dur
        if !repeats && cycles >= 1 {
            let freeze = (el.attrs["fill"] ?? "remove") == "freeze"
            return (freeze ? 1 : 0, freeze)
        }
        return (CGFloat(cycles - floor(cycles)), true)
    }

    private static func applyAnimateTransform(_ el: SVGElement, time: Double, origin: CGPoint, into state: inout AnimatedState) {
        let (p, active) = smilProgress(el, time: time)
        guard active else { return }
        let type = (el.attrs["type"] ?? "translate").lowercased()
        let values = sampleValues(el, p: p)   // the interpolated numeric args
        guard !values.isEmpty else { return }
        let t: CGAffineTransform
        switch type {
        case "rotate":
            let angle = (values.first ?? 0) * .pi / 180
            let cx = values.count >= 3 ? values[1] : origin.x
            let cy = values.count >= 3 ? values[2] : origin.y
            t = CGAffineTransform(translationX: cx, y: cy).rotated(by: angle).translatedBy(x: -cx, y: -cy)
        case "scale":
            let sx = values.first ?? 1
            let sy = values.count > 1 ? values[1] : sx
            t = CGAffineTransform(translationX: origin.x, y: origin.y)
                .scaledBy(x: sx, y: sy)
                .translatedBy(x: -origin.x, y: -origin.y)
        default: // translate
            t = CGAffineTransform(translationX: values.first ?? 0, y: values.count > 1 ? values[1] : 0)
        }
        state.extraTransform = state.extraTransform.concatenating(t)
    }

    private static func applyAnimate(_ el: SVGElement, time: Double, into state: inout AnimatedState) {
        let (p, active) = smilProgress(el, time: time)
        guard active else { return }
        let attr = (el.attrs["attributeName"] ?? "").lowercased()
        let vals = sampleValues(el, p: p)
        guard let v = vals.first else { return }
        if attr == "opacity" || attr == "fill-opacity" {
            state.opacityMultiplier *= v
        }
    }

    private static func applySet(_ el: SVGElement, time: Double, into state: inout AnimatedState) {
        let begin = parseClock(el.attrs["begin"]) ?? 0
        guard time >= begin else { return }
        if (el.attrs["attributeName"]?.lowercased() == "opacity"), let v = SVGNum.parse(el.attrs["to"]) {
            state.opacityMultiplier *= v
        }
    }

    /// Sample SMIL `values;...` (with optional keyTimes) or from/to at progress p.
    private static func sampleValues(_ el: SVGElement, p: CGFloat) -> [CGFloat] {
        if let valuesStr = el.attrs["values"] {
            let frames = valuesStr.split(separator: ";").map { SVGNum.list(String($0)) }
            guard frames.count >= 2 else { return frames.first ?? [] }
            let keyTimes = el.attrs["keyTimes"].map { SVGNum.list($0) }
            // locate segment
            var i0 = 0, i1 = 1, segT = p
            if let kt = keyTimes, kt.count == frames.count {
                for k in 0..<(kt.count - 1) where p >= kt[k] && p <= kt[k + 1] {
                    i0 = k; i1 = k + 1
                    let span = kt[k + 1] - kt[k]
                    segT = span > 0 ? (p - kt[k]) / span : 0
                    break
                }
            } else {
                let scaled = p * CGFloat(frames.count - 1)
                i0 = min(frames.count - 1, Int(floor(scaled)))
                i1 = min(frames.count - 1, i0 + 1)
                segT = scaled - floor(scaled)
            }
            return lerpLists(frames[i0], frames[i1], segT)
        }
        if let from = el.attrs["from"], let to = el.attrs["to"] {
            return lerpLists(SVGNum.list(from), SVGNum.list(to), p)
        }
        if let to = el.attrs["to"] { return SVGNum.list(to) }
        return []
    }

    // MARK: Transform string interpolation

    private static func interpolateTransformStrings(_ a: String, _ b: String, _ t: CGFloat) -> String {
        let opsA = parseOps(a), opsB = parseOps(b)
        guard opsA.count == opsB.count else { return t < 0.5 ? a : b }
        var pieces: [String] = []
        for (oa, ob) in zip(opsA, opsB) where oa.name == ob.name {
            let n = max(oa.args.count, ob.args.count)
            var args: [CGFloat] = []
            for k in 0..<n {
                let va = k < oa.args.count ? oa.args[k] : 0
                let vb = k < ob.args.count ? ob.args[k] : 0
                args.append(va + (vb - va) * t)
            }
            pieces.append("\(oa.name)(\(args.map { String(format: "%.4f", $0) }.joined(separator: " ")))")
        }
        return pieces.joined(separator: " ")
    }

    private static func parseOps(_ s: String) -> [TOp] {
        var ops: [TOp] = []
        var idx = s.startIndex
        while idx < s.endIndex {
            guard let open = s[idx...].firstIndex(of: "(") else { break }
            let name = s[idx..<open].trimmingCharacters(in: CharacterSet(charactersIn: " ,\n\t")).lowercased()
            guard let close = s[open...].firstIndex(of: ")") else { break }
            var args = SVGNum.list(String(s[s.index(after: open)..<close]))
            // normalize deg suffixes already stripped by SVGNum.list
            if name == "rotate" && args.isEmpty { args = [0] }
            ops.append(TOp(name: name, args: args))
            idx = s.index(after: close)
        }
        return ops
    }

    /// Build a matrix from a transform string, taking rotate/scale about `origin`.
    private static func matrix(from s: String, origin: CGPoint) -> CGAffineTransform {
        var m = CGAffineTransform.identity
        for op in parseOps(s) {
            switch op.name {
            case "translate":
                m = m.concatenating(CGAffineTransform(translationX: op.args.first ?? 0, y: op.args.count > 1 ? op.args[1] : 0))
            case "translatex": m = m.concatenating(CGAffineTransform(translationX: op.args.first ?? 0, y: 0))
            case "translatey": m = m.concatenating(CGAffineTransform(translationX: 0, y: op.args.first ?? 0))
            case "rotate":
                let rad = (op.args.first ?? 0) * .pi / 180
                let cx = op.args.count >= 3 ? op.args[1] : origin.x
                let cy = op.args.count >= 3 ? op.args[2] : origin.y
                m = m.concatenating(CGAffineTransform(translationX: cx, y: cy).rotated(by: rad).translatedBy(x: -cx, y: -cy))
            case "scale":
                let sx = op.args.first ?? 1
                let sy = op.args.count > 1 ? op.args[1] : sx
                m = m.concatenating(CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: sx, y: sy).translatedBy(x: -origin.x, y: -origin.y))
            default: break
            }
        }
        return m
    }

    // MARK: helpers

    private static func splitAnimations(_ s: String) -> [String] {
        // split on commas that are NOT inside parentheses (cubic-bezier(...))
        var out: [String] = []
        var depth = 0, cur = ""
        for c in s {
            if c == "(" { depth += 1; cur.append(c) }
            else if c == ")" { depth -= 1; cur.append(c) }
            else if c == "," && depth == 0 { out.append(cur); cur = "" }
            else { cur.append(c) }
        }
        if !cur.trimmingCharacters(in: .whitespaces).isEmpty { out.append(cur) }
        return out
    }

    private static func lerpLists(_ a: [CGFloat], _ b: [CGFloat], _ t: CGFloat) -> [CGFloat] {
        let n = max(a.count, b.count)
        return (0..<n).map { k in
            let va = k < a.count ? a[k] : 0
            let vb = k < b.count ? b[k] : 0
            return va + (vb - va) * t
        }
    }

    /// Parse a SMIL clock value ("2s", "500ms", "2", "00:02").
    private static func parseClock(_ raw: String?) -> Double? {
        guard let s = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !s.isEmpty else { return nil }
        if s.hasSuffix("ms") { return Double(s.dropLast(2)).map { $0 / 1000 } }
        if s.hasSuffix("s") { return Double(s.dropLast()) }
        if s.contains(":") {
            let parts = s.split(separator: ":").compactMap { Double($0) }
            if parts.count == 2 { return parts[0] * 60 + parts[1] }
            if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
        }
        return Double(s)
    }
}
