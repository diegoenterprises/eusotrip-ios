//
//  040_DischargeInProgress.swift
//  EusoTrip — Lifecycle screen 040 · Discharge in Progress.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `040 Discharge in Progress.png`. Product is flowing off the rig,
//  ESANG and the receiver's closed-loop scrubber confirm flow path.
//  Big "transferred / remaining" hero + truck draining gauge +
//  receiver filling gauge + 3 safety tiles + ESANG watchdog row +
//  Pause / Emergency Stop CTAs.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct DischargeInProgress: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var showEStop: Bool = false
    @State private var isPaused: Bool = false
    @State private var pauseInflight: Bool = false
    @State private var pauseToast: String? = nil
    @State private var eStopInflight: Bool = false

    enum Register { case night, afternoon }
    let register: Register
    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // Figma fallback (product-aware; routes through ctx)
    private let fallbackClock      = "21:34"
    private let fallbackElapsed    = "00:16:24"
    private let fallbackTransferred = 4_250
    private let fallbackRemaining   = 2_550
    private let fallbackTotal       = 6_800
    private let fallbackEtaRemain   = "ETA 15 MIN"
    private let fallbackFlowRate    = "165"
    private let fallbackTruckPct    = 38.0
    private let fallbackRecvPct     = 71.0

    private var transferredPct: Double {
        Double(fallbackTransferred) / Double(fallbackTotal)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                heroCard
                flowRateRow
                gaugePair
                if !ctx.dischargeSafetyTiles.isEmpty {
                    safetyTiles
                }
                watchdogStrip
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .screenTileRoot()
        .alert("Emergency stop?", isPresented: $showEStop) {
            Button("E-STOP now", role: .destructive) {
                Task { await triggerEStop() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Closes the discharge valve and arms scrubber dump. Use only in a safety event.")
        }
        .overlay(alignment: .bottom) {
            if let msg = pauseToast {
                Text(msg)
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderSoft)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: pauseToast)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            // 100th firing · ledger-hygiene sweep — was `Button { }` (no-op
            // chevron). Wired to env-injected `driverNavBack`.
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
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    // EUSOTRIP-MODE-BADGE-2026-05-17 — mode chip on lifecycle screen
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
                Text("\(ctx.dischargeHeaderTitle) · \(ctx.dischargeFacilityLine)")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(ctx.dischargeKickerSubtitle)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(fallbackElapsed)
                    .font(EType.mono(.caption)).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
                Text("ELAPSED")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.top, 4)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TRANSFERRED")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text("\(fallbackTransferred.formatted())")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                    Text("\(ctx.dischargeUnit)")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("REMAINING")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text("\(fallbackRemaining.formatted()) \(ctx.dischargeUnit)")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.bgCardSoft).frame(height: 6)
                    Capsule().fill(LinearGradient.diagonal)
                        .frame(width: geo.size.width * CGFloat(transferredPct), height: 6)
                }
            }
            .frame(height: 6)
            HStack {
                Text("\(Int((transferredPct * 100).rounded()))% COMPLETE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(fallbackEtaRemain)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var flowRateRow: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "wind")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text("FLOW RATE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(fallbackFlowRate)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                Text(ctx.unloadRateLabel.lowercased())
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
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

    private var gaugePair: some View {
        let badge = ctx.dischargeRateBadge(value: 165)
        let truckSub = "\(badge) · 2,550 \(ctx.dischargeUnit) LEFT"
        let recvSub  = "\(badge) · 60% FILLED"
        return HStack(spacing: Space.s2) {
            gauge(label: truckGaugeLabel,    value: fallbackTruckPct, sub: truckSub, invert: true)
            gauge(label: receiverGaugeLabel, value: fallbackRecvPct,  sub: recvSub,  invert: false)
        }
    }

    private var truckGaugeLabel: String {
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:   return "TRUCK (DROPPING)"
        case .reefer, .dryVan:               return "TRAILER (UNLOADING)"
        case .flatbed:                       return "DECK (RELEASING)"
        case .container, .railIntermodal,
             .vesselContainer:               return "CHASSIS (LIFTING)"
        case .railBulk, .vesselBulk:         return "BULK (DROPPING)"
        }
    }

    private var receiverGaugeLabel: String {
        switch ctx.product {
        case .hazmatTanker, .vesselTanker:   return "RECEIVER (RISING)"
        case .reefer, .dryVan:               return "DOCK (FILLING)"
        case .flatbed:                       return "RECEIVER (LANDED)"
        case .container, .railIntermodal:    return "RAMP (LANDED)"
        case .vesselContainer:               return "VESSEL (LOADED)"
        case .railBulk, .vesselBulk:         return "SILO (RISING)"
        }
    }

    private func gauge(label: String, value: Double, sub: String, invert: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(String(format: "%.0f%%", value))
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(palette.bgCardSoft).frame(height: 8)
                    Rectangle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: geo.size.width * CGFloat(value / 100), height: 8)
                }
            }
            .frame(height: 8)
            .rotationEffect(.degrees(invert ? 180 : 0))
            Text(sub)
                .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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

    private var safetyTiles: some View {
        HStack(spacing: Space.s2) {
            ForEach(ctx.dischargeSafetyTiles) { tile in
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.label)
                        .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text(tile.primary)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                    Text(tile.secondary)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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
        }
    }

    private var watchdogStrip: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text(ctx.dischargeWatchdogLabel)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text("ALL CLEAR")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(Brand.success)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .overlay(Capsule().stroke(Brand.success.opacity(0.5), lineWidth: 1))
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            // PAUSE / RESUME — same pattern as 030 + 032: records a
            // timestamped note on the load's appointment via the
            // real `appointments.updateStatus` mutation so the
            // shipper / dispatcher web surfaces see why the rig is
            // halted on the dock past the usual purge window.
            // Local visual state still flips for instant UI feedback.
            Button { Task { await togglePauseDischarge() } } label: {
                HStack(spacing: 6) {
                    if pauseInflight {
                        ProgressView()
                            .controlSize(.small)
                            .tint(palette.textPrimary)
                    }
                    Text(isPaused ? "RESUME" : "PAUSE")
                        .font(EType.body.weight(.semibold))
                        .foregroundStyle(isPaused
                                         ? AnyShapeStyle(LinearGradient.diagonal)
                                         : AnyShapeStyle(palette.textPrimary))
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(
                            isPaused
                                ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.6))
                                : AnyShapeStyle(palette.borderSoft)
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .disabled(pauseInflight)
            .accessibilityLabel(isPaused ? "Resume discharge" : "Pause discharge")
            Button { showEStop = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("EMERGENCY STOP")
                        .font(EType.body.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Brand.danger)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
        }
    }

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    /// Pause / resume the discharge — same pattern as 030 + 032.
    /// Server tolerates same-status updates with a fresh `notes`
    /// field so the timestamped pause shows up in the appointment's
    /// history without needing a separate `paused` enum value.
    private func togglePauseDischarge() async {
        guard !pauseInflight else { return }
        pauseInflight = true
        defer { pauseInflight = false }
        let willPause = !isPaused
        let stamp = ISO8601DateFormatter().string(from: Date())
        let note = willPause
            ? "Driver paused discharge at \(stamp)"
            : "Driver resumed discharge at \(stamp)"
        guard !lifecycle.loadId.isEmpty else {
            pauseToast = "No active load"
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            pauseToast = nil
            return
        }
        do {
            if let appt = try await EusoTripAPI.shared.appointments
                .getByLoad(loadId: lifecycle.loadId) {
                _ = try? await EusoTripAPI.shared.appointments
                    .updateStatus(
                        id: appt.id,
                        status: "unloading",
                        notes: note
                    )
            }
            isPaused.toggle()
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            pauseToast = willPause ? "Discharge paused" : "Discharge resumed"
        } catch {
            pauseToast = "Couldn't update appointment"
        }
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        pauseToast = nil
    }

    /// Trigger the emergency-stop transition. Same pattern as 016
    /// `triggerEStop` — picks the first available transition whose
    /// destination phase contains "abort", "emergency", or
    /// "stopped" and executes it via the lifecycle store. Server
    /// fans the safety event to dispatch + CHEMTREC + the load's
    /// shipper. Notes the timestamp on the appointment so the
    /// audit trail records the exact moment the driver triggered.
    private func triggerEStop() async {
        guard !eStopInflight else { return }
        eStopInflight = true
        defer { eStopInflight = false }
        let stamp = ISO8601DateFormatter().string(from: Date())
        let forwardKeys = ["abort", "emergency", "stopped"]
        if let transition = lifecycle.availableTransitions.first(where: { t in
            let to = t.to.lowercased()
            return forwardKeys.contains(where: { to.contains($0) })
        }) {
            _ = await lifecycle.execute(transition)
        }
        if !lifecycle.loadId.isEmpty,
           let appt = try? await EusoTripAPI.shared.appointments
               .getByLoad(loadId: lifecycle.loadId) {
            _ = try? await EusoTripAPI.shared.appointments
                .updateStatus(
                    id: appt.id,
                    status: "unloading",
                    notes: "Driver triggered EMERGENCY STOP at \(stamp)"
                )
        }
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}

struct DischargeInProgressScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            DischargeInProgress(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_040(),
                      trailing: driverNavTrailing_040(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_040() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_040() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

#Preview("040 · Discharge in Progress · Dark") {
    DischargeInProgressScreen(theme: Theme.dark).preferredColorScheme(.dark)
}
#Preview("040 · Discharge in Progress · Light") {
    DischargeInProgressScreen(theme: Theme.light).preferredColorScheme(.light)
}
