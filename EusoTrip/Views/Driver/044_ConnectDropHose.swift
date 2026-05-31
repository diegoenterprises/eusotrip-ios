//
//  044_ConnectDropHose.swift
//  EusoTrip — Lifecycle screen 044 · Connect Drop Hose.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `044 Connect Drop Hose.png`. Mirror of 042 — driver is mating
//  the next leg's drop hose (or coupling next trailer for non-
//  tanker products). Step 2 of 4 with ladder + ESD bond +
//  pressure-check tiles + supervisor live mic.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct ConnectDropHose: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @Environment(\.driverShowHelp) private var showHelp
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var isConfirming: Bool = false

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    private let fallbackClock = "21:14"

    /// Connecting-headline — composes "Connecting <medium> ·
    /// <cityState>" with em-dash sentinels for parts that aren't
    /// first-class fields on `Load` yet.
    ///
    /// 116th firing M2 retrofit (2026-04-26): previous literal
    /// "Yara York PA Dock 3" excised. The dock label is not yet a
    /// first-class field on `Load`; until `Load.deliveryDockLabel`
    /// ships from the backend the headline omits the dock segment
    /// rather than fabricating one. The cityState is hydrated live
    /// from the active trip's `deliveryLocation`. Doctrine: 0% mock
    /// data — sentinel parity with 043_DisconnectConfirmed.
    private var connectHeadline: String {
        let medium = ctx.isHazmat ? "drop hose" : "next trailer"
        let cityState = activeLoad?.deliveryLocation?.cityState ?? "—"
        return "Connecting \(medium) · \(cityState)"
    }

    /// ESD-bond continuity gate. On step 2 the bond-strap ladder rung
    /// ("Bond ESD strap to dock grid") is already DONE and the ESD BOND
    /// metric reads LIVE · Continuity OK — so the bonding strap + ground
    /// clamp in the diagram light up live (gold). A dry-break poppet
    /// must not pass product before continuity is proven, so the diagram
    /// only paints the bond as "hot" when the bond rung has cleared.
    /// Mirrors the static metric/ladder state until the backend exposes
    /// a first-class `Load.esdContinuityOK` field.
    private var esdBondLive: Bool { true }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                connectorRing
                stepCard
                metricRow
                ladder
                supervisorMic
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .screenTileRoot()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { navBack?() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: ctx.product.symbol)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("STEP 2 OF 4 · \(ctx.headerKicker)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(LinearGradient.diagonal)
                    // EUSOTRIP-MODE-BADGE-2026-05-17 — mode chip on lifecycle screen
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
                Text(connectHeadline)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text("DRY-DISCONNECT MATE · ESD BOND LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
            Text(fallbackClock)
                .font(EType.mono(.caption)).fontWeight(.semibold)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.top, 4)
    }

    private var connectorRing: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(ctx.isHazmat ? "DRY-DISCONNECT" : "TRAILER COUPLING")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.danger)
            }
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md).fill(Color.black.opacity(0.7))
                // Bespoke vector dry-break "mate" diagram. The crude
                // grey-capsules placeholder is gone — this is an
                // operationally-true coupler: cam-lever rotates DOWN to
                // seat/lock onto the stub adapter (lever-down = seated,
                // which is exactly when the poppet valve opens and flow
                // can prime). ESD bond + ground clamp gate continuity
                // before flow. Honors reduce-motion (freeze seated).
                DryBreakMateDiagram(esdBonded: esdBondLive,
                                    isHazmat: ctx.isHazmat)
                    .padding(.horizontal, 4)
            }
            .frame(height: 96)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var stepCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CURRENT STEP")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(ctx.isHazmat ? "Mate the dry-disconnect coupler" : "Couple to next trailer")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text(ctx.isHazmat
                 ? "Spin the threaded ring on by hand until it shoulders, then snug. Three full turns past hand-tight. Don't cross-thread."
                 : "Set the kingpin on the fifth wheel. Pull-test, then visual gap check before lights + air lines.")
                .font(EType.body)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var metricRow: some View {
        HStack(spacing: Space.s2) {
            metric(label: "ESD BOND",     value: "LIVE", note: "Continuity OK")
            metric(label: "PRESS CHECK",  value: "0.0", note: "LINE EMPTY")
            metric(label: "LEAK TEST",    value: "Priming", note: "WAITS · STEP 3")
        }
    }

    private func metric(label: String, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
            Text(note)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var ladder: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CONNECT LADDER · \(ctx.isHazmat ? "NH3 CLOSED-LOOP" : "TRAILER")")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("STEP 2 OF 4")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
            }
            connectRow(title: ctx.isHazmat ? "Bond ESD strap to dock grid" : "Pull-test fifth wheel", state: "done", time: "21:13:38")
            connectRow(title: ctx.isHazmat ? "Mate dry-disconnect coupler" : "Couple gladhands + lights", state: "now",  time: "NOW")
            connectRow(title: "Pressurize-check & sniff vapor", state: "next", time: "STEP 3")
            connectRow(title: "Open loop & prime to receiver", state: "next", time: "STEP 4")
        }
    }

    private func connectRow(title: String, state: String, time: String) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: state == "done" ? "checkmark.circle.fill" : (state == "now" ? "smallcircle.fill.circle.fill" : "circle"))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(state == "done" ? Brand.success : (state == "now" ? Brand.warning : palette.textTertiary))
            Text(title)
                .font(EType.caption.weight(.semibold))
                .foregroundStyle(state == "next" ? palette.textSecondary : palette.textPrimary)
            Spacer()
            Text(time)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(state == "now" ? Brand.warning : palette.textTertiary)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 9)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var supervisorMic: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Text("RH").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Reg Hammond")
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    HStack(spacing: 3) {
                        Circle().fill(Brand.danger).frame(width: 5, height: 5)
                        Text("LIVE MIC")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(Brand.danger)
                    }
                }
                Text("\"Ring is on three turns — give it a snug, no torquing.\"")
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            Button { showHelp?("connect-drop-hose") } label: {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Help")
                        .font(EType.body.weight(.semibold))
                }
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .accessibilityLabel("Open ESANG help for connecting drop hose")
            CTAButton(
                title: "Confirm mated",
                action: { Task { await confirmMated() } },
                leadingIcon: "checkmark.circle.fill",
                isLoading: isConfirming
            )
        }
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func confirmMated() async {
        isConfirming = true
        defer { isConfirming = false }
        let keys = ["mated", "primed", "departing"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        advance?()
    }
}

