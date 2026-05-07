//
//  EquipmentAnimation.swift
//  EusoTrip — Equipment-aware animation primitive for the post-load
//  wizard (and any other surface that needs to render a live equipment
//  silhouette with product-type-aware motion).
//
//  Doctrine: feedback_lifecycle_parity_animations + feedback_animation_doctrine.
//  Tanker silhouette never paints on a dry-van load. Hazmat is a
//  variant, not the default. Every product type gets its own
//  animation lens. Motion stays under §B.4 budget — `.easeInOut`
//  durations <= 0.6s, continuous loops stay subtle (opacity / fill
//  / offset only, no view-tree mutation per frame).
//
//  Built reactive: every input is a value type, the View body re-
//  derives layers from those inputs, and TimelineView drives the
//  ambient loop at .animation(minimumInterval: 1.0/30.0). Reduced
//  motion respect via @Environment(\.accessibilityReduceMotion).
//
//  Usage from the post-load wizard:
//
//      EquipmentAnimation(
//          equipment: equipmentType,
//          cargo: cargoType,
//          weightUnit: weightUnit,
//          tankerHose: tankerHoseSpec,
//          isHazmat: cargoType == .hazmat || isHazmatTanker,
//          ergMatched: ergMatch?.found == true,
//          reeferLowText: reeferTempLowText,
//          reeferHighText: reeferTempHighText,
//          continuousMode: continuousMode,
//          flatbedStraps: flatbedStraps,
//          flatbedTarps: flatbedTarps,
//          flatbedChains: flatbedChains
//      )
//      .frame(height: 180)
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Public entry point

