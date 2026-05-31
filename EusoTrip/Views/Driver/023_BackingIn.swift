//
//  023_BackingIn.swift
//  EusoTrip — Lifecycle screen 023 · Backing In.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `023 Backing In.png` (Dark + Light). Fires when the driver is
//  actively backing into the assigned door. Live rear IR canvas,
//  three distance tiles (driver-side / center-rear / blind-side),
//  alignment bar, live-mic / spotter advisory card, Pull up & redo
//  / Set brakes CTAs.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct BackingIn: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @StateObject private var uwb = EusoNISession()
    @StateObject private var doorScanner = DoorMarkerScanner()
    @State private var activeLoad: Load?
    // Live appointment row for the active load — carries the
    // server-assigned dock door (`dockNumber`) the guard / terminal
    // pushed. Same `appointments.getByLoad` read the sibling lifecycle
    // screens (022 Dock Assigned, 024 Unloading) hydrate. The door is
    // the ONE non-sensor live datum this screen can surface.
    @State private var appointment: AppointmentsAPI.ByLoadAppointment?
    @State private var isConfirming: Bool = false
    @State private var liveFeedPaused: Bool = false
    @State private var terminalCaps: CapabilitiesAPI.TerminalCapabilities? = nil
    @State private var arkitFallbackActive: Bool = false

    enum Register { case night, afternoon }
    let register: Register

    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Empty-state sentinels + live-derived fields
    //
    // FOUNDER BAR: 0 fabricated business data. The back-in alignment
    // numbers (driver-side / center-rear / blind-side inches, the
    // alignment degrees, the IR-camera timestamp) have NO live source
    // unless a UWB anchor or an ARKit door marker is paired for this
    // door — that hardware is the only thing on this screen that can
    // measure a real distance. When no sensor is active every
    // measurement collapses to the honest em-dash sentinel and the
    // tiles read "no sensor". They are NEVER rendered as fabricated
    // inches/degrees. The live overlay path (uwbCenterlineCard /
    // arkitMarkerCard) is unchanged — it renders the real numbers when
    // the hardware is present. Pattern mirrors sibling 022/024/039.
    private let dash = "—"

    /// Server-assigned dock door, trimmed. Empty when not yet assigned.
    private var liveDock: String {
        (appointment?.dockNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var hasDock: Bool { !liveDock.isEmpty }
    /// Door label used across the header / camera overlay / sensor
    /// cards. Live dock number when assigned, em-dash otherwise.
    private var doorLabel: String { hasDock ? liveDock : dash }

    /// True when a real alignment sensor is actively measuring — either
    /// the UWB anchor is ranging or the ARKit door-marker fallback is
    /// tracking. Gates whether the measurement readouts may show
    /// numbers at all.
    private var sensorActive: Bool { uwbActive || arkitFallbackActive }

    /// True when the active terminal has declared a partner camera feed
    /// for this dock door. There is no WebRTC player wired into this
    /// screen yet, so even when `true` we don't claim a LIVE stream —
    /// but when `false` we positively label the canvas "NO FEED" rather
    /// than implying a live IR feed exists.
    private var hasCameraFeed: Bool {
        guard hasDock, let caps = terminalCaps else { return false }
        return caps.hasCameraFeed(doorNumber: liveDock)
    }

    /// Aisle / receiving line. No discrete aisle column exists on
    /// `loads.getById` / `appointments.getByLoad` (same backend gap 022
    /// documents) — derive an honest "Door N · receiving" when a dock is
    /// assigned, else an awaiting-assignment line. Never a fabricated
    /// "Aisle 2" literal.
    private var aisleLine: String {
        hasDock ? "Door \(liveDock) · receiving" : "Awaiting dock assignment"
    }
    /// Trailer id isn't first-class on the live projection yet —
    /// em-dash sentinel.
    private var trailerLine: String { dash }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                cameraCanvas
                if uwbActive { uwbCenterlineCard }
                if arkitFallbackActive { arkitMarkerCard }
                distanceTiles
                alignmentCard
                advisoryCard
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .onChange(of: uwb.lostLineOfSight) { _, lost in
            // ARKit fallback fires automatically when UWB loses LOS
            // AND the active terminal has a door marker registered
            // for the current door. Stops when UWB recovers.
            if lost && hasDoorMarker {
                doorScanner.start(markers: terminalCaps?.doorMarkers ?? [])
                arkitFallbackActive = true
            } else if !lost && arkitFallbackActive {
                doorScanner.stop()
                arkitFallbackActive = false
            }
        }
        .onDisappear {
            uwb.stop()
            doorScanner.stop()
        }
        .screenTileRoot()
    }

    // MARK: ARKit door-marker overlay

    /// True when the active terminal has registered a door marker
    /// for this dock door — gates whether the ARKit fallback can
    /// activate at all.
    private var hasDoorMarker: Bool {
        guard hasDock else { return false }
        return terminalCaps?.doorMarkers.contains { $0.doorNumber == liveDock } ?? false
    }

    /// Card that fires only when UWB has lost LOS and a door marker
    /// exists. Embeds the ARKit camera preview with marker tracking
    /// + a centerline drift readout. Positions itself directly under
    /// the UWB card so the driver sees the handoff: UWB → AR fallback.
    private var arkitMarkerCard: some View {
        VStack(spacing: 8) {
            DoorMarkerScannerView(scanner: doorScanner)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                        .frame(width: 36, height: 36)
                    Image(systemName: "viewfinder")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(arkitOffsetText)
                        .font(EType.body.weight(.heavy))
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                    Text("AR FALLBACK · DOOR \(doorLabel)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var arkitOffsetText: String {
        if let cm = doorScanner.lateralOffsetCm {
            let side = cm > 0 ? "LEFT" : (cm < 0 ? "RIGHT" : "CENTER")
            return "\(abs(cm)) cm \(side)"
        }
        if doorScanner.recognisedDoor != nil { return "Tracking…" }
        return "Point camera at door marker"
    }

    // MARK: UWB centerline drift card
    //
    // Renders only when a UWB anchor is paired for this dock door —
    // otherwise we trust the visual / static distance tiles below.
    // The card converts the NI direction unit vector (phone-frame
    // x/z plane) into a left/right drift number relative to the
    // dock-anchor centerline. When LOS is lost the card flips into a
    // muted "Lost line-of-sight · rotate phone" advisory.

    private var uwbActive: Bool {
        if case .ranging = uwb.status { return true }
        return false
    }

    private var uwbCenterlineCard: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .strokeBorder(
                        uwb.lostLineOfSight ? palette.borderFaint
                                            : Brand.success.opacity(0.7),
                        lineWidth: 1.5
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: "scope")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(
                        uwb.lostLineOfSight ? AnyShapeStyle(palette.textTertiary)
                                            : AnyShapeStyle(LinearGradient.diagonal)
                    )
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(uwbCenterlineText)
                    .font(EType.body.weight(.heavy))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                Text(uwbCenterlineSub)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Distance + drift line. `direction.x` is the lateral component
    /// in the phone's frame; positive == anchor is to the right of
    /// the phone (driver drifting LEFT of the centerline). We render
    /// a sign-flipped drift cm value so the message reads from the
    /// driver's perspective.
    private var uwbCenterlineText: String {
        guard !uwb.lostLineOfSight else { return "—" }
        guard let dist = uwb.distance else { return "Locating…" }
        if let dir = uwb.direction {
            let lateralCm = Int((dir.x * dist) * 100)
            let side = lateralCm > 0 ? "RIGHT" : (lateralCm < 0 ? "LEFT" : "CENTER")
            return String(format: "%.1f m · %d cm %@", dist, abs(lateralCm), side)
        }
        return String(format: "%.1f m", dist)
    }

    private var uwbCenterlineSub: String {
        if uwb.lostLineOfSight { return "LOST LINE-OF-SIGHT · ROTATE PHONE" }
        return "UWB CENTERLINE · DOOR \(doorLabel)"
    }

    // MARK: Header

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
                    Text("BACKING IN")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("· DOOR \(doorLabel)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textSecondary)
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
                Text("\(ctx.defaultApproach) · \(aisleLine)")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(trailerLine)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button { liveFeedPaused.toggle() } label: {
                Image(systemName: liveFeedPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
            }
            .accessibilityLabel(liveFeedPaused ? "Resume live feed" : "Pause live feed")
        }
        .padding(.top, 4)
    }

    // MARK: Camera canvas

    /// "LIVE"/"PAUSED" only when a partner feed is declared; otherwise
    /// the honest "NO FEED" badge.
    private var feedStatusText: String {
        guard hasCameraFeed else { return "NO FEED" }
        return liveFeedPaused ? "PAUSED" : "LIVE"
    }
    private var feedDotColor: Color {
        guard hasCameraFeed else { return .white.opacity(0.55) }
        return liveFeedPaused ? .white.opacity(0.7) : Brand.danger
    }

    private var cameraCanvas: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Color.black)
                .frame(height: 220)

            // IR-grey horizon
            GeometryReader { geo in
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#2C2F36"), Color(hex: "#121419")],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(height: geo.size.height * 0.55)
                    .offset(y: 18)
                // Dock outline (stylized)
                Rectangle()
                    .stroke(Color.white.opacity(0.35), lineWidth: 1.2)
                    .frame(width: geo.size.width * 0.45, height: geo.size.height * 0.32)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.50)
                // Target line
                Rectangle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: geo.size.width * 0.45, height: 3)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.66)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            // Top overlay — feed status + door.
            //
            // There is no WebRTC player wired into this screen, so the
            // guide rectangle below is a drawn alignment frame, NOT a
            // camera image. We only badge "LIVE" when a partner camera
            // feed is actually declared for this door; otherwise we
            // label the canvas honestly as "NO FEED" so the driver is
            // never told a fabricated IR stream is live.
            HStack {
                HStack(spacing: 4) {
                    Circle()
                        .fill(feedDotColor)
                        .frame(width: 6, height: 6)
                    Text(feedStatusText)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(feedDotColor)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                Text("DOOR \(doorLabel)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text(hasCameraFeed ? "REAR · IR" : "ALIGNMENT GUIDE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, Space.s3)
            .padding(.top, Space.s2)

            // Bottom overlay — only carries a timestamp/cam id when a
            // real feed is declared. With no live feed there is no
            // honest stamp to show, so the strip collapses rather than
            // print a fabricated "00:32:48 · cam-R" pair.
            if hasCameraFeed {
                VStack {
                    Spacer()
                    HStack {
                        Text(liveFeedPaused ? "PAUSED" : "STREAMING")
                            .font(EType.mono(.micro)).tracking(0.4)
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Text("DOOR \(doorLabel)")
                            .font(EType.mono(.micro)).tracking(0.4)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(.horizontal, Space.s3)
                    .padding(.bottom, Space.s2)
                }
            } else {
                VStack {
                    Spacer()
                    Text("No partner camera at this door — drawn alignment guide only")
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, Space.s3)
                        .padding(.bottom, Space.s2)
                }
            }
        }
        .frame(height: 220)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: Distance tiles — live wiring
    //
    // Per-corner clearance (driver-side / blind-side inches) has NO live
    // source: a UWB anchor reports a single centerline range, not three
    // corner distances, and there's no per-corner LiDAR feed wired here.
    // So those two tiles always render the em-dash sentinel. The CENTER
    // REAR tile maps to the one real datum we do have — the UWB
    // centerline distance — when the UWB session is ranging with LOS;
    // otherwise it too is "—". No fabricated inches, ever.

    /// Center-rear distance derived from the live UWB range, rendered in
    /// feet+inches. Em-dash when no UWB range is available.
    private var centerRearValue: String {
        guard uwbActive, !uwb.lostLineOfSight, let m = uwb.distance else { return dash }
        let totalInches = Int((Double(m) * 39.3701).rounded())
        if totalInches < 12 { return "\(totalInches)\"" }
        return "\(totalInches / 12)' \(totalInches % 12)\""
    }
    private var centerRearSub: String {
        (uwbActive && !uwb.lostLineOfSight && uwb.distance != nil) ? "to dock rubber" : "no sensor"
    }

    private var distanceTiles: some View {
        HStack(spacing: Space.s2) {
            distanceTile(label: "DRIVER-SIDE",
                         value: dash,
                         sub: sensorActive ? "no per-corner sensor" : "no sensor",
                         color: palette.textTertiary)
            distanceTile(label: "CENTER REAR",
                         value: centerRearValue,
                         sub: centerRearSub,
                         color: centerRearValue == dash ? palette.textTertiary : palette.textPrimary)
            distanceTile(label: "BLIND-SIDE",
                         value: dash,
                         sub: sensorActive ? "no per-corner sensor" : "no sensor",
                         color: palette.textTertiary)
        }
    }

    private func distanceTile(label: String, value: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(sub)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Alignment card

    /// Lateral drift fraction across the alignment bar, 0...1, where
    /// 0.5 is dead-center. Derived from the live UWB direction unit
    /// vector when the session is ranging with LOS; clamps to a sane
    /// span so the marker never leaves the track. `nil` when there's no
    /// live alignment sensor — the marker then parks dead-center and the
    /// degree readout renders the em-dash sentinel.
    private var alignmentFraction: CGFloat? {
        guard uwbActive, !uwb.lostLineOfSight,
              let dist = uwb.distance, let dir = uwb.direction else { return nil }
        let lateralM = Double(dir.x) * Double(dist)
        // Map roughly ±0.5 m of drift onto the full ±0.4 of the bar.
        let frac = 0.5 + max(-0.4, min(0.4, lateralM / 1.0))
        return CGFloat(frac)
    }
    private var alignmentReadout: String {
        guard let f = alignmentFraction else { return dash }
        let cm = Int(((Double(f) - 0.5) * 100).rounded())
        if cm == 0 { return "centered" }
        return "\(abs(cm)) cm \(cm > 0 ? "right" : "left")"
    }
    private var alignmentReadoutColor: Color {
        alignmentFraction == nil ? palette.textTertiary : Brand.warning
    }

    private var alignmentCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("ALIGNMENT")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(alignmentReadout)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(alignmentReadoutColor)
            }
            GeometryReader { geo in
                ZStack {
                    Capsule()
                        .fill(palette.bgCardSoft)
                        .frame(height: 6)
                    // Center tick
                    Rectangle()
                        .fill(palette.borderFaint)
                        .frame(width: 1, height: 14)
                        .position(x: geo.size.width / 2, y: 10)
                    // Alignment marker — live UWB-derived drift when a
                    // sensor is ranging, dead-center (neutral) otherwise.
                    Circle()
                        .fill(alignmentFraction == nil
                              ? AnyShapeStyle(palette.borderSoft)
                              : AnyShapeStyle(LinearGradient.diagonal))
                        .frame(width: 12, height: 12)
                        .position(x: geo.size.width * (alignmentFraction ?? 0.5), y: 10)
                }
            }
            .frame(height: 20)
            HStack {
                Text("-5°")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("0°")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("+5°")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Advisory

    /// Advisory copy is general back-in guidance — but it must NOT quote
    /// a specific clearance number unless a sensor is actually measuring
    /// one. With no sensor we give the honest "no live distance / use
    /// mirrors + GOAL" advisory instead of a fabricated inch count.
    private var advisoryText: String {
        guard sensorActive else {
            return "No alignment sensor paired at this door — no live clearance reading. Use your mirrors, get out and look, and re-pull if you aren't square. No spotter overnight."
        }
        return "Counter-steer and hold it. Straighten before you close the last foot. Watch the live centerline above. No spotter overnight — re-pull if you aren't square."
    }

    private var advisoryCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 32, height: 32)
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(advisoryText)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
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

    // MARK: Footer CTAs

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            Button { navBack?() } label: {
                Text("Pull up & redo")
                    .font(EType.body.weight(.semibold))
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
                title: "Set brakes",
                action: { Task { await setBrakes() } },
                isLoading: isConfirming
            )
        }
    }

    // MARK: Hydration + actions

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
        // Live dock door — the one non-sensor datum this screen surfaces.
        // Same `appointments.getByLoad` read 022/024 hydrate.
        appointment = try? await EusoTripAPI.shared.appointments
            .getByLoad(loadId: lifecycle.loadId)
        terminalCaps = try? await EusoTripAPI.shared.capabilities
            .getTerminal(terminalId: 0)
        startUwbIfPaired()
    }

    /// Start the UWB session against the registered anchor for the
    /// active dock door. Caller is responsible for stopping the
    /// session on screen disappear (handled below via `.onDisappear`).
    private func startUwbIfPaired() {
        guard hasDock else { return }
        guard let anchor = terminalCaps?.uwbAnchors
            .first(where: { $0.doorNumber == liveDock }) else { return }
        guard let data = Data(base64Encoded: anchor.accessoryConfigData) else { return }
        let bt = anchor.bluetoothPeerIdentifier.flatMap { UUID(uuidString: $0) }
        uwb.startAccessory(configData: data, btIdentifier: bt)
    }

    private func setBrakes() async {
        isConfirming = true
        defer { isConfirming = false }
        let forwardKeys = ["unloading", "discharge", "dockset"]
        let candidate = lifecycle.availableTransitions.first { t in
            let to = t.to.lowercased()
            return forwardKeys.contains(where: { to.contains($0) })
        } ?? lifecycle.availableTransitions.first
        if let transition = candidate {
            _ = await lifecycle.execute(transition)
        }
        advance?()
    }
}

