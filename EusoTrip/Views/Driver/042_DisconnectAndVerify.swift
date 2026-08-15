//
//  042_DisconnectAndVerify.swift
//  EusoTrip — Lifecycle screen 042 · Disconnect & Verify.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `042 Disconnect and Verify.png`. Driver is at the dry-disconnect
//  ring (or trailer-side disconnect for non-tanker products) with
//  ESANG narrating the step. Animated coupler diagram + 3
//  pressure/vapor/bond tiles + 4-step ladder + supervisor live mic
//  + Help / Confirm uncoupled CTAs.
//
//  Wave-A1 (2026-06-10): the grey-capsules placeholder is DEAD —
//  replaced with `DryBreakReleaseDiagram`, the 044 mate diagram
//  ported in REVERSE per the operational truth of a dry-disconnect:
//  the poppet RE-SEATS first (flow shimmer dies — product cannot be
//  trapped in an open line), the re-seat is verified, and only THEN
//  does the cam lever lift along the release arc to free the coupler
//  off the stub adapter. Once the driver confirms uncoupled (the
//  real lifecycle event) the diagram freezes at the released pose.
//  Reduce-motion freezes at the SAFE state: poppet re-seated, flow
//  dead, lever still locked.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct DisconnectAndVerify: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @Environment(\.driverShowHelp) private var showHelp
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var isConfirming: Bool = false
    /// True once the driver has confirmed the uncouple on THIS screen —
    /// the real confirmation event that freezes the diagram released.
    @State private var uncoupleConfirmed: Bool = false

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    /// Real uncouple state. The diagram loops the INSTRUCTIONAL release
    /// cycle (re-seat → flow dies → lever lifts) until the disconnect
    /// is actually confirmed — either the lifecycle state says so or
    /// the driver just confirmed it here — then freezes at the
    /// RELEASED pose. Real state, never a decorative loop.
    private var isUncoupled: Bool {
        if uncoupleConfirmed { return true }
        let s = (lifecycle.currentState ?? activeLoad?.status ?? "").lowercased()
        return s.contains("disconnect_confirmed") || s.contains("stowed")
            || s.contains("released") || s.contains("uncoupled")
    }

    // Production-clean placeholders. Updated 2026-04-24
    // (eusotrip-killers ledger-hygiene pass). Live readings come from
    // `tankMonitor.getDisconnectSnapshot` once the bay-ops sensor stack
    // ships — until then, em-dashes only.
    private let fallbackPressure = "-"
    private let fallbackVapor    = "-"
    private let fallbackBond     = "-"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                couplerRing
                stepCard
                // Wave B (2026-06-10) — during disconnect/verify the
                // driver sees the UNLOADING procedure animation for the
                // real rig, bound live. Complements the reverse-mate
                // coupler diagram above (the A1 quality bar) — never
                // replaces it.
                DriverEquipmentMoment(
                    facts: activeLoad.map(LoadAnimationContext.DriverLoadFacts.init(load:)),
                    state: .unloading,
                    label: "DISCONNECT & VERIFY"
                )
                metricRow
                ladderCard
                supervisorMic
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .eusoRefreshTask { await hydrateLiveTrip() }
        .screenTileRoot()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            // 100th firing · ledger-hygiene sweep — wired no-op chevron to
            // `driverNavBack` so back-nav walks the lifecycle phase backward.
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
                    Text(ctx.headerKicker)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(LinearGradient.diagonal)
                    // EUSOTRIP-MODE-BADGE-2026-05-17 — mode chip on lifecycle screen
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
                Text("Disconnecting \(ctx.isHazmat ? "NH3 line" : "trailer")")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text("COUPLER UNHOOK")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 0)
            // Live device clock — the header time is the driver's wall
            // clock, not a seeded literal. There is no event/elapsed
            // source on this screen, so we render the real `Date()`
            // (HH:mm, refreshed each minute) rather than a stub.
            TimelineView(.everyMinute) { tl in
                Text(tl.date, format: .dateTime.hour().minute())
                    .font(EType.mono(.caption)).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.top, 4)
    }

    private var couplerRing: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("COUPLER RING")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                // No live coupler sensor feed — the diagram below is an
                // instructional reference until the uncouple is
                // confirmed, then it freezes at the real released
                // state. Honest em-dash, never a "LIVE" assertion.
                Text(isUncoupled ? "UNCOUPLED" : fallbackBond)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(isUncoupled ? Brand.success : palette.textTertiary)
            }
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(Color.black.opacity(0.7))
                // Bespoke vector dry-break RELEASE diagram — the 044
                // mate diagram ported in reverse, operationally
                // ordered: the poppet re-seats (flow shimmer dies),
                // the re-seat verifies, THEN the cam lever lifts along
                // the release arc and the coupler backs off the stub.
                // ESD bond renders neutral (no live continuity feed).
                // Freezes released once the uncouple is confirmed;
                // reduce-motion freezes at the safe re-seated state.
                DryBreakReleaseDiagram(esdBonded: false,
                                       isHazmat: ctx.isHazmat,
                                       released: isUncoupled)
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
            Text(ctx.isHazmat ? "Spin off the dry-disconnect coupler" : "Lift trailer off dock plate")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text(ctx.isHazmat
                 ? "Two-handed grip on the ring, counter-clockwise. Pressure-equalize port should be open before the ring leaves the threads."
                 : "Pull dock plate. Verify the dock door has cleared the trailer top before easing off the rubber.")
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
            metric(label: "PRESSURE", value: fallbackPressure, unit: "psi")
            metric(label: "VAPOR",    value: fallbackVapor,    unit: "psig")
            metric(label: "ESD BOND", value: fallbackBond,     unit: "")
        }
    }

    private func metric(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                }
            }
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

    private var ladderCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DISCONNECT LADDER · \(ctx.isHazmat ? "NH3 CLOSED-LOOP" : "RECEIVER")")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                // No per-row completion model on this static ladder (every
                // step is "next" until a real step-progress source lands) —
                // neutral em-dash, never a hardcoded "STEP 1 OF 4" count or
                // a "GO" assertion.
                Text(fallbackBond)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            ForEach(ctx.disconnectLadder) { step in
                HStack(spacing: Space.s3) {
                    Image(systemName: stepIcon(step.state))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(stepColor(step.state))
                    Text(step.title)
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(step.state == "next" ? palette.textSecondary : palette.textPrimary)
                    Spacer()
                    Text(step.timestamp ?? (step.state == "now" ? "NOW" : ""))
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(stepColor(step.state))
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
        }
    }

    private func stepIcon(_ state: String) -> String {
        switch state {
        case "done": return "checkmark.circle.fill"
        case "now":  return "smallcircle.fill.circle.fill"
        default:     return "circle"
        }
    }
    private func stepColor(_ state: String) -> Color {
        switch state {
        case "done": return Brand.success
        case "now":  return Brand.warning
        default:     return palette.textTertiary
        }
    }

    // Honest empty state. There is no live supervisor-mic feed wired to
    // this screen (no dock-side spotter session, no transcript stream),
    // so we render neutral card chrome with a "No supervisor connected"
    // label — never an invented person, avatar, "LIVE MIC", or transcript
    // quote. When a real spotter/supervisor session backend lands, this
    // card surfaces that participant + their live captions.
    private var supervisorMic: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(palette.bgCardSoft).frame(width: 32, height: 32)
                Image(systemName: "person.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("No supervisor connected")
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text(fallbackBond)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
                Text("Supervisor / spotter mic not connected for this disconnect.")
                    .font(EType.body)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            // 100th firing · ledger-hygiene sweep — was no-op. Wires to
            // env-injected `driverShowHelp` with a context-tagged topic
            // ("disconnect-and-verify"). Falls through if env not registered.
            Button { showHelp?("disconnect-and-verify") } label: {
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
            CTAButton(
                title: "Confirm uncoupled",
                action: { Task { await confirmUncoupled() } },
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

    private func confirmUncoupled() async {
        isConfirming = true
        defer { isConfirming = false }
        let keys = ["disconnect_confirmed", "stowed", "released"]
        if let t = lifecycle.availableTransitions.first(where: { t in keys.contains(where: { t.to.lowercased().contains($0) }) })
            ?? lifecycle.availableTransitions.first {
            _ = await lifecycle.execute(t)
        }
        // The driver's confirmation IS the uncouple witness event —
        // freeze the diagram at the real released state from here on.
        uncoupleConfirmed = true
        advance?()
    }
}

// MARK: - DryBreakReleaseDiagram
//
// Bespoke vector illustration of a dry-break (dry-disconnect) coupler
// RELEASING from its fixed stub adapter — the 044 `DryBreakMateDiagram`
// ported in reverse, drawn entirely with SwiftUI Canvas paths (no
// raster, no SF Symbol stand-ins).
//
// Operational truth (per dry-disconnect coupler datasheets — Seal
// Fast / Emco Wheaton / Control Devices DryLink): the coupler CANNOT
// be unlocked while product is moving; the internal poppet must
// re-seat first, sealing both halves, and only then can the cam
// release lever rotate UP to free the body off the adapter. The
// reverse sequence is therefore: (1) flow shimmer DIES as the poppet
// re-seats, (2) a brief verify beat on the sealed collar, (3) the
// lever lifts along the dashed release arc while the coupler backs
// ~2px off the stub. `released: true` (the real confirmed uncouple)
// freezes the scene at the released pose. Reduce-motion freezes at
// the SAFE state — poppet re-seated, flow dead, lever still locked.
//
// Palette: steel/orange/charcoal are physical-equipment colors (not
// brand UI); the pivot dot + release arc reuse Brand.magenta and the
// ESD strap Brand.hazmat/neutral, matching the 044 quality bar.
private struct DryBreakReleaseDiagram: View {
    let esdBonded: Bool
    let isHazmat: Bool
    /// Real uncouple confirmation. False = the instructional release
    /// cycle loops; true = the disconnect is CONFIRMED and the scene
    /// freezes at the released pose — real state, not decoration.
    var released: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Physical-hardware colors (steel, safety-orange, charcoal fitting).
    private let steelHi    = Color(hex: 0xC9CED6)
    private let steelMid   = Color(hex: 0x8C939E)
    private let steelLo    = Color(hex: 0x5A616C)
    private let orangeHi   = Color(hex: 0xFF8A3D)
    private let orangeMid  = Color(hex: 0xF26A1B)
    private let orangeLo   = Color(hex: 0xC44E0E)
    private let charcoal   = Color(hex: 0x342B26)
    private let charcoalHi = Color(hex: 0x4A3E36)

    /// One loop of the release cycle (seconds): drain (flow dies) →
    /// verify beat → lever lift → open dwell → eased reset to seated.
    private let loop: Double = 4.6
    // Phase boundaries within one loop.
    private let drain: Double = 1.1      // poppet re-seats, shimmer dies
    private let verify: Double = 0.5     // sealed-collar verify beat
    private let lift: Double = 0.7       // cam lever rotates up
    private let dwell: Double = 1.3      // released hold

    /// Scene freeze. Released (real state) wins; reduce-motion freezes
    /// at the safe re-seated pose.
    private var frozen: Bool { released || reduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: frozen)) { timeline in
            let clock = timeline.date.timeIntervalSinceReferenceDate
            // seat: 1 = locked/seated, 0 = lever raised / released.
            // flow: residual product shimmer 1 → 0 as the poppet re-seats.
            let pose = frozen ? frozenPose : releasePose(clock)
            Canvas(rendersAsynchronously: false) { ctx, size in
                drawScene(ctx: &ctx, size: size,
                          seat: pose.seat, flow: pose.flow,
                          pulse: frozen ? 0 : verifyPulse(clock),
                          shimmer: frozen ? 0.5 : clock)
            }
            .overlay(alignment: .topLeading) { titlePill }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityCopy)
    }

    /// Frozen pose: released → lever up, off the stub; otherwise the
    /// reduce-motion SAFE pose — sealed, flow dead, still locked.
    private var frozenPose: (seat: Double, flow: Double) {
        released ? (seat: 0, flow: 0) : (seat: 1, flow: 0)
    }

    /// VoiceOver copy for each real state of the release sequence.
    private var accessibilityCopy: String {
        if released {
            return "Dry-break coupler confirmed uncoupled: poppet re-seated, flow stopped, release lever raised off the stub adapter."
        }
        if reduceMotion {
            return "Dry-break coupler sealed and locked with flow stopped — safe to release. Lever lifts to free the coupler."
        }
        return "Dry-break release guide: poppet re-seats and flow dies, then the release lever rotates up to free the coupler from the stub adapter."
    }

    /// Pose for the current clock — the REVERSE of the 044 mate cycle.
    /// drain: seated, flow 1→0 · verify: seated, flow 0 · lift: seat
    /// 1→0 on the cubic-bezier(0.4,0,0.2,1) curve with a small release
    /// overshoot · dwell: open · reset: eased return to the loop start.
    private func releasePose(_ clock: Double) -> (seat: Double, flow: Double) {
        let phase = clock.truncatingRemainder(dividingBy: loop)
        if phase < drain {
            // Poppet re-seats: the residual flow shimmer decays to dead
            // BEFORE anything mechanical moves — 49 CFR-grade order.
            let p = phase / drain
            return (seat: 1, flow: 1 - bezier(p, 0.4, 0.0, 0.2, 1.0))
        } else if phase < drain + verify {
            return (seat: 1, flow: 0)                  // sealed verify beat
        } else if phase < drain + verify + lift {
            // The unlock stroke: lever lifts along the release arc.
            let p = (phase - drain - verify) / lift
            let eased = bezier(p, 0.4, 0.0, 0.2, 1.0)
            // Slight past-zero overshoot reads as the cam popping free.
            let over = 0.04 * sin(min(p * 1.6, 1.0) * .pi)
            return (seat: max(1 - eased - over, -0.05), flow: 0)
        } else if phase < drain + verify + lift + dwell {
            return (seat: 0, flow: 0)                  // released dwell
        } else {
            // Eased reset to the loop start (re-seat + shimmer return) —
            // the loop chrome, mirroring 044's lift-back reset.
            let p = (phase - drain - verify - lift - dwell)
                / (loop - drain - verify - lift - dwell)
            let eased = bezier(p, 0.4, 0.0, 0.2, 1.0)
            return (seat: eased, flow: eased)
        }
    }

    /// Verify-beat intensity (0…1) — a brief sealed glow on the collar
    /// right after the flow dies, confirming the poppet re-seat.
    private func verifyPulse(_ clock: Double) -> Double {
        let phase = clock.truncatingRemainder(dividingBy: loop)
        guard phase >= drain, phase < drain + verify + 0.4 else { return 0 }
        let span = verify + 0.4
        return cos((phase - drain) / span * .pi / 2)   // 1 → 0 decay
    }

    private var titlePill: some View {
        Text("DRY-BREAK RELEASE")
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

    // MARK: Scene draw (shared vocabulary with 044's mate diagram)

    private func drawScene(ctx: inout GraphicsContext, size: CGSize,
                           seat: Double, flow: Double, pulse: Double, shimmer: Double) {
        let w = size.width, h = size.height
        // The coupler backs ~2px OFF the stub as the lever unlocks.
        let push = CGFloat(max(0, min(1, seat))) * 2.0

        drawHazardFloor(ctx: &ctx, w: w, h: h)
        drawHose(ctx: &ctx, w: w, h: h, shimmer: shimmer, flow: flow)
        drawStub(ctx: &ctx, w: w, h: h)
        drawCouplerBody(ctx: &ctx, w: w, h: h, push: push, pulse: pulse)
        drawESDBond(ctx: &ctx, w: w, h: h, shimmer: shimmer)
        drawPivotAndArc(ctx: &ctx, w: w, h: h, shimmer: shimmer)
        drawLever(ctx: &ctx, w: w, h: h, seat: seat)
    }

    /// Cubic-bezier solver (x==t approximation) for short fixed curves.
    private func bezier(_ t: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        let t = max(0, min(1, t))
        let u = 1 - t
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
        var lip = Path()
        lip.move(to: CGPoint(x: 0, y: floorTop))
        lip.addLine(to: CGPoint(x: w, y: floorTop))
        ctx.stroke(lip, with: .color(.black.opacity(0.5)), lineWidth: 1)
    }

    // Thick safety-orange corrugated hose curving off-frame to the right.
    // `flow` (1→0) is the dying residual shimmer — the poppet re-seat
    // read. At 0 the line is visually dead: no travelling band at all.
    private func drawHose(ctx: inout GraphicsContext, w: CGFloat, h: CGFloat, shimmer: Double, flow: Double) {
        let start = CGPoint(x: w * 0.66, y: h * 0.52)
        var spine = Path()
        spine.move(to: start)
        spine.addCurve(to: CGPoint(x: w * 1.02, y: h * 0.40),
                       control1: CGPoint(x: w * 0.84, y: h * 0.55),
                       control2: CGPoint(x: w * 0.96, y: h * 0.30))
        let hoseGrad = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [orangeMid, orangeHi, orangeMid]),
            startPoint: start, endPoint: CGPoint(x: w, y: h * 0.40))
        ctx.stroke(spine, with: .color(orangeLo), style: StrokeStyle(lineWidth: 26, lineCap: .round))
        ctx.stroke(spine, with: hoseGrad, style: StrokeStyle(lineWidth: 22, lineCap: .round))
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
        // Residual-flow shimmer, draining AWAY from the coupler (toward
        // the hose end) and fading with `flow`. Fully dead at flow = 0.
        guard flow > 0.02 else { return }
        let intensity = 0.55 * max(0, min(1, flow))
        let phase = (shimmer.truncatingRemainder(dividingBy: 1.6)) / 1.6
        let head = pointOnCubic(start,
                                CGPoint(x: w * 0.84, y: h * 0.55),
                                CGPoint(x: w * 0.96, y: h * 0.30),
                                CGPoint(x: w * 1.02, y: h * 0.40), CGFloat(phase))
        ctx.fill(Path(ellipseIn: CGRect(x: head.x - 7, y: head.y - 7, width: 14, height: 14)),
                 with: .radialGradient(Gradient(colors: [Color.white.opacity(intensity), .clear]),
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
        let flange = CGRect(x: pipe.maxX - 7, y: midY - 17, width: 9, height: 34)
        let fr = Path(roundedRect: flange, cornerRadius: 3)
        ctx.fill(fr, with: .linearGradient(
            Gradient(colors: [steelMid, steelHi, steelLo]),
            startPoint: CGPoint(x: 0, y: flange.minY), endPoint: CGPoint(x: 0, y: flange.maxY)))
        ctx.stroke(fr, with: .color(.black.opacity(0.4)), lineWidth: 1)
        for fy in [midY - 9, midY + 9] {
            ctx.fill(Path(ellipseIn: CGRect(x: flange.midX - 1.6, y: fy - 1.6, width: 3.2, height: 3.2)),
                     with: .color(steelLo))
        }
    }

    // Stout orange coupler body + charcoal fitting block. `push` slides
    // the body onto the stub while locked; as the lever lifts the body
    // backs off. `pulse` is the sealed-poppet verify glow.
    private func drawCouplerBody(ctx: inout GraphicsContext, w: CGFloat, h: CGFloat, push: CGFloat, pulse: Double) {
        let midY = h * 0.50
        let dx = -push
        let barrel = CGRect(x: w * 0.40 + dx, y: midY - 19, width: w * 0.26, height: 38)
        let br = Path(roundedRect: barrel, cornerRadius: 11)
        ctx.fill(br, with: .linearGradient(
            Gradient(colors: [orangeHi, orangeMid, orangeLo]),
            startPoint: CGPoint(x: 0, y: barrel.minY), endPoint: CGPoint(x: 0, y: barrel.maxY)))
        ctx.stroke(br, with: .color(orangeLo.opacity(0.8)), lineWidth: 1)
        let spec = Path(roundedRect: CGRect(x: barrel.minX + 4, y: barrel.minY + 4,
                                            width: barrel.width - 8, height: 6), cornerRadius: 3)
        ctx.fill(spec, with: .color(.white.opacity(0.28)))
        let collar = CGRect(x: barrel.minX - 3, y: midY - 21, width: 11, height: 42)
        let cr = Path(roundedRect: collar, cornerRadius: 5)
        ctx.fill(cr, with: .linearGradient(
            Gradient(colors: [orangeMid, orangeLo]),
            startPoint: CGPoint(x: 0, y: collar.minY), endPoint: CGPoint(x: 0, y: collar.maxY)))
        ctx.stroke(cr, with: .color(orangeLo), lineWidth: 1)
        let block = CGRect(x: barrel.midX - 13, y: barrel.minY - 15, width: 26, height: 17)
        let blk = Path(roundedRect: block, cornerRadius: 4)
        ctx.fill(blk, with: .linearGradient(
            Gradient(colors: [charcoalHi, charcoal]),
            startPoint: CGPoint(x: 0, y: block.minY), endPoint: CGPoint(x: 0, y: block.maxY)))
        ctx.stroke(blk, with: .color(.black.opacity(0.5)), lineWidth: 1)
        for bx in [block.minX + 7, block.maxX - 7] {
            ctx.fill(Path(ellipseIn: CGRect(x: bx - 2, y: block.midY - 2, width: 4, height: 4)),
                     with: .color(.black.opacity(0.45)))
        }
        // Poppet re-seat VERIFY beat — a cool sealed glow on the collar
        // (deliberately not the warm mate "thunk"): flow is dead and the
        // halves are sealed, the precondition for lifting the lever.
        if pulse > 0.01 {
            let cx = collar.midX, cy = midY
            ctx.fill(Path(ellipseIn: CGRect(x: cx - 16, y: cy - 16, width: 32, height: 32)),
                     with: .radialGradient(
                        Gradient(colors: [steelHi.opacity(0.55 * pulse), .clear]),
                        center: CGPoint(x: cx, y: cy), startRadius: 2, endRadius: 18))
        }
    }

    // Gold ESD bonding strap angling down-left to a small ground clamp.
    // Neutral (grey) when no live continuity proof exists — on 042
    // there is no bond feed, so the strap never asserts "hot".
    private func drawESDBond(ctx: inout GraphicsContext, w: CGFloat, h: CGFloat, shimmer: Double) {
        let live = esdBonded
        let gold = live ? Brand.hazmat : Brand.neutral
        let anchor = CGPoint(x: w * 0.43, y: h * 0.62)
        let clamp  = CGPoint(x: w * 0.20, y: h * 0.78)
        var strap = Path()
        strap.move(to: anchor)
        strap.addQuadCurve(to: clamp, control: CGPoint(x: w * 0.28, y: h * 0.78))
        ctx.stroke(strap, with: .color(gold), style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
        ctx.stroke(strap, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: anchor.x - 3, y: anchor.y - 3, width: 6, height: 6)),
                 with: .color(gold))
        let clampRect = CGRect(x: clamp.x - 6, y: clamp.y - 4, width: 12, height: 8)
        ctx.fill(Path(roundedRect: clampRect, cornerRadius: 2), with: .color(gold))
        ctx.stroke(Path(roundedRect: clampRect, cornerRadius: 2), with: .color(.black.opacity(0.4)), lineWidth: 1)
        if live && !frozen {
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

    // Magenta pivot dot + dashed curved RELEASE arc over the coupler —
    // mirrored from 044: the arrowhead sits at the RAISED end because
    // the lever travels UP along this arc to unlock.
    private func drawPivotAndArc(ctx: inout GraphicsContext, w: CGFloat, h: CGFloat, shimmer: Double) {
        let raisedTip = CGPoint(x: w * 0.585, y: h * 0.14)   // release target
        let seatedTip = CGPoint(x: w * 0.715, y: h * 0.34)   // locked start
        var arc = Path()
        arc.move(to: seatedTip)
        arc.addQuadCurve(to: raisedTip, control: CGPoint(x: w * 0.78, y: h * 0.10))
        // Dash marches TOWARD the raised tip (negative phase = reversed
        // travel vs the mate diagram) so the guide reads "lift".
        let dash = frozen ? StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [4, 3])
                          : StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [4, 3],
                                        dashPhase: -CGFloat(shimmer * 14).truncatingRemainder(dividingBy: 14))
        ctx.stroke(arc, with: .color(Brand.magenta.opacity(0.9)), style: dash)
        // Arrowhead at the RAISED end — release direction.
        var head = Path()
        head.move(to: raisedTip)
        head.addLine(to: CGPoint(x: raisedTip.x + 5.5, y: raisedTip.y + 3.5))
        head.move(to: raisedTip)
        head.addLine(to: CGPoint(x: raisedTip.x - 1.5, y: raisedTip.y + 6.5))
        ctx.stroke(head, with: .color(Brand.magenta), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
    }

    // The orange cam RELEASE LEVER — rotates UP about the magenta pivot
    // to unlock (seated -44° → raised -118°, the exact reverse sweep of
    // the 044 mate). `seat` 1→0 lifts it along the dashed release arc;
    // a slight past-raised overshoot reads as the cam popping free.
    private func drawLever(ctx: inout GraphicsContext, w: CGFloat, h: CGFloat, seat: Double) {
        let pivot = CGPoint(x: w * 0.585, y: h * 0.50)
        let raised = -118.0, seated = -44.0
        let angle = (raised + (seated - raised) * seat) * .pi / 180.0

        var sub = ctx
        sub.translateBy(x: pivot.x, y: pivot.y)
        sub.rotate(by: .radians(angle))

        let armLen: CGFloat = min(w * 0.24, h * 0.42)
        let armW: CGFloat = 11
        let arm = Path(roundedRect: CGRect(x: 2, y: -armW / 2, width: armLen, height: armW),
                       cornerRadius: armW / 2)
        sub.fill(arm, with: .linearGradient(
            Gradient(colors: [orangeHi, orangeMid, orangeLo]),
            startPoint: CGPoint(x: 0, y: -armW / 2), endPoint: CGPoint(x: 0, y: armW / 2)))
        sub.stroke(arm, with: .color(orangeLo.opacity(0.9)), lineWidth: 1)
        let hi = Path(roundedRect: CGRect(x: 5, y: -armW / 2 + 2, width: armLen - 8, height: 2.4),
                      cornerRadius: 1.2)
        sub.fill(hi, with: .color(.white.opacity(0.3)))
        for gx in stride(from: armLen - 4, to: armLen - 18, by: -4) {
            var k = Path()
            k.move(to: CGPoint(x: gx, y: -armW / 2 + 2))
            k.addLine(to: CGPoint(x: gx, y: armW / 2 - 2))
            sub.stroke(k, with: .color(orangeLo.opacity(0.7)), lineWidth: 1)
        }

        let hubR: CGFloat = 8
        ctx.fill(Path(ellipseIn: CGRect(x: pivot.x - hubR, y: pivot.y - hubR, width: hubR * 2, height: hubR * 2)),
                 with: .radialGradient(Gradient(colors: [orangeMid, orangeLo]),
                                       center: pivot, startRadius: 1, endRadius: hubR))
        ctx.stroke(Path(ellipseIn: CGRect(x: pivot.x - hubR, y: pivot.y - hubR, width: hubR * 2, height: hubR * 2)),
                   with: .color(orangeLo), lineWidth: 1)

        // Magenta PIVOT dot — the rotation axis, on top of the hub.
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

struct DisconnectAndVerifyScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            DisconnectAndVerify(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_042(),
                      trailing: driverNavTrailing_042(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_042() -> [NavSlot] {
    RoleNav.driverLeading(current: .trips)
}
private func driverNavTrailing_042() -> [NavSlot] {
    RoleNav.driverTrailing(current: .none)
}

#Preview("042 · Disconnect & Verify · Dark") {
    DisconnectAndVerifyScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("042 · Disconnect & Verify · Light") {
    DisconnectAndVerifyScreen(theme: Theme.light).preferredColorScheme(.light)
}