/// One animation component, every equipment type. Internally branches
/// on `equipment` and renders the matching silhouette + ambient loop.
/// All inputs are pure value types so the View re-derives whenever
/// the user changes a field — no manual `withAnimation` from the
/// caller, motion handled inside.
struct EquipmentAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette

    let equipment: EquipmentKind
    let cargo: CargoKind
    let weightUnit: String                     // unit raw (lbs / bbl / gal / plt / TEU / mt …)

    // Optional subform inputs — drive layer detail.
    var tankerHose: String      = ""           // "2_camlock" / "3_camlock" / "4_camlock" / "dry_disconnect"
    var isHazmat: Bool          = false
    var ergMatched: Bool        = false        // true → ERG row chip shown, intensify hazard pulse
    var reeferLowText: String   = ""
    var reeferHighText: String  = ""
    var preCoolRequired: Bool   = false
    var continuousMode: Bool    = true
    var flatbedStraps: Bool     = false
    var flatbedTarps: Bool      = false
    var flatbedChains: Bool     = false
    var flatbedEdgeProtectors: Bool = false
    var oversizePermits: Bool   = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/30.0, paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSince1970
            ZStack {
                background(t: t)
                stageContent(t: t)
                topRightBadgeStack
                hazmatPulse(t: t)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
    }

    // MARK: - Background — vertical-aware

    @ViewBuilder
    private func background(t: TimeInterval) -> some View {
        switch equipment.vertical {
        case .truck:
            // Subtle road-perspective gradient with horizon line;
            // gentle scan-line drift for ambient motion.
            ZStack {
                LinearGradient(
                    colors: [palette.bgCard, palette.bgCardSoft],
                    startPoint: .top, endPoint: .bottom
                )
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Brand.blue.opacity(0.12), .clear],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .opacity(0.5 + 0.5 * sin(t * 0.5))
                    .blendMode(.plusLighter)
                roadLines(t: t)
            }
        case .rail:
            ZStack {
                LinearGradient(
                    colors: [Brand.rail.opacity(0.20), palette.bgCardSoft],
                    startPoint: .top, endPoint: .bottom
                )
                railTracks(t: t)
            }
        case .vessel:
            ZStack {
                LinearGradient(
                    colors: [Brand.vessel.opacity(0.25), palette.bgCard],
                    startPoint: .top, endPoint: .bottom
                )
                waterWaves(t: t)
            }
        }
    }

    /// Animated dashed road centerline that scrolls left → giving the
    /// truck a feeling of motion without actually moving the silhouette.
    private func roadLines(t: TimeInterval) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let y = geo.size.height * 0.72
            let dashWidth: CGFloat = 16
            let dashGap: CGFloat = 14
            let period = dashWidth + dashGap
            let offset = CGFloat(t * 90).truncatingRemainder(dividingBy: period)
            Path { p in
                var x: CGFloat = -period - offset
                while x < w + period {
                    p.addRoundedRect(in: CGRect(x: x, y: y, width: dashWidth, height: 3),
                                     cornerSize: .init(width: 1.5, height: 1.5))
                    x += period
                }
            }
            .fill(LinearGradient.diagonal.opacity(0.55))
        }
    }

    private func railTracks(t: TimeInterval) -> some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            let trackY1 = h * 0.78
            let trackY2 = h * 0.86
            let tieSpacing: CGFloat = 22
            let offset = CGFloat(t * 60).truncatingRemainder(dividingBy: tieSpacing)
            ZStack {
                // rails
                Path { p in
                    p.move(to: .init(x: 0, y: trackY1)); p.addLine(to: .init(x: w, y: trackY1))
                    p.move(to: .init(x: 0, y: trackY2)); p.addLine(to: .init(x: w, y: trackY2))
                }
                .stroke(palette.textTertiary.opacity(0.7), lineWidth: 2)
                // ties (animated)
                Path { p in
                    var x: CGFloat = -tieSpacing - offset
                    while x < w + tieSpacing {
                        p.addRoundedRect(
                            in: CGRect(x: x, y: trackY1 - 3, width: 14, height: trackY2 - trackY1 + 6),
                            cornerSize: .init(width: 1.5, height: 1.5)
                        )
                        x += tieSpacing
                    }
                }
                .fill(palette.textTertiary.opacity(0.45))
            }
        }
    }

    private func waterWaves(t: TimeInterval) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let waveBase = h * 0.78
            Path { p in
                p.move(to: .init(x: 0, y: waveBase))
                let steps = 60
                for i in 0...steps {
                    let x = w * CGFloat(i) / CGFloat(steps)
                    let phase = Double(i) / Double(steps) * .pi * 4 + t * 1.6
                    let y = waveBase + CGFloat(sin(phase)) * 4
                    p.addLine(to: .init(x: x, y: y))
                }
                p.addLine(to: .init(x: w, y: h))
                p.addLine(to: .init(x: 0, y: h))
                p.closeSubpath()
            }
            .fill(LinearGradient(
                colors: [Brand.vessel.opacity(0.55), Brand.blue.opacity(0.35)],
                startPoint: .top, endPoint: .bottom
            ))
            .blendMode(.plusLighter)
        }
    }

    // MARK: - Stage content (dispatch on equipment)

    @ViewBuilder
    private func stageContent(t: TimeInterval) -> some View {
        switch equipment {
        case .tankerHazmat, .tankerPetro, .tankerLiquid, .tankerGas:
            tankerStage(t: t)
        case .reefer:
            reeferStage(t: t)
        case .flatbed, .stepDeck, .conestoga:
            flatbedStage(t: t)
        case .dryVan:
            dryVanStage(t: t)
        case .container:
            containerStage(t: t)
        case .powerOnly:
            powerOnlyStage(t: t)
        case .oversized:
            oversizedStage(t: t)
        case .railTOFC, .railCOFC, .railIntermodal:
            railStage(t: t)
        case .vesselContainer, .vesselBulk, .vesselTanker:
            vesselStage(t: t)
        }
    }

    // MARK: TANKER

    /// Tanker silhouette + animated liquid fill + hose with flowing
    /// droplets. Color tint adapts to the cargo (amber for petroleum,
    /// blue for liquid/water, cyan for gas, magenta-tinted for hazmat).
    private func tankerStage(t: TimeInterval) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let bodyY = h * 0.40
            let bodyH = h * 0.36
            let bodyW = w * 0.66
            let bodyX = w * 0.20

            // Liquid fill animates via a sine-modulated meniscus —
            // the tank breathes between 40% and 78% full.
            let baseFill = 0.40 + 0.38 * (sin(t * 0.4) * 0.5 + 0.5)
            let fillTop = bodyY + bodyH * (1.0 - baseFill)
            let liquidColor = tankerLiquidColor

            ZStack {
                // Shadow
                Ellipse()
                    .fill(Color.black.opacity(0.22))
                    .frame(width: bodyW + 24, height: 8)
                    .position(x: bodyX + bodyW / 2, y: bodyY + bodyH + 18)
                    .blur(radius: 6)

                // Tank cylinder
                RoundedRectangle(cornerRadius: bodyH / 2, style: .continuous)
                    .fill(LinearGradient(
                        colors: [palette.bgCard, palette.bgCardSoft],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: bodyW, height: bodyH)
                    .position(x: bodyX + bodyW / 2, y: bodyY + bodyH / 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: bodyH / 2, style: .continuous)
                            .strokeBorder(palette.borderFaint, lineWidth: 1.5)
                            .frame(width: bodyW, height: bodyH)
                            .position(x: bodyX + bodyW / 2, y: bodyY + bodyH / 2)
                    )

                // Liquid fill — clipped to tank shape
                RoundedRectangle(cornerRadius: bodyH / 2, style: .continuous)
                    .fill(LinearGradient(
                        colors: [liquidColor.opacity(0.85), liquidColor.opacity(0.55)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: bodyW, height: bodyH)
                    .position(x: bodyX + bodyW / 2, y: bodyY + bodyH / 2)
                    .mask(
                        Rectangle()
                            .frame(width: bodyW, height: bodyH * baseFill)
                            .position(x: bodyX + bodyW / 2,
                                      y: fillTop + (bodyH * baseFill) / 2)
                    )

                // Meniscus highlight
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: bodyW * 0.85, height: 1.5)
                    .position(x: bodyX + bodyW / 2, y: fillTop + 1)

                // Hazmat placard — only on hazmat / petro / chemicals
                if isHazmat {
                    hazmatDiamond(at: CGPoint(x: bodyX + bodyW * 0.18, y: bodyY + bodyH * 0.5))
                }

                // Tanker chassis (wheels)
                ForEach([0.18, 0.36, 0.62, 0.80], id: \.self) { fr in
                    Circle()
                        .fill(palette.textPrimary.opacity(0.85))
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle().fill(LinearGradient.diagonal).frame(width: 5, height: 5)
                        )
                        .position(x: bodyX + bodyW * fr, y: bodyY + bodyH + 12)
                }

                // Cab — rounded square ahead of tank
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient.diagonal)
                    .frame(width: 44, height: bodyH * 0.7)
                    .position(x: bodyX - 22, y: bodyY + bodyH * 0.65)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 16, height: bodyH * 0.28)
                            .position(x: bodyX - 14, y: bodyY + bodyH * 0.45)
                    )

                // Hose + flowing droplets — origin is the entry valve
                // on top of the tank, dest is off-screen-right (loading
                // rack). Drops travel along the hose path.
                hoseAndFlow(
                    start: CGPoint(x: bodyX + bodyW * 0.78, y: bodyY),
                    rackTop: CGPoint(x: w - 16, y: bodyY - 14),
                    t: t
                )

                // Hose-spec chip floats above the entry valve
                if !tankerHose.isEmpty {
                    Text(hoseSpecLabel)
                        .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(LinearGradient.diagonal))
                        .position(x: bodyX + bodyW * 0.78, y: bodyY - 14)
                }
            }
        }
    }

    private func hazmatDiamond(at center: CGPoint) -> some View {
        ZStack {
            Rectangle()
                .fill(Brand.hazmat.opacity(0.18))
                .frame(width: 26, height: 26)
                .rotationEffect(.degrees(45))
            Rectangle()
                .stroke(Brand.hazmat, lineWidth: 1.8)
                .frame(width: 26, height: 26)
                .rotationEffect(.degrees(45))
            Text("3")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Color(hex: 0xB27300))
                .offset(y: 4)
        }
        .position(center)
    }

    private func hoseAndFlow(start: CGPoint, rackTop: CGPoint, t: TimeInterval) -> some View {
        GeometryReader { _ in
            // Bezier connecting start (tank top) to rackTop with a
            // gentle arc.
            let mid = CGPoint(x: (start.x + rackTop.x) / 2, y: start.y - 28)
            ZStack {
                Path { p in
                    p.move(to: start)
                    p.addQuadCurve(to: rackTop, control: mid)
                }
                .stroke(palette.textPrimary.opacity(0.7), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                Path { p in
                    p.move(to: start)
                    p.addQuadCurve(to: rackTop, control: mid)
                }
                .stroke(LinearGradient.diagonal.opacity(0.6),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

                // Animated droplets — 3 in flight, staggered phase
                ForEach(0..<3, id: \.self) { i in
                    let phase = (t * 0.7 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1.0)
                    let pt = pointAlongQuad(start: start, control: mid, end: rackTop, t: CGFloat(phase))
                    Circle()
                        .fill(tankerLiquidColor)
                        .frame(width: 5, height: 5)
                        .position(pt)
                        .opacity(1 - phase * 0.6)
                }
            }
        }
    }

    private func pointAlongQuad(start: CGPoint, control: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
        let u = 1 - t
        let x = u * u * start.x + 2 * u * t * control.x + t * t * end.x
        let y = u * u * start.y + 2 * u * t * control.y + t * t * end.y
        return CGPoint(x: x, y: y)
    }

    private var tankerLiquidColor: Color {
        switch equipment {
        case .tankerPetro:   return Color(hex: 0xE0A95B)              // amber
        case .tankerGas:     return Color(hex: 0x6CC0FF)              // cyan
        case .tankerLiquid:  return Brand.info                         // blue
        case .tankerHazmat:
            return isHazmat ? Color(hex: 0xFFA726) : Brand.info        // hazmat orange
        case .vesselTanker:  return Color(hex: 0xE0A95B)
        default:             return Brand.blue
        }
    }

    private var hoseSpecLabel: String {
        switch tankerHose {
        case "2_camlock":     return "2\""
        case "3_camlock":     return "3\""
        case "4_camlock":     return "4\""
        case "dry_disconnect":return "DRY"
        default:              return ""
        }
    }

    // MARK: REEFER

    /// Reefer trailer with snowflakes drifting + temp-gauge needle
    /// oscillating between low and high. Compressor unit on top
    /// pulses when continuous mode is on.
    private func reeferStage(t: TimeInterval) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let bodyY = h * 0.30
            let bodyH = h * 0.46
            let bodyW = w * 0.62
            let bodyX = w * 0.22

            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(0.22))
                    .frame(width: bodyW + 24, height: 8)
                    .position(x: bodyX + bodyW / 2, y: bodyY + bodyH + 18)
                    .blur(radius: 6)

                // Trailer box
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(
                        colors: [palette.bgCard, palette.bgCardSoft],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: bodyW, height: bodyH)
                    .position(x: bodyX + bodyW / 2, y: bodyY + bodyH / 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Brand.info.opacity(0.6), lineWidth: 1.5)
                            .frame(width: bodyW, height: bodyH)
                            .position(x: bodyX + bodyW / 2, y: bodyY + bodyH / 2)
                    )

                // Cold glow
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(
                        colors: [Brand.info.opacity(0.18 + 0.10 * sin(t * 1.4)),
                                 Brand.info.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: bodyW - 4, height: bodyH - 4)
                    .position(x: bodyX + bodyW / 2, y: bodyY + bodyH / 2)
                    .blendMode(.plusLighter)

                // Snowflakes
                ForEach(0..<8, id: \.self) { i in
                    let phase = (t * 0.5 + Double(i) * 0.13).truncatingRemainder(dividingBy: 1.0)
                    let xJitter = sin(t * 0.8 + Double(i)) * 8
                    let xPos = bodyX + bodyW * (0.1 + 0.8 * Double(i) / 8) + CGFloat(xJitter)
                    let yPos = bodyY + 6 + CGFloat(phase) * (bodyH - 12)
                    Image(systemName: "snowflake")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Brand.info.opacity(0.85))
                        .position(x: xPos, y: yPos)
                        .opacity(0.7 - phase * 0.4)
                }

                // Reefer compressor unit on top
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient.diagonal)
                    .frame(width: bodyW * 0.5, height: 14)
                    .position(x: bodyX + bodyW * 0.5, y: bodyY - 7)
                    .overlay(
                        Circle()
                            .fill(continuousMode
                                  ? Brand.success.opacity(0.6 + 0.4 * sin(t * 3.0))
                                  : Brand.warning)
                            .frame(width: 5, height: 5)
                            .position(x: bodyX + bodyW * 0.5 + bodyW * 0.18, y: bodyY - 7)
                    )

                // Temp gauge — needle oscillates between low and high
                let lo = parseDouble(reeferLowText) ?? 33
                let hi = parseDouble(reeferHighText) ?? 40
                let span = max(hi - lo, 1)
                let needleT = (sin(t * 0.6) + 1) / 2      // 0..1
                let needleAngle = -45 + Double(needleT) * 90    // -45° .. +45°
                tempGauge(at: CGPoint(x: bodyX + bodyW * 0.85, y: bodyY + bodyH * 0.25),
                          needleAngle: needleAngle,
                          loLabel: "\(Int(lo))°",
                          hiLabel: "\(Int(hi))°",
                          spanLabel: "\(Int(span))°F")

                // Pre-cool indicator
                if preCoolRequired {
                    HStack(spacing: 4) {
                        Image(systemName: "thermometer.snowflake")
                            .font(.system(size: 8, weight: .heavy))
                        Text("PRE-COOL")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Brand.info))
                    .position(x: bodyX + bodyW * 0.18, y: bodyY + bodyH * 0.18)
                }

                // Wheels
                ForEach([0.18, 0.32, 0.66, 0.82], id: \.self) { fr in
                    Circle()
                        .fill(palette.textPrimary.opacity(0.85))
                        .frame(width: 12, height: 12)
                        .position(x: bodyX + bodyW * fr, y: bodyY + bodyH + 12)
                }

                // Cab
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient.diagonal)
                    .frame(width: 44, height: bodyH * 0.55)
                    .position(x: bodyX - 22, y: bodyY + bodyH * 0.72)
            }
        }
    }

    private func tempGauge(at center: CGPoint, needleAngle: Double, loLabel: String, hiLabel: String, spanLabel: String) -> some View {
        ZStack {
            Circle()
                .fill(palette.bgCard)
                .frame(width: 40, height: 40)
                .overlay(Circle().strokeBorder(Brand.info.opacity(0.6), lineWidth: 1))
            // Needle
            Capsule()
                .fill(LinearGradient.diagonal)
                .frame(width: 2, height: 14)
                .offset(y: -7)
                .rotationEffect(.degrees(needleAngle))
            // Center pin
            Circle().fill(LinearGradient.diagonal).frame(width: 4, height: 4)
            Text(spanLabel)
                .font(.system(size: 7, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textPrimary)
                .offset(y: 12)
        }
        .position(center)
    }

    // MARK: FLATBED / STEP-DECK / CONESTOGA

    /// Flatbed silhouette with cargo crates + animated straps + tarp
    /// slide-over when toggled.
    private func flatbedStage(t: TimeInterval) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let bedY = h * 0.62
            let bedW = w * 0.66
            let bedX = w * 0.20

            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(0.22))
                    .frame(width: bedW + 24, height: 8)
                    .position(x: bedX + bedW / 2, y: bedY + 22)
                    .blur(radius: 6)

                // Bed plank
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(
                        colors: [palette.bgCard, palette.bgCardSoft],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: bedW, height: 8)
                    .position(x: bedX + bedW / 2, y: bedY + 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(palette.borderFaint, lineWidth: 1)
                            .frame(width: bedW, height: 8)
                            .position(x: bedX + bedW / 2, y: bedY + 4)
                    )

                // Cargo crates (3 stacked)
                ForEach(0..<3, id: \.self) { i in
                    let cw: CGFloat = bedW / 4
                    let ch: CGFloat = 26
                    let cx = bedX + bedW * 0.20 + CGFloat(i) * (cw + 8)
                    let cy = bedY - ch / 2
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(
                            colors: [Brand.warning.opacity(0.85), Brand.warning.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .frame(width: cw, height: ch)
                        .position(x: cx + cw / 2, y: cy)
                        .overlay(
                            // Strap line — slides in if straps toggled.
                            Group {
                                if flatbedStraps {
                                    Rectangle()
                                        .fill(palette.textPrimary)
                                        .frame(width: cw + 8, height: 1.5)
                                        .position(x: cx + cw / 2, y: cy)
                                        .opacity(0.6 + 0.4 * sin(t * 1.6 + Double(i)))
                                }
                            }
                        )
                        .overlay(
                            // Edge-protector glow at corners
                            Group {
                                if flatbedEdgeProtectors {
                                    Circle().fill(LinearGradient.diagonal)
                                        .frame(width: 4, height: 4)
                                        .position(x: cx + 2, y: cy - ch / 2 + 2)
                                    Circle().fill(LinearGradient.diagonal)
                                        .frame(width: 4, height: 4)
                                        .position(x: cx + cw - 2, y: cy - ch / 2 + 2)
                                }
                            }
                        )
                }

                // Tarp — slides over the cargo when toggled
                if flatbedTarps {
                    let tarpProgress = (sin(t * 0.6) + 1) / 2
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(
                            colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.45)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: bedW * 0.7 * CGFloat(tarpProgress), height: 30)
                        .position(x: bedX + bedW * 0.20 + (bedW * 0.7 * CGFloat(tarpProgress)) / 2,
                                  y: bedY - 16)
                        .blendMode(.plusLighter)
                }

                // Chains (V-shape down to bed)
                if flatbedChains {
                    ForEach(0..<3, id: \.self) { i in
                        let cw: CGFloat = bedW / 4
                        let cx = bedX + bedW * 0.20 + CGFloat(i) * (cw + 8) + cw / 2
                        Path { p in
                            p.move(to: .init(x: cx - 14, y: bedY))
                            p.addLine(to: .init(x: cx, y: bedY - 22))
                            p.addLine(to: .init(x: cx + 14, y: bedY))
                        }
                        .stroke(palette.textPrimary.opacity(0.85),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    }
                }

                // Wheels
                ForEach([0.18, 0.32, 0.66, 0.82], id: \.self) { fr in
                    Circle()
                        .fill(palette.textPrimary.opacity(0.85))
                        .frame(width: 12, height: 12)
                        .position(x: bedX + bedW * fr, y: bedY + 14)
                }

                // Cab
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient.diagonal)
                    .frame(width: 44, height: 32)
                    .position(x: bedX - 22, y: bedY - 12)
            }
        }
    }

    // MARK: DRY VAN

    /// Dry van — pallets slide in from the back. Door rolls open.
    private func dryVanStage(t: TimeInterval) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let bodyY = h * 0.30
            let bodyH = h * 0.46
            let bodyW = w * 0.62
            let bodyX = w * 0.22

            ZStack {
                Ellipse().fill(Color.black.opacity(0.22))
                    .frame(width: bodyW + 24, height: 8)
                    .position(x: bodyX + bodyW / 2, y: bodyY + bodyH + 18)
                    .blur(radius: 6)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(
                        colors: [palette.bgCard, palette.bgCardSoft],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: bodyW, height: bodyH)
                    .position(x: bodyX + bodyW / 2, y: bodyY + bodyH / 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(palette.borderFaint, lineWidth: 1.5)
                            .frame(width: bodyW, height: bodyH)
                            .position(x: bodyX + bodyW / 2, y: bodyY + bodyH / 2)
                    )

                // Pallets sliding in (3 of them, staggered)
                ForEach(0..<3, id: \.self) { i in
                    let phase = (t * 0.4 + Double(i) * 0.18).truncatingRemainder(dividingBy: 2.0)
                    let progress = min(phase, 1.0)
                    let pw: CGFloat = bodyW * 0.18
                    let startX = bodyX + bodyW + 30
                    let endX = bodyX + bodyW * 0.20 + CGFloat(i) * (pw + 6)
                    let x = startX + (endX - startX) * CGFloat(progress)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(
                            colors: [Brand.warning.opacity(0.85), Brand.warning.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .frame(width: pw, height: bodyH * 0.55)
                        .position(x: x + pw / 2, y: bodyY + bodyH * 0.55)
                        .opacity(progress < 1 ? 1 : 0)
                }

                // Wheels
                ForEach([0.18, 0.32, 0.66, 0.82], id: \.self) { fr in
                    Circle().fill(palette.textPrimary.opacity(0.85))
                        .frame(width: 12, height: 12)
                        .position(x: bodyX + bodyW * fr, y: bodyY + bodyH + 12)
                }

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient.diagonal)
                    .frame(width: 44, height: bodyH * 0.55)
                    .position(x: bodyX - 22, y: bodyY + bodyH * 0.72)
            }
        }
    }

    // MARK: CONTAINER

    private func containerStage(t: TimeInterval) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Stacked containers (3 high, gentle pulse)
                ForEach(0..<3, id: \.self) { i in
                    let cw: CGFloat = w * 0.45
                    let ch: CGFloat = 24
                    let cy = h * 0.78 - CGFloat(i) * (ch + 4)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(
                            colors: [Brand.info.opacity(0.7 - Double(i) * 0.18),
                                     Brand.info.opacity(0.4 - Double(i) * 0.10)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: cw, height: ch)
                        .position(x: w * 0.5, y: cy)
                        .overlay(
                            // Corrugation
                            Path { p in
                                let count = 8
                                for j in 0..<count {
                                    let x = w * 0.5 - cw / 2 + cw * CGFloat(j) / CGFloat(count - 1)
                                    p.move(to: .init(x: x, y: cy - ch / 2 + 4))
                                    p.addLine(to: .init(x: x, y: cy + ch / 2 - 4))
                                }
                            }
                            .stroke(palette.textPrimary.opacity(0.18), lineWidth: 0.8)
                        )
                        .scaleEffect(1.0 + 0.005 * sin(t * 0.8 + Double(i)))
                }

                // ISO chip
                Text("ISO")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(LinearGradient.diagonal))
                    .position(x: w * 0.5, y: h * 0.18)
            }
        }
    }

    // MARK: POWER ONLY

    private func powerOnlyStage(t: TimeInterval) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Tractor only, dotted "bring own trailer" outline behind
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(palette.textTertiary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: w * 0.45, height: h * 0.40)
                    .position(x: w * 0.62, y: h * 0.55)
                    .opacity(0.6 + 0.4 * sin(t * 0.8))

                Text("BRING OWN TRAILER")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .position(x: w * 0.62, y: h * 0.55)

                // Tractor cab + wheels
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient.diagonal)
                    .frame(width: w * 0.20, height: h * 0.32)
                    .position(x: w * 0.22, y: h * 0.60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.3))
                            .frame(width: w * 0.10, height: h * 0.14)
                            .position(x: w * 0.22, y: h * 0.55)
                    )

                ForEach([0.16, 0.28], id: \.self) { fr in
                    Circle().fill(palette.textPrimary.opacity(0.85))
                        .frame(width: 12, height: 12)
                        .position(x: w * fr, y: h * 0.78)
                }
            }
        }
    }

    // MARK: OVERSIZED

    private func oversizedStage(t: TimeInterval) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Same flatbed body but the cargo overhangs
                flatbedStage(t: t)
                // Red flags on overhang corners
                ForEach(0..<2, id: \.self) { i in
                    let x = i == 0 ? w * 0.16 : w * 0.84
                    let waveAngle = sin(t * 2.5 + Double(i)) * 8
                    Path { p in
                        p.move(to: .init(x: x, y: h * 0.50))
                        p.addLine(to: .init(x: x, y: h * 0.30))
                        p.addLine(to: .init(x: x + 14, y: h * 0.34))
                        p.closeSubpath()
                    }
                    .fill(Brand.danger)
                    .rotationEffect(.degrees(waveAngle), anchor: UnitPoint(x: x / w, y: 0.50))
                }
                // Permit chip
                if oversizePermits {
                    Text("PERMIT")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(Brand.warning))
                        .position(x: w * 0.5, y: h * 0.18)
                }
            }
        }
    }

    // MARK: RAIL

    private func railStage(t: TimeInterval) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Rail car silhouette with container/trailer on top
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(palette.textPrimary.opacity(0.75))
                    .frame(width: w * 0.65, height: 14)
                    .position(x: w * 0.50, y: h * 0.66)

                // Top cargo — container for COFC, trailer for TOFC
                if equipment == .railCOFC || equipment == .railIntermodal {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(
                            colors: [Brand.info.opacity(0.85), Brand.info.opacity(0.55)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: w * 0.55, height: h * 0.30)
                        .position(x: w * 0.50, y: h * 0.46)
                } else if equipment == .railTOFC {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(
                            colors: [palette.bgCard, palette.bgCardSoft],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .frame(width: w * 0.55, height: h * 0.30)
                        .position(x: w * 0.50, y: h * 0.46)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(palette.borderFaint, lineWidth: 1.5)
                                .frame(width: w * 0.55, height: h * 0.30)
                                .position(x: w * 0.50, y: h * 0.46)
                        )
                }

                // Bogie wheels
                ForEach([0.30, 0.40, 0.60, 0.70], id: \.self) { fr in
                    Circle().fill(palette.textPrimary.opacity(0.85))
                        .frame(width: 10, height: 10)
                        .position(x: w * fr, y: h * 0.74)
                }
            }
        }
    }

    // MARK: VESSEL

    private func vesselStage(t: TimeInterval) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let bob = sin(t * 1.0) * 3
            ZStack {
                // Hull
                Path { p in
                    p.move(to: .init(x: w * 0.18, y: h * 0.62 + bob))
                    p.addLine(to: .init(x: w * 0.82, y: h * 0.62 + bob))
                    p.addLine(to: .init(x: w * 0.74, y: h * 0.78 + bob))
                    p.addLine(to: .init(x: w * 0.26, y: h * 0.78 + bob))
                    p.closeSubpath()
                }
                .fill(LinearGradient(
                    colors: [palette.textPrimary.opacity(0.85),
                             palette.textPrimary.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                ))

                // Cargo on deck — container stack for vessel container,
                // bulk dome for vessel bulk, tank rounds for vessel tanker.
                if equipment == .vesselContainer {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(
                                colors: [Brand.info.opacity(0.85 - Double(i) * 0.12),
                                         Brand.info.opacity(0.5 - Double(i) * 0.08)],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: w * 0.42, height: 12)
                            .position(x: w * 0.50, y: h * 0.50 + bob - CGFloat(i) * 14)
                    }
                } else if equipment == .vesselBulk {
                    Path { p in
                        p.move(to: .init(x: w * 0.30, y: h * 0.62 + bob))
                        p.addQuadCurve(to: .init(x: w * 0.70, y: h * 0.62 + bob),
                                       control: .init(x: w * 0.50, y: h * 0.30 + bob))
                        p.closeSubpath()
                    }
                    .fill(Brand.warning.opacity(0.7))
                } else if equipment == .vesselTanker {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(
                            colors: [tankerLiquidColor.opacity(0.85), tankerLiquidColor.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .frame(width: w * 0.50, height: 24)
                        .position(x: w * 0.50, y: h * 0.50 + bob)
                }

                // Bridge tower
                RoundedRectangle(cornerRadius: 2)
                    .fill(palette.bgCard)
                    .frame(width: 14, height: 22)
                    .position(x: w * 0.72, y: h * 0.50 + bob)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(palette.borderFaint, lineWidth: 1)
                            .frame(width: 14, height: 22)
                            .position(x: w * 0.72, y: h * 0.50 + bob)
                    )
            }
        }
    }

    // MARK: - Top-right badges (vertical + product type tag)

    private var topRightBadgeStack: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            Text(equipment.vertical.label.uppercased())
                .font(.system(size: 7, weight: .heavy)).tracking(0.6)
                .foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Capsule().fill(verticalBadgeColor))
            Text(weightUnit.uppercased())
                .font(.system(size: 7, weight: .heavy, design: .monospaced)).tracking(0.4)
                .foregroundStyle(LinearGradient.diagonal)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .overlay(Capsule().strokeBorder(LinearGradient.diagonal.opacity(0.6), lineWidth: 1))
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topTrailing)
    }

    private var verticalBadgeColor: Color {
        switch equipment.vertical {
        case .truck:  return Brand.blue
        case .rail:   return Brand.rail
        case .vessel: return Brand.vessel
        }
    }

    /// Hazmat pulse — full-frame radial wash that intensifies when the
    /// ERG database has matched the UN. Subtle and gradient-doctrine-
    /// compliant; never a flat warning fill.
    @ViewBuilder
    private func hazmatPulse(t: TimeInterval) -> some View {
        if isHazmat {
            let intensity: Double = ergMatched ? 0.20 : 0.10
            let pulse = (sin(t * 1.6) + 1) / 2
            RadialGradient(
                colors: [Brand.hazmat.opacity(intensity * (0.5 + 0.5 * pulse)), .clear],
                center: .center, startRadius: 30, endRadius: 220
            )
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
    }

    // Helper used by reefer stage
    private func parseDouble(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - Public input enums (caller-facing — the wizard's
//         EquipmentChoice + ShipperAPI.CargoType map to these via
//         small extensions defined where the wizard lives)

enum EquipmentKind: String, Hashable {
    case dryVan, reefer, flatbed, stepDeck, conestoga, container
    case tankerHazmat, tankerPetro, tankerLiquid, tankerGas
    case powerOnly, oversized
    case railTOFC, railCOFC, railIntermodal
    case vesselContainer, vesselBulk, vesselTanker

    var vertical: AnimVertical {
        switch self {
        case .railTOFC, .railCOFC, .railIntermodal: return .rail
        case .vesselContainer, .vesselBulk, .vesselTanker: return .vessel
        default: return .truck
        }
    }
}

enum CargoKind: String, Hashable {
    case general, hazmat, refrigerated, oversized
    case liquid, gas, chemicals, petroleum
}

enum AnimVertical: Hashable {
    case truck, rail, vessel
    var label: String {
        switch self {
        case .truck:  return "Truck"
        case .rail:   return "Rail"
        case .vessel: return "Vessel"
        }
    }
}

// MARK: - Previews

#Preview("Tanker · Hazmat · Dark") {
    EquipmentAnimation(
        equipment: .tankerHazmat,
        cargo: .hazmat,
        weightUnit: "bbl",
        tankerHose: "3_camlock",
        isHazmat: true,
        ergMatched: true
    )
    .frame(height: 200)
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Reefer · Light") {
    EquipmentAnimation(
        equipment: .reefer,
        cargo: .refrigerated,
        weightUnit: "plt",
        reeferLowText: "33",
        reeferHighText: "40",
        preCoolRequired: true,
        continuousMode: true
    )
    .frame(height: 200)
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Flatbed · Dark") {
    EquipmentAnimation(
        equipment: .flatbed,
        cargo: .general,
        weightUnit: "lbs",
        flatbedStraps: true,
        flatbedTarps: true,
        flatbedChains: true,
        flatbedEdgeProtectors: true
    )
    .frame(height: 200)
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Vessel · Container · Dark") {
    EquipmentAnimation(
        equipment: .vesselContainer,
        cargo: .general,
        weightUnit: "TEU"
    )
    .frame(height: 200)
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Rail · COFC · Light") {
    EquipmentAnimation(
        equipment: .railCOFC,
        cargo: .general,
        weightUnit: "mt"
    )
    .frame(height: 200)
    .padding()
    .preferredColorScheme(.light)
}
