//
//  ModularTickBezel.swift
//  EusoTrip Pulse Watch App — Modular Ultra design language
//
//  Purely decorative overlay that adopts the Apple Watch Ultra
//  "Modular Ultra" watch-face's circumferential tick-mark rails +
//  four corner labels. Sits on top of an existing ZStack so it never
//  interacts with the live data columns underneath.
//
//  Design doctrine (2026-04-24 user anchor):
//
//    • Apple Watch Ultra "Modular Ultra" is the design inspiration
//      for the EusoTrip Pulse UI. The tick-mark rails wrap around the
//      top + bottom edges; short ticks between long ones; a tiny
//      colored dot marks the bottom rail's midpoint the same way the
//      reference face highlights 6 o'clock.
//
//    • Corner labels sit flush to the bezel curve with wide tracking
//      and micro type — "VITALS" / "TRAINING" / "NO WORKOUTS" /
//      "TYPICAL" in the reference translates here to duty-status /
//      fatigue / link / convoy labels the driver glances at.
//
//    • Pure Canvas rendering. No Shape views allocated per frame;
//      no state; no animation. This keeps the cost to a single
//      pass even on a 38mm S6 where we're frame-budget sensitive
//      in the instrument panel.
//

import SwiftUI

struct ModularTickBezel: View {
    struct Corners: Equatable {
        var topLeading:     String
        var topTrailing:    String
        var bottomLeading:  String
        var bottomTrailing: String
    }

    let corners: Corners

    /// Number of ticks across the rail. 36 at most — denser than that
    /// turns into a solid line on a 42mm watch. 28 is the reference
    /// density on a 49mm Apple Watch Ultra.
    var tickCount: Int = 28

    /// Highlight dot diameter on the bottom rail midpoint, in points.
    var midpointDotDiameter: CGFloat = 4

    var body: some View {
        // Tick rails removed — they were rendering as visible lines
        // bleeding into every page's content. Apple's own watchOS apps
        // don't decorate the bezel; the hardware curve is the chrome.
        // Only the four corner labels remain, hugging the curve so
        // they sit at the watch's literal bezel edge rather than in
        // the content's reading column.
        GeometryReader { geo in
            cornerLabels(in: geo.size)
        }
    }

    // MARK: - Tick rail

    private func tickRail(in size: CGSize, top: Bool) -> some View {
        Canvas { ctx, _ in
            let step = (size.width - 24) / CGFloat(tickCount)
            let yBase: CGFloat = top ? 6 : size.height - 6
            let longH: CGFloat = 6
            let shortH: CGFloat = 3

            for i in 0...tickCount {
                let x = 12 + CGFloat(i) * step
                let isMajor = (i % 5 == 0)
                let h = isMajor ? longH : shortH
                let y0 = top ? yBase : yBase - h
                let y1 = top ? yBase + h : yBase
                let rect = CGRect(
                    x: x - 0.5,
                    y: y0,
                    width: 1,
                    height: y1 - y0
                )
                let opacity: Double = isMajor ? 0.85 : 0.38
                ctx.fill(Path(rect), with: .color(.white.opacity(opacity)))
            }

            // Midpoint accent — a tiny dot inside the bottom rail's
            // centre, styled like the blue highlight in the reference.
            if !top {
                let cx = size.width / 2
                let cy = yBase - midpointDotDiameter / 2
                let dot = Path(ellipseIn: CGRect(
                    x: cx - midpointDotDiameter / 2,
                    y: cy - midpointDotDiameter / 2,
                    width: midpointDotDiameter,
                    height: midpointDotDiameter
                ))
                ctx.fill(dot, with: .color(.esangBlue))
            }
        }
    }

    // MARK: - Corner labels
    //
    // Short labels flush to the bezel curve. Tracking + caps mimics
    // the Modular Ultra's "VITALS" / "TRAINING" / "NO WORKOUTS" /
    // "TYPICAL" corner language. Rotated zero degrees (not along the
    // bezel curve) because even on the 49mm the text reads cleaner
    // flat than it does warped around the radius.

    private func cornerLabels(in size: CGSize) -> some View {
        VStack {
            HStack {
                cornerLabel(corners.topLeading,  align: .leading)
                Spacer(minLength: 0)
                cornerLabel(corners.topTrailing, align: .trailing)
            }
            .padding(.top, 2)
            Spacer()
            HStack {
                cornerLabel(corners.bottomLeading,  align: .leading)
                Spacer(minLength: 0)
                cornerLabel(corners.bottomTrailing, align: .trailing)
            }
            .padding(.bottom, 2)
        }
        .padding(.horizontal, 6)
    }

    private func cornerLabel(
        _ text: String,
        align: HorizontalAlignment
    ) -> some View {
        Text(text)
            .font(.system(size: 7, weight: .semibold, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.45))
            .lineLimit(1)
            .frame(
                maxWidth: 56,
                alignment: align == .leading ? .leading : .trailing
            )
            .allowsTightening(true)
            .minimumScaleFactor(0.6)
    }
}

#Preview {
    ZStack {
        Color.black
        ModularTickBezel(
            corners: .init(
                topLeading:     "DRV 7:42",
                topTrailing:    "TYPICAL",
                bottomLeading:  "LINK",
                bottomTrailing: "CONVOY 3"
            )
        )
    }
    .preferredColorScheme(.dark)
}
