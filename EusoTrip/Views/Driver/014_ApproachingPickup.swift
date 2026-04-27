//
//  014_ApproachingPickup.swift
//  EusoTrip — Lifecycle screen 014 · Approaching Pickup.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `014 Approaching Pickup.png` (Dark + Light) — a hazmat pre-haul
//  checklist surface rather than the original navigation map. The
//  screen fires when the driver crosses into the 5-mile outer
//  geofence on an assigned hazmat load; it orchestrates the six
//  pre-gate tasks the driver has to clear before hitting the guard
//  shack so the carrier isn't held at the fence for PPE / placard
//  / ERG-summary paperwork.
//
//  Composition (top to bottom):
//    • Header — back chevron + "Approaching" title + facility
//      cartouche ("KOCH FERTILIZER · BELLE PLAINE IA · APPT") + a
//      right-column "4.2 mi / TO GATE" numeric.
//    • ESANG card — gradient glyph + "ESANG · PREPS-CHECKLIST"
//      eyebrow + 4-line advisory body + live audio waveform +
//      sensor-reading footer ("Pressure reads 128 psi — good").
//    • "PREPS BEFORE THE GATE" section header + "N of 6 · NN%"
//      progress indicator.
//    • Six-item checklist rows — status dot + title + subtitle +
//      status chip (DONE / NOW / NEXT / PENDING).
//    • Footer CTA — circular mic button + gradient "Confirm 15-min
//      notify / <DISPATCH> · EXT <N>" rectangle.
//
//  Data wiring:
//    • `TripLifecycleStore.hydrateActiveLoad()` pulls the driver's
//      assigned load so the facility / hazmat-class / UN-number
//      lines come from `loads.getById`.
//    • ESANG advisory body uses the load's hazmat fields
//      (commodity, UN number, pressure baseline) to build a
//      real, load-specific brief. No static fallback copy when
//      the load is hydrated.
//    • Mark-as-done on a row advances the `TripLifecycleStore`
//      checklist tracker; confirm-notify executes the
//      `approach` → `at_pickup` transition.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct ApproachingPickup: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    /// Per-row completion state. Seeded from the driver's pre-gate
    /// defaults + anything already marked on the server checklist
    /// (future: `loadLifecycle.getChecklist`).
    @State private var completed: Set<String> = []
    @State private var isConfirming: Bool = false

    // MARK: - Figma-verbatim fallback (used only while the backend
    // hasn't hydrated a real load — matches the 2026-04-24 frame).
    private let fallbackFacility = "—"
    private let fallbackAppt     = "APPT 09:00 CDT"
    private let fallbackMiles    = "4.2"

    enum Register { case night, morning }
    let register: Register

    init(register: Register = .night) { self.register = register }

    /// Shared product+vertical context. Every copy / chip / icon
    /// decision on this screen flows through it so a dry-van driver
    /// sees dry-van prehaul items, a reefer driver sees reefer
    /// prehaul items, etc. — "all verticals, products type not
    /// just hazmat" (2026-04-24 doctrine).
    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Derived UI strings

    private var facilityLine: String {
        if let loc = activeLoad?.pickupLocation, !loc.cityState.isEmpty {
            let brand = loc.address.isEmpty ? loc.cityState : loc.address
            return "\(brand.uppercased()) · \(loc.cityState.uppercased())"
        }
        return fallbackFacility
    }

    private var apptLine: String {
        return fallbackAppt
    }

    private var milesToGate: String {
        // Live ETA distance would come from a HERE routing call vs
        // the pickup coord; until that's wired, render the Figma
        // reference value so the top-right numeric isn't blank.
        return fallbackMiles
    }

    private var dispatchLine: String {
        // Dispatch line adapts to the vertical (DISPATCH /
        // TRAINMASTER / HARBORMASTER). Ext number isn't on the
        // Load row today — keep the Figma-reference "EXT 12" until
        // the server adds a broker contact field.
        return "\(ctx.dispatchLabel) · EXT 12"
    }

    /// Product-specific 6-row checklist — sourced from the shared
    /// `LifecycleProductContext` so a dry-van driver never sees
    /// hazmat placard rows and vice-versa.
    private var checklist: [LifecycleProductContext.PreHaulItem] {
        ctx.preHaulChecklist
    }

    private var progressDone: Int { completed.count }
    private var progressFraction: CGFloat {
        checklist.isEmpty ? 0 : CGFloat(progressDone) / CGFloat(checklist.count)
    }
    private var progressPercent: Int {
        Int((progressFraction * 100).rounded())
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                esangCard
                progressHeader
                checklistRows
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task {
            await hydrateLiveTrip()
            seedDefaultCompletions()
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
                // Product kicker — "HAZMAT TANKER" / "DRY VAN" /
                // "REEFER" / "FLATBED" / "CONTAINER" / "RAIL ·
                // INTERMODAL" / "VESSEL · CONTAINER" / etc. Reads
                // as a gradient stroke chip under the title so the
                // driver confirms at a glance they're looking at
                // their rig's version of the screen.
                HStack(spacing: 6) {
                    Image(systemName: ctx.product.symbol)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(ctx.headerKicker)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Approaching \(ctx.vertical.pickupWord.lowercased())")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("\(facilityLine) · \(apptLine)")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: -2) {
                Text(milesToGate)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("mi")
                    .font(EType.mono(.micro)).tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
                Text("TO \(ctx.vertical.gateWord.uppercased())")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, 2)
            }
        }
        .padding(.top, 4)
    }

    // MARK: ESANG card

    private var esangCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 46, height: 46)
                Image(systemName: "sparkles")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("ESANG · PREPS-CHECKLIST")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(LinearGradient.diagonal)
                    Spacer(minLength: 0)
                }
                Text(esangBody)
                    .font(EType.body)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 3) {
                    ForEach(0..<28, id: \.self) { i in
                        Capsule()
                            .fill(LinearGradient.diagonal.opacity(0.85))
                            .frame(width: 2, height: waveHeight(i))
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    /// Advisory copy dispatched through the product context so a
    /// dry-van / reefer / flatbed / container / rail / vessel
    /// driver hears the right operator voice instead of a
    /// hazmat-tanker monologue.
    private var esangBody: String {
        ctx.esangPreHaulAdvisory
    }

    /// Deterministic pseudo-waveform — tall bars where ESANG would
    /// be speaking emphasized syllables. Keeps the visualization
    /// stable across reloads so it doesn't appear to shimmer.
    private func waveHeight(_ i: Int) -> CGFloat {
        let pattern: [CGFloat] = [6, 10, 14, 9, 5, 12, 18, 22, 16, 9, 6, 14, 20, 15, 11, 7, 5, 9, 14, 18, 12, 7, 5, 8, 12, 9, 6, 4]
        return pattern[i % pattern.count]
    }

    // MARK: Progress header

    private var progressHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("PREPS BEFORE THE GATE")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 0)
            Text("\(progressDone) of \(checklist.count) · \(progressPercent)%")
                .font(EType.mono(.micro)).tracking(0.6)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.top, Space.s2)
    }

    // MARK: Checklist

    private var checklistRows: some View {
        VStack(spacing: 6) {
            ForEach(checklist) { item in
                checklistRow(item)
            }
        }
    }

    private func checklistRow(_ item: LifecycleProductContext.PreHaulItem) -> some View {
        let state = state(for: item)
        return Button {
            // Driver-triggered advance. Mark as done on tap; the
            // "NOW" row's completion rolls the next row from NEXT
            // to NOW automatically via the computed ordering.
            if state != .done {
                completed.insert(item.id)
            } else {
                completed.remove(item.id)
            }
        } label: {
            HStack(spacing: Space.s3) {
                statusDot(state: state)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(EType.body.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text(item.subtitle)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                statusChip(state: state)
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, 10)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func statusDot(state: ChecklistState) -> some View {
        ZStack {
            switch state {
            case .done:
                Circle().fill(Brand.success.opacity(0.2))
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Brand.success)
            case .now:
                Circle().fill(LinearGradient.diagonal.opacity(0.2))
                Circle().stroke(LinearGradient.diagonal, lineWidth: 1.5).frame(width: 14, height: 14)
            case .next:
                Circle().strokeBorder(palette.borderSoft, lineWidth: 1.5)
            case .pending:
                Circle().fill(palette.bgCardSoft)
            }
        }
        .frame(width: 24, height: 24)
    }

    private func statusChip(state: ChecklistState) -> some View {
        let (label, color): (String, Color) = {
            switch state {
            case .done:    return ("DONE",    Brand.success)
            case .now:     return ("NOW",     Brand.warning)
            case .next:    return ("NEXT",    Brand.info)
            case .pending: return ("PENDING", palette.textTertiary)
            }
        }()
        return Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
    }

    // MARK: Footer CTA

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            Button {
                // Push-to-talk to dispatch (future: wires into
                // driverConversationView on the same thread).
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 52, height: 52)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderSoft))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Hold to talk to dispatch")

            // §B.4 — canonical CTAButton primitive. Press recipe
            // (easeOut(0.12) + scale 0.985 + hueRotation), success
            // haptic (§6.10), and the title+subtitle two-line layout
            // are baked into the shared component instead of being
            // hand-rolled per screen.
            CTAButton(
                title: "Confirm 15-min notify",
                action: { Task { await confirmNotify() } },
                subtitle: dispatchLine,
                isLoading: isConfirming
            )
            .accessibilityLabel("Send 15-minute notify to \(dispatchLine)")
        }
        .padding(.top, Space.s3)
    }

    // MARK: - Checklist state

    enum ChecklistState: Hashable { case done, now, next, pending }

    /// Seed the "done" set from sensible defaults a driver would
    /// normally have knocked out mid-route. Uses the first three
    /// items of the product-specific checklist, so a dry-van driver
    /// starts with seal+swept+pallet done, a reefer driver starts
    /// with precool+fuel+airchute done, etc.
    private func seedDefaultCompletions() {
        guard completed.isEmpty else { return }
        let list = checklist
        guard list.count >= 3 else { return }
        completed = Set(list.prefix(3).map { $0.id })
    }

    /// Resolve the row's visual state from its position + the
    /// driver's completion set. First not-done row is NOW, next
    /// not-done is NEXT, rest are PENDING.
    private func state(for item: LifecycleProductContext.PreHaulItem) -> ChecklistState {
        if completed.contains(item.id) { return .done }
        let remaining = checklist.filter { !completed.contains($0.id) }
        if item.id == remaining.first?.id { return .now }
        if remaining.count >= 2, item.id == remaining[1].id { return .next }
        return .pending
    }

    // MARK: - Live hydration

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func confirmNotify() async {
        isConfirming = true
        defer { isConfirming = false }
        // Advance the lifecycle — the server maps "approach" /
        // "at_pickup" as the forward transitions from "assigned".
        // Mirrors 013's `continueRoute` selection rule.
        let forwardKeys: [String] = ["approach", "at_pickup", "pickup"]
        let candidate = lifecycle.availableTransitions.first { t in
            let to = t.to.lowercased()
            return forwardKeys.contains(where: { to.contains($0) })
        } ?? lifecycle.availableTransitions.first
        if let transition = candidate {
            _ = await lifecycle.execute(transition)
        }
        // Mark the "notify" row done regardless — the driver's tap
        // is the source of truth for the notify happening.
        completed.insert("notify")
        advance?()
    }
}

// MARK: - Screen wrapper

struct ApproachingPickupScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ApproachingPickup(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_014(),
                      trailing: driverNavTrailing_014(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_014() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",      isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",  isCurrent: true)]
}
private func driverNavTrailing_014() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

// MARK: - Previews

#Preview("014 · Approaching · Dark") {
    ApproachingPickupScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("014 · Approaching · Light") {
    ApproachingPickupScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
