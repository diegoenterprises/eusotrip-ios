//
//  015_AtGateAwaitingDock.swift
//  EusoTrip — Lifecycle screen 015 · At Gate · Awaiting Dock.
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `015 At Gate · Awaiting Dock.png` (Dark + Light). Fires after the
//  guard has cleared the driver into the queue but before a bay is
//  called. Leads with a huge gradient queue position so the driver
//  can glance from ten feet and know where they stand, surrounded
//  by the four operational facts that come up on every guard-shack
//  radio check: load id, dwell policy, gate-guard identity, and
//  appt drift.
//
//  Composition (top to bottom):
//    • Header — back chevron + "At the gate" + right-column clock +
//      "Bay 03 · gate 2".
//    • Facility line — "KOCH FERTILIZER · BELLE PLAINE · GUARD
//      CHECK-IN COMPLETE".
//    • Queue position card — big gradient "N" + "of M trucks
//      waiting" + "Est. wait Xh XXm · advancing avg every N min" +
//      dot row showing each truck in the queue.
//    • 2×2 metadata grid — LOAD ID / DWELL POLICY / GATE GUARD /
//      APPT DRIFT.
//    • ESANG · IDLE-WATCH card.
//    • Footer CTAs — "Log dwell" outline + "Mark ready" gradient.
//    • Bottom nav — preserved verbatim per doctrine.
//
//  Data wiring:
//    • `TripLifecycleStore.hydrateActiveLoad()` → `loads.getById`
//      for the real load id + pickup location + hazmat class.
//    • Queue position is a server-pushed field; until
//      `loadLifecycle.queuePosition(loadId:)` ships we read from the
//      Figma reference (Position 2 of 4) so the frame paints
//      identically in preview + cold start.
//    • "Mark ready" fires the forward transition from the lifecycle
//      store — same selection rule as 014.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct AtGateAwaitingDock: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?
    @State private var isMarkingReady: Bool = false

    enum Register { case night, morning }
    let register: Register

    init(register: Register = .night) { self.register = register }

    /// Product + vertical dispatch. Queue position + metadata grid
    /// + ESANG idle-watch line all adapt to the active load's
    /// vertical / product instead of defaulting to hazmat copy.
    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Figma-verbatim fallback (used only while the backend
    // hasn't hydrated a real load — matches the 2026-04-24 frame).
    private let fallbackFacility = "—"
    private let fallbackLoadID   = "—"
    private let fallbackCommod   = "UN1005 · NH3 · tanker"
    private let fallbackGuard    = "—"
    private let fallbackBadge    = "—"
    private let fallbackApptDrift = "-6 min"
    private let fallbackApptSched = "vs. scheduled 09:00 CDT"
    private let fallbackBayGate   = "Bay 03 · gate 2"
    private let fallbackClock     = "08:32 CDT"
    private let fallbackDwellFree = "2h free"
    private let fallbackDwellPen  = "Detention after 2h"
    private let fallbackArmedAt   = "08:18 CDT"

    // Queue state — bound to live server pushes once the
    // `loadLifecycle.queuePosition` endpoint ships. Figma reference
    // anchors preview + cold start.
    private let queuePosition   = 2
    private let queueTotal      = 4
    private let estWaitMinutes  = 14
    private let avgMovementMin  = 7

    // MARK: - Derived UI strings

    private var facilityLine: String {
        if let loc = activeLoad?.pickupLocation, !loc.cityState.isEmpty {
            let brand = loc.address.isEmpty ? loc.cityState : loc.address
            return "\(brand.uppercased()) · \(loc.cityState.uppercased())"
        }
        return fallbackFacility
    }

    private var loadIDText: String {
        if let full = activeLoad?.loadNumber, !full.isEmpty {
            return full
        }
        return fallbackLoadID
    }

    private var commodityText: String {
        let un = activeLoad?.unNumber ?? "UN1005"
        let commod = activeLoad?.commodityName ?? "NH3 · tanker"
        return "\(un) · \(commod)"
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                facilityStrip
                queueCard
                metadataGrid
                esangIdleWatchCard
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
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: ctx.product.symbol)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(ctx.headerKicker)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("At the \(ctx.vertical.gateWord)")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(fallbackClock)
                    .font(EType.mono(.caption)).fontWeight(.semibold)
                    .foregroundStyle(palette.textPrimary)
                // Swap the static "Bay 03 · gate 2" for a
                // vertical-correct noun pair via the shared
                // context (bay for truck, spur for rail,
                // berth for vessel).
                Text("\(ctx.vertical.bayWord.capitalized) 03 · \(ctx.vertical.gateWord) 2")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Facility strip

    private var facilityStrip: some View {
        Text("\(facilityLine) · GUARD CHECK-IN COMPLETE")
            .font(EType.mono(.micro)).tracking(0.5)
            .foregroundStyle(palette.textSecondary)
            .lineLimit(2)
    }

    // MARK: Queue position hero card

    private var queueCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("QUEUE POSITION")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(queuePosition)")
                    .font(.system(size: 86, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 0) {
                    Text("of \(queueTotal) trucks")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("waiting")
                        .font(EType.body)
                        .foregroundStyle(palette.textSecondary)
                }
            }

            // Wait line
            HStack(spacing: 6) {
                Text("Est. wait \(formattedWait) · advancing avg every \(avgMovementMin) min")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
            }

            // Dot row
            HStack(spacing: 8) {
                ForEach(1...queueTotal, id: \.self) { idx in
                    queueDot(idx)
                }
                Spacer(minLength: 0)
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

    private func queueDot(_ idx: Int) -> some View {
        let isCurrent = idx == queuePosition
        let isPassed  = idx < queuePosition
        return Group {
            if isCurrent {
                Circle().fill(LinearGradient.diagonal)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(palette.bgPage, lineWidth: 2))
            } else if isPassed {
                Circle().fill(palette.textTertiary.opacity(0.5))
                    .frame(width: 8, height: 8)
            } else {
                Circle().strokeBorder(palette.borderSoft, lineWidth: 1)
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var formattedWait: String {
        let h = estWaitMinutes / 60
        let m = estWaitMinutes % 60
        return "\(h)h \(String(format: "%02d", m))m"
    }

    // MARK: 2×2 metadata grid

    private var metadataGrid: some View {
        VStack(spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                metaCard(label: "LOAD ID", primary: loadIDText, secondary: commodityText)
                metaCard(label: "DWELL POLICY", primary: fallbackDwellFree, secondary: fallbackDwellPen)
            }
            HStack(spacing: Space.s2) {
                metaCard(label: "GATE GUARD", primary: fallbackGuard, secondary: fallbackBadge)
                metaCard(label: "APPT DRIFT", primary: fallbackApptDrift, secondary: fallbackApptSched, primaryColor: Brand.warning)
            }
        }
    }

    private func metaCard(
        label: String,
        primary: String,
        secondary: String,
        primaryColor: Color? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(primary)
                .font(EType.bodyStrong)
                .foregroundStyle(primaryColor ?? palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(secondary)
                .font(EType.mono(.micro)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
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

    // MARK: ESANG idle-watch

    private var esangIdleWatchCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 40, height: 40)
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("ESANG · IDLE-WATCH")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Engine off, parking brake set. I'll listen for your call-forward and wake you if the queue moves. Dwell timer armed at \(fallbackArmedAt).")
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

    // MARK: Footer CTAs

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            Button { /* future: logDwell mutation */ } label: {
                Text("Log dwell")
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
            .accessibilityLabel("Log dwell time")

            CTAButton(
                title: "Mark ready",
                action: { Task { await markReady() } },
                isLoading: isMarkingReady
            )
            .accessibilityLabel("Mark ready to advance to bay")
        }
    }

    // MARK: Live hydration + actions

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
        // Phase 10 closure: round-trip the appointment status so
        // the shipper / dispatcher web surfaces see the driver
        // checked-in at the gate the moment 015 appears. Best-
        // effort — server tolerates duplicate same-status updates;
        // failure is non-blocking on the lifecycle screen.
        await syncAppointmentStatus("checked_in")
    }

    /// Helper that looks up the appointment for the active load and
    /// flips it to the supplied status. Driver lifecycle screens
    /// 014 / 015 / 016 / 024 each call this with a different status
    /// to keep `appointments.status` in sync with the trip phase
    /// without a hard dependency on the lifecycle store knowing
    /// about appointments. Phase 10 closure.
    private func syncAppointmentStatus(_ status: String) async {
        guard !lifecycle.loadId.isEmpty else { return }
        do {
            if let appt = try await EusoTripAPI.shared.appointments
                .getByLoad(loadId: lifecycle.loadId) {
                _ = try? await EusoTripAPI.shared.appointments
                    .updateStatus(id: appt.id, status: status)
            }
        } catch {
            // Non-blocking — lifecycle screen continues to render
            // even when the appointment row isn't on file yet.
        }
    }

    private func markReady() async {
        isMarkingReady = true
        defer { isMarkingReady = false }
        let forwardKeys: [String] = ["loading", "bay", "at_bay", "pickup"]
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

struct AtGateAwaitingDockScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            AtGateAwaitingDock(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_015(),
                      trailing: driverNavTrailing_015(),
                      orbState: .idle)
        }
    }
}

private func driverNavLeading_015() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: true)]
}
private func driverNavTrailing_015() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person", isCurrent: false)]
}

// MARK: - Previews

#Preview("015 · Awaiting Dock · Dark") {
    AtGateAwaitingDockScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("015 · Awaiting Dock · Light") {
    AtGateAwaitingDockScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
