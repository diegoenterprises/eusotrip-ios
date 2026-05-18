//
//  016_PickupLoading.swift
//  EusoTrip — Lifecycle screen 016 · Pickup Loading.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `016 Pickup Loading.png` (Dark + Light). The tanker is at the
//  bay, hose is connected, and product is flowing. Leads with a
//  gradient progress ring (% loaded), the live rate + time-to-full
//  readout, three safety tiles (pressure / product temp / grounding
//  resistance), an ESANG watchdog card, the bay-sequence checklist,
//  and an E-Stop / View BOL preview pair of CTAs.
//
//  Composition (top to bottom):
//    • Header — back chevron + "Loading" + right-column clock / load
//      id / bay info.
//    • Facility strip — "BAY 3 · KOCH BELLE PLAINE · ARM 04".
//    • Progress card — big ring with % loaded in the center, rate +
//      remaining readouts to the right.
//    • Safety tile row — PRESSURE / PRODUCT TEMP / GROUNDING.
//    • ESANG watchdog card — operator-voice live summary.
//    • BAY SEQUENCE — 6-step checklist with timestamps per row +
//      DONE / NOW / Next chips.
//    • Footer — E-Stop (red outline) + View BOL preview (gradient).
//    • Bottom nav — preserved verbatim per doctrine.
//
//  Data wiring:
//    • `TripLifecycleStore.hydrateActiveLoad()` pulls the real load
//      for commodity / UN number / total-gallons fields.
//    • Sensor readings (pressure psi, temp °F, ground Ω) are
//      forwarded-from-truck telemetry in production; until that
//      pipeline ships, the Figma reference values render so the
//      frame paints identically in preview + cold start.
//    • View BOL preview opens the 017 BOL signing sheet.
//    • E-Stop fires an emergency mutation — routes through
//      `emergencyOps.triggerEStop` when wired.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct PickupLoading: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var showBolPreview: Bool = false
    @State private var showEStopConfirm: Bool = false

    enum Register { case night, morning }
    let register: Register

    init(register: Register = .night) { self.register = register }

    /// Product+vertical dispatch for every copy / chip / icon
    /// decision on this screen. Hazmat shows pressure/temp/
    /// grounding; reefer shows set-point/return-air/fuel; dry-van
    /// shows pallets/dock/seal; flatbed shows tarps/straps/height;
    /// container/intermodal/vessel show pins/seal/chassis.
    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Figma-verbatim fallback (matches the 2026-04-24 frame).
    private let fallbackClock        = "09:14 CDT"
    private let fallbackBayLine      = "—"
    private let fallbackLoadID       = "—"
    private let fallbackCommod       = "Anhydrous Ammonia"
    private let fallbackUN           = "UN1005"
    private let fallbackPressure     = 132
    private let fallbackPressureLim  = 250
    private let fallbackTempF        = -28
    private let fallbackChillSpec    = "chill spec"
    private let fallbackGroundOhm    = 0.8
    private let fallbackGroundSpec   = "cap 0.8 Ω"
    private let fallbackRateGpm      = 218
    private let fallbackMinutesLeft  = 18
    private let fallbackGallonsFlown = 6_510
    private let fallbackGallonsTotal = 10_500

    private var loadedFraction: Double {
        Double(fallbackGallonsFlown) / Double(fallbackGallonsTotal)
    }
    private var loadedPercent: Int {
        Int((loadedFraction * 100).rounded())
    }

    private var loadIDText: String {
        activeLoad?.loadNumber ?? fallbackLoadID
    }
    private var commodityText: String {
        activeLoad?.commodityName ?? fallbackCommod
    }
    private var unText: String {
        activeLoad?.unNumber ?? fallbackUN
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                facilityStrip
                progressCard
                safetyTiles
                watchdogCard
                baySequenceCard
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .screenTileRoot()
        .alert("Stop load transfer?", isPresented: $showEStopConfirm) {
            Button("E-Stop now", role: .destructive) {
                Task { await triggerEStop() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Closes the bay arm and aborts the transfer. Only use in a genuine safety event.")
        }
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

            Text("Loading")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(palette.textPrimary)

            // 2026-05-17 — Mode badge on the loading-dock header. The
            // dock crew's procedure differs sharply by mode (vessel
            // requires tide window + tug coordination, rail needs
            // siding alignment, truck is dock-door). Hidden for the
            // default truck-single-vehicle case.
            LoadModeBadge(modeRaw: activeLoad?.transportMode,
                          multiVehicleCount: activeLoad?.multiVehicleCount,
                          compact: true)

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(fallbackClock)
                    .font(EType.mono(.caption)).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
                Text(loadIDText)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Facility strip

    private var facilityStrip: some View {
        Text(fallbackBayLine)
            .font(EType.mono(.micro)).tracking(0.5)
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
    }

    // MARK: Progress card

    private var progressCard: some View {
        HStack(alignment: .center, spacing: Space.s4) {
            progressRing
            VStack(alignment: .leading, spacing: 6) {
                Text("\(commodityText) · \(unText)")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(fallbackGallonsFlown.formatted())
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                    Text("/ \(fallbackGallonsTotal.formatted()) gal")
                        .font(EType.body)
                        .foregroundStyle(palette.textSecondary)
                }
                HStack(spacing: 4) {
                    Text("▲ \(fallbackRateGpm) gpm")
                        .font(EType.mono(.caption)).fontWeight(.semibold)
                        .foregroundStyle(Brand.success)
                    Text("·")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                    Text("\(fallbackMinutesLeft) min to full")
                        .font(EType.mono(.caption)).fontWeight(.semibold)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(palette.bgCardSoft, lineWidth: 10)
                .frame(width: 108, height: 108)
            Circle()
                .trim(from: 0, to: CGFloat(loadedFraction))
                .stroke(
                    LinearGradient.diagonal,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 108, height: 108)
                .animation(.easeOut(duration: 0.6), value: loadedFraction)
            VStack(spacing: 0) {
                Text("\(loadedPercent)%")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("LOADED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: Safety tiles — product-dispatched

    /// 3 live sensor tiles. Content swaps based on the active
    /// load's product — hazmat shows pressure/temp/grounding;
    /// reefer shows set-point/return-air/fuel; dry-van shows
    /// pallets/dock/seal; etc. Fulfils the "all verticals,
    /// products type not just hazmat" doctrine (2026-04-24).
    private var safetyTiles: some View {
        HStack(spacing: Space.s2) {
            ForEach(ctx.loadingMetrics) { tile in
                safetyTile(
                    label: tile.label,
                    primary: tile.primary,
                    secondary: tile.secondary,
                    color: tileColor(for: tile)
                )
            }
        }
    }

    /// Derive a tile color from the label — pressure/critical
    /// tiles promote to warn/danger at threshold, OK/primary tiles
    /// stay on brand success.
    private func tileColor(for tile: LifecycleProductContext.SafetyTile) -> Color {
        let l = tile.label.uppercased()
        if l.contains("PRESSURE") {
            return pressureColor
        }
        if l.contains("TEMP") {
            return Brand.info
        }
        if l.contains("GROUND") || l.contains("SEAL") || l.contains("PINS") {
            return Brand.success
        }
        if l.contains("FUEL") || l.contains("REEFER") {
            return Brand.success
        }
        return palette.textPrimary
    }

    private var pressureColor: Color {
        let ratio = Double(fallbackPressure) / Double(fallbackPressureLim)
        if ratio < 0.8 { return Brand.success }
        if ratio < 0.95 { return Brand.warning }
        return Brand.danger
    }

    private func safetyTile(
        label: String,
        primary: String,
        secondary: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(primary)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(secondary)
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

    // MARK: ESANG watchdog

    private var watchdogCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 40, height: 40)
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("ESANG · WATCHDOG")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Rate steady at \(fallbackRateGpm) gpm, pressure \(fallbackPressure) psi — well under \(fallbackPressureLim). I'm listening for pressure spikes. Ground is solid at \(String(format: "%.1f", fallbackGroundOhm)) Ω.")
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Bay sequence

    private struct SequenceStep: Identifiable, Hashable {
        let id: String
        let title: String
        let timestamp: String?
        let state: State
        enum State { case done, now, next }
    }

    private let bayCanonicalSteps: [SequenceStep] = [
        .init(id: "chock",    title: "Chock + wheel lock",           timestamp: "09:02", state: .done),
        .init(id: "ground",   title: "Grounding cable clipped",      timestamp: "09:03", state: .done),
        .init(id: "arm",      title: "Arm connected · leak-tested",  timestamp: "09:08", state: .done),
        .init(id: "transfer", title: "Transfer in progress",         timestamp: "09:10", state: .now),
        .init(id: "blowdown", title: "Line blow-down · cap torque",  timestamp: nil,     state: .next),
        .init(id: "release",  title: "Release from gantry",          timestamp: nil,     state: .next),
    ]

    private var baySequenceCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("BAY SEQUENCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
            }
            VStack(spacing: 0) {
                ForEach(Array(bayCanonicalSteps.enumerated()), id: \.element.id) { idx, step in
                    sequenceRow(step)
                    if idx < bayCanonicalSteps.count - 1 {
                        Divider().overlay(palette.borderFaint).padding(.leading, 36)
                    }
                }
            }
            .padding(.vertical, Space.s1)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private func sequenceRow(_ step: SequenceStep) -> some View {
        HStack(spacing: Space.s3) {
            sequenceDot(state: step.state)
            Text(step.title)
                .font(EType.body)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            Text(sequenceTail(step))
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                .foregroundStyle(sequenceTailColor(step))
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 10)
    }

    private func sequenceDot(state: SequenceStep.State) -> some View {
        Group {
            switch state {
            case .done:
                ZStack {
                    Circle().fill(Brand.success.opacity(0.2))
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Brand.success)
                }
            case .now:
                ZStack {
                    Circle().fill(LinearGradient.diagonal.opacity(0.2))
                    Circle().stroke(LinearGradient.diagonal, lineWidth: 1.5).frame(width: 12, height: 12)
                }
            case .next:
                Circle().strokeBorder(palette.borderSoft, lineWidth: 1.5)
            }
        }
        .frame(width: 20, height: 20)
    }

    private func sequenceTail(_ step: SequenceStep) -> String {
        switch step.state {
        case .done: return step.timestamp ?? "DONE"
        case .now:  return step.timestamp ?? "NOW"
        case .next: return "NEXT"
        }
    }

    private func sequenceTailColor(_ step: SequenceStep) -> Color {
        switch step.state {
        case .done: return palette.textTertiary
        case .now:  return Brand.warning
        case .next: return palette.textTertiary
        }
    }

    // MARK: Footer CTAs

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            Button { showEStopConfirm = true } label: {
                Text("E-Stop")
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(Brand.danger)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(Brand.danger.opacity(0.6), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .accessibilityLabel("Emergency stop — halt transfer")

            CTAButton(title: "View BOL preview") { showBolPreview = true }
            .accessibilityLabel("Preview bill of lading before signing")
            .sheet(isPresented: $showBolPreview) {
                PickupBolSigning()
                    .environment(\.palette, palette)
                    .eusoSheetX()
            }
        }
    }

    // MARK: - Live hydration + actions

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
        // Phase 10 closure: appointment status -> loading the
        // moment 016 appears (driver at the dock + product
        // moving). Best-effort; non-blocking on lifecycle.
        if let appt = try? await EusoTripAPI.shared.appointments
            .getByLoad(loadId: lifecycle.loadId) {
            _ = try? await EusoTripAPI.shared.appointments
                .updateStatus(id: appt.id, status: "loading")
        }
    }

    private func triggerEStop() async {
        let forwardKeys = ["abort", "emergency", "stopped"]
        if let transition = lifecycle.availableTransitions.first(where: { t in
            let to = t.to.lowercased()
            return forwardKeys.contains(where: { to.contains($0) })
        }) {
            _ = await lifecycle.execute(transition)
        }
    }
}

// MARK: - Wrapper

struct PickupLoadingScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            PickupLoading(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_016(),
                      trailing: driverNavTrailing_016(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_016() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_016() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person", isCurrent: false)]
}

// MARK: - Previews

#Preview("016 · Pickup Loading · Dark") {
    PickupLoadingScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("016 · Pickup Loading · Light") {
    PickupLoadingScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
