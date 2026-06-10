//
//  SVGAnimation.swift
//  EusoTrip — Native SVG renderer · time → animated state.
//
//  Evaluates CSS @keyframes (driven by the `animation:` shorthand) and SMIL
//  (<animate>/<animateTransform>/<set>) at a wall-clock time, producing the
//  extra transform + opacity multiplier + animated geometry/paint overrides
//  to apply to an element. Animated rotate/scale are taken about the element's
//  transform-origin (default = bbox center; transform-box: view-box honored)
//  so wheels, gauges, booms, and pulses move about the right point.
//
//  Wave E (2026-06-10):
//    • beyond transform+opacity — SMIL r/cy/cx/x/y/width/height/
//      stroke-dashoffset and keyframed x/y/r/cx/cy/width/height/
//      stroke-dashoffset/fill now interpolate (the tanker fill-flow,
//      exhaust puffs, hose flow visuals).
//    • the hot path consumes BAKED data only (specs, compiled keyframes,
//      compiled SMIL) — no per-frame string splitting/parsing/formatting.
//

import Foundation
import SwiftUI
import CoreGraphics

struct AnimatedState {
    var extraTransform: CGAffineTransform = .identity
    var opacityMultiplier: CGFloat = 1
    var hidden: Bool = false
    // Animated geometry overrides (absolute values, SVG user units).
    var x: CGFloat? = nil
    var y: CGFloat? = nil
    var cx: CGFloat? = nil
    var cy: CGFloat? = nil
    var r: CGFloat? = nil
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    // Animated paint overrides.
    var dashoffset: CGFloat? = nil
    var fillOverride: SVGRGBA? = nil

    var hasGeometryOverride: Bool {
        x != nil || y != nil || cx != nil || cy != nil || r != nil || width != nil || height != nil
    }
}

enum SVGAnimation {

    // MARK: CSS @keyframes (compiled)

