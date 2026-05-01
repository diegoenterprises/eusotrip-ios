//
//  020_ApproachingDelivery.swift
//  EusoTrip — Lifecycle screen 020 · Approaching Delivery.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `020 Approaching Delivery.png` (Dark + Light). Fires at ~2 mi
//  out from the receiver. Leads with the final turn call-out,
//  geofence arming line, facility card, big "mi to delivery"
//  numeric + ETA/appt/on-time cluster, and a 4-row pre-gate
//  checklist (sealed / BOL / dashcam / lumper — swaps by product).
//
//  Every chip + row dispatches through `LifecycleProductContext`
//  so a dry-van / reefer / flatbed / container / rail / vessel
//  driver sees the right operational copy. Hazmat is a variant,
//  not a default.
//
//  Composition:
//    • Header — back chevron + "APPROACHING DELIVERY" kicker +
//      turn banner "In 0.8 mi · Turn right onto Rockfish Rd" +
//      keep-right subtitle.
//    • Geofence pill — "0.4 MI · ARMING DASH-CAM ON ENTRY".
//    • Facility card — receiver brand + city/state + dock name (e.g.
//      "ACME DC 7271 / SOMECITY, ST · Receiving Dock"); rendered live
//      from `activeLoad.deliveryLocation`.
//    • Hero — big gradient "2.0 mi to delivery" + right-column
//      ETA / appt window / on-time chip.
//    • 4-row product-specific pre-gate checklist with READY/PENDING/NA chips.
//    • Footer CTAs — "I'm at the gate" gradient + "Call receiver" outline.
//    • Bottom nav — preserved verbatim per doctrine.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct ApproachingDelivery: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var completed: Set<String> = []
    @State private var isConfirming: Bool = false

    enum Register { case night, afternoon }
    let register: Register

    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Figma fallback (2026-04-24 frame — receiver-DC variant)
    private let fallbackClock    = "00:08"
    private let fallbackTurnIn   = "0.8"
    private let fallbackTurnWord = "In"
    private let fallbackTurnRoad = "—"
    private let fallbackTurnSub  = "—"
    private let fallbackGeofence = "0.4 MI · ARMING DASH-CAM ON ENTRY"
    private let fallbackFacility = "—"
    private let fallbackFacCity  = "—"
    private let fallbackMiles    = "2.0"
    private let fallbackEta      = "ETA 00:22"
    private let fallbackAppt     = "Appt 23:30 – 23:59 EDT"

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                geofencePill
                facilityCard
                heroBlock
                checklistRows
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task {
            await hydrateLiveTrip()
            seedDefaults()
        }
        .screenTileRoot()
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                    HStack(spacing: 6) {
                        Image(systemName: ctx.product.symbol)
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("APPROACHING DELIVERY")
                            .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    Text("\(fallbackTurnWord) \(fallbackTurnIn) mi · \(fallbackTurnRoad)")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(fallbackTurnSub)
                        .font(EType.mono(.micro)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .fill(LinearGradient.diagonal)
                        .frame(width: 38, height: 38)
                    Image(systemName: "arrow.turn.up.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: Geofence pill

    private var geofencePill: some View {
        HStack(spacing: 6) {
            Circle().fill(LinearGradient.diagonal).frame(width: 6, height: 6)
            Text(fallbackGeofence)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Facility card

    private var facilityCard: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(LinearGradient.diagonal)
                Image(systemName: "building.2.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(activeLoad?.deliveryLocation?.address.isEmpty == false
                     ? activeLoad!.deliveryLocation!.address
                     : fallbackFacility)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(activeLoad?.deliveryLocation?.cityState.isEmpty == false
                     ? "\(activeLoad!.deliveryLocation!.cityState) · Receiving Dock"
                     : fallbackFacCity)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
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

    // MARK: Hero block

    private var heroBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: -4) {
                Text(fallbackMiles)
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("mi to delivery")
                    .font(EType.mono(.caption)).fontWeight(.semibold)
                    .foregroundStyle(palette.textSecondary)
                    .tracking(0.4)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(fallbackEta)
                    .font(EType.mono(.caption)).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
                Text(fallbackAppt)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                Text("ON-TIME")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(Capsule().stroke(Brand.success.opacity(0.5), lineWidth: 1))
            }
        }
    }

    // MARK: Checklist

    private var checklistRows: some View {
        VStack(spacing: 6) {
            ForEach(ctx.deliveryPreCheck) { item in
                let state = state(for: item)
                HStack(spacing: Space.s3) {
                    statusDot(state)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(EType.body.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                        Text(item.subtitle)
                            .font(EType.mono(.micro)).tracking(0.3)
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Text(tail(state))
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(tailColor(state))
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
        }
    }

    private enum RowState { case ready, pending, na, next }

    private func state(for item: LifecycleProductContext.PreHaulItem) -> RowState {
        if completed.contains(item.id) { return .ready }
        // Lumper row is typically N/A for the driver — it's a
        // receiver-side decision.
        if item.id == "lumper" { return .na }
        return .pending
    }

    private func statusDot(_ s: RowState) -> some View {
        Group {
            switch s {
            case .ready:
                ZStack {
                    Circle().fill(Brand.success.opacity(0.2))
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Brand.success)
                }
            case .pending:
                Circle().strokeBorder(palette.borderSoft, lineWidth: 1.5)
            case .na:
                Circle().fill(palette.bgCardSoft)
            case .next:
                Circle().fill(LinearGradient.diagonal.opacity(0.2))
            }
        }
        .frame(width: 22, height: 22)
    }

    private func tail(_ s: RowState) -> String {
        switch s {
        case .ready:   return "READY"
        case .pending: return "PENDING"
        case .na:      return "N/A"
        case .next:    return "NEXT"
        }
    }

    private func tailColor(_ s: RowState) -> Color {
        switch s {
        case .ready:   return Brand.success
        case .pending: return palette.textTertiary
        case .na:      return palette.textTertiary
        case .next:    return Brand.warning
        }
    }

    private func seedDefaults() {
        guard completed.isEmpty else { return }
        // Start with sealed + BOL already confirmed; dashcam auto-
        // arms at the geofence (so it's pending until crossed).
        let list = ctx.deliveryPreCheck
        if list.count >= 2 {
            completed = Set(list.prefix(2).map { $0.id })
        }
    }

    // MARK: Footer CTAs

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            CTAButton(
                title: "I'm at the gate",
                action: { Task { await markAtGate() } },
                isLoading: isConfirming
            )

            Button { /* upstream call-receiver handler */ } label: {
                Text("Call receiver")
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

    // MARK: - Hydration + actions

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }

    private func markAtGate() async {
        isConfirming = true
        defer { isConfirming = false }
        let forwardKeys = ["at_delivery", "receiver", "at_receiver", "delivery"]
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

// MARK: - Wrapper

struct ApproachingDeliveryScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ApproachingDelivery(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_020(),
                      trailing: driverNavTrailing_020(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_020() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_020() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person", isCurrent: false)]
}

#Preview("020 · Approaching Delivery · Dark") {
    ApproachingDeliveryScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("020 · Approaching Delivery · Light") {
    ApproachingDeliveryScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