struct BackingInScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            BackingIn(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_023(),
                      trailing: driverNavTrailing_023(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_023() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_023() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person", isCurrent: false)]
}

#Preview("023 · Backing In · Dark") {
    BackingInScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("023 · Backing In · Light") {
    BackingInScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}

// MARK: - ARKit door-marker scanner
//
// Visual fiducial fallback for the back-in alignment overlay. When
// the UWB anchor loses line-of-sight (steel trailers / yard clutter
// blocking the radio), the driver rotates the phone toward the dock
// door and the rear camera reads the printed AprilTag / QR marker
// epoxied above the bay. ARKit's `ARImageTrackingConfiguration`
// resolves the marker's id + 6-DOF pose, we look up the registered
// `DoorMarker { offsetX, offsetY }` for that id, and paint the
// trailer centerline as a 3D plane on top of the camera feed.
//
// Lifecycle: foreground only (ARKit constraint). Caller owns the
// AR session; the SwiftUI view starts on appear, stops on disappear.
//
// Capability gating: only renders when the active terminal's caps
// include a `doorMarker` for the active door. Otherwise the host
// surface routes to the existing distance-tile fallback.

import ARKit

@MainActor
final class DoorMarkerScanner: NSObject, ObservableObject, ARSessionDelegate {
    /// Published recognised marker payload + 6-DOF pose. The host
    /// SwiftUI view binds these into a centerline overlay.
    @Published var recognisedDoor: String? = nil
    @Published var lateralOffsetCm: Int? = nil
    @Published var status: Status = .idle

    enum Status: Equatable {
        case idle
        case unsupported
        case scanning
        case authDenied
        case failed(String)
    }

    private let session = ARSession()
    /// Door markers known for the active terminal — passed in from
    /// the host view's hydrated capability envelope. Each marker is
    /// a printed AprilTag/QR with a server-registered id + offset.
    private var registry: [CapabilitiesAPI.DoorMarker] = []

    static var isSupported: Bool {
        ARImageTrackingConfiguration.isSupported
    }

    override init() {
        super.init()
        session.delegate = self
    }

    /// Start the AR session with the registered door markers as
    /// `ARReferenceImage`s. Each marker becomes a tracked target;
    /// the framework reports a 6-DOF transform on every camera
    /// frame that contains one.
    func start(markers: [CapabilitiesAPI.DoorMarker]) {
        guard Self.isSupported else {
            status = .unsupported
            return
        }
        self.registry = markers
        // Each printed marker is published to a CDN as a reference
        // image — the markerId on the capability envelope maps to
        // the asset name. The terminal admin uploads + registers
        // markers from the Hardware Capabilities self-declaration
        // form (built in commit #5 of this wave). For now we
        // attempt to fetch each marker from the asset catalog by
        // markerId; if missing, that marker is silently skipped.
        var refs = Set<ARReferenceImage>()
        for m in markers {
            if let img = UIImage(named: m.markerId)?.cgImage {
                let ref = ARReferenceImage(
                    img,
                    orientation: .up,
                    physicalWidth: 0.30 // 30cm printed marker — admin uploads at this size
                )
                ref.name = m.markerId
                refs.insert(ref)
            }
        }
        let cfg = ARImageTrackingConfiguration()
        cfg.trackingImages = refs
        cfg.maximumNumberOfTrackedImages = max(1, refs.count)
        session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
        status = .scanning
    }

    func stop() {
        session.pause()
        recognisedDoor = nil
        lateralOffsetCm = nil
        status = .idle
    }

    /// Internal: the underlying ARSession. Exposed so the SwiftUI
    /// `ARSCNViewRepresentable` host can bind the session directly
    /// without the scanner going through an ObservableObject hop
    /// for every camera frame (which would thrash the main actor).
    var arSession: ARSession { session }

    // MARK: ARSessionDelegate

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        // Build a snapshot on the AR delegate queue with no main-
        // actor reads. The actor hop happens inside the Task below
        // where we resolve the registered offset + publish state.
        var samples: [(name: String, lateralCm: Int)] = []
        for anchor in anchors {
            guard let img = anchor as? ARImageAnchor,
                  let name = img.referenceImage.name else { continue }
            // The transform's translation is the marker's pose in
            // the camera-frame. `m.columns.3.x` is the lateral
            // offset (m), positive == marker is to the right of
            // the camera optical axis. We sign-flip so positive
            // values mean the trailer is drifting LEFT of the
            // marker (driver's perspective).
            let m = img.transform
            let lateralM = -m.columns.3.x
            samples.append((name: name, lateralCm: Int(lateralM * 100)))
        }
        guard !samples.isEmpty else { return }
        Task { @MainActor in
            for s in samples {
                self.recognisedDoor = s.name
                if let marker = self.registry.first(where: { $0.markerId == s.name }) {
                    self.lateralOffsetCm = s.lateralCm + Int(marker.offsetX * 100)
                } else {
                    self.lateralOffsetCm = s.lateralCm
                }
            }
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.status = .failed(error.localizedDescription)
        }
    }
}

/// Live AR camera preview with marker tracking. Wraps `ARSCNView` so
/// we get the system's camera feed for free; the marker overlay is
/// rendered separately on top via SwiftUI primitives so the visual
/// design stays under our control.
import SceneKit

struct DoorMarkerScannerView: UIViewRepresentable {
    let scanner: DoorMarkerScanner

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = scanner.arSession
        view.automaticallyUpdatesLighting = true
        view.scene = SCNScene()
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
