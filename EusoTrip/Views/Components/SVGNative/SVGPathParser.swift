//
//  SVGPathParser.swift
//  EusoTrip — Native SVG renderer · path `d` mini-language → SwiftUI Path.
//
//  Full SVG 1.1 path grammar: M/L/H/V/C/S/Q/T/A/Z in absolute + relative form,
//  S/T control-point reflection, and elliptical arcs (A) converted to cubic
//  béziers via the endpoint→center algorithm so they render exactly.
//

import SwiftUI
import CoreGraphics

enum SVGPathParser {

    static func path(from d: String) -> Path {
        var path = Path()
        let tokens = tokenize(d)
        var i = 0
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastCubicControl: CGPoint? = nil
        var lastQuadControl: CGPoint? = nil
        var lastCmd: Character = " "

        func num() -> CGFloat? {
            guard i < tokens.count, case .number(let v) = tokens[i] else { return nil }
            i += 1; return v
        }
        func pt(relative: Bool) -> CGPoint? {
            guard let x = num(), let y = num() else { return nil }
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while i < tokens.count {
            var cmd: Character
            if case .command(let c) = tokens[i] {
                cmd = c; i += 1; lastCmd = c
            } else {
                // implicit repeat of the previous command (M→L, m→l per spec)
                cmd = lastCmd == "M" ? "L" : (lastCmd == "m" ? "l" : lastCmd)
                if cmd == " " { break }
            }
            let rel = cmd.isLowercase
            switch Character(cmd.uppercased()) {
            case "M":
                guard let p = pt(relative: rel) else { i = tokens.count; break }
                path.move(to: p); current = p; start = p
                lastCubicControl = nil; lastQuadControl = nil
            case "L":
                guard let p = pt(relative: rel) else { i = tokens.count; break }
                path.addLine(to: p); current = p
                lastCubicControl = nil; lastQuadControl = nil
            case "H":
                guard let x = num() else { i = tokens.count; break }
                let p = CGPoint(x: rel ? current.x + x : x, y: current.y)
                path.addLine(to: p); current = p
                lastCubicControl = nil; lastQuadControl = nil
            case "V":
                guard let y = num() else { i = tokens.count; break }
                let p = CGPoint(x: current.x, y: rel ? current.y + y : y)
                path.addLine(to: p); current = p
                lastCubicControl = nil; lastQuadControl = nil
            case "C":
                guard let c1 = pt(relative: rel), let c2 = pt(relative: rel), let p = pt(relative: rel) else { i = tokens.count; break }
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p; lastCubicControl = c2; lastQuadControl = nil
            case "S":
                let c1 = lastCubicControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                guard let c2 = pt(relative: rel), let p = pt(relative: rel) else { i = tokens.count; break }
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p; lastCubicControl = c2; lastQuadControl = nil
            case "Q":
                guard let c = pt(relative: rel), let p = pt(relative: rel) else { i = tokens.count; break }
                path.addQuadCurve(to: p, control: c)
                current = p; lastQuadControl = c; lastCubicControl = nil
            case "T":
                let c = lastQuadControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                guard let p = pt(relative: rel) else { i = tokens.count; break }
                path.addQuadCurve(to: p, control: c)
                current = p; lastQuadControl = c; lastCubicControl = nil
            case "A":
                guard let rx = num(), let ry = num(), let rot = num(),
                      let large = num(), let sweep = num(), let p = pt(relative: rel) else { i = tokens.count; break }
                addArc(to: &path, from: current, to: p, rx: rx, ry: ry,
                       xRotDeg: rot, largeArc: large != 0, sweep: sweep != 0)
                current = p; lastCubicControl = nil; lastQuadControl = nil
            case "Z":
                path.closeSubpath(); current = start
                lastCubicControl = nil; lastQuadControl = nil
            default:
                i = tokens.count
            }
        }
        return path
    }

    // MARK: Tokenizer

    private enum Token { case command(Character); case number(CGFloat) }

    private static func tokenize(_ d: String) -> [Token] {
        var tokens: [Token] = []
        var numBuf = ""
        func flush() {
            if !numBuf.isEmpty {
                if let v = Double(numBuf) { tokens.append(.number(CGFloat(v))) }
                numBuf = ""
            }
        }
        let cmds: Set<Character> = ["M","m","L","l","H","h","V","v","C","c","S","s","Q","q","T","t","A","a","Z","z"]
        for ch in d {
            if cmds.contains(ch) {
                flush(); tokens.append(.command(ch))
            } else if ch == "," || ch == " " || ch == "\n" || ch == "\t" || ch == "\r" {
                flush()
            } else if ch == "-" || ch == "+" {
                // sign starts a new number unless right after 'e'/'E'
                if let last = numBuf.last, last == "e" || last == "E" {
                    numBuf.append(ch)
                } else {
                    flush(); numBuf.append(ch)
                }
            } else if ch == "." {
                // a second dot starts a new number ("1.5.5" → 1.5 , .5)
                if numBuf.contains(".") { flush() }
                numBuf.append(ch)
            } else {
                numBuf.append(ch)
            }
        }
        flush()
        return tokens
    }

    // MARK: Elliptical arc → cubic béziers (SVG endpoint→center parameterization)

    private static func addArc(to path: inout Path, from p0: CGPoint, to p1: CGPoint,
                               rx rxIn: CGFloat, ry ryIn: CGFloat, xRotDeg: CGFloat,
                               largeArc: Bool, sweep: Bool) {
        if rxIn == 0 || ryIn == 0 || (p0 == p1) {
            path.addLine(to: p1); return
        }
        var rx = abs(rxIn), ry = abs(ryIn)
        let phi = xRotDeg * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)

        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        // correct out-of-range radii
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let s = sqrt(lambda); rx *= s; ry *= s
        }

        let sign: CGFloat = (largeArc != sweep) ? 1 : -1
        var num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        if num < 0 { num = 0 }
        let co = sign * sqrt(num / max(den, .leastNonzeroMagnitude))
        let cxp = co * (rx * y1p / ry)
        let cyp = co * (-ry * x1p / rx)

        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            var a = acos(min(1, max(-1, dot / max(len, .leastNonzeroMagnitude))))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var dTheta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && dTheta > 0 { dTheta -= 2 * .pi }
        if sweep && dTheta < 0 { dTheta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(dTheta) / (.pi / 2))))
        let delta = dTheta / CGFloat(segments)
        let t = 4.0 / 3.0 * tan(delta / 4)
        var angleStart = theta1

        for _ in 0..<segments {
            let cos1 = cos(angleStart), sin1 = sin(angleStart)
            let a2 = angleStart + delta
            let cos2 = cos(a2), sin2 = sin(a2)

            func map(_ ex: CGFloat, _ ey: CGFloat) -> CGPoint {
                CGPoint(x: cosPhi * rx * ex - sinPhi * ry * ey + cx,
                        y: sinPhi * rx * ex + cosPhi * ry * ey + cy)
            }
            let end = map(cos2, sin2)
            let c1 = map(cos1 - t * sin1, sin1 + t * cos1)
            let c2 = map(cos2 + t * sin2, sin2 - t * cos2)
            path.addCurve(to: end, control1: c1, control2: c2)
            angleStart = a2
        }
    }
}