    /// Evaluate the element's baked animation specs into `state`.
    static func cssState(specs: [SVGAnimationSpec],
                         keyframes: [String: SVGKeyframes],
                         time: Double,
                         origin: CGPoint,
                         cssVars: [String: String],
                         into state: inout AnimatedState) {
        for spec in specs {
            guard let kf = keyframes[spec.name], !kf.compiled.isEmpty else { continue }
            let e = progress(spec: spec, time: time)
            applyCompiled(kf.compiled, at: e, origin: origin, cssVars: cssVars, into: &state)
        }
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

    private static func applyCompiled(_ frames: [SVGCompiledFrame], at e: CGFloat,
                                      origin: CGPoint, cssVars: [String: String],
                                      into state: inout AnimatedState) {
        guard let first = frames.first, let last = frames.last else { return }

        let lo: SVGCompiledFrame
        let hi: SVGCompiledFrame
        var t: CGFloat = 0
        if e <= first.pct {
            lo = first; hi = first
        } else if e >= last.pct {
            lo = last; hi = last
        } else {
            var loF = first, hiF = first
            for f in frames {
                if f.pct <= e { loF = f }
                if f.pct >= e { hiF = f; break }
            }
            lo = loF; hi = hiF
            let span = hi.pct - lo.pct
            t = span > 0 ? (e - lo.pct) / span : 0
        }

        // transform
        if let m = lerpedTransform(lo, hi, t, origin: origin, cssVars: cssVars) {
            state.extraTransform = state.extraTransform.concatenating(m)
        }
        // opacity
        if let o0 = lo.opacity, let o1 = hi.opacity {
            state.opacityMultiplier *= (o0 + (o1 - o0) * t)
        } else if let o = lo.opacity ?? hi.opacity {
            state.opacityMultiplier *= o
        }
        // numeric geometry/paint channels
        if let v = lerpOpt(lo.x, hi.x, t) { state.x = v }
        if let v = lerpOpt(lo.y, hi.y, t) { state.y = v }
        if let v = lerpOpt(lo.r, hi.r, t) { state.r = v }
        if let v = lerpOpt(lo.cx, hi.cx, t) { state.cx = v }
        if let v = lerpOpt(lo.cy, hi.cy, t) { state.cy = v }
        if let v = lerpOpt(lo.width, hi.width, t) { state.width = v }
        if let v = lerpOpt(lo.height, hi.height, t) { state.height = v }
        if let v = lerpOpt(lo.dashoffset, hi.dashoffset, t) { state.dashoffset = v }
        // fill (color lerp)
        if let f0 = lo.fill, let f1 = hi.fill {
            state.fillOverride = f0.lerp(to: f1, t)
        } else if let f = lo.fill ?? hi.fill {
            state.fillOverride = f
        }
    }

    private static func lerpOpt(_ a: CGFloat?, _ b: CGFloat?, _ t: CGFloat) -> CGFloat? {
        if let a = a, let b = b { return a + (b - a) * t }
        return a ?? b
    }

    /// Interpolated transform matrix between two compiled frames. Pre-parsed
    /// ops are the fast path; var()-bearing transforms resolve+parse per frame.
    private static func lerpedTransform(_ lo: SVGCompiledFrame, _ hi: SVGCompiledFrame,
                                        _ t: CGFloat, origin: CGPoint,
                                        cssVars: [String: String]) -> CGAffineTransform? {
        let loOps = resolvedOps(lo, cssVars)
        let hiOps = resolvedOps(hi, cssVars)
        switch (loOps, hiOps) {
        case (nil, nil):
            return nil
        case (let a?, nil):
            return matrix(ops: a, origin: origin)
        case (nil, let b?):
            return matrix(ops: b, origin: origin)
        case (let a?, let b?):
            guard a.count == b.count, zip(a, b).allSatisfy({ $0.name == $1.name }) else {
                // op shapes differ — snap to the nearer frame (legacy behavior)
                return matrix(ops: t < 0.5 ? a : b, origin: origin)
            }
            var m = CGAffineTransform.identity
            for (oa, ob) in zip(a, b) {
                let n = max(oa.args.count, ob.args.count)
                let a0 = lerpArg(oa.args, ob.args, 0, t)
                let a1 = lerpArg(oa.args, ob.args, 1, t)
                let a2 = lerpArg(oa.args, ob.args, 2, t)
                m = m.concatenating(opMatrix(oa.name, a0, a1, a2, argCount: n, origin: origin))
            }
            return m
        }
    }

    private static func resolvedOps(_ f: SVGCompiledFrame, _ cssVars: [String: String]) -> [SVGTransformOp]? {
        if let ops = f.ops { return ops }
        if let raw = f.transformRaw {
            let resolved = SVGRenderer.resolveVars(raw, cssVars) ?? raw
            return parseOps(resolved)
        }
        return nil
    }

    private static func lerpArg(_ a: [CGFloat], _ b: [CGFloat], _ k: Int, _ t: CGFloat) -> CGFloat {
        let va = k < a.count ? a[k] : 0
        let vb = k < b.count ? b[k] : 0
        return va + (vb - va) * t
    }

    // MARK: SMIL (compiled)

    static func smilState(element: SVGElement, time: Double, origin: CGPoint,
                          into state: inout AnimatedState) {
        for child in element.bakedSMILChildren {
            guard let c = child.bakedSMIL else { continue }
            switch c.kind {
            case .animateTransform:
                applyAnimateTransform(c, time: time, origin: origin, into: &state)
            case .animate:
                applyAnimate(c, time: time, into: &state)
            case .set:
                applySet(c, time: time, into: &state)
            }
        }
    }

    private static func smilProgress(_ c: SVGSMILCompiled, time: Double) -> (p: CGFloat, active: Bool) {
        guard c.dur > 0 else { return (1, true) }
        let elapsed = time - c.begin
        if elapsed < 0 { return (0, false) }
        let cycles = elapsed / c.dur
        if !c.repeats && cycles >= 1 {
            return (c.freeze ? 1 : 0, c.freeze)
        }
        return (CGFloat(cycles - floor(cycles)), true)
    }

    private static func applyAnimateTransform(_ c: SVGSMILCompiled, time: Double, origin: CGPoint,
                                              into state: inout AnimatedState) {
        let (p, active) = smilProgress(c, time: time)
        guard active else { return }
        let v = sample(c, p: p)
        guard v.count > 0 else { return }
        let t: CGAffineTransform
        switch c.transformType {
        case "rotate":
            let angle = v.a * .pi / 180
            let cx = v.count >= 3 ? v.b : origin.x
            let cy = v.count >= 3 ? v.c : origin.y
            t = CGAffineTransform(translationX: cx, y: cy).rotated(by: angle).translatedBy(x: -cx, y: -cy)
        case "scale":
            let sx = v.a
            let sy = v.count > 1 ? v.b : sx
            t = CGAffineTransform(translationX: origin.x, y: origin.y)
                .scaledBy(x: sx, y: sy)
                .translatedBy(x: -origin.x, y: -origin.y)
        default: // translate
            t = CGAffineTransform(translationX: v.a, y: v.count > 1 ? v.b : 0)
        }
        state.extraTransform = state.extraTransform.concatenating(t)
    }

    private static func applyAnimate(_ c: SVGSMILCompiled, time: Double, into state: inout AnimatedState) {
        let (p, active) = smilProgress(c, time: time)
        guard active else { return }
        let v = sample(c, p: p)
        guard v.count > 0 else { return }
        assign(c.attributeName, v.a, into: &state)
    }

    private static func applySet(_ c: SVGSMILCompiled, time: Double, into state: inout AnimatedState) {
        guard time >= c.begin else { return }
        guard let to = c.frames.last, to.count > 0 else { return }
        assign(c.attributeName, to.a, into: &state)
    }

    /// Route an animated attribute value into the state (the Wave E
    /// geometry/paint extension beyond opacity).
    private static func assign(_ attr: String, _ v: CGFloat, into state: inout AnimatedState) {
        switch attr {
        case "opacity", "fill-opacity": state.opacityMultiplier *= v
        case "r": state.r = v
        case "cy": state.cy = v
        case "cx": state.cx = v
        case "x": state.x = v
        case "y": state.y = v
        case "width": state.width = v
        case "height": state.height = v
        case "stroke-dashoffset": state.dashoffset = v
        default: break
        }
    }

    /// Sample compiled SMIL frames (with optional keyTimes) at progress p.
    private static func sample(_ c: SVGSMILCompiled, p: CGFloat) -> SVGSMILVec {
        let frames = c.frames
        guard frames.count >= 2 else { return frames.first ?? SVGSMILVec() }
        var i0 = 0, i1 = 1, segT = p
        if let kt = c.keyTimes, kt.count == frames.count {
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
        return SVGSMILVec.lerp(frames[i0], frames[i1], segT)
    }

    // MARK: Transform op parsing + matrices (shared with the baker)

    static func parseOps(_ s: String) -> [SVGTransformOp] {
        var ops: [SVGTransformOp] = []
        var idx = s.startIndex
        while idx < s.endIndex {
            guard let open = s[idx...].firstIndex(of: "(") else { break }
            let name = s[idx..<open].trimmingCharacters(in: CharacterSet(charactersIn: " ,\n\t")).lowercased()
            guard let close = s[open...].firstIndex(of: ")") else { break }
            var args = SVGNum.list(String(s[s.index(after: open)..<close]))
            if name == "rotate" && args.isEmpty { args = [0] }
            ops.append(SVGTransformOp(name: name, args: args))
            idx = s.index(after: close)
        }
        return ops
    }

    /// Build a matrix from parsed ops, taking rotate/scale about `origin`.
    static func matrix(ops: [SVGTransformOp], origin: CGPoint) -> CGAffineTransform {
        var m = CGAffineTransform.identity
        for op in ops {
            let n = op.args.count
            let a0 = n > 0 ? op.args[0] : .nan
            let a1 = n > 1 ? op.args[1] : .nan
            let a2 = n > 2 ? op.args[2] : .nan
            m = m.concatenating(opMatrix(op.name, a0, a1, a2, argCount: n, origin: origin))
        }
        return m
    }

    /// Build a matrix from a CSS transform string, taking rotate/scale about
    /// `origin` (used for var()-bearing transforms resolved per frame).
    static func matrix(from s: String, origin: CGPoint) -> CGAffineTransform {
        matrix(ops: parseOps(s), origin: origin)
    }

    private static func opMatrix(_ name: String, _ a0: CGFloat, _ a1: CGFloat, _ a2: CGFloat,
                                 argCount: Int, origin: CGPoint) -> CGAffineTransform {
        func v(_ x: CGFloat, _ fallback: CGFloat) -> CGFloat { x.isNaN ? fallback : x }
        switch name {
        case "translate":
            return CGAffineTransform(translationX: v(a0, 0), y: argCount > 1 ? v(a1, 0) : 0)
        case "translatex": return CGAffineTransform(translationX: v(a0, 0), y: 0)
        case "translatey": return CGAffineTransform(translationX: 0, y: v(a0, 0))
        case "rotate":
            let rad = v(a0, 0) * .pi / 180
            let cx = argCount >= 3 ? v(a1, origin.x) : origin.x
            let cy = argCount >= 3 ? v(a2, origin.y) : origin.y
            return CGAffineTransform(translationX: cx, y: cy).rotated(by: rad).translatedBy(x: -cx, y: -cy)
        case "scale":
            let sx = v(a0, 1)
            let sy = argCount > 1 ? v(a1, sx) : sx
            return CGAffineTransform(translationX: origin.x, y: origin.y)
                .scaledBy(x: sx, y: sy)
                .translatedBy(x: -origin.x, y: -origin.y)
        case "scalex":
            return CGAffineTransform(translationX: origin.x, y: origin.y)
                .scaledBy(x: v(a0, 1), y: 1)
                .translatedBy(x: -origin.x, y: -origin.y)
        case "scaley":
            return CGAffineTransform(translationX: origin.x, y: origin.y)
                .scaledBy(x: 1, y: v(a0, 1))
                .translatedBy(x: -origin.x, y: -origin.y)
        default:
            return .identity
        }
    }

    // MARK: Bake-time helpers (string parsing — never on the render path)

    /// Split a CSS `animation:` shorthand on commas that are NOT inside
    /// parentheses (cubic-bezier(...)).
    static func splitAnimations(_ s: String) -> [String] {
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

    /// Parse a SMIL clock value ("2s", "500ms", "2", "00:02", "-0.9s").
    static func parseClock(_ raw: String?) -> Double? {
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