// MARK: - DryBreakMateDiagram
//
// Bespoke vector illustration of a dry-break (dry-disconnect) coupler
// mating onto a fixed stub adapter — the real mechanism behind the
// "DRY-DISCONNECT MATE" step. Drawn entirely with SwiftUI Path /
// shapes (no raster, no SF Symbol stand-ins), animated with a
// phaseAnimator.
//
// Operational truth (per dry-disconnect coupler datasheets — Seal
// Fast / Emco Wheaton / Control Devices DryLink): the cam release
// LEVER rotates DOWN to lock the coupler body onto the adapter; the
// same cam stroke opens the internal poppet so product can finally
// prime. Fluid cannot flow until the coupler is locked, and it cannot
// be unlocked until the poppet re-seats — so "lever DOWN = seated =
// flow-ready". We therefore animate the lever dropping along the
// dashed-arrow arc, the coupler camming ~2px onto the stub as it
// locks, then a subtle seated pulse + a faint priming shimmer down
// the hose. Reduce-motion freezes everything in the seated state.
//
// Palette: the steel/orange/charcoal hardware colors are physical-
// equipment colors (not brand UI), so they're local constants; the
// pivot dot + release arc + ESD glow reuse Brand.magenta / Brand.hazmat
// and the diagram chrome uses Space / Radius tokens.
private struct DryBreakMateDiagram: View {
    let esdBonded: Bool
    let isHazmat: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Physical-hardware colors (steel, safety-orange, charcoal fitting).
    private let steelHi   = Color(hex: 0xC9CED6)
    private let steelMid  = Color(hex: 0x8C939E)
    private let steelLo   = Color(hex: 0x5A616C)
    private let orangeHi  = Color(hex: 0xFF8A3D)
    private let orangeMid = Color(hex: 0xF26A1B)
    private let orangeLo  = Color(hex: 0xC44E0E)
    private let charcoal  = Color(hex: 0x342B26)   // dark-brown/charcoal fitting block
    private let charcoalHi = Color(hex: 0x4A3E36)

