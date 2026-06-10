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
//  Data wiring (Wave-A1 fabrication kill, 2026-06-10):
//    • `TripLifecycleStore.hydrateActiveLoad()` pulls the real load
//      for commodity / UN number / total-gallons fields.
//    • The fill TARGET derives from the real load weight (the 030
//      pattern: weight ÷ 5.15 lb/gal). Gallons FLOWN have no live
//      source yet (forwarded-from-truck fill telemetry) — the ring
//      renders the honest EMPTY state with an em-dash center, never
//      the old fixed Figma numerator. Rate / time-to-full / sensor
//      tiles / bay-sequence stamps are em-dash until their feeds land.
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    // MARK: - Honest sentinels (no Figma reference values on the live path).
    // The old "Anhydrous Ammonia" / "UN1005" commodity pair was a Figma
    // persona — em-dash until the real load hydrates (Wave-A1 kill).
    private let fallbackBayLine      = "-"
    private let fallbackLoadID       = "-"
    private let fallbackCommod       = "—"
    private let fallbackUN           = "—"

    // MARK: - Loaded-fraction source of truth
    //
    // The progress ring, the big "% LOADED" label, and the
    // "gallons flown / total" readout MUST all read off the same two
    // numbers so they can never disagree on screen. `gallonsTotal`
    // (the fill target) is REAL — derived from the load's manifested
    // weight, the same weight ÷ 5.15 lb/gal derivation 030 uses.
    // `gallonsFlown` is the live forwarded-from-truck fill telemetry,
    // which has NO source yet — so it is nil and the ring renders the
    // honest EMPTY state with an em-dash center. The old fixed Figma
    // numerator is DEAD (Wave-A1 fabrication kill, 2026-06-10): a ring
    // that swept to 62% on every load was telemetry-shaped fiction.

    /// Fill target in gallons. Derived from the real load's net
    /// weight when present (anhydrous ammonia ≈ 5.15 lb/gal at the
    /// fill reference — the 030 pattern). Nil when the load hasn't
    /// hydrated or carries no weight → the readout em-dashes.
    private var gallonsTotal: Int? {
        guard let load = activeLoad, load.weightValue > 0,
              load.weightValue.isFinite else { return nil }
        return max(Int((load.weightValue / 5.15).rounded()), 1)
    }

    /// Gallons transferred so far. Live fill telemetry is forwarded
    /// from the truck in production; that stream has NOT shipped, so
    /// this is nil and every consumer renders the em-dash / empty-ring
    /// state (the 050 fill-gauge pattern). Never a baked number.
    private var gallonsFlown: Int? { nil }

    /// Flown ÷ target, clamped 0…1. Nil when either side has no live
    /// source — the ring then renders EMPTY, never a fabricated sweep.
    private var loadedFraction: Double? {
        guard let flown = gallonsFlown, let total = gallonsTotal,
              total > 0 else { return nil }
        return min(1, Double(flown) / Double(total))
    }

    private static let groupedGal: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal
        f.maximumFractionDigits = 0; return f
    }()
    private func gal(_ v: Int?) -> String {
        guard let v else { return "—" }
        return Self.groupedGal.string(from: NSNumber(value: v)) ?? "\(v)"
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
                // Wave B (2026-06-10) — the driver at the rack sees the
                // LOADING procedure animation for the real rig (the
                // bind-rich state-variant file the census found fully
                // orphaned), bound to this load's live status / commodity
                // / UN / weight. Complements the ring + gauges above —
                // never replaces them.
                DriverEquipmentMoment(
                    facts: activeLoad.map(LoadAnimationContext.DriverLoadFacts.init(load:)),
                    state: .loading,
                    label: "AT THE RACK"
                )
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
                // Live device wall clock, refreshed every minute — the
                // 039/044 pattern, never the seeded "09:14 CDT".
                TimelineView(.everyMinute) { tl in
                    Text(tl.date, format: .dateTime.hour().minute())
                        .font(EType.mono(.caption)).fontWeight(.semibold)
                        .foregroundStyle(palette.textPrimary)
                }
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
                    // Gallons flown have no live source → em-dash; the
                    // target is the REAL weight-derived total when known.
                    Text(gal(gallonsFlown))
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                    Text("/ \(gal(gallonsTotal)) gal")
                        .font(EType.body)
                        .foregroundStyle(palette.textSecondary)
                }
                HStack(spacing: 4) {
                    // No live flow-rate / time-to-full feed → em-dash,
                    // never the seeded "218 gpm" / "18 min" Figma pair.
                    Text("— gpm")
                        .font(EType.mono(.caption)).fontWeight(.semibold)
                        .foregroundStyle(palette.textTertiary)
                    Text("·")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                    Text("— min to full")
                        .font(EType.mono(.caption)).fontWeight(.semibold)
                        .foregroundStyle(palette.textTertiary)
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
        // No live fraction (gallons flown unsourced) → the arc renders
        // EMPTY and the center reads "—" — the 050 fill-gauge pattern.
        // When the fill-telemetry lane ships, the same trim lights up
        // with the real flown ÷ target ratio. Never a decorative sweep.
        let frac = loadedFraction
        let shown = CGFloat(frac ?? 0)
        return ZStack {
            Circle()
                .stroke(palette.bgCardSoft, lineWidth: 10)
                .frame(width: 108, height: 108)
            Circle()
                // Completed arc = real flown / target fraction (0 = empty).
                .trim(from: 0, to: shown)
                .stroke(
                    LinearGradient.diagonal,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 108, height: 108)
                // Each fill tick is a data-update settle: Material
                // decelerate (cubic-bezier 0.4,0,0.2,1) so the arc
                // eases out as it reaches the new level. Reduce-motion
                // snaps straight to the final state — no sweep.
                .animation(
                    reduceMotion
                        ? nil
                        : .timingCurve(0.4, 0, 0.2, 1, duration: 0.6),
                    value: shown
                )
            VStack(spacing: 0) {
                Text(frac.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("LOADED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Load fill progress")
        .accessibilityValue(
            frac.map { "\(Int(($0 * 100).rounded())) percent loaded · \(gal(gallonsFlown)) of \(gal(gallonsTotal)) gallons" }
                ?? "Awaiting fill telemetry · target \(gal(gallonsTotal)) gallons"
        )
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
    /// stay on brand success. An em-dash primary (no live reading)
    /// stays NEUTRAL — a green em-dash would assert "OK" with no
    /// sensor behind it, and the old pressure ratio computed off the
    /// seeded 132/250 Figma pair (dead, Wave-A1 fabrication kill).
    private func tileColor(for tile: LifecycleProductContext.SafetyTile) -> Color {
        guard tile.primary != LiveLoadFacets.dash else {
            return palette.textPrimary
        }
        let l = tile.label.uppercased()
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
                // Honest watchdog copy — never narrates readings it
                // doesn't have. The old line recited the seeded
                // 218 gpm / 132 psi / 0.8 Ω Figma trio as if it were
                // streaming (dead, Wave-A1 fabrication kill).
                Text("I'm on this fill. Rate, pressure, and grounding telemetry will narrate here the moment the bay sensor lane connects — until then I'm walking the \(commodityText == fallbackCommod ? "product" : commodityText) transfer procedure with you.")
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

    /// The canonical NH3 bay procedure ORDER — operational truth, kept.
    /// Per-row completion/timestamps have NO live source (no witness-
    /// checks / bay-ops step feed reaches this screen), so every row is
    /// neutral with an em-dash tail — never the seeded "09:02 … DONE /
    /// 09:10 NOW" Figma ladder (Wave-A1 fabrication kill; the 042
    /// disconnect-ladder pattern). `.done`/`.now` rendering is retained
    /// for the day a real step-progress source lands.
    private let bayCanonicalSteps: [SequenceStep] = [
        .init(id: "chock",    title: "Chock + wheel lock",           timestamp: nil, state: .next),
        .init(id: "ground",   title: "Grounding cable clipped",      timestamp: nil, state: .next),
        .init(id: "arm",      title: "Arm connected · leak-tested",  timestamp: nil, state: .next),
        .init(id: "transfer", title: "Transfer in progress",         timestamp: nil, state: .next),
        .init(id: "blowdown", title: "Line blow-down · cap torque",  timestamp: nil, state: .next),
        .init(id: "release",  title: "Release from gantry",          timestamp: nil, state: .next),
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
        // No per-row completion source → em-dash tail, never a
        // hardcoded "NEXT" queue assertion (042 ladder pattern).
        case .next: return "—"
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
            .accessibilityLabel("Emergency stop - halt transfer")

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
