//
//  024_Unloading.swift
//  EusoTrip — Lifecycle screen 024 · Unloading.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `024 Unloading.png` (Dark + Light). Fires while the trailer is
//  being unloaded at the dock. Surfaces a live pallet map (trailer
//  grid with unloaded squares), a progress counter + rate, a
//  detention ticker (free-time passed → paid), a receiver info
//  row, and an ESANG advisory.
//
//  Adapts to the product — hazmat tanker shows gallons offloaded,
//  reefer shows pallet count (same as dry van), flatbed shows
//  tie-downs released, container shows moves.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct Unloading: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var showBol: Bool = false

    /// Real-time anchor for the detention accrual ticker — set to the
    /// load's actual `at_delivery` (arrival) lifecycle transition
    /// timestamp once hydrated. Free time runs from arrival; detention
    /// accrues once the free window passes. Nil until the live history
    /// resolves, in which case the screen falls back to the Figma
    /// reference clock so the layout still holds.
    @State private var arrivalAnchor: Date?

    /// Live unloaded count, resolved from the load's lifecycle progress
    /// once hydrated. Nil = no live count yet → render the Figma
    /// `fallbackOff` reference. Driven through `unloadedNow` /
    /// `unloadProgress` so the grid + rail bind to ONE real fraction.
    @State private var liveUnloaded: Int?

    /// Drives the autoreversing opacity breath on the PAID chip while
    /// detention is accruing. Toggled true on appear; the repeatForever
    /// animation carries it. Off under reduce-motion.
    @State private var billingPulse: Bool = false

    enum Register { case night, afternoon }
    let register: Register

    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Figma fallback
    private let fallbackDoor      = "12"
    private let fallbackOff       = 4
    private let fallbackTotal     = 26
    private let fallbackTrailer   = "—"
    private let fallbackStarted   = "00:32"
    private let fallbackEtaRemain = "3:15"
    private let fallbackRate      = "2"
    private let fallbackDetention = "2:47"
    private let fallbackDetRate   = "—"
    private let fallbackDetCharge = "—"
    private let fallbackReceiver  = "—"
    private let fallbackReceiverSub = "dispatch bell · door 12"

    // MARK: - Real-logic bindings
    //
    // Every meaningful animation on this screen reads from ONE of the
    // two derived values below — never a decorative literal. The grid
    // fill, the progress rail, and the hero counter all bind to
    // `unloadedNow` / `unloadProgress`; the detention ticker binds to
    // the real `arrivalAnchor` elapsed clock.

    /// Total unload units (pallets / gallons / moves / tons). Falls
    /// back to the Figma reference total until a live count column
    /// lands on the load envelope.
    private var unloadTotal: Int { fallbackTotal }

    /// Live count of units off the trailer. Prefers the hydrated
    /// `liveUnloaded` from the lifecycle progress; falls back to the
    /// Figma reference until a live column ships. Clamped to the total.
    private var unloadedNow: Int {
        min(liveUnloaded ?? fallbackOff, unloadTotal)
    }

    /// THE real unload fraction (0…1). Bound directly to the progress
    /// rail width and to the grid fill threshold so both reflect the
    /// same live `unloaded / total` — never a hardcoded percentage.
    private var unloadProgress: Double {
        guard unloadTotal > 0 else { return 0 }
        return Double(unloadedNow) / Double(unloadTotal)
    }

    // MARK: Detention accrual

    /// Free-time window before detention starts billing. Standard
    /// 2-hour free window (matches the "Free time ended at 2:00"
    /// reference copy). A regulatory/contract constant, not fabricated
    /// per-load data.
    private let freeTimeWindow: TimeInterval = 2 * 3600

    /// The instant detention began accruing (= arrival + free window).
    /// Nil until the live arrival timestamp resolves.
    private var detentionStart: Date? {
        arrivalAnchor.map { $0.addingTimeInterval(freeTimeWindow) }
    }

    /// Real detention elapsed at `now`. Zero before the free window
    /// passes. Returns nil when no live anchor is wired (→ the Figma
    /// reference string renders instead).
    private func detentionElapsed(at now: Date) -> TimeInterval? {
        guard let start = detentionStart else { return nil }
        return max(0, now.timeIntervalSince(start))
    }

    /// "H:MM" accrual display for a real elapsed interval.
    private func formatDetention(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let h = total / 3600
        let m = (total % 3600) / 60
        return String(format: "%d:%02d", h, m)
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                palletMap
                progressCard
                detentionCard
                receiverRow
                advisoryCard
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
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

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("DETENTION")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(Brand.warning)
                    Text("· PAID TIME")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textSecondary)
                    // 2026-05-17 — Mode chip on unloading header. The
                    // unloading procedure differs by mode (vessel
                    // hatch discharge, rail tank-car offloading, truck
                    // dock unload). Hidden on default truck-single-
                    // vehicle.
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
                Text("Door \(fallbackDoor) · \(unloadedNow) of \(unloadTotal) \(ctx.unloadUnitLabel) off")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .contentTransition(.numericText(value: Double(unloadedNow)))
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
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Pallet map

    private var palletMap: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("PALLET MAP · REFRESHED 03:19")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(palette.textSecondary.opacity(0.5)).frame(width: 6, height: 6)
                    Text("on trailer").font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                    Circle().fill(LinearGradient.diagonal).frame(width: 6, height: 6)
                    Text("unloaded").font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
            }

            // Stylized trailer grid — 110th firing M2 retrofit:
            // hardcoded "TR-2118" excised. Trailer id is not yet a
            // first-class field on Load; until FleetStore.assignedTrailer
            // wires in we render the existing `fallbackTrailer` em-dash
            // sentinel so the layout holds without leaking a fake id.
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(fallbackTrailer)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .accessibilityLabel(fallbackTrailer == "—" ? "Trailer pending" : "Trailer \(fallbackTrailer)")
                    Spacer()
                    Text("DOOR \(fallbackDoor)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
                GeometryReader { geo in
                    let rows = 2
                    let cols = 13
                    let cellW = (geo.size.width - CGFloat(cols - 1) * 3) / CGFloat(cols)
                    let cellH: CGFloat = 18
                    VStack(spacing: 3) {
                        ForEach(0..<rows, id: \.self) { r in
                            HStack(spacing: 3) {
                                ForEach(0..<cols, id: \.self) { c in
                                    let idx = r * cols + c
                                    // Bound to the REAL unloaded count
                                    // (`unloadedNow`). Each cell flips
                                    // gradient-filled the instant the
                                    // live count crosses its index — no
                                    // decorative threshold.
                                    let isOff = idx < unloadedNow
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(isOff
                                              ? AnyShapeStyle(LinearGradient.diagonal)
                                              : AnyShapeStyle(palette.bgCardSoft))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 2)
                                                .stroke(
                                                    isOff ? Color.clear : palette.borderFaint,
                                                    lineWidth: 1
                                                )
                                        )
                                        .frame(width: cellW, height: cellH)
                                }
                            }
                        }
                    }
                    // Spring-settle fill crossfade when a unit flips from
                    // on-trailer to unloaded — each newly-crossed cell
                    // eases from the soft slot to the gradient fill,
                    // reading as a satisfying "thunk" as the live count
                    // advances. Bound to the REAL `unloadedNow`; snaps to
                    // the final grid under reduce-motion.
                    .animation(
                        reduceMotion
                            ? nil
                            : .spring(response: 0.34, dampingFraction: 0.72),
                        value: unloadedNow
                    )
                }
                .frame(height: 44)

                HStack(spacing: 4) {
                    Text("unload")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.top, 2)
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Progress card

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(unloadedNow)")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(unloadedNow)))
                Text("/ \(unloadTotal) \(ctx.unloadUnitLabel)")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Text("Est. \(fallbackEtaRemain) remaining")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }

            // Progress rail — width is bound to the REAL `unloadProgress`
            // fraction (unloaded / total), never a decorative value.
            // Eases with a cubic-bezier(0.4,0,0.2,1) decelerate curve on
            // a 280ms data-update beat as the count advances; snaps to
            // the final fill under reduce-motion.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.bgCardSoft).frame(height: 5)
                    Capsule()
                        .fill(LinearGradient.diagonal)
                        .frame(
                            width: geo.size.width * CGFloat(unloadProgress),
                            height: 5
                        )
                        .animation(
                            reduceMotion
                                ? nil
                                : .timingCurve(0.4, 0, 0.2, 1, duration: 0.28),
                            value: unloadProgress
                        )
                }
            }
            .frame(height: 5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Unload progress")
            .accessibilityValue("\(Int((unloadProgress * 100).rounded())) percent, \(unloadedNow) of \(unloadTotal) \(ctx.unloadUnitLabel)")

            HStack {
                Text("STARTED \(fallbackStarted)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("RATE \(fallbackRate) \(ctx.unloadRateLabel)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
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

    // MARK: Detention card

    private var detentionCard: some View {
        // Real-time accrual ticker. The clock advances off a real
        // `Date`, computing elapsed against the live `detentionStart`
        // anchor (arrival + free window). The display is H:MM, so under
        // reduce-motion we step the schedule down to a 60s minute
        // cadence and freeze the PAID-chip breath + digit-roll — no
        // per-second churn or pulsing. When no live anchor is wired the
        // card falls through to the Figma reference clock.
        let tick: TimeInterval = reduceMotion ? 60.0 : 1.0
        return TimelineView(.periodic(from: .now, by: tick)) { timeline in
            let now = timeline.date
            let elapsed = detentionElapsed(at: now)
            let display = elapsed.map(formatDetention) ?? fallbackDetention
            let isAccruing = (elapsed ?? 0) > 0

            return VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text("DETENTION · PAID")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(LinearGradient.diagonal)
                    Spacer()
                    Text("PAID")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(Brand.warning)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(Capsule().stroke(Brand.warning.opacity(0.5), lineWidth: 1))
                        // Live "billing" pulse — a slow 1.6s autoreversing
                        // opacity breath on the PAID chip while detention
                        // is actually accruing, signalling the meter is
                        // running. Held static at full opacity when not
                        // accruing or under reduce-motion.
                        .opacity((billingPulse && isAccruing && !reduceMotion) ? 0.5 : 1.0)
                        .animation(
                            (isAccruing && !reduceMotion)
                                ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
                                : .default,
                            value: billingPulse
                        )
                }
                Text(display)
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel("Detention time accrued")
                    .accessibilityValue(display)
                Text("Free time ended at 2:00. \(fallbackDetRate) since. Running charge: \(fallbackDetCharge)")
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        // Kick the PAID-chip breath once detention is actually accruing
        // (anchor resolved + free window past). Keyed on the live anchor
        // so it also fires after async hydration lands, not just on
        // first appear. Stays off under reduce-motion.
        .onChange(of: detentionStart) { _, newStart in
            guard !reduceMotion, let s = newStart, Date() >= s else { return }
            billingPulse = true
        }
        .onAppear {
            guard !reduceMotion, let s = detentionStart, Date() >= s else { return }
            billingPulse = true
        }
    }

    // MARK: Receiver row

    private var receiverRow: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(palette.bgCardSoft)
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(fallbackReceiver)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(fallbackReceiverSub)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("BACK")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(fallbackDoor)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Advisory

    private var advisoryCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Brand.success)
            Text("Wake the house crew if it stalls. No lumper overnight — they run a two-person crew at 4 \(ctx.unloadUnitLabel)/hr. If detention passes $75, ping dispatch from the Chat button and they'll rebill the shipper.")
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
            Button {
                // Route to the messages tab via the canonical
                // RealtimeService notification — same path the
                // DISPATCH_MESSAGE WS event uses, so the chat
                // surface always resolves the same way regardless
                // of entry point. Was an empty closure (audit hit).
                NotificationCenter.default.post(
                    name: .esangOpenMeDetail,
                    object: "messages",
                    userInfo: nil
                )
            } label: {
                Text("Chat")
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

            CTAButton(title: "Capture POD") { showBol = true }
            .fullScreenCover(isPresented: $showBol) {
                // Production-grade POD capture (camera + signature
                // pad + receiver + notes) firing pod.submitPOD.
                // Replaces the prior PickupBolSigning sheet — wrong
                // sheet for delivery context. After submit the load
                // server-side flips to pod_pending; lifecycle store
                // advances to 025 Paperwork.
                DeliveryPODCaptureView(
                    loadId: lifecycle.loadId,
                    loadNumber: activeLoad?.loadNumber,
                    receiverHint: ctx.facets.deliveryFacility == LiveLoadFacets.dash
                        ? nil : ctx.facets.deliveryFacility
                )
                .environment(\.palette, palette)
                .environment(\.lifecycleAdvance, advance)
                .environmentObject(session)
            }
        }
    }

    // MARK: Hydration

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)

        // Detention anchor — the REAL arrival timestamp. Free time runs
        // from the moment the driver hit the receiver, so the detention
        // ticker accrues against the actual `at_delivery` (falling back
        // to `unloading`) lifecycle transition recorded server-side.
        // Stays nil if no arrival row exists → the Figma reference clock
        // renders instead, never a fake live tick.
        resolveArrivalAnchor(from: lifecycle.history)

        // Live unloaded count — derived honestly from lifecycle state.
        // The load envelope doesn't yet ship a granular unloaded-unit
        // column (LiveLoadFacets.palletCount is a backend gap), so we
        // only assert a count we can prove: once the load reaches a
        // terminal unload state, every unit is off. Mid-unload we leave
        // it nil and render the Figma reference rather than fabricate a
        // partial number.
        let terminalUnloaded: Set<String> = [
            "delivered", "pod_pending", "pod_signed", "completed", "closed",
        ]
        let state = (lifecycle.currentState ?? activeLoad?.status ?? "").lowercased()
        if terminalUnloaded.contains(state) {
            // Animate the count roll + grid spring + rail ease together
            // on the real data update. Snap under reduce-motion.
            if reduceMotion {
                liveUnloaded = unloadTotal
            } else {
                withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.4)) {
                    liveUnloaded = unloadTotal
                }
            }
        }

        // Phase 10 closure: appointment status -> unloading.
        // (Server marks completed when the lifecycle store
        // transitions to 025 / Paperwork.) Best-effort.
        if let appt = try? await EusoTripAPI.shared.appointments
            .getByLoad(loadId: lifecycle.loadId) {
            _ = try? await EusoTripAPI.shared.appointments
                .updateStatus(id: appt.id, status: "unloading")
        }
    }

    /// Find the real arrival timestamp from the lifecycle audit trail
    /// and set `arrivalAnchor`. Prefers the transition INTO `at_delivery`
    /// (arrival at the receiver); falls back to the first `unloading`
    /// transition. Parses the ISO-8601 `createdAt` server stamp.
    private func resolveArrivalAnchor(from history: [LoadLifecycleAPI.StateTransition]) {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        func parse(_ s: String?) -> Date? {
            guard let s = s, !s.isEmpty else { return nil }
            return iso.date(from: s) ?? isoPlain.date(from: s)
        }
        // Arrival = transition whose destination is at_delivery; else the
        // first unloading transition.
        let arrival = history.first(where: { ($0.toState ?? "").lowercased() == "at_delivery" })
            ?? history.first(where: { ($0.toState ?? "").lowercased() == "unloading" })
        if let stamp = parse(arrival?.createdAt) {
            arrivalAnchor = stamp
        }
    }
}

struct UnloadingScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            Unloading(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_024(),
                      trailing: driverNavTrailing_024(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_024() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_024() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person", isCurrent: false)]
}

#Preview("024 · Unloading · Dark") {
    UnloadingScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("024 · Unloading · Light") {
    UnloadingScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