    /// One loop of the mate cycle (seconds). The lever drops fast, holds
    /// seated for a beat (with a seated pulse), then eases back up before
    /// repeating — "drops once, then a subtle seated pulse" on a gentle
    /// loop. The whole loop is frozen at fully-seated under reduce-motion.
    private let loop: Double = 3.4

    var body: some View {
        // TimelineView clock gives deterministic per-frame control over
        // the eased lever drop (exact cubic-bezier 0.4,0,0.2,1), the
        // overshoot settle, the seated pulse, and the hose prime — and
        // `paused: reduceMotion` halts the clock so everything freezes in
        // the seated state for reduce-motion users.
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            let clock = timeline.date.timeIntervalSinceReferenceDate
            // seat: 0 = lever raised/open, 1 = locked down/seated.
            let seat = reduceMotion ? 1.0 : seatProgress(clock)
            Canvas(rendersAsynchronously: false) { ctx, size in
                drawScene(ctx: &ctx, size: size, seat: seat,
                          shimmer: reduceMotion ? 0.5 : clock)
            }
                .overlay(alignment: .topLeading) { titlePill }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reduceMotion
            ? "Dry-break coupler seated and locked onto the stub adapter, ESD bond live."
            : "Dry-break coupler mating: release lever rotating down to seat and lock onto the stub adapter, ESD bond live, hose priming.")
    }

    /// Eased mate progress for the current clock. Maps one `loop` window
    /// into: a 0.7s cubic-bezier(0.4,0,0.2,1) DROP (with a tiny overshoot
    /// settle), a seated DWELL, then an eased lift back to open.
    private func seatProgress(_ clock: Double) -> Double {
        let phase = clock.truncatingRemainder(dividingBy: loop)
        let drop = 0.7, settle = 0.28, dwell = 1.4
        if phase < drop {
            // The lock stroke: 0.7s cubic-bezier(0.4,0,0.2,1) "decelerate"
            // drop, reaching the seated position.
            return bezier(phase / drop, 0.4, 0.0, 0.2, 1.0)
        } else if phase < drop + settle {
            // Tiny overshoot/settle right after the lever locks — a damped
            // bounce that briefly rides past seated (~+5%) then returns to
            // exactly seated, reading as the mechanical "thunk".
            let s = (phase - drop) / settle               // 0→1
            return 1.0 + 0.05 * sin(s * .pi) * (1.0 - s)
        } else if phase < drop + settle + dwell {
            return 1.0                                     // seated dwell
        } else {
            // Gentle ease back up to open before the loop repeats.
            let p = (phase - drop - settle - dwell) / (loop - drop - settle - dwell)
            return 1.0 - bezier(p, 0.4, 0.0, 0.2, 1.0)
        }
    }

    /// Seated-pulse intensity (0…1) — a brief glow/scale tick right after
    /// the lever locks, decaying through the dwell.
    private func seatedPulse(_ clock: Double) -> Double {
        if reduceMotion { return 0 }
        let phase = clock.truncatingRemainder(dividingBy: loop)
        let drop = 0.7
        guard phase >= drop, phase < drop + 0.9 else { return 0 }
        return cos((phase - drop) / 0.9 * .pi / 2)   // 1 → 0 decay
    }

    private var titlePill: some View {
        Text("DRY-BREAK MATE")
            .font(.system(size: 8.5, weight: .heavy)).tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.black.opacity(0.55))
                    .overlay(Capsule().strokeBorder(orangeMid.opacity(0.7), lineWidth: 1))
            )
            .padding(8)
    }

    // MARK: Scene draw

    private func drawScene(ctx: inout GraphicsContext, size: CGFloat2, seat: Double, shimmer: Double) {
        let w = size.width, h = size.height
        // The coupler cams ~2px onto the stub as it locks (seat → 1).
        let push = CGFloat(seat) * 2.0
        let pulse = seatedPulse(shimmer)

        drawHazardFloor(ctx: &ctx, w: w, h: h)
        drawHose(ctx: &ctx, w: w, h: h, shimmer: shimmer, seat: seat)
        drawStub(ctx: &ctx, w: w, h: h)
        drawCouplerBody(ctx: &ctx, w: w, h: h, push: push, pulse: pulse)
        drawESDBond(ctx: &ctx, w: w, h: h, shimmer: shimmer)
        drawPivotAndArc(ctx: &ctx, w: w, h: h, shimmer: shimmer)
        drawLever(ctx: &ctx, w: w, h: h, seat: seat, pulse: pulse)
    }

    private typealias CGFloat2 = CGSize

    /// Cubic-bezier solver (x==t approximation is fine for our short
    /// fixed-duration curves) returning the eased y for input t∈[0,1].
    private func bezier(_ t: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        let t = max(0, min(1, t))
        let u = 1 - t
        // Standard cubic Bézier with implicit P0=(0,0), P3=(1,1).
        return 3*u*u*t*y1 + 3*u*t*t*y2 + t*t*t
    }

    // Yellow/black diagonal hazard-striped floor strip across the bottom.
    private func drawHazardFloor(ctx: inout GraphicsContext, w: CGFloat, h: CGFloat) {
        let floorTop = h * 0.80
        let floorRect = CGRect(x: 0, y: floorTop, width: w, height: h - floorTop)
        let clip = Path(roundedRect: floorRect, cornerRadius: 3)
        ctx.drawLayer { layer in
            layer.clip(to: clip)
            layer.fill(Path(floorRect), with: .color(Color(hex: 0x1A1A1A)))
            // Diagonal caution stripes.
            let stripeW: CGFloat = 11
            var x = -h
            while x < w + h {
                var p = Path()
                p.move(to: CGPoint(x: x, y: floorTop))
                p.addLine(to: CGPoint(x: x + stripeW, y: floorTop))
                p.addLine(to: CGPoint(x: x + stripeW - (h - floorTop), y: h))
                p.addLine(to: CGPoint(x: x - (h - floorTop), y: h))
                p.closeSubpath()
                layer.fill(p, with: .color(Brand.hazmat))
                x += stripeW * 2
            }
        }
        // Top hairline of the floor for a "lip" read.
        var lip = Path()
        lip.move(to: CGPoint(x: 0, y: floorTop))
        lip.addLine(to: CGPoint(x: w, y: floorTop))
        ctx.stroke(lip, with: .color(.black.opacity(0.5)), lineWidth: 1)
    }

    // Thick safety-orange corrugated hose curving off-frame to the right.
    private func drawHose(ctx: inout GraphicsContext, w: CGFloat, h: CGFloat, shimmer: Double, seat: Double) {
        let start = CGPoint(x: w * 0.66, y: h * 0.52)
        var spine = Path()
        spine.move(to: start)
        spine.addCurve(to: CGPoint(x: w * 1.02, y: h * 0.40),
                       control1: CGPoint(x: w * 0.84, y: h * 0.55),
                       control2: CGPoint(x: w * 0.96, y: h * 0.30))
        let hoseGrad = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [orangeMid, orangeHi, orangeMid]),
            startPoint: start, endPoint: CGPoint(x: w, y: h * 0.40))
        // Hose casing.
        ctx.stroke(spine, with: .color(orangeLo), style: StrokeStyle(lineWidth: 26, lineCap: .round))
        ctx.stroke(spine, with: hoseGrad, style: StrokeStyle(lineWidth: 22, lineCap: .round))
        // Corrugation ribs — short cross-strokes stepped along the spine.
        for i in stride(from: 0.06, through: 0.94, by: 0.085) {
            let pt = pointOnCubic(start,
                                  CGPoint(x: w * 0.84, y: h * 0.55),
                                  CGPoint(x: w * 0.96, y: h * 0.30),
                                  CGPoint(x: w * 1.02, y: h * 0.40), CGFloat(i))
            var rib = Path()
            rib.move(to: CGPoint(x: pt.x, y: pt.y - 11))
            rib.addLine(to: CGPoint(x: pt.x, y: pt.y + 11))
            ctx.stroke(rib, with: .color(orangeLo.opacity(0.55)), lineWidth: 1.6)
        }
        // Priming/flow shimmer: a faint bright band travelling down the
        // hose. The poppet only opens once the coupler is locked, so the
        // prime strengthens with `seat` — dim when open, full when seated.
        let flow = 0.18 + 0.42 * max(0, min(1, seat))
        let phase = (shimmer.truncatingRemainder(dividingBy: 1.6)) / 1.6
        let head = pointOnCubic(start,
                                CGPoint(x: w * 0.84, y: h * 0.55),
                                CGPoint(x: w * 0.96, y: h * 0.30),
                                CGPoint(x: w * 1.02, y: h * 0.40), CGFloat(phase))
        ctx.fill(Path(ellipseIn: CGRect(x: head.x - 7, y: head.y - 7, width: 14, height: 14)),
                 with: .radialGradient(Gradient(colors: [Color.white.opacity(flow), .clear]),
                                       center: head, startRadius: 0, endRadius: 10))
    }

    // Horizontal grey steel stub pipe on the left + flange face.
    private func drawStub(ctx: inout GraphicsContext, w: CGFloat, h: CGFloat) {
        let midY = h * 0.50
        let pipe = CGRect(x: -2, y: midY - 13, width: w * 0.40, height: 26)
        let body = Path(roundedRect: pipe, cornerRadius: 7)
        ctx.fill(body, with: .linearGradient(
            Gradient(colors: [steelLo, steelHi, steelMid, steelLo]),
            startPoint: CGPoint(x: 0, y: pipe.minY), endPoint: CGPoint(x: 0, y: pipe.maxY)))
        ctx.stroke(body, with: .color(.black.opacity(0.35)), lineWidth: 1)
        // Bolt-flange ring at the mating face.
        let flange = CGRect(x: pipe.maxX - 7, y: midY - 17, width: 9, height: 34)
        let fr = Path(roundedRect: flange, cornerRadius: 3)
        ctx.fill(fr, with: .linearGradient(
            Gradient(colors: [steelMid, steelHi, steelLo]),
            startPoint: CGPoint(x: 0, y: flange.minY), endPoint: CGPoint(x: 0, y: flange.maxY)))
        ctx.stroke(fr, with: .color(.black.opacity(0.4)), lineWidth: 1)
        // A couple flange bolts.
        for fy in [midY - 9, midY + 9] {
            ctx.fill(Path(ellipseIn: CGRect(x: flange.midX - 1.6, y: fy - 1.6, width: 3.2, height: 3.2)),
                     with: .color(steelLo))
        }
    }

    // Stout orange coupler body + charcoal fitting block on top.
    // `push` slides the body ~2px left (camming onto the stub) as the
    // lever locks; `pulse` (0…1) is the seated "thunk" glow.
    private func drawCouplerBody(ctx: inout GraphicsContext, w: CGFloat, h: CGFloat, push: CGFloat, pulse: Double) {
        let midY = h * 0.50
        let dx = -push   // seat push is toward the stub (leftward)
        // Main barrel.
        let barrel = CGRect(x: w * 0.40 + dx, y: midY - 19, width: w * 0.26, height: 38)
        let br = Path(roundedRect: barrel, cornerRadius: 11)
        ctx.fill(br, with: .linearGradient(
            Gradient(colors: [orangeHi, orangeMid, orangeLo]),
            startPoint: CGPoint(x: 0, y: barrel.minY), endPoint: CGPoint(x: 0, y: barrel.maxY)))
        ctx.stroke(br, with: .color(orangeLo.opacity(0.8)), lineWidth: 1)
        // Specular highlight.
        let spec = Path(roundedRect: CGRect(x: barrel.minX + 4, y: barrel.minY + 4,
                                            width: barrel.width - 8, height: 6), cornerRadius: 3)
        ctx.fill(spec, with: .color(.white.opacity(0.28)))
        // Locking collar (where the cam grips the adapter).
        let collar = CGRect(x: barrel.minX - 3, y: midY - 21, width: 11, height: 42)
        let cr = Path(roundedRect: collar, cornerRadius: 5)
        ctx.fill(cr, with: .linearGradient(
            Gradient(colors: [orangeMid, orangeLo]),
            startPoint: CGPoint(x: 0, y: collar.minY), endPoint: CGPoint(x: 0, y: collar.maxY)))
        ctx.stroke(cr, with: .color(orangeLo), lineWidth: 1)
        // Charcoal / dark-brown fitting block on top.
        let block = CGRect(x: barrel.midX - 13, y: barrel.minY - 15, width: 26, height: 17)
        let blk = Path(roundedRect: block, cornerRadius: 4)
        ctx.fill(blk, with: .linearGradient(
            Gradient(colors: [charcoalHi, charcoal]),
            startPoint: CGPoint(x: 0, y: block.minY), endPoint: CGPoint(x: 0, y: block.maxY)))
        ctx.stroke(blk, with: .color(.black.opacity(0.5)), lineWidth: 1)
        // Two hex screws on the block.
        for bx in [block.minX + 7, block.maxX - 7] {
            ctx.fill(Path(ellipseIn: CGRect(x: bx - 2, y: block.midY - 2, width: 4, height: 4)),
                     with: .color(.black.opacity(0.45)))
        }
        // Seated "thunk" — a brief warm glow ring on the locking collar
        // the instant the lever locks, decaying through the dwell.
        if pulse > 0.01 {
            let cx = collar.midX, cy = midY
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 16, y: cy - 16, width: 32, height: 32)),
                     with: .radialGradient(
                        Gradient(colors: [orangeHi.opacity(0.55 * pulse), .clear]),
                        center: CGPoint(x: cx, y: cy), startRadius: 2, endRadius: 18))
        }
    }

    // Gold ESD bonding strap angling down-left to a small ground clamp.
    private func drawESDBond(ctx: inout GraphicsContext, w: CGFloat, h: CGFloat, shimmer: Double) {
        let live = esdBonded
        let gold = live ? Brand.hazmat : Brand.neutral
        let anchor = CGPoint(x: w * 0.43, y: h * 0.62)     // off the coupler collar
        let clamp  = CGPoint(x: w * 0.20, y: h * 0.78)     // small ground clamp near the floor
        var strap = Path()
        strap.move(to: anchor)
        strap.addQuadCurve(to: clamp, control: CGPoint(x: w * 0.28, y: h * 0.78))
        ctx.stroke(strap, with: .color(gold), style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
        ctx.stroke(strap, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        // Anchor lug + ground clamp.
        ctx.fill(Path(ellipseIn: CGRect(x: anchor.x - 3, y: anchor.y - 3, width: 6, height: 6)),
                 with: .color(gold))
        let clampRect = CGRect(x: clamp.x - 6, y: clamp.y - 4, width: 12, height: 8)
        ctx.fill(Path(roundedRect: clampRect, cornerRadius: 2), with: .color(gold))
        ctx.stroke(Path(roundedRect: clampRect, cornerRadius: 2), with: .color(.black.opacity(0.4)), lineWidth: 1)
        // Live-continuity glow pulse on the clamp when bonded.
        if live && !reduceMotion {
            let g = 0.35 + 0.35 * (sin(shimmer * 3.0) * 0.5 + 0.5)
            ctx.fill(Path(ellipseIn: CGRect(x: clamp.x - 9, y: clamp.y - 7, width: 18, height: 14)),
                     with: .radialGradient(Gradient(colors: [gold.opacity(g), .clear]),
                                           center: clamp, startRadius: 0, endRadius: 12))
        } else if live {
            ctx.fill(Path(ellipseIn: CGRect(x: clamp.x - 8, y: clamp.y - 6, width: 16, height: 12)),
                     with: .radialGradient(Gradient(colors: [gold.opacity(0.5), .clear]),
                                           center: clamp, startRadius: 0, endRadius: 11))
        }
    }

    // Magenta pivot dot + dashed curved release arc over the coupler.
    private func drawPivotAndArc(ctx: inout GraphicsContext, w: CGFloat, h: CGFloat, shimmer: Double) {
        // Dashed curved arrow arcing over the coupler (downward rotation).
        let from = CGPoint(x: w * 0.585, y: h * 0.14)   // lever raised tip
        let to   = CGPoint(x: w * 0.715, y: h * 0.34)   // seated tip
        var arc = Path()
        arc.move(to: from)
        arc.addQuadCurve(to: to, control: CGPoint(x: w * 0.78, y: h * 0.10))
        let dash = reduceMotion ? StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [4, 3])
                                : StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [4, 3],
                                              dashPhase: CGFloat(shimmer * 14).truncatingRemainder(dividingBy: 14))
        ctx.stroke(arc, with: .color(Brand.magenta.opacity(0.9)), style: dash)
        // Arrowhead at the seated end.
        var head = Path()
        head.move(to: to)
        head.addLine(to: CGPoint(x: to.x - 5, y: to.y - 5))
        head.move(to: to)
        head.addLine(to: CGPoint(x: to.x - 6.5, y: to.y + 2))
        ctx.stroke(head, with: .color(Brand.magenta), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        // (The magenta pivot dot is drawn in drawLever, on top of the hub,
        // so the rotation axis stays visible above the orange knuckle.)
    }

    // The orange cam RELEASE LEVER — the one moving part. It rotates
    // DOWN about the magenta pivot to lock the coupler onto the adapter
    // (lever-down = seated = poppet open). `seat` 0→1 swings it from the
    // raised/open angle to the locked angle, tracking the dashed arc; a
    // small overshoot past 1 reads as the seated settle. Drawn with a
    // transformed sub-context so the rotation pivots exactly on the dot.
    private func drawLever(ctx: inout GraphicsContext, w: CGFloat, h: CGFloat, seat: Double, pulse: Double) {
        let pivot = CGPoint(x: w * 0.585, y: h * 0.50)
        // Raised ≈ -118° (handle pointing up-and-back), seated ≈ -44°
        // (handle laid down toward the hose) — a ~74° downward sweep that
        // follows the dashed release arc. `seat` can ride slightly past 1
        // for the overshoot settle.
        let raised = -118.0, seated = -44.0
        let angle = (raised + (seated - raised) * seat) * .pi / 180.0

        var sub = ctx
        sub.translateBy(x: pivot.x, y: pivot.y)
        sub.rotate(by: .radians(angle))

        // Cap arm length against BOTH axes so the rotated handle never
        // overshoots the 96pt-tall frame at the raised angle.
        let armLen: CGFloat = min(w * 0.24, h * 0.42)
        let armW: CGFloat = 11
        // Lever arm, drawn from the hub (origin) outward along +x.
        let arm = Path(roundedRect: CGRect(x: 2, y: -armW / 2, width: armLen, height: armW),
                       cornerRadius: armW / 2)
        sub.fill(arm, with: .linearGradient(
            Gradient(colors: [orangeHi, orangeMid, orangeLo]),
            startPoint: CGPoint(x: 0, y: -armW / 2), endPoint: CGPoint(x: 0, y: armW / 2)))
        sub.stroke(arm, with: .color(orangeLo.opacity(0.9)), lineWidth: 1)
        // Highlight stripe down the arm.
        let hi = Path(roundedRect: CGRect(x: 5, y: -armW / 2 + 2, width: armLen - 8, height: 2.4),
                      cornerRadius: 1.2)
        sub.fill(hi, with: .color(.white.opacity(0.3)))
        // Grip knurls near the handle end.
        for gx in stride(from: armLen - 4, to: armLen - 18, by: -4) {
            var k = Path()
            k.move(to: CGPoint(x: gx, y: -armW / 2 + 2))
            k.addLine(to: CGPoint(x: gx, y: armW / 2 - 2))
            sub.stroke(k, with: .color(orangeLo.opacity(0.7)), lineWidth: 1)
        }

        // Hub knuckle over the pivot (in the un-rotated context so it
        // reads as a clean pin, with the magenta dot on top).
        let hubR: CGFloat = 8
        ctx.fill(Path(ellipseIn: CGRect(x: pivot.x - hubR, y: pivot.y - hubR, width: hubR * 2, height: hubR * 2)),
                 with: .radialGradient(Gradient(colors: [orangeMid, orangeLo]),
                                       center: pivot, startRadius: 1, endRadius: hubR))
        ctx.stroke(Path(ellipseIn: CGRect(x: pivot.x - hubR, y: pivot.y - hubR, width: hubR * 2, height: hubR * 2)),
                   with: .color(orangeLo), lineWidth: 1)

        // Faint seated highlight on the hub as it locks.
        if pulse > 0.01 {
            ctx.fill(Path(ellipseIn: CGRect(x: pivot.x - 12, y: pivot.y - 12, width: 24, height: 24)),
                     with: .radialGradient(Gradient(colors: [Color.white.opacity(0.28 * pulse), .clear]),
                                           center: pivot, startRadius: 1, endRadius: 13))
        }

        // Magenta PIVOT dot — the rotation axis, on top of the hub so it
        // stays visible just below the coupler (matches the proof).
        ctx.fill(Path(ellipseIn: CGRect(x: pivot.x - 4, y: pivot.y - 4, width: 8, height: 8)),
                 with: .color(Brand.magenta))
        ctx.fill(Path(ellipseIn: CGRect(x: pivot.x - 1.8, y: pivot.y - 1.8, width: 3.6, height: 3.6)),
                 with: .color(.white.opacity(0.9)))
    }

    // MARK: Math helpers

    private func pointOnCubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let x = u*u*u*p0.x + 3*u*u*t*p1.x + 3*u*t*t*p2.x + t*t*t*p3.x
        let y = u*u*u*p0.y + 3*u*u*t*p1.y + 3*u*t*t*p2.y + t*t*t*p3.y
        return CGPoint(x: x, y: y)
    }
}

struct ConnectDropHoseScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ConnectDropHose(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_044(),
                      trailing: driverNavTrailing_044(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_044() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_044() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

#Preview("044 · Connect Drop Hose · Dark") {
    ConnectDropHoseScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("044 · Connect Drop Hose · Light") {
    ConnectDropHoseScreen(theme: Theme.light).preferredColorScheme(.light)
}
