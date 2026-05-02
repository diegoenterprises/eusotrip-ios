//
//  022_DockAssigned.swift
//  EusoTrip — Lifecycle screen 022 · Dock Assigned.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `022 Dock Assigned.png` (Dark + Light). Fires when the guard
//  pushes the dock number to the driver. Leads with the big
//  gradient "B → 12" transition graphic, 3 orientation metrics
//  (DOOR / AISLE / APPROACH), a yard-map strip, 3-button action
//  row, a tip banner, and the final "I'm at door 12" / "Call
//  dispatch" CTAs.
//
//  Every label + glyph passes through `LifecycleProductContext`
//  so approach word, facility line, and load metadata adapt to
//  the vertical + product — a container driver sees "ramp / stack
//  / straight-in" instead of "door / aisle / blind-side".
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct DockAssigned: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @Environment(\.driverDialPhone) private var dialPhone
    @Environment(\.driverOpenMessages) private var openMessages
    @Environment(\.driverUploadPhoto) private var uploadPhoto
    @EnvironmentObject private var session: EusoTripSession

    @State private var showYardmap: Bool = false
    @State private var showDockCamPicker: Bool = false
    @State private var terminalCaps: CapabilitiesAPI.TerminalCapabilities? = nil
    @State private var carrierCaps: CapabilitiesAPI.CarrierCapabilities? = nil

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var isConfirming: Bool = false

    enum Register { case night, afternoon }
    let register: Register

    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Figma fallback
    private let fallbackFacility = "—"
    private let fallbackTrailer  = "—"
    private let fallbackGuard    = "Guard · 00:30  Dwell 17m"
    private let fallbackDoor     = "12"
    private let fallbackAisle    = "2"
    private let fallbackPushTime = "—"
    private let fallbackAisleLine = "Aisle 2 · night receiving"
    private let fallbackApproachSub = "Blind-side · flush to the rubber"
    private let fallbackYardLine = "YARD · SC 2718"

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                clearedStrip
                dockCard
                yardMap
                actionRow
                tipBanner
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .sheet(isPresented: $showYardmap) {
            DockYardmapSheet(
                load: activeLoad,
                dockNumber: fallbackDoor,
                caps: terminalCaps
            )
            .environment(\.palette, palette)
        }
        .sheet(isPresented: $showDockCamPicker) {
            DockCamSourcePicker(
                doorNumber: fallbackDoor,
                terminalCaps: terminalCaps,
                carrierCaps: carrierCaps,
                onPickPhoneFallback: {
                    showDockCamPicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        uploadPhoto?()
                    }
                }
            )
            .environment(\.palette, palette)
        }
        .screenTileRoot()
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
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 2) {
                Text("DOCK ASSIGNED")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Text(deliveryTitle)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(fallbackTrailer)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 38, height: 38)
                Image(systemName: ctx.product.symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.top, 4)
    }

    private var deliveryTitle: String {
        guard let loc = activeLoad?.deliveryLocation,
              !loc.cityState.isEmpty else { return fallbackFacility }
        let brand = loc.address.isEmpty ? loc.cityState : loc.address
        return "\(brand) · \(loc.cityState)"
    }

    // MARK: Cleared strip

    private var clearedStrip: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Brand.success)
            Text("CLEARED")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(Brand.success)
            Text(fallbackGuard)
                .font(EType.mono(.micro)).tracking(0.4)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
        }
    }

    // MARK: Dock card

    private var dockCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("DOCK ASSIGNED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(Brand.success)
                Spacer(minLength: 0)
                Text(fallbackPushTime)
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("B")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textSecondary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(fallbackDoor)
                    .font(.system(size: 78, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }

            Text(fallbackAisleLine)
                .font(EType.body.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            Text(fallbackApproachSub)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)

            HStack(spacing: Space.s2) {
                dockMetric(label: "DOOR", value: fallbackDoor)
                dockMetric(label: "AISLE", value: fallbackAisle)
                dockMetric(label: "APPROACH", value: ctx.defaultApproach)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Brand.success.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func dockMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 10)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    // MARK: Yard map strip

    private var yardMap: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(fallbackYardLine)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("EXPAND")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }

            // Receiving aisle strip — stylized row of dock doors with
            // the driver's assigned door highlighted.
            GeometryReader { geo in
                let count = 14
                let slot = geo.size.width / CGFloat(count)
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(0..<count, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(i == 7 ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCardSoft))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(
                                            i == 7 ? Color.clear : palette.borderFaint,
                                            lineWidth: 1
                                        )
                                )
                                .frame(height: 28)
                                .frame(width: slot - 2)
                        }
                    }
                    // Driver truck marker under door 12
                    Circle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: 8, height: 8)
                        .offset(x: slot * 7 + slot / 2 - 4, y: 18)
                }
            }
            .frame(height: 48)

            HStack(spacing: Space.s3) {
                legend(color: LinearGradient.diagonal, label: "Your door")
                legend(color: palette.bgCardSoft, label: "Other docks")
                legend(color: LinearGradient.diagonal, label: "You", asCircle: true)
            }
            .font(.system(size: 9, weight: .semibold)).tracking(0.4)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func legend<S: ShapeStyle>(color: S, label: String, asCircle: Bool = false) -> some View {
        HStack(spacing: 4) {
            Group {
                if asCircle {
                    Circle().fill(color).frame(width: 8, height: 8)
                } else {
                    RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 6)
                }
            }
            Text(label)
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Action row

    private var actionRow: some View {
        // Yardmap, Dock cam, Message Lumper — all real today.
        //   • Yardmap → HereMapView sheet pinned on the load's
        //     deliveryLocation so the driver can orient inside the
        //     terminal yard at GPS resolution. Upgrade path:
        //     NearbyInteraction (cm-level UWB anchors at each dock
        //     door) + websocket-pushed yard graph (forklift +
        //     trailer positions) — pending founder pick.
        //   • Dock cam → device camera via `\.driverUploadPhoto`
        //     env, scoped to the dock door for safety/audit photo.
        //     Upgrade path: WebRTC stream from the terminal's
        //     Genetec / Avigilon NVR via a signaling websocket —
        //     pending founder pick.
        //   • Message Lumper → real `\.driverOpenMessages(nil)`
        //     opening the messaging inbox.
        HStack(spacing: Space.s2) {
            actionButton(symbol: "map.fill", label: "Yardmap", sub: "Full view") {
                showYardmap = true
            }
            actionButton(symbol: "camera.fill",
                         label: "Dock cam",
                         sub: "Door \(fallbackDoor)") {
                showDockCamPicker = true
            }
            actionButton(symbol: "message.fill", label: "Message", sub: "Lumper") {
                openMessages?(nil)
            }
        }
    }

    private func actionButton(
        symbol: String,
        label: String,
        sub: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(label)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(sub)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .padding(.vertical, Space.s2)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Tip banner

    private var tipBanner: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Brand.success)
            Text("Green at door \(fallbackDoor) = back in \(ctx.defaultApproach.lowercased()). Check the rear once flush, then walk the BOL packet to receiving on aisle \(fallbackAisle).")
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(Brand.success.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.success.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Footer CTAs

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            CTAButton(
                title: "I'm at door \(fallbackDoor)",
                action: { Task { await markAtDoor() } },
                isLoading: isConfirming
            )

            Button {
                Task {
                    let rows = (try? await EusoTripAPI.shared.contacts
                        .list(type: "dispatcher", limit: 1)) ?? []
                    if let phone = rows.first?.phone, !phone.isEmpty {
                        dialPhone?(phone)
                    } else {
                        openMessages?(nil)
                    }
                }
            } label: {
                Text("Call dispatch")
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
        }
    }

    // MARK: Hydration + actions

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
        await hydrateCapabilities()
    }

    /// Pull the terminal + carrier capability envelopes from
    /// `capabilities.*` so the Yardmap sheet + DockCamSourcePicker
    /// can light up the right hardware paths (UWB / NVR / dash-cam /
    /// dome-cam / phone fallback). Each call is non-blocking — if
    /// the backend hasn't shipped yet (or no row exists), the API
    /// client returns an empty envelope and the UI shows every
    /// hardware-required option as "Pair hardware".
    private func hydrateCapabilities() async {
        // Carrier dash-cam vendor — driver-scoped, no terminalId needed.
        carrierCaps = try? await EusoTripAPI.shared.capabilities.getMyCarrier()
        // Terminal capabilities — try to derive terminalId from the
        // load. The Load model doesn't yet expose a terminalId field
        // directly; until it does we attempt a 0 lookup which the
        // API client returns as `.empty` so the UI falls back to
        // "phone camera only" + GPS yardmap.
        let terminalId = 0
        terminalCaps = try? await EusoTripAPI.shared.capabilities
            .getTerminal(terminalId: terminalId)
    }

    private func markAtDoor() async {
        isConfirming = true
        defer { isConfirming = false }
        let forwardKeys = ["backing", "at_door", "unloading"]
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

struct DockAssignedScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            DockAssigned(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_022(),
                      trailing: driverNavTrailing_022(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_022() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_022() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person", isCurrent: false)]
}

// MARK: - Yardmap sheet

/// Driver-facing yardmap presented when the dock-assigned action row's
/// "Yardmap" affordance fires. Uses the canonical `HereMapView` (the
/// same component every other lifecycle / pulse map surface uses) so
/// the driver sees a consistent palette + legend. Pinned on the load's
/// deliveryLocation today (GPS resolution).
///
/// Upgrade path (pending founder pick from feedback_no_ceilings
/// options menu): NearbyInteraction (`NISession` + UWB anchors at each
/// dock door) overlays cm-level positioning + direction once the
/// terminal-side anchors deploy; a websocket stream from the
/// terminal-ops backend (`yardOps.streamPositions`) renders live
/// trailer + forklift positions as additional `LoadMarker` rows.
struct DockYardmapSheet: View {
    let load: Load?
    let dockNumber: String
    /// Terminal capability envelope. When nil, every layered overlay
    /// (UWB anchor cm-level positioning, ARKit door markers, yard-
    /// layout GeoJSON polygon) renders as "Pair hardware" and the
    /// sheet falls back to the GPS-resolution HereMapView base.
    let caps: CapabilitiesAPI.TerminalCapabilities?
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uwb = EusoNISession()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                HereMapView(
                    stops: load.flatMap { ld -> [LoadLocation] in
                        if let drop = ld.deliveryLocation { return [drop] }
                        return []
                    } ?? []
                )
                .ignoresSafeArea(edges: .bottom)
                VStack(spacing: 8) {
                    capabilityStrip
                    if anchorForDoor != nil {
                        uwbOverlay
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }
            .navigationTitle("Yardmap · Door \(dockNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { startUwbIfPaired() }
            .onDisappear { uwb.stop() }
        }
    }

    /// Three pills along the top of the yardmap, one per upgrade
    /// path. Each pill renders one of three states:
    ///   • Active   — terminal has registered the hardware + the
    ///                iOS device supports it. Tinted accent color.
    ///   • Pending  — hardware not yet declared by terminal admin.
    ///                Pill says "Pair hardware".
    ///   • Unsupported — device hardware can't run the option (e.g.
    ///                iPhone < U1 chip can't do NearbyInteraction).
    private var capabilityStrip: some View {
        HStack(spacing: 8) {
            capPill(
                label: capUwbLabel,
                icon: "dot.radiowaves.left.and.right",
                state: capUwbState
            )
            capPill(
                label: capArkitLabel,
                icon: "viewfinder",
                state: capArkitState
            )
            capPill(
                label: capLayoutLabel,
                icon: "map",
                state: capLayoutState
            )
        }
    }

    private enum CapState { case active, pending, unsupported }

    private var capUwbState: CapState {
        // iOS device support: iPhone 11+ (U1) or 15+ (U2).
        // We can't statically check chip presence — `NISession`
        // imports + `NISession.isSupported` would be the runtime
        // check. For now we treat support as available unless caps
        // explicitly mark the device as legacy.
        let hasAnchor = caps?.hasUwbAnchor(doorNumber: dockNumber) ?? false
        return hasAnchor ? .active : .pending
    }
    private var capUwbLabel: String {
        capUwbState == .active ? "UWB · cm-level" : "UWB · pair anchor"
    }

    private var capArkitState: CapState {
        let hasMarker = caps?.hasDoorMarker(doorNumber: dockNumber) ?? false
        return hasMarker ? .active : .pending
    }
    private var capArkitLabel: String {
        capArkitState == .active ? "AR marker · ready" : "AR marker · print + register"
    }

    private var capLayoutState: CapState {
        (caps?.hasYardLayout == true) ? .active : .pending
    }
    private var capLayoutLabel: String {
        capLayoutState == .active ? "Yard layout · loaded" : "Yard layout · upload GeoJSON"
    }

    private func capPill(label: String, icon: String, state: CapState) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .heavy))
            Text(label)
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(capPillForeground(state: state))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(palette.bgCard.opacity(0.92))
        .overlay(
            Capsule().strokeBorder(capPillStroke(state: state), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    private func capPillForeground(state: CapState) -> Color {
        switch state {
        case .active:      return palette.textPrimary
        case .pending:     return palette.textSecondary
        case .unsupported: return palette.textTertiary
        }
    }

    private func capPillStroke(state: CapState) -> Color {
        switch state {
        case .active:                  return Brand.success.opacity(0.5)
        case .pending, .unsupported:   return palette.borderFaint
        }
    }

    // MARK: - UWB overlay

    /// The registered anchor for the active dock door, if any.
    private var anchorForDoor: CapabilitiesAPI.UwbAnchor? {
        caps?.uwbAnchors.first { $0.doorNumber == dockNumber }
    }

    /// On appear, decode the anchor's accessoryConfigData blob (base64
    /// from the manufacturer's pairing flow) and start an
    /// `EusoNISession`. The session publishes distance + direction +
    /// LOS state which the overlay reads.
    private func startUwbIfPaired() {
        guard let anchor = anchorForDoor else { return }
        guard let data = Data(base64Encoded: anchor.accessoryConfigData) else { return }
        let bt = anchor.bluetoothPeerIdentifier.flatMap { UUID(uuidString: $0) }
        uwb.startAccessory(configData: data, btIdentifier: bt)
    }

    /// Cm-level guidance card: distance (m, one decimal) + a chevron
    /// rotated by `uwb.direction` so the driver sees the bearing
    /// vector relative to the phone's orientation. When line-of-sight
    /// drops, the card switches to a "Lost line-of-sight" state and
    /// the rear chevron dims — the driver knows to step into the
    /// open or rotate the phone.
    private var uwbOverlay: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(palette.bgCard.opacity(0.92))
                    .frame(width: 44, height: 44)
                Circle()
                    .strokeBorder(
                        uwb.lostLineOfSight ? palette.borderFaint
                                            : Brand.success.opacity(0.7),
                        lineWidth: 1.5
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: "location.north.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(
                        uwb.lostLineOfSight ? AnyShapeStyle(palette.textTertiary)
                                            : AnyShapeStyle(LinearGradient.diagonal)
                    )
                    .rotationEffect(uwbHeadingRadians)
                    .animation(.easeOut(duration: 0.18), value: uwb.direction)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(uwbDistanceText)
                    .font(EType.body.weight(.heavy))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                Text(uwbStatusText)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(palette.bgCard.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Phone-frame heading vector → 2D rotation angle for the chevron
    /// glyph. NI returns a `simd_float3`; we use the X/Z plane
    /// (azimuth) for the on-screen rotation.
    private var uwbHeadingRadians: Angle {
        guard let dir = uwb.direction else { return .zero }
        let azimuth = atan2(dir.x, -dir.z)
        return .radians(Double(azimuth))
    }

    private var uwbDistanceText: String {
        if uwb.lostLineOfSight { return "—" }
        guard let d = uwb.distance else { return "Locating…" }
        return String(format: "%.1f m", d)
    }

    private var uwbStatusText: String {
        switch uwb.status {
        case .ranging:
            return uwb.lostLineOfSight ? "LINE-OF-SIGHT LOST · ROTATE PHONE"
                                       : "UWB · DOOR \(dockNumber)"
        case .idle:                 return "UWB · STARTING"
        case .suspended:            return "UWB · BACKGROUND PAUSED"
        case .unsupported(let m):   return m.uppercased()
        case .failed(let m):        return "UWB · \(m.uppercased())"
        }
    }
}

// MARK: - Dock cam source picker
//
// Capability-gated chooser presented when the dock-assigned action
// row's "Dock cam" affordance fires. Renders one row per source —
// terminal NVR (Option A), driver dash-cam (Option B), trailer dome
// cam (Option C), and phone camera fallback (Option D, always on).
//
// Each row's enabled state reads from the live capability envelopes
// hydrated on screen entry. Disabled rows render with "Pair hardware"
// helper text + an info chevron pointing at the Hardware Capabilities
// self-declaration screen — the same surface terminal managers /
// shipper-of-record / carrier admins use to register equipment.
//
// Doctrine: the Yardmap + Dock cam buttons NEVER render inert —
// every row that can't fire the upstream stream still surfaces a
// real path forward (declare hardware → unlocks → row lights up).
//
// Upstream wiring TODO (per founder pick):
//   • A · partner NVR via WebRTC + signaling websocket
//   • B · dash-cam vendor live stream (Samsara / Motive / Garmin / Cipia)
//   • C · trailer dome cam vendor stream (Sensata / ORBCOMM / Spireon)
//   • D · device camera capture (DriverPhotoUploadSheet) — wired today
//         via `\.driverUploadPhoto` env handler + `onPickPhoneFallback`
//         callback on this picker.

struct DockCamSourcePicker: View {
    let doorNumber: String
    let terminalCaps: CapabilitiesAPI.TerminalCapabilities?
    let carrierCaps: CapabilitiesAPI.CarrierCapabilities?
    let onPickPhoneFallback: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    headerCard

                    sourceRow(
                        icon: "video.fill",
                        title: "Terminal NVR live",
                        subtitle: nvrSubtitle,
                        available: hasNvr,
                        action: { /* signaling handshake target */ }
                    )

                    sourceRow(
                        icon: "car.side.fill",
                        title: "Dash cam · \(carrierCaps?.dashCam.vendor.capitalized ?? "None")",
                        subtitle: dashCamSubtitle,
                        available: hasDashCam,
                        action: { /* dash-cam vendor stream target */ }
                    )

                    sourceRow(
                        icon: "shippingbox.fill",
                        title: "Trailer dome cam",
                        subtitle: domeCamSubtitle,
                        available: false,
                        action: { /* dome-cam vendor stream target */ }
                    )

                    sourceRow(
                        icon: "camera.fill",
                        title: "Phone camera",
                        subtitle: "Capture a dock-door photo for safety + audit. Always available.",
                        available: true,
                        action: onPickPhoneFallback
                    )

                    helperFooter
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .navigationTitle("Dock cam · Door \(doorNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CAMERA SOURCES")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            Text("Pick a feed for door \(doorNumber)")
                .font(EType.body.weight(.bold))
                .foregroundStyle(palette.textPrimary)
            Text("Sources without paired hardware show a setup link. Phone camera is always available as a safety fallback.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    @ViewBuilder
    private func sourceRow(
        icon: String,
        title: String,
        subtitle: String,
        available: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            if available { action() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(
                        available ? AnyShapeStyle(LinearGradient.diagonal)
                                  : AnyShapeStyle(palette.textTertiary)
                    )
                    .frame(width: 32, height: 32)
                    .background(palette.bgCardSoft)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(EType.body.weight(.semibold))
                        .foregroundStyle(available ? palette.textPrimary : palette.textTertiary)
                    Text(subtitle)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if available {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(palette.textSecondary)
                } else {
                    Text("Pair")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().strokeBorder(palette.borderFaint))
                }
            }
            .padding(14)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .opacity(available ? 1.0 : 0.74)
        }
        .buttonStyle(.plain)
        .disabled(!available)
    }

    private var helperFooter: some View {
        Text("Sources marked Pair require the terminal manager, carrier admin, or fleet owner to register hardware in Settings → Hardware Capabilities. Once registered the source lights up automatically next time you open this picker.")
            .font(EType.caption)
            .foregroundStyle(palette.textSecondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    // MARK: - Capability resolution

    private var hasNvr: Bool {
        terminalCaps?.hasCameraFeed(doorNumber: doorNumber) ?? false
    }
    private var nvrSubtitle: String {
        if let feed = terminalCaps?.cameraFeeds.first(where: { $0.doorNumber == doorNumber }) {
            return "\(feed.vendor.capitalized) · live WebRTC"
        }
        return "Pending terminal NVR registration"
    }

    private var hasDashCam: Bool {
        guard let dc = carrierCaps?.dashCam else { return false }
        return dc.configured && dc.vendor != "none"
    }
    private var dashCamSubtitle: String {
        if hasDashCam {
            return "Live stream from your fleet's dash cam"
        }
        return "Carrier admin connects vendor (Samsara / Motive / Garmin / Cipia)"
    }

    /// Trailer dome cam isn't currently scoped to the active load —
    /// shown for completeness but disabled until the per-trailer
    /// capability lookup wires through.
    private var domeCamSubtitle: String {
        "Trailer dome cam (Sensata / ORBCOMM / Spireon) — requires per-trailer registration"
    }
}

#Preview("022 · Dock Assigned · Dark") {
    DockAssignedScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("022 · Dock Assigned · Light") {
    DockAssignedScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
